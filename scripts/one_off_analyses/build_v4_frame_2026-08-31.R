# ==============================================================================
# Build the v4 sampling frame - corrects two bugs found in v3 (which was
# already handed to the data officer) via a full audit sweep Jack asked for
# after he caught v3 potentially still counting stale/inaccessible surveys:
#
#   BUG 1 - ward-level accessibility never reached the household frame.
#     The accessibility impact workbook computes per-cluster accessible
#     status (to decide how many new clusters to draw) but never writes
#     that back into the sampling frame's own coverage_status column -
#     that column only ever tracked partner-coverage-declined and
#     population-sub-floor exclusion (whole STRATA), never "this
#     individual cluster's ward is now inaccessible." Result: v3's WORKING
#     still contained 7,597 not-yet-collected rows (566 clusters, 86
#     strata) sitting in wards currently marked Inaccessible - both
#     original clusters wiped out by this week's accessibility loss AND,
#     worse, 52 of the 375 NEWLY-drawn clusters this week (14%), because
#     the draw scripts pull candidates from a cached hex-level accessible
#     layer (input_data/boundaries/nga_hexagons/accessible_hex.rds) dated
#     2026-08-06 - three weeks stale, predating every accessibility report
#     ingested this week. That cache needs regenerating separately (not
#     done here - flagged as a follow-up, this script only patches the
#     symptom in the delivered frame, not the draw pipeline's own cache).
#
#   BUG 2 - stale target_households/reserve_households on 29 IDP clusters.
#     Every "expand an existing cluster" merge this week (Stage F) appends
#     new interview-slot rows via existing_cluster_household_additions_idp.csv,
#     but that file stamps the NEW rows with the OLD (pre-increase) target/
#     reserve value instead of the NEW one - so a cluster expanded 6->12
#     ends up with 12 rows correctly saying target=12 and 12 rows
#     incorrectly saying target=6. Row COUNT is right (24 rows matches a
#     genuine 12/12 cluster); the LABEL on half of them is wrong. Caught by
#     the per-cluster row-count-vs-capacity audit Jack asked for - a naive
#     "rows > target+reserve" check using whichever row happens to be
#     read first would have wrongly flagged this as 3 clusters with too
#     many rows (and risked deleting genuine, valid rows if patched
#     carelessly) instead of correctly diagnosing it as 29 clusters with
#     an inconsistent label. Fix: set target_households/reserve_households
#     to the MAX value seen across a cluster's own rows, uniformly.
#
# Also re-derives the achieved-interview set from a FRESHLY REBUILT
# real_submissions.csv (2_monitoring/dashboard_app/data/real_submissions.csv
# was last built 2026-08-30 23:06 - stale by a full day of fielding;
# rebuilt via cleaning/real/prep_real_submissions.R immediately before this
# script ran, 12,522 rows vs the prior 11,906).
#
# Archived pre-change copy: _archive/2026-08-31_pre_v4_frame_build/
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(here)
})

output_dir <- here("output")
sf_dir     <- here(output_dir, "data", "data_collection")
resamp_dir <- here("resampling")
monitoring_dir <- here("..", "2_monitoring")

log_lines <- character(0)
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); log_lines <<- c(log_lines, m) }

# =============================================================================
# STEP 0: load v3 (already has FACT's revert + 12-strata exclusion applied)
# =============================================================================
full_v3    <- read_csv(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v3_FULL.csv"), show_col_types = FALSE)
strata_full_v3 <- read_csv(here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v3_FULL.csv"), show_col_types = FALSE)
log_msg("Loaded v3 FULL: %d rows, %d distinct clusters", nrow(full_v3), n_distinct(full_v3$cluster_id))

# =============================================================================
# BUG FIX 1: stale target_households/reserve_households on expanded clusters
# =============================================================================
stale_fix <- full_v3 %>%
  group_by(cluster_id) %>%
  mutate(
    .correct_target  = max(as.numeric(target_households)),
    .correct_reserve = max(as.numeric(reserve_households))
  ) %>%
  ungroup()
n_target_fixed  <- sum(stale_fix$target_households  != stale_fix$.correct_target)
n_reserve_fixed <- sum(stale_fix$reserve_households != stale_fix$.correct_reserve)
fixed_clusters <- stale_fix %>% filter(target_households != .correct_target) %>% distinct(cluster_id) %>% pull(cluster_id)
log_msg("\nBUG FIX 1: stale target/reserve label on expanded clusters")
log_msg("  %d row(s) had target_households corrected, %d row(s) had reserve_households corrected", n_target_fixed, n_reserve_fixed)
log_msg("  across %d cluster(s): %s", length(fixed_clusters), paste(fixed_clusters, collapse = ", "))

full_v4 <- stale_fix %>%
  mutate(target_households = .correct_target, reserve_households = .correct_reserve) %>%
  select(-.correct_target, -.correct_reserve)

# sanity: row count must be unchanged (this is a label fix, not a row fix)
stopifnot(nrow(full_v4) == nrow(full_v3))

# =============================================================================
# BUG FIX 2: per-cluster ward accessibility, joined onto FULL as a new
# informational column, then used to filter WORKING (FULL keeps every row -
# "FULL contains all", per Jack's own definition)
# =============================================================================
ward_status_tbl <- read_csv(
  here(resamp_dir, "output", "master_accessibility_status_ward_level.csv"),
  show_col_types = FALSE
) %>%
  select(adm1_name = State, adm2_name = LGA, adm3_name = `Ward (GRID3)`, ward_accessible_status = `Accessible status`) %>%
  distinct(adm1_name, adm2_name, adm3_name, .keep_all = TRUE)

full_v4 <- full_v4 %>%
  left_join(ward_status_tbl, by = c("adm1_name", "adm2_name", "adm3_name"))

n_unknown_ward <- sum(is.na(full_v4$ward_accessible_status))
log_msg("\nBUG FIX 2: joined current ward accessibility onto FULL v4 (new column: ward_accessible_status)")
log_msg("  %d row(s) had no matching ward in the accessibility table (left as NA, not stripped from WORKING - treated as accessible by default since status is genuinely unknown, not confirmed inaccessible)", n_unknown_ward)

n_inaccessible_rows <- sum(full_v4$ward_accessible_status == "Inaccessible", na.rm = TRUE)
n_inaccessible_clusters <- full_v4 %>% filter(ward_accessible_status == "Inaccessible") %>% distinct(cluster_id) %>% nrow()
log_msg("  %d row(s) across %d cluster(s) currently sit in a ward marked Inaccessible", n_inaccessible_rows, n_inaccessible_clusters)

write_csv(full_v4, here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"), na = "NA")
log_msg("\nWrote FULL v4: %d rows (row count unchanged from v3 - FULL keeps every row, accessibility is informational only)", nrow(full_v4))

# strata-level FULL v4: carry the same target/reserve fix through (strata
# CSV's own target_sample/achieved_sample columns are stratum aggregates,
# not per-cluster - not affected by Bug Fix 1's per-row label issue, so
# strata_full_v3 carries forward unchanged other than being re-saved as v4)
write_csv(strata_full_v3, here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v4_FULL.csv"), na = "NA")

# =============================================================================
# STEP: re-derive ACHIEVED from the FRESHLY REBUILT real_submissions.csv
# (rebuilt via prep_real_submissions.R immediately before this script ran -
# was stale by a full day of fielding: 11,906 -> 12,522 rows)
# =============================================================================
del_dir <- here(monitoring_dir, "cleaning", "real", "handoff_for_resampling")
del_candidates <- list.files(del_dir, pattern = "^revised_deletion_log_for_resampling_.*\\.csv$", full.names = TRUE)
deletion_log_path <- del_candidates[which.max(file.mtime(del_candidates))]
log_msg("\nUsing deletion log: %s", basename(deletion_log_path))
deletion_uuids <- read_csv(deletion_log_path, show_col_types = FALSE)$uuid

subs <- read_csv(here(monitoring_dir, "dashboard_app", "data", "real_submissions.csv"), show_col_types = FALSE)
log_msg("real_submissions.csv: %d rows (freshly rebuilt)", nrow(subs))
subs <- subs %>%
  mutate(achieved = interview_outcome == "completed" &
                     is_duplicate != "TRUE" &
                     !(matched_survey_id %in% c(NA, "", "NA")) &
                     !(submission_uuid %in% deletion_uuids))
achieved <- subs %>% filter(achieved)
log_msg("Real achieved (canonical, post-deletion): %d of %d submissions", nrow(achieved), nrow(subs))

achieved_non_idp_survey_ids <- achieved %>% filter(pop_type == "non_idp") %>% pull(matched_survey_id) %>% unique()
achieved_idp_counts <- achieved %>% filter(pop_type == "idp") %>% count(matched_cluster_id, matched_status, name = "n_achieved")
log_msg("Non-IDP achieved survey_ids (exact join): %d", length(achieved_non_idp_survey_ids))
log_msg("IDP clusters with achieved interviews (count-based removal): %d", nrow(achieved_idp_counts))

# =============================================================================
# STEP: build WORKING v4 = FULL v4, covered & not excluded, ward-accessible,
#       MINUS achieved (exact for Non-IDP, count-based for IDP)
# =============================================================================
covered_v4 <- full_v4 %>%
  filter(coverage_status == "covered", exclusion_reason == "none") %>%
  filter(is.na(ward_accessible_status) | ward_accessible_status == "Accessible")
n_dropped_for_access <- (full_v4 %>% filter(coverage_status == "covered", exclusion_reason == "none") %>% nrow()) - nrow(covered_v4)
log_msg("\nWORKING v4 candidate pool: %d rows (dropped %d row(s) for sitting in an inaccessible ward)", nrow(covered_v4), n_dropped_for_access)

non_idp_rows <- covered_v4 %>% filter(pop_type == "non_idp")
idp_rows     <- covered_v4 %>% filter(pop_type == "idp")

n_non_idp_before <- nrow(non_idp_rows)
non_idp_rows <- non_idp_rows %>% filter(!(survey_id %in% achieved_non_idp_survey_ids))
log_msg("Non-IDP: %d -> %d rows (dropped %d achieved)", n_non_idp_before, nrow(non_idp_rows), n_non_idp_before - nrow(non_idp_rows))

idp_primary <- idp_rows %>% filter(status == "primary") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "primary") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  group_by(cluster_id) %>% arrange(interview_number, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>% filter(rn > n_achieved) %>% ungroup() %>% select(-n_achieved, -rn)

idp_reserve <- idp_rows %>% filter(status == "reserve") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "reserve") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  group_by(cluster_id) %>% arrange(replacement_rank, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>% filter(rn > n_achieved) %>% ungroup() %>% select(-n_achieved, -rn)

n_idp_before <- nrow(idp_rows)
idp_rows <- bind_rows(idp_primary, idp_reserve)
log_msg("IDP: %d -> %d rows (dropped %d achieved, count-based)", n_idp_before, nrow(idp_rows), n_idp_before - nrow(idp_rows))

working_v4 <- bind_rows(non_idp_rows, idp_rows) %>% select(all_of(names(full_v4)))
log_msg("\nWORKING v4 final: %d rows, %d distinct clusters", nrow(working_v4), n_distinct(working_v4$cluster_id))

strata_working_v4 <- strata_full_v3 %>% filter(coverage_status == "covered", exclusion_reason == "none")

write_csv(working_v4, here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"), na = "NA")
write_csv(strata_working_v4, here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"), na = "NA")
log_msg("\nWrote v4 WORKING files to %s", sf_dir)

# =============================================================================
# POST-BUILD AUDIT - rerun the same checks against v4 to confirm it's clean
# =============================================================================
log_msg("\n==== POST-BUILD AUDIT ====")

# 1. per-cluster row count vs (corrected) target+reserve capacity
cap_check <- working_v4 %>%
  group_by(cluster_id) %>%
  summarise(n_rows = n(), cap = first(as.numeric(target_households)) + first(as.numeric(reserve_households)), .groups = "drop") %>%
  filter(n_rows > cap)
log_msg("Clusters where WORKING v4 row count exceeds target+reserve capacity: %d", nrow(cap_check))

# 2. duplicate survey_ids
dupe_check <- working_v4 %>% count(survey_id) %>% filter(n > 1)
log_msg("Duplicate survey_ids in WORKING v4: %d", nrow(dupe_check))

# 3. target/reserve consistency within a cluster (Bug Fix 1's check, rerun)
consistency_check <- working_v4 %>% group_by(cluster_id) %>%
  summarise(n_target_vals = n_distinct(target_households), n_reserve_vals = n_distinct(reserve_households), .groups = "drop") %>%
  filter(n_target_vals > 1 | n_reserve_vals > 1)
log_msg("Clusters with inconsistent target/reserve labels in WORKING v4: %d", nrow(consistency_check))

# 4. any row still sitting in an Inaccessible ward
residual_inaccessible <- working_v4 %>% filter(ward_accessible_status == "Inaccessible") %>% nrow()
log_msg("WORKING v4 rows still in an Inaccessible ward (should be 0): %d", residual_inaccessible)

# 5. any row belonging to an excluded/not-covered stratum (should be 0)
residual_excluded <- working_v4 %>% filter(coverage_status != "covered" | exclusion_reason != "none") %>% nrow()
log_msg("WORKING v4 rows belonging to an excluded/not-covered stratum (should be 0): %d", residual_excluded)

# 6. any of FACT's 39 reverted cluster_ids still present anywhere (should be 0)
fact_new_clusters <- read_csv(here(resamp_dir, "output", "resample_runs", "FACT", "2026-08-30", "new_clusters_non_idp.csv"), show_col_types = FALSE)
subfloor_pcodes_check <- c("NG021008","NG021013","NG021029","NG021031","NG022016")
reverted_ids_check <- fact_new_clusters %>% filter(adm2_pcode %in% subfloor_pcodes_check) %>% pull(cluster_id)
residual_reverted <- sum(full_v4$cluster_id %in% reverted_ids_check)
log_msg("Reverted FACT cluster rows still present in FULL v4 (should be 0): %d", residual_reverted)

# 7. strata that are "covered" but now have ZERO rows in WORKING v4 (fully
#    neutralized by the accessibility/achieved filters - needs a human look,
#    not auto-resampled here)
covered_strata_ids <- strata_working_v4$strata_id
strata_with_rows <- unique(working_v4$strata_id)
zeroed_out <- setdiff(covered_strata_ids, strata_with_rows)
log_msg("\nStrata marked 'covered' with ZERO rows left in WORKING v4 (flag for review, not auto-fixed): %d", length(zeroed_out))
if (length(zeroed_out) > 0) log_msg("  %s", paste(zeroed_out, collapse = ", "))

log_msg("\n=== v4 BUILD + AUDIT COMPLETE ===")
writeLines(log_lines, here(sf_dir, "_v4_build_log_2026-08-31.txt"))
