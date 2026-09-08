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
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
RUN_DATE <- "2026-08-30"
RUN_LABEL <- "intersos_fact_pilot"
STAGING_DIR <- file.path("resampling", "output", "resample_runs", paste0(RUN_DATE, "_", RUN_LABEL))
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

pilot_shortfalls_raw <- read_csv(
  "C:/Users/JACKPH~1/AppData/Local/Temp/claude/c--Users-JackPHILPOTT-ACTED-IMPACT-NGA---02--MSNA-4--Data-MSNA-N-WEC-2026/bbf40540-4359-44ed-a137-933cff5a411a/scratchpad/pilot_shortfalls.csv",
  show_col_types = FALSE
)
shortfalls <- pilot_shortfalls_raw %>%
  transmute(pop_type = pop_type, adm2_pcode = adm2_pcode, households_needed = additional_clusters_needed * 6)
log_msg("  %d strata in shortfalls, %d total households needed", nrow(shortfalls), sum(shortfalls$households_needed))

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

# ---- Stage C: Tier 1 draw (already-used hexes hard-excluded, function's own default behaviour) ----
log_msg("Stage C: Tier 1 draw (fresh hexes only)...")
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv", show_col_types = FALSE)
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
  cache_directory = file.path("resampling", "output", "cache", "pilot_supplementary_tier1"),
  m = 6,
  seed = 90001,
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
    cache_directory = file.path("resampling", "output", "cache", "pilot_supplementary_tier2"),
    m = 6,
    seed = 90002,
    rebuild = FALSE
  )

  n_tier2_clusters <- if (is.null(tier2$new_clusters)) 0 else nrow(tier2$new_clusters)
  log_msg("  Tier 2: %d new cluster(s) drawn (repeat draws allowed)", n_tier2_clusters)
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
if (!is.null(tier1$new_clusters)) { tier1$new_clusters$.source <- "tier1"; tier1$new_households$.source <- "tier1" }
if (!is.null(tier2$new_clusters)) { tier2$new_clusters$.source <- "tier2"; tier2$new_households$.source <- "tier2" }

log_msg("Stage E: combining results...")
all_new_clusters <- dplyr::bind_rows(tier1$new_clusters, tier2$new_clusters)
all_new_households <- dplyr::bind_rows(tier1$new_households, tier2$new_households)

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
    file.path("resampling", "output", "cache", "pilot_supplementary_tier1", "final_buildings"),
    file.path("resampling", "output", "cache", "pilot_supplementary_tier2", "final_buildings")
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
  dup_bids <- all_new_households %>% dplyr::filter(!is.na(building_id)) %>%
    dplyr::count(cluster_id, building_id) %>% dplyr::filter(n > 1)
  if (nrow(dup_bids) > 0) stop("Stage E.1 merge produced a cluster with the SAME building assigned twice: ", paste(dup_bids$cluster_id, collapse = ", "))
  log_msg("  Verified: no hex appears more than once, no cluster has a duplicate building_id.")
} else {
  log_msg("Stage E.1: no hex was drawn more than once within this batch - nothing to merge.")
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
  stop("Cluster IDs in new_clusters and new_households disagree after renumbering - mismatch.")
}
log_msg("  Verified: %d new cluster_id(s), all unique, zero collisions with the live WORKING frame, clusters/households agree.", nrow(all_new_clusters))

# One more check, deliberately not relying on the earlier informal check
# (which found 3 hexes shared with the LIVE frame's own existing clusters,
# zero real building_id overlap - verified, not assumed). That verification
# was ad hoc and outside this script; making it a permanent, fail-loud part
# of every run so a future rerun can never silently ship a real duplicate
# household against an already-fielded cluster, even one that's genuinely
# rare. Does NOT redraw or touch the existing cluster - only fails loudly if
# it ever finds a real collision, since fixing it would mean choosing whose
# data to keep, a call for a human, not this script.
existing_bids_by_hex <- working %>%
  dplyr::filter(pop_type == "non_idp", !is.na(building_id)) %>%
  dplyr::mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  dplyr::group_by(uuid_hex_pop) %>%
  dplyr::summarise(existing_bids = list(unique(building_id)), .groups = "drop")

new_bids_by_cluster <- all_new_households %>%
  dplyr::filter(!is.na(building_id)) %>%
  dplyr::left_join(st_drop_geometry(all_new_clusters) %>% dplyr::select(cluster_id, uuid_hex_pop), by = "cluster_id") %>%
  dplyr::group_by(cluster_id, uuid_hex_pop) %>%
  dplyr::summarise(new_bids = list(unique(building_id)), .groups = "drop") %>%
  dplyr::inner_join(existing_bids_by_hex, by = "uuid_hex_pop")

if (nrow(new_bids_by_cluster) > 0) {
  overlap_check <- new_bids_by_cluster %>%
    dplyr::rowwise() %>%
    dplyr::mutate(n_overlap = length(intersect(new_bids, existing_bids))) %>%
    dplyr::ungroup() %>%
    dplyr::filter(n_overlap > 0)
  log_msg("  Checked %d new cluster(s) sharing a hex with an existing live-frame cluster - %d have a real building_id overlap.",
          nrow(new_bids_by_cluster), nrow(overlap_check))
  if (nrow(overlap_check) > 0) {
    stop("Real building_id overlap found between new cluster(s) and the EXISTING live frame - do not merge until resolved: ",
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
