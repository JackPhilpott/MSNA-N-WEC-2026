# ==============================================================================
# Standalone validation of select_stage2_idp_sites() before wiring into the
# full pipeline run - reuses cached Stage 1 objects, no GDAL/building work
# involved at all so this should be fast.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(purrr)
})

lines <- readLines("sampling_MSNA_NGA_2026_v3.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

source("03_household_selection.R")
source("05_idp_site_assignment.R")

nga_wards <- sf::st_read(
  here::here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

cat("idp_clusters rows (raw PPS draws):", nrow(idp_clusters), "\n")
cat("distinct idp uuid_hex_pop:", n_distinct(idp_clusters$uuid_hex_pop), "\n")
cat("iom_idp_df rows:", nrow(iom_idp_df), "\n")

idp_result <- select_stage2_idp_sites(
  clusters = idp_clusters,
  iom_idp_df = iom_idp_df,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(output_dir, "cache", "idp_sites_test"),
  rebuild = TRUE
)

h <- idp_result$households

cat("\n=== RESULT SUMMARY ===\n")
cat("Total IDP household rows:", nrow(h), "\n")
cat("Duplicate survey_id:", anyDuplicated(h$survey_id), "\n")
cat("Distinct clusters:", n_distinct(h$cluster_id), "\n")
print(table(h$status))

cat("\n=== SAME-GPS-PER-CLUSTER CHECK ===\n")
gps_check <- h %>% sf::st_drop_geometry() %>% group_by(cluster_id) %>%
  summarise(n_distinct_points = n_distinct(paste(round(latitude,6), round(longitude,6))), .groups="drop")
print(table(gps_check$n_distinct_points))

cat("\n=== MULTI-SITE HEXAGONS ===\n")
multi <- idp_result$clusters_final %>% sf::st_drop_geometry() %>% filter(n_other_sites_in_hex > 0)
cat("Clusters with >1 site in hex:", nrow(multi), "of", nrow(idp_result$clusters_final), "\n")
print(head(multi %>% select(cluster_id, adm2_pcode, iom_site_name, n_other_sites_in_hex), 10))

cat("\n=== WEIGHT SANITY ===\n")
print(summary(h$base_weight))
print(summary(h$ssu_probability))
cat("below_target_cluster TRUE count:", sum(h$below_target_cluster), "of", nrow(h), "\n")

cat("\n=== COORDINATE SANITY ===\n")
cat("Longitude range:", range(h$longitude, na.rm=TRUE), "\n")
cat("Latitude range:", range(h$latitude, na.rm=TRUE), "\n")
cat("NA coords:", sum(is.na(h$longitude) | is.na(h$latitude)), "\n")

cat("\nDONE\n")
