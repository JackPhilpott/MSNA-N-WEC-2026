# ==============================================================================
# Render example cluster maps: hexagon boundary + building footprints +
# selected household points, on a satellite basemap. Fetches building
# POLYGONS fresh from the source GDBs for just the 2 example clusters
# (fast, tiny scope) since the main pipeline discards full polygon
# geometry early on for memory reasons and only keeps centroids.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
})

example_ids <- readRDS("output/example_cluster_ids.rds")

lines <- readLines("sampling_MSNA_NGA_2026_v3.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

households <- sf::st_read("output/stage2_sampling_frame.gpkg", quiet = TRUE)

reference_data_dir <- "C:/Users/JackPHILPOTT/Personal - Documents/GIS"
building_data_dir <- file.path(reference_data_dir, "Google_Open_Buildings")

source("02_building_ingestion.R")

render_cluster_map <- function(cluster_id_i, out_file, title_txt) {

  cat("Rendering:", cluster_id_i, "\n")

  hh <- households %>% filter(cluster_id == cluster_id_i)

  # Hexagon boundary: the merged cluster may combine repeated draws of the
  # same hexagon (all identical geometry), so any matching row's geometry
  # works - dedupe by uuid_hex_pop.
  hex <- selected_clusters %>%
    filter(cluster_id == cluster_id_i) %>%
    distinct(uuid_hex_pop, .keep_all = TRUE) %>%
    slice(1)

  if (nrow(hex) == 0) {
    cat("  Cluster not found in selected_clusters - skipping\n")
    return(invisible(NULL))
  }

  # Fresh, small-scope building polygon fetch for just this one cluster
  buildings_poly <- load_building_footprints(
    gdb_directory = building_data_dir,
    accessible_area = hex,
    mycrs = mycrs,
    cache_directory = file.path(output_dir, "cache", "map_examples", cluster_id_i),
    rebuild = TRUE
  )

  # buildings_poly is now a vector of file paths (points, not polygons) per
  # the current architecture - re-fetch polygons directly via a light GDAL
  # query instead, mirroring fetch_cluster()'s approach.
  hex_wgs84 <- sf::st_transform(hex, 4326)
  bbox_wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(hex_wgs84)))

  gdb_files <- list.dirs(building_data_dir, recursive = TRUE, full.names = TRUE) |>
    stringr::str_subset("\\.gdb$")

  poly_list <- purrr::map(gdb_files, function(gdb_path) {
    layers <- sf::st_layers(gdb_path)$name
    building_layer <- layers[stringr::str_detect(tolower(layers), "build")][1]
    tryCatch(
      sf::st_read(gdb_path, wkt_filter = bbox_wkt, quiet = TRUE) %>%
        sf::st_transform(mycrs) %>%
        sf::st_filter(sf::st_transform(hex, mycrs), .predicate = sf::st_intersects),
      error = function(e) NULL
    )
  })

  buildings_full <- dplyr::bind_rows(poly_list)

  hex_proj <- sf::st_transform(hex, mycrs)
  hex_wgs84_geom <- sf::st_transform(hex_proj, 4326)
  bbox_map <- sf::st_bbox(hex_wgs84_geom)
  pad <- 0.01
  bbox_map <- bbox_map + c(-pad, -pad, pad, pad)

  hh_wgs84 <- sf::st_transform(hh, 4326)
  buildings_wgs84 <- sf::st_transform(buildings_full, 4326)

  map_extent_sf <- sf::st_as_sfc(bbox_map, crs = 4326)

  basemap_tiles <- maptiles::get_tiles(
    map_extent_sf,
    provider = "Esri.WorldImagery",
    zoom = 17,
    crop = TRUE
  )

  p <- ggplot() +
    tidyterra::geom_spatraster_rgb(data = basemap_tiles, maxcell = 2e6) +
    geom_sf(data = buildings_wgs84, fill = NA, color = "#FFD700", linewidth = 0.35, alpha = 0.9) +
    geom_sf(data = hex_wgs84_geom, fill = NA, color = "#FF3B30", linewidth = 1.1) +
    geom_sf(data = hh_wgs84, aes(color = status, shape = status), size = 3, stroke = 1.2) +
    scale_color_manual(values = c(primary = "#00E5FF", reserve = "#FFFFFF"), name = "Household") +
    scale_shape_manual(values = c(primary = 16, reserve = 4), name = "Household") +
    coord_sf(xlim = c(bbox_map["xmin"], bbox_map["xmax"]), ylim = c(bbox_map["ymin"], bbox_map["ymax"]), expand = FALSE, crs = 4326) +
    labs(title = title_txt,
         subtitle = paste0(cluster_id_i, " | ", nrow(buildings_full), " eligible buildings | red = hexagon boundary, yellow = building footprints"),
         caption = "Basemap: Esri World Imagery") +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
      plot.subtitle = element_text(size = 9, color = "grey30", margin = margin(b = 8)),
      plot.caption = element_text(size = 7, color = "grey50"),
      legend.position = "bottom"
    )

  ggsave(out_file, p, width = 7, height = 7, dpi = 110, bg = "white")

  cat("  Saved:", out_file, "\n")

}

render_cluster_map(example_ids$host_id, "output/example_map_host.png", "Example Host Cluster")
render_cluster_map(example_ids$idp_id, "output/example_map_idp.png", "Example IDP Cluster")

cat("ALL DONE\n")
