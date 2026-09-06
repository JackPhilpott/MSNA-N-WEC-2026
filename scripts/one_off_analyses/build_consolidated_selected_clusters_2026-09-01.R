# ==============================================================================
# Build ONE consolidated, current geometry source for every currently-
# selected cluster - fixes a root cause found 2026-09-01 while writing a
# dashboard prompt: at least 3 separate consumers (2_monitoring's
# prep_psu_geometries.R, this project's own build_cluster_maps_production.R,
# and analysis_coverage_map2.R) all still read cluster geometry from
# _archive/2026-08-06_design_frame_post_nw_targeted_resample/
# selected_clusters_final.rds - a frozen snapshot that predates this week's
# entire resampling round. Every one of the ~356 new clusters from this
# round is simply ABSENT (not stale - never existed there), and the 39
# reverted FACT clusters (population-floor revert) are still present as if
# still selected. This script builds a single drop-in replacement RDS with
# the same shape (sf object, POLYGON=Non-IDP hex, POINT=IDP site).
#
# Sources unioned:
#   1. The Aug-6 archive itself (5,864 rows - the original design's
#      geometry, still correct/needed for every cluster that hasn't
#      changed since).
#   2. Every resampling/output/resample_runs/<Partner>/<date>/
#      new_clusters_{non_idp,idp}.gpkg (9 files across the 6 partners -
#      COOPI/Save the Children/ZOA had no IDP additions, so those 3 files
#      don't exist and are skipped, not an error).
#
# IMPORTANT design choice, found the hard way (2026-09-01): the staged
# new_clusters_*.gpkg files' OWN cluster_id label is NOT always what
# actually ended up live. Both INTERSOS and FACT staged proposals for
# idp_NG002001 (Demsa) during their joint 2026-08-30 pilot run using the
# SAME cluster_id labels (idp_NG002001_supp1/2/3) - but v4 FULL's
# partners_covering shows this LGA is FACT-only, so INTERSOS's staged
# rows for it were a pilot-run artifact never actually merged. 266 of 375
# staged cluster_id labels collide across the 9 files this way. Trusting
# a staged file's cluster_id label directly would risk attaching the
# wrong attributes to a hex, or silently dropping a real one during
# de-duplication.
#
# Fix: join on (uuid_hex, pop_type) - the physically stable hex/site
# identity - not cluster_id. Every geometry source contributes
# (uuid_hex, pop_type) -> geometry only; v4 FULL (already-verified ground
# truth for what's actually live) supplies the authoritative cluster_id
# and every attribute. A hex proposed by two different staged files
# collapses to one geometry row (harmless - same physical location
# either way, confirmed by direct inspection of the idp_NG002001 case);
# what matters is v4 FULL decides which cluster_id it belongs to, not
# either staging file.
#
# Output: output/gis/selected_clusters_v4_current.rds (sf object) +
# a plain-text build log alongside it.
# ==============================================================================
suppressMessages({
  library(dplyr)
  library(sf)
  library(readr)
  library(purrr)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

# s2 (spherical) validity is stricter than GEOS (planar) and flags at least
# one source hex as having a degenerate vertex that GEOS - and every other
# script in this project - treats as fine (verified directly: st_is_valid()
# under GEOS finds 0 invalid geometries across all 10 sources here). Off for
# this script only, not a project-wide setting.
sf::sf_use_s2(FALSE)

log_con <- file("output/gis/_consolidated_clusters_build_log_2026-09-01.txt", open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Build consolidated selected-clusters geometry - %s ====", format(Sys.time()))

# geometry-only standardize: uuid_hex + pop_type (the join key) + geometry.
# NOT cluster_id - see header note on why the staged label isn't trusted.
standardize_geom <- function(x, source_label) {
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

log_msg("\nStage B: loading every partner batch's new_clusters_{non_idp,idp}.gpkg (geometry only, cluster_id label NOT trusted)...")
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

log_msg("\nStage D: v4 FULL supplies the authoritative cluster_id + every attribute - joined onto the geometry lookup by (uuid_hex, pop_type), not by cluster_id...")
full_v4 <- read_csv(
  "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
  show_col_types = FALSE, col_types = cols(.default = "c")
)
current_clusters <- full_v4 %>%
  filter(coverage_status != "not_covered") %>%
  mutate(target_households = as.numeric(target_households), reserve_households = as.numeric(reserve_households)) %>%
  distinct(cluster_id, .keep_all = TRUE) %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  select(cluster_id, strata_id, pop_type, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode,
         adm3_name, adm3_pcode, iom_site_name, iom_site_type, idp_population_category,
         selection_type, below_target_cluster, uuid_hex, uuid_hex_pop, target_households,
         reserve_households, coverage_status, exclusion_reason, ward_accessible_status)
log_msg("  v4 FULL, coverage_status != not_covered: %d distinct cluster_id (includes population-floor-excluded strata, e.g. Dandume/Faskari - same reasoning as the ward-status scripts fixed earlier tonight: a status/geometry picture should still show them, not silently drop them).",
        nrow(current_clusters))

still_selected <- combined_geom %>%
  right_join(current_clusters, by = c("uuid_hex", "pop_type"))

n_missing <- sum(st_is_empty(still_selected) | is.na(st_dimension(still_selected)))
log_msg("  %d of %d current cluster_id(s) matched a geometry row via (uuid_hex, pop_type).", nrow(still_selected) - n_missing, nrow(still_selected))
if (n_missing > 0) {
  missing_ids <- still_selected$cluster_id[st_is_empty(still_selected) | is.na(st_dimension(still_selected))]
  log_msg("  %d cluster_id(s) have NO geometry in either source (genuinely missing) - first 20: %s",
          n_missing, paste(head(missing_ids, 20), collapse = ", "))
  still_selected <- still_selected[!(st_is_empty(still_selected) | is.na(st_dimension(still_selected))), ]
}

log_msg("\n==== DONE. %d clusters in the consolidated geometry (%d Non-IDP hex polygons, %d IDP site points). ====",
        nrow(still_selected),
        sum(st_geometry_type(still_selected) %in% c("POLYGON", "MULTIPOLYGON")),
        sum(st_geometry_type(still_selected) == "POINT"))

saveRDS(still_selected, "output/gis/selected_clusters_v4_current.rds")
log_msg("Wrote output/gis/selected_clusters_v4_current.rds")
close(log_con)
