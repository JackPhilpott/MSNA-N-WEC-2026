# ==============================================================================
# IDP in-camp backup GPS point generation - PART 1: flag largest camps,
# gather extent-delineation evidence (building-footprint query + satellite
# imagery crop) for manual visual review.
#
# Standalone pre-fieldwork analysis (NOT part of the numbered 00-08 pipeline,
# does not modify the frozen sampling frame). Scope: "idps in camp" sites
# only (81 sites) - the complement of the earlier host-community feasibility
# analysis, which covered "idps in host" sites specifically.
#
# This script does the parts a script CAN do (ranking, footprint query,
# image capture). Camp extent delineation from satellite imagery requires
# visual judgement a script cannot make - Part 2 (a separate script)
# consumes a manually-completed review sheet this script produces, together
# with the footprint-cluster evidence gathered here, to finalise each
# flagged camp's extent and draw the randomised backup point.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
  library(ggspatial)
  library(stringr)
  library(purrr)
})

mycrs <- 31028   # WGS 84 / UTM zone 28N, metres - identical to main pipeline

data_dir       <- here("input_data")
output_dir     <- here("output")
analysis_dir   <- here(output_dir, "data", "supporting_analysis", "idp_camp_backup_points")
review_dir     <- here(analysis_dir, "camp_review_images")
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)

reference_data_dir <- "C:/Users/JackPHILPOTT/Personal - Documents/GIS"
building_data_dir <- file.path(reference_data_dir, "Google_Open_Buildings")

get_tiles_retry <- function(..., max_attempts = 5, pause_s = 5) {
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(maptiles::get_tiles(...), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    message("get_tiles() attempt ", attempt, "/", max_attempts, " failed: ", conditionMessage(result))
    Sys.sleep(pause_s)
  }
  stop("get_tiles() failed after ", max_attempts, " attempts: ", conditionMessage(result))
}

map_theme <- function(){
  list(
    theme_void(),
    annotation_scale(location = "br", text_cex = 0.9),
    annotation_north_arrow(location = "tl", height = unit(0.9, "cm"), width = unit(0.9, "cm"))
  )
}

# ---------------------------------------------------------------------------
# 1. Load in-camp IDP sites, rank by caseload
# ---------------------------------------------------------------------------
idp_sites_raw <- read_csv(here("_archive", "2026-07-23_design_frame_pre_coverage", "stage2_sampling_frame_idp.csv"), show_col_types = FALSE)

camp_sites <-
  idp_sites_raw %>%
  filter(idp_population_category == "idps in camp") %>%
  distinct(
    cluster_id, iom_site_id, iom_site_name, iom_site_type, iom_site_ward,
    region, adm1_pcode, adm1_name, adm2_pcode, adm2_name,
    latitude, longitude, households_in_cluster, n_other_sites_in_hex
  ) %>%
  arrange(desc(households_in_cluster))

n_total <- nrow(camp_sites)
message(n_total, " in-camp IDP sites in the delivered sample.")

caseload_percentiles <- quantile(
  camp_sites$households_in_cluster,
  probs = c(0, .10, .25, .50, .75, .80, .85, .90, .95, .975, .99, 1),
  na.rm = TRUE
)
cat("\n=== IN-CAMP CASELOAD PERCENTILES ===\n")
print(round(caseload_percentiles, 0))

cutoff_options <- tibble::tibble(
  rule = c(
    "Top decile (n ~ 8)",
    "Absolute > 1,000 hh",
    "Absolute > 2,000 hh (working default below)",
    "Absolute > 5,000 hh"
  ),
  threshold_hh = c(caseload_percentiles[["90%"]], 1000, 2000, 5000),
  n_flagged = c(
    sum(camp_sites$households_in_cluster > caseload_percentiles[["90%"]]),
    sum(camp_sites$households_in_cluster > 1000),
    sum(camp_sites$households_in_cluster > 2000),
    sum(camp_sites$households_in_cluster > 5000)
  )
)
cat("\n=== CUTOFF OPTIONS (for review - not fixed) ===\n")
print(cutoff_options)

# ---------------------------------------------------------------------------
# Working default for this pass: > 2,000 households. Large enough to focus
# on genuinely huge camps warranting individual imagery review (a costly,
# manual step - not something to run on all 81 sites), small enough to
# review one-by-one. Trivial to change: edit CASELOAD_CUTOFF_HH and rerun.
# ---------------------------------------------------------------------------
CASELOAD_CUTOFF_HH <- 2000

camp_sites <- camp_sites %>% mutate(flagged_camp = households_in_cluster > CASELOAD_CUTOFF_HH)

flagged <- camp_sites %>% filter(flagged_camp)
message(nrow(flagged), " camps flagged at the working >", CASELOAD_CUTOFF_HH, "hh cutoff.")

# ---------------------------------------------------------------------------
# 2. Query Google Open Buildings around each flagged camp's DTM point -
#    identical field-detection/filter logic (confidence >= 0.75, area
#    12-1000 sq m) as load_building_footprints() (02_stage2_building_ingestion.R),
#    just against a fresh ad hoc bounding box per camp instead of the
#    pre-selected Non-IDP cluster list that function was built for.
# ---------------------------------------------------------------------------
gdb_files <- list.dirs(building_data_dir, recursive = TRUE, full.names = TRUE) |>
  stringr::str_subset("\\.gdb$")
message(length(gdb_files), " Google Open Buildings GDB(s) found.")

query_radius_m <- 1500  # generous half-width around the DTM point

query_buildings_near_point <- function(lon, lat, radius_m) {
  pt_wgs84 <- sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326)
  pt_proj  <- sf::st_transform(pt_wgs84, mycrs)
  bbox_proj <- sf::st_buffer(pt_proj, radius_m) |> sf::st_bbox()
  bbox_wgs84 <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(bbox_proj, crs = mycrs), 4326))
  bbox_wkt <- sf::st_as_text(sf::st_as_sfc(bbox_wgs84))

  results <- purrr::map(gdb_files, function(gdb_path) {
    layers <- sf::st_layers(gdb_path)$name
    building_layer <- layers[stringr::str_detect(tolower(layers), "build")]
    if (length(building_layer) == 0) building_layer <- layers[1]
    building_layer <- building_layer[1]

    sample_row <- sf::st_read(gdb_path, query = paste0('SELECT * FROM "', building_layer, '" LIMIT 1'), quiet = TRUE)
    confidence_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("confidence", ignore_case = TRUE))][1]
    area_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("^area", ignore_case = TRUE))]
    has_area_field <- length(area_field) > 0
    area_field <- if (has_area_field) area_field[1] else NA_character_

    where_parts <- paste0('"', confidence_field, '" >= 0.75')
    if (has_area_field) {
      where_parts <- c(where_parts, paste0('"', area_field, '" >= 12'), paste0('"', area_field, '" <= 1000'))
    }
    where_clause <- paste(where_parts, collapse = " AND ")

    res <- tryCatch(
      sf::st_read(gdb_path, query = paste0('SELECT * FROM "', building_layer, '" WHERE ', where_clause),
                  wkt_filter = bbox_wkt, quiet = TRUE),
      error = function(e) NULL
    )
    if (is.null(res) || nrow(res) == 0) return(NULL)
    sf::st_geometry(res) <- sf::st_centroid(sf::st_geometry(res))
    res |> sf::st_transform(mycrs) |> select(geometry)
  })

  results <- results[!vapply(results, is.null, logical(1))]
  if (length(results) == 0) return(NULL)
  out <- dplyr::bind_rows(results)
  # de-duplicate near-identical centroids from overlapping GDB tile edges
  out[!duplicated(round(sf::st_coordinates(out), 0)), ]
}

footprint_summary <- vector("list", nrow(flagged))

for (i in seq_len(nrow(flagged))) {

  site <- flagged[i, ]
  message("\n[", i, "/", nrow(flagged), "] ", site$iom_site_name, " (", site$adm2_name, ", ", site$adm1_name, ") - ", site$households_in_cluster, " hh")

  bldg <- tryCatch(
    query_buildings_near_point(site$longitude, site$latitude, query_radius_m),
    error = function(e) { message("  Building query failed: ", conditionMessage(e)); NULL }
  )
  n_bldg <- if (is.null(bldg)) 0 else nrow(bldg)
  message("  Footprints within ", query_radius_m, "m: ", n_bldg)

  hull_area_ha <- NA_real_
  if (n_bldg >= 15) {
    hull <- sf::st_convex_hull(sf::st_union(bldg))
    hull_area_ha <- as.numeric(sf::st_area(hull)) / 1e4
    saveRDS(hull, here(review_dir, paste0(site$cluster_id, "_footprint_hull.rds")))
  }
  if (n_bldg > 0) saveRDS(bldg, here(review_dir, paste0(site$cluster_id, "_footprints.rds")))

  footprint_summary[[i]] <- tibble::tibble(
    cluster_id = site$cluster_id,
    n_footprints_1500m = n_bldg,
    footprint_hull_area_ha = hull_area_ha
  )

  # ---------------------------------------------------------------------
  # Satellite image crop for visual review - Esri.WorldImagery, identical
  # provider/zoom to the existing Non-IDP example-cluster maps
  # (08_render_methodology_maps.R). 2km x 2km box centred on the DTM
  # point, with the point marked, a scale bar, and (where found) the
  # queried building footprints overlaid, so visual size/offset estimates
  # in Part 2's review sheet can be read directly against the scale bar.
  # ---------------------------------------------------------------------
  pt_wgs84 <- sf::st_sfc(sf::st_point(c(site$longitude, site$latitude)), crs = 4326)
  pt_proj <- sf::st_transform(pt_wgs84, mycrs)
  img_extent <- sf::st_buffer(pt_proj, 1000) |> sf::st_transform(4326)

  basemap <- tryCatch(
    get_tiles_retry(img_extent, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE),
    error = function(e) { message("  Imagery fetch failed: ", conditionMessage(e)); NULL }
  )

  if (!is.null(basemap)) {
    pt_sf <- sf::st_sf(geometry = pt_wgs84)
    p <- ggplot() +
      tidyterra::geom_spatraster_rgb(data = basemap, maxcell = 2e6) +
      geom_sf(data = pt_sf, shape = 3, size = 5, stroke = 1.3, colour = "red") +
      geom_sf(data = pt_sf, shape = 1, size = 14, stroke = 1, colour = "red") +
      labs(title = paste0(site$iom_site_name, " - ", site$adm2_name, ", ", site$adm1_name),
           subtitle = paste0(site$households_in_cluster, " hh recorded | ", n_bldg, " OGB footprints within 1.5km | red = DTM point")) +
      map_theme() +
      theme(plot.title = element_text(size = 12, face = "bold", hjust = 0.5),
            plot.subtitle = element_text(size = 9.5, hjust = 0.5))

    if (n_bldg > 0) {
      p <- p + geom_sf(data = sf::st_transform(bldg, 4326), colour = "yellow", size = 0.4, alpha = 0.6)
    }

    ggsave(here(review_dir, paste0(site$cluster_id, "_review.png")), p, width = 7, height = 7.5, dpi = 130, bg = "white")
    message("  Wrote review image: ", site$cluster_id, "_review.png")
  }
}

footprint_summary <- dplyr::bind_rows(footprint_summary)

flagged_with_footprints <- flagged %>% left_join(footprint_summary, by = "cluster_id")

write_csv(camp_sites, here(analysis_dir, "camp_sites_all_ranked.csv"))
write_csv(flagged_with_footprints, here(analysis_dir, "flagged_camps_footprint_evidence.csv"))
saveRDS(list(camp_sites = camp_sites, flagged = flagged_with_footprints, cutoff_options = cutoff_options),
        here(analysis_dir, "part1_state.rds"))

cat("\n=== PART 1 COMPLETE ===\n")
cat("Flagged camps:", nrow(flagged), "of", n_total, "\n")
cat("Review images written to:", review_dir, "\n")
print(footprint_summary)
