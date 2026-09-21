# ==============================================================================
# Re-run of build_consolidated_selected_clusters_2026-09-14.R against the
# CURRENT (v11) frame - the same root-cause class every version of this
# script's header has described: a version-bump sed sweep renames
# build_cluster_maps_production.R's reference (v8 -> v9 -> v10 on 09-14/
# 09-17), but nothing regenerates the artifact under the new name - this
# file has always had to be REBUILT by hand after a bump, never renamed.
# State found 2026-09-21 (end of the post-Feasibility-fix draw round, v11):
# output/gis/ held only selected_clusters_v8_current.rds (2026-09-14); the
# maps script pointed at a v10 file that never existed, and
# build_lga_summary_maps.R / analysis_coverage_map2*.R still pointed at a
# v6 file that never existed either. Every cluster guide and LGA summary
# map therefore predates the v9/v10/v11 rounds. This build feeds the
# 2026-09-21 guides push (LGA summary maps, per-cluster maps, factsheets).
#
# Logic unchanged from 09-14 (incl. its widened bare-name gpkg glob): union
# the Aug-6 design archive with every partner batch's new_clusters gpkg
# (geometry only, keyed by (uuid_hex, pop_type) - a staged file's
# cluster_id label is never trusted), then right-join v11 FULL's own
# cluster roster for the authoritative cluster_id + attributes. Site-level
# IDP draws have no uuid_hex and are skipped, as before - the maps script
# degrades those to has_hex=FALSE regardless.
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

FRAME_VERSION <- "v11"
FULL_CSV <- sprintf("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION)
OUT_RDS <- sprintf("output/gis/selected_clusters_%s_current.rds", FRAME_VERSION)

log_con <- file("output/gis/_consolidated_clusters_build_log_2026-09-21.txt", open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Build consolidated selected-clusters geometry (%s re-run) - %s ====", FRAME_VERSION, format(Sys.time()))

standardize_geom <- function(x, source_label) {
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
log_msg("  %d rows loaded, %d distinct (uuid_hex, pop_type) [%d duplicate pairs within the archive itself, kept - first occurrence wins]",
        nrow(design_geom), n_distinct(paste(design_geom$uuid_hex, design_geom$pop_type)), dupe_hex_design)

log_msg("\nStage B: loading every partner batch's new_clusters(_non_idp|_idp)?.gpkg (geometry only, cluster_id label NOT trusted)...")
new_cluster_files <- list.files(
  "resampling/output/resample_runs", pattern = "^new_clusters(_non_idp|_idp)?\\.gpkg$",
  recursive = TRUE, full.names = TRUE
)
# Never read a batch's own pre-fix backup copies (e.g. FACT/2026-09-21_post_
# feasibility_fix/_pre_artefact_removal_2026-09-21/new_clusters.gpkg) - the
# live file in the batch folder is the record.
new_cluster_files <- new_cluster_files[!grepl("/_pre_|/_archive", new_cluster_files)]
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

log_msg("\nStage C: union geometry sources, de-duplicate by (uuid_hex, pop_type) - new-cluster files listed first...")
combined_geom <- bind_rows(new_geom, design_geom) %>%
  distinct(uuid_hex, pop_type, .keep_all = TRUE) %>%
  select(-.source)
log_msg("  %d distinct (uuid_hex, pop_type) geometry rows available.", nrow(combined_geom))

log_msg("\nStage D: %s FULL supplies the authoritative cluster_id + every attribute - joined onto the geometry lookup by (uuid_hex, pop_type)...", FRAME_VERSION)
full_cur <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
current_clusters <- full_cur %>%
  filter(coverage_status != "not_covered") %>%
  mutate(target_households = as.numeric(target_households), reserve_households = as.numeric(reserve_households)) %>%
  distinct(cluster_id, .keep_all = TRUE) %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  select(cluster_id, strata_id, pop_type, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode,
         adm3_name, adm3_pcode, iom_site_name, iom_site_type, idp_population_category,
         selection_type, below_target_cluster, uuid_hex, uuid_hex_pop, target_households,
         reserve_households, coverage_status, exclusion_reason, ward_accessible_status)
log_msg("  %s FULL, coverage_status != not_covered: %d distinct cluster_id.", FRAME_VERSION, nrow(current_clusters))

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

saveRDS(still_selected, OUT_RDS)
log_msg("Wrote %s", OUT_RDS)
close(log_con)
