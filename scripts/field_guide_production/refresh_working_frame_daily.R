# ==============================================================================
# Daily/every-other-day repeatable refresh of the WORKING frame (household-
# AND strata-level) against live submission data and current ward
# accessibility - so WORKING (and everything built from it: partner KML
# files, the "Needs Collecting"/"Cluster Summary" sheets, target-vs-achieved
# figures) reflects what field teams have actually done and what's actually
# currently reachable, not just whatever changed at the last resample/
# version bump or partner merge.
#
# 2026-09-05: generalises the one-off achieved-row-drop from
# scripts/one_off_analyses/build_v3_frame_2026-08-31.R (Step 3/Steps 4-5)
# into a repeatable step, built while adding a daily partner sampling-points
# status workflow (Jack) - the KML files and old "Sampling Points" sheet
# were found to have gone stale on achieved status too (675 already-
# completed Non-IDP points nationally were still sitting in WORKING),
# which is part of why partners were confused about what they still needed
# to do.
#
# 2026-09-05, same day, EXTENDED after a second, bigger finding: Jack
# noticed this workbook's "achieved" total for FACT (7,118) didn't match
# the live dashboard's (6,946). Traced to a real bug in
# merge_partner_resample_batch.R's recompute_strata() - it counted every
# primary row for a stratum regardless of ward_accessible_status, so a
# cluster accessible when drawn but marked inaccessible LATER (a ward-level
# accessibility update, independent of any merge) stayed counted in
# WORKING's strata-level achieved_sample forever after. Verified nationally:
# this fully or mostly explained 63 of 75 strata where achieved_sample
# exceeded target_sample (structurally impossible under a correctly capped
# mechanism) - national gap 2,897 -> 51 households once corrected. See
# 1_sampling/CLAUDE.md's "Revision 2026-09-05" for the full trace.
# This script now ALSO keeps strata-level WORKING's achieved_clusters/
# achieved_sample/realized_moe_pct correct on the same repeatable cadence,
# instead of leaving that to depend on whichever merge script last touched
# a given stratum.
#
# IMPORTANT TERMINOLOGY, easy to get backwards: strata-level achieved_sample
# is a DESIGN metric ("how many primary slots has the sampling design
# successfully assigned, that are currently accessible" - compared against
# target_sample to see whether the design reached its MoE-driven target).
# It has NEVER meant "how many have been really interviewed" - that's the
# separate, real-submissions-based "achieved" concept this script also uses
# to decide which household-level rows to drop from WORKING. These two
# meanings of "achieved" must not be conflated:
#   - Household-level WORKING (this script's other output) = ward-
#     accessible, covered, NOT YET field-achieved (real submissions) - the
#     literal to-do list, per Jack's request this session that KML/the
#     workbook reflect real field progress.
#   - Strata-level WORKING's achieved_clusters/achieved_sample = ward-
#     accessible, covered, DESIGN-assigned total - deliberately NOT
#     filtered by field-completion, so it stays comparable to target_sample
#     exactly the way it always has. Computed from the ward-accessible
#     subset of FULL BEFORE the achieved-row drop below, not from the
#     household-level WORKING output itself (which has already had
#     achieved rows removed and so would give the wrong - backwards -
#     number if used here).
#
# KEY DIFFERENCES FROM THE AUG-31 SCRIPT (deliberate, not an oversight):
#   - Aug 31 joined a separate "revised_deletion_log_for_resampling_*.csv"
#     on top of is_duplicate to determine achieved. That log hasn't been
#     updated since 2026-08-31 (checked directly) - it's been superseded by
#     2_monitoring's own is_duplicate/quality_exclusion_reason columns on
#     real_submissions.csv itself, which are now self-contained. This script
#     uses ONLY real_submissions.csv's own columns, matching 2_monitoring's
#     current canonical is_achieved() definition (dashboard_app/global.R,
#     ~line 682) EXACTLY - mirrored here (duplicated, not imported, per this
#     project's standalone-script convention) rather than the Aug-31 logic,
#     so this frame and the live dashboard never disagree on what counts as
#     achieved.
#   - Always recomputes WORKING FRESH from FULL every run (never chains off
#     yesterday's WORKING) - idempotent by construction. If a submission is
#     later invalidated (e.g. found fraudulent and its quality_exclusion_
#     reason set), its point correctly REAPPEARS in WORKING next run, not
#     just monotonically shrinks. Same for ward_accessible_status: if a
#     cluster's ward is later reported accessible again, it correctly
#     reappears too.
#   - No version bump. FULL is untouched (it never drops a row, and its own
#     achieved_clusters/achieved_sample stay unfiltered by ward
#     accessibility too - see 1_sampling/CLAUDE.md). Only WORKING
#     (household- and strata-level) is overwritten, in place, same v5
#     filenames - this is routine maintenance of "what's currently
#     outstanding/currently accessible," not the kind of substantive change
#     this project's _v4_/_v5_ versioning convention is reserved for.
#
# Non-IDP achieved: exact survey_id join (frame and submissions share the
# same HH##/R## scheme) - a specific pre-assigned building either has been
# visited or hasn't. IDP achieved: count-based per (cluster, primary/
# reserve) - submissions use on-site listing numbers, not the frame's
# pre-assigned labels (no fixed physical building per IDP slot), so only
# "how many of this cluster's primary/reserve slots are done" is
# meaningful, not which specific one - same logic as the Aug-31 script's
# IDP branch, reused as-is.
#
# 2026-09-05, SAME EVENING, EXTENDED AGAIN - "stranded-achieved" credit.
# Jack asked: what happens to real, already-collected data when its area
# later becomes inaccessible, or a straddling cluster drops below the
# 4-accessible-HH threshold added earlier tonight? Answer found: household-
# level Achieved/Collected already kept full credit (see the block above),
# but strata-level achieved_sample - the design metric the supplementary-
# draw shortfall is sized against - did NOT, because it only ever counted
# rows currently IN covered_accessible. A real completed interview sitting
# in a row that's since been excluded (ward-inaccessible, or below-
# threshold) was silently treated as still-outstanding capacity, inflating
# the shortfall - i.e. asking for NEW households to replace work already
# done. Fixed by adding these "stranded-achieved" rows back into
# achieved_sample specifically (not into household-level WORKING - that
# to-do list correctly still excludes them, nobody should be told to visit
# an inaccessible building). Quantified nationally before implementing: 341
# real completed interviews stranded this way, 254 of them inside the
# then-current 89-strata/1,346-household shortfall list, closing 9 strata's
# shortfall to zero outright - see CLAUDE.md for the full breakdown and the
# same fix mirrored in merge_partner_resample_batch.R's recompute_strata().
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
MONITORING_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring"
setwd(PROJECT_DIR)

SF_DIR <- "output/data/data_collection"
FULL_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv")
WORKING_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v5_WORKING.csv")
STRATA_WORKING_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v5_WORKING.csv")
REAL_SUBMISSIONS_CSV <- file.path(MONITORING_DIR, "dashboard_app", "data", "real_submissions.csv")

log_lines <- character(0)
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); log_lines <<- c(log_lines, m) }

realized_moe <- function(achieved_sample, N_hh, m, ICC, Z = qnorm(0.95), p = 0.5) {
  deff  <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

log_msg("=== WORKING frame refresh: %s ===", format(Sys.time()))
log_msg("Real-submissions source: %s (modified %s)", REAL_SUBMISSIONS_CSV, format(file.info(REAL_SUBMISSIONS_CSV)$mtime))

full_df <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
subs <- read_csv(REAL_SUBMISSIONS_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- canonical is_achieved(), mirrored from 2_monitoring/dashboard_app/
# global.R exactly - see header note. ----------------------------------------
achieved <- subs %>%
  filter(
    interview_outcome == "completed",
    is_duplicate != "TRUE",
    !(matched_survey_id %in% c(NA, "", "NA")),
    quality_exclusion_reason %in% c(NA, "", "NA")
  )
log_msg("Real submissions: %d total, %d achieved (canonical formula).", nrow(subs), nrow(achieved))

# ---- Non-IDP: exact survey_id drop ----
achieved_non_idp_survey_ids <- achieved %>% filter(pop_type == "non_idp") %>% pull(matched_survey_id) %>% unique()
log_msg("Non-IDP achieved survey_ids (exact join): %d", length(achieved_non_idp_survey_ids))

# ---- IDP: count-based drop per (cluster, primary/reserve) ----
achieved_idp_counts <- achieved %>%
  filter(pop_type == "idp") %>%
  count(matched_cluster_id, matched_status, name = "n_achieved")
log_msg("IDP (cluster, status) combinations with achieved interviews: %d", nrow(achieved_idp_counts))

# ---- Stage 1: covered, not-excluded, and currently ward-accessible - the
# design's true in-scope pool right now, BEFORE any field-completion
# filtering. This is what strata-level achieved_clusters/achieved_sample
# below is computed from (see header note on terminology). ------------------
covered <- full_df %>% filter(coverage_status == "covered", exclusion_reason == "none")
covered_accessible <- covered %>% filter(is.na(ward_accessible_status) | ward_accessible_status != "Inaccessible")

# 2026-09-05, Jack's threshold decision (same evening as the ward-
# accessibility fix above, discussed after seeing how many straddling
# Non-IDP hexagons - a hex spanning two wards with different status - end
# up with only a handful of accessible households left): a cluster with
# FEWER than NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH (4) still-accessible
# primary households is treated as fully inaccessible, not just the
# literal 0-accessible case. Reasoning: those few remaining households sit
# closest to the inaccessible ward's boundary (least reliable to safely
# collect - the same concern that argued for a stratum-level, not same-
# hex, supplementary redraw), a dedicated field visit for 1-3 households
# is operationally inefficient, and the stratum-level supplementary draw
# is expected to close the resulting gap instead - see 1_sampling/
# CLAUDE.md's Revision 2026-09-05. NOT a blanket "any straddling cluster"
# rule: checked directly before deciding, of 184 straddling Non-IDP
# clusters nationally 46 have 5 of 6 (or equivalent) STILL accessible,
# clearly still worth collecting - the threshold only drops clusters below
# it, not every mixed-status one. IDP is unaffected (single-point sites,
# no straddling-hex/accessible-household-count concept applies).
# Mirrored (duplicated, not imported, per this project's standalone-script
# convention) in build_partner_dc_packages.py's identical
# NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH / cluster_accessible_primary_n logic -
# same threshold, same counting basis, kept in sync deliberately.
NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH <- 4
cluster_accessible_primary_n <- covered %>%
  filter(pop_type == "non_idp", status == "primary", is.na(ward_accessible_status) | ward_accessible_status != "Inaccessible") %>%
  count(cluster_id, name = "n_accessible_primary")
below_threshold_clusters <- cluster_accessible_primary_n %>%
  filter(n_accessible_primary < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH) %>%
  pull(cluster_id)
n_before_threshold_drop <- nrow(covered_accessible)
covered_accessible <- covered_accessible %>% filter(!(cluster_id %in% below_threshold_clusters))
n_ward_inaccessible <- nrow(covered) - n_before_threshold_drop
n_below_threshold_dropped <- n_before_threshold_drop - nrow(covered_accessible)
log_msg(
  "FULL rows: %d | covered & not excluded: %d | ward-inaccessible rows dropped: %d | below-%d-accessible-HH clusters (%d clusters) also dropped entirely: %d rows | in-scope pool: %d",
  nrow(full_df), nrow(covered), n_ward_inaccessible, NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH,
  length(below_threshold_clusters), n_below_threshold_dropped, nrow(covered_accessible)
)

# ---- Stage 2: household-level WORKING = in-scope pool MINUS field-achieved
# rows (the actual to-do list). ----------------------------------------------
non_idp_rows <- covered_accessible %>% filter(pop_type == "non_idp")
idp_rows <- covered_accessible %>% filter(pop_type == "idp")

n_non_idp_before <- nrow(non_idp_rows)
non_idp_rows <- non_idp_rows %>% filter(!(survey_id %in% achieved_non_idp_survey_ids))
log_msg("Non-IDP: %d -> %d rows (dropped %d achieved)", n_non_idp_before, nrow(non_idp_rows), n_non_idp_before - nrow(non_idp_rows))

idp_primary <- idp_rows %>% filter(status == "primary") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "primary") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L), interview_number = as.integer(interview_number)) %>%
  group_by(cluster_id) %>%
  arrange(interview_number, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>%
  filter(rn > n_achieved) %>%
  ungroup() %>%
  select(-n_achieved, -rn) %>%
  mutate(interview_number = as.character(interview_number))

idp_reserve <- idp_rows %>% filter(status == "reserve") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "reserve") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L), replacement_rank = as.integer(replacement_rank)) %>%
  group_by(cluster_id) %>%
  arrange(replacement_rank, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>%
  filter(rn > n_achieved) %>%
  ungroup() %>%
  select(-n_achieved, -rn) %>%
  mutate(replacement_rank = as.character(replacement_rank))

n_idp_before <- nrow(idp_rows)
idp_rows_after <- bind_rows(idp_primary, idp_reserve)
log_msg("IDP: %d -> %d rows (dropped %d achieved, count-based)", n_idp_before, nrow(idp_rows_after), n_idp_before - nrow(idp_rows_after))

working_new <- bind_rows(non_idp_rows, idp_rows_after) %>% select(all_of(names(full_df)))
log_msg("\nWORKING (household-level, new): %d rows, %d distinct clusters", nrow(working_new), n_distinct(working_new$cluster_id))

working_old <- read_csv(WORKING_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
log_msg("WORKING (household-level, previous): %d rows, %d distinct clusters", nrow(working_old), n_distinct(working_old$cluster_id))

n_clusters_dropped_entirely <- length(setdiff(unique(working_old$cluster_id), unique(working_new$cluster_id)))
log_msg("Clusters now fully achieved/inaccessible and removed entirely from WORKING this run: %d", n_clusters_dropped_entirely)

write_csv(working_new, WORKING_CSV, na = "NA")
log_msg("Wrote %s (in place, no version bump).", WORKING_CSV)

# ---- Strata-level WORKING: achieved_clusters/achieved_sample/
# realized_moe_pct recomputed from covered_accessible (Stage 1 - NOT
# working_new, which has already had field-achieved rows removed and would
# give the wrong, backwards number here - see header note). target_sample/
# clusters_target_stage1/projected_moe_pct/coverage_status/exclusion_reason
# left untouched - same "batch the target_sample recalibration separately"
# rule as merge_partner_resample_batch.R (CLAUDE.md 2026-07-15 fix, Jack's
# 2026-08-30 call). Every covered stratum is refreshed every run (not just
# ones a recent merge happened to touch), so this can't go stale again the
# way relying on each merge script's own recompute did. ----------------------
strata_working_old <- read_csv(STRATA_WORKING_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  mutate(across(c(N_hh, m_used, ICC, target_sample, achieved_clusters, achieved_sample, realized_moe_pct), as.numeric))

# ---- Stranded-achieved credit, added 2026-09-05 (Jack's follow-up: what
# happens to already-collected data when its area later becomes
# inaccessible, or a straddling cluster drops below the 4-accessible-HH
# threshold?). Household-level Achieved/Collected (workbook, dashboard)
# already keep full credit regardless of current accessibility - this is
# the SAME principle applied to achieved_sample, which until now did not:
# a row excluded from covered_accessible (ward-inaccessible, or dropped by
# the threshold rule) that ALREADY has a real completed interview was
# silently treated as still-outstanding capacity, inflating the shortfall
# used to size the supplementary draw - i.e. asking for NEW households to
# replace work that's already done. Quantified nationally before
# implementing: 341 real completed interviews stranded this way (147
# Non-IDP exact-survey_id, 194 IDP count-based, capped per cluster so it
# can never over-credit past what's real), 254 of them inside the
# then-current 89-strata/1,346-household shortfall list, closing 9
# strata's shortfall to zero outright - see CLAUDE.md for the full
# breakdown. Non-IDP: exact survey_id join (achieved_non_idp_survey_ids,
# already computed above for the household-level drop). IDP: count-based
# per cluster, capped at min(excluded rows, achieved count) - can't credit
# more stranded slots than there are excluded rows to represent; specific
# rows picked deterministically (lowest interview_number first) since IDP
# achieved is inherently count-based, not tied to a specific physical slot
# (same reasoning as the household-level IDP achieved-row-drop above).
excluded_primary <- covered %>%
  filter(status == "primary") %>%
  filter(
    (!is.na(ward_accessible_status) & ward_accessible_status == "Inaccessible") |
    (pop_type == "non_idp" & cluster_id %in% below_threshold_clusters)
  )

stranded_non_idp <- excluded_primary %>%
  filter(pop_type == "non_idp", survey_id %in% achieved_non_idp_survey_ids)

idp_excluded <- excluded_primary %>% filter(pop_type == "idp")
idp_cluster_stranded_n <- idp_excluded %>%
  count(cluster_id, name = "n_excluded") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "primary") %>% select(cluster_id = matched_cluster_id, n_achieved), by = "cluster_id") %>%
  mutate(n_achieved = coalesce(n_achieved, 0L), n_stranded = pmin(n_excluded, n_achieved)) %>%
  filter(n_stranded > 0)

stranded_idp <- idp_excluded %>%
  inner_join(idp_cluster_stranded_n %>% select(cluster_id, n_stranded), by = "cluster_id") %>%
  mutate(interview_number_num = as.integer(interview_number)) %>%
  group_by(cluster_id) %>%
  arrange(interview_number_num, .by_group = TRUE) %>%
  filter(row_number() <= n_stranded) %>%
  ungroup() %>%
  select(-interview_number_num)

stranded_rows <- bind_rows(stranded_non_idp, stranded_idp)
log_msg(
  "Stranded-achieved credit: %d Non-IDP + %d IDP = %d real completed interviews sit in rows excluded from the accessible pool (ward-inaccessible or below-threshold) - added back into strata-level achieved_sample so the shortfall doesn't double-ask for them.",
  nrow(stranded_non_idp), nrow(stranded_idp), nrow(stranded_rows)
)

strata_agg <- bind_rows(covered_accessible %>% filter(status == "primary"), stranded_rows) %>%
  group_by(strata_id) %>%
  summarise(achieved_clusters_new = n_distinct(cluster_id), achieved_sample_new = n(), .groups = "drop")

strata_working_new <- strata_working_old %>%
  left_join(strata_agg, by = "strata_id") %>%
  mutate(
    achieved_clusters_new = coalesce(achieved_clusters_new, 0L),
    achieved_sample_new = coalesce(achieved_sample_new, 0L),
    achieved_clusters = achieved_clusters_new,
    achieved_sample = achieved_sample_new,
    realized_moe_pct = if_else(
      achieved_sample > 0 & achieved_sample < N_hh,
      100 * realized_moe(achieved_sample, N_hh, m_used, ICC),
      NA_real_
    )
  ) %>%
  select(-achieved_clusters_new, -achieved_sample_new)

n_strata_changed <- sum(strata_working_old$achieved_sample != strata_working_new$achieved_sample, na.rm = TRUE)
still_over_target <- strata_working_new %>% filter(achieved_sample > target_sample)
log_msg(
  "\nStrata-level WORKING: %d strata refreshed, %d changed achieved_sample. %d stratum/strata still show achieved_sample > target_sample after this fix (should be a small residual, not systemic).",
  nrow(strata_working_new), n_strata_changed, nrow(still_over_target)
)
if (nrow(still_over_target) > 0) {
  for (i in seq_len(nrow(still_over_target))) {
    log_msg("  %s: target=%d achieved=%d", still_over_target$strata_id[i], still_over_target$target_sample[i], still_over_target$achieved_sample[i])
  }
}

write_csv(strata_working_new, STRATA_WORKING_CSV, na = "NA")
log_msg("Wrote %s (in place, no version bump).", STRATA_WORKING_CSV)

log_dir <- file.path(SF_DIR, "_working_refresh_logs")
dir.create(log_dir, showWarnings = FALSE)
writeLines(log_lines, file.path(log_dir, sprintf("_working_refresh_log_%s.txt", format(Sys.Date()))))
cat("\n=== DONE ===\n")
