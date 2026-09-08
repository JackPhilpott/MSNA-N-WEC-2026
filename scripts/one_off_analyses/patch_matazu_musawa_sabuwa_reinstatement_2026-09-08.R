# ==============================================================================
# Reinstates Matazu (IDP), Musawa (IDP + Non-IDP), and Sabuwa (Non-IDP only -
# Sabuwa IDP stays excluded, genuinely 0% accessible) from coverage_status=
# excluded/exclusion_reason=accessibility_loss_below_population_threshold back
# to covered/none, 2026-09-08.
#
# Same mechanism as patch_dandume_faskari_reinstatement_2026-09-08.R, but
# fixes that script's first-pass bug up front: flips BOTH the strata-level
# summary row AND every household-level FULL row's own coverage_status/
# exclusion_reason in this one pass (Dandume/Faskari's first attempt only did
# the strata-level row and had to be corrected when household-level WORKING
# didn't grow - see CLAUDE.md Update 2026-09-08g).
#
# Population-weighted % accessible (05_build_accessibility_impact_workbook.py's
# own load_lga_area_pop_fractions() formula, current data, reproduced exactly
# against the recheck_population_threshold_exclusions.py audit tool before
# trusting it):
#   idp_NG021028 (Matazu):      43.73% accessible
#   idp_NG021029 (Musawa):      22.36% accessible
#   non_idp_NG021029 (Musawa):  17.96% accessible
#   non_idp_NG021031 (Sabuwa):  25.53% accessible
# All four clear the 10% floor comfortably. idp_NG021031 (Sabuwa IDP) and the
# other 3 originally-flagged strata (Kankara IDP, Sakaba non-IDP) stay
# excluded - genuinely <1% accessible, confirmed separately, not touched here.
#
# Household-level FULL rows already exist for all 4 (un-gating existing rows,
# not a fresh draw - same shape as Dandume/Faskari). Their ward_accessible_
# status is a MIX, not uniformly accessible, so un-gating alone will leave a
# real shortfall against target_sample once refresh_working_frame_daily.R
# recomputes achieved_sample from the now-accessible subset - a genuine
# supplementary draw is expected next, not just this patch.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

TARGET_STRATA <- c("idp_NG021028", "idp_NG021029", "non_idp_NG021029", "non_idp_NG021031")

full_hh     <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
full_sl     <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
working_sl  <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE)

before_sl <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("Before (strata FULL):\n"); print(as.data.frame(before_sl))
stopifnot(nrow(before_sl) == 4, all(before_sl$coverage_status == "excluded"))

before_hh_n <- full_hh %>% filter(strata_id %in% TARGET_STRATA) %>% nrow()
cat("\nHousehold-level FULL rows for these strata (before):", before_hh_n, "\n")
stopifnot(before_hh_n > 0)

# --- Flip strata-level FULL ---
full_sl <- full_sl %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "covered", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, "none", exclusion_reason)
  )

# --- Flip household-level FULL (the part Dandume/Faskari's first pass missed) ---
full_hh <- full_hh %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "covered", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, "none", exclusion_reason)
  )

after_sl <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("\nAfter (strata FULL):\n"); print(as.data.frame(after_sl))

after_hh_check <- full_hh %>% filter(strata_id %in% TARGET_STRATA) %>%
  summarise(n = n(), n_covered = sum(coverage_status == "covered"), n_none_reason = sum(exclusion_reason == "none"))
cat("\nAfter (household FULL) - sanity check all flipped:\n"); print(as.data.frame(after_hh_check))
stopifnot(after_hh_check$n == before_hh_n, after_hh_check$n_covered == before_hh_n, after_hh_check$n_none_reason == before_hh_n)

# --- Add to strata-level WORKING (doesn't exist there while excluded) ---
stopifnot(!any(TARGET_STRATA %in% working_sl$strata_id))
new_working_rows <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>%
  mutate(achieved_clusters = 0L, achieved_sample = 0L, realized_moe_pct = NA_real_)
working_sl <- bind_rows(working_sl, new_working_rows)
cat("\nAdded 4 placeholder rows to strata WORKING (achieved figures recomputed next by refresh_working_frame_daily.R):\n")
print(as.data.frame(new_working_rows %>% select(strata_id, coverage_status, target_sample, achieved_sample)))

stopifnot(!anyDuplicated(full_sl$strata_id), !anyDuplicated(working_sl$strata_id))
write_csv(full_hh, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"))
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"))
cat("\nWritten. Household FULL:", nrow(full_hh), "rows. Strata FULL:", nrow(full_sl), "rows. Strata WORKING:", nrow(working_sl), "rows.\n")
