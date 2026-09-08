# ==============================================================================
# Reinstates Dandume and Faskari (Katsina, both FACT) from coverage_status=
# excluded/exclusion_reason=accessibility_loss_below_population_threshold
# back to covered/none, 2026-09-08.
#
# Background: this exclusion mechanism (build_v3_frame_2026-08-31.R, POP_
# FLOOR_PCT=10) was computed ONCE against Aug 31 accessibility data and never
# recomputed since - flagged tonight as part of a broader "frozen one-time
# scripts" pattern (see 1_sampling/CLAUDE.md). Jack asked specifically about
# Dandume/Faskari after the data officer reported FACT's subcontracted
# partners (Conpad Initiatives) requesting to cover LGAs that don't appear in
# the working frame.
#
# Recomputed the real population-weighted "% of population accessible"
# (05_build_accessibility_impact_workbook.py's own load_lga_area_pop_
# fractions() formula, from the ward-level GIS layer - NOT a row-count
# approximation) using current, verified-fresh accessibility data:
#   idp_NG021008 (Dandume):     19.19% accessible
#   non_idp_NG021008 (Dandume): 22.08% accessible
#   idp_NG021013 (Faskari):    100.00% accessible
#   non_idp_NG021013 (Faskari): 56.52% accessible
# All four clear the 10% floor comfortably.
#
# One data-quality call Jack made explicitly before this: Faskari's 5
# currently-Accessible wards carried a contradictory "Banditry and
# kidnappings" note against their own Yes flag - identical text on all 5,
# read as a copied-down note rather than 5 independent reports. Jack's
# explicit decision: trust the Accessible (Y/N) column, disregard the note.
# No data was changed for this - the master ward CSV already showed
# Accessible for these 5 wards; the decision was which existing signal to
# trust, not which to write.
#
# Unlike the Mobbar precedent (patch_mobbar_strata_pre_merge_2026-09-03.R),
# no new population/n_hex/N_hh needs adding here - these are pre-existing
# household rows already in FULL with correct ward_accessible_status (this
# week's resweep), just gated off from WORKING by the stratum-level
# exclusion flag. N_hh/n_pop/target_sample are left untouched - all four
# strata are at the same population scale (tens of thousands of N_hh) where
# this project's FPC-adjusted target formula has repeatedly been shown to
# saturate regardless of exact population figure (confirmed for Mobbar at a
# comparable scale, 2026-09-03).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

TARGET_STRATA <- c("idp_NG021008", "non_idp_NG021008", "idp_NG021013", "non_idp_NG021013")

full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE)

before <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("Before:\n"); print(as.data.frame(before))
stopifnot(nrow(before) == 4, all(before$coverage_status == "excluded"))

full_sl <- full_sl %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "covered", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, "none", exclusion_reason)
  )

after <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("\nAfter (FULL):\n"); print(as.data.frame(after))

stopifnot(!any(TARGET_STRATA %in% working_sl$strata_id))
new_working_rows <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>%
  mutate(achieved_clusters = 0L, achieved_sample = 0L, realized_moe_pct = NA_real_)
working_sl <- bind_rows(working_sl, new_working_rows)
cat("\nAdded 4 placeholder rows to strata WORKING (achieved figures recomputed next by refresh_working_frame_daily.R):\n")
print(as.data.frame(new_working_rows %>% select(strata_id, coverage_status, target_sample, achieved_sample)))

stopifnot(!anyDuplicated(full_sl$strata_id), !anyDuplicated(working_sl$strata_id))
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"))
cat("\nWritten. Strata FULL:", nrow(full_sl), "rows. Strata WORKING:", nrow(working_sl), "rows.\n")
