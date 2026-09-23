# ==============================================================================
# Task 5 (2026-09-13, target-inflation-fix batch): retroactive drop-rule.
# Where Task 2's corrected target (target_sample_representativity) now needs
# FEWER clusters than a stratum currently has actively assigned, drop the
# excess - least-progressed first, most-recently-drawn as tiebreak.
#
# Status-taxonomy question the spec asked to be flagged before building
# (not silently decided): dropping for CAPACITY reasons (stratum needs
# fewer clusters than it has) is a genuinely different kind of exclusion
# from the existing 4-value completion-status taxonomy
# (NGA_MSNA_2026_cluster_status_v13.csv, all 4 values are accessibility/
# completion-driven) - none of them mean "still accessible, still
# incomplete, but no longer needed." Rather than force this into that
# taxonomy or invent a 5th status value there (which would muddy a function
# other scripts already depend on for a different purpose), this reuses
# this project's own established OVERLAY pattern instead - the exact same
# shape as cluster_accessibility_overlay.csv (build_cluster_accessibility_
# overlay.py, 2026-09-13 earlier tonight): a small, derived, single-purpose
# exclusion list that refresh_working_frame_daily.R additionally excludes
# from WORKING, without touching the cluster-status function's own
# accessibility-only semantics. Candidate pool for dropping is exactly
# NGA_MSNA_2026_cluster_status_v13.csv's "not_started_other" status - the
# ONLY one of the 4 that means "currently accessible, actively assigned,
# not yet fully done" (the other 3 are either already-excluded-for-
# accessibility or already-permanently-completed, neither of which this
# task should touch).
#
# "Most-recently-drawn" tiebreak, worth being explicit about since no real
# draw-date column exists anywhere in the frame: uses the numeric suffix on
# a supplementary cluster_id (e.g. "..._supp7" -> 7; a plain original
# cluster_id with no _supp suffix -> 0) as a recency proxy - this project's
# own supplementary-draw scripts already renumber continuing each stratum's
# _supp sequence in order (see CLAUDE.md, multiple entries), so a HIGHER
# number genuinely means "drawn later" within that stratum. An approximation,
# not a real timestamp - flagged as such, not silently treated as exact.
#
# CUMULATIVE, APPEND-ONLY, safe to rerun (2026-09-14, wired live per Jack's
# go-ahead): a cluster already in the drop list from a prior run is NEVER
# re-decided or re-dropped - it's carried forward unchanged, and excluded
# from the candidate pool so it can't be "un-dropped" by a shifting target
# on a later run either. Only genuinely NEW excess (given the current
# target_sample_representativity and the current, already-reduced pool of
# still-active not_started_other clusters) gets added on top. This file is
# read live by scripts/shared/frame_status.R's compute_cluster_
# accessibility() (default parameter, load_target_correction_drops()) -
# every cluster_id in it is excluded from WORKING + gets stranded-achieved
# credit preserved the next time refresh_working_frame_daily.R runs. This
# script only ever writes the list; it does not itself touch WORKING/FULL -
# run refresh_working_frame_daily.R afterward to actually apply it.
#
# ---- 2026-09-21 (Task 2 of Jack's five): THE TEST ITSELF WAS REPLACED ----
# The original test (kept below only as history) dropped clusters whenever
# the achieved in COMPLETED clusters met target_sample_representativity -
# a target built on the equal-cluster-size formula, the same understatement
# as the Feasibility bug. It ignored partially-done clusters and never
# looked at the MoE that decides representativity. Of the 76 clusters it
# dropped on 2026-09-13/14, 18 were still accessible and unstarted in 10
# strata that were NOT representative; reinstating them (Jack, 2026-09-21,
# logged in resampling/output/target_correction_reinstated_clusters.csv)
# made 8 of the 10 Representative, incl. Demsa and Bakura IDP, which had
# been on the donor-justification list.
#
# NEW TEST (Jack's choice): a not-started cluster is dropped only if the
# stratum's MoE STILL sits at or under DROP_CEILING_MOE_PCT (9.5%) WITHOUT
# it, using the same MoE that drives the representativity verdict. Per
# stratum, candidates are taken in the existing priority order (least
# progress first, most recently drawn first); each is dropped if the
# stratum stays at or under the ceiling without it, and the scan stops at
# the first one that would push it over. So this can only ever trim genuine
# surplus - never a cluster a stratum needs. Two guards:
#   - Strata where the certainty-PSU treatment applies are SKIPPED, not
#     trimmed: their verdict MoE is the certainty-aware figure, which lives
#     only in 05_build_accessibility_impact_workbook.py, and copying that
#     logic into R would recreate the duplicated-logic drift this project
#     keeps paying for. Skipping keeps clusters, the conservative direction.
#   - Before deciding anything, it recomputes every other stratum's MoE here
#     (frame_status.R's realized_moe_unequal(), the same Kish formula as
#     05) and STOPS unless it matches the representativity record's
#     rigorous figure. A stale record (05 not rebuilt after the last WORKING
#     refresh) or any R/Python formula drift then fails loudly instead of
#     silently dropping on a basis that disagrees with the verdicts.
# The ceiling is 9.5%, not the 10% representativity threshold - Jack's call
# (2026-09-21) after seeing the numbers. The MoE here is at FULL completion
# of every assigned slot, so trimming to just under 10% would leave no
# buffer for non-response. A preview on that day's data: a 10% ceiling
# proposed 105 new drops across 65 strata (80 FACT), 9.5% proposed 24 across
# 15, 9.0% proposed 4 across 3. The half-point cushion keeps a trimmed
# stratum clear of the threshold if a few interviews are lost.
#
# Usage: Rscript compute_target_correction_drops.R              (LIVE: writes the drop list)
#        Rscript compute_target_correction_drops.R --dry-run <dir>  (writes only into <dir>)
# Jack's instruction (2026-09-21): do NOT run it live without his go. Run
# 05 first, straight after refresh_working_frame_daily.R, so the guard can
# pass.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(stringr); library(tidyr) })
source("scripts/shared/frame_status.R")  # realized_moe_unequal() - same Kish formula as 05; never re-copied here

args <- commandArgs(trailingOnly = TRUE)
DRY_RUN <- length(args) >= 1 && args[1] == "--dry-run"
if (DRY_RUN) {
  stopifnot(length(args) >= 2)
  DRY_DIR <- args[2]
  dir.create(DRY_DIR, showWarnings = FALSE, recursive = TRUE)
  cat(sprintf("DRY RUN - nothing live is written; output goes to %s\n", DRY_DIR))
}
DROP_CEILING_MOE_PCT <- 9.5   # Jack, 2026-09-21 - see header; the representativity threshold itself stays 10%
MOE_MATCH_TOLERANCE <- 0.02   # the representativity record rounds to 2 dp
REPRESENTATIVITY_CSV <- "resampling/output/strata_representativity_status.csv"

CLUSTER_STATUS_CSV <- "output/data/data_collection/NGA_MSNA_2026_cluster_status_v13.csv"
TARGET_REPR_CSV <- "resampling/output/target_sample_representativity_last_run.csv"
STRATA_CSV <- "output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v13_FULL.csv"
HOUSEHOLD_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv"
OUT_CSV <- "resampling/output/target_correction_dropped_clusters.csv"
REPORT_CSV <- "resampling/output/target_correction_drop_rule_report.csv"

cluster_status <- read_csv(CLUSTER_STATUS_CSV, show_col_types = FALSE)
target_repr <- read_csv(TARGET_REPR_CSV, show_col_types = FALSE)
strata <- read_csv(STRATA_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  mutate(m_used = as.integer(m_used)) %>%
  distinct(strata_id, m_used, adm1_name, adm2_name, pop_type, partners_covering)

# cluster_id -> strata_id, from the household frame directly (not parsed from
# the cluster_id string) - robust to any future ID-format change. Also pulls
# sampling_method, since MSNA Light clusters (Abadam/Nganzai/Guzamala,
# 2026-09-11) must NEVER be touched by this task - they have their own
# separate, disclosed-only targets and are explicitly excluded from every
# other achieved/target calculation in this codebase (compute_strata_
# achieved()'s own not_msna_light() filter) for exactly this reason. Caught
# directly in this script's own first dry run: 3 of an initial 56 flagged
# drops were MSNA Light clusters (2 Abadam, 1 Nganzai) - fixed here before
# this ever reaches a live exclusion.
cluster_to_strata <- read_csv(HOUSEHOLD_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  distinct(cluster_id, strata_id, sampling_method)

n_msna_light_clusters_excluded <- cluster_to_strata %>% filter(sampling_method == "MSNA Light") %>% pull(cluster_id) %>% n_distinct()
cat(sprintf("Excluding %d MSNA Light cluster(s) from this task entirely (separate, disclosed-only targets, never blended in).\n",
            n_msna_light_clusters_excluded))
cluster_to_strata <- cluster_to_strata %>% filter(is.na(sampling_method) | sampling_method != "MSNA Light")

cluster_status <- cluster_status %>%
  inner_join(cluster_to_strata, by = "cluster_id") %>%
  mutate(
    supp_n = as.integer(str_match(cluster_id, "_supp(\\d+)$")[, 2]),
    supp_n = coalesce(supp_n, 0L)  # a plain original cluster_id -> 0 (oldest)
  )

# Already-dropped, from a prior run - carried forward unchanged, never
# re-considered as a fresh candidate. Empty on a genuinely first run.
prior_drops <- if (file.exists(OUT_CSV)) read_csv(OUT_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  mutate(n_achieved = as.integer(n_achieved), target_households = as.integer(target_households), drop_rank = as.integer(drop_rank)) else tibble()
prior_dropped_ids <- if (nrow(prior_drops) > 0) prior_drops$cluster_id else character(0)
cat(sprintf("%d cluster(s) already dropped in a prior run - carried forward, not re-evaluated.\n", length(prior_dropped_ids)))

# ---- 2026-09-21: verdict-MoE test (see header) ----
# Per-cluster size in the MoE = the same "ceiling contribution" 05 uses:
# completed / partially-completed-then-access-lost clusters count the larger
# of accessible primaries and real interviews; everything else counts
# accessible primaries after the <4 threshold and both overlays (so an
# already-dropped cluster contributes 0, as it does in 05).
cluster_status <- cluster_status %>%
  mutate(size = ifelse(status %in% c("completed", "partially_completed_access_lost"),
                       pmax(n_accessible_primary_post_threshold, n_achieved),
                       n_accessible_primary_post_threshold))

rep <- read_csv(REPRESENTATIVITY_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
col_like <- function(pattern) { hit <- grep(pattern, names(rep), fixed = TRUE, value = TRUE); stopifnot(length(hit) == 1); hit }
rep <- rep %>% transmute(
  strata_id = .data[[col_like("Strata ID")]],
  N_hh = suppressWarnings(as.numeric(.data[[col_like("accessible N_hh")]])),
  certainty_applied = startsWith(coalesce(.data[[col_like("treatment applied")]], ""), "Yes"),
  moe_05_rigorous = suppressWarnings(as.numeric(.data[[col_like("rigorous Kish")]]))
)

moe_pct <- function(sizes, N) {
  sizes <- sizes[!is.na(sizes) & sizes > 0]
  n <- sum(sizes)
  if (length(sizes) == 0 || is.na(N) || N <= n) return(NA_real_)
  100 * realized_moe_unequal(n, N, sizes, ICC = 0.06)
}

sizes_by_stratum <- split(cluster_status$size, cluster_status$strata_id)
rep$moe_here <- vapply(seq_len(nrow(rep)), function(i) {
  s <- sizes_by_stratum[[rep$strata_id[i]]]; if (is.null(s)) NA_real_ else moe_pct(s, rep$N_hh[i])
}, numeric(1))

# Guard: this script's MoE must reproduce the representativity record's.
# The record stores N ROUNDED to a whole household (05 writes
# round(N_hh_accessible)), and in a small stratum half a household moves the
# finite-population correction by ~0.02 pp (idp_NG034002, 165 hh: 9.44 at
# N=165 vs the record's 9.46 at the unrounded ~165.4). So a stratum matches
# if the record's figure lies in the range the MoE takes over N-0.5..N+0.5,
# widened by the record's own 2-dp rounding. A stratum where one side has a
# figure and the other doesn't is a mismatch too - that case is how Abadam
# Non-IDP (Full Design MoE only computable WITH its MSNA Light clusters)
# slipped past the first version of this check.
chk <- rep %>% filter(!certainty_applied) %>%
  rowwise() %>%
  mutate(
    lo = { s <- sizes_by_stratum[[strata_id]]; if (is.null(s) || is.na(N_hh)) NA_real_ else suppressWarnings(min(moe_pct(s, N_hh - 0.5), moe_pct(s, N_hh + 0.5), na.rm = TRUE)) },
    hi = { s <- sizes_by_stratum[[strata_id]]; if (is.null(s) || is.na(N_hh)) NA_real_ else suppressWarnings(max(moe_pct(s, N_hh - 0.5), moe_pct(s, N_hh + 0.5), na.rm = TRUE)) },
    lo = ifelse(is.finite(lo), lo, NA_real_), hi = ifelse(is.finite(hi), hi, NA_real_),
    computable_here = !is.na(moe_here), computable_05 = !is.na(moe_05_rigorous),
    mismatch = (computable_here != computable_05) ||
      (computable_here && computable_05 &&
         (moe_05_rigorous < lo - MOE_MATCH_TOLERANCE / 2 - 1e-9 || moe_05_rigorous > hi + MOE_MATCH_TOLERANCE / 2 + 1e-9))
  ) %>%
  ungroup()
n_bad <- sum(chk$mismatch)
cat(sprintf("MoE check vs %s: %d of %d strata agree (N rounding allowed for; computability must also agree).\n",
            REPRESENTATIVITY_CSV, nrow(chk) - n_bad, nrow(chk)))
if (n_bad > 0) {
  print(as.data.frame(chk %>% filter(mismatch) %>% select(strata_id, N_hh, moe_05_rigorous, moe_here, lo, hi) %>% head(10)))
  stop("MoE recomputed here disagrees with the representativity record for ", n_bad, " stratum/strata. ",
       "Either the record is stale (rebuild 05_build_accessibility_impact_workbook.py straight after ",
       "refresh_working_frame_daily.R) or the two compute it differently (e.g. MSNA Light clusters counted ",
       "on one side only). Nothing dropped.")
}

# Candidate pool: ONLY "not_started_other" (see header comment for why the
# other 3 statuses are out of scope), MINUS anything already dropped in a
# prior run - those are already gone from active capacity, not up for
# re-decision.
candidates <- cluster_status %>% filter(status == "not_started_other", !(cluster_id %in% prior_dropped_ids))

decide <- lapply(split(candidates, candidates$strata_id), function(cand) {
  sid <- cand$strata_id[1]
  r <- rep[rep$strata_id == sid, ]
  if (nrow(r) == 0) return(list(basis = "skipped: stratum not in representativity record", drop = character(0), moe_after = NA_real_))
  if (r$certainty_applied) return(list(basis = "skipped: certainty treatment applies (verdict MoE computed in 05 only)", drop = character(0), moe_after = r$moe_here))
  if (is.na(r$moe_here)) return(list(basis = "skipped: MoE not computable", drop = character(0), moe_after = NA_real_))
  live <- cluster_status %>% filter(strata_id == sid)
  sizes <- setNames(live$size, live$cluster_id)
  cand <- cand %>% arrange(n_achieved, desc(supp_n))
  dropped <- character(0)
  for (cid in cand$cluster_id) {
    trial <- sizes[names(sizes) != cid]
    m <- moe_pct(trial, r$N_hh)
    if (!is.na(m) && m <= DROP_CEILING_MOE_PCT) { sizes <- trial; dropped <- c(dropped, cid) } else break
  }
  list(basis = "verdict MoE (rigorous Kish; certainty not applied)", drop = dropped, moe_after = moe_pct(sizes, r$N_hh))
})

report <- rep %>%
  left_join(strata %>% select(strata_id, m_used, adm1_name, adm2_name, pop_type, partners_covering), by = "strata_id") %>%
  mutate(
    n_candidates_current = vapply(strata_id, function(s) sum(candidates$strata_id == s), integer(1)),
    basis = vapply(strata_id, function(s) if (!is.null(decide[[s]])) decide[[s]]$basis else "no not-started candidates", character(1)),
    n_to_drop = vapply(strata_id, function(s) if (!is.null(decide[[s]])) length(decide[[s]]$drop) else 0L, integer(1)),
    moe_after_drops = vapply(strata_id, function(s) if (!is.null(decide[[s]])) decide[[s]]$moe_after else NA_real_, numeric(1))
  )

drop_ids <- unlist(lapply(decide, `[[`, "drop"), use.names = FALSE)
new_drops <- candidates %>%
  filter(cluster_id %in% drop_ids) %>%
  group_by(strata_id) %>%
  arrange(n_achieved, desc(supp_n), .by_group = TRUE) %>%
  mutate(drop_rank = row_number()) %>%
  ungroup() %>%
  mutate(reason = "verdict_moe_surplus_below_9.5pct_ceiling", computed_at = as.character(Sys.time())) %>%
  select(cluster_id, strata_id, pop_type, n_achieved, target_households, drop_rank, reason, computed_at)

all_drops <- bind_rows(prior_drops %>% mutate(across(everything(), as.character)),
                       new_drops %>% mutate(across(everything(), as.character)))
if (DRY_RUN) {
  REPORT_CSV <- file.path(DRY_DIR, "drop_rule_report_DRY_RUN.csv")
  OUT_CSV <- file.path(DRY_DIR, "dropped_clusters_DRY_RUN.csv")
}
write_csv(report, REPORT_CSV, na = "NA")
write_csv(all_drops, OUT_CSV, na = "NA")

cat(sprintf("Report: %d strata evaluated, %d strata have NEW excess this run, %d NEW cluster(s) flagged for drop (%d total across all runs, incl. %d carried forward).\n",
            nrow(report), sum(report$n_to_drop > 0), nrow(new_drops), nrow(all_drops), length(prior_dropped_ids)))
cat(sprintf("Wrote %s (this run's full per-stratum report) and %s (the cumulative drop list).\n", REPORT_CSV, OUT_CSV))
cat("Live as of the next refresh_working_frame_daily.R run - frame_status.R's compute_cluster_accessibility() reads this file by default.\n")

if (nrow(new_drops) > 0) {
  by_partner <- new_drops %>%
    left_join(strata %>% select(strata_id, partners_covering), by = "strata_id") %>%
    separate_rows(partners_covering, sep = ",\\s*") %>%
    count(partners_covering, sort = TRUE)
  cat("\nNEW this run, by partner (a multi-partner stratum counts toward each):\n")
  print(as.data.frame(by_partner))

  cat("\nTop 15 strata by n_to_drop (this run):\n")
  print(as.data.frame(report %>% filter(n_to_drop > 0) %>% arrange(desc(n_to_drop)) %>%
                         select(strata_id, m_used, N_hh, moe_here, n_candidates_current, n_to_drop, moe_after_drops) %>% head(15)))
} else {
  cat("\nNo new drops this run.\n")
}
