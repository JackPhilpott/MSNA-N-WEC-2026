# ==============================================================================
# IDP in-camp backup GPS point generation - PART 2: finalise camp extents
# (visual review + footprint evidence -> fixed-radius fallback where needed),
# draw one reproducible randomised backup point per flagged camp, produce
# the deliverable CSV/XLSX and a sanity-check map.
#
# Consumes:
#   - output/analysis_idp_camp_backup_points/part1_state.rds (all 81 camp
#     sites, ranked + flagged; footprint evidence for the 15 flagged camps)
#   - output/analysis_idp_camp_backup_points/manual_visual_review.csv
#     (hand-completed after visually reviewing each flagged camp's
#     satellite image against its building-footprint overlay - see
#     Part 1's review images and CLAUDE.md/this analysis's notes for the
#     reasoning behind each row)
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(tidyterra)
  library(ggspatial)
})

set.seed(1234)  # same seed convention as the main pipeline's Stage 1 draw

mycrs <- 31028
output_dir   <- here("output")
analysis_dir <- here(output_dir, "analysis_idp_camp_backup_points")
review_dir   <- here(analysis_dir, "camp_review_images")

# Fixed-radius fallback for camps where visual delineation failed - not
# calibrated per-camp (that's the point of it being a fallback), set to the
# middle of the range used across the successful visual delineations
# (140-380m) rather than an arbitrary round number.
FALLBACK_RADIUS_M <- 300

state <- readRDS(here(analysis_dir, "part1_state.rds"))
camp_sites <- state$camp_sites
flagged <- state$flagged

review <- read_csv(here(analysis_dir, "manual_visual_review.csv"), show_col_types = FALSE)

stopifnot(
  "Every flagged camp must have a review row" = all(flagged$cluster_id %in% review$cluster_id),
  "Review file should not have extra rows" = all(review$cluster_id %in% flagged$cluster_id)
)

flagged <- flagged %>% left_join(review, by = "cluster_id")

# ---------------------------------------------------------------------------
# Finalise extent (centre + radius, in the projected CRS) per flagged camp
# ---------------------------------------------------------------------------
flagged_proj <-
  flagged %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_transform(mycrs)

coords <- st_coordinates(flagged_proj)
flagged_proj <- flagged_proj %>%
  mutate(
    dtm_x = coords[, 1],
    dtm_y = coords[, 2],
    extent_delineation_failed = delineation_failed,
    final_radius_m = if_else(delineation_failed, FALLBACK_RADIUS_M, radius_m),
    final_centre_x = if_else(delineation_failed, dtm_x, dtm_x + coalesce(offset_east_m, 0)),
    final_centre_y = if_else(delineation_failed, dtm_y, dtm_y + coalesce(offset_north_m, 0)),
    extent_source_note = if_else(
      delineation_failed,
      paste0("Fixed-radius buffer fallback (", FALLBACK_RADIUS_M, "m) - satellite imagery reviewed but no ",
             "camp-specific structure confidently distinguishable from surrounding built-up area. ", visual_note),
      paste0("Imagery-delineated (Esri World Imagery, visual review vs. Google Open Buildings footprint overlay, ",
             confidence, " confidence): ", visual_note)
    )
  )

# ---------------------------------------------------------------------------
# Draw one reproducible random point per flagged camp, uniform over the
# extent circle's AREA (r = R*sqrt(u), not r = R*u, which would bias points
# toward the centre)
# ---------------------------------------------------------------------------
n_flagged <- nrow(flagged_proj)
theta <- runif(n_flagged, 0, 2 * pi)
u <- runif(n_flagged)
r <- flagged_proj$final_radius_m * sqrt(u)

flagged_proj <- flagged_proj %>%
  mutate(
    backup_x = final_centre_x + r * cos(theta),
    backup_y = final_centre_y + r * sin(theta)
  )

backup_pts_wgs84 <-
  flagged_proj %>%
  st_drop_geometry() %>%
  select(cluster_id, backup_x, backup_y) %>%
  st_as_sf(coords = c("backup_x", "backup_y"), crs = mycrs) %>%
  st_transform(4326) %>%
  mutate(backup_gps_lon = st_coordinates(.)[, 1], backup_gps_lat = st_coordinates(.)[, 2]) %>%
  st_drop_geometry()

flagged_final <- flagged_proj %>% st_drop_geometry() %>% left_join(backup_pts_wgs84, by = "cluster_id")

# ---------------------------------------------------------------------------
# Assemble deliverable: every in-camp site, backup fields populated only
# for flagged camps
# ---------------------------------------------------------------------------
deliverable <-
  camp_sites %>%
  left_join(
    flagged_final %>%
      select(cluster_id, extent_delineation_failed, backup_gps_lat, backup_gps_lon, extent_source_note),
    by = "cluster_id"
  ) %>%
  transmute(
    site_id = cluster_id,
    iom_site_id, iom_site_name, iom_site_type, iom_site_ward,
    region, adm1_name, adm2_name,
    households_in_cluster,
    dtm_gps_lat = latitude,
    dtm_gps_lon = longitude,
    flagged_camp,
    backup_gps_lat,
    backup_gps_lon,
    extent_delineation_failed,
    extent_source_note
  )

write_csv(deliverable, here(analysis_dir, "idp_camp_backup_points.csv"))

xlsx_ok <- requireNamespace("openxlsx", quietly = TRUE)
if (xlsx_ok) {
  openxlsx::write.xlsx(deliverable, here(analysis_dir, "idp_camp_backup_points.xlsx"), overwrite = TRUE)
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
n_total_camps <- nrow(camp_sites)
n_flagged_out <- sum(deliverable$flagged_camp)
n_delin_ok <- sum(!flagged_final$extent_delineation_failed)
n_delin_failed <- sum(flagged_final$extent_delineation_failed)

cat("\n=== SUMMARY ===\n")
cat("Total in-camp IDP sites:", n_total_camps, "\n")
cat("Flagged (largest) camps:", n_flagged_out, sprintf("(%.1f%%)\n", 100 * n_flagged_out / n_total_camps))
cat("  - Extent delineated from imagery:", n_delin_ok, "\n")
cat("  - Fell back to fixed-radius buffer:", n_delin_failed, "\n")

cat("\nBy state (flagged camps):\n")
print(flagged_final %>% count(adm1_name, sort = TRUE))

# ---------------------------------------------------------------------------
# Sanity-check maps: DTM point vs. extent vs. backup point, for a few
# example camps spanning the success/fallback split
# ---------------------------------------------------------------------------
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
  list(theme_void(),
       annotation_scale(location = "br", text_cex = 0.9),
       annotation_north_arrow(location = "tl", height = unit(0.9, "cm"), width = unit(0.9, "cm")))
}

example_ids <- c(
  "idp_NG008013_17",  # highest-confidence delineation
  "idp_NG008025_1",   # high-confidence, offset centre
  "idp_NG008013_7"    # fallback buffer example
)

for (cid in example_ids) {
  site <- flagged_final %>% filter(cluster_id == cid)
  if (nrow(site) == 0) next

  centre_wgs84 <- st_as_sf(data.frame(x = site$final_centre_x, y = site$final_centre_y), coords = c("x", "y"), crs = mycrs) %>%
    st_transform(4326)
  extent_circle <- st_buffer(st_transform(centre_wgs84, mycrs), site$final_radius_m) %>% st_transform(4326)
  dtm_pt <- st_sfc(st_point(c(site$longitude, site$latitude)), crs = 4326)
  backup_pt <- st_sfc(st_point(c(site$backup_gps_lon, site$backup_gps_lat)), crs = 4326)

  img_extent <- st_buffer(st_transform(dtm_pt, mycrs), max(site$final_radius_m + 200, 500)) %>% st_transform(4326)
  basemap <- tryCatch(get_tiles_retry(img_extent, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE), error = function(e) NULL)
  if (is.null(basemap)) next

  p <- ggplot() +
    tidyterra::geom_spatraster_rgb(data = basemap, maxcell = 2e6) +
    geom_sf(data = st_sf(geometry = extent_circle), fill = NA, colour = "cyan", linewidth = 1) +
    geom_sf(data = st_sf(geometry = dtm_pt), shape = 3, size = 5, stroke = 1.4, colour = "red") +
    geom_sf(data = st_sf(geometry = backup_pt), shape = 17, size = 4, colour = "orange") +
    labs(
      title = paste0(site$iom_site_name, " - ", site$adm2_name, ", ", site$adm1_name),
      subtitle = paste0(
        format(site$households_in_cluster, big.mark = ","), " hh | ",
        if (site$extent_delineation_failed) "fixed-buffer fallback" else paste0(site$confidence, "-confidence delineation"),
        "\nred + = DTM point (Method 1)   orange ▲ = backup point (Method 2)   cyan = extent used"
      )
    ) +
    map_theme() +
    theme(plot.title = element_text(size = 13, face = "bold", hjust = 0.5),
          plot.subtitle = element_text(size = 9, hjust = 0.5, lineheight = 1.3))

  ggsave(here(analysis_dir, paste0("example_", cid, ".png")), p, width = 8.5, height = 8.2, dpi = 130, bg = "white")
  message("Wrote example map: example_", cid, ".png")
}

cat("\nWrote:", here(analysis_dir, "idp_camp_backup_points.csv"), "\n")
if (xlsx_ok) cat("Wrote:", here(analysis_dir, "idp_camp_backup_points.xlsx"), "\n")
cat("\n=== PART 2 COMPLETE ===\n")
