# ==============================================================================
# Found during the 2026-09-03 comprehensive post-rollout review: an
# independent recompute of achieved_clusters/achieved_sample (stated in
# NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv) against the
# ACTUAL current primary-row count for that stratum in the household-level
# WORKING CSV found 222 strata where the stated achieved_sample doesn't
# match reality - always stated > actual, and in every case checked the
# stale stated value exactly equals the corresponding FULL frame's primary
# row count for that stratum. FULL itself is perfectly self-consistent
# (0 mismatches, checked nationally) - only WORKING's strata-level summary
# is affected, for any stratum not directly touched by a merge/patch
# script's own recompute_strata()-equivalent call.
#
# This patch recomputes achieved_clusters, achieved_sample, and
# realized_moe_pct (same realized_moe() formula used everywhere else in
# this project - deff = 1+(m-1)*ICC; ndeff = achieved*(N_hh-1)/(N_hh-achieved);
# n0 = ndeff/deff; sqrt(Z^2*p*(1-p)/n0), Z=qnorm(0.95), p=0.5) directly from
# the CURRENT household-level WORKING CSV, for every stratum in the
# strata-level WORKING CSV. target_sample and every other column are left
# untouched - Jack has a separate, already-planned single deliberate
# target/achieved recalibration pass for after this round of data
# collection; this patch only fixes the mechanical staleness (reported
# achieved_sample not matching the file's own actual row count), not any
# target-side design question.
#
# IMPORTANT CONTEXT for whoever reads this next: the SAME review that found
# this staleness also found a much larger, separate issue - 9,911 primary-
# status household rows (1,157 clusters, all 18 partners, both IDP hex_v1
# and Non-IDP) are missing from WORKING entirely while their paired reserve
# rows remain present, despite FULL showing identical qualifying
# coverage_status/exclusion_reason/ward_accessible_status for both. This
# patch does NOT touch that issue - it only makes achieved_sample honestly
# reflect what's ACTUALLY in WORKING right now, which for those 1,157
# clusters' strata means a LOWER, not higher, corrected number than even
# this patch's own recompute would show if that separate issue is later
# fixed. See the 2026-09-03 comprehensive review report for full detail -
# do not treat this patch as having resolved that separate finding.
# ==============================================================================
suppressMessages({
  library(dplyr)
  library(readr)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC <- "output/data/data_collection"

realized_moe <- function(achieved_sample, N_hh, m, ICC, Z = qnorm(0.95), p = 0.5) {
  deff  <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

working_hh <- read_csv(file.path(DC, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"), show_col_types = FALSE)

actual <- working_hh %>%
  filter(status == "primary") %>%
  group_by(strata_id) %>%
  summarise(actual_clusters = n_distinct(cluster_id), actual_sample = n(), .groups = "drop")

before <- working_sl %>% select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)

working_sl_fixed <- working_sl %>%
  left_join(actual, by = "strata_id") %>%
  mutate(
    actual_clusters = coalesce(actual_clusters, 0L),
    actual_sample = coalesce(actual_sample, 0L),
    achieved_clusters = actual_clusters,
    achieved_sample = actual_sample,
    realized_moe_pct = if_else(
      achieved_sample > 0,
      100 * realized_moe(achieved_sample, N_hh, m_used, ICC),
      NA_real_
    )
  ) %>%
  select(-actual_clusters, -actual_sample)

changed <- before %>%
  inner_join(
    working_sl_fixed %>% select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct),
    by = "strata_id", suffix = c("_before", "_after")
  ) %>%
  filter(achieved_clusters_before != achieved_clusters_after | achieved_sample_before != achieved_sample_after)

cat(sprintf("Strata corrected: %d\n", nrow(changed)))
cat(sprintf("Total achieved_sample delta (after - before): %d\n",
            sum(changed$achieved_sample_after - changed$achieved_sample_before)))
cat("Sample of corrections:\n")
print(as.data.frame(changed %>%
  select(strata_id, achieved_clusters_before, achieved_clusters_after,
         achieved_sample_before, achieved_sample_after,
         realized_moe_pct_before, realized_moe_pct_after) %>% head(15)))

stopifnot(nrow(working_sl_fixed) == nrow(working_sl))

write_csv(working_sl_fixed, file.path(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"))
cat(sprintf("\nWritten: %s\n", file.path(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv")))
