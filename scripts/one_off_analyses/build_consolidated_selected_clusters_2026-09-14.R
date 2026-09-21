# ==============================================================================
# Re-run of build_consolidated_selected_clusters_2026-09-07.R against the
# CURRENT (v8) frame - same root-cause class the 2026-09-07 version's own
# header describes: the v7->v8 version-bump sed sweep earlier tonight
# renamed build_cluster_maps_production.R's reference from
# "selected_clusters_v7_current.rds" to "selected_clusters_v8_current.rds"
# (a purely mechanical find/replace, correct for the ~34 other files it
# touched), but nothing ever regenerated the underlying v8 artifact under
# that new name - this file has always had to be rebuilt by hand after a
# version bump, not renamed. Caught immediately (build_cluster_maps_
# production.R crashed outright, "cannot open the connection") when
# resuming the comprehensive cluster-field-guide sweep tonight, before any
# partner-facing output was affected.
#
# Also found and fixed here, NOT just a v8 re-point: Stage B's glob only
# ever matched "new_clusters_non_idp.gpkg" / "new_clusters_idp.gpkg" - but
# checked directly against what's actually on disk, the Non-IDP file has
# been written as the BARE name "new_clusters.gpkg" (no "_non_idp" infix)
# for essentially every batch since 2026-09-02 (the "_non_idp" suffix only
# ever appears in 6 files, all dated 2026-08-30/08-31). This means both the
# 2026-09-01 AND 2026-09-07 versions of this script silently missed nearly
# every Non-IDP geometry batch drawn all week, including tonight's -
# confirmed by inspecting resampling/output/resample_runs/FACT/2026-09-14_
# combined/new_clusters.gpkg directly (111 rows, pop_type=="non_idp"
# uniformly, has uuid_hex) before trusting this read. Not a bug introduced
# tonight - a pre-existing gap in this consolidation mechanism, caught now
# because tonight's version bump forced a full rebuild rather than another
# silent stale-file substitution. Fixed by widening the glob to
# "new_clusters(_non_idp|_idp)?\\.gpkg$", which now also matches the bare
# form to name.
# ==============================================================================
suppressMessages({
  library(dplyr)
  library(sf)
  library(readr)
  library(purrr)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

sf::sf_use_s2(FALSE)

log_con <- file("output/gis/_consolidated_clusters_build_log_2026-09-14.txt", open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Build consolidated selected-clusters geometry (v8 re-run) - %s ====", format(Sys.time()))

standardize_geom <- function(x, source_label) {
  # Site-level IDP draws (the 2026-09-02 IDP PSU redesign) have no uuid_hex
  # column - keyed by cluster_id directly. Skip cleanly, same as 09-07 -
  # build_cluster_maps_production.R's own uuid_hex_lookup degrades these to
  # has_hex=FALSE regardless of whether they appear here.
  if (!"uuid_hex" %in% names(x)) {
    log_msg("  SKIPPING (no uuid_hex column - likely a site-level IDP draw, not a hex): %s", source_label)
    return(NULL)
  }
  if (!"geometry" %in% names(x)) {
    geom_col <- attr(x, "sf_column")
    names(x)[names(x) == geom_col] <- "geometry"
    st_geometry(x) <- "geometry"
  }
  x <- st_make_valid(x)
  x <- st_transform(x, 4326)
  out <- x[, c("uuid_hex", "pop_type", "geometry")]
  out$.source <- source_label
  out
}

log_msg("\nStage A: loading the Aug-6 design-frame archive...")
design_path <- "_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds"
design_raw <- readRDS(design_path)
design_geom <- standardize_geom(design_raw, "design_frame_2026-08-06")
dupe_hex_design <- sum(duplicated(design_geom[, c("uuid_hex", "pop_type")] %>% st_drop_geometry()))
log_msg("  %d rows loaded, %d distinct (uuid_hex, pop_type) [%d duplicate pairs within the archive itself, kept - first occurrence wins, geometry should be identical for a repeat-drawn hex]",
        nrow(design_geom), n_distinct(paste(design_geom$uuid_hex, design_geom$pop_type)), dupe_hex_design)

log_msg("\nStage B: loading every partner batch's new_clusters(_non_idp|_idp)?.gpkg (geometry only, cluster_id label NOT trusted) - dynamic glob, whatever exists today, including everything landed since the 09-07 re-run, AND the bare-named Non-IDP files that were being silently missed until now (see header)...")
new_cluster_files <- list.files(
  "resampling/output/resample_runs", pattern = "^new_clusters(_non_idp|_idp)?\\.gpkg$",
  recursive = TRUE, full.names = TRUE
)
log_msg("  Found %d file(s):", length(new_cluster_files))
for (f in new_cluster_files) log_msg("    %s", f)

new_geom_list <- map(new_cluster_files, function(f) {
  x <- st_read(f, quiet = TRUE)
  if (nrow(x) == 0) {
    log_msg("  SKIPPING (0 rows): %s", f)
    return(NULL)
  }
  standardize_geom(x, f)
})
new_geom_list <- compact(new_geom_list)
new_geom <- bind_rows(new_geom_list)
log_msg("  %d total new-cluster row(s) loaded across %d non-empty file(s), %d distinct (uuid_hex, pop_type)",
        nrow(new_geom), length(new_geom_list), n_distinct(paste(new_geom$uuid_hex, new_geom$pop_type)))

log_msg("\nStage C: union geometry sources, de-duplicate by (uuid_hex, pop_type) - new-cluster files listed first so a hex proposed by more than one staged file resolves to one row (harmless which one, same physical location)...")
combined_geom <- bind_rows(new_geom, design_geom) %>%
  distinct(uuid_hex, pop_type, .keep_all = TRUE) %>%
  select(-.source)
log_msg("  %d distinct (uuid_hex, pop_type) geometry rows available.", nrow(combined_geom))

log_msg("\nStage D: v8 FULL supplies the authoritative cluster_id + every attribute - joined onto the geometry lookup by (uuid_hex, pop_type), not by cluster_id...")
full_v8 <- read_csv(
  "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv",
  show_col_types = FALSE, col_types = cols(.default = "c")
)
current_clusters <- full_v8 %>%
  filter(coverage_status != "not_covered") %>%
  mutate(target_households = as.numeric(target_households), reserve_households = as.numeric(reserve_households)) %>%
  distinct(cluster_id, .keep_all = TRUE) %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  select(cluster_id, strata_id, pop_type, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode,
         adm3_name, adm3_pcode, iom_site_name, iom_site_type, idp_population_category,
         selection_type, below_target_cluster, uuid_hex, uuid_hex_pop, target_households,
         reserve_households, coverage_status, exclusion_reason, ward_accessible_status)
log_msg("  v8 FULL, coverage_status != not_covered: %d distinct cluster_id (includes population-floor-excluded strata - a status/geometry picture should still show them, not silently drop them).",
        nrow(current_clusters))

still_selected <- combined_geom %>%
  right_join(current_clusters, by = c("uuid_hex", "pop_type"))

n_missing <- sum(st_is_empty(still_selected) | is.na(st_dimension(still_selected)))
log_msg("  %d of %d current cluster_id(s) matched a geometry row via (uuid_hex, pop_type).", nrow(still_selected) - n_missing, nrow(still_selected))
if (n_missing > 0) {
  missing_ids <- still_selected$cluster_id[st_is_empty(still_selected) | is.na(st_dimension(still_selected))]
  log_msg("  %d cluster_id(s) have NO geometry in either source (genuinely missing) - first 30: %s",
          n_missing, paste(head(missing_ids, 30), collapse = ", "))
  still_selected <- still_selected[!(st_is_empty(still_selected) | is.na(st_dimension(still_selected))), ]
}

log_msg("\n==== DONE. %d clusters in the consolidated geometry (%d Non-IDP hex polygons, %d IDP site points). ====",
        nrow(still_selected),
        sum(st_geometry_type(still_selected) %in% c("POLYGON", "MULTIPOLYGON")),
        sum(st_geometry_type(still_selected) == "POINT"))

saveRDS(still_selected, "output/gis/selected_clusters_v8_current.rds")
log_msg("Wrote output/gis/selected_clusters_v8_current.rds")
close(log_con)
