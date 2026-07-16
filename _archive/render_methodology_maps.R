# ==============================================================================
# Render maps for the methodology summary document:
#   1. National overview - all 5,750 final selected clusters, coloured by
#      pop_type, over the 3-region admin1 boundary.
#   2. Updated IDP example - hexagon boundary (Stage 1 context) + DTM site
#      GPS point + 150m field radius, satellite basemap. Replaces the old
#      building-footprint IDP example map, which no longer reflects how IDP
#      Stage 2 actually works.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
})

lines <- readLines("sampling_MSNA_NGA_2026_v3.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

clusters_final <- readRDS("output/selected_clusters_final.rds")

# ---------------------------------------------------------------------------
# Map 1: national overview
# ---------------------------------------------------------------------------

cluster_points <- clusters_final %>%
  sf::st_centroid() %>%
  sf::st_transform(4326)

admin1_wgs84 <- sf::st_transform(NGA_shapes_all_cleaned$nga_admin1, 4326) %>%
  dplyr::filter(adm1_pcode %in% admin1_focus_areas)

p_overview <- ggplot() +
  geom_sf(data = admin1_wgs84, fill = "#EDEDE6", color = "#8A8A7E", linewidth = 0.3) +
  geom_sf(data = cluster_points, aes(color = pop_type), size = 0.55, alpha = 0.75) +
  scale_color_manual(
    values = c(host = "#2E6F8E", idp = "#C1502E"),
    labels = c(host = "Host", idp = "IDP"),
    name = "Cluster type"
  ) +
  labs(
    title = "Selected clusters across the assessment area",
    subtitle = paste0(nrow(clusters_final), " clusters — North-West, North-East, North-Central Nigeria")
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 10, color = "grey30", margin = margin(b = 8)),
    legend.position = "bottom"
  )

ggsave("output/methodology_map_overview.png", p_overview, width = 8, height = 8, dpi = 130, bg = "white")
cat("Saved overview map\n")

# ---------------------------------------------------------------------------
# Map 2: updated IDP example - hexagon + site point + 150m radius
# ---------------------------------------------------------------------------

example_cluster_id <- "idp_NG002002_12"

hex_context <- idp_clusters %>%
  dplyr::filter(cluster_id == example_cluster_id) %>%
  dplyr::distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  dplyr::slice(1)

site_row <- clusters_final %>%
  dplyr::filter(cluster_id == example_cluster_id)

stopifnot(nrow(hex_context) == 1, nrow(site_row) == 1)

hex_wgs84 <- sf::st_transform(hex_context, 4326)
site_wgs84 <- sf::st_transform(site_row, 4326)

site_proj <- sf::st_transform(site_row, mycrs)
radius_m <- site_row$site_radius_m[1]
site_buffer_wgs84 <- sf::st_buffer(site_proj, radius_m) %>% sf::st_transform(4326)

bbox_map <- sf::st_bbox(sf::st_transform(hex_context, 4326))
pad <- 0.01
bbox_map <- bbox_map + c(-pad, -pad, pad, pad)

map_extent_sf <- sf::st_as_sfc(bbox_map, crs = 4326)

basemap_tiles <- maptiles::get_tiles(
  map_extent_sf,
  provider = "Esri.WorldImagery",
  zoom = 16,
  crop = TRUE
)

site_name_lbl <- site_row$iom_site_name[1]
n_other <- site_row$n_other_sites_in_hex[1]

p_idp <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_tiles, maxcell = 2e6) +
  geom_sf(data = hex_wgs84, fill = NA, color = "#FF3B30", linewidth = 1.1) +
  geom_sf(data = site_buffer_wgs84, fill = "#00E5FF", color = "#00E5FF", alpha = 0.15, linewidth = 1) +
  geom_sf(data = site_wgs84, color = "#00E5FF", size = 4, shape = 16) +
  coord_sf(xlim = c(bbox_map["xmin"], bbox_map["xmax"]), ylim = c(bbox_map["ymin"], bbox_map["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "IDP cluster: site point + fixed radius",
    subtitle = paste0(
      example_cluster_id, " | ", site_name_lbl, " | red = Stage 1 hexagon | ",
      "cyan = site point + ", radius_m, "m radius",
      if(n_other > 0) paste0(" | ", n_other, " other site(s) also in this hexagon") else ""
    ),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50")
  )

ggsave("output/methodology_map_idp_site.png", p_idp, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved IDP site map\n")

# ---------------------------------------------------------------------------
# Map 2b: close-up of just the site + radius (150m is imperceptible against
# the ~5km hexagon at the zoom level above - a tight crop makes the radius
# actually legible).
# ---------------------------------------------------------------------------

site_pt_proj <- sf::st_transform(site_row, mycrs)
closeup_bbox_proj <- sf::st_bbox(sf::st_buffer(site_pt_proj, radius_m * 2.2))
closeup_extent_wgs84 <- sf::st_as_sfc(closeup_bbox_proj, crs = mycrs) %>% sf::st_transform(4326)
bbox_closeup <- sf::st_bbox(closeup_extent_wgs84)

basemap_closeup <- maptiles::get_tiles(
  closeup_extent_wgs84,
  provider = "Esri.WorldImagery",
  zoom = 17,
  crop = TRUE
)

p_idp_closeup <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_closeup, maxcell = 2e6) +
  geom_sf(data = site_buffer_wgs84, fill = "#00E5FF", color = "#00E5FF", alpha = 0.2, linewidth = 1.3) +
  geom_sf(data = site_wgs84, color = "#00E5FF", size = 5, shape = 16) +
  coord_sf(xlim = c(bbox_closeup["xmin"], bbox_closeup["xmax"]), ylim = c(bbox_closeup["ymin"], bbox_closeup["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Close-up: the 150m site radius",
    subtitle = paste0(example_cluster_id, " | ", site_name_lbl, " | cyan circle = 150m radius around the site GPS point"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50")
  )

ggsave("output/methodology_map_idp_site_closeup.png", p_idp_closeup, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved IDP site close-up map\n")

cat("ALL DONE\n")
