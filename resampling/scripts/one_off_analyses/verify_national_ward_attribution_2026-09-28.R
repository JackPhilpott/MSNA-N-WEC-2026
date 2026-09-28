# ==============================================================================
# Full national follow-up to verify_monguno_ward_attribution_2026-09-28_v2_
# clean.R (Jack's ask, via Coordinator, 2026-09-28 morning - not urgent, but
# thorough/complete, no sampling): geometric verification of adm3_name
# against the REAL ward boundary shapefile for every WORKING row, not a
# spot-check. Same method as the v2 clean Monguno re-run - join columns
# renamed to rule out any status.x/status.y-style collision, checked
# against 100% of rows with usable coordinates. Read-only on the frame,
# writes only to its own output folder.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
sf::sf_use_s2(TRUE)

OUT <- "resampling/output/national_ward_attribution_check_2026-09-28"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

t0 <- Sys.time()
cat("Loading GRID3 ward boundary shapefile...\n")
wards <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>%
  st_transform(4326) %>%
  select(true_wardname = wardname, true_lganame = lganame, true_statename = statename)
cat("  ", nrow(wards), "ward polygons loaded.\n")

cat("Loading WORKING frame...\n")
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE) %>%
  select(survey_id, cluster_id, pop_type, adm1_name, adm2_name, adm3_name, admin3_cod_name, latitude, longitude)
cat("  ", nrow(working), "WORKING rows loaded.\n")

n_no_coord <- sum(is.na(working$latitude) | is.na(working$longitude))
cat("  ", n_no_coord, "row(s) with missing lat/lon - excluded from the geometric check, reported separately.\n")

usable <- working %>% filter(!is.na(latitude), !is.na(longitude))
cat("\nRunning point-in-polygon join for", nrow(usable), "points (this is the long step, national scale)...\n")
pts <- usable %>% st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
joined <- st_join(pts, wards, join = st_within) %>% st_drop_geometry()
cat("  Join complete in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min.\n")

# ---- Results ----
joined <- joined %>%
  mutate(
    join_failed = is.na(true_wardname),
    matches_adm3 = !join_failed & (adm3_name == true_wardname),
    matches_cod  = !join_failed & !is.na(admin3_cod_name) & (admin3_cod_name == true_wardname)
  )

n_total <- nrow(joined)
n_join_failed <- sum(joined$join_failed)
n_match <- sum(joined$matches_adm3)
n_mismatch <- sum(!joined$join_failed & !joined$matches_adm3)

cat("\n==== NATIONAL RESULT ====\n")
cat(sprintf("Total WORKING rows: %d\n", nrow(working)))
cat(sprintf("  Missing lat/lon (not geometrically checkable): %d\n", n_no_coord))
cat(sprintf("  Checked (usable coordinates): %d\n", n_total))
cat(sprintf("    Join failed (point outside every ward polygon in the shapefile): %d (%.2f%%)\n", n_join_failed, 100 * n_join_failed / n_total))
cat(sprintf("    adm3_name MATCHES true geometry: %d (%.2f%% of checked)\n", n_match, 100 * n_match / n_total))
cat(sprintf("    adm3_name MISMATCHES true geometry (real problem if any): %d (%.2f%% of checked)\n", n_mismatch, 100 * n_mismatch / n_total))

write_csv(joined, file.path(OUT, "national_ward_attribution_full_result.csv"))

if (n_join_failed > 0) {
  jf <- joined %>% filter(join_failed) %>% count(adm1_name, adm2_name, adm3_name, sort = TRUE)
  write_csv(jf, file.path(OUT, "join_failed_by_lga_ward.csv"))
  cat("\nJoin-failed rows by (state, LGA, adm3_name) - top 20:\n")
  print(head(as.data.frame(jf), 20))
}

if (n_mismatch > 0) {
  mm <- joined %>% filter(!join_failed, !matches_adm3)
  mm_by_cluster <- mm %>% count(adm1_name, adm2_name, adm3_name, true_wardname, cluster_id, sort = TRUE)
  write_csv(mm, file.path(OUT, "real_adm3_name_mismatches_ALL_ROWS.csv"))
  write_csv(mm_by_cluster, file.path(OUT, "real_adm3_name_mismatches_by_cluster.csv"))
  cat("\n*** REAL adm3_name mismatches found - by (state, LGA, claimed ward, true ward, cluster) - top 30: ***\n")
  print(head(as.data.frame(mm_by_cluster), 30))
} else {
  cat("\nNo real adm3_name mismatches found - adm3_name matches true geometry for every row where the join succeeded.\n")
}

cat("\nWrote full result to", OUT, "\n")
cat(sprintf("\nTotal wall time: %.1f min\n", difftime(Sys.time(), t0, units = "mins")))
cat("==== DONE ====\n")
