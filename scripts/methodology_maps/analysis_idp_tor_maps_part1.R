# ==============================================================================
# New ToR figures replacing the outdated single 150m-radius IDP map -
# PART 1: render the IDP-in-camp example (idp_NG008013_17, Shuwari-Kaleri
# Housing Unit Camp, Jere, Borno).
#
# Standalone pre-fieldwork analysis (NOT part of the numbered 00-08
# pipeline, does not modify the frozen sampling frame). Style matches the
# real Figure 4 convention (methodology_map_non_idp_v2.png in
# 08_render_methodology_maps.R): bold in-image title + grey subtitle,
# legend along the bottom - not Figure 1's boxed side-panel convention.
#
# v3: reverted to the original site pick after trying two clean-hexagon
# alternatives (Gssss Camp Bama, GGSS Mafa) per user feedback - neither
# matched Shuwari-Kaleri's quality as an illustration (Bama's camp blends
# into the edge of Bama town at this zoom and its 35,519hh caseload looks
# like a data outlier; Mafa's camp is contiguous with surrounding town on
# one side). Shuwari-Kaleri's Stage 1 hexagon is genuinely admin2-boundary-
# clipped (15 vertices, 17.2km2, confirmed against hex_access directly -
# not a plotting bug), which the user has explicitly accepted and prefers
# to explain rather than swap sites over, since the camp itself fills the
# frame far more cleanly than either alternative.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
})

mycrs <- 31028

output_dir   <- here("output")
analysis_dir <- here(output_dir, "maps")
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

get_tiles_retry <- function(..., max_attempts = 5, pause_s = 5) {
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(maptiles::get_tiles(...), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    message("get_tiles() attempt ", attempt, "/", max_attempts, " failed: ", conditionMessage(result))
    if (attempt < max_attempts) Sys.sleep(pause_s)
  }
  stop("get_tiles() failed after ", max_attempts, " attempts: ", conditionMessage(result))
}

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(non_idp_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

camp_backup_pts <- read_csv(here(output_dir, "data", "data_collection", "idp_camp_backup_points.csv"), show_col_types = FALSE)

MAP_A_SITE_ID <- "idp_NG008013_17"  # Shuwari-Kaleri Housing Unit Camp, Jere, Borno

site_a <- camp_backup_pts %>% filter(site_id == MAP_A_SITE_ID)
stopifnot(nrow(site_a) == 1, site_a$flagged_camp, !is.na(site_a$backup_gps_lat))

hex_a <- selected_clusters %>%
  filter(cluster_id == MAP_A_SITE_ID) %>%
  distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  slice(1)
stopifnot(nrow(hex_a) == 1)

hex_a_wgs84 <- st_transform(hex_a, 4326)
dtm_pt_a    <- st_sfc(st_point(c(site_a$dtm_gps_lon, site_a$dtm_gps_lat)), crs = 4326)
backup_pt_a <- st_sfc(st_point(c(site_a$backup_gps_lon, site_a$backup_gps_lat)), crs = 4326)

point_labels_a <- c(dtm = "DTM point (Tier 1 listing)", backup = "Backup point (Tier 2 fallback only)")
points_a <- st_sf(
  point_type = factor(c(point_labels_a[["dtm"]], point_labels_a[["backup"]]), levels = point_labels_a),
  geometry   = c(dtm_pt_a, backup_pt_a)
)
marker_shape_a <- setNames(c(3, 17), point_labels_a)
marker_color_a <- setNames(c("#FF3B30", "#FFA500"), point_labels_a)
marker_size_a  <- setNames(c(5, 4.2), point_labels_a)

# ---- Wide view: full hexagon context ----
bbox_hex_a <- st_bbox(hex_a_wgs84)
pad_hex_a <- 0.006
bbox_hex_a <- bbox_hex_a + c(-pad_hex_a, -pad_hex_a, pad_hex_a, pad_hex_a)
map_extent_hex_a <- st_as_sfc(bbox_hex_a, crs = 4326)

basemap_hex_a <- get_tiles_retry(map_extent_hex_a, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_idp_camp_wide <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_hex_a, maxcell = 2e6) +
  geom_sf(data = hex_a_wgs84, fill = NA, color = "#FF3B30", linewidth = 1.1) +
  geom_sf(data = points_a, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.4) +
  scale_shape_manual(values = marker_shape_a, name = NULL) +
  scale_color_manual(values = marker_color_a, name = NULL) +
  scale_size_manual(values = marker_size_a, name = NULL, guide = "none") +
  coord_sf(xlim = c(bbox_hex_a["xmin"], bbox_hex_a["xmax"]), ylim = c(bbox_hex_a["ymin"], bbox_hex_a["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Example in-camp IDP cluster",
    subtitle = paste0(
      site_a$iom_site_name, " (", site_a$adm2_name, ", ", site_a$adm1_name, ") | ",
      format(site_a$households_in_cluster, big.mark = ","), " hh recorded | red = Stage 1 hexagon boundary\n",
      "(clipped to the admin-2 boundary near this site, hence the irregular shape)"
    ),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8), lineheight = 1.3),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom",
    plot.margin = margin(t = 10, r = 10, b = 6, l = 10)
  )

ggsave(here(analysis_dir, "methodology_map_idp_camp_v2.png"), p_idp_camp_wide, width = 7, height = 7.3, dpi = 130, bg = "white")
message("Saved IDP-in-camp (wide): methodology_map_idp_camp_v2.png")

# ---- Close-up: both points, tight crop ----
pts_proj_a <- st_transform(points_a, mycrs)
bbox_pts_proj_a <- st_bbox(pts_proj_a)
pad_m_a <- 120
closeup_bbox_proj_a <- bbox_pts_proj_a + c(-pad_m_a, -pad_m_a, pad_m_a, pad_m_a)
closeup_extent_wgs84_a <- st_as_sfc(closeup_bbox_proj_a, crs = mycrs) %>% st_transform(4326)
bbox_closeup_a <- st_bbox(closeup_extent_wgs84_a)

basemap_closeup_a <- get_tiles_retry(closeup_extent_wgs84_a, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_idp_camp_closeup <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_closeup_a, maxcell = 2e6) +
  geom_sf(data = points_a, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6) +
  scale_shape_manual(values = marker_shape_a, name = NULL) +
  scale_color_manual(values = marker_color_a, name = NULL) +
  scale_size_manual(values = c(7, 6), name = NULL, guide = "none") +
  coord_sf(xlim = c(bbox_closeup_a["xmin"], bbox_closeup_a["xmax"]), ylim = c(bbox_closeup_a["ymin"], bbox_closeup_a["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Close-up: DTM point vs. backup point",
    subtitle = paste0(MAP_A_SITE_ID, " | backup point used only if the Tier 2 fallback walk is triggered"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom",
    plot.margin = margin(t = 10, r = 10, b = 6, l = 10)
  )

ggsave(here(analysis_dir, "methodology_map_idp_camp_closeup.png"), p_idp_camp_closeup, width = 7, height = 7, dpi = 130, bg = "white")
message("Saved IDP-in-camp (close-up): methodology_map_idp_camp_closeup.png")

cat("\nIDP-in-camp site:", MAP_A_SITE_ID, "-", site_a$iom_site_name, "\n")
cat("  Extent source note:", site_a$extent_source_note, "\n")

file.remove("temp_stage1_only.R")

cat("\n=== PART 1 COMPLETE ===\n")
