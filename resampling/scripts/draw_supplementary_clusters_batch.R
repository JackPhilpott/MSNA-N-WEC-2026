# ==============================================================================
# PILOT non-IDP supplementary draw - INTERSOS + FACT only (2026-08-30).
#
# Reuses add_supplementary_clusters() (scripts/04_stage2_cluster_reallocation.R)
# unmodified - the same function already used for the original 28 below-target
# strata and the 2026-08-06 NW resample's 2 clusters. What's new here:
#
# 1. Ward-accessibility pre-filter: a copy of non_idp_sampling$sampling_frame
#    has MOS zeroed for any hex whose centroid resolves (via the same nearest-
#    ward-gap-fixed join as analysis_remaining_eligible_pool.R) to an
#    Inaccessible ward - MOS>0 is already one of the function's own candidate
#    filters, so this excludes them without touching the function itself.
# 2. Two-tier draw: Tier 1 calls the function as-is (hard-excludes already-
#    used hexes, same as always). Whatever's still unresolved after Tier 1
#    gets a Tier 2 pass with already_used_hexagons relaxed to empty - i.e.
#    repeat draws allowed, same selection_count/merge_repeated_psu_draws()
#    mechanism already used throughout the delivered design, just reached
#    deliberately here instead of by chance. Jack's explicit call, 2026-08-29.
# 3. Cluster-ID collision check: add_supplementary_clusters()'s own _supp1/
#    _supp2/... counter restarts at 1 every call. 21 strata (including this
#    pilot's own Abadam) already have _supp clusters from the original design
#    - verified directly before this script existed. Every new ID is checked
#    against the live WORKING frame and renumbered to continue the real
#    sequence before anything is written anywhere.
#
# STAGING ONLY - writes to resampling/output/resample_runs/<date>/, does NOT
# touch the live WORKING/FULL frame. A separate, explicit merge step (after
# review) does that.
# ==============================================================================
# Generalized from draw_supplementary_clusters_pilot_2026-08-30.R (the
# INTERSOS+FACT pilot) so a partner batch can be drawn without copy-pasting
# this whole script again - same proven Tier1/Tier2 + collision-safe
# renumbering mechanism, just parameterized by the shortfalls CSV and a run
# label instead of hardcoding the pilot's own path.
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) stop("Usage: Rscript draw_supplementary_clusters_batch.R <shortfalls_csv> <staging_dir> <seed_base>")
SHORTFALLS_CSV <- args[1]
STAGING_DIR <- args[2]
SEED_BASE <- as.integer(args[3])
# 2026-09-08 resample_runs reorg: STAGING_DIR must resolve to exactly
# resample_runs/<Partner>/<date>/ (2 levels) - 2_monitoring's
# prep_psu_geometries.R globs exactly that depth (non-recursive) for
# new_clusters*.gpkg to build the Coverage Map. A 3rd nested level (e.g.
# an idp_draw/non_idp_draw subfolder) silently drops this batch's geometry
# off the map - exactly what happened to 21 batches before the reorg found
# and fixed it. Use resolve_staging_dir() (scripts/shared/resolve_staging_dir.R)
# to build this argument rather than hand-typing a path.
.after_rr <- sub("^.*resample_runs/", "", gsub("\\\\", "/", STAGING_DIR))
if (.after_rr != gsub("\\\\", "/", STAGING_DIR)) {
  .depth <- length(strsplit(sub("/+$", "", .after_rr), "/")[[1]])
  if (.depth != 2) {
    stop(sprintf("STAGING_DIR '%s' is %d level(s) deep under resample_runs/, expected exactly 2 (<Partner>/<date>). See the note above this check.", STAGING_DIR, .depth))
  }
}
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(STAGING_DIR, "run_log.txt"), open = "wt")
log_msg <- function(...) {
  msg <- sprintf(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_con)
}

log_msg("==== Pilot supplementary draw run - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

# ---- Stage A: source the deterministic pipeline prefix (no set.seed before line 1194) ----
log_msg("Stage A: sourcing pipeline prefix through build_sampling_plan()...")
lines <- readLines("scripts/01_sampling_pipeline_main.R")
writeLines(lines[1:1002], "temp_pilot_draw_prefix.R")
source("temp_pilot_draw_prefix.R")
file.remove("temp_pilot_draw_prefix.R")
log_msg("  non_idp_sampling$sampling_frame: %d rows", nrow(non_idp_sampling$sampling_frame))

# Function definitions needed by add_supplementary_clusters() - pure function
# files, no top-level side effects (confirmed before writing this script),
# safe to source directly regardless of the main pipeline's own order.
source("scripts/02_stage2_building_ingestion.R")
source("scripts/03_stage2_household_selection.R")
source("scripts/04_stage2_cluster_reallocation.R")

building_data_dir <- file.path("C:/Users/JackPHILPOTT/Personal - Documents/GIS", "Google_Open_Buildings")
nga_wards <- sf::st_read(
  here::here("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

# ---- Stage B: ward-accessibility filter ----
log_msg("Stage B: computing ward-accessibility status per candidate hex...")
library(dplyr); library(sf); library(readr)

pilot_shortfalls_raw <- read_csv(SHORTFALLS_CSV, show_col_types = FALSE)

# 2026-09-14 fix: re-validate every shortfall row's coverage_status against
# the CURRENT strata-level WORKING frame, right before it's used - found
# necessary via a direct audit the same night (audit_tonight_draws_vs_bug1_
# fix_2026-09-14.py, per Jack's "checked across everything" follow-up): the
# combined draw earlier that same night wasted real draw effort on 3 strata
# (49 clusters, non_idp_NG036007/NG034009/NG034013) whose shortfalls.csv
# was generated at 02:29, roughly an hour BEFORE a separate population-
# threshold-exclusion decision (patch_population_threshold_new_exclusions_
# 2026-09-14.R, written 03:22) dropped them from the sampling universe
# entirely. Harmless in outcome that time - merge_partner_resample_batch.R's
# own coverage_status check correctly kept the resulting clusters out of
# WORKING - but the draw itself (candidate-hex building, PPS selection,
# household generation) still ran and burned real time for nothing. This
# isn't a staleness problem `assert_fresh()` fits (the shortfalls CSV's own
# SOURCE, the accessibility workbook, hadn't gone stale relative to what
# generated it - a LATER, independent decision moved the ground out from
# under an already-correct snapshot). Simplest real fix: re-check the one
# fact that actually matters (is this stratum still covered right now)
# immediately before spending any draw effort on it, rather than trust a
# shortfall list's age at all.
strata_frame_current <- read_csv(
  "output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v12_WORKING.csv",
  show_col_types = FALSE, col_types = cols(.default = "c")
)
still_covered_strata_ids <- strata_frame_current$strata_id  # WORKING only ever contains covered, non-excluded strata by construction

shortfalls_id_col <- if ("strata_id" %in% names(pilot_shortfalls_raw)) {
  pilot_shortfalls_raw$strata_id
} else {
  paste0(pilot_shortfalls_raw$pop_type, "_", pilot_shortfalls_raw$adm2_pcode)
}
now_excluded <- !(shortfalls_id_col %in% still_covered_strata_ids)
if (any(now_excluded)) {
  log_msg("  WARNING: %d shortfall row(s) reference a stratum no longer covered in the CURRENT strata-level WORKING frame (excluded/dropped since the shortfalls CSV was generated) - dropping from this draw, not wasting effort on them: %s",
          sum(now_excluded), paste(shortfalls_id_col[now_excluded], collapse = ", "))
}
pilot_shortfalls_raw <- pilot_shortfalls_raw[!now_excluded, ]

shortfalls <- pilot_shortfalls_raw %>%
  transmute(pop_type = pop_type, adm2_pcode = adm2_pcode, households_needed = additional_clusters_needed * 6)
log_msg("  %d strata in shortfalls, %d total households needed", nrow(shortfalls), sum(shortfalls$households_needed))

# Freshness gate (2026-09-08 rebuild): this shapefile is a heavy standalone
# GIS recompute (analysis_accessible_area_layer.R), not auto-regenerated -
# this is the exact artifact that was 3 days stale during the 2026-09-07
# incident. mode="stop" deliberately: rebuilding it isn't cheap or something
# to fire off automatically mid-draw, so this blocks with the exact command
# rather than silently proceeding OR silently regenerating something heavy.
source("scripts/shared/assert_fresh.R")
assert_fresh(
  artifact_path = "resampling/output/gis/accessible_area_lga_ward_portions.shp",
  source_paths = "resampling/output/master_accessibility_status_ward_level.csv",
  mode = "stop",
  fix_hint = 'Rscript resampling/scripts/analysis_accessible_area_layer.R',
  label = "accessible_area_lga_ward_portions.shp"
)
ward_layer_raw <- st_read("resampling/output/gis/accessible_area_lga_ward_portions.shp", quiet = TRUE) %>%
  st_transform(mycrs) %>%
  rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ)
ward_layer_non_idp <- ward_layer_raw %>% filter(pop_type == "Non-IDP")

candidate_hexes <- non_idp_sampling$sampling_frame %>%
  filter(adm2_pcode %in% shortfalls$adm2_pcode, MOS > 0)
hex_centroids <- st_centroid(candidate_hexes %>% select(uuid_hex, uuid_hex_pop, adm2_pcode))
hex_ward_status <- st_join(hex_centroids, ward_layer_non_idp["accessible_status"], join = st_within)

na_idx <- which(is.na(hex_ward_status$accessible_status))
if (length(na_idx) > 0) {
  nearest_idx <- st_nearest_feature(hex_ward_status[na_idx, ], ward_layer_non_idp)
  dists <- as.numeric(st_distance(hex_ward_status[na_idx, ], ward_layer_non_idp[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= 5000
  hex_ward_status$accessible_status[na_idx[within_cap]] <- ward_layer_non_idp$accessible_status[nearest_idx[within_cap]]
  if (any(!within_cap)) hex_ward_status$accessible_status[na_idx[!within_cap]] <- "Accessible"
}
hex_status_lookup <- st_drop_geometry(hex_ward_status) %>% select(uuid_hex_pop, accessible_status)

n_inaccessible <- sum(hex_status_lookup$accessible_status == "Inaccessible")
log_msg("  %d of %d pilot-LGA candidate hexes are in an inaccessible ward - excluding from the draw", n_inaccessible, nrow(hex_status_lookup))

non_idp_sampling_filtered <- non_idp_sampling
non_idp_sampling_filtered$sampling_frame <- non_idp_sampling$sampling_frame %>%
  left_join(hex_status_lookup, by = "uuid_hex_pop") %>%
  mutate(MOS = ifelse(!is.na(accessible_status) & accessible_status == "Inaccessible", 0, MOS))

# ---- Task 3B (2026-09-13): access-compromised clusters are never Tier-2
# repeat-draw candidates. -----------------------------------------------------
# Tier 1 already can't re-hit an already-selected hex at all (already_used_
# hexagons hard-excludes it) - this only matters for Tier 2 below, which
# deliberately relaxes that exclusion to character(0) so a hex with an
# EXISTING live cluster can be repeat-drawn (a second selection_count hit,
# same mechanism the delivered design already relies on elsewhere). Without
# this, Tier 2 could add MORE households to a cluster whose access has
# already been lost or partially lost - exactly the scenario Jack's
# 2026-09-05b decision against same-hex replacement for straddling clusters
# already ruled out, generalized here rather than re-litigated. Reads the
# per-cluster status refresh_working_frame_daily.R/merge_partner_resample_
# batch.R write fresh every run (scripts/shared/frame_status.R) - not
# recomputed here, so this doesn't need its own copy of the achieved-lookup
# machinery.
CLUSTER_STATUS_CSV <- "output/data/data_collection/NGA_MSNA_2026_cluster_status_v12.csv"
if (file.exists(CLUSTER_STATUS_CSV)) {
  cluster_status <- read_csv(CLUSTER_STATUS_CSV, show_col_types = FALSE)
  access_compromised_clusters <- cluster_status %>%
    filter(pop_type == "non_idp", status %in% c("partially_completed_access_lost", "not_started_access_lost")) %>%
    pull(cluster_id)
  full_for_status <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v12_FULL.csv", show_col_types = FALSE)
  access_compromised_hex <- full_for_status %>%
    filter(pop_type == "non_idp", cluster_id %in% access_compromised_clusters) %>%
    mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
    distinct(uuid_hex_pop) %>% pull(uuid_hex_pop)
  n_zeroed <- sum(non_idp_sampling_filtered$sampling_frame$uuid_hex_pop %in% access_compromised_hex & non_idp_sampling_filtered$sampling_frame$MOS > 0)
  non_idp_sampling_filtered$sampling_frame <- non_idp_sampling_filtered$sampling_frame %>%
    mutate(MOS = ifelse(uuid_hex_pop %in% access_compromised_hex, 0, MOS))
  log_msg("  %d hex(es) belonging to %d access-compromised cluster(s) excluded from Tier-2 repeat-draw eligibility (MOS zeroed).", n_zeroed, length(access_compromised_clusters))
} else {
  log_msg("  WARNING: %s not found - Task 3B's access-compromised-cluster exclusion skipped this run (run refresh_working_frame_daily.R first to generate it).", CLUSTER_STATUS_CSV)
}

# ---- Stage B2 (2026-09-21, Jack's direct go: "build now, dry-run only";
# floor "6 buildings"): judge every candidate hex on its BUILDINGS, not its
# centroid. -------------------------------------------------------------------
# Why: Stage B classifies a hex by its centroid's ward only, and
# add_supplementary_clusters() counts (and later draws from) EVERY building in
# the hex. A hex straddling an inaccessible ward is therefore fully eligible,
# and its households get stamped Inaccessible after the draw - measured on
# FULL after 2026-09-21's two rounds: of 262 Non-IDP clusters drawn, 57 came
# in under 6 accessible primaries and 31 under the 4-primary floor (38 ward
# straddle, 19 thin hex). The morning round drew 64 clusters for the 13
# strata that then needed a second round; 16 were duds on arrival.
# Fix, no change to the core pipeline functions (this project's convention -
# adapt in the wrapper, as Stage B's MOS zeroing and Stage E.1's redraw do):
#   B2 (here): count each candidate hex's buildings that are (i) in an
#      ACCESSIBLE ward by the exact rule stamp_ward_accessible_status.py
#      applies after the draw - the GRID3 ward the point falls st_within,
#      looked up as (adm1_name, adm2_name, ward) in master_accessibility_
#      status_ward_level.csv, no match = not accessible - and (ii) not already
#      claimed by an existing live-frame household at that hex (real
#      coordinates, 6 dp, same key as Stage D). Hexes with fewer than
#      MIN_ACCESSIBLE_BUILDINGS get MOS zeroed, so PPS never selects them.
#   F (after Stage E.1): every new cluster's households are redrawn from that
#      validated pool only, so no primary can land in an inaccessible ward.
# With every candidate able to deliver a full 6, the function's own
# "contributed = min(m, n_buildings)" accounting becomes exact, so its
# household-need loop IS a usable-household loop.
MIN_ACCESSIBLE_BUILDINGS <- 6L
log_msg("Stage B2: building-validating the candidate pool (>= %d accessible, unclaimed buildings per hex)...", MIN_ACCESSIBLE_BUILDINGS)
master_ward_b2 <- read_csv("resampling/output/master_accessibility_status_ward_level.csv", show_col_types = FALSE)
ward_status_b2 <- setNames(master_ward_b2$`Accessible status`,
                           paste(master_ward_b2$State, master_ward_b2$LGA, master_ward_b2$`Ward (GRID3)`, sep = "|"))
wards_proj_b2 <- sf::st_transform(nga_wards, mycrs) %>% dplyr::select(.ward_b2 = wardname)
full_b2 <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v12_FULL.csv", show_col_types = FALSE)
claimed_keys_b2 <- full_b2 %>%
  dplyr::filter(pop_type == "non_idp", !is.na(latitude), !is.na(longitude)) %>%
  dplyr::transmute(uuid_hex_pop = paste0(pop_type, "_", uuid_hex),
                   .coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))) %>%
  dplyr::distinct()
rm(full_b2)

# Classifies building points (sf, mycrs, carrying uuid_hex_pop) exactly as the
# post-draw stamp will classify a household drawn at that point.
classify_buildings_b2 <- function(bpts, hex_attrs) {
  bpts <- bpts %>% dplyr::left_join(hex_attrs, by = "uuid_hex_pop")
  j <- sf::st_join(bpts, wards_proj_b2, join = sf::st_within, left = TRUE)
  j <- j[!duplicated(paste(j$uuid_hex_pop, j$.centroid_key)), ]   # a point inside two overlapping ward polygons
  ll <- sf::st_coordinates(sf::st_transform(j, 4326))
  j$.coord_key <- paste0(round(ll[, "Y"], 6), "_", round(ll[, "X"], 6))
  st <- unname(ward_status_b2[paste(j$.adm1_b2, j$.adm2_b2, j$.ward_b2, sep = "|")])
  j$.accessible <- !is.na(st) & st == "Accessible"
  j
}
B2_HELPER_COLS <- c(".adm1_b2", ".adm2_b2", ".ward_b2", ".coord_key", ".accessible")

cand_b2 <- non_idp_sampling_filtered$sampling_frame %>%
  dplyr::filter(pop_type == "non_idp", adm2_pcode %in% shortfalls$adm2_pcode, MOS > 0)
hex_attrs_b2 <- cand_b2 %>% sf::st_drop_geometry() %>%
  dplyr::distinct(uuid_hex_pop, .adm1_b2 = adm1_name, .adm2_b2 = adm2_name)
pool_files_b2 <- load_building_footprints(
  gdb_directory = building_data_dir,
  accessible_area = cand_b2,
  mycrs = mycrs,
  cache_directory = file.path(STAGING_DIR, "cache_pool_validation"),
  rebuild = FALSE
)
validated_pool <- purrr::map(pool_files_b2, function(bf) {
  part <- tryCatch(readRDS(bf), error = function(e) NULL)
  if (is.null(part) || nrow(part) == 0) return(NULL)
  part <- sf::st_transform(part, mycrs)
  xy <- sf::st_coordinates(part)
  part %>% dplyr::mutate(.centroid_key = paste0(round(xy[, "X"], 1), "_", round(xy[, "Y"], 1)))
}) %>% purrr::compact() %>% dplyr::bind_rows()
if (nrow(validated_pool) > 0) {
  validated_pool <- validated_pool %>%
    dplyr::filter(uuid_hex_pop %in% cand_b2$uuid_hex_pop) %>%
    dplyr::distinct(uuid_hex_pop, .centroid_key, .keep_all = TRUE)
  validated_pool <- classify_buildings_b2(validated_pool, hex_attrs_b2)
  n_raw_b2 <- nrow(validated_pool)
  validated_pool <- validated_pool %>%
    dplyr::anti_join(claimed_keys_b2, by = c("uuid_hex_pop", ".coord_key"))
  n_claimed_b2 <- n_raw_b2 - nrow(validated_pool)
  n_inacc_b2 <- sum(!validated_pool$.accessible)
  validated_pool <- validated_pool[validated_pool$.accessible, ]
} else {
  n_claimed_b2 <- 0L; n_inacc_b2 <- 0L
}
acc_count_b2 <- validated_pool %>% sf::st_drop_geometry() %>% dplyr::count(uuid_hex_pop, name = "n_acc")
hex_check_b2 <- hex_attrs_b2 %>% dplyr::select(uuid_hex_pop) %>%
  dplyr::left_join(acc_count_b2, by = "uuid_hex_pop") %>%
  dplyr::mutate(n_acc = dplyr::coalesce(n_acc, 0L), eligible = n_acc >= MIN_ACCESSIBLE_BUILDINGS)
thin_hex_b2 <- hex_check_b2$uuid_hex_pop[!hex_check_b2$eligible]
non_idp_sampling_filtered$sampling_frame <- non_idp_sampling_filtered$sampling_frame %>%
  dplyr::mutate(MOS = ifelse(uuid_hex_pop %in% thin_hex_b2, 0, MOS))
validated_pool <- validated_pool %>% dplyr::filter(!(uuid_hex_pop %in% thin_hex_b2))
log_msg("  %d candidate hex(es) checked; %d building(s) excluded as already claimed, %d as in an inaccessible/unmatched ward.",
        nrow(hex_check_b2), n_claimed_b2, n_inacc_b2)
log_msg("  %d hex(es) have fewer than %d accessible, unclaimed buildings - MOS zeroed; %d remain drawable.",
        length(thin_hex_b2), MIN_ACCESSIBLE_BUILDINGS, sum(hex_check_b2$eligible))
b2_by_stratum <- hex_check_b2 %>%
  dplyr::left_join(cand_b2 %>% sf::st_drop_geometry() %>% dplyr::distinct(uuid_hex_pop, adm2_pcode), by = "uuid_hex_pop") %>%
  dplyr::group_by(adm2_pcode) %>%
  dplyr::summarise(candidates = dplyr::n(), drawable = sum(eligible), .groups = "drop")
for (i in seq_len(nrow(b2_by_stratum))) {
  log_msg("    %s: %d of %d candidate hexes drawable after building validation",
          b2_by_stratum$adm2_pcode[i], b2_by_stratum$drawable[i], b2_by_stratum$candidates[i])
}
write_csv(hex_check_b2, file.path(STAGING_DIR, "pool_validation_by_hex.csv"))

# ---- Stage C: Tier 1 draw (already-used hexes hard-excluded, function's own default behaviour) ----
log_msg("Stage C: Tier 1 draw (fresh hexes only)...")
# FULL, not WORKING (2026-09-01 fix, applied when bumping this script from
# v2 to v4): already_used_hex must include hexes belonging to clusters that
# are currently ward-inaccessible (and so absent from WORKING v4) too - the
# site is still a real, already-designed cluster, so a new draw must not be
# allowed to land on the same hex and create a second cluster_id at the same
# location. WORKING would silently permit exactly that collision.
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v12_FULL.csv", show_col_types = FALSE)
# WORKING's own export doesn't carry a plain uuid_hex_pop column (that's an
# in-memory-only field in the main pipeline's own objects) - and its
# original_uuid_hex_pop is a DIFFERENT, reallocation-audit field (99.3% blank
# - only tracks a reallocated cluster's pre-reallocation hex), not this.
# Reconstructed the same way build_population_by_hex() builds it in the first
# place: paste0(pop_type, "_", uuid_hex). Verified against a real row before
# using this.
already_used_hex <- working %>% filter(pop_type == "non_idp") %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  distinct(uuid_hex_pop) %>% pull(uuid_hex_pop)

tier1 <- add_supplementary_clusters(
  shortfalls = as.data.frame(shortfalls),
  already_used_hexagons = already_used_hex,
  non_idp_sampling = non_idp_sampling_filtered,
  building_data_dir = building_data_dir,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(STAGING_DIR, "cache_tier1"),
  m = 6,
  seed = SEED_BASE + 1L,
  rebuild = FALSE
)

n_tier1_clusters <- if (is.null(tier1$new_clusters)) 0 else nrow(tier1$new_clusters)
log_msg("  Tier 1: %d new cluster(s) drawn", n_tier1_clusters)
if (!is.null(tier1$unresolved) && nrow(tier1$unresolved) > 0) {
  log_msg("  Tier 1 unresolved: %d stratum/strata still short", nrow(tier1$unresolved))
  print(tier1$unresolved)
}

saveRDS(tier1, file.path(STAGING_DIR, "tier1_result.rds"))
log_msg("Stage C complete - tier1_result.rds saved.")

# ---- Stage D: Tier 2 (repeat-draw fallback) for whatever Tier 1 left unresolved ----
if (!is.null(tier1$unresolved) && nrow(tier1$unresolved) > 0) {
  log_msg("Stage D: Tier 2 draw (repeat draws allowed) for %d unresolved stratum/strata...", nrow(tier1$unresolved))

  tier2_shortfalls <- tier1$unresolved %>%
    transmute(
      pop_type = sub("_NG.*$", "", strata_key),
      adm2_pcode = sub("^(non_idp|idp)_", "", strata_key),
      households_needed = households_still_needed
    )
  print(tier2_shortfalls)

  # already_used_hexagons deliberately EMPTY here - Tier 2 exists specifically
  # to allow reselecting a hex Tier 1 (or the original design) already used,
  # same selection_count/merge_repeated_psu_draws() mechanism the delivered
  # design already relies on elsewhere. Ward-accessibility filtering (Stage B)
  # still applies via non_idp_sampling_filtered - Tier 2 relaxes ONLY the
  # already-used exclusion, nothing else.
  tier2 <- add_supplementary_clusters(
    shortfalls = as.data.frame(tier2_shortfalls),
    already_used_hexagons = character(0),
    non_idp_sampling = non_idp_sampling_filtered,
    building_data_dir = building_data_dir,
    wards = nga_wards,
    admin3 = NGA_shapes_all_cleaned$nga_admin3,
    mycrs = mycrs,
    cache_directory = file.path(STAGING_DIR, "cache_tier2"),
    m = 6,
    seed = SEED_BASE + 2L,
    rebuild = FALSE
  )

  n_tier2_clusters <- if (is.null(tier2$new_clusters)) 0 else nrow(tier2$new_clusters)
  log_msg("  Tier 2: %d new cluster(s) drawn (repeat draws allowed)", n_tier2_clusters)

  # 2026-09-17 fix, added live after a real, confirmed problem: Tier 2
  # deliberately allows redrawing an already-used hex (already_used_hexagons
  # relaxed to empty, above) - but nothing previously excluded buildings that
  # hex's EXISTING cluster(s) already claimed. The only safety net was a
  # building_id-based check further down (and the Stage E.1 within-batch
  # check) - found the hard way that building_id is a per-scan sequential
  # label ("nga_buildings_part2_0000000002"), not a stable identifier across
  # independent scans, so it can neither reliably catch a real cross-scan
  # duplicate nor avoid a false-positive within-batch one. Verified
  # nationally before this fix existed: 14 real hexes / 59 overlapping
  # household-instance pairs where 2+ clusters already claim identical real
  # addresses - not hypothetical, already in the live frame (Jack's explicit
  # call: leave those as-is, this fix is only to stop it recurring). Jack's
  # rule: once a household is used in ANY cluster draw, it's excluded from
  # what's available for any later draw at that hex - checked by real
  # coordinates (rounded to 6dp, ~11cm), not building_id. Applied here,
  # right after Tier 2's own draw, before anything downstream (Stage E.1,
  # the merge) can treat these rows as valid new households.
  if (n_tier2_clusters > 0) {
    existing_coords_by_hex <- working %>%
      dplyr::filter(pop_type == "non_idp", !is.na(latitude), !is.na(longitude)) %>%
      dplyr::mutate(
        uuid_hex_pop = paste0(pop_type, "_", uuid_hex),
        .coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))
      ) %>%
      dplyr::group_by(uuid_hex_pop) %>%
      dplyr::summarise(existing_keys = list(unique(.coord_key)), .groups = "drop")

    tier2_hh_df <- sf::st_drop_geometry(tier2$new_households) %>%
      dplyr::mutate(
        uuid_hex_pop = paste0(pop_type, "_", uuid_hex),
        .coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))
      ) %>%
      dplyr::left_join(existing_coords_by_hex, by = "uuid_hex_pop")

    is_dupe <- purrr::map2_lgl(tier2_hh_df$.coord_key, tier2_hh_df$existing_keys,
                                function(k, existing) !is.null(existing) && k %in% existing)
    n_dupe <- sum(is_dupe, na.rm = TRUE)
    if (n_dupe > 0) {
      log_msg("  Excluding %d household row(s) from Tier 2 output - already claimed by an EXISTING live-frame cluster at the same hex (real coordinate match, not building_id).", n_dupe)
      tier2$new_households <- tier2$new_households[!is_dupe, ]
      surviving_ids <- unique(tier2$new_households$cluster_id)
      n_clusters_before <- nrow(tier2$new_clusters)
      tier2$new_clusters <- tier2$new_clusters %>% dplyr::filter(cluster_id %in% surviving_ids)
      if (nrow(tier2$new_clusters) < n_clusters_before) {
        log_msg("  Dropped %d Tier 2 cluster(s) entirely - zero real (never-before-claimed) households remained after exclusion.", n_clusters_before - nrow(tier2$new_clusters))
      }
      n_tier2_clusters <- nrow(tier2$new_clusters)
    } else {
      log_msg("  Verified: 0 of Tier 2's new households collide with an existing live-frame household at the same hex (real coordinate check).")
    }
  }

  if (!is.null(tier2$unresolved) && nrow(tier2$unresolved) > 0) {
    log_msg("  STILL unresolved after Tier 2 (%d stratum/strata) - genuinely exhausted, even repeat draws can't close this:", nrow(tier2$unresolved))
    print(tier2$unresolved)
  }
  saveRDS(tier2, file.path(STAGING_DIR, "tier2_result.rds"))

  # Flag which of Tier 2's new clusters are genuine repeat draws (same hex as
  # an existing cluster) vs. hexes Tier 1 simply hadn't reached yet in its own
  # candidate ordering - both are valid Tier 2 output, but worth knowing which
  # is which when reviewing.
  if (n_tier2_clusters > 0) {
    is_repeat <- tier2$new_clusters$uuid_hex_pop %in% c(already_used_hex, tier1$new_clusters$uuid_hex_pop)
    log_msg("  Of Tier 2's %d new clusters, %d are genuine repeat draws (same hex as an existing cluster).", n_tier2_clusters, sum(is_repeat))
  }
} else {
  log_msg("Stage D: nothing unresolved after Tier 1 - no Tier 2 needed.")
  tier2 <- list(new_clusters = NULL, new_households = NULL, unresolved = NULL)
}

# ---- Stage E: combine Tier 1 + Tier 2, fix cluster-ID collisions, write staged output ----
# FIXED (found on the first run): Tier 1 and Tier 2 are two SEPARATE calls to
# add_supplementary_clusters(), and each restarts its own _suppN counter at 1
# independently - so for any stratum touched by BOTH tiers, tier1 and tier2
# can each produce a cluster labelled e.g. "_supp1", two genuinely different
# clusters sharing one string. String-matching rename logic (the first
# attempt) collapsed these into one ID. Fixed by tagging each row with its
# source tier BEFORE combining (so (.source, old cluster_id) is a real unique
# key) and renumbering EVERY new cluster row-by-row rather than matching by
# ID text - simpler and provably collision-free, not just for colliding ones.
# nrow() > 0 guard added 2026-09-21: PLAN/Kala-Balge hit the case where Tier 2
# drew 2 clusters and BOTH were then dropped entirely (every household already
# claimed by an existing live cluster), leaving a non-NULL, 0-row sf frame -
# `$<-` of a length-1 value onto 0 rows errors ("replacement has 1 row, data
# has 0") and killed the whole run after Tier 1 had already succeeded.
if (!is.null(tier1$new_clusters) && nrow(tier1$new_clusters) > 0) { tier1$new_clusters$.source <- "tier1"; tier1$new_households$.source <- "tier1" }
if (!is.null(tier2$new_clusters) && nrow(tier2$new_clusters) > 0) { tier2$new_clusters$.source <- "tier2"; tier2$new_households$.source <- "tier2" }

log_msg("Stage E: combining results...")
all_new_clusters <- dplyr::bind_rows(tier1$new_clusters, tier2$new_clusters)
all_new_households <- dplyr::bind_rows(tier1$new_households, tier2$new_households)

# Zero clusters drawn in either tier is a valid, real outcome (a fully-
# exhausted candidate pool - see tier1/tier2$unresolved above for which
# strata) - exit cleanly here rather than let bind_rows(NULL, NULL)'s
# columnless empty tibble crash Stage E.1's dplyr::count(uuid_hex_pop)
# further down with a confusing "column not found" error.
if (nrow(all_new_clusters) == 0) {
  log_msg("==== DONE. 0 new cluster(s) drawn - every shortfall stratum's candidate pool was already exhausted. ====")
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_clusters.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_households.csv"))
  close(log_con)
  quit(save = "no", status = 0)
}

# ---- Stage E.1: merge same-hex duplicates WITHIN this batch ----
# Tier 1 and Tier 2 are two SEPARATE add_supplementary_clusters() calls, each
# with its own draw_cluster() building draw - neither knows what the other
# already picked at a shared hex. Checked directly against this run before
# building this fix: 11 hexes were drawn by BOTH tiers, and this time zero
# buildings actually overlapped (verified, not assumed) - purely because the
# two different seeds happened to diverge enough on these specific pools, not
# because anything prevented it. Not something to rely on at full scale.
# Fixed the correct way: merge same-hex duplicates into ONE cluster (combined
# target/reserve/selection_count) and redraw fresh in a single draw_cluster()
# call - the same merge-before-draw approach merge_repeated_psu_draws() +
# finalize_households() already use for the original design's own repeat
# draws, reused directly here rather than reimplemented. Does NOT touch the
# live WORKING frame's existing clusters - only merges duplicates within
# today's new batch itself.
hex_dup_counts <- all_new_clusters %>% sf::st_drop_geometry() %>%
  dplyr::count(uuid_hex_pop, name = "n_in_batch") %>% dplyr::filter(n_in_batch > 1)

if (nrow(hex_dup_counts) > 0) {
  affected_hexes <- hex_dup_counts$uuid_hex_pop
  log_msg("Stage E.1: %d hex(es) drawn more than once within this batch - merging each into one cluster, redrawn fresh.", length(affected_hexes))

  cache_dirs <- c(
    file.path(STAGING_DIR, "cache_tier1", "final_buildings"),
    file.path(STAGING_DIR, "cache_tier2", "final_buildings")
  )
  bfiles <- unlist(lapply(cache_dirs, function(d) list.files(d, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE)))
  building_pool_by_hex <- purrr::map(bfiles, function(bf) {
    part <- tryCatch(readRDS(bf), error = function(e) NULL)
    if (is.null(part) || nrow(part) == 0) return(NULL)
    part <- part %>% dplyr::filter(uuid_hex_pop %in% affected_hexes)
    if (nrow(part) == 0) return(NULL)
    coords <- sf::st_coordinates(part)
    part %>% dplyr::mutate(.centroid_key = paste0(round(coords[, "X"], 1), "_", round(coords[, "Y"], 1)))
  }) %>% purrr::compact() %>% dplyr::bind_rows() %>%
    dplyr::distinct(uuid_hex_pop, .centroid_key, .keep_all = TRUE)

  clusters_untouched <- all_new_clusters %>% dplyr::filter(!(uuid_hex_pop %in% affected_hexes))
  # (.source, cluster_id) together, NOT cluster_id alone - the exact same
  # mistake as Stage E's first attempt (tier1 and tier2 can label two
  # genuinely different clusters, at two DIFFERENT hexes, with the same
  # _suppN string, since each tier's counter restarts independently).
  # Caught here on this run: cluster_id-only filtering wrongly dropped 48
  # households belonging to valid, untouched clusters that just happened to
  # share a label with one of the merged-away ones - anti_join on the
  # compound key fixes it the same way Stage E's ID renumbering already does.
  hh_ids_to_drop_df <- all_new_clusters %>% sf::st_drop_geometry() %>%
    dplyr::filter(uuid_hex_pop %in% affected_hexes) %>% dplyr::select(.source, cluster_id)
  households_untouched <- all_new_households %>% dplyr::anti_join(hh_ids_to_drop_df, by = c(".source", "cluster_id"))

  merged_cluster_rows <- list()
  merged_household_rows <- list()
  for (hx in affected_hexes) {
    grp <- all_new_clusters %>% dplyr::filter(uuid_hex_pop == hx)
    grp_df <- sf::st_drop_geometry(grp)
    merged_target <- sum(grp_df$target_households)
    merged_reserve <- sum(grp_df$reserve_households)
    merged_selection_count <- sum(grp_df$selection_count)
    # Deliberately keeps geometry (real building point locations) - draw_cluster()
    # itself doesn't need it, but finalize_households() right after does, for
    # its own ward spatial-join. Dropping it here was the bug on the first run.
    pool_hx <- building_pool_by_hex %>% dplyr::filter(uuid_hex_pop == hx)

    keep_row <- grp[1, ]
    keep_row$target_households <- merged_target
    keep_row$reserve_households <- merged_reserve
    keep_row$selection_count <- merged_selection_count
    # .source must match what the merged households below get tagged with -
    # otherwise the later households join (matched on .source + old cluster
    # ID) silently fails to match these rows, leaving them with an NA
    # cluster_id that the final verification below would then catch anyway,
    # but better to not create the mismatch in the first place.
    keep_row$.source <- "merged"
    new_id <- keep_row$cluster_id[[1]]

    drawn <- draw_cluster(pool_hx, merged_target, merged_reserve)
    log_msg("  hex %s: merged %d cluster(s) into %s (target %d + reserve %d) - %d real building(s) in pool, %s",
            hx, nrow(grp_df), new_id, merged_target, merged_reserve, nrow(pool_hx),
            if (is.null(drawn)) "0 drawn" else paste0(nrow(drawn), " drawn"))
    if (!is.null(drawn) && nrow(drawn) > 0) {
      drawn$cluster_id <- new_id
      hh_final <- finalize_households(drawn, keep_row, nga_wards, NGA_shapes_all_cleaned$nga_admin3, mycrs)
      hh_final$.source <- "merged"
      merged_household_rows[[hx]] <- hh_final
    }
    merged_cluster_rows[[hx]] <- keep_row
  }

  all_new_clusters <- dplyr::bind_rows(clusters_untouched, dplyr::bind_rows(merged_cluster_rows))
  all_new_households <- dplyr::bind_rows(households_untouched, dplyr::bind_rows(merged_household_rows))

  # Re-verify directly - this fix must not itself introduce a NEW within-hex
  # duplicate, and every merged cluster's households must be genuinely unique.
  still_dup_hexes <- all_new_clusters %>% sf::st_drop_geometry() %>%
    dplyr::count(uuid_hex_pop, name = "n") %>% dplyr::filter(n > 1)
  if (nrow(still_dup_hexes) > 0) stop("Stage E.1 merge failed - hexes still duplicated: ", paste(still_dup_hexes$uuid_hex_pop, collapse = ", "))
  # 2026-09-17 fix: was keyed on building_id, which is a per-scan sequential
  # label ("nga_buildings_part2_0000000002"), not a stable identifier - two
  # genuinely different real buildings, drawn in two separate scans (tier1's
  # vs tier2's), can coincidentally land on the same ordinal position and get
  # the same label, producing a FALSE-POSITIVE crash here even when the
  # dedup one function earlier (which correctly keys on rounded coordinates)
  # already removed every genuine duplicate. Confirmed live, 2026-09-17
  # (PLAN/Kala-Balge draw): 48 raw rows for one hex, 24 genuinely unique
  # coordinate pairs (correct), only 42 distinct building_id strings - the
  # gap is coincidental label collision, not a real duplicate building. Keyed
  # on the same rounded-coordinate approach the dedup step already trusts,
  # instead of reinventing a new judgement call.
  dup_bids <- all_new_households %>% dplyr::filter(!is.na(latitude), !is.na(longitude)) %>%
    dplyr::mutate(.coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))) %>%
    dplyr::count(cluster_id, .coord_key) %>% dplyr::filter(n > 1)
  if (nrow(dup_bids) > 0) stop("Stage E.1 merge produced a cluster with the SAME real household (coordinate) assigned twice: ", paste(dup_bids$cluster_id, collapse = ", "))
  log_msg("  Verified: no hex appears more than once, no cluster has a duplicate real household (coordinate check, not building_id).")
} else {
  log_msg("Stage E.1: no hex was drawn more than once within this batch - nothing to merge.")
}

# ---- Stage F (2026-09-21, see Stage B2): every new cluster's households are
# redrawn from its validated pool - accessible, unclaimed buildings only - so
# no primary can land in an inaccessible ward. Same unmodified draw_cluster()
# + finalize_households() Stage E.1 already uses for its own redraw; this
# supersedes both the function's household draw and E.1's (E.1's merging of
# same-hex cluster ROWS is kept). households_in_cluster therefore counts the
# hex's accessible, unclaimed buildings - the true within-hex selection
# universe for these clusters. -------------------------------------------------
log_msg("Stage F: redrawing every new cluster's households from accessible, unclaimed buildings only...")
set.seed(SEED_BASE + 3L)
pool_by_hex_f <- split(validated_pool, validated_pool$uuid_hex_pop)
f_rows <- list()
f_no_pool <- character(0)
for (i in seq_len(nrow(all_new_clusters))) {
  crow <- all_new_clusters[i, ]
  pool_hx <- pool_by_hex_f[[crow$uuid_hex_pop]]
  if (is.null(pool_hx) || nrow(pool_hx) == 0) {
    f_no_pool <- c(f_no_pool, paste(crow$.source, crow$cluster_id, sep = "|"))
    next
  }
  pool_hx <- pool_hx[, setdiff(names(pool_hx), B2_HELPER_COLS)]
  drawn <- draw_cluster(pool_hx, crow$target_households, crow$reserve_households)
  if (is.null(drawn) || nrow(drawn) == 0) {
    f_no_pool <- c(f_no_pool, paste(crow$.source, crow$cluster_id, sep = "|"))
    next
  }
  drawn$cluster_id <- crow$cluster_id
  hh <- finalize_households(drawn, crow, nga_wards, NGA_shapes_all_cleaned$nga_admin3, mycrs)
  hh$.source <- crow$.source
  f_rows[[length(f_rows) + 1]] <- hh
}
if (length(f_no_pool) > 0) {
  log_msg("  WARNING: %d new cluster(s) had no validated pool at redraw (should not happen after Stage B2) - their households are dropped with them below: %s",
          length(f_no_pool), paste(f_no_pool, collapse = ", "))
}
n_hh_before_f <- nrow(all_new_households)
all_new_households <- dplyr::bind_rows(f_rows)
if (anyDuplicated(paste(all_new_households$.source, all_new_households$survey_id)) > 0) {
  stop("Stage F produced duplicate survey IDs - a household point matched more than one ward polygon.")
}
acc_f <- unname(ward_status_b2[paste(all_new_households$adm1_name, all_new_households$adm2_name, all_new_households$adm3_name, sep = "|")])
acc_f <- !is.na(acc_f) & acc_f == "Accessible"
n_bad_primary_f <- sum(all_new_households$status == "primary" & !acc_f)
prim_f <- all_new_households %>% sf::st_drop_geometry() %>%
  dplyr::filter(status == "primary") %>% dplyr::count(.source, cluster_id, name = "n_primary")
n_under_f <- sum(prim_f$n_primary < MIN_ACCESSIBLE_BUILDINGS)
log_msg("  Stage F: %d household row(s) (was %d from the function's own draw); %d primary row(s) in an inaccessible/unmatched ward; %d cluster(s) under %d primaries.",
        nrow(all_new_households), n_hh_before_f, n_bad_primary_f, n_under_f, MIN_ACCESSIBLE_BUILDINGS)
if (n_bad_primary_f > 0 || n_under_f > 0) {
  stop("Stage F check failed: every primary must be in an Accessible ward and every cluster must have >= MIN_ACCESSIBLE_BUILDINGS primaries - the B2 classification and the stamp's rule have diverged. Nothing written.")
}

# 2026-09-07: a Tier 2 (repeat-draw) candidate can get a cluster-level
# metadata row added before its actual draw_cluster() call confirms real
# buildings exist - when the repeat draw comes back empty (the hex's
# already-claimed buildings left nothing genuinely unclaimed for this
# specific candidate), the cluster row was never cleaned up, leaving a
# cluster with metadata but zero households - later tripping the
# new_clusters/new_households set-mismatch check below with no indication
# of why. Found live, FACT's 2026-09-07 supplementary draw (8 of 122
# clusters this way, all Tier 2). A cluster with zero real households was
# never going to contribute anything - drop it here rather than let it
# reach a human as an opaque mismatch error.
#
# 2026-09-21, two corrections, both found by the standing UUID reconciliation
# check on the v11 partner packages (FACT: 1 KML-only reserve point):
#   (1) "zero households" was not strict enough. A repeat draw can leave a
#       cluster with reserve rows but NO primary row - live case:
#       non_idp_NG036011_supp4 (FACT/Machina, Tier 2 repeat of hex_69: exactly
#       one unclaimed building, assigned as reserve rank 2), merged into FULL
#       as a primary-less cluster. Such a cluster contributes nothing to
#       achieved_sample and only ever puts a stray reserve point in front of a
#       field team. Test for "no PRIMARY household", and drop the cluster's
#       reserve rows with it.
#   (2) The test keyed on cluster_id alone, BEFORE the renumbering below - but
#       tier1 and tier2 restart their _suppN counters independently (Stage E's
#       own comment), so a tier1 "_supp3" with households could mask an empty
#       tier2 "_supp3" at a different hex. That is the most plausible mechanism
#       for the 2026-09-07 orphan that "survived a filter that should have
#       caught it" (see the post-renumbering check below). Keyed on
#       (.source, cluster_id) - the same compound key Stage E.1 and the
#       renumbering already use.
.cluster_key <- function(df) paste(df$.source, df$cluster_id, sep = "|")
primary_cluster_keys <- unique(.cluster_key(all_new_households)[all_new_households$status == "primary"])
empty_cluster_keys <- setdiff(unique(.cluster_key(all_new_clusters)), primary_cluster_keys)
if (length(empty_cluster_keys) > 0) {
  n_reserve_dropped <- sum(.cluster_key(all_new_households) %in% empty_cluster_keys)
  log_msg("  Dropping %d cluster(s) that were added as candidates but yielded zero real PRIMARY households (%d reserve-only household row(s) dropped with them): %s",
          length(empty_cluster_keys), n_reserve_dropped, paste(empty_cluster_keys, collapse = ", "))
  all_new_clusters <- all_new_clusters[!(.cluster_key(all_new_clusters) %in% empty_cluster_keys), ]
  all_new_households <- all_new_households[!(.cluster_key(all_new_households) %in% empty_cluster_keys), ]
}

all_new_clusters <- all_new_clusters %>%
  dplyr::mutate(.old_cluster_id = cluster_id, .row_key = dplyr::row_number())

existing_ids <- working$cluster_id
id_map <- all_new_clusters %>%
  sf::st_drop_geometry() %>%
  dplyr::select(.row_key, .source, .old_cluster_id, pop_type, adm2_pcode) %>%
  dplyr::mutate(strata_key = paste0(pop_type, "_", adm2_pcode)) %>%
  dplyr::group_by(strata_key) %>%
  dplyr::mutate(.rank_in_batch = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    .existing_max = {
      existing_supp <- existing_ids[grepl(paste0("^", strata_key, "_supp[0-9]+$"), existing_ids)]
      if (length(existing_supp) > 0) max(as.integer(sub(".*_supp", "", existing_supp))) else 0L
    }
  ) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(new_cluster_id = paste0(strata_key, "_supp", .existing_max + .rank_in_batch))

log_msg("  Renumbered %d new cluster(s) across %d strata, continuing each stratum's real existing _supp sequence.",
        nrow(id_map), dplyr::n_distinct(id_map$strata_key))

all_new_clusters <- all_new_clusters %>%
  dplyr::left_join(id_map %>% dplyr::select(.row_key, new_cluster_id), by = ".row_key") %>%
  dplyr::mutate(cluster_id = new_cluster_id) %>%
  dplyr::select(-.row_key, -new_cluster_id)

all_new_households <- all_new_households %>%
  dplyr::left_join(
    id_map %>% dplyr::select(.source, .old_cluster_id, new_cluster_id),
    by = c(".source" = ".source", "cluster_id" = ".old_cluster_id")
  )
# base R's sub()/gsub() do NOT vectorize `pattern` per-element the way `x` is
# vectorized (only pattern[1] would be used for every row) - substring() with
# a per-row nchar() offset is properly vectorized and sidesteps needing any
# regex at all, since survey_id is known to literally start with the exact
# (still-present, pre-overwrite) cluster_id string.
.suffix <- substring(all_new_households$survey_id, nchar(all_new_households$cluster_id) + 1)
all_new_households <- all_new_households %>%
  dplyr::mutate(
    survey_id = paste0(new_cluster_id, .suffix),
    cluster_id = new_cluster_id
  ) %>%
  dplyr::select(-new_cluster_id)

# Verification - not assumed, checked directly.
still_colliding <- intersect(all_new_clusters$cluster_id, existing_ids)
if (length(still_colliding) > 0) {
  stop("Collision fix failed - still colliding with the live frame: ", paste(still_colliding, collapse = ", "))
}
dup_within_new <- all_new_clusters$cluster_id[duplicated(all_new_clusters$cluster_id)]
if (length(dup_within_new) > 0) {
  stop("Duplicate cluster_id(s) WITHIN the new batch itself: ", paste(unique(dup_within_new), collapse = ", "))
}
if (any(is.na(all_new_clusters$cluster_id)) || any(is.na(all_new_households$cluster_id))) {
  stop("NA cluster_id after renumbering - the join dropped or failed to match some row(s).")
}
if (!setequal(unique(all_new_clusters$cluster_id), unique(all_new_households$cluster_id))) {
  clusters_only <- setdiff(unique(all_new_clusters$cluster_id), unique(all_new_households$cluster_id))
  households_only <- setdiff(unique(all_new_households$cluster_id), unique(all_new_clusters$cluster_id))
  # 2026-09-07: this can still happen post-rename even after the pre-rename
  # empty-cluster drop above (found live: an upstream filter removed 7 of 8
  # empty candidates in FACT's 2026-09-07 draw, but one - a Tier 2 repeat-
  # draw candidate - still turned up orphaned only after the renumbering
  # join, root cause not fully pinned down under time pressure - something
  # about how that one candidate's .source label or row_key interacted with
  # the join, not a fresh empty-draw case since it survived the earlier,
  # identical-in-spirit filter). Rather than block the whole batch (the
  # other 114+ clusters here are genuinely fine) on an unresolved 1-cluster
  # edge case, drop any orphan on EITHER side (cluster metadata with no
  # households, or household rows with no matching cluster row) and log it
  # loudly - conservative (only ever removes incomplete data, never
  # fabricates), and this diagnostic block still fires so it's never silent.
  log_msg("  In new_clusters but not new_households (%d, dropping): %s", length(clusters_only), paste(clusters_only, collapse = ", "))
  log_msg("  In new_households but not new_clusters (%d, dropping): %s", length(households_only), paste(households_only, collapse = ", "))
  all_new_clusters <- all_new_clusters %>% dplyr::filter(!(cluster_id %in% clusters_only))
  all_new_households <- all_new_households %>% dplyr::filter(!(cluster_id %in% households_only))
  if (!setequal(unique(all_new_clusters$cluster_id), unique(all_new_households$cluster_id))) {
    stop("Cluster IDs in new_clusters and new_households STILL disagree after dropping known orphans - needs investigation, not safe to auto-resolve further.")
  }
}
log_msg("  Verified: %d new cluster_id(s), all unique, zero collisions with the live WORKING frame, clusters/households agree.", nrow(all_new_clusters))

# One more check, deliberately not relying on the earlier informal check
# (which found 3 hexes shared with the LIVE frame's own existing clusters,
# zero real overlap - verified, not assumed). That verification was ad hoc
# and outside this script; making it a permanent, fail-loud part of every
# run so a future rerun can never silently ship a real duplicate household
# against an already-fielded cluster, even one that's genuinely rare. Does
# NOT redraw or touch the existing cluster - only fails loudly if it ever
# finds a real collision, since fixing it would mean choosing whose data to
# keep, a call for a human, not this script.
#
# 2026-09-17 fix: was keyed on building_id (see the Stage E.1 fix above for
# the full explanation of why that's unsound) - here the mismatch is even
# more certain to hide a real problem, since this compares TONIGHT's fresh
# scan against the ORIGINAL design's scan from months ago, two genuinely
# independent building_id sequences with no relationship to each other. A
# real duplicate would essentially never coincidentally share a building_id
# string across two scans that far apart, so this check could very plausibly
# have never been able to catch a genuine overlap. Now this specific failure
# mode is caught upstream anyway (Tier 2's own proactive coordinate-based
# exclusion, added the same night), so this check is now a fail-loud
# backstop, not the only line of defense - but fixed for the same reason:
# keyed on real coordinates, the same key the exclusion step above trusts.
existing_coords_by_hex_final <- working %>%
  dplyr::filter(pop_type == "non_idp", !is.na(latitude), !is.na(longitude)) %>%
  dplyr::mutate(
    uuid_hex_pop = paste0(pop_type, "_", uuid_hex),
    .coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))
  ) %>%
  dplyr::group_by(uuid_hex_pop) %>%
  dplyr::summarise(existing_coords = list(unique(.coord_key)), .groups = "drop")

new_coords_by_cluster <- all_new_households %>%
  dplyr::filter(!is.na(latitude), !is.na(longitude)) %>%
  dplyr::mutate(.coord_key = paste0(round(latitude, 6), "_", round(longitude, 6))) %>%
  dplyr::left_join(st_drop_geometry(all_new_clusters) %>% dplyr::select(cluster_id, uuid_hex_pop), by = "cluster_id") %>%
  dplyr::group_by(cluster_id, uuid_hex_pop) %>%
  dplyr::summarise(new_coords = list(unique(.coord_key)), .groups = "drop") %>%
  dplyr::inner_join(existing_coords_by_hex_final, by = "uuid_hex_pop")

if (nrow(new_coords_by_cluster) > 0) {
  overlap_check <- new_coords_by_cluster %>%
    dplyr::rowwise() %>%
    dplyr::mutate(n_overlap = length(intersect(new_coords, existing_coords))) %>%
    dplyr::ungroup() %>%
    dplyr::filter(n_overlap > 0)
  log_msg("  Checked %d new cluster(s) sharing a hex with an existing live-frame cluster - %d have a real coordinate overlap.",
          nrow(new_coords_by_cluster), nrow(overlap_check))
  if (nrow(overlap_check) > 0) {
    stop("Real household (coordinate) overlap found between new cluster(s) and the EXISTING live frame - do not merge until resolved: ",
         paste(overlap_check$cluster_id, collapse = ", "))
  }
}

st_write(all_new_clusters, file.path(STAGING_DIR, "new_clusters.gpkg"), delete_layer = TRUE, quiet = TRUE)
write_csv(st_drop_geometry(all_new_households), file.path(STAGING_DIR, "new_households.csv"))
write_csv(st_drop_geometry(all_new_clusters), file.path(STAGING_DIR, "new_clusters.csv"))

summary_by_strata <- st_drop_geometry(all_new_clusters) %>%
  group_by(strata_id, adm2_pcode) %>%
  summarise(new_clusters = n(), new_households = sum(target_households), .groups = "drop")
write_csv(summary_by_strata, file.path(STAGING_DIR, "summary_by_stratum.csv"))

log_msg("==== DONE. %d total new cluster(s), %d new household row(s), across %d strata. ====",
        nrow(all_new_clusters), nrow(all_new_households), nrow(summary_by_strata))
log_msg("Staged in: %s", STAGING_DIR)
log_msg("NOT merged into the live WORKING/FULL frame - staged for review only.")
close(log_con)
