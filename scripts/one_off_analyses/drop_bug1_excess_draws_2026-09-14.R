# ==============================================================================
# Task-5-style removal of the 9 clusters found excess by audit_tonight_
# draws_vs_bug1_fix_2026-09-14.py, per Jack's explicit go-ahead ("yes,
# remove the 9 excess clusters, task-5-style").
#
# Background: the audit reconstructed each stratum's PRE-DRAW achievable
# ceiling using the corrected (Bug 1) n_primary_ceiling_contribution
# formula, and compared "clusters actually drawn tonight" against "clusters
# the corrected formula says were actually needed." 6 of the 60 strata
# drawn tonight came out oversized by 9 clusters total - all verified
# not_started_other, n_achieved=0 (drawn only hours ago, zero real
# fieldwork lost either way). Full detail: resampling/output/audit_
# tonight_draws_vs_bug1_fix_2026-09-14.csv.
#
# Mechanism: reuses Task 5's own overlay file/pattern (resampling/output/
# target_correction_dropped_clusters.csv - already wired as a third overlay
# input into frame_status.R's compute_cluster_accessibility(), folded into
# covered_accessible/excluded_primary, NOT into compute_cluster_status()'s
# own status computation - a dropped cluster still honestly shows
# status="not_started_other", same as every other Task 5 drop) rather than
# inventing a parallel mechanism - this is conceptually the same class of
# fact ("no longer needed to hit the survey's precision target, removed
# from the active list"), just found via a different, stricter check (the
# Bug-1-corrected ceiling, not Task 5's own achieved_locked-vs-target_
# sample_representativity formula - the two are independent; re-running
# Task 5's own script would NOT have caught this, since it doesn't use
# n_primary_ceiling_contribution at all). Distinguished by its own `reason`
# value so provenance stays auditable; load_target_correction_drops() in
# frame_status.R takes the whole cluster_id column regardless of reason,
# so no code change is needed anywhere else - appending is enough.
#
# Cluster selection already applied Task 5's own tiebreak rule by hand
# (least-progressed first - all 9 tied at n_achieved=0 - then most-
# recently-drawn first via descending _suppN, matching compute_target_
# correction_drops.R's arrange(n_achieved, desc(supp_n))) - hardcoded here
# since this is a one-time, audit-driven action, not a recurring mechanism.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

OVERLAY_CSV <- "resampling/output/target_correction_dropped_clusters.csv"

new_rows <- tribble(
  ~cluster_id,                  ~strata_id,             ~pop_type,  ~n_achieved, ~target_households,
  "non_idp_NG002009_supp5",     "non_idp_NG002009",      "non_idp",  0,           6,
  "non_idp_NG008011_supp10",    "non_idp_NG008011",      "non_idp",  0,           6,
  "non_idp_NG008011_supp9",     "non_idp_NG008011",      "non_idp",  0,           6,
  "non_idp_NG008019_supp32",    "non_idp_NG008019",      "non_idp",  0,           6,
  "non_idp_NG008019_supp31",    "non_idp_NG008019",      "non_idp",  0,           6,
  "non_idp_NG008019_supp29",    "non_idp_NG008019",      "non_idp",  0,           6,
  "non_idp_NG036004_supp5",     "non_idp_NG036004",      "non_idp",  0,           6,
  "non_idp_NG037001_supp10",    "non_idp_NG037001",      "non_idp",  0,           6,
  "non_idp_NG037013_supp14",    "non_idp_NG037013",      "non_idp",  0,           6,
) %>%
  mutate(drop_rank = row_number(), reason = "bug1_ceiling_fix_excess_draw_2026-09-14",
         computed_at = as.character(Sys.time()))

existing <- if (file.exists(OVERLAY_CSV)) {
  read_csv(OVERLAY_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    mutate(n_achieved = as.integer(n_achieved), target_households = as.integer(target_households), drop_rank = as.integer(drop_rank))
} else {
  tibble()
}

stopifnot(!any(new_rows$cluster_id %in% existing$cluster_id))  # append-only - never re-drop something already dropped

combined <- bind_rows(existing, new_rows)
write_csv(combined, OVERLAY_CSV)
cat(sprintf("Appended %d row(s) to %s (was %d, now %d).\n", nrow(new_rows), OVERLAY_CSV, nrow(existing), nrow(combined)))
