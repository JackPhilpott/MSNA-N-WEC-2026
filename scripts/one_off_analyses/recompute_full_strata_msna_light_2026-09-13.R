# ==============================================================================
# Recomputes strata-level FULL's achieved_clusters/achieved_sample for the
# 3 MSNA Light strata (non_idp_NG008001 Abadam, non_idp_NG008010 Guzamala,
# non_idp_NG008026 Nganzai), 2026-09-13. These have been stale since the
# 2026-09-11 MSNA Light merge, which deliberately never touched strata-
# level FULL (avoiding the blending risk into WORKING's operational figure
# the safe way that night, at the cost of leaving FULL itself unrecomputed).
# Confirmed via a synthetic test while building scripts/shared/frame_
# status.R: FULL's stored achieved_sample (161/203/284) doesn't reflect the
# 564 MSNA Light rows added to FULL that night, even though FULL is
# documented as "the complete, unfiltered historical record of every row
# ever drawn... regardless of current accessibility AND regardless of
# sampling_method" - a real staleness, not a policy question. Jack's
# explicit call tonight: recompute it, heading to a DO handoff.
#
# Uses compute_strata_achieved(..., filter_ward_accessible=FALSE) - the
# exact same unfiltered FULL-mode logic merge_partner_resample_batch.R now
# calls, just run once here directly for these 3 strata rather than via a
# partner merge (there's no new batch to merge - this is a pure recompute
# of already-live data).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
source("scripts/shared/frame_status.R")
DC_DIR <- "output/data/data_collection"

TARGET_STRATA <- c("non_idp_NG008001", "non_idp_NG008010", "non_idp_NG008026")

full_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
full_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)

before <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, N_hh, m_used, ICC, target_sample, achieved_clusters, achieved_sample, realized_moe_pct)
cat("Before:\n"); print(as.data.frame(before))

base <- full_hh %>% filter(strata_id %in% TARGET_STRATA)
result <- compute_strata_achieved(base, achieved_lookup = compute_achieved_lookup(
  read_csv("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring/data/real_submissions.csv", show_col_types = FALSE, col_types = cols(.default = "c")),
  read_csv("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv", show_col_types = FALSE, col_types = cols(.default = "c"))
), filter_ward_accessible = FALSE)

agg <- result$agg
cluster_size_vecs <- split(result$cluster_sizes$n, result$cluster_sizes$strata_id)

full_sl_new <- full_sl %>%
  left_join(agg %>% rename(achieved_clusters_new = achieved_clusters, achieved_sample_new = achieved_sample), by = "strata_id") %>%
  mutate(
    achieved_clusters = if_else(strata_id %in% TARGET_STRATA & !is.na(achieved_clusters_new), achieved_clusters_new, achieved_clusters),
    achieved_sample = if_else(strata_id %in% TARGET_STRATA & !is.na(achieved_sample_new), achieved_sample_new, achieved_sample)
  )

# realized_moe_pct via the same Kish formula, only for the 3 target strata
new_moe <- mapply(function(sid, n_hh, icc, ach) {
  if (!(sid %in% TARGET_STRATA) || is.na(ach) || !(ach > 0 & ach < n_hh)) return(NA_real_)
  sizes <- cluster_size_vecs[[sid]]
  if (is.null(sizes)) return(NA_real_)
  100 * realized_moe_unequal(ach, n_hh, sizes, icc)
}, full_sl_new$strata_id, full_sl_new$N_hh, full_sl_new$ICC, full_sl_new$achieved_sample)
full_sl_new$realized_moe_pct <- ifelse(full_sl_new$strata_id %in% TARGET_STRATA, new_moe, full_sl_new$realized_moe_pct)

full_sl_new <- full_sl_new %>% select(-achieved_clusters_new, -achieved_sample_new)

after <- full_sl_new %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, N_hh, m_used, ICC, target_sample, achieved_clusters, achieved_sample, realized_moe_pct)
cat("\nAfter:\n"); print(as.data.frame(after))

stopifnot(nrow(full_sl_new) == nrow(full_sl), !anyDuplicated(full_sl_new$strata_id))
write_csv(full_sl_new, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
cat("\nWritten.\n")
