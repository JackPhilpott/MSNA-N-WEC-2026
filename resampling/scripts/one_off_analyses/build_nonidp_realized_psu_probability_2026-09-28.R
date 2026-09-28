# ==============================================================================
# Non-IDP realized psu_probability build - full weighting build, piece 2
# (Jack, approved as option A, relayed by Coordinator 2026-09-28 morning; see
# project memory project_full_weighting_build_2026-09-28). Read this file's
# header before touching the output; it documents two real findings made
# while building it, not just the mechanism.
#
# WHAT THIS BUILDS. A NEW, standalone, read-only output: cluster_id ->
# psu_probability / ssu_probability / base_weight, for every Non-IDP,
# non-MSNA-Light cluster ever in the frame (original design draw AND every
# supplementary field draw since - D0/D0-flag/D0b/D3/quick-4/final draws).
# Per the 2026-07-24 export-schema decision (01_sampling_pipeline_main.R,
# "Export schema" comment block), these three columns are deliberately NOT
# written back into FULL/WORKING - this script does not touch either file.
#
# THE FORMULA - reused exactly, not re-derived. Same one already live in
# 01_sampling_pipeline_main.R's own supplementary-shortfall patch (~line
# 1461-1516, "Recompute psu_probability for any stratum that received
# supplementary clusters"):
#     psu_probability = certainty_stratum ? 1 : pmin(1, (clusters + n_supplementary) * MOS / total_MOS)
#     ssu_probability  = pmin(1, target_households / households_in_cluster)      [design formula, 03_stage2_household_selection.R:517-522]
#     base_weight      = 1 / (psu_probability * ssu_probability)
# where MOS = pop_hh (a hex's WorldPop-derived household estimate) and
# total_MOS = sum(MOS) over EVERY accessible hex in the stratum (the whole
# candidate universe at design time, not just selected hexes) - both sourced
# from the cached hex_grid_non_idp.rds (see the near-miss note below on
# verifying that cache before trusting it). "clusters" is the ORIGINAL Stage-1
# design draw count for the stratum (fixed since 2026-07-15); this script's
# only real extension over the existing patch is generalizing
# "n_supplementary" from one shortfall round to EVERY supplementary cluster
# ever merged into the live frame, using the frame's own supplementary_
# cluster flag rather than a specific round's staging file.
#
# THEN: ssu_probability/base_weight for TOPPED-UP clusters (real achieved >
# target_households) are recomputed via scripts/shared/realized_weights.R's
# compute_realized_weight_for_cluster() - already built, tested and
# documented 2026-09-27 night, reused here verbatim, not reimplemented. For
# every cluster where that function reports NOT topped up, this script
# falls back to the design ssu_probability formula above (that function
# itself only returns a value for topped-up clusters, by design - see its
# own header).
#
# SCOPE. pop_type == "non_idp" AND !is.na(supplementary_cluster). The frame's
# own supplementary_cluster column is NA for exactly (and only) MSNA Light
# clusters (verified: 564 NA rows among non_idp = 564 sampling_method ==
# "MSNA Light" rows, an exact match) - using that as the scope filter is a
# self-deriving rule, not a hardcoded method-name string, and it also
# sidesteps a separate, unrelated data quirk found in the frame (389 rows in
# Mubi North / NG034009 carry sampling_method "Accessible"/"Inaccessible"
# instead of "MSNA Full Design" - a mislabeled column value, not a real
# methodology difference; those clusters ARE ordinary design clusters
# [supplementary_cluster == FALSE] and are correctly INCLUDED here via the
# supplementary_cluster filter. Not investigated further - out of this
# task's scope, flagged in the summary output below for whoever next
# touches that LGA's sampling_method column). MSNA Light uses a completely
# different, non-PPS design (no real georeferencing - see project memory
# project_achieved_definition_redesign_2026-09-10) and is correctly left
# out of a PPS psu_probability formula entirely, not patched into it.
#
# ---------------------------------------------------------------------------
# NEAR-MISS, CORRECTED BEFORE USE (recorded honestly, not scrubbed). The
# first two direct reads of input_data/population/sampling_frame/
# hex_grid_non_idp.rds this session (readRDS, same file, same 2026-08-30
# 20:24:57 mtime both times) returned only 14 of the 323 Non-IDP adm2_pcodes
# - which read as a real bug (a silent partial-rebuild overwriting the
# national cache) and was about to be reported as one. A THIRD read, moments
# later, returned the correct, complete 323/323 on the identical file with
# the identical mtime - the only plausible explanation is OneDrive
# Files-On-Demand serving a not-yet-fully-hydrated placeholder for the first
# two reads of this large (1.9MB) file on this synced folder, not an actual
# data problem. Re-verified directly (a fresh readRDS, immediately before
# writing this note) before trusting either result, per project memory
# feedback_verify_dont_defend / project_ward_attribution_national_
# verification_2026-09-28's own near-miss. This script keeps the archived
# (_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_non_idp.rds,
# the pre-buffer-fix Jul original) as a defensive fallback regardless - it
# costs nothing, and the build run below confirms 0 of 323 adm2_pcodes
# actually needed it, i.e. the live cache is genuinely complete. hex_source
# is still stamped on every row so this is verifiable from the output
# itself, not just asserted here.
# ---------------------------------------------------------------------------
suppressMessages({ library(dplyr); library(sf); library(readr); library(tidyr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
source("scripts/shared/realized_weights.R")

OUT <- "resampling/output/full_weighting_build_2026-09-28"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

FRAME_PATH <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"
SUBS_PATH  <- "../2_monitoring/data/real_submissions.csv"
DEL_PATH   <- "../2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv"

cat("Loading v14 FULL frame...\n")
full <- read_csv(FRAME_PATH, show_col_types = FALSE)

cluster_level <- full %>%
  filter(pop_type == "non_idp", !is.na(supplementary_cluster)) %>%
  distinct(
    cluster_id, strata_id, pop_type, adm2_pcode, uuid_hex, certainty_stratum,
    supplementary_cluster, households_in_cluster, target_households, sampling_method
  )

# QA: one cluster-level row per cluster_id, no conflicting values.
dupe_check <- cluster_level %>% count(cluster_id) %>% filter(n > 1)
if (nrow(dupe_check) > 0) {
  stop(sprintf(
    "%d cluster_id(s) have >1 distinct combination of cluster-level columns - cannot proceed safely. First few: %s",
    nrow(dupe_check), paste(head(dupe_check$cluster_id, 5), collapse = ", ")
  ))
}
cat("  ", nrow(cluster_level), "Non-IDP, non-MSNA-Light clusters in scope.\n")

# ---- clusters (original design draw count) + n_supplementary, per stratum ----
strata_counts <- cluster_level %>%
  group_by(strata_id, adm2_pcode) %>%
  summarise(
    clusters_design = n_distinct(cluster_id[!supplementary_cluster]),
    n_supplementary  = n_distinct(cluster_id[supplementary_cluster]),
    .groups = "drop"
  )

# ---- MOS / total_MOS: live hex cache, archived (pre-buffer-fix) fallback ----
cat("Loading hex population grids (live + archived pre-buffer-fix fallback)...\n")
hex_live <- readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds") %>%
  sf::st_drop_geometry() %>% select(uuid_hex, adm2_pcode, pop_hh)
hex_archived <- readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_non_idp.rds") %>%
  sf::st_drop_geometry() %>% select(uuid_hex, adm2_pcode, pop_hh)

hex_merged <- bind_rows(
  hex_live %>% mutate(hex_source = "live_post_buffer_fix_2026-08-30"),
  hex_archived %>% filter(!uuid_hex %in% hex_live$uuid_hex) %>%
    mutate(hex_source = "archived_pre_buffer_fix_2026-07")
)
cat("  Merged hex grid:", nrow(hex_merged), "hexes,", n_distinct(hex_merged$adm2_pcode),
    "adm2_pcodes (", n_distinct(hex_live$adm2_pcode), "on live post-fix values ).\n")

total_mos_by_stratum <- hex_merged %>%
  group_by(adm2_pcode) %>%
  summarise(total_MOS = sum(pop_hh, na.rm = TRUE), n_hex_in_stratum = n(), .groups = "drop")

cluster_mos <- cluster_level %>%
  left_join(hex_merged %>% select(uuid_hex, MOS = pop_hh, hex_source), by = "uuid_hex")

unmatched_hex <- cluster_mos %>% filter(is.na(MOS))
if (nrow(unmatched_hex) > 0) {
  cat("  WARNING:", nrow(unmatched_hex), "cluster(s) have a uuid_hex not found in either hex grid - MOS/psu_probability will be NA for these, flagged in output, not silently dropped.\n")
}

# ---- Real achieved interviews per cluster (canonical is_achieved() formula) ----
cat("Loading real_submissions.csv + CONFIRMED_DELETIONS_OVERLAY.csv...\n")
subs <- read_csv(SUBS_PATH, show_col_types = FALSE)
dels <- read_csv(DEL_PATH, show_col_types = FALSE)
achieved_by_cluster <- compute_achieved_by_cluster(subs, dels)

# ---- Assemble + compute ----
cluster_final <- cluster_mos %>%
  left_join(strata_counts %>% select(strata_id, clusters_design, n_supplementary), by = "strata_id") %>%
  left_join(total_mos_by_stratum, by = "adm2_pcode") %>%
  left_join(achieved_by_cluster, by = "cluster_id") %>%
  mutate(
    n_achieved = coalesce(n_achieved, 0L),
    psu_probability = case_when(
      certainty_stratum ~ 1,
      is.na(MOS) | is.na(total_MOS) ~ NA_real_,
      TRUE ~ pmin(1, (clusters_design + n_supplementary) * MOS / total_MOS)
    ),
    ssu_probability_design = pmin(1, target_households / households_in_cluster)
  )

realized <- compute_realized_weight_for_cluster(
  psu_probability = cluster_final$psu_probability,
  target_households = cluster_final$target_households,
  households_in_cluster = cluster_final$households_in_cluster,
  achieved_interviews = cluster_final$n_achieved
)

cluster_final <- cluster_final %>%
  mutate(
    topped_up = realized$topped_up,
    ssu_probability = if_else(topped_up, realized$ssu_probability, ssu_probability_design),
    base_weight = 1 / (psu_probability * ssu_probability),
    cap_bound = realized$capped
  ) %>%
  select(
    cluster_id, strata_id, adm2_pcode, certainty_stratum, supplementary_cluster,
    clusters_design, n_supplementary, MOS, total_MOS, hex_source,
    psu_probability, target_households, households_in_cluster, n_achieved,
    topped_up, ssu_probability, base_weight, cap_bound, sampling_method
  ) %>%
  arrange(strata_id, cluster_id)

write_csv(cluster_final, file.path(OUT, "nonidp_realized_psu_probability_2026-09-28.csv"))

# ---- Summary ----
n_total <- nrow(cluster_final)
n_na_psu <- sum(is.na(cluster_final$psu_probability))
n_supp_total <- sum(cluster_final$supplementary_cluster)
n_topped <- sum(cluster_final$topped_up)
n_capped <- sum(cluster_final$cap_bound, na.rm = TRUE)
n_prefix_lga <- cluster_final %>% filter(hex_source == "archived_pre_buffer_fix_2026-07") %>%
  distinct(adm2_pcode) %>% nrow()

cat("\n==== SUMMARY ====\n")
cat(sprintf("Clusters in scope (Non-IDP, non-Light): %d\n", n_total))
cat(sprintf("  Supplementary clusters (any D0/D0-flag/D0b/D3/quick-4/final draw): %d\n", n_supp_total))
cat(sprintf("  Clusters with NA psu_probability (uuid_hex not in either hex grid): %d\n", n_na_psu))
cat(sprintf("  Topped-up clusters (real achieved > target_households, realized_weights.R): %d\n", n_topped))
cat(sprintf("  Of those, pmin(1,...) cap bound (achieved > households_in_cluster): %d\n", n_capped))
cat(sprintf("  adm2_pcodes still running on pre-buffer-fix (Jul) hex values: %d of %d\n",
            n_prefix_lga, n_distinct(cluster_final$adm2_pcode)))
cat("\nWrote:", file.path(OUT, "nonidp_realized_psu_probability_2026-09-28.csv"), "\n")
cat("==== DONE ====\n")
