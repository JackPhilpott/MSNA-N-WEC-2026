# ==============================================================================
# Stage 2 household selection
#
# Function:
#   select_stage2_households()
#
# Purpose:
#   Selects household GPS locations within each selected Stage-1 PSU cluster
#   by randomly drawing building footprints as household proxies, and
#   attaches the geospatial and survey-design attributes needed for weighted
#   analysis.
#
# ==============================================================================


#' Draw primary + reserve households from a cluster's eligible building pool
#'
#' Simple random sample without replacement of primary households plus a
#' reserve/replacement list, ranked in draw order. A cluster with fewer
#' eligible buildings than the target takes everything available and is
#' flagged via \code{below_target_cluster}. Shared by \code{select_stage2_households()} and
#' \code{reallocate_zero_building_clusters()} (\code{04_stage2_cluster_reallocation.R})
#' so both draw households the same way.
#'
#' @param pool sf object of eligible building points for one cluster.
#' @param target_hh Integer. Primary household target for this cluster.
#' @param reserve_n Integer. Maximum reserve households beyond \code{target_hh}.
draw_cluster <- function(pool, target_hh, reserve_n) {

  n_pool <- nrow(pool)

  if(n_pool == 0) {

    return(NULL)

  }

  pool <- pool[sample.int(n_pool), ]

  n_take <- min(n_pool, target_hh + reserve_n)

  pool <- pool[seq_len(n_take), ]

  n_primary <- min(n_pool, target_hh)

  draw_rank <- seq_len(n_take)

  pool %>%
    dplyr::mutate(
      status = ifelse(draw_rank <= n_primary, "primary", "reserve"),
      interview_number = ifelse(status == "primary", draw_rank, NA_integer_),
      replacement_rank = ifelse(status == "reserve", draw_rank - n_primary, NA_integer_),
      households_in_cluster = n_pool,
      below_target_cluster = n_pool < target_hh
    )

}


#' Read an RDS file with retry, guarding against a transient file lock
#'
#' Mirrors the retry pattern already used for cache writes elsewhere in
#' this pipeline (\code{02_stage2_building_ingestion.R}'s \code{flush_buildings()}/
#' \code{save_progress()}), applied to reads here: a OneDrive/AV lock
#' briefly held on a cache file must not silently produce a short read in
#' one pass and a full read in another, which is exactly the kind of
#' inconsistency \code{draw_households_from_files()}' two-pass design
#' depends on NOT happening.
safe_read_rds <- function(path, attempts = 5) {

  for(attempt in seq_len(attempts)) {

    result <- tryCatch(readRDS(path), error = function(e) e)

    if(!inherits(result, "error")) {
      return(result)
    }

    message("Warning: read attempt ", attempt, " of ", path, " failed (", conditionMessage(result), "), retrying...")
    Sys.sleep(2)

  }

  stop("Could not read ", path, " after ", attempts, " attempts.")

}


#' Determine which building files each cluster's eligible buildings appear in
#'
#' Building points arriving from \code{load_building_footprints()} can have
#' a given cluster's eligible buildings split across more than one cache
#' file - not just the three national Google Open Buildings source parts
#' (an intentional, accepted overlap - see
#' \code{load_building_footprints()} roxygen docs), but also, for
#' hexagons in very dense areas, across more than one chunk file WITHIN
#' the same part. This happens because the ingestion-time duplicate
#' detector (\code{seen_keys} in \code{02_stage2_building_ingestion.R}) only
#' remembers a bounded, rolling window of recently-seen buildings; in a
#' dense stratum with many nearby selected hexagons, enough buildings can
#' be processed between two overlapping fetches of the SAME physical
#' building that the window has already forgotten it, so it gets fetched
#' and saved a second time under a different chunk. A naive "use the first
#' file a cluster appears in" rule (which correctly handles the 3-part
#' overlap case) then arbitrarily locks onto whichever chunk happened to
#' be processed first for that cluster - which, empirically, is very
#' often a small, incomplete fragment of the true set (confirmed on a
#' real cluster: 3,288 true eligible buildings, only 121 in the first
#' chunk).
#'
#' This function does a first, lightweight pass over every file to record
#' - for every cluster - the INDEX of every file its buildings appear in
#' at all (existence, not a count), so \code{draw_households_from_files()}
#' knows exactly which file completes a cluster's pool rather than
#' assuming the first file is enough. Existence-per-file is a much more
#' robust signal to rely on across two independent passes than an exact
#' row count would be: it depends only on whether a file's join against
#' \code{clusters_lookup} produces any match for a cluster, using the
#' IDENTICAL deterministic join both times - not on point-level identity
#' matching (e.g. rounded centroid coordinates), which risks disagreeing
#' between passes for reasons as subtle as floating-point jitter from an
#' otherwise-idempotent CRS transform. An earlier count-based version of
#' this fix hit exactly that failure mode (a small number of clusters
#' where the two passes' counts disagreed, causing a cluster to be drawn
#' more than once - duplicate survey IDs); tracking file membership
#' instead of counts closes that gap.
#'
#' @param building_files Character vector of building cache file paths.
#' @param clusters_lookup Data frame with \code{uuid_hex_pop},
#'   \code{cluster_id}.
#'
#' @return Named list, \code{cluster_id} -> integer vector of indices into
#'   \code{building_files} where that cluster has at least one eligible
#'   building.
compute_cluster_file_membership <- function(building_files, clusters_lookup) {

  message("Pass 1/2: scanning ", length(building_files), " file(s) to determine which file(s) each cluster's buildings appear in...")

  membership <- new.env(parent = emptyenv())

  for(i in seq_along(building_files)) {

    part_buildings <- safe_read_rds(building_files[i])

    if(nrow(part_buildings) == 0) {
      rm(part_buildings)
      next
    }

    present_clusters <-
      part_buildings %>%
      sf::st_drop_geometry() %>%
      dplyr::inner_join(
        clusters_lookup %>% dplyr::select(uuid_hex_pop, cluster_id),
        by = "uuid_hex_pop"
      ) %>%
      dplyr::distinct(cluster_id) %>%
      dplyr::pull(cluster_id)

    for(cid in present_clusters) {

      if(exists(cid, envir = membership, inherits = FALSE)) {
        assign(cid, c(get(cid, envir = membership), i), envir = membership)
      } else {
        assign(cid, i, envir = membership)
      }

    }

    rm(part_buildings, present_clusters)
    gc(full = FALSE)

  }

  result <- as.list(membership)

  message("Pass 1/2 complete: ", length(result), " cluster(s) have at least one eligible building.")

  result

}


#' Draw households from building files, consolidating clusters split across files
#'
#' Two-pass replacement for a naive "first file wins" draw. Pass 1
#' (\code{compute_cluster_file_membership()}) establishes exactly which
#' file(s) each cluster's eligible buildings appear in. Pass 2 scans every
#' file again, accumulating each cluster's rows (deduplicated by centroid
#' location, as a defence against a physical building genuinely being
#' fetched more than once) in a small per-cluster buffer as they're
#' encountered, and draws + discards a cluster as soon as the file
#' currently being processed is the LAST file pass 1 recorded for it - so
#' at any point only clusters still awaiting a later file (a small
#' fraction of the total) are held in memory, not the whole dataset. Any
#' cluster somehow still incomplete after every file has been scanned is
#' drawn anyway from whatever was found, with a warning - a safety net,
#' not the expected path.
#'
#' @param building_files Character vector of building cache file paths.
#' @param clusters_lookup Data frame with \code{uuid_hex_pop},
#'   \code{cluster_id}, \code{target_households}.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param reserve_n Integer. Maximum reserve households beyond target,
#'   passed through to \code{draw_cluster()}.
#'
#' @return sf point object, one row per drawn household (primary +
#'   reserve), same shape as \code{draw_cluster()}'s output, combined
#'   across all clusters found in \code{building_files}.
draw_households_from_files <- function(building_files, clusters_lookup, mycrs, reserve_n) {

  membership <- compute_cluster_file_membership(building_files, clusters_lookup)
  last_file_lookup <- purrr::map_int(membership, max)

  accumulator <- new.env(parent = emptyenv())
  households_list <- list()

  finalize_cluster <- function(cluster_id_i) {

    acc <- get(cluster_id_i, envir = accumulator)
    target_hh <- clusters_lookup$target_households[match(cluster_id_i, clusters_lookup$cluster_id)]

    result <- draw_cluster(acc$rows, target_hh, reserve_n)

    if(!is.null(result)) {
      households_list[[length(households_list) + 1]] <<- result
    }

    rm(list = cluster_id_i, envir = accumulator)

  }

  for(i in seq_along(building_files)) {

    bf <- building_files[i]

    message("Pass 2/2: processing (", i, "/", length(building_files), ") ", bf)

    part_buildings <- safe_read_rds(bf) %>% sf::st_transform(mycrs)

    if(nrow(part_buildings) == 0) {
      rm(part_buildings)
      next
    }

    coords <- sf::st_coordinates(part_buildings)

    part_building_points <-
      part_buildings %>%
      dplyr::mutate(
        .centroid_key = paste0(round(coords[, "X"], 1), "_", round(coords[, "Y"], 1))
      ) %>%
      dplyr::inner_join(
        clusters_lookup %>% dplyr::select(uuid_hex_pop, cluster_id),
        by = "uuid_hex_pop"
      )

    rm(part_buildings, coords)
    gc(full = FALSE)

    if(nrow(part_building_points) > 0) {

      part_building_points <- part_building_points %>% dplyr::arrange(cluster_id)

      cluster_rle <- rle(part_building_points$cluster_id)
      cluster_ids_ordered <- cluster_rle$values
      cluster_row_ends <- cumsum(cluster_rle$lengths)
      cluster_row_starts <- c(1L, head(cluster_row_ends, -1) + 1L)

      n_clusters_in_part <- length(cluster_ids_ordered)
      cluster_chunk_size <- 50

      for(cc_start in seq(1, n_clusters_in_part, by = cluster_chunk_size)) {

        cc_end <- min(cc_start + cluster_chunk_size - 1, n_clusters_in_part)
        row_start <- cluster_row_starts[cc_start]
        row_end <- cluster_row_ends[cc_end]

        chunk_points <- part_building_points[row_start:row_end, ]

        for(cid in unique(chunk_points$cluster_id)) {

          new_rows <- chunk_points[chunk_points$cluster_id == cid, ]

          if(exists(cid, envir = accumulator, inherits = FALSE)) {

            existing <- get(cid, envir = accumulator)
            new_rows <- new_rows[!new_rows$.centroid_key %in% existing$keys, ]

            if(nrow(new_rows) > 0) {
              assign(
                cid,
                list(
                  rows = dplyr::bind_rows(existing$rows, new_rows),
                  keys = c(existing$keys, new_rows$.centroid_key)
                ),
                envir = accumulator
              )
            }

          } else {

            new_rows <- new_rows[!duplicated(new_rows$.centroid_key), ]
            assign(cid, list(rows = new_rows, keys = new_rows$.centroid_key), envir = accumulator)

          }

          # Finalize once we've just processed this cluster's LAST known
          # file (per pass 1) - a simple index comparison, not dependent
          # on the accumulated row count matching anything.
          if(i >= last_file_lookup[[cid]]) {
            finalize_cluster(cid)
          }

        }

        rm(chunk_points)

      }

      rm(cluster_rle, cluster_ids_ordered, cluster_row_ends, cluster_row_starts)

    }

    rm(part_building_points)
    gc(full = FALSE)

  }

  remaining <- ls(envir = accumulator)

  if(length(remaining) > 0) {

    warning(
      length(remaining), " cluster(s) still incomplete after scanning every building ",
      "file (should not normally happen) - drawing from whatever was accumulated: ",
      paste(remaining, collapse = ", ")
    )

    for(cid in remaining) finalize_cluster(cid)

  }

  dplyr::bind_rows(households_list)

}


#' Merge repeated PSU draws of the same hexagon into one cluster
#'
#' PPS systematic sampling can select the same hexagon more than once,
#' producing multiple rows in the selected-clusters table that share the
#' same \code{uuid_hex_pop}. Collapses these into one row per physical
#' hexagon with a proportionally larger household target, rather than
#' treating each draw as an independent cluster visit. Shared by
#' \code{select_stage2_households()} and
#' \code{reallocate_zero_building_clusters()} (\code{04_stage2_cluster_reallocation.R})
#' so both work from an identical cluster-level table.
#'
#' @param clusters sf polygon object, one row per Stage-1 PPS draw (e.g.
#'   \code{bind_rows(host_clusters, idp_clusters)}).
#' @param m Integer. Primary households per cluster.
#'
#' @return sf polygon object, one row per unique \code{uuid_hex_pop}, with
#'   \code{target_households}, \code{strata_id}, \code{reallocated} (FALSE),
#'   \code{original_uuid_hex_pop} (NA), and the location/site provenance
#'   columns described below (all set to their host/building-footprint
#'   defaults here - \code{05_stage2_idp_site_assignment.R} overrides them for IDP
#'   clusters) added.
merge_repeated_psu_draws <- function(clusters, m) {

  clusters_merged <-
    clusters %>%
    dplyr::group_by(
      pop_type,
      adm2_pcode,
      uuid_hex_pop
    ) %>%
    dplyr::slice_min(
      cluster_number,
      n = 1,
      with_ties = FALSE
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      target_households = m * selection_count,
      strata_id = paste(pop_type, adm2_pcode, sep = "_"),
      # Every cluster is "not reallocated" here - only
      # reallocate_zero_building_clusters() (04_stage2_cluster_reallocation.R) ever
      # sets these, for the small number of zero-building clusters it
      # substitutes a new hexagon into. Present on every row (not just
      # reallocated ones) so finalize_households()'s output schema is
      # identical between a normal Stage 2 run and a reallocation run.
      reallocated = FALSE,
      original_uuid_hex_pop = NA_character_,
      # Set on every row for the same reason as reallocated/
      # original_uuid_hex_pop above - only add_supplementary_clusters()
      # (04_stage2_cluster_reallocation.R) ever sets this TRUE, for the small
      # number of brand-new clusters it adds (not substitutes) to a
      # stratum whose realized sample fell short of its target even after
      # raising m.
      supplementary_cluster = FALSE,
      # Location/site provenance - host clusters are always
      # building-footprint-based. IDP clusters (05_stage2_idp_site_assignment.R)
      # override every one of these with the IOM DTM site actually used,
      # since IDP Stage 2 no longer queries buildings at all. Present on
      # every row so the combined host+IDP output has one consistent
      # schema rather than pop_type-conditional columns.
      location_source = "building_footprint",
      households_in_cluster_source = "building_footprint_count",
      site_radius_m = NA_real_,
      iom_site_id = NA_character_,
      iom_site_name = NA_character_,
      iom_site_type = NA_character_,
      iom_site_ward = NA_character_,
      n_other_sites_in_hex = NA_integer_
    )

  message(
    nrow(clusters) - nrow(clusters_merged),
    " repeated PSU draw(s) merged into existing clusters. ",
    nrow(clusters_merged),
    " unique clusters remain."
  )

  clusters_merged

}


#' Attach cluster-level design/geospatial attributes and finalize columns
#'
#' Shared finishing logic for a set of drawn household rows (still in
#' \code{mycrs}, one row per household, from \code{draw_cluster()}): joins
#' cluster-level Stage 1 attributes, computes second-stage selection
#' probability and design weight, attaches GRID3 ward (primary) and COD
#' Admin-3 (secondary) attribution, builds \code{survey_id}, and produces
#' both UTM and WGS84 coordinate columns. Shared by
#' \code{select_stage2_households()} and
#' \code{reallocate_zero_building_clusters()} (\code{04_stage2_cluster_reallocation.R})
#' so both produce an identical output schema.
#'
#' @param households sf point object of drawn households (in \code{mycrs}),
#'   carrying \code{cluster_id} for the join.
#' @param clusters_merged sf/data frame, one row per cluster, carrying
#'   \code{cluster_id}, \code{pop_type}, \code{strata_id}, \code{region},
#'   \code{adm1_pcode}, \code{adm1_name}, \code{adm2_pcode}, \code{adm2_name},
#'   \code{uuid_hex}, \code{uuid}, \code{certainty_stratum},
#'   \code{selection_type}, \code{selection_count}, \code{psu_probability},
#'   \code{target_households}, \code{reallocated}, \code{original_uuid_hex_pop},
#'   \code{supplementary_cluster},
#'   \code{location_source}, \code{households_in_cluster_source},
#'   \code{site_radius_m}, \code{iom_site_id}, \code{iom_site_name},
#'   \code{iom_site_type}, \code{iom_site_ward}, \code{n_other_sites_in_hex}
#'   (see \code{merge_repeated_psu_draws()} for the host-side defaults).
#' @param wards sf polygon object of GRID3 ward boundaries.
#' @param admin3 sf polygon object of official COD Admin-3 boundaries.
#' @param mycrs Coordinate reference system used for spatial processing.
#'
#' @return sf point object (WGS84), finalized households ready for output.
finalize_households <- function(households, clusters_merged, wards, admin3, mycrs) {

  households <-
    households %>%
    dplyr::left_join(
      clusters_merged %>%
        sf::st_drop_geometry() %>%
        dplyr::select(
          cluster_id,
          pop_type,
          strata_id,
          region,
          adm1_pcode,
          adm1_name,
          adm2_pcode,
          adm2_name,
          uuid_hex,
          uuid,
          certainty_stratum,
          selection_type,
          selection_count,
          psu_probability,
          target_households,
          reallocated,
          original_uuid_hex_pop,
          supplementary_cluster,
          location_source,
          households_in_cluster_source,
          site_radius_m,
          iom_site_id,
          iom_site_name,
          iom_site_type,
          iom_site_ward,
          n_other_sites_in_hex
        ),
      by = "cluster_id"
    )

  households <-
    households %>%
    dplyr::mutate(
      ssu_probability = pmin(1, target_households / households_in_cluster),
      base_weight = 1 / (psu_probability * ssu_probability)
    )

  wards_proj <-
    sf::st_transform(wards, mycrs) %>%
    dplyr::select(
      adm3_pcode = wardcode,
      adm3_name = wardname
    ) %>%
    dplyr::mutate(
      admin3_source = "GRID3"
    )

  households <-
    sf::st_join(
      households,
      wards_proj,
      join = sf::st_within,
      left = TRUE
    )

  admin3_proj <-
    sf::st_transform(admin3, mycrs) %>%
    dplyr::select(
      admin3_cod_pcode = adm3_pcode,
      admin3_cod_name = adm3_name
    )

  households <-
    sf::st_join(
      households,
      admin3_proj,
      join = sf::st_within,
      left = TRUE
    )

  households <-
    households %>%
    dplyr::mutate(
      survey_id =
        dplyr::case_when(
          status == "primary" ~
            paste0(cluster_id, "_HH", stringr::str_pad(interview_number, 2, pad = "0")),
          status == "reserve" ~
            paste0(cluster_id, "_R", stringr::str_pad(replacement_rank, 2, pad = "0"))
        )
    )

  coords_utm <- sf::st_coordinates(households)

  households <-
    households %>%
    dplyr::mutate(
      x_utm = coords_utm[, "X"],
      y_utm = coords_utm[, "Y"]
    )

  households_wgs84 <- sf::st_transform(households, 4326)

  coords_wgs84 <- sf::st_coordinates(households_wgs84)

  households_wgs84 <-
    households_wgs84 %>%
    dplyr::mutate(
      longitude = coords_wgs84[, "X"],
      latitude = coords_wgs84[, "Y"]
    )

  households_wgs84 %>%
    dplyr::select(
      survey_id,
      cluster_id,
      status,
      interview_number,
      replacement_rank,
      pop_type,
      strata_id,
      region,
      adm1_pcode,
      adm1_name,
      adm2_pcode,
      adm2_name,
      adm3_pcode,
      adm3_name,
      admin3_source,
      admin3_cod_pcode,
      admin3_cod_name,
      uuid_hex,
      uuid,
      building_id,
      confidence,
      building_area_m2,
      latitude,
      longitude,
      x_utm,
      y_utm,
      households_in_cluster,
      target_households,
      selection_count,
      certainty_stratum,
      selection_type,
      psu_probability,
      ssu_probability,
      base_weight,
      below_target_cluster,
      reallocated,
      original_uuid_hex_pop,
      supplementary_cluster,
      location_source,
      households_in_cluster_source,
      site_radius_m,
      iom_site_id,
      iom_site_name,
      iom_site_type,
      iom_site_ward,
      n_other_sites_in_hex,
      geometry
    )

}


#' Select Stage 2 households from building footprints within selected clusters
#'
#' For each selected Stage-1 PSU cluster (hexagon), assigns eligible building
#' footprints to that cluster via centroid point-in-polygon, then draws a
#' simple random sample without replacement of primary households plus a
#' reserve/replacement list. PPS systematic sampling can select the same
#' hexagon more than once; repeated selections of the same hexagon are
#' merged into a single cluster with a proportionally larger household
#' target, rather than treated as separate cluster visits.
#'
#' @param clusters sf polygon object of the SELECTED Stage-1 sampling
#'   clusters - host clusters only (\code{host_clusters}). IDP clusters use
#'   \code{select_stage2_idp_sites()} (\code{05_stage2_idp_site_assignment.R})
#'   instead: IDP household locations come from the IOM DTM site's own GPS
#'   point rather than a building footprint draw, so IDP Stage 2 never
#'   queries Google Open Buildings. One row per PPS draw - a hexagon
#'   selected more than once appears as multiple rows sharing the same
#'   \code{uuid_hex_pop} and is merged here.
#' @param building_files Character vector of file paths to per-GDB-part
#'   cached building points, as returned by \code{load_building_footprints()}
#'   - each an sf POINT object already carrying \code{uuid_hex_pop}
#'   identifying which physical hexagon each building falls within.
#'   Never combined into a single object (see \code{load_building_footprints()}
#'   for why) - processed via \code{draw_households_from_files()}, which
#'   correctly consolidates a cluster's eligible buildings even when they
#'   are split across more than one of these files.
#' @param wards sf polygon object of GRID3 ward boundaries (fields
#'   \code{wardcode}, \code{wardname}), used as the PRIMARY Admin-3/ward
#'   attribution source for every region, since it is the only boundary
#'   layer with national (NW/NE/NC) coverage - the official COD Admin-3
#'   layer (\code{admin3}) only covers the 3 NE states.
#' @param admin3 sf polygon object of official COD Admin-3 boundaries
#'   (fields \code{adm3_pcode}, \code{adm3_name}), used as a SECONDARY
#'   reference source, attached under \code{admin3_cod_pcode}/
#'   \code{admin3_cod_name} where available (NE only in practice) for field
#'   teams who may need to cross-reference the official identifiers.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param cache_directory Character. Directory for the cached RDS output.
#' @param m Integer. Primary households per cluster. Default 6.
#' @param reserve_n Integer. Maximum reserve/replacement households per
#'   cluster, beyond the \code{m} primary, capped by building availability.
#'   Default equal to \code{m}.
#' @param seed Integer or NULL. Random seed set before the household draw,
#'   for reproducibility, independent of the Stage 1 PPS draw's seed.
#'   Default 1234.
#' @param rebuild Logical. If TRUE, rebuild cached outputs.
#'
#' @return sf point object (WGS84 geometry), one row per selected household
#'   (primary + reserve), with design and geospatial attributes, including
#'   both UTM (\code{x_utm}/\code{y_utm}, in \code{mycrs}) and WGS84
#'   (\code{longitude}/\code{latitude}) coordinate columns. Primary rows are
#'   numbered \code{interview_number} 1..m; reserve rows are numbered
#'   \code{replacement_rank} 1..reserve_n instead, ranked in draw order.
#'   \code{adm3_pcode}/\code{adm3_name} (GRID3-sourced, national coverage)
#'   are the primary Admin-3 fields, with \code{admin3_source} recording
#'   provenance and \code{admin3_cod_pcode}/\code{admin3_cod_name} carrying
#'   the official COD reference where available.
#'
#' @export
select_stage2_households <- function(
    clusters,
    building_files,
    wards,
    admin3,
    mycrs,
    cache_directory,
    m = 6,
    reserve_n = m,
    seed = 1234,
    rebuild = FALSE
) {


  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  stopifnot(
    inherits(clusters, "sf"),
    is.character(building_files),
    all(file.exists(building_files)),
    inherits(wards, "sf"),
    inherits(admin3, "sf")
  )


  dir.create(
    cache_directory,
    recursive = TRUE,
    showWarnings = FALSE
  )


  final_cache <- file.path(
    cache_directory,
    "stage2_households.rds"
  )


  if(file.exists(final_cache) && !rebuild) {

    message("Loading cached: stage2_households")

    return(
      readRDS(final_cache)
    )

  }


  if(!is.null(seed)) {

    set.seed(seed)

  }


  # ---------------------------------------------------------------------------
  # Merge repeated PSU draws of the same hexagon into a single cluster with a
  # proportionally larger household target, rather than treating each draw
  # as an independent cluster visit (shared helper, defined above).
  # ---------------------------------------------------------------------------

  clusters_merged <- merge_repeated_psu_draws(clusters, m)


  # ---------------------------------------------------------------------------
  # Per-cluster household draw: primary (SRS without replacement) + reserve,
  # ranked in draw order, via the shared draw_cluster() defined above.
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Assign buildings to clusters and draw households via the shared
  # draw_households_from_files() (defined above) - correctly consolidates
  # any cluster whose eligible buildings are split across more than one
  # cache file (both the 3 national source parts, which deliberately
  # overlap at their edges, and - within a single part - chunks split by
  # a rolling duplicate-detection window that can lose track of a building
  # in very dense areas) rather than assuming the first file it appears in
  # is a complete picture.
  # ---------------------------------------------------------------------------

  clusters_lookup <-
    clusters_merged %>%
    sf::st_drop_geometry() %>%
    dplyr::select(
      uuid_hex_pop,
      cluster_id,
      target_households
    )

  households <- draw_households_from_files(building_files, clusters_lookup, mycrs, reserve_n)


  zero_building_clusters <-
    clusters_merged$cluster_id[
      !clusters_merged$cluster_id %in% households$cluster_id
    ]

  if(length(zero_building_clusters) > 0) {

    warning(
      length(zero_building_clusters),
      " selected cluster(s) had ZERO eligible buildings and produced no ",
      "households: ",
      paste(zero_building_clusters, collapse = ", ")
    )

  }


  # ---------------------------------------------------------------------------
  # Attach cluster-level attributes, design weights, admin3/ward attribution,
  # survey_id and coordinates via the shared finalize_households() (defined
  # above) - identical logic to what reallocate_zero_building_clusters()
  # (04_stage2_cluster_reallocation.R) uses for the replacement households it draws.
  # ---------------------------------------------------------------------------

  households_final <- finalize_households(households, clusters_merged, wards, admin3, mycrs)


  # ---------------------------------------------------------------------------
  # Final validation
  # ---------------------------------------------------------------------------

  if(anyDuplicated(households_final$survey_id) > 0) {

    stop(
      "Duplicate survey IDs detected."
    )

  }


  saveRDS(
    households_final,
    final_cache
  )


  households_final

}
