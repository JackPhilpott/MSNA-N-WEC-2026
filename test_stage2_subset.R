# ==============================================================================
# Small-subset validation of:
#   1) the deduplication fix in 02_building_ingestion.R
#   2) 03_household_selection.R end-to-end (never yet run successfully,
#      since the full run crashed during building ingestion before Stage 2
#      was reached)
# Uses a representative subset (~30 clusters per pop_type x region) rather
# than the full 8717 clusters, to get a fast sanity check before committing
# to another long full run.
# ==============================================================================

lines <- readLines("sampling_MSNA_NGA_2026_v3.R")

stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(host_clusters, idp_clusters\\)",
  lines
))

stopifnot(length(stop_idx) == 1)

writeLines(lines[1:stop_idx], "temp_stage1_only.R")

source("temp_stage1_only.R")


set.seed(99)

test_clusters <-
  selected_clusters %>%
  dplyr::group_by(pop_type, region) %>%
  dplyr::slice_sample(n = 30) %>%
  dplyr::ungroup()

cat("Test subset:", nrow(test_clusters), "clusters\n")


reference_data_dir <- "C:/Users/JackPHILPOTT/Personal - Documents/GIS"
building_data_dir <- file.path(reference_data_dir, "Google_Open_Buildings")

source("02_building_ingestion.R")

test_building_files <- load_building_footprints(
  gdb_directory = building_data_dir,
  accessible_area = test_clusters,
  mycrs = mycrs,
  cache_directory = file.path(output_dir, "cache", "buildings_test"),
  rebuild = TRUE
)

cat("Test building files:", paste(test_building_files, collapse = ", "), "\n")
cat("Test buildings (post-dedup), per part:",
    paste(sapply(test_building_files, function(f) nrow(readRDS(f))), collapse = ", "), "\n")


source("03_household_selection.R")

nga_wards <- sf::st_read(
  here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

test_households <- select_stage2_households(
  clusters = test_clusters,
  building_files = test_building_files,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(output_dir, "cache", "stage2_test"),
  rebuild = TRUE
)

cat("Test households:", nrow(test_households), "\n")
cat("Status breakdown:\n")
print(table(test_households$status))
cat("Base weight summary:\n")
print(summary(test_households$base_weight))
cat("Understaffed clusters (unique):",
    length(unique(test_households$cluster_id[test_households$understaffed_cluster])), "\n")
cat("Duplicate survey_id check:", anyDuplicated(test_households$survey_id), "\n")
cat("NA adm3_pcode (GRID3, primary) check:", sum(is.na(test_households$adm3_pcode)), "of", nrow(test_households), "\n")
cat("admin3_source breakdown:\n")
print(table(test_households$admin3_source, useNA = "ifany"))
cat("NA admin3_cod_pcode (COD, secondary, NE-only expected) check:", sum(is.na(test_households$admin3_cod_pcode)), "of", nrow(test_households), "\n")
cat("admin3_cod_pcode non-NA by region:\n")
print(table(test_households$region, !is.na(test_households$admin3_cod_pcode)))

saveRDS(test_households, "output/cache/test_households_subset.rds")

cat("TEST COMPLETE\n")
