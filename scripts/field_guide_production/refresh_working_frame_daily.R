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
#     (household- and strata-level) is overwritten, in place, same v6
#     filenames - this is routine maintenance of "what's currently
#     outstanding/currently accessible," not the kind of substantive change
#     this project's _v4_/_v6_ versioning convention is reserved for.
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
source("scripts/shared/assert_plausible.R")
# 2026-09-13: the achieved/accessibility/strata-aggregation logic below is
# now a real shared call (scripts/shared/frame_status.R), not a mirrored
# copy - this and merge_partner_resample_batch.R had already drifted twice
# (the below-4-threshold rule, then the MSNA Light exclusion) under the
# "duplicated, not imported" convention this project otherwise deliberately
# keeps everywhere else. See that file's own header for why this one case
# gets a real source() instead.
source("scripts/shared/frame_status.R")
# 2026-09-14 (Jack-approved, Coordinator co-designed - Part 1 of the
# "2_monitoring sat stale on our fixes" two-part fix): a real, pure-logging
# audit trail of when WORKING materially changes, so a stale downstream
# mirror has something concrete to diff against instead of being found
# stale by accident. See that file's own header for full context.
source("scripts/shared/log_pipeline_change.R")

SF_DIR <- "output/data/data_collection"
FULL_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v12_FULL.csv")
WORKING_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v12_WORKING.csv")
STRATA_WORKING_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v12_WORKING.csv")
CLUSTER_STATUS_CSV <- file.path(SF_DIR, "NGA_MSNA_2026_cluster_status_v12.csv")
# CORRECTED 2026-09-08: was hardcoded to the dashboard_app/data/ mirror,
# which only refreshes on a full deploy_dashboard.R run - flagged repeatedly
# during the 2026-09-07 incident review as a real, live staleness risk
# (this script could silently run against a submissions snapshot that's a
# full deploy cycle old). Canonical is 2_monitoring/data/real_submissions.csv;
# the dashboard_app copy is the derived mirror, not the other way around.
REAL_SUBMISSIONS_CSV <- file.path(MONITORING_DIR, "data", "real_submissions.csv")

log_lines <- character(0)
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); log_lines <<- c(log_lines, m) }

# ---- Step 0 (2026-09-17): resweep FULL's ward_accessible_status against
# the current master ward file BEFORE anything below reads it. Closes the
# gap documented in CLAUDE.md's "Incident 2026-09-07" / Update 2026-09-08d
# ("FACT legacy-gap") - ward_accessible_status on an already-merged row was
# only ever a one-time snapshot from whenever that row was staged/last
# resweeped, with nothing keeping it in sync as the live master file moved
# on. That gap was previously closed only once, by hand
# (resweep_full_ward_accessible_status_2026-09-07.py, run manually
# 2026-09-08), and has been silently reaccumulating since - exactly the
# "two steps, someone forgets the order" shape flagged repeatedly this
# project's history. Wired in here as this script's own first step instead
# of a separately-remembered standalone script, so it can't be skipped.
# Real transition counts logged below (not just "ran successfully") so a
# genuinely partner-facing flip (Inaccessible -> Accessible reopens a
# cluster into WORKING) is always visible, not a silent diff.
resweep_result <- system2(
  "python3",
  args = shQuote("resampling/scripts/resweep_full_ward_accessible_status_2026-09-07.py"),
  stdout = TRUE, stderr = TRUE
)
log_msg("\n---- Step 0: FULL ward_accessible_status resweep ----")
for (l in resweep_result) log_msg("%s", l)
if (!is.null(attr(resweep_result, "status")) && attr(resweep_result, "status") != 0) {
  stop("resweep_full_ward_accessible_status_2026-09-07.py failed - see output above. Not safe to continue with a FULL frame the resweep may have left half-written.")
}

# 2026-09-13: realized_moe() is now realized_moe_unequal() (scripts/shared/
# frame_status.R) - Jack's explicit call (Task 4) for the proper Kish-style
# unequal-cluster-size DEFF formula rather than the simple average-size
# correction, since it strictly generalizes the old uniform-m formula
# (verified algebraically to reduce to it exactly when cluster sizes don't
# vary) rather than being a different formula for the common case.

log_msg("=== WORKING frame refresh: %s ===", format(Sys.time()))
log_msg("Real-submissions source: %s (modified %s)", REAL_SUBMISSIONS_CSV, format(file.info(REAL_SUBMISSIONS_CSV)$mtime))

full_df <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
subs <- read_csv(REAL_SUBMISSIONS_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- canonical is_achieved(), mirrored from 2_monitoring/dashboard_app/
# global.R exactly - see header note. ----------------------------------------
#
# 2026-09-06, Jack's policy decision on quality_exclusion_reason (relayed via
# the orchestrator session): deletion confirmation requires a genuine,
# deliberate decision (partner recovery-workbook response or a reviewed
# internal call), never an automatic/timeout default - and as of tonight,
# nothing in the recovery_issue_tracker.csv-based confirmed-deletion process
# meets that bar (10 registered confirmed_deletion-type issues, all still
# contested). SEPARATELY, Jack confirmed duration_under_20 and fcs_zero
# specifically bypass that appeal process entirely and go straight to
# confirmed_deleted (confirmed_by=internal_team) - these are validated
# methodological thresholds from piloting (under 20 min can't cover the
# questionnaire; all-8-FCS-components-zero is implausible as a real
# response), not ambiguous judgment calls needing field input, unlike the
# other rule categories the pipeline can produce (GPS-duplicate-point,
# pct_missing_flagged, no_consent, listing_missing - explicitly still NOT
# confirmed, treat as achieved-eligible for now). The permanent mechanism
# (2_monitoring's tracker/overlay rebuild) isn't ready yet, so for now this
# reads real_submissions.csv's own quality_exclusion_reason column directly
# as a stopgap - verified 2026-09-06 that its only two populated values ARE
# exactly duration_under_20/fcs_zero (578 rows: 547+31), so this is a precise
# implementation of the decision, not an approximation. Written as an
# explicit inclusion-list (only these two values exclude), NOT the previous
# "any non-blank value excludes" - so if/when the pipeline starts populating
# one of the other four categories, those rows correctly stay achieved-
# eligible instead of being silently excluded by an over-broad filter. Zero
# effect on today's actual figures (confirmed: no other reason value
# currently exists in the data) - this is a forward-looking precision fix,
# not a behavior change.
#
# 2026-09-07 SUPERSEDES the above: the permanent mechanism IS ready now -
# 2_monitoring's recovery_issue_tracker.csv-based CONFIRMED_DELETIONS_
# OVERLAY.csv, same file 05_build_accessibility_impact_workbook.py was
# repointed to on 2026-09-06 (see CLAUDE.md "Update 2026-09-06b"). Switched
# from the hardcoded reason-string allowlist to reading the overlay's own
# status=="confirmed" directly - found while doing the pre-resampling-run
# readiness check that the tracker has grown past duration_under_20/fcs_zero
# since last night (639 confirmed now, up from 627): 14 more via the
# genuine partner-confirmation channel (no_consent x10, duplicate_point x2,
# gps_no_match_partner_confirmed x2 - all confirmed_by=partner, exactly the
# "genuine deliberate decision" Jack's policy requires, not an automatic
# default). The hardcoded list would have silently kept treating these 14
# as achieved-eligible. Reading the overlay directly means this never goes
# stale again as the tracker keeps moving - no more hardcoded list to
# remember to update. Verified before switching: real_submissions.csv's own
# quality_exclusion_reason column currently matches the overlay's confirmed
# set exactly (2_monitoring is keeping it synced deliberately, per Jack) -
# but the overlay is read directly here regardless, not inferred from that
# column, since that's the actual source of truth and this project already
# saw that column go stale/corrupted once (2026-09-06 evening).
# Still NOT mirrored into build_partner_dc_packages.py (the partner
# workbook) - do this same fix there before rebuilding partner workbooks.
CONFIRMED_DELETIONS_OVERLAY_CSV <- file.path(MONITORING_DIR, "data", "CONFIRMED_DELETIONS_OVERLAY.csv")
deletions_overlay <- read_csv(CONFIRMED_DELETIONS_OVERLAY_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
log_msg("Confirmed-deletions overlay: %d rows (%d confirmed, %d contested/other).",
        nrow(deletions_overlay), sum(deletions_overlay$status == "confirmed"), sum(deletions_overlay$status != "confirmed"))

achieved_lookup <- compute_achieved_lookup(subs, deletions_overlay)
log_msg("Real submissions: %d total, %d achieved (canonical formula).", achieved_lookup$n_total, achieved_lookup$n_achieved)

# ---- Non-IDP: exact survey_id drop ----
achieved_non_idp_survey_ids <- achieved_lookup$non_idp_survey_ids
log_msg("Non-IDP achieved survey_ids (exact join): %d", length(achieved_non_idp_survey_ids))

# ---- IDP: count-based drop per (cluster, primary/reserve) ----
achieved_idp_counts <- achieved_lookup$idp_counts
log_msg("IDP (cluster, status) combinations with achieved interviews: %d", nrow(achieved_idp_counts))

# ---- Stage 1: covered, not-excluded, and currently ward-accessible - the
# design's true in-scope pool right now, BEFORE any field-completion
# filtering. This is what strata-level achieved_clusters/achieved_sample
# below is computed from (see header note on terminology). ------------------
# 2026-09-05, Jack's threshold decision (discussed after seeing how many
# straddling Non-IDP hexagons - a hex spanning two wards with different
# status - end up with only a handful of accessible households left): a
# cluster with FEWER than NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH (4) still-
# accessible primary households is treated as fully inaccessible, not just
# the literal 0-accessible case. Reasoning: those few remaining households
# sit closest to the inaccessible ward's boundary (least reliable to safely
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
# 2026-09-13: this and the covered/covered_accessible computation now come
# from compute_cluster_accessibility() (scripts/shared/frame_status.R) -
# still mirrored (duplicated, not imported) in build_partner_dc_packages.py's
# own NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH logic, since that's Python and can't
# source() this R file - same threshold, same counting basis, kept in sync
# deliberately as before.
NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH <- 4
accessibility <- compute_cluster_accessibility(full_df, NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH)
covered <- accessibility$covered
covered_accessible <- accessibility$covered_accessible
below_threshold_clusters <- accessibility$below_threshold_clusters

covered_by_ward_only <- covered %>% filter(!is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible")
n_ward_inaccessible <- nrow(covered) - nrow(covered_by_ward_only)
n_below_threshold_dropped <- nrow(covered_by_ward_only) - nrow(covered_accessible)
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

# ---- Output-plausibility gate (2026-09-08 audit, pass 4) ----
# Hard invariant, not a fuzzy range: WORKING must never contain a row whose
# ward is currently Inaccessible - this is the exact core invariant the
# 2026-09-07 incident violated. Recomputed independently here (not just
# trusting covered_accessible's own filter above) precisely because the
# whole point is catching a bug in the logic that built working_new, not
# re-confirming what that logic already assumes.
n_working_in_inaccessible_ward <- working_new %>%
  filter(!is.na(ward_accessible_status), ward_accessible_status == "Inaccessible") %>%
  nrow()
assert_plausible("WORKING rows in a currently-Inaccessible ward", n_working_in_inaccessible_ward, c(0, 0),
                  context = "must always be exactly 0 - this is the 2026-09-07 incident's core invariant")

write_csv(working_new, WORKING_CSV, na = "NA")
log_msg("Wrote %s (in place, no version bump).", WORKING_CSV)

# 2026-09-14: changelog entry - only when this run actually changed
# something (row or cluster count differs from the previous run's WORKING).
# A no-op daily refresh (common - most runs find nothing new) correctly
# writes nothing here, keeping the changelog a record of real events, not
# every routine check.
if (nrow(working_new) != nrow(working_old) || n_distinct(working_new$cluster_id) != n_distinct(working_old$cluster_id)) {
  log_pipeline_change(
    script = "refresh_working_frame_daily.R", description = "routine daily refresh",
    old_rows = nrow(working_old), new_rows = nrow(working_new),
    old_clusters = n_distinct(working_old$cluster_id), new_clusters = n_distinct(working_new$cluster_id)
  )
}

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
# the SAME principle applied to achieved_sample. Formalized 2026-09-13 as
# this project's explicit CORE PRINCIPLE (Jack): a completed interview is
# permanent and never retroactively excluded by later accessibility loss;
# current accessibility only gates what's still planned but not yet
# completed. Quantified nationally when first built: 341 real completed
# interviews stranded this way, 254 of them inside the then-current
# 89-strata/1,346-household shortfall list, closing 9 strata's shortfall to
# zero outright - see CLAUDE.md for the full breakdown. sampling_method ==
# "MSNA Light" rows (government-negotiated, unverifiable collection) never
# contribute here, same reasoning as the aggregation below - both are now
# one shared call (scripts/shared/frame_status.R's compute_strata_achieved()),
# not separately-maintained logic.
strata_result <- compute_strata_achieved(full_df, achieved_lookup, accessibility, filter_ward_accessible = TRUE)
log_msg(
  "Stranded-achieved credit: %d real completed interview(s) sit in rows excluded from the accessible pool (ward-inaccessible or below-threshold) - added back into strata-level achieved_sample so the shortfall doesn't double-ask for them.",
  nrow(strata_result$stranded_rows)
)

# 2026-09-13: realized_moe_pct now uses realized_moe_unequal() (Task 4,
# Jack's call - the proper Kish-style unequal-cluster-size DEFF formula),
# fed the real per-cluster achieved sizes for each stratum from strata_
# result$cluster_sizes, not just the nominal m_used uniformly.
cluster_size_vecs <- split(strata_result$cluster_sizes$n, strata_result$cluster_sizes$strata_id)

strata_working_new <- strata_working_old %>%
  left_join(strata_result$agg %>% rename(achieved_clusters_new = achieved_clusters, achieved_sample_new = achieved_sample), by = "strata_id") %>%
  mutate(
    achieved_clusters_new = coalesce(achieved_clusters_new, 0L),
    achieved_sample_new = coalesce(achieved_sample_new, 0L),
    achieved_clusters = achieved_clusters_new,
    achieved_sample = achieved_sample_new,
    realized_moe_pct = mapply(function(strata_id, achieved_sample, N_hh, ICC) {
      if (!(achieved_sample > 0 & achieved_sample < N_hh)) return(NA_real_)
      sizes <- cluster_size_vecs[[strata_id]]
      if (is.null(sizes)) return(NA_real_)
      100 * realized_moe_unequal(achieved_sample, N_hh, sizes, ICC)
    }, strata_id, achieved_sample, N_hh, ICC)
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

# 2026-09-08 audit pass 4 used to gate this with assert_plausible(ceiling)
# here - retired 2026-09-14 (Jack approved). That check measured the
# ever-growing baseline of organic reserve-list substitution (not a
# resampling bug) and needed its own ceiling bumped once already (40->45)
# purely to keep up with normal field progress, not because anything was
# wrong. Task 4's target_sample_representativity STOP-mode gate (05_build_
# accessibility_impact_workbook.py) is the correct, precise replacement -
# it catches an actual resampling-target regression directly, with no
# organic-completion noise and no threshold to ever re-tune. The logging
# above (still_over_target) stays as non-blocking visibility only.

write_csv(strata_working_new, STRATA_WORKING_CSV, na = "NA")
log_msg("Wrote %s (in place, no version bump).", STRATA_WORKING_CSV)

# ---- Per-cluster status (Task 3, 2026-09-13) - completed / partially_
# completed_access_lost / not_started_access_lost / not_started_other.
# Written fresh every run so it's always current for any downstream
# consumer, most importantly draw_supplementary_clusters_batch.R and the
# IDP equivalent's Tier-2 repeat-draw exclusion (Task 3B) - an access-
# compromised cluster's hex/site must never be a repeat-draw candidate,
# and those scripts read this file rather than recomputing cluster status
# themselves (which would mean a 4th copy of the achieved-lookup machinery).
cluster_status <- compute_cluster_status(full_df, achieved_lookup, accessibility, NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH)
write_csv(cluster_status, CLUSTER_STATUS_CSV, na = "NA")
status_counts <- cluster_status %>% count(status)
log_msg("\nPer-cluster status (%s): %d clusters - %s", CLUSTER_STATUS_CSV, nrow(cluster_status),
        paste(sprintf("%s=%d", status_counts$status, status_counts$n), collapse = ", "))

# ---- Final step (2026-09-17): rebuild the combined sampling frame workbook
# (NGA_MSNA_2026_sampling_frame_workbook_v8.xlsx) so it never drifts out of
# sync with the CSVs this run just wrote - Jack's explicit instruction
# ("they should all come together"), same "don't let two related outputs
# drift apart" shape as Step 0's ward-status resweep above. Overwritten IN
# PLACE at its current v8 name every routine refresh (same convention as
# WORKING/strata-level - only a roster-changing version bump gets a new
# v-number, a routine content refresh doesn't). Runs last, after every
# other output this script produces is already on disk, since the
# workbook script reads the FULL/WORKING/strata CSVs directly from disk
# rather than taking them as in-memory objects.
workbook_result <- system2(
  "python3",
  args = shQuote("scripts/partner_coverage/build_partner_coverage_workbook.py"),
  stdout = TRUE, stderr = TRUE
)
log_msg("\n---- Final step: combined sampling frame workbook rebuild ----")
for (l in workbook_result) log_msg("%s", l)
if (!is.null(attr(workbook_result, "status")) && attr(workbook_result, "status") != 0) {
  log_msg("WARNING: combined workbook rebuild failed (see output above) - CSV outputs above are still correct and were written first; only the .xlsx is stale/missing until this is investigated.")
}

log_dir <- file.path(SF_DIR, "_working_refresh_logs")
dir.create(log_dir, showWarnings = FALSE)
writeLines(log_lines, file.path(log_dir, sprintf("_working_refresh_log_%s.txt", format(Sys.Date()))))
cat("\n=== DONE ===\n")
