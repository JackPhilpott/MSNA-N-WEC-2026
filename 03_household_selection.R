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
#'   clusters (e.g. \code{bind_rows(host_clusters, idp_clusters)}), one row
#'   per PPS draw - a hexagon selected more than once appears as multiple
#'   rows sharing the same \code{uuid_hex_pop} and is merged here.
#' @param building_files Character vector of file paths to per-GDB-part
#'   cached building points, as returned by \code{load_building_footprints()}
#'   - each an sf POINT object already carrying \code{uuid_hex_pop}
#'   identifying which physical hexagon each building falls within.
#'   Processed one file at a time (never combined into a single object -
#'   see \code{load_building_footprints()} for why) since every selected
#'   cluster's buildings come from exactly one part.
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
  # as an independent cluster visit.
  # ---------------------------------------------------------------------------

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
      strata_id = paste(pop_type, adm2_pcode, sep = "_")
    )


  message(
    nrow(clusters) - nrow(clusters_merged),
    " repeated PSU draw(s) merged into existing clusters. ",
    nrow(clusters_merged),
    " unique clusters remain."
  )


  # ---------------------------------------------------------------------------
  # Per-cluster household draw: primary (SRS without replacement) + reserve,
  # ranked in draw order. Clusters with fewer eligible buildings than the
  # target take everything available and are flagged as understaffed.
  # ---------------------------------------------------------------------------

  draw_cluster <- function(pool, target_hh) {

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
        understaffed_cluster = n_pool < target_hh
      )

  }


  # ---------------------------------------------------------------------------
  # Assign buildings to clusters and draw households ONE PART AT A TIME.
  #
  # Buildings arrive from load_building_footprints() as centroid points
  # already carrying uuid_hex_pop (the physical hexagon identity), so
  # assignment is a cheap attribute join rather than a spatial join - that
  # already happened per-batch during ingestion. Processing is done per
  # part rather than on one combined object because at full survey scale
  # the 3 parts together are 13M+ rows - repeatedly proved too large to
  # hold as a single in-memory object regardless of how it was assembled.
  # Since the GDB parts are geographically disjoint, every cluster's
  # buildings come from exactly one part, so no cluster's household draw
  # is ever split across two calls of this loop - only the small
  # per-household results need combining afterward.
  # ---------------------------------------------------------------------------

  clusters_lookup <-
    clusters_merged %>%
    sf::st_drop_geometry() %>%
    dplyr::select(
      uuid_hex_pop,
      cluster_id,
      target_households
    )

  households_list <- list()

  # Google Open Buildings country-scale tiles deliberately overlap at their
  # boundaries (so features straddling a tile edge aren't missed by either
  # tile) - confirmed empirically (~7% of hexagons in a test run had
  # buildings appearing in more than one part). A cluster whose hexagon
  # falls in that overlap zone would otherwise get drawn independently in
  # each part it appears in, producing duplicate survey IDs and an
  # incomplete/inconsistent pool either way. Tracking which cluster_ids
  # have already been drawn and skipping them in later parts resolves this
  # without needing to hold multiple parts' pools for the same cluster
  # simultaneously - the first part a cluster appears in is treated as
  # authoritative for that cluster.
  drawn_cluster_ids <- character(0)

  for(bf in building_files) {

    message("Stage 2: processing building file ", bf)

    part_buildings <- readRDS(bf)

    part_building_points <-
      part_buildings %>%
      sf::st_transform(mycrs) %>%
      dplyr::inner_join(
        # Only cluster_id is attached here (not target_households, looked up
        # separately below) - carrying target_households through would
        # collide with the left_join that re-attaches it further down,
        # producing target_households.x/.y instead of a clean column.
        clusters_lookup %>% dplyr::select(uuid_hex_pop, cluster_id),
        by = "uuid_hex_pop"
      ) %>%
      dplyr::filter(
        !cluster_id %in% drawn_cluster_ids
      )

    rm(part_buildings)
    gc(full = FALSE)

    message(
      nrow(part_building_points), " buildings from this part fall within a selected cluster ",
      "not already drawn from an earlier part."
    )

    if(nrow(part_building_points) > 0) {

      # Process in cluster-group chunks rather than splitting and drawing
      # the whole file's worth of buildings at once - a single part/chunk
      # file can itself be millions of rows (confirmed: this step alone
      # crashed on a 2.87M-row file), the same "materialize everything
      # before processing" problem already fixed elsewhere, just one layer
      # deeper. Sorting once and slicing by row index (not repeated
      # dplyr::filter() scans) keeps each cluster's rows contiguous and
      # this cheap even across many chunks.
      message("Stage 2: sorting ", nrow(part_building_points), " rows by cluster_id...")

      part_building_points <- part_building_points %>% dplyr::arrange(cluster_id)

      gc(full = FALSE)
      message("Stage 2: sort done, computing cluster boundaries...")

      cluster_rle <- rle(part_building_points$cluster_id)
      cluster_ids_ordered <- cluster_rle$values
      cluster_row_ends <- cumsum(cluster_rle$lengths)
      cluster_row_starts <- c(1L, head(cluster_row_ends, -1) + 1L)

      n_clusters_in_part <- length(cluster_ids_ordered)
      cluster_chunk_size <- 50

      message(
        "Stage 2: ", n_clusters_in_part, " clusters in this file, processing in chunks of ",
        cluster_chunk_size
      )

      chunk_num <- 0

      for(cc_start in seq(1, n_clusters_in_part, by = cluster_chunk_size)) {

        chunk_num <- chunk_num + 1

        cc_end <- min(cc_start + cluster_chunk_size - 1, n_clusters_in_part)

        row_start <- cluster_row_starts[cc_start]
        row_end <- cluster_row_ends[cc_end]

        chunk_points <- part_building_points[row_start:row_end, ]

        pools <- split(chunk_points, chunk_points$cluster_id)

        targets <- clusters_lookup$target_households[
          match(names(pools), clusters_lookup$cluster_id)
        ]

        chunk_households <-
          purrr::map2(pools, targets, draw_cluster) %>%
          dplyr::bind_rows()

        households_list[[length(households_list) + 1]] <- chunk_households

        drawn_cluster_ids <- c(drawn_cluster_ids, names(pools))

        rm(chunk_points, pools, targets, chunk_households)
        gc(full = FALSE)

        if(chunk_num %% 5 == 0) {
          message(
            "Stage 2: cluster chunk ", cc_start, "-", cc_end, " of ", n_clusters_in_part,
            " done (", sum(purrr::map_int(households_list, nrow)), " households so far this run)"
          )
        }

      }

      rm(cluster_rle, cluster_ids_ordered, cluster_row_ends, cluster_row_starts)

    }

    rm(part_building_points)
    gc(full = FALSE)

  }

  households <- dplyr::bind_rows(households_list)

  rm(households_list)
  gc(full = FALSE)


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
  # Attach cluster-level design/geospatial attributes
  # ---------------------------------------------------------------------------

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
          target_households
        ),
      by = "cluster_id"
    )


  # ---------------------------------------------------------------------------
  # Second-stage selection probability and base design weight
  # ---------------------------------------------------------------------------

  households <-
    households %>%
    dplyr::mutate(
      ssu_probability = pmin(1, target_households / households_in_cluster),
      base_weight = 1 / (psu_probability * ssu_probability)
    )


  # ---------------------------------------------------------------------------
  # Admin-3/ward attribution.
  #
  # GRID3 ward boundaries are the PRIMARY source (adm3_pcode/adm3_name),
  # since they are the only layer with national NW/NE/NC coverage - the
  # official COD Admin-3 layer only covers the 3 NE states. The COD layer is
  # still attached as a secondary reference (admin3_cod_pcode/
  # admin3_cod_name) where available, since it may be the identifier field
  # teams are already used to referencing in NE.
  # ---------------------------------------------------------------------------

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


  # ---------------------------------------------------------------------------
  # Survey identifier and UTM coordinates (households is still in mycrs here)
  # ---------------------------------------------------------------------------

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


  # ---------------------------------------------------------------------------
  # WGS84 coordinates
  # ---------------------------------------------------------------------------

  households_wgs84 <- sf::st_transform(households, 4326)

  coords_wgs84 <- sf::st_coordinates(households_wgs84)

  households_wgs84 <-
    households_wgs84 %>%
    dplyr::mutate(
      longitude = coords_wgs84[, "X"],
      latitude = coords_wgs84[, "Y"]
    )


  # ---------------------------------------------------------------------------
  # Final column selection
  # ---------------------------------------------------------------------------

  households_final <-
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
      understaffed_cluster,
      geometry
    )


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
