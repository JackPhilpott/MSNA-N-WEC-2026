# ==============================================================================
# Excludes 2 currently-covered strata (Shagari NI, Shagari IDP - NG034014,
# CRS) whose real, current population-weighted accessibility has fallen
# below the 10% floor - the "new-exclusion" direction of the accessibility_
# loss_below_population_threshold mechanism (build_v3_frame_2026-08-31.R),
# flagged by resampling/scripts/recheck_population_threshold_exclusions.py's
# 2026-09-27 00:30 run (population_threshold_recheck_2026-09-27.csv):
#   non_idp_NG034014 (Shagari NI, CRS): 0.00% accessible (floor 10.0%)
#   idp_NG034014     (Shagari IDP, CRS): 0.00% accessible (floor 10.0%)
# Re-verified directly against the live v13 strata FULL frame immediately
# before this patch (not just the cached recheck): both still coverage_
# status=covered, exclusion_reason=none, unchanged since 00:30 - D3 tonight
# touched neither stratum.
#
# This is D4 from tonight's representativity review pack (S5_decisions_for_
# jack.csv / REVIEW.md), narrowed: the pack bundled 3 candidates (Shagari
# NI, Shagari IDP, Guzamala NI - all 3 mechanically flagged NEW_EXCLUSION_
# CANDIDATE by the identical population-threshold test). Jack's direct
# decision (this session's window, 2026-09-27): apply Shagari's two only
# (option b of 3 presented); HOLD Guzamala NI (non_idp_NG008010, 7.10%
# accessible) - its 281 achieved interviews vs a target of 102 raise a
# separate, not-yet-resolved question (real MSNA Light-tainted achieved
# count vs standard-MSNA-comparable) that option (b) explicitly leaves for
# a later, better-informed call, not this mechanical population-floor
# patch. Guzamala's row is intentionally NOT in TARGET_STRATA below.
#
# Mirrors patch_population_threshold_new_exclusions_2026-09-14.R's tested
# 2-level (strata + household) pattern exactly, updated to v13 paths.
#
# Real achieved field data at stake (checked before applying, same as every
# prior use of this mechanism): non_idp_NG034014 has 175 real achieved
# interviews, idp_NG034014 has 138 - both CRS, both genuinely collected.
# Nothing here touches real_submissions.csv; those interviews are untouched
# and remain fully intact in the achieved-interview log. This patch only
# changes whether the STRATUM counts in the national covered/target/
# credited rollup going forward - exactly the same treatment already used
# for every other accessibility_loss_below_population_threshold exclusion
# (2026-09-08 batch, 2026-09-14 batch). Consistent with that precedent,
# these become indicative-only stranded achieved data, not blended into any
# stratum-level aggregate.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
EXCLUSION_REASON <- "accessibility_loss_below_population_threshold"

TARGET_STRATA <- c("non_idp_NG034014", "idp_NG034014")

# ---- Archive first, standard precondition ----
archive_dir <- file.path(DC_DIR, "_archive", paste0(Sys.Date(), "_pre_population_threshold_new_exclusions_shagari"))
dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(DC_DIR, pattern = "^NGA_MSNA_2026_(stage2|strata_level)_sampling_frame_v13_(FULL|WORKING)\\.csv$", full.names = TRUE)) {
  file.copy(f, file.path(archive_dir, basename(f)), overwrite = FALSE)
}
cat("Archived pre-exclusion state to", archive_dir, "\n\n")

full_hh    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
working_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
n_full_hh_rows_before <- nrow(full_hh)
full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v13_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v13_WORKING.csv"), show_col_types = FALSE)

before_sl <- full_sl %>% filter(strata_id %in% TARGET_STRATA) %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)
cat("Before (strata FULL):\n"); print(as.data.frame(before_sl))
stopifnot(nrow(before_sl) == length(TARGET_STRATA), all(before_sl$coverage_status == "covered"), all(before_sl$exclusion_reason %in% c("none", NA)))

n_hh_before <- sum(full_hh$strata_id %in% TARGET_STRATA)
n_working_before <- sum(working_hh$strata_id %in% TARGET_STRATA)
cat(sprintf("\nHousehold-level FULL rows for these strata: %d (all currently coverage_status=covered)\n", n_hh_before))
cat(sprintf("Household-level WORKING rows for these strata: %d\n", n_working_before))

# ---- Strata-level FULL: flip, then DROP from strata WORKING (matches every
# other accessibility_loss_below_population_threshold-excluded stratum) ----
full_sl <- full_sl %>%
  mutate(
    coverage_status  = if_else(strata_id %in% TARGET_STRATA, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id %in% TARGET_STRATA, EXCLUSION_REASON, exclusion_reason)
  )
working_sl <- working_sl %>% filter(!(strata_id %in% TARGET_STRATA))

# ---- Household-level FULL: same flip, on every row (primary + reserve).
# WORKING itself is NOT touched here directly - refresh_working_frame_
# daily.R (run immediately after this script) drops these rows from WORKING
# using the same covered/exclusion_reason gate it always uses. ----
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

write_csv(full_hh, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv"), na = "NA")
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v13_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v13_WORKING.csv"))
cat(sprintf("\nWritten. FULL: %d rows. Strata FULL: %d rows. Strata WORKING: %d rows (was %d, dropped %d).\n",
            nrow(full_hh), nrow(full_sl), nrow(working_sl), nrow(working_sl) + length(TARGET_STRATA), length(TARGET_STRATA)))
cat("\nNOTE: household-level WORKING not yet updated - run refresh_working_frame_daily.R next to propagate, then the rest of the standard refresh chain.\n")
