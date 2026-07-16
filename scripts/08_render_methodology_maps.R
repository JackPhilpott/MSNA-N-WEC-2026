# ==============================================================================
# Round 2 of methodology maps:
#   1. National assessment-area overview: host population raster (gradient),
#      IOM DTM IDP sites (population-scaled points), and excluded
#      (inaccessible) areas overlaid.
#   2. Revised host example cluster - denser building footprints, bordered/
#      fillable markers with transparency so buildings show through.
#   3. New host close-up (mirrors the IDP close-up) - ground-level look at
#      the selected households against nearby buildings.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
  library(terra)
})

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

dir.create("output/images", showWarnings = FALSE)

households_all <- sf::st_read("output/stage2_sampling_frame.gpkg", quiet = TRUE)

# ---------------------------------------------------------------------------
# Map 1: national overview - population raster + IDP sites + excluded areas
# (unaffected by the Stage 2 building-consolidation fix - skip re-render if
# already produced)
# ---------------------------------------------------------------------------

admin1_focus <- NGA_shapes_all_cleaned$nga_admin1 %>%
  dplyr::filter(adm1_pcode %in% admin1_focus_areas)

admin1_focus_union <- sf::st_union(sf::st_make_valid(admin1_focus))

worldpop_focus <- terra::crop(worldpop_pop, terra::vect(admin1_focus))
worldpop_focus <- terra::mask(worldpop_focus, terra::vect(admin1_focus))
# Also mask out the excluded zone itself (border buffer + FACT inaccessible
# admin-3s) - accessible_area already = admin1 minus restricted, so this
# leaves population showing only within the actual sampling universe rather
# than bleeding through under the grey excluded-area overlay.
worldpop_focus <- terra::mask(worldpop_focus, terra::vect(sf::st_make_valid(accessible_area)))

restricted_focus <- sf::st_intersection(sf::st_make_valid(restricted), admin1_focus_union) %>%
  sf::st_make_valid()

accessible_area_focus <- sf::st_intersection(sf::st_make_valid(accessible_area), admin1_focus_union) %>%
  sf::st_make_valid()

# IDP sites are kept only if they fall INSIDE the accessible area - a
# positive inclusion test against accessible_area_focus, matching how the
# host population raster is now masked, rather than a "disjoint from the
# excluded zone" test (which would incorrectly keep a site that's outside
# the excluded zone but also outside the accessible area entirely).
idp_sites_focus <- iom_idp_df %>%
  dplyr::filter(!is.na(individuals), individuals > 0) %>%
  sf::st_transform(sf::st_crs(accessible_area_focus)) %>%
  sf::st_filter(accessible_area_focus, .predicate = sf::st_within)

p_overview2 <- ggplot() +
  tidyterra::geom_spatraster(data = worldpop_focus, maxcell = 3e6) +
  scale_fill_gradientn(
    colors = c("#FFFFFF00", "#FFF2AE", "#FDB863", "#E08214", "#B2182B"),
    na.value = "transparent",
    trans = "log1p",
    name = "Host population\nper grid cell"
  ) +
  geom_sf(data = restricted_focus, aes(color = "Excluded from sampling\nuniverse (border buffer +\ninaccessible admin-3s)"), fill = "grey25", alpha = 0.65, linewidth = 0.3) +
  scale_color_manual(
    values = c("Excluded from sampling\nuniverse (border buffer +\ninaccessible admin-3s)" = "grey25"),
    name = NULL,
    guide = guide_legend(override.aes = list(fill = "grey25", alpha = 0.65, linewidth = 0))
  ) +
  geom_sf(data = admin1_focus, fill = NA, color = "grey15", linewidth = 0.3) +
  geom_sf(data = idp_sites_focus, aes(size = individuals), color = "#1B6FA8", alpha = 0.8, shape = 16) +
  scale_size_continuous(range = c(0.4, 5), name = "IDP site\npopulation") +
  labs(
    title = "Assessment area: host population, IDP sites, and excluded areas",
    subtitle = paste0(
      nrow(admin1_focus), " states across NW/NE/NC Nigeria | ",
      nrow(idp_sites_focus), " IOM DTM sites"
    ),
    caption = "Excluded area = 20km buffer along the Niger border, 5km along Chad/Cameroon/Benin, plus FACT-assessed inaccessible admin-3 areas (North-East only)"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 10, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 8, color = "grey40", margin = margin(t = 8)),
    legend.position = "right"
  )

ggsave("output/images/methodology_map_overview_v2.png", p_overview2, width = 10, height = 9, dpi = 130, bg = "white")
cat("Saved overview v2 map\n")

# ---------------------------------------------------------------------------
# Shared: fetch fresh building POLYGONS for a single cluster (mirrors
# archive/render_example_maps.R's approach - the main pipeline only keeps
# centroids)
# ---------------------------------------------------------------------------

source("scripts/02_stage2_building_ingestion.R")

fetch_cluster_buildings <- function(hex_row) {

  hex_wgs84 <- sf::st_transform(hex_row, 4326)
  bbox_wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(hex_wgs84)))

  gdb_files <- list.dirs(building_data_dir, recursive = TRUE, full.names = TRUE) |>
    stringr::str_subset("\\.gdb$")

  poly_list <- purrr::map(gdb_files, function(gdb_path) {

    layers <- sf::st_layers(gdb_path)$name
    building_layer <- layers[stringr::str_detect(tolower(layers), "build")][1]

    sample_row <- sf::st_read(gdb_path, query = paste0('SELECT * FROM "', building_layer, '" LIMIT 1'), quiet = TRUE)

    confidence_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("confidence", ignore_case = TRUE))][1]
    area_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("^area", ignore_case = TRUE))]
    has_area_field <- length(area_field) > 0
    area_field <- if(has_area_field) area_field[1] else NA_character_

    where_parts <- paste0('"', confidence_field, '" >= 0.75')
    if(has_area_field) {
      where_parts <- c(where_parts, paste0('"', area_field, '" >= 12'), paste0('"', area_field, '" <= 1000'))
    }
    where_clause <- paste(where_parts, collapse = " AND ")

    tryCatch({
      result <- sf::st_read(
        gdb_path,
        query = paste0('SELECT * FROM "', building_layer, '" WHERE ', where_clause),
        wkt_filter = bbox_wkt,
        quiet = TRUE
      ) %>%
        sf::st_transform(mycrs) %>%
        sf::st_filter(sf::st_transform(hex_row, mycrs), .predicate = sf::st_intersects)

      if(!has_area_field) {
        result <- result %>%
          dplyr::mutate(building_area_m2 = as.numeric(sf::st_area(geometry))) %>%
          dplyr::filter(building_area_m2 <= 1000, building_area_m2 >= 12)
      }

      result
    }, error = function(e) NULL)

  })

  dplyr::bind_rows(poly_list)

}

# ---------------------------------------------------------------------------
# Map 2 + 3: revised host example - denser cluster, improved marker styling,
# plus a new close-up.
# ---------------------------------------------------------------------------

host_example_id <- "host_NG023010_1"

hh <- households_all %>% dplyr::filter(cluster_id == host_example_id)

hex <- selected_clusters %>%
  dplyr::filter(cluster_id == host_example_id) %>%
  dplyr::distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  dplyr::slice(1)

stopifnot(nrow(hex) == 1, nrow(hh) > 0)

buildings_full <- fetch_cluster_buildings(hex)

cat("Host example:", host_example_id, "-", nrow(buildings_full), "eligible buildings,", nrow(hh), "households\n")

hex_wgs84 <- sf::st_transform(hex, 4326)
buildings_wgs84 <- sf::st_transform(buildings_full, 4326)
hh_wgs84 <- sf::st_transform(hh, 4326)

marker_fill  <- c(primary = "#00E5FF", reserve = "#FFFFFF")
marker_color <- c(primary = "#0A3A46", reserve = "#111111")
marker_shape <- c(primary = 21, reserve = 24)

# ---- Map 2: full hexagon context, revised markers ----

bbox_hex <- sf::st_bbox(hex_wgs84)
pad_hex <- 0.01
bbox_hex <- bbox_hex + c(-pad_hex, -pad_hex, pad_hex, pad_hex)

map_extent_hex <- sf::st_as_sfc(bbox_hex, crs = 4326)

basemap_hex <- maptiles::get_tiles(map_extent_hex, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_host2 <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_hex, maxcell = 2e6) +
  geom_sf(data = buildings_wgs84, fill = NA, color = "#FFD700", linewidth = 0.3, alpha = 0.85) +
  geom_sf(data = hex_wgs84, fill = NA, color = "#FF3B30", linewidth = 1.1) +
  geom_sf(data = hh_wgs84, aes(fill = status, color = status, shape = status), size = 3.3, stroke = 1, alpha = 0.8) +
  scale_fill_manual(values = marker_fill, name = "Household") +
  scale_color_manual(values = marker_color, name = "Household") +
  scale_shape_manual(values = marker_shape, name = "Household") +
  coord_sf(xlim = c(bbox_hex["xmin"], bbox_hex["xmax"]), ylim = c(bbox_hex["ymin"], bbox_hex["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Example host cluster",
    subtitle = paste0(host_example_id, " | ", nrow(buildings_full), " eligible buildings | red = hexagon boundary, yellow = building footprints"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom"
  )

ggsave("output/images/methodology_map_host_v2.png", p_host2, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved host v2 map\n")

# ---- Map 3: close-up around the drawn households, buildings visible nearby ----

hh_proj <- sf::st_transform(hh, mycrs)
hh_bbox_proj <- sf::st_bbox(hh_proj)
pad_m <- 80

closeup_bbox_proj <- hh_bbox_proj + c(-pad_m, -pad_m, pad_m, pad_m)
closeup_extent_wgs84 <- sf::st_as_sfc(closeup_bbox_proj, crs = mycrs) %>% sf::st_transform(4326)
bbox_closeup_host <- sf::st_bbox(closeup_extent_wgs84)

basemap_closeup_host <- maptiles::get_tiles(closeup_extent_wgs84, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_host_closeup <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_closeup_host, maxcell = 2e6) +
  geom_sf(data = buildings_wgs84, fill = NA, color = "#FFD700", linewidth = 0.45, alpha = 0.9) +
  geom_sf(data = hh_wgs84, aes(fill = status, color = status, shape = status), size = 4.5, stroke = 1.2, alpha = 0.8) +
  scale_fill_manual(values = marker_fill, name = "Household") +
  scale_color_manual(values = marker_color, name = "Household") +
  scale_shape_manual(values = marker_shape, name = "Household") +
  coord_sf(xlim = c(bbox_closeup_host["xmin"], bbox_closeup_host["xmax"]), ylim = c(bbox_closeup_host["ymin"], bbox_closeup_host["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Close-up: selected households and nearby buildings",
    subtitle = paste0(host_example_id, " | yellow = eligible building footprints"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom"
  )

ggsave("output/images/methodology_map_host_closeup.png", p_host_closeup, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved host close-up map\n")

cat("ALL DONE\n")
