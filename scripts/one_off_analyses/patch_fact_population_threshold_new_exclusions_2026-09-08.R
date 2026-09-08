# ==============================================================================
# Excludes 8 currently-covered FACT strata whose real, current population-
# weighted accessibility has fallen below the 10% floor since they were last
# checked - the "new-exclusion" direction of the accessibility_loss_below_
# population_threshold mechanism (build_v3_frame_2026-08-31.R), found and
# recomputed by resampling/scripts/recheck_population_threshold_exclusions.py
# (new standing tool, same day), Jack's explicit go-ahead 2026-09-08 to
# apply this batch. Mirrors patch_dandume_faskari_reinstatement_2026-09-08.R's
# 2-level (strata + household) pattern, in the opposite direction - and
# EXPLICITLY includes the household-level FULL patch that script's own
# committed version omits (CLAUDE.md records that gap was caught and fixed
# only as an un-scripted inline correction at the time, not captured in that
# file - not repeating that miss here).
#
# TARGET_STRATA, all FACT, recomputed via the same authoritative population-
# weighted formula as Dandume/Faskari (05_build_accessibility_impact_
# workbook.py's load_lga_area_pop_fractions(), from the ward-clipped GIS
# layer):
#   non_idp_NG008009 (Gubio):    0.98% accessible
#   non_idp_NG008010 (Guzamala): 1.13%
#   non_idp_NG008017 (Kukawa):   0.14%
#   non_idp_NG021019 (Kankara):  0.85%
#   non_idp_NG022017 (Shanga):   1.53%
#   non_idp_NG034010 (Kebbe):    5.48%
#   idp_NG008009 (Gubio):        0.00%
#   idp_NG034010 (Kebbe):        0.00%
# All 8 carry real, substantial achieved field effort (up to 208 completed
# interviews) against targets that are now essentially unreachable - this is
# exactly why Jack asked for the achieved-credit-preservation fix (option a,
# see build_partner_dc_packages.py/refresh_partner_workbooks_daily.py's
# 2026-09-08 fix notes) BEFORE applying this batch, not after: without that
# fix, excluding these strata the naive way would have silently erased that
# real credit from every consumer (WORKING, the impact workbook, FACT's own
# workbook) simultaneously.
#
# Deliberately NOT dropping achieved_sample/target_sample to 0 in strata-
# level WORKING via this script - these strata are being REMOVED from
# strata WORKING entirely (below, mirroring how an excluded stratum has no
# WORKING presence at all, same as every other accessibility_loss_below_
# population_threshold-excluded stratum) rather than left as a zeroed row.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
EXCLUSION_REASON <- "accessibility_loss_below_population_threshold"

TARGET_STRATA <- c(
  "non_idp_NG008009", "non_idp_NG008010", "non_idp_NG008017", "non_idp_NG021019",
  "non_idp_NG022017", "non_idp_NG034010", "idp_NG008009", "idp_NG034010"
)

# ---- Archive first, standard precondition ----
archive_dir <- file.path(DC_DIR, "_archive", paste0(Sys.Date(), "_pre_fact_population_threshold_new_exclusions"))
dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(DC_DIR, pattern = "^NGA_MSNA_2026_(stage2|strata_level)_sampling_frame_v7_(FULL|WORKING)\\.csv$", full.names = TRUE)) {
  file.copy(f, file.path(archive_dir, basename(f)), overwrite = FALSE)
}
cat("Archived pre-exclusion state to", archive_dir, "\n\n")

full_hh    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
working_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
n_full_hh_rows_before <- nrow(full_hh)
full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE)

before_sl <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("Before (strata FULL):\n"); print(as.data.frame(before_sl))
stopifnot(nrow(before_sl) == length(TARGET_STRATA), all(before_sl$coverage_status == "covered"))

n_hh_before <- sum(full_hh$strata_id %in% TARGET_STRATA)
n_working_before <- sum(working_hh$strata_id %in% TARGET_STRATA)
cat(sprintf("\nHousehold-level FULL rows for these strata: %d (all currently coverage_status=covered)\n", n_hh_before))
cat(sprintf("Household-level WORKING rows for these strata: %d\n", n_working_before))

# ---- Strata-level FULL: flip, then DROP from strata WORKING (matches every
# other accessibility_loss_below_population_threshold-excluded stratum -
# they have no strata-level WORKING presence at all) ----
full_sl <- full_sl %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, EXCLUSION_REASON, exclusion_reason)
  )
working_sl <- working_sl %>% filter(!(strata_id %in% TARGET_STRATA))

# ---- Household-level FULL: same flip, on every row (primary + reserve) -
# this is the part the Dandume/Faskari precedent's committed script omitted.
# WORKING itself is NOT touched here directly - refresh_working_frame_
# daily.R (run immediately after this script) is what actually drops these
# rows from WORKING, using the same covered/exclusion_reason gate it always
# uses, so there's exactly one place that logic lives. ----
full_hh <- full_hh %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, EXCLUSION_REASON, exclusion_reason)
  )

after_sl <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("\nAfter (strata FULL):\n"); print(as.data.frame(after_sl))
n_hh_after <- sum(full_hh$strata_id %in% TARGET_STRATA & full_hh$coverage_status == "excluded")
cat(sprintf("\nHousehold-level FULL rows now flipped to excluded: %d (should equal %d)\n", n_hh_after, n_hh_before))
stopifnot(n_hh_after == n_hh_before)
stopifnot(!any(TARGET_STRATA %in% working_sl$strata_id))

stopifnot(!anyDuplicated(full_sl$strata_id), !anyDuplicated(working_sl$strata_id))
stopifnot(nrow(full_hh) == n_full_hh_rows_before)  # mutate() only - no rows dropped or added

write_csv(full_hh, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), na = "NA")
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"))
cat(sprintf("\nWritten. FULL: %d rows. Strata FULL: %d rows. Strata WORKING: %d rows (was %d, dropped %d).\n",
            nrow(full_hh), nrow(full_sl), nrow(working_sl), nrow(working_sl) + length(TARGET_STRATA), length(TARGET_STRATA)))
cat("\nNOTE: household-level WORKING not yet updated - run refresh_working_frame_daily.R next to propagate.\n")
