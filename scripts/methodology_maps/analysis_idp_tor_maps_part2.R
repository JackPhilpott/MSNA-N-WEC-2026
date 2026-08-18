# ==============================================================================
# New ToR figures replacing the outdated single 150m-radius IDP map -
# PART 2: render the IDP-in-host example (idp_NG021005_2, Rugar Tsara,
# Bindawa, Katsina - confirmed as the right site by the user), with a
# hand-delineated illustrative settlement boundary.
#
# v2 fixes, both per direct user feedback on the v1 render:
#  1. Wide view now shows the Stage 1 hexagon (PSU) boundary too, at the
#     same zoomed-out extent as the IDP-in-camp wide view - previously it
#     only showed a tight crop around the illustrative boundary itself.
#  2. The illustrative boundary rendered ~50m too far north relative to
#     the visible rooftop cluster in the v1 PNG (confirmed by comparing
#     the rendered image directly: boundary vertical centre sat ~90px
#     above the DTM point, while the buildings themselves are correctly
#     centred on the DTM point) - the hand-drawn SHAPE was right, this was
#     a rendering/estimation offset, not a re-draw. Likely cause: the
#     boundary vertices were originally eyeballed off a non-square
#     candidate review image (7in x 7.5in project onto a squarish geographic
#     extent), which can letterbox unevenly and throw off a pixel-based
#     read. Fixed here with an empirical constant shift (SHIFT_SOUTH_M),
#     not by re-deriving vertices from the flawed source image.
#
# The boundary itself is NOT derived from a footprint/imagery algorithm -
# it is a hand-specified irregular polygon (bearing/distance vertices from
# the DTM point), rendered dashed and explicitly labelled illustrative.
# This matches the actual host-community method: there is no GPS radius or
# footprint delineation behind it in the field, so the map must not imply
# one either.
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

get_tiles_retry <- function(..., max_attempts = 5, pause_s = 5) {
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(maptiles::get_tiles(...), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    message("get_tiles() attempt ", attempt, "/", max_attempts, " failed: ", conditionMessage(result))
    if (attempt < max_attempts) Sys.sleep(pause_s)
  }
  stop("get_tiles() failed after ", max_attempts, " attempts: ", conditionMessage(result))
}

MAP_B_SITE_ID <- "idp_NG021005_2"

# ---------------------------------------------------------------------------
# Load hex_grid_idp (Stage 1 IDP hexagons), same mechanism as the IDP-in-camp
# script and 08_render_methodology_maps.R - host-community IDP clusters are
# Stage 1 PPS hexagons too, same as camps and Non-IDP clusters.
# ---------------------------------------------------------------------------
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(non_idp_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only_hostb.R")
source("temp_stage1_only_hostb.R")

hex_b <- selected_clusters %>%
  filter(cluster_id == MAP_B_SITE_ID) %>%
  distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  slice(1)
stopifnot(nrow(hex_b) == 1)
hex_b_wgs84 <- st_transform(hex_b, 4326)

file.remove("temp_stage1_only_hostb.R")

host_flags <- read_csv(here(output_dir, "data", "supporting_analysis", "idp_host_feasibility", "idp_host_community_feasibility_flags.csv"), show_col_types = FALSE)
site_b <- host_flags %>% filter(cluster_id == MAP_B_SITE_ID)
stopifnot(nrow(site_b) == 1)

dtm_pt_b_wgs84 <- st_sfc(st_point(c(site_b$longitude, site_b$latitude)), crs = 4326)
dtm_pt_b_proj  <- st_transform(dtm_pt_b_wgs84, mycrs)
centre_xy <- st_coordinates(dtm_pt_b_proj)[1, ]

# ---------------------------------------------------------------------------
# Hand-eyeballed irregular boundary: bearing (deg, 0=N clockwise) / distance
# (m) vertices from the DTM point. Shape/proportions kept exactly as drawn -
# only a uniform southward shift is applied below to correct the v1
# rendering offset (see header note).
# ---------------------------------------------------------------------------
boundary_verts <- tibble::tribble(
  ~bearing_deg, ~dist_m,
  0,    260,
  30,   230,
  60,   150,
  90,    80,
  120,  100,
  150,  110,
  180,  115,
  210,  120,
  240,  140,
  270,  145,
  300,  190,
  330,  230
)

SHIFT_SOUTH_M <- 85  # empirical correction, see header note (tuned via test_shift_{75,100}.png comparison)

set.seed(2021)  # site-derived seed, purely for reproducible cosmetic jitter
jitter <- runif(nrow(boundary_verts), 0.92, 1.08)

boundary_xy <- boundary_verts %>%
  mutate(
    dist_jittered = dist_m * jitter,
    x = centre_xy["X"] + dist_jittered * sin(bearing_deg * pi / 180),
    y = centre_xy["Y"] + dist_jittered * cos(bearing_deg * pi / 180) - SHIFT_SOUTH_M
  )

boundary_coords <- rbind(as.matrix(boundary_xy[, c("x", "y")]), as.matrix(boundary_xy[1, c("x", "y")]))
boundary_poly_proj <- st_sfc(st_polygon(list(boundary_coords)), crs = mycrs)
boundary_poly_wgs84 <- st_transform(boundary_poly_proj, 4326)

# ---------------------------------------------------------------------------
# Shared legend: hexagon (as a linetype key, matching how the IDP-in-camp
# map keys its hexagon via colour, kept consistent here via colour too),
# DTM point, and the illustrative boundary all as one combined colour scale.
# ---------------------------------------------------------------------------
label_hex      <- "Stage 1 hexagon boundary"
label_dtm      <- "DTM point (informant-listing reference)"
label_boundary <- "Illustrative boundary – not a fixed radius or GPS-derived"

hex_sf_b      <- st_sf(label = label_hex, geometry = st_geometry(hex_b_wgs84))
dtm_sf_b      <- st_sf(label = label_dtm, geometry = dtm_pt_b_wgs84)
boundary_sf_b <- st_sf(label = label_boundary, geometry = boundary_poly_wgs84)

map_b_colors <- setNames(c("#FF3B30", "#FF3B30", "#1B6FA8"), c(label_hex, label_dtm, label_boundary))

# ==============================================================================
# Wide view - now hex-based extent, same convention as the IDP-in-camp map
# ==============================================================================

bbox_hex_b <- st_bbox(hex_b_wgs84)
pad_hex_b <- 0.006
bbox_hex_b <- bbox_hex_b + c(-pad_hex_b, -pad_hex_b, pad_hex_b, pad_hex_b)
wide_extent_wgs84 <- st_as_sfc(bbox_hex_b, crs = 4326)
bbox_wide_b <- st_bbox(wide_extent_wgs84)

basemap_wide_b <- get_tiles_retry(wide_extent_wgs84, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_idp_host_wide <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_wide_b, maxcell = 2e6) +
  geom_sf(data = hex_sf_b, aes(color = label), fill = NA, linewidth = 1.1) +
  geom_sf(data = boundary_sf_b, aes(color = label), fill = "#1B6FA8", alpha = 0.12, linewidth = 1.9, linetype = "dashed") +
  geom_sf(data = dtm_sf_b, aes(color = label), shape = 3, size = 3.2, stroke = 1.4) +
  scale_color_manual(values = map_b_colors, name = NULL) +
  coord_sf(xlim = c(bbox_wide_b["xmin"], bbox_wide_b["xmax"]), ylim = c(bbox_wide_b["ymin"], bbox_wide_b["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Example host-community IDP site",
    subtitle = paste0(
      site_b$iom_site_name, " (", site_b$adm2_name, ", ", site_b$adm1_name, ") | ",
      format(site_b$caseload_hh, big.mark = ","), " hh recorded"
    ),
    caption = "Basemap: Esri World Imagery. Dashed outline is illustrative only, sketched loosely against visible\nsettlement extent for this figure – field teams do not draw or use a boundary of any kind;\nlisting is bounded by informant social recognition, not geography."
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8), lineheight = 1.3),
    plot.caption = element_text(size = 6.5, color = "grey50", margin = margin(t = 6), lineheight = 1.3, hjust = 0),
    legend.position = "bottom",
    legend.text = element_text(size = 8),
    plot.margin = margin(t = 10, r = 10, b = 6, l = 10)
  )

ggsave(here(analysis_dir, "methodology_map_idp_host_v2.png"), p_idp_host_wide, width = 8, height = 8, dpi = 130, bg = "white")
message("Saved IDP-in-host (wide): methodology_map_idp_host_v2.png")

# ==============================================================================
# Close-up
# ==============================================================================

pad_m_close <- 60
bbox_close_proj <- st_bbox(boundary_poly_proj) + c(-pad_m_close, -pad_m_close, pad_m_close, pad_m_close)
close_extent_wgs84 <- st_as_sfc(bbox_close_proj, crs = mycrs) %>% st_transform(4326)
bbox_close_b <- st_bbox(close_extent_wgs84)

basemap_close_b <- get_tiles_retry(close_extent_wgs84, provider = "Esri.WorldImagery", zoom = 18, crop = TRUE)

p_idp_host_closeup <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_close_b, maxcell = 2e6) +
  geom_sf(data = boundary_sf_b, aes(color = label), fill = "#1B6FA8", alpha = 0.12, linewidth = 1.2, linetype = "dashed") +
  geom_sf(data = dtm_sf_b, aes(color = label), shape = 3, size = 6, stroke = 1.6) +
  scale_color_manual(values = map_b_colors, name = NULL) +
  coord_sf(xlim = c(bbox_close_b["xmin"], bbox_close_b["xmax"]), ylim = c(bbox_close_b["ymin"], bbox_close_b["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Close-up: illustrative settlement extent",
    subtitle = paste0(MAP_B_SITE_ID, " | boundary follows visible rooftop cluster only – not a survey or GPS boundary"),
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

ggsave(here(analysis_dir, "methodology_map_idp_host_closeup.png"), p_idp_host_closeup, width = 7, height = 7, dpi = 130, bg = "white")
message("Saved IDP-in-host (close-up): methodology_map_idp_host_closeup.png")

cat("\n=== PART 2 COMPLETE ===\n")
cat("IDP-in-host site:", MAP_B_SITE_ID, "-", site_b$iom_site_name, "\n")
