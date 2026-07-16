# ==============================================================================
# Standalone diagnostic (no live GDAL queries): identify zero-building
# clusters, split by certainty vs PPS stratum, and check each affected PPS
# stratum's candidate pool size - run this BEFORE the full reallocation to
# confirm the problem is sized as expected and every stratum has enough
# unselected hexagons to draw a replacement from.
#
# Reuses cached Stage 1 objects (host_sampling/idp_sampling/selected_clusters)
# and the cached Stage 2 output - does not recompute either.
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

source("02_building_ingestion.R")
source("03_household_selection.R")
source("04_cluster_reallocation.R")

nga_wards <- sf::st_read(
  here::here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

building_files <- load_building_footprints(
  gdb_directory = building_data_dir,
  accessible_area = selected_clusters,
  mycrs = mycrs,
  cache_directory = file.path(output_dir, "cache", "buildings"),
  rebuild = FALSE
)

stage2_households <- select_stage2_households(
  clusters = selected_clusters,
  building_files = building_files,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(output_dir, "cache", "stage2"),
  rebuild = FALSE
)

diag <- diagnose_zero_building_clusters(
  clusters = selected_clusters,
  host_sampling = host_sampling,
  idp_sampling = idp_sampling,
  stage2_households = stage2_households,
  m = 6
)

cat("\n=== DIAGNOSTIC SUMMARY ===\n")
cat("Total zero-building clusters:", nrow(diag$zero_building_clusters), "\n")
cat("Reallocatable (PPS stratum):", nrow(diag$pps_targets), "\n")
cat("NOT reallocatable (certainty stratum):", nrow(diag$certainty_unresolvable), "\n")

cat("\n=== POOL SIZES BY AFFECTED STRATUM ===\n")
print(diag$pool_sizes %>% arrange(pool_size))

cat("\nStrata with pool_size < n_needed (likely partial shortfall):\n")
print(diag$pool_sizes %>% filter(pool_size < n_needed))

saveRDS(diag, "output/reallocation_diagnostic.rds")

cat("\nDONE - saved output/reallocation_diagnostic.rds\n")
