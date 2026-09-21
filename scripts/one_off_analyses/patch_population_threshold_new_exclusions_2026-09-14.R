# ==============================================================================
# Excludes 7 currently-covered strata whose real, current population-weighted
# accessibility has fallen below the 10% floor since they were last checked -
# the "new-exclusion" direction of the accessibility_loss_below_population_
# threshold mechanism (build_v3_frame_2026-08-31.R), found by resampling/
# scripts/recheck_population_threshold_exclusions.py after tonight's IRC/NRC/
# DRC/LHI accessibility batch + supplementary draw. Jack's explicit go-ahead
# 2026-09-14 to apply this batch. Mirrors patch_fact_population_threshold_
# new_exclusions_2026-09-08.R's 2-level (strata + household) pattern exactly,
# including the household-level FULL patch that script's own header flags as
# easy to miss.
#
# TARGET_STRATA, all from tonight's IRC/NRC/DRC/LHI accessibility loss,
# recomputed via the same authoritative population-weighted formula (05_
# build_accessibility_impact_workbook.py's load_lga_area_pop_fractions()):
#   non_idp_NG036007 (Gujba, NRC):                    4.19% accessible
#   idp_NG036007 (Gujba, NRC):                        0.00%
#   idp_NG037013 (Tsafe, IRC):                        0.00%
#   non_idp_NG034009 (Isa, DRC/IRC/LHI):               7.24%
#   non_idp_NG034013 (Sabon Birni, IRC/LHI):           6.48%
#   idp_NG034009 (Isa, DRC/IRC/LHI):                   0.00%
#   idp_NG034013 (Sabon Birni, IRC/LHI):               0.00%
#
# Real achieved field data at stake, checked before applying (Jack's explicit
# ask): only idp_NG037013 (Tsafe) has any - 29 real completed interviews,
# FULL-frame-wide, regardless of current accessibility. The other 6 have
# ZERO real collected interviews ever, at any point. Nothing here touches
# real_submissions.csv - those 29 interviews are untouched by this patch and
# remain fully intact; Jack's call is to present them as indicative-only data
# in the final write-up, not blended into any stratum-level aggregate (same
# treatment already used for other exhausted/excluded strata's stranded
# achieved data elsewhere in this project).
#
# non_idp_NG034009/non_idp_NG034013 note: these two strata just received 14
# and 28 combined new supplementary clusters (185 + 297 household rows) from
# tonight's batch draw+merge, most of which already sit excluded from WORKING
# (unmatched ward geography / inaccessible) - this exclusion formally retires
# that draw effort rather than leaving it as a live but functionally-dead
# "Closeable with a modest top-up" shortfall entry. No real interviews were
# ever collected against any of it (confirmed above), so nothing real is lost.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
EXCLUSION_REASON <- "accessibility_loss_below_population_threshold"

TARGET_STRATA <- c(
  "non_idp_NG036007", "idp_NG036007", "idp_NG037013",
  "non_idp_NG034009", "non_idp_NG034013", "idp_NG034009", "idp_NG034013"
)

# ---- Archive first, standard precondition ----
archive_dir <- file.path(DC_DIR, "_archive", paste0(Sys.Date(), "_pre_population_threshold_new_exclusions"))
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

write_csv(full_hh, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), na = "NA")
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"))
cat(sprintf("\nWritten. FULL: %d rows. Strata FULL: %d rows. Strata WORKING: %d rows (was %d, dropped %d).\n",
            nrow(full_hh), nrow(full_sl), nrow(working_sl), nrow(working_sl) + length(TARGET_STRATA), length(TARGET_STRATA)))
cat("\nNOTE: household-level WORKING not yet updated - run refresh_working_frame_daily.R next to propagate.\n")
