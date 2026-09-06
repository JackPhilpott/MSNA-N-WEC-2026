# ==============================================================================
# PILOT IDP supplementary draw - INTERSOS + FACT only (2026-08-30). Sibling to
# draw_supplementary_clusters_pilot_2026-08-30.R (Non-IDP) - same staging
# location, same tiering/verification philosophy, reusing the lessons that
# script's bugs surfaced rather than repeating them here.
#
# No add_supplementary_clusters()-equivalent exists for IDP (confirmed before
# writing this - see resampling/RESAMPLING_DECISION_RULES.md). What's reused
# instead: hex-level PPS-by-household-count selection (same weighted-without-
# replacement method add_supplementary_clusters() itself uses, NOT the more
# complex systematic PPS select_pps_clusters() does for the original full
# draw - consistent with the Non-IDP supplementary precedent), then
# select_stage2_idp_sites() UNMODIFIED for site resolution + household
# row construction - it already calls merge_repeated_psu_draws() internally,
# so repeat-hex merging (the exact bug that took three tries to get right on
# the Non-IDP side) is handled correctly by construction here, not bolted on
# after the fact.
#
# Simpler than Non-IDP in one real way: hex_grid_idp is built FROM iom_idp_df
# (build_population_by_hex(), 01_sampling_pipeline_main.R) - every hex in it
# already contains at least one real DTM site by construction. No multi-round
# building-validation is needed; a hex's candidacy is already resolved at
# hex_grid_idp build time, not discovered mid-draw the way Non-IDP building
# eligibility is.
#
# STAGING ONLY - writes to resampling/output/resample_runs/<date>/, does NOT
# touch the live WORKING/FULL frame.
# ==============================================================================
# Generalized from draw_supplementary_idp_clusters_pilot_2026-08-30.R - see
# that file's header for the mechanism design. Parameterized by shortfalls
# CSV / staging dir / seed base instead of the pilot's hardcoded path.
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) stop("Usage: Rscript draw_supplementary_idp_clusters_batch.R <shortfalls_idp_csv> <staging_dir> <seed_base>")
SHORTFALLS_IDP_CSV <- args[1]
STAGING_DIR <- args[2]
SEED_BASE <- as.integer(args[3])
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(STAGING_DIR, "run_log_idp.txt"), open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Pilot IDP supplementary draw run - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

library(dplyr); library(sf); library(readr); library(purrr)

log_msg("Stage A: sourcing pipeline prefix (same deterministic range as the Non-IDP script)...")
lines <- readLines("scripts/01_sampling_pipeline_main.R")
writeLines(lines[1:1002], "temp_pilot_idp_draw_prefix.R")
source("temp_pilot_idp_draw_prefix.R")
file.remove("temp_pilot_idp_draw_prefix.R")
log_msg("  idp_sampling$sampling_frame: %d rows | iom_idp_df: %d sites", nrow(idp_sampling$sampling_frame), nrow(iom_idp_df))

source("scripts/03_stage2_household_selection.R")  # merge_repeated_psu_draws(), finalize_households() - not defined by the pipeline prefix itself
source("scripts/05_stage2_idp_site_assignment.R")   # select_stage2_idp_sites()
nga_wards <- sf::st_read(
  here::here("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

# ---- Stage B: ward-accessibility filter (identical method to the Non-IDP script) ----
log_msg("Stage B: computing ward-accessibility status per candidate IDP hex...")
shortfalls <- read_csv(SHORTFALLS_IDP_CSV, show_col_types = FALSE) %>%
  transmute(pop_type = pop_type, adm2_pcode = adm2_pcode, households_needed = additional_clusters_needed * 6)
log_msg("  %d strata in shortfalls, %d total households needed", nrow(shortfalls), sum(shortfalls$households_needed))

ward_layer_idp <- st_read("resampling/output/gis/accessible_area_lga_ward_portions.shp", quiet = TRUE) %>%
  st_transform(mycrs) %>%
  rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ) %>%
  filter(pop_type == "IDP")

candidate_hexes <- idp_sampling$sampling_frame %>% filter(adm2_pcode %in% shortfalls$adm2_pcode, MOS > 0)
hex_centroids <- st_centroid(candidate_hexes %>% select(uuid_hex, uuid_hex_pop, adm2_pcode))
hex_ward_status <- st_join(hex_centroids, ward_layer_idp["accessible_status"], join = st_within)
na_idx <- which(is.na(hex_ward_status$accessible_status))
if (length(na_idx) > 0) {
  nearest_idx <- st_nearest_feature(hex_ward_status[na_idx, ], ward_layer_idp)
  dists <- as.numeric(st_distance(hex_ward_status[na_idx, ], ward_layer_idp[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= 5000
  hex_ward_status$accessible_status[na_idx[within_cap]] <- ward_layer_idp$accessible_status[nearest_idx[within_cap]]
  if (any(!within_cap)) hex_ward_status$accessible_status[na_idx[!within_cap]] <- "Accessible"
}
hex_status_lookup <- st_drop_geometry(hex_ward_status) %>% select(uuid_hex_pop, accessible_status)
n_inaccessible <- sum(hex_status_lookup$accessible_status == "Inaccessible")
log_msg("  %d of %d pilot-LGA candidate IDP hexes are in an inaccessible ward - excluding", n_inaccessible, nrow(hex_status_lookup))

idp_sampling_filtered <- idp_sampling
idp_sampling_filtered$sampling_frame <- idp_sampling$sampling_frame %>%
  left_join(hex_status_lookup, by = "uuid_hex_pop") %>%
  mutate(MOS = ifelse(!is.na(accessible_status) & accessible_status == "Inaccessible", 0, MOS))

# ---- Stage C: weighted-without-replacement hex draw (Tier 1: fresh hexes only) ----
# FULL, not WORKING (2026-09-01 fix, applied when bumping this script from
# v2 to v4 - same reasoning as the Non-IDP script's Stage C): a hex used by a
# currently ward-inaccessible cluster is still a real, already-designed
# cluster and must stay excluded from redraw, even though it's absent from
# WORKING v4.
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv", show_col_types = FALSE)
already_used_hex <- working %>% filter(pop_type == "idp") %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>% distinct(uuid_hex_pop) %>% pull(uuid_hex_pop)

draw_idp_hexes <- function(shortfalls_df, already_used, seed) {
  set.seed(seed)
  purrr::map_dfr(seq_len(nrow(shortfalls_df)), function(i) {
    row <- shortfalls_df[i, ]
    pool <- idp_sampling_filtered$sampling_frame %>%
      filter(pop_type == row$pop_type, adm2_pcode == row$adm2_pcode, MOS > 0, !uuid_hex_pop %in% already_used)
    n_needed <- ceiling(row$households_needed / 6)
    if (nrow(pool) == 0 || n_needed == 0) return(NULL)
    # (a NULL return here means purrr::map_dfr() below can hand back an
    # empty-but-non-NULL 0-row tibble if EVERY stratum hits this branch -
    # is.null() alone won't catch that, see the is-empty helper below)
    pool_ordered <- pool[sample.int(nrow(pool), size = nrow(pool), prob = pool$MOS), ]
    pool_ordered[seq_len(min(n_needed, nrow(pool))), ] %>%
      mutate(strata_key = paste0(row$pop_type, "_", row$adm2_pcode), n_drawn_this_stratum = min(n_needed, nrow(pool)), n_needed_this_stratum = n_needed)
  })
}

# purrr::map_dfr() returns an empty-but-non-NULL 0-row/0-col tibble when
# EVERY per-row call returns NULL (all strata exhausted) - is.null() alone
# doesn't catch that case, found 2026-08-30 via a real "0 candidates for
# every stratum" run. Check both.
is_empty_hexes <- function(x) is.null(x) || nrow(x) == 0

log_msg("Stage C: Tier 1 IDP hex draw (fresh hexes only)...")
tier1_hexes <- draw_idp_hexes(shortfalls, already_used_hex, seed = SEED_BASE + 1L)
log_msg("  Tier 1: %d hex(es) drawn", if (is_empty_hexes(tier1_hexes)) 0 else nrow(tier1_hexes))

# Build the Tier 1 coverage table from the FULL 14-strata shortfalls list,
# not from tier1_hexes' own strata_key set - draw_idp_hexes() returns NULL
# rows for a stratum with an empty candidate pool (all its hexes already in
# the live WORKING frame), so that stratum simply never appears in
# tier1_hexes at all. Building shortfall_check from tier1_hexes alone
# silently dropped those strata from ever being considered for Tier 2 -
# found and fixed 2026-08-30: 8 of 14 strata got zero Tier 1 hexes and were
# never even attempted under Tier 2's relaxed already-used filter, even
# though Tier 2 (which does NOT exclude already-used hexes) can legitimately
# draw from exactly the hexes Tier 1's exclusion ruled out.
tier1_drawn_by_stratum <- if (is_empty_hexes(tier1_hexes)) {
  tibble::tibble(strata_key = character(0), n_drawn_this_stratum = integer(0))
} else {
  tier1_hexes %>% st_drop_geometry() %>% distinct(strata_key, n_drawn_this_stratum)
}
shortfall_check <- shortfalls %>%
  mutate(strata_key = paste0(pop_type, "_", adm2_pcode), n_needed_this_stratum = ceiling(households_needed / 6)) %>%
  left_join(tier1_drawn_by_stratum, by = "strata_key") %>%
  mutate(n_drawn_this_stratum = coalesce(n_drawn_this_stratum, 0L)) %>%
  select(strata_key, pop_type, adm2_pcode, n_drawn_this_stratum, n_needed_this_stratum)
print(shortfall_check)

unresolved_strata <- shortfall_check %>% filter(n_drawn_this_stratum < n_needed_this_stratum)
if (nrow(unresolved_strata) > 0) {
  log_msg("  %d stratum/strata still short after Tier 1 - trying Tier 2 (repeat draws allowed)...", nrow(unresolved_strata))
  tier2_shortfalls <- unresolved_strata %>%
    mutate(households_needed = (n_needed_this_stratum - n_drawn_this_stratum) * 6) %>%
    select(pop_type, adm2_pcode, households_needed)
  tier2_hexes <- draw_idp_hexes(tier2_shortfalls, character(0), seed = SEED_BASE + 2L)
  log_msg("  Tier 2: %d hex(es) drawn (repeat draws allowed)", if (is_empty_hexes(tier2_hexes)) 0 else nrow(tier2_hexes))
} else {
  tier2_hexes <- NULL
  log_msg("  Nothing unresolved after Tier 1 - no Tier 2 needed.")
}

final_check <- shortfalls %>%
  mutate(strata_key = paste0(pop_type, "_", adm2_pcode)) %>%
  left_join(
    dplyr::bind_rows(tier1_hexes, tier2_hexes) %>% st_drop_geometry() %>%
      count(strata_key, name = "n_hex_total"),
    by = "strata_key"
  ) %>%
  mutate(n_hex_total = coalesce(n_hex_total, 0L), n_hh_covered = n_hex_total * 6,
         n_needed = ceiling(households_needed / 6) * 6, fully_closed = n_hh_covered >= n_needed)
log_msg("  Final closure check across all %d strata (%d fully closed, %d still short even after Tier 2):",
        nrow(final_check), sum(final_check$fully_closed), sum(!final_check$fully_closed))
print(final_check %>% select(strata_key, n_hex_total, n_hh_covered, n_needed, fully_closed))
if (any(!final_check$fully_closed)) {
  still_short <- final_check %>% filter(!fully_closed)
  log_msg("  UNCLOSABLE even with Tier 2 (candidate hex pool exhausted - every DTM-recorded hex in the LGA is already drawn): %s",
          paste(sprintf("%s (needs %d more hh)", still_short$strata_key, still_short$n_needed - still_short$n_hh_covered), collapse = "; "))
}

# bind_rows() silently drops the sf class when Tier 1 comes back completely
# empty for every stratum (is_empty_hexes(tier1_hexes) TRUE) - a fully-
# exhausted Tier 1 is a real, valid outcome (hit 2026-09-02, FACT's IDP
# batch: all 9 strata had 0 fresh-hex candidates), but tier1_hexes is then
# an ordinary 0-row/0-col tibble, not sf - binding that in front of tier2_
# hexes (a real sf tibble) confuses dplyr's output-type inference and the
# result loses its sf class, which select_stage2_idp_sites() then rejects
# via stopifnot(inherits(clusters, "sf")). Fix: drop empty inputs before
# binding rather than assuming both sides are always sf.
hex_parts <- list(tier1_hexes, tier2_hexes)
hex_parts <- hex_parts[!vapply(hex_parts, is_empty_hexes, logical(1))]
all_new_hexes <- if (length(hex_parts) == 0) tier1_hexes else dplyr::bind_rows(hex_parts)
log_msg("Stage C complete: %d total new IDP hex(es) selected across both tiers.", nrow(all_new_hexes))
saveRDS(all_new_hexes, file.path(STAGING_DIR, "idp_tier_hexes.rds"))

# ---- Stage D: site resolution via select_stage2_idp_sites() (unmodified) ----
# select_stage2_idp_sites() already contains everything needed to handle a
# hex drawn more than once WITHIN one call - it runs merge_repeated_psu_
# draws() internally, which groups by uuid_hex_pop and sets target_households
# = m * selection_count. That means, unlike the Non-IDP side (where a
# building POOL is a finite, physically-consumed resource and duplicate
# draws had to be merged-and-redrawn by hand in Stage E.1 below), IDP repeat-
# hex handling needs no manual merge step at all - just feed Tier 1 + Tier 2
# together in ONE call, with selection_count correctly precomputed per row
# (the function needs this already set, it does not derive it from row
# duplication itself - see merge_repeated_psu_draws()'s own docs).
if (nrow(all_new_hexes) == 0) {
  log_msg("==== DONE. 0 new IDP hex(es) drawn in either tier - every shortfall stratum's candidate pool was already exhausted. ====")
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_clusters_idp.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_households_idp.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "existing_cluster_target_increases_idp.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "existing_cluster_household_additions_idp.csv"))
  close(log_con)
  quit(save = "no", status = 0)
}

all_new_hexes <- all_new_hexes %>%
  dplyr::mutate(.orig_row = dplyr::row_number()) %>%
  dplyr::group_by(uuid_hex_pop) %>%
  dplyr::mutate(selection_count = dplyr::n(), cluster_number = .orig_row) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(cluster_id = paste0(strata_key, "_TEMP", .orig_row)) %>%
  dplyr::select(-.orig_row, -n_drawn_this_stratum, -n_needed_this_stratum)

n_repeat_hex <- all_new_hexes %>% st_drop_geometry() %>% distinct(uuid_hex_pop, selection_count) %>% filter(selection_count > 1) %>% nrow()
log_msg("Stage D: %d of %d distinct hex(es) in this batch were drawn more than once across tiers (selection_count > 1) - handled natively by select_stage2_idp_sites()'s own merge_repeated_psu_draws() call, no manual redraw needed.",
        n_repeat_hex, dplyr::n_distinct(all_new_hexes$uuid_hex_pop))

idp_site_result <- select_stage2_idp_sites(
  clusters = all_new_hexes,
  iom_idp_df = iom_idp_df,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(STAGING_DIR, "cache_idp"),
  m = 6,
  rebuild = TRUE
)

new_clusters <- idp_site_result$clusters_final
new_households <- idp_site_result$households
log_msg("Stage D complete: %d new IDP cluster(s) resolved to a representative DTM site, %d household interview slot(s).",
        nrow(new_clusters), nrow(new_households))

# ---- Stage E: renumber cluster_ids, continuing each stratum's real _supp sequence ----
# Identical pattern to the Non-IDP pilot script's Stage E (draw_supplementary_
# clusters_pilot_2026-08-30.R) - same collision class (add_supplementary_
# clusters()'s own _supp counter restarts at 1 every call; the TEMP ids
# assigned in Stage D above are placeholders, never meant to ship).
new_clusters <- new_clusters %>%
  dplyr::mutate(.old_cluster_id = cluster_id, .row_key = dplyr::row_number())

existing_ids <- working$cluster_id
id_map <- new_clusters %>%
  sf::st_drop_geometry() %>%
  dplyr::select(.row_key, .old_cluster_id, strata_key = strata_id) %>%
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

log_msg("Stage E: renumbered %d new IDP cluster(s) across %d strata, continuing each stratum's real existing _supp sequence.",
        nrow(id_map), dplyr::n_distinct(id_map$strata_key))

new_clusters <- new_clusters %>%
  dplyr::left_join(id_map %>% dplyr::select(.row_key, new_cluster_id), by = ".row_key") %>%
  dplyr::mutate(cluster_id = new_cluster_id) %>%
  dplyr::select(-.row_key, -new_cluster_id)

new_households <- new_households %>%
  dplyr::left_join(
    id_map %>% dplyr::select(.old_cluster_id, new_cluster_id),
    by = c("cluster_id" = ".old_cluster_id")
  )
.suffix <- substring(new_households$survey_id, nchar(new_households$cluster_id) + 1)
new_households <- new_households %>%
  dplyr::mutate(survey_id = paste0(new_cluster_id, .suffix), cluster_id = new_cluster_id) %>%
  dplyr::select(-new_cluster_id)

# Verification - not assumed, checked directly (same checks as the Non-IDP script).
still_colliding <- intersect(new_clusters$cluster_id, existing_ids)
if (length(still_colliding) > 0) stop("Collision fix failed - still colliding with the live frame: ", paste(still_colliding, collapse = ", "))
dup_within_new <- new_clusters$cluster_id[duplicated(new_clusters$cluster_id)]
if (length(dup_within_new) > 0) stop("Duplicate cluster_id(s) WITHIN the new IDP batch itself: ", paste(unique(dup_within_new), collapse = ", "))
if (any(is.na(new_clusters$cluster_id)) || any(is.na(new_households$cluster_id))) stop("NA cluster_id after renumbering.")
if (!setequal(unique(new_clusters$cluster_id), unique(new_households$cluster_id))) stop("Cluster IDs in new_clusters and new_households disagree after renumbering.")
if (anyDuplicated(new_households$survey_id) > 0) stop("Duplicate survey_id(s) after renumbering.")
log_msg("  Verified: %d new cluster_id(s), all unique, zero collisions with the live WORKING frame, clusters/households agree, survey_ids unique.", nrow(new_clusters))

# Site-level collision check against the EXISTING live frame - the IDP
# equivalent of the Non-IDP script's building_id-overlap check. Tier 2
# deliberately allows redrawing a hex already used by an EXISTING WORKING-
# frame cluster (not just one used elsewhere in this batch, which select_
# stage2_idp_sites() already merges correctly via selection_count). If that
# happens, the new cluster's representative site is picked the same
# deterministic way (largest by household count) as the existing cluster
# already uses - meaning the SAME physical DTM site ends up assigned to two
# separate cluster_ids, planning two field visits to one location.
#
# Match key is (iom_site_id, iom_site_name), NOT iom_site_id alone - found
# 2026-08-30 that iom_site_id carries generic placeholder values ("New
# Camp", "New HC") for unregistered DTM sites, shared across many genuinely
# different physical locations nationally (5 and 16 respectively) - matching
# on iom_site_id alone produced 3 false-positive "collisions" (Nadabo
# Primary School Camp, Danbaza, Gidankano - each a different real site that
# just happens to lack a real SSID) that a name-blind check would have
# wrongly tried to merge into an unrelated existing cluster.
#
# Jack's decision (2026-08-30): a genuine repeat-site match gets MERGED into
# the existing live cluster's target_households/reserve_households (the
# same selection_count-scaling logic merge_repeated_psu_draws() already
# applies WITHIN one draw call, just reaching across into an already-staged/
# fielded cluster here) rather than shipped as a second, separate cluster_id
# at the same location or silently dropped.
existing_sites_idp <- working %>%
  dplyr::filter(pop_type == "idp", !is.na(iom_site_id)) %>%
  dplyr::distinct(iom_site_id, iom_site_name, cluster_id)

dup_site_key <- existing_sites_idp %>% dplyr::count(iom_site_id, iom_site_name) %>% dplyr::filter(n > 1)
if (nrow(dup_site_key) > 0) {
  stop("(iom_site_id, iom_site_name) is not a 1:1 key onto an existing cluster_id in the live frame - ",
       "cannot safely merge repeat-site draws until this is resolved: ",
       paste(sprintf("%s / %s", dup_site_key$iom_site_id, dup_site_key$iom_site_name), collapse = "; "))
}

new_clusters_df <- sf::st_drop_geometry(new_clusters)
site_match <- new_clusters_df %>%
  dplyr::select(cluster_id, uuid_hex_pop, iom_site_id, iom_site_name) %>%
  dplyr::inner_join(existing_sites_idp, by = c("iom_site_id", "iom_site_name"), suffix = c("", "_existing"))

log_msg("  Checked new IDP cluster(s) against the live WORKING frame's existing (site_id, site_name) - %d of %d genuinely share a site with an already-fielded cluster (name-matched, not just placeholder-ID-matched).",
        nrow(site_match), nrow(new_clusters_df))
if (nrow(site_match) > 0) {
  log_msg("  Will MERGE into the existing cluster (not ship as a new cluster_id): %s",
          paste(sprintf("%s (new, dropped) -> %s (existing, target increased)", site_match$cluster_id, site_match$cluster_id_existing), collapse = "; "))
}

repeat_ids <- site_match$cluster_id
genuine_new_clusters <- new_clusters %>% dplyr::filter(!cluster_id %in% repeat_ids)
genuine_new_households <- new_households %>% dplyr::filter(!cluster_id %in% repeat_ids)
repeat_new_clusters <- new_clusters_df %>% dplyr::filter(cluster_id %in% repeat_ids)

log_msg("Stage F: %d genuinely new cluster(s) (new site, no live-frame match) vs %d repeat-site cluster(s) to merge into %d existing cluster(s).",
        nrow(genuine_new_clusters), length(repeat_ids), dplyr::n_distinct(site_match$cluster_id_existing))

# ---- Stage F: merge repeat-site draws into their existing live cluster ----
if (nrow(site_match) > 0) {

  merge_increase <- repeat_new_clusters %>%
    dplyr::select(cluster_id, target_households, reserve_households) %>%
    dplyr::left_join(site_match %>% dplyr::select(cluster_id, cluster_id_existing), by = "cluster_id") %>%
    dplyr::group_by(cluster_id_existing) %>%
    dplyr::summarise(
      increase_target = sum(target_households),
      increase_reserve = sum(reserve_households),
      absorbed_new_cluster_ids = paste(cluster_id, collapse = "; "),
      .groups = "drop"
    ) %>%
    dplyr::rename(cluster_id = cluster_id_existing)

  existing_current <- working %>%
    dplyr::filter(cluster_id %in% merge_increase$cluster_id) %>%
    dplyr::group_by(cluster_id) %>%
    dplyr::summarise(
      old_target = dplyr::first(target_households),
      old_reserve = dplyr::first(reserve_households),
      old_max_primary = suppressWarnings(max(interview_number, na.rm = TRUE)),
      old_max_reserve = suppressWarnings(max(replacement_rank, na.rm = TRUE)),
      .groups = "drop"
    )

  target_increases <- merge_increase %>%
    dplyr::left_join(existing_current, by = "cluster_id") %>%
    dplyr::mutate(
      new_target = old_target + increase_target,
      new_reserve = old_reserve + increase_reserve
    )
  write_csv(target_increases, file.path(STAGING_DIR, "existing_cluster_target_increases_idp.csv"))
  log_msg("  %d existing cluster(s) get target_households increased (e.g. %s): see existing_cluster_target_increases_idp.csv",
          nrow(target_increases), paste(sprintf("%s: %d->%d", target_increases$cluster_id[1], target_increases$old_target[1], target_increases$new_target[1]), collapse = ""))

  # Build the new interview-slot rows to APPEND to each affected existing
  # cluster - template each row off that cluster's own existing rows in
  # `working` (every column except survey_id/status/interview_number/
  # replacement_rank is constant within a cluster_id - verified against the
  # WORKING csv schema directly, 2026-08-30), so ward/admin3/GPS/site
  # attribution etc. are correct without recomputing anything.
  build_additional_rows <- function(cid, inc_target, inc_reserve, old_max_p, old_max_r) {
    template <- working %>% dplyr::filter(cluster_id == cid) %>% dplyr::slice(1)
    primary_new <- template[rep(1, inc_target), ] %>%
      dplyr::mutate(
        status = "primary",
        interview_number = old_max_p + seq_len(inc_target),
        replacement_rank = NA_real_,
        survey_id = sprintf("%s_HH%02d", cid, old_max_p + seq_len(inc_target))
      )
    reserve_new <- template[rep(1, inc_reserve), ] %>%
      dplyr::mutate(
        status = "reserve",
        interview_number = NA_real_,
        replacement_rank = old_max_r + seq_len(inc_reserve),
        survey_id = sprintf("%s_R%02d", cid, old_max_r + seq_len(inc_reserve))
      )
    dplyr::bind_rows(primary_new, reserve_new)
  }

  existing_cluster_additions <- purrr::pmap_dfr(
    target_increases %>% dplyr::select(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve),
    function(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve) {
      build_additional_rows(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve)
    }
  )

  if (anyDuplicated(c(existing_cluster_additions$survey_id, working$survey_id)) > 0) {
    stop("New survey_id(s) for existing-cluster additions collide with the live frame or each other.")
  }
  write_csv(existing_cluster_additions, file.path(STAGING_DIR, "existing_cluster_household_additions_idp.csv"))
  log_msg("  %d new household interview-slot row(s) built to append to those %d existing cluster(s), verified: zero survey_id collisions with the live frame.",
          nrow(existing_cluster_additions), nrow(target_increases))

} else {
  target_increases <- tibble::tibble()
  existing_cluster_additions <- tibble::tibble()
}

st_write(genuine_new_clusters, file.path(STAGING_DIR, "new_clusters_idp.gpkg"), delete_layer = TRUE, quiet = TRUE)
write_csv(st_drop_geometry(genuine_new_households), file.path(STAGING_DIR, "new_households_idp.csv"))
write_csv(st_drop_geometry(genuine_new_clusters), file.path(STAGING_DIR, "new_clusters_idp.csv"))

summary_by_strata <- st_drop_geometry(genuine_new_clusters) %>%
  dplyr::group_by(strata_id, adm2_pcode) %>%
  dplyr::summarise(new_clusters = dplyr::n(), new_households_via_new_cluster = sum(target_households), .groups = "drop")
write_csv(summary_by_strata, file.path(STAGING_DIR, "summary_by_stratum_idp.csv"))

log_msg("==== DONE. %d genuinely new IDP cluster(s) (%d household rows) + %d existing cluster(s) target-increased (%d additional household rows via merge), across %d strata. ====",
        nrow(genuine_new_clusters), nrow(genuine_new_households),
        if (nrow(site_match) > 0) nrow(target_increases) else 0L,
        if (nrow(site_match) > 0) nrow(existing_cluster_additions) else 0L,
        dplyr::n_distinct(new_clusters_df$strata_id))
if (any(!final_check$fully_closed)) {
  still_short <- final_check %>% filter(!fully_closed)
  log_msg("  STILL UNCLOSABLE (candidate DTM hex/site pool exhausted under current data - documented as a real data ceiling, per Jack's decision 2026-08-30): %s",
          paste(still_short$strata_key, collapse = ", "))
}
log_msg("Staged in: %s", STAGING_DIR)
log_msg("NOT merged into the live WORKING/FULL frame - staged for review only.")
close(log_con)
