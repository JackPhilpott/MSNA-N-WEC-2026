# ==============================================================================
# One-off export of Stage 1 outputs (accessible area hexagon grid + selected
# cluster sampling frame) without running the heavy Stage 2 building
# ingestion. Sources only the main script up to the point where
# selected_clusters is computed (line found dynamically by anchor text).
# ==============================================================================

lines <- readLines("sampling_MSNA_NGA_2026_v3.R")

stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))

stopifnot(length(stop_idx) == 1)

writeLines(lines[1:stop_idx], "temp_stage1_only.R")

source("temp_stage1_only.R")


# ---- Export 1: accessible area hexagon grid, shapefile ----

sf::st_write(
  hex_access,
  here(output_dir, "hex_access.shp"),
  delete_dsn = TRUE,
  quiet = TRUE
)

message("Exported hex_access.shp: ", nrow(hex_access), " hexagons.")


# ---- Export 2: cluster-level sampling frame, CSV with WKT geometry ----

selected_clusters_export <-
  selected_clusters %>%
  dplyr::mutate(
    wkt_geometry = sf::st_as_text(geometry)
  ) %>%
  sf::st_drop_geometry()

readr::write_csv(
  selected_clusters_export,
  here(output_dir, "selected_clusters_sampling_frame.csv")
)

message("Exported selected_clusters_sampling_frame.csv: ", nrow(selected_clusters_export), " clusters.")

message("Stage 1 export complete.")
