# ==============================================================================
# IDP Stage 2 site assignment
#
# Function:
#   select_stage2_idp_sites()
#
# Purpose:
#   For IDP, Stage 2 does not use Google Open Buildings at all. Every
#   selected IDP hexagon was selected BECAUSE it has IOM DTM-reported
#   population, so it always has a real site location - the IOM DTM site's
#   own GPS point is used as that cluster's location, with a fixed radius
#   defining "this site" for the field team, who build a household list on
#   arrival and randomly select interviewees themselves. This removes the
#   zero-building-cluster problem for IDP entirely, rather than working
#   around it: unlike a building-footprint draw, there is nothing that can
#   come up empty here.
#
# ==============================================================================


#' Assign IOM DTM site locations to selected Stage-1 IDP clusters
#'
#' For each selected IDP cluster (hexagon), matches it to the IOM DTM
#' site(s) that fall within it, picks the largest by household count as the
#' cluster's representative location, and generates one row per household
#' interview slot (primary + reserve, same \code{survey_id} scheme as
#' \code{select_stage2_households()}) all sharing that single site's GPS
#' point - no building draw, since the field team performs the actual
#' household listing and random selection on-site.
#'
#' @param clusters sf polygon object of the SELECTED Stage-1 IDP clusters
#'   (\code{idp_clusters}).
#' @param iom_idp_df sf POINT object, one row per IOM DTM site, carrying
#'   \code{households}/\code{individuals} (numeric population fields - see
#'   \code{sampling_MSNA_NGA_2026_v3.R}, these are the cleaned numeric
#'   versions of the raw \code{pop_hh}/\code{pop} fields), \code{site_id_ssid},
#'   \code{site_name}, \code{site_type}, \code{ward}.
#' @param wards sf polygon object of GRID3 ward boundaries, passed through
#'   to \code{finalize_households()}.
#' @param admin3 sf polygon object of official COD Admin-3 boundaries,
#'   passed through to \code{finalize_households()}.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param cache_directory Character. Directory for the cached RDS output.
#' @param m Integer. Primary households per cluster. Default 6.
#' @param reserve_n Integer. Maximum reserve households per cluster beyond
#'   \code{m}. Default equal to \code{m}.
#' @param site_radius_m Numeric. Fixed radius (metres) around the site GPS
#'   point defining "this site" for field teams. Default 150 - chosen after
#'   checking the actual national IOM DTM site spacing (median
#'   nearest-neighbour distance between distinct sites ~513m, but ~38% of
#'   sites have another site within 300m), balancing covering a typical
#'   site's footprint against not sweeping in a neighbouring, genuinely
#'   different site.
#' @param dedup_radius_m Numeric. Sites within this distance of each other
#'   are treated as duplicate records of the same physical site (population
#'   summed) rather than distinct sites, before anything else happens.
#'   Default 30 - small compared to \code{site_radius_m}, since a real share
#'   of near-zero-distance "neighbours" in the source data are almost
#'   certainly repeat records (e.g. separate rows per population category)
#'   of one physical location, not two adjacent camps.
#' @param rebuild Logical. If TRUE, rebuild cached outputs.
#'
#' @return List:
#' \describe{
#'   \item{households}{sf point object (WGS84), one row per household
#'     interview slot, same schema as \code{select_stage2_households()}'s
#'     output (via the shared \code{finalize_households()}).}
#'   \item{clusters_final}{sf object, one row per IDP cluster, with the
#'     representative site's point as geometry and the site/location
#'     columns populated - the IDP counterpart to
#'     \code{reallocate_zero_building_clusters()}'s \code{clusters_final}.}
#' }
#'
#' @export
select_stage2_idp_sites <- function(
    clusters,
    iom_idp_df,
    wards,
    admin3,
    mycrs,
    cache_directory,
    m = 6,
    reserve_n = m,
    site_radius_m = 150,
    dedup_radius_m = 30,
    rebuild = FALSE
) {

  stopifnot(
    inherits(clusters, "sf"),
    inherits(iom_idp_df, "sf"),
    all(c("households", "individuals", "site_id_ssid", "site_name", "site_type", "ward") %in% names(iom_idp_df))
  )

  dir.create(cache_directory, recursive = TRUE, showWarnings = FALSE)

  final_cache <- file.path(cache_directory, "stage2_idp_sites.rds")

  if(file.exists(final_cache) && !rebuild) {

    message("Loading cached: stage2_idp_sites")

    return(readRDS(final_cache))

  }

  # radius_val: read once into a plain variable so it can be used safely
  # inside dplyr::mutate() below without any risk of colliding with the
  # site_radius_m COLUMN also being created on the same table.
  radius_val <- site_radius_m

  clusters_merged <- merge_repeated_psu_draws(clusters, m)

  clusters_proj <- sf::st_transform(clusters_merged, mycrs)
  sites_proj <- sf::st_transform(iom_idp_df, mycrs)

  # ---------------------------------------------------------------------------
  # Step A: dedup near-identical IOM DTM site records. A meaningful share of
  # "nearest neighbour" site pairs are ~0m apart in the raw data - almost
  # certainly the same physical site recorded more than once (e.g. separate
  # rows per population category/arrival year) rather than genuinely
  # distinct sites. Buffer-and-dissolve groups anything within
  # dedup_radius_m into one physical site before matching against hexagons,
  # so duplicate records don't masquerade as multiple distinct candidate
  # sites within the same selected hexagon.
  # ---------------------------------------------------------------------------

  sites_buffered <- sf::st_buffer(sites_proj, dedup_radius_m / 2)

  dedup_groups <-
    sf::st_union(sites_buffered) %>%
    sf::st_cast("POLYGON") %>%
    sf::st_sf(dedup_group_id = seq_along(.), geometry = .)

  sites_grouped <-
    sf::st_join(sites_proj, dedup_groups, join = sf::st_within)

  sites_deduped <-
    sites_grouped %>%
    dplyr::group_by(dedup_group_id) %>%
    dplyr::mutate(
      group_households = sum(households, na.rm = TRUE),
      group_individuals = sum(individuals, na.rm = TRUE)
    ) %>%
    dplyr::slice_max(households, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      households = group_households,
      individuals = group_individuals
    ) %>%
    dplyr::select(-group_households, -group_individuals)

  message(
    nrow(sites_proj) - nrow(sites_deduped),
    " IOM DTM site record(s) merged as duplicates of another site within ",
    dedup_radius_m, "m. ", nrow(sites_deduped), " distinct site(s) remain."
  )

  # ---------------------------------------------------------------------------
  # Step C: match deduped sites to selected hexagons. Every selected IDP
  # hexagon was selected BECAUSE it has IOM DTM-reported population, so a
  # cluster matching zero sites here is a structural error, not an expected
  # edge case - stop() rather than silently drop, so a real problem surfaces
  # immediately instead of shipping a bad frame.
  # ---------------------------------------------------------------------------

  clusters_geom_only <-
    clusters_proj %>%
    dplyr::select(cluster_id)

  site_matches <-
    sf::st_join(
      sites_deduped,
      clusters_geom_only,
      join = sf::st_within,
      left = FALSE
    )

  missing_clusters <- setdiff(clusters_merged$cluster_id, site_matches$cluster_id)

  if(length(missing_clusters) > 0) {

    stop(
      length(missing_clusters), " selected IDP cluster(s) matched no IOM DTM ",
      "site after dedup - this should not happen (every selected IDP ",
      "hexagon was selected because it has DTM-reported population): ",
      paste(missing_clusters, collapse = ", ")
    )

  }

  site_counts <-
    site_matches %>%
    sf::st_drop_geometry() %>%
    dplyr::count(cluster_id, name = "n_sites_in_hex")

  representative_sites <-
    site_matches %>%
    dplyr::group_by(cluster_id) %>%
    dplyr::slice_max(households, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::left_join(site_counts, by = "cluster_id") %>%
    dplyr::mutate(n_other_sites_in_hex = n_sites_in_hex - 1L)

  message(
    sum(representative_sites$n_other_sites_in_hex > 0),
    " of ", nrow(representative_sites),
    " selected IDP cluster(s) had more than one IOM DTM site in the same ",
    "hexagon - the largest by household count was used, others recorded ",
    "in n_other_sites_in_hex."
  )

  # ---------------------------------------------------------------------------
  # Step D: attach the representative site's point + attributes onto the
  # cluster table, replacing the hexagon polygon geometry with the site's
  # own point (the actual location field teams will be given) and
  # overriding the location/site provenance columns from their host-side
  # defaults (see merge_repeated_psu_draws()).
  # ---------------------------------------------------------------------------

  site_attrs <-
    representative_sites %>%
    sf::st_drop_geometry() %>%
    dplyr::transmute(
      cluster_id,
      site_households = households,
      iom_site_id = as.character(site_id_ssid),
      iom_site_name = as.character(site_name),
      iom_site_type = as.character(site_type),
      iom_site_ward = as.character(ward),
      n_other_sites_in_hex
    )

  site_geometry <-
    representative_sites %>%
    dplyr::select(cluster_id)

  clusters_merged_with_sites <-
    clusters_merged %>%
    sf::st_drop_geometry() %>%
    dplyr::select(
      -location_source,
      -households_in_cluster_source,
      -site_radius_m,
      -iom_site_id,
      -iom_site_name,
      -iom_site_type,
      -iom_site_ward,
      -n_other_sites_in_hex
    ) %>%
    dplyr::left_join(site_attrs, by = "cluster_id") %>%
    dplyr::mutate(
      location_source = "idp_site_point",
      households_in_cluster_source = "DTM_estimate_provisional",
      site_radius_m = radius_val,
      below_target_cluster = site_households < target_households
    ) %>%
    dplyr::left_join(site_geometry, by = "cluster_id") %>%
    sf::st_as_sf()

  # site_households was only needed transiently above (to build the
  # household rows' households_in_cluster below, and below_target_cluster
  # just above) - dropped here rather than kept as a cluster-level column so
  # clusters_final has the identical schema on both the host
  # (reallocate_zero_building_clusters()) and IDP side and bind_rows()
  # between them doesn't introduce a host-side-NA extra column.
  clusters_merged_with_sites_for_slots <- clusters_merged_with_sites

  clusters_merged_with_sites <-
    clusters_merged_with_sites %>%
    dplyr::select(-site_households)

  # ---------------------------------------------------------------------------
  # Step E: build household interview-slot rows directly (no draw_cluster()
  # call - there is no building pool to sample from; the field team performs
  # the actual listing and random selection on-site). Every slot in a
  # cluster shares that cluster's single site GPS point.
  # ---------------------------------------------------------------------------

  build_slots <- function(cluster_id_i, target_hh) {

    dplyr::bind_rows(
      tibble::tibble(
        cluster_id = cluster_id_i,
        status = "primary",
        interview_number = seq_len(target_hh),
        replacement_rank = NA_integer_
      ),
      tibble::tibble(
        cluster_id = cluster_id_i,
        status = "reserve",
        interview_number = NA_integer_,
        replacement_rank = seq_len(reserve_n)
      )
    )

  }

  household_slots <-
    purrr::map2(
      clusters_merged_with_sites$cluster_id,
      clusters_merged_with_sites$target_households,
      build_slots
    ) %>%
    dplyr::bind_rows()

  households_raw <-
    household_slots %>%
    dplyr::left_join(
      clusters_merged_with_sites_for_slots %>%
        sf::st_drop_geometry() %>%
        dplyr::select(cluster_id, households_in_cluster = site_households, target_households),
      by = "cluster_id"
    ) %>%
    dplyr::mutate(
      below_target_cluster = households_in_cluster < target_households,
      # No building draw for IDP - these three are host-only fields
      # (finalize_households()'s output schema is shared, so they still
      # need to exist here, just empty).
      building_id = NA_character_,
      confidence = NA_real_,
      building_area_m2 = NA_real_
    ) %>%
    dplyr::select(-target_households) %>%
    dplyr::left_join(
      clusters_merged_with_sites_for_slots %>% dplyr::select(cluster_id),
      by = "cluster_id"
    ) %>%
    sf::st_as_sf()

  message(
    "Built ", nrow(households_raw), " IDP household interview slot(s) across ",
    nrow(clusters_merged_with_sites), " cluster(s)."
  )

  # ---------------------------------------------------------------------------
  # Attach cluster-level attributes, design weights, admin3/ward attribution,
  # survey_id and coordinates via the shared finalize_households() - same
  # logic as select_stage2_households() and
  # reallocate_zero_building_clusters().
  # ---------------------------------------------------------------------------

  households_final <- finalize_households(households_raw, clusters_merged_with_sites, wards, admin3, mycrs)

  if(anyDuplicated(households_final$survey_id) > 0) {

    stop("Duplicate survey IDs detected in IDP site assignment.")

  }

  result <- list(
    households = households_final,
    clusters_final = clusters_merged_with_sites
  )

  saveRDS(result, final_cache)

  result

}
