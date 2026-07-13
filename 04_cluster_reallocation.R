# ==============================================================================
# Zero-building cluster reallocation
#
# Functions:
#   diagnose_zero_building_clusters()
#   reallocate_zero_building_clusters()
#
# Purpose:
#   A selected Stage-1 PPS hexagon with zero eligible Google Open Buildings
#   footprints produces no households and cannot be visited by a field team.
#   These functions identify such clusters and substitute a different
#   hexagon from the SAME (pop_type, adm2_pcode) stratum, drawn with the
#   same PPS-by-population-size mechanism as the original Stage 1 draw, so
#   the substitute is methodologically identical rather than an ad hoc fix.
#   Clusters that have SOME buildings but fewer than the target
#   ("understaffed") are out of scope - only clusters with NO eligible
#   buildings at all are reallocated.
#
# ==============================================================================


#' Identify zero-building clusters and check reallocation feasibility
#'
#' Diagnoses, without running any GDAL queries, which selected Stage-1
#' clusters produced no households, splits them into ones that CAN be
#' reallocated (in a PPS stratum, where unselected hexagons remain) versus
#' ones that CANNOT (in a certainty stratum, where every hexagon in the
#' Admin-2 is already enumerated as its own cluster - there is nothing left
#' to substitute), and reports each affected stratum's remaining candidate
#' pool size so an unexpectedly small pool can be spotted before spending
#' time on live building queries.
#'
#' @param clusters sf polygon object of the SELECTED Stage-1 sampling
#'   clusters (e.g. \code{bind_rows(host_clusters, idp_clusters)}).
#' @param host_sampling,idp_sampling Lists returned by
#'   \code{build_sampling_plan()} for the host and IDP hex grids - used for
#'   \code{sampling_frame} (every hexagon in the universe, not just selected
#'   ones, carrying \code{MOS}/\code{total_MOS}/\code{clusters}/
#'   \code{psu_probability}).
#' @param stage2_households sf object returned by
#'   \code{select_stage2_households()}.
#' @param m Integer. Primary households per cluster (must match the value
#'   used for \code{select_stage2_households()}).
#'
#' @return List with \code{zero_building_clusters} (all of them, with
#'   \code{certainty_stratum} flag), \code{pps_targets} (the reallocatable
#'   subset), \code{certainty_unresolvable} (cannot be reallocated - reported,
#'   not silently dropped), and \code{pool_sizes} (candidate pool size per
#'   affected PPS stratum).
diagnose_zero_building_clusters <- function(
    clusters,
    host_sampling,
    idp_sampling,
    stage2_households,
    m = 6
) {

  clusters_merged <- merge_repeated_psu_draws(clusters, m)

  zero_building_clusters <-
    clusters_merged %>%
    sf::st_drop_geometry() %>%
    dplyr::filter(
      !cluster_id %in% stage2_households$cluster_id
    ) %>%
    dplyr::select(
      cluster_id,
      pop_type,
      adm2_pcode,
      uuid_hex_pop,
      target_households,
      selection_count,
      certainty_stratum,
      selection_type
    )

  certainty_unresolvable <-
    zero_building_clusters %>%
    dplyr::filter(certainty_stratum)

  pps_targets <-
    zero_building_clusters %>%
    dplyr::filter(!certainty_stratum)

  message(
    nrow(zero_building_clusters), " zero-building cluster(s) total: ",
    nrow(pps_targets), " in a PPS stratum (reallocatable), ",
    nrow(certainty_unresolvable), " in a certainty stratum (NOT reallocatable - ",
    "the whole Admin-2 is already fully enumerated)."
  )

  full_sampling_frame <-
    dplyr::bind_rows(
      host_sampling$sampling_frame,
      idp_sampling$sampling_frame
    ) %>%
    sf::st_drop_geometry()

  already_used <- clusters_merged$uuid_hex_pop

  pool_sizes <-
    pps_targets %>%
    dplyr::distinct(pop_type, adm2_pcode) %>%
    dplyr::mutate(
      n_needed = purrr::map2_int(
        pop_type, adm2_pcode,
        \(pt, a2) sum(pps_targets$pop_type == pt & pps_targets$adm2_pcode == a2)
      ),
      pool_size = purrr::map2_int(
        pop_type, adm2_pcode,
        \(pt, a2) {
          full_sampling_frame %>%
            dplyr::filter(
              pop_type == pt,
              adm2_pcode == a2,
              MOS > 0,
              !uuid_hex_pop %in% already_used
            ) %>%
            nrow()
        }
      )
    )

  if(any(pool_sizes$pool_size < pool_sizes$n_needed)) {

    tight <- pool_sizes %>% dplyr::filter(pool_size < n_needed)

    warning(
      nrow(tight), " stratum/strata have a smaller candidate pool than the ",
      "number of zero-building clusters needing reallocation - some will ",
      "likely remain unresolved: ",
      paste(paste0(tight$pop_type, "_", tight$adm2_pcode, " (need ", tight$n_needed,
                    ", pool ", tight$pool_size, ")"), collapse = "; ")
    )

  }

  list(
    zero_building_clusters = zero_building_clusters,
    pps_targets = pps_targets,
    certainty_unresolvable = certainty_unresolvable,
    pool_sizes = pool_sizes
  )

}


#' Reallocate zero-building clusters to a different hexagon in-stratum
#'
#' For every selected cluster with zero eligible buildings (see
#' \code{diagnose_zero_building_clusters()}), draws a replacement hexagon
#' from the same (\code{pop_type}, \code{adm2_pcode}) stratum's remaining
#' unselected hexagons, weighted by population size exactly like the
#' original Stage 1 PPS draw (same \code{psu_probability} formula, just
#' evaluated at the replacement hexagon's own \code{MOS}), checks it for
#' eligible buildings, and - if empty - tries the next weighted draw from
#' the shrinking pool. Runs in at most two rounds per stratum: an initial
#' batch sized at \code{candidate_multiplier} times what's needed, then (only
#' for strata still short) everything remaining in that stratum's pool.
#' Certainty-stratum zero-building clusters have no in-stratum pool to draw
#' from and are reported as unresolved, not silently dropped.
#'
#' @param clusters sf polygon object of the SELECTED Stage-1 sampling
#'   clusters (e.g. \code{bind_rows(host_clusters, idp_clusters)}).
#' @param host_sampling,idp_sampling Lists returned by
#'   \code{build_sampling_plan()}.
#' @param stage2_households sf object returned by
#'   \code{select_stage2_households()}.
#' @param building_data_dir Character. Directory containing the Google Open
#'   Buildings File Geodatabases (passed to \code{load_building_footprints()}).
#' @param wards,admin3 sf polygon objects, passed through to
#'   \code{finalize_households()}.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param cache_directory Character. Directory for intermediate/cached files
#'   (kept separate from the main Stage 2 building cache).
#' @param m Integer. Primary households per cluster. Default 6.
#' @param reserve_n Integer. Maximum reserve households per cluster. Default
#'   equal to \code{m}.
#' @param seed Integer or NULL. Random seed for the replacement draw,
#'   independent of the Stage 1 and Stage 2 seeds. Default 4321.
#' @param candidate_multiplier Numeric. Round-1 candidate batch size per
#'   stratum, as a multiple of that stratum's number of zero-building
#'   clusters. Default 5.
#' @param rebuild Logical. If TRUE, rebuild cached building queries.
#'
#' @return List:
#' \describe{
#'   \item{clusters_final}{sf object, one row per FINAL cluster - the
#'     original merged cluster table with resolved zero-building clusters'
#'     hexagon swapped for their replacement (geometry, \code{uuid_hex_pop},
#'     \code{uuid_hex}, \code{uuid}, \code{psu_probability},
#'     \code{reallocated}, \code{original_uuid_hex_pop} all updated).}
#'   \item{new_households}{sf object of finalized household rows for the
#'     reallocated clusters only (same schema as
#'     \code{select_stage2_households()}'s output) - bind onto the existing
#'     Stage 2 output.}
#'   \item{unresolved}{Data frame of \code{cluster_id}s that could not be
#'     reallocated, with a \code{reason} column
#'     ("certainty_stratum_full_enumeration" or "candidate_pool_exhausted").}
#' }
#'
#' @export
reallocate_zero_building_clusters <- function(
    clusters,
    host_sampling,
    idp_sampling,
    stage2_households,
    building_data_dir,
    wards,
    admin3,
    mycrs,
    cache_directory,
    m = 6,
    reserve_n = m,
    seed = 4321,
    candidate_multiplier = 5,
    rebuild = FALSE
) {

  stopifnot(
    inherits(clusters, "sf"),
    inherits(stage2_households, "sf")
  )

  dir.create(cache_directory, recursive = TRUE, showWarnings = FALSE)

  if(!is.null(seed)) set.seed(seed)

  clusters_merged <- merge_repeated_psu_draws(clusters, m)

  diag <- diagnose_zero_building_clusters(
    clusters = clusters,
    host_sampling = host_sampling,
    idp_sampling = idp_sampling,
    stage2_households = stage2_households,
    m = m
  )

  unresolved <-
    diag$certainty_unresolvable %>%
    dplyr::mutate(reason = "certainty_stratum_full_enumeration") %>%
    dplyr::select(cluster_id, pop_type, adm2_pcode, reason)

  pps_targets <- diag$pps_targets

  if(nrow(pps_targets) == 0) {

    message("No PPS-stratum zero-building clusters to reallocate.")

    return(
      list(
        clusters_final = clusters_merged,
        new_households = stage2_households[0, ],
        unresolved = unresolved
      )
    )

  }

  full_sampling_frame <-
    dplyr::bind_rows(
      host_sampling$sampling_frame,
      idp_sampling$sampling_frame
    )

  already_used <- clusters_merged$uuid_hex_pop

  strata_keys <-
    pps_targets %>%
    dplyr::distinct(pop_type, adm2_pcode)

  # ---------------------------------------------------------------------------
  # Build one full weighted-random ranking (PPS-by-MOS, without replacement)
  # of each affected stratum's unselected candidate hexagons. Slices taken
  # off the front of this ranking in successive rounds below preserve proper
  # PPS draw order - this is not a fresh independent draw each round.
  # ---------------------------------------------------------------------------

  stratum_pools <- purrr::pmap(strata_keys, function(pop_type, adm2_pcode) {

    pool <-
      full_sampling_frame %>%
      dplyr::filter(
        pop_type == !!pop_type,
        adm2_pcode == !!adm2_pcode,
        MOS > 0,
        !uuid_hex_pop %in% already_used
      )

    if(nrow(pool) == 0) {
      return(pool)
    }

    pool[sample.int(nrow(pool), size = nrow(pool), prob = pool$MOS), ]

  })

  names(stratum_pools) <- paste(strata_keys$pop_type, strata_keys$adm2_pcode, sep = "_")

  tried_pointer <- setNames(rep(0L, length(stratum_pools)), names(stratum_pools))

  remaining_slots <- pps_targets

  assigned <- list()   # cluster_id -> replacement sampling_frame row (1-row sf)

  max_rounds <- 2

  for(round_i in seq_len(max_rounds)) {

    if(nrow(remaining_slots) == 0) break

    needed_by_stratum <-
      remaining_slots %>%
      dplyr::count(pop_type, adm2_pcode, name = "n_still_needed") %>%
      dplyr::mutate(strata_key = paste(pop_type, adm2_pcode, sep = "_"))

    round_batches <- purrr::pmap(needed_by_stratum, function(pop_type, adm2_pcode, n_still_needed, strata_key) {

      pool <- stratum_pools[[strata_key]]
      pool_n <- nrow(pool)
      start <- tried_pointer[[strata_key]] + 1L

      if(start > pool_n) {
        return(pool[0, ])
      }

      # Round 1: a generous multiple of what's needed. Round 2 (last resort,
      # only for strata still short after round 1): everything left in the
      # pool, since there's no round 3 to save any back for.
      batch_size <- if(round_i == 1) {
        min(candidate_multiplier * n_still_needed, pool_n - start + 1L)
      } else {
        pool_n - start + 1L
      }

      end <- start + batch_size - 1L

      tried_pointer[[strata_key]] <<- end

      pool[start:end, ]

    })

    candidate_batch <- dplyr::bind_rows(round_batches)

    if(nrow(candidate_batch) == 0) {

      message("Round ", round_i, ": no untried candidates remain in any short stratum.")
      break

    }

    message(
      "Round ", round_i, ": checking ", nrow(candidate_batch),
      " candidate hexagon(s) across ", length(round_batches), " stratum/strata for eligible buildings."
    )

    round_cache_dir <- file.path(cache_directory, paste0("round_", round_i, "_buildings"))

    round_building_files <- load_building_footprints(
      gdb_directory = building_data_dir,
      accessible_area = candidate_batch,
      mycrs = mycrs,
      cache_directory = round_cache_dir,
      rebuild = rebuild
    )

    # Lightweight per-hexagon building counts only (never the full building
    # geometries for the whole candidate batch at once) - the same
    # discipline as the rest of this pipeline, even though this batch is
    # small enough that it would likely be fine either way.
    hex_building_counts <-
      purrr::map(round_building_files, function(bf) {
        readRDS(bf) %>%
          sf::st_drop_geometry() %>%
          dplyr::count(uuid_hex_pop, name = "n_buildings")
      }) %>%
      dplyr::bind_rows() %>%
      dplyr::group_by(uuid_hex_pop) %>%
      dplyr::summarise(n_buildings = sum(n_buildings), .groups = "drop")

    eligible_hexes <-
      hex_building_counts %>%
      dplyr::filter(n_buildings > 0) %>%
      dplyr::pull(uuid_hex_pop)

    # Walk each stratum's round batch in PPS-rank order, assigning the first
    # eligible hexagon found to the next still-unresolved cluster_id in that
    # stratum. Each candidate hexagon appears at most once across all of
    # this run (sample without replacement upstream), so no hexagon can be
    # assigned twice.
    for(strata_key_i in unique(paste(candidate_batch$pop_type, candidate_batch$adm2_pcode, sep = "_"))) {

      batch_i <- candidate_batch %>%
        dplyr::filter(paste(pop_type, adm2_pcode, sep = "_") == strata_key_i) %>%
        dplyr::filter(uuid_hex_pop %in% eligible_hexes)

      slots_i <- remaining_slots %>%
        dplyr::filter(paste(pop_type, adm2_pcode, sep = "_") == strata_key_i)

      n_fill <- min(nrow(batch_i), nrow(slots_i))

      if(n_fill == 0) next

      for(k in seq_len(n_fill)) {

        assigned[[slots_i$cluster_id[k]]] <- batch_i[k, ]

      }

      remaining_slots <- remaining_slots %>%
        dplyr::filter(!(cluster_id %in% slots_i$cluster_id[seq_len(n_fill)]))

    }

    message(
      "Round ", round_i, ": ", length(assigned), " of ", nrow(pps_targets),
      " zero-building cluster(s) resolved so far."
    )

  }

  if(nrow(remaining_slots) > 0) {

    warning(
      nrow(remaining_slots), " zero-building cluster(s) could not be reallocated - ",
      "candidate pool exhausted in their stratum: ",
      paste(remaining_slots$cluster_id, collapse = ", ")
    )

    unresolved <-
      dplyr::bind_rows(
        unresolved,
        remaining_slots %>%
          dplyr::mutate(reason = "candidate_pool_exhausted") %>%
          dplyr::select(cluster_id, pop_type, adm2_pcode, reason)
      )

  }

  if(length(assigned) == 0) {

    message("No zero-building clusters were successfully reallocated.")

    return(
      list(
        clusters_final = clusters_merged,
        new_households = stage2_households[0, ],
        unresolved = unresolved
      )
    )

  }

  # ---------------------------------------------------------------------------
  # Build clusters_merged-equivalent rows for the resolved replacements: the
  # replacement hexagon's own Stage 1 attributes (geometry, uuid_hex_pop,
  # uuid_hex, uuid, MOS, psu_probability - all hexagon-specific), combined
  # with the ORIGINAL cluster's identity (cluster_id, target_households,
  # selection_count) so the "slot" being filled stays the same.
  # ---------------------------------------------------------------------------

  replacement_rows <- purrr::imap(assigned, function(replacement_hex, cluster_id_i) {

    original <- pps_targets %>% dplyr::filter(cluster_id == cluster_id_i)

    replacement_hex %>%
      dplyr::mutate(
        cluster_id = cluster_id_i,
        target_households = original$target_households[1],
        selection_count = original$selection_count[1],
        strata_id = paste(pop_type, adm2_pcode, sep = "_"),
        reallocated = TRUE,
        original_uuid_hex_pop = original$uuid_hex_pop[1],
        # Still building-footprint-based (just a different hexagon) - same
        # defaults merge_repeated_psu_draws() sets for every host cluster.
        # replacement_hex comes straight from host_sampling$sampling_frame,
        # which never went through that function, so these need setting
        # here explicitly for finalize_households()'s shared schema.
        location_source = "building_footprint",
        households_in_cluster_source = "building_footprint_count",
        site_radius_m = NA_real_,
        iom_site_id = NA_character_,
        iom_site_name = NA_character_,
        iom_site_type = NA_character_,
        iom_site_ward = NA_character_,
        n_other_sites_in_hex = NA_integer_
      )

  }) %>%
    dplyr::bind_rows() %>%
    sf::st_as_sf()

  message(
    nrow(replacement_rows), " replacement hexagon(s) assigned. Drawing households from their building pools."
  )

  # ---------------------------------------------------------------------------
  # Fetch each replacement hexagon's full building pool (not just counts)
  # and draw households, reusing the same draw_cluster() logic as the main
  # Stage 2 run. Replacement hexagons are spread across whichever round(s)
  # resolved them, so their buildings live across the corresponding
  # round_building_files sets - re-fetch fresh here (small scope: at most a
  # few hundred hexagons) rather than threading per-round file lists through
  # the assignment loop above.
  # ---------------------------------------------------------------------------

  final_building_files <- load_building_footprints(
    gdb_directory = building_data_dir,
    accessible_area = replacement_rows,
    mycrs = mycrs,
    cache_directory = file.path(cache_directory, "final_buildings"),
    rebuild = rebuild
  )

  clusters_lookup <-
    replacement_rows %>%
    sf::st_drop_geometry() %>%
    dplyr::select(uuid_hex_pop, cluster_id, target_households)

  new_households_list <- list()

  # Google Open Buildings tiles deliberately overlap at their boundaries
  # (see 02_building_ingestion.R / 03_household_selection.R) - a
  # replacement hexagon sitting in an overlap zone would otherwise get
  # drawn independently from each part file it appears in, producing
  # duplicate survey_ids. Same "first file wins" fix as
  # select_stage2_households(): track which cluster_ids have already been
  # drawn and skip them in any later file.
  drawn_cluster_ids <- character(0)

  for(bf in final_building_files) {

    part_buildings <- readRDS(bf)

    part_building_points <-
      part_buildings %>%
      sf::st_transform(mycrs) %>%
      dplyr::inner_join(
        clusters_lookup %>% dplyr::select(uuid_hex_pop, cluster_id),
        by = "uuid_hex_pop"
      ) %>%
      dplyr::filter(
        !cluster_id %in% drawn_cluster_ids
      )

    if(nrow(part_building_points) == 0) next

    pools <- split(part_building_points, part_building_points$cluster_id)

    targets <- clusters_lookup$target_households[
      match(names(pools), clusters_lookup$cluster_id)
    ]

    new_households_list[[length(new_households_list) + 1]] <-
      purrr::map2(pools, targets, draw_cluster, reserve_n = reserve_n) %>%
      dplyr::bind_rows()

    drawn_cluster_ids <- c(drawn_cluster_ids, names(pools))

  }

  new_households_raw <- dplyr::bind_rows(new_households_list)

  still_empty <- setdiff(replacement_rows$cluster_id, new_households_raw$cluster_id)

  if(length(still_empty) > 0) {

    # Extremely unlikely given the round-based eligibility check just above,
    # but the eligibility check and this fetch are two separate GDAL calls -
    # report rather than silently drop if a replacement somehow still comes
    # up empty (e.g. a building right at the edge of the confidence/area
    # filter boundary in one query but not the other).
    warning(
      length(still_empty), " replacement hexagon(s) unexpectedly had no ",
      "eligible buildings on final fetch: ", paste(still_empty, collapse = ", ")
    )

    unresolved <-
      dplyr::bind_rows(
        unresolved,
        pps_targets %>%
          dplyr::filter(cluster_id %in% still_empty) %>%
          dplyr::mutate(reason = "candidate_pool_exhausted") %>%
          dplyr::select(cluster_id, pop_type, adm2_pcode, reason)
      )

    replacement_rows <- replacement_rows %>% dplyr::filter(cluster_id %in% new_households_raw$cluster_id)

  }

  new_households <- finalize_households(new_households_raw, replacement_rows, wards, admin3, mycrs)

  if(anyDuplicated(new_households$survey_id) > 0) {

    stop("Duplicate survey IDs detected in cluster reallocation.")

  }

  clusters_final <-
    clusters_merged %>%
    dplyr::filter(!cluster_id %in% replacement_rows$cluster_id) %>%
    dplyr::bind_rows(replacement_rows)

  message(
    "Reallocation complete: ", nrow(replacement_rows), " cluster(s) reallocated, ",
    nrow(unresolved), " unresolved."
  )

  list(
    clusters_final = clusters_final,
    new_households = new_households,
    unresolved = unresolved
  )

}
