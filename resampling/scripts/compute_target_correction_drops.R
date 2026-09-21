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
# (NGA_MSNA_2026_cluster_status_v11.csv, all 4 values are accessibility/
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
# NGA_MSNA_2026_cluster_status_v11.csv's "not_started_other" status - the
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
# Usage: Rscript compute_target_correction_drops.R
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(stringr); library(tidyr) })

CLUSTER_STATUS_CSV <- "output/data/data_collection/NGA_MSNA_2026_cluster_status_v11.csv"
TARGET_REPR_CSV <- "resampling/output/target_sample_representativity_last_run.csv"
STRATA_CSV <- "output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v11_FULL.csv"
HOUSEHOLD_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv"
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

# Locked-in achieved credit per stratum - completed clusters' n_achieved
# counts toward what's already met, permanently, regardless of this task.
achieved_locked <- cluster_status %>%
  filter(status == "completed") %>%
  group_by(strata_id) %>%
  summarise(achieved_locked = sum(n_achieved), .groups = "drop")

# Candidate pool: ONLY "not_started_other" (see header comment for why the
# other 3 statuses are out of scope), MINUS anything already dropped in a
# prior run - those are already gone from active capacity, not up for
# re-decision.
candidates <- cluster_status %>% filter(status == "not_started_other", !(cluster_id %in% prior_dropped_ids))

report <- target_repr %>%
  left_join(strata, by = "strata_id") %>%
  left_join(achieved_locked, by = "strata_id") %>%
  mutate(achieved_locked = coalesce(achieved_locked, 0)) %>%
  rowwise() %>%
  mutate(
    n_candidates_current = sum(candidates$strata_id == strata_id, na.rm = TRUE),
    remaining_need = max(0, target_sample_representativity - achieved_locked),
    clusters_still_needed = ceiling(remaining_need / m_used),
    n_to_drop = max(0, n_candidates_current - clusters_still_needed)
  ) %>%
  ungroup()

write_csv(report, REPORT_CSV, na = "NA")

new_drops <- report %>%
  filter(n_to_drop > 0) %>%
  select(strata_id, n_to_drop) %>%
  left_join(candidates, by = "strata_id") %>%
  group_by(strata_id) %>%
  arrange(n_achieved, desc(supp_n), .by_group = TRUE) %>%
  mutate(drop_rank = row_number()) %>%
  filter(drop_rank <= n_to_drop) %>%
  ungroup() %>%
  mutate(reason = "target_correction_excess_capacity", computed_at = as.character(Sys.time())) %>%
  select(cluster_id, strata_id, pop_type, n_achieved, target_households, drop_rank, reason, computed_at)

all_drops <- bind_rows(prior_drops, new_drops)
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
                         select(strata_id, m_used, target_sample_representativity, achieved_locked,
                                n_candidates_current, clusters_still_needed, n_to_drop) %>% head(15)))
} else {
  cat("\nNo new drops this run.\n")
}
