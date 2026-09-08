# ==============================================================================
# Re-run of build_consolidated_selected_clusters_2026-09-01.R (see that
# script's own header for the full original rationale) against the CURRENT
# state, not a new design. Found necessary 2026-09-07 while running the
# established cluster-guide pipeline: build_cluster_maps_production.R has
# referenced "selected_clusters_v6_current.rds" since some point after
# 2026-09-01, but that file was NEVER actually built - the Sep-1 script
# hardcodes its own output name to v4 (matching whatever the frame's version
# was that day), and nobody ever re-ran a v6 (or later) version of it. First
# discovered as an outright crash (file doesn't exist); pointing at the
# stale v4 file instead got the script running, but then 660 of tonight's
# ~660+ supplementary ("_supp") clusters failed with the exact
# "uuid_hex == uuid_hex_i" vctrs-recycling error the ORIGINAL Sep-1 fix was
# built to eliminate - traced to uuid_hex_lookup (build_cluster_maps_
# production.R line 214) being built directly from this file's own
# cluster_id set, which of course has zero entries for any cluster_id that
# didn't exist yet on 2026-09-01 (five partners' worth of resampling ago).
#
# Only two things changed from the Sep-1 script: the join now uses v7_FULL
# (current) instead of v4_FULL, and the output is named accordingly. Stage
# B's new_clusters_*.gpkg glob is unchanged and dynamic - it picks up
# whatever's actually on disk today, including tonight's, with no code
# change needed there. Same (uuid_hex, pop_type) join-key design as the
# original for the same reason: staged files' own cluster_id labels aren't
# trustworthy (see that script's header), v7 FULL is the verified ground
# truth for which cluster_id a hex/site actually belongs to now.
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

log_con <- file("output/gis/_consolidated_clusters_build_log_2026-09-07.txt", open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Build consolidated selected-clusters geometry (v7 re-run) - %s ====", format(Sys.time()))

standardize_geom <- function(x, source_label) {
  # 2026-09-07: site-level IDP draws (the 2026-09-02 IDP PSU redesign - see
  # 1_sampling/CLAUDE.md - switched IDP sampling from hex-based to direct
  # site-identity PPS) have no uuid_hex column at all - keyed by cluster_id
  # directly instead. This whole consolidation is a hex-geometry mechanism;
  # it has nothing to contribute for a site that was never a hex. Skip
  # these cleanly rather than crash Stage B - they're handled downstream by
  # build_cluster_maps_production.R's own uuid_hex_lookup fix (2026-09-07),
  # which now guarantees every current cluster_id gets a lookup row (NA
  # uuid_hex, gracefully degrading has_hex to FALSE) regardless of whether
  # it ever appears here.
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

log_msg("\nStage B: loading every partner batch's new_clusters_{non_idp,idp}.gpkg (geometry only, cluster_id label NOT trusted) - dynamic glob, whatever exists today...")
new_cluster_files <- list.files(
  "resampling/output/resample_runs", pattern = "^new_clusters_(non_idp|idp)\\.gpkg$",
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

log_msg("\nStage D: v7 FULL supplies the authoritative cluster_id + every attribute - joined onto the geometry lookup by (uuid_hex, pop_type), not by cluster_id...")
full_v7 <- read_csv(
  "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv",
  show_col_types = FALSE, col_types = cols(.default = "c")
)
current_clusters <- full_v7 %>%
  filter(coverage_status != "not_covered") %>%
  mutate(target_households = as.numeric(target_households), reserve_households = as.numeric(reserve_households)) %>%
  distinct(cluster_id, .keep_all = TRUE) %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  select(cluster_id, strata_id, pop_type, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode,
         adm3_name, adm3_pcode, iom_site_name, iom_site_type, idp_population_category,
         selection_type, below_target_cluster, uuid_hex, uuid_hex_pop, target_households,
         reserve_households, coverage_status, exclusion_reason, ward_accessible_status)
log_msg("  v7 FULL, coverage_status != not_covered: %d distinct cluster_id (includes population-floor-excluded strata - a status/geometry picture should still show them, not silently drop them).",
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

saveRDS(still_selected, "output/gis/selected_clusters_v7_current.rds")
log_msg("Wrote output/gis/selected_clusters_v7_current.rds")
close(log_con)
