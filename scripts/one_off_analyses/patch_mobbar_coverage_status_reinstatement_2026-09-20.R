# ==============================================================================
# Fixes a stale coverage_status/exclusion_reason on non_idp_NG008023's
# (Mobbar) original 17 clusters, found by the new validity_checks suite
# (accessibility_consistency module, 2026-09-20 first run).
#
# Context: Mobbar's original 17 clusters (non_idp_NG008023_1 through _17)
# were drawn under the standard 20km NE international-buffer rule. FHI 360
# (the assigned partner) then reported the opposite of what the buffer
# assumed - their real accessibility in the LGA sits WITHIN that buffer
# (Damasak + Zanna Umarti), not outside it where the original 17 clusters
# were drawn. The stratum was reinstated to coverage_status=covered on
# 2026-09-03 (Revision 2026-09-03, "Mobbar ward-level border-buffer
# override") and 15 new supplementary clusters drawn in the newly-opened
# wards - but that reinstatement only ever flipped the STRATA-LEVEL summary
# row, never the original 17 clusters' own household-level FULL rows, which
# still carry the pre-reinstatement coverage_status=excluded/
# accessibility_loss_below_population_threshold label.
#
# This is NOT a live bug - all 202 of these rows also carry
# ward_accessible_status=Inaccessible, sourced from FHI 360's own
# point-level review (dated 2026-08-17: "For Mobbar LGA, all currently
# assigned households are inaccessible" for these specific 10 wards -
# Kareto/Layi/Futchimiram/Zari/Banowa/Fukurti/Gashigar/Ngetra/Chamba/
# Gazabure), confirmed directly against master_accessibility_status_
# ward_level.csv before this patch was written - so they're already
# correctly excluded from WORKING via that column, independent of
# coverage_status. The fix here only removes a LATENT trap: if one of
# those 10 wards is ever reported accessible again later, the stale
# accessibility_loss_below_population_threshold label would keep blocking
# it even after ward_accessible_status correctly flips.
#
# Jack confirmed this account directly and approved the fix, 2026-09-20.
#
# Only household-level FULL needs a change - strata-level FULL/WORKING
# already correctly show covered/none (verified before writing this
# script), same as the 15 new supp clusters' own rows.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v10"

TARGET_STRATA_ID <- "non_idp_NG008023"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

# --- archive_before_fix(), inlined per this project's own convention for
# one-off scripts (see stamp_frame_version.R's own archive_before_fix() -
# not sourced directly here, since that file also runs its own top-level
# stray-backup sweep as a side effect of being sourced at all) -----------
archive_reason <- "mobbar_coverage_status_reinstatement"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE)
full_sl <- read_csv(sl_path, show_col_types = FALSE)

# --- Sanity checks before touching anything ------------------------------
strata_row <- full_sl %>% filter(strata_id == TARGET_STRATA_ID)
stopifnot(nrow(strata_row) == 1, strata_row$coverage_status == "covered")
cat("Strata-level FULL already covered/none (unchanged by this patch):\n")
print(as.data.frame(strata_row %>% select(strata_id, coverage_status, exclusion_reason, target_sample, achieved_sample)))

before_stale <- full_hh %>% filter(strata_id == TARGET_STRATA_ID, coverage_status == "excluded")
cat(sprintf("\nStale rows found (strata_id=%s, coverage_status=excluded): %d\n", TARGET_STRATA_ID, nrow(before_stale)))
stopifnot(nrow(before_stale) == 202, all(before_stale$exclusion_reason == "accessibility_loss_below_population_threshold"), all(before_stale$ward_accessible_status == "Inaccessible"))

# --- Flip only the stale subset - leave the already-correct 201 rows and
# everything else in the file untouched ------------------------------------
full_hh <- full_hh %>%
  mutate(
    coverage_status  = if_else(strata_id == TARGET_STRATA_ID & coverage_status == "excluded", "covered", coverage_status),
    exclusion_reason = if_else(strata_id == TARGET_STRATA_ID & exclusion_reason == "accessibility_loss_below_population_threshold", "none", exclusion_reason)
  )

after <- full_hh %>% filter(strata_id == TARGET_STRATA_ID)
cat("\nAfter (household FULL) - sanity check all 403 rows now covered/none, ward_accessible_status untouched:\n")
print(as.data.frame(after %>% count(coverage_status, exclusion_reason, ward_accessible_status)))
stopifnot(nrow(after) == 403, all(after$coverage_status == "covered"), all(after$exclusion_reason == "none"),
          sum(after$ward_accessible_status == "Inaccessible") == 202, sum(after$ward_accessible_status == "Accessible") == 201)

write_csv(full_hh, hh_path)
cat(sprintf("\nWritten. Household FULL: %d rows (unchanged count, only coverage_status/exclusion_reason values changed for the 202 stale rows).\n", nrow(full_hh)))
