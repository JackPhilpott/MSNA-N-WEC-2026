suppressMessages(library(dplyr))

h <- readr::read_csv("output/stage2_sampling_frame.csv", show_col_types = FALSE)

cat("=== ROW COUNTS ===\n")
cat("Total rows:", nrow(h), "\n")
cat("Duplicate survey_id count:", sum(duplicated(h$survey_id)), "\n")
print(table(h$status))
print(table(h$pop_type))

cat("\n=== HOUSEHOLDS PER CLUSTER (primary only) ===\n")
primary_per_cluster <- h %>% filter(status == "primary") %>% count(cluster_id)
print(table(primary_per_cluster$n))

cat("\n=== UNDERSTAFFED CLUSTERS ===\n")
understaffed <- h %>% filter(understaffed_cluster) %>% distinct(cluster_id, households_in_cluster, target_households)
cat("Count of understaffed clusters:", nrow(understaffed), "\n")
cat("Total clusters represented in output:", n_distinct(h$cluster_id), "\n")

cat("\n=== REALLOCATION ===\n")
cat("Reallocated clusters (households drawn from a substituted hexagon):", sum(h$reallocated, na.rm = TRUE) > 0, "\n")
reallocated_clusters <- h %>% dplyr::filter(reallocated) %>% dplyr::distinct(cluster_id)
cat("Reallocated cluster count:", nrow(reallocated_clusters), "\n")

unresolved_path <- "output/reallocation_unresolved.csv"
if(file.exists(unresolved_path)) {
  unresolved <- readr::read_csv(unresolved_path, show_col_types = FALSE)
  cat("Unresolved zero-building clusters (could not be reallocated):", nrow(unresolved), "\n")
  print(table(unresolved$reason))
} else {
  cat("No reallocation_unresolved.csv found - either no reallocation was run, or none were unresolved.\n")
}

cat("\nRemaining zero-building clusters in final output (should be 0 for PPS-stratum clusters):\n")
# selected_clusters_final.rds is the authoritative post-reallocation cluster
# table (one row per final cluster) - compare against it rather than the
# stale pre-reallocation warning message.
clusters_final_path <- "output/selected_clusters_final.rds"
if(file.exists(clusters_final_path)) {
  clusters_final <- readRDS(clusters_final_path) %>% sf::st_drop_geometry()
  zero_building_final <- clusters_final$cluster_id[!clusters_final$cluster_id %in% h$cluster_id]
  cat("Count:", length(zero_building_final), "\n")
  if(length(zero_building_final) > 0) {
    print(clusters_final %>% dplyr::filter(cluster_id %in% zero_building_final) %>% dplyr::select(cluster_id, pop_type, adm2_pcode, certainty_stratum))
  }
} else {
  cat("output/selected_clusters_final.rds not found - cannot verify.\n")
}

cat("\n=== IDP SITE ASSIGNMENT ===\n")
idp_rows <- h %>% filter(pop_type == "idp")
cat("IDP rows:", nrow(idp_rows), "using location_source:\n")
print(table(idp_rows$location_source, useNA = "ifany"))

cat("\nSame-GPS-point-per-cluster check (should be exactly 1 distinct lat/lon per cluster):\n")
gps_per_cluster <- idp_rows %>% group_by(cluster_id) %>% summarise(n_distinct_points = n_distinct(paste(latitude, longitude)), .groups = "drop")
print(table(gps_per_cluster$n_distinct_points))

cat("\nsite_radius_m used:\n")
print(table(idp_rows$site_radius_m, useNA = "ifany"))

multi_site_clusters <- idp_rows %>% distinct(cluster_id, n_other_sites_in_hex) %>% filter(n_other_sites_in_hex > 0)
cat("\nClusters whose hexagon contained more than one IOM DTM site (largest used):", nrow(multi_site_clusters), "\n")

cat("\nhouseholds_in_cluster_source by pop_type:\n")
print(table(h$pop_type, h$households_in_cluster_source))

cat("\n=== WEIGHTS ===\n")
print(summary(h$base_weight))
print(summary(h$psu_probability))
print(summary(h$ssu_probability))

cat("\n=== ADMIN3 COVERAGE ===\n")
cat("NA adm3_pcode (GRID3 primary):", sum(is.na(h$adm3_pcode)), "of", nrow(h), "\n")
print(table(h$admin3_source, useNA = "ifany"))
cat("NA admin3_cod_pcode (secondary):", sum(is.na(h$admin3_cod_pcode)), "of", nrow(h), "\n")
print(table(h$region, !is.na(h$admin3_cod_pcode)))

cat("\n=== GEOGRAPHIC SPREAD ===\n")
print(table(h$region))
print(table(h$region, h$pop_type))

cat("\n=== COORDINATE SANITY ===\n")
cat("Longitude range:", range(h$longitude, na.rm=TRUE), "\n")
cat("Latitude range:", range(h$latitude, na.rm=TRUE), "\n")
cat("NA coordinates:", sum(is.na(h$longitude) | is.na(h$latitude)), "\n")

cat("\n=== CERTAINTY VS PPS ===\n")
print(table(h$selection_type))

cat("\nDONE\n")
