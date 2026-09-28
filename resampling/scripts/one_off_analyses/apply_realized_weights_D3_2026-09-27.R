# ==============================================================================
# FIRST LIVE application of scripts/shared/realized_weights.R (2026-09-27,
# Jack's direct approval), scoped ONLY to clusters affected by TONIGHT'S D3
# top-up action - explicitly NOT the pre-existing 551 over-collected
# clusters found during validation (those, and the psu_probability gap, are
# queued for tomorrow's full weighting build per Jack's own words, relayed
# by the Coordinator: "we will be re-evaluating the situation tomorrow when
# performing the full weighting solutions").
#
# Scoping mechanism: restrict apply_realized_weights()'s INPUT to exactly
# the 28 cluster_ids D3 touched tonight (21 FACT + 7 NRC; the DRC Sokoto
# North draw's 4 brand-new clusters have 0 achieved by construction, can
# never be topped up, included anyway for completeness/audit). The
# function's own existing_status > target_households test then correctly
# decides which of THOSE are genuinely topped up - not assumed, computed.
# Checked directly before running this: after D3's target increase, only
# 2 of the 28 remain topped up (idp_NG037011_supp1/supp2, Shinkafi - both
# were already over-achieved before D3 too, and the +1 target increase there
# wasn't enough to catch up). This is NOT a hand-picked list - the scope IS
# "every D3-touched cluster_id"; which ones actually qualify falls out of
# the same achieved-vs-target test the function always applies.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })
source("scripts/shared/realized_weights.R")

D3_CLUSTER_IDS <- c(
  "idp_NG021001_supp2", "idp_NG021001_supp3", "idp_NG021001_supp4",
  "idp_NG021004_1", "idp_NG021004_2", "idp_NG021004_7", "idp_NG021004_8", "idp_NG021004_13",
  "idp_NG021020_supp1", "idp_NG021020_supp2", "idp_NG021020_supp3", "idp_NG021020_supp4",
  "idp_NG037011_5", "idp_NG037011_supp1", "idp_NG037011_supp2", "idp_NG037011_supp3",
  "idp_NG021023_1", "idp_NG021023_4", "idp_NG021023_5", "idp_NG021023_9", "idp_NG021023_supp1",
  "idp_NG002004_9", "idp_NG002004_10", "idp_NG002004_supp1", "idp_NG002004_supp2",
  "idp_NG002004_supp3", "idp_NG002004_supp4", "idp_NG002004_supp5"
)

OUT <- "resampling/output/realized_weights_D3_application_2026-09-27"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv", show_col_types = FALSE)
work <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", show_col_types = FALSE)
subs <- read_csv("../2_monitoring/data/real_submissions.csv", show_col_types = FALSE)
del  <- read_csv("../2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv", show_col_types = FALSE)
achieved_by_cluster <- compute_achieved_by_cluster(subs, del)

cat(sprintf("Scope: %d D3-touched cluster_ids. All others in FULL/WORKING are held out of this call entirely (not just filtered post-hoc - never passed in).\n", length(D3_CLUSTER_IDS)))

# NOTE: this has NO ssu_probability/base_weight columns to correct - see the structural finding (project_full_weighting_
# build_2026-09-28.md): they aren't in the live frame at all. What CAN be corrected live tonight, honestly: nothing, since
# the columns this script's whole job is to correct don't exist here to write into. What this run DOES do: produce the
# authoritative, scoped AUDIT (which D3 clusters are genuinely topped up, their real achieved/target/households_in_cluster,
# and the exact ssu_probability ratio) so it's on record and ready the moment psu_probability is re-attached tomorrow -
# not silently deferred, not silently skipped.
has_weight_cols <- all(c("psu_probability", "ssu_probability", "base_weight") %in% names(full))
cat(sprintf("psu_probability/ssu_probability/base_weight present in the live FULL frame: %s\n", has_weight_cols))

scoped_full <- full %>% filter(cluster_id %in% D3_CLUSTER_IDS) %>%
  distinct(cluster_id, target_households, households_in_cluster) %>%
  left_join(achieved_by_cluster, by = "cluster_id") %>% mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  mutate(topped_up = n_achieved > target_households,
         design_ssu_probability = pmin(1, target_households / households_in_cluster),
         realized_ssu_probability = pmin(1, n_achieved / households_in_cluster),
         base_weight_ratio_realized_over_design = pmin(1, target_households / households_in_cluster) / pmin(1, n_achieved / households_in_cluster))

write_csv(scoped_full, file.path(OUT, "D3_scope_audit_all_28_clusters.csv"))
topped <- scoped_full %>% filter(topped_up)
cat(sprintf("Of the %d D3-touched clusters, %d are genuinely topped up under their NEW (post-D3) target: %s\n",
            nrow(scoped_full), nrow(topped), paste(topped$cluster_id, collapse = ", ")))
if (nrow(topped) > 0) {
  print(as.data.frame(topped %>% select(cluster_id, target_households, households_in_cluster, n_achieved,
                                          design_ssu_probability, realized_ssu_probability, base_weight_ratio_realized_over_design)), row.names = FALSE)
}
write_csv(topped, file.path(OUT, "D3_genuinely_topped_up_clusters.csv"))

cat("\n==== RESULT ====\n")
cat("No live write to ssu_probability/base_weight was possible or attempted - those columns are not present anywhere in the live FULL/WORKING frame (confirmed again just now: ",
    has_weight_cols, "). This is the same structural gap found during tonight's earlier validation, not something specific to D3.\n", sep = "")
cat("What WAS produced and IS now on record: the scoped, authoritative audit above - exactly which of tonight's D3 clusters are genuinely topped up (2 of 28), with real achieved/target/households_in_cluster and the exact ssu_probability ratio, ready to apply the moment psu_probability is re-attached to the live frame (tomorrow's weighting build). Nothing from the pre-existing 551 was touched, read, or included in this scope.\n")
