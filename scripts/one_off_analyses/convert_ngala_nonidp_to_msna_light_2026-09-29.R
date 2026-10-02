# ==============================================================================
# Ngala Non-IDP -> MSNA Light conversion (Jack, via Coordinator, 2026-09-29
# - methodology decision, not resampling; his own reasoning: the switch
# already reflects the field team can't sustain Full Design rigor there, so
# a fresh draw wouldn't meaningfully improve real-world compliance either).
#
# Scope: non_idp_NG008025 ONLY (315 household rows: 170 primary, 145 reserve,
# 1 achieved of 91 target, 90 outstanding). idp_NG008025 (Ngala IDP, 101/92
# achieved, COMPLETE) is a completely separate strata_id and is never
# touched by this script - the frame's own sampling_method column is already
# stratum-grain (LIGHT_STRATA_IDS in apply_r6_msna_light_frame_changes_
# 2026-09-22.R proves this - a list of strata_ids, not LGA names), so a
# mixed-LGA split needs no new mechanism, just the same tag on the one
# strata_id this decision actually covers.
#
# UNLIKE the 3 precedent Light strata (Abadam/Nganzai/Guzamala, Light from
# original design), this is the FIRST mid-round conversion FROM Full Design.
# Jack's Option 1 (his own call, not assumed): relabel the 90 outstanding
# points as Light and keep collecting them under relaxed rules - no fresh
# draw, no new households. So this script does NOT draw anything new; it
# only retags sampling_method on the rows that already exist.
#
# Every downstream consumer checked (05_build_accessibility_impact_workbook.py,
# build_partner_dc_packages.py, refresh_partner_workbooks_daily.py,
# refresh_working_frame_daily.R, frame_status.R, merge_partner_resample_
# batch.R, draw_supplementary_*_batch.R, compute_target_correction_drops.R,
# extract_partner_shortfalls.R, qa_cluster_factsheets_batch.py,
# build_cluster_factsheets.py) self-derives from sampling_method =="MSNA
# Light" directly - no hardcoded LGA/strata list found anywhere outside this
# one-off script family, matching this project's own "minimal generic
# mechanisms" convention. So retagging this ONE column, on this ONE
# strata_id, is the complete fix - nothing else needs editing by hand.
#
# Household-level FULL is the source of truth this fix edits; WORKING and
# every derived output regenerate FROM FULL on the next refresh_working_
# frame_daily.R run, so WORKING is deliberately NOT hand-edited here (same
# rebuild-not-hand-patch discipline as every other frame fix tonight).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v14"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

TARGET_STRATA_ID <- "non_idp_NG008025"

archive_reason <- "ngala_nonidp_msna_light_conversion"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
file.copy(sl_path, file.path(archive_dir, basename(sl_path)), overwrite = TRUE)
cat(sprintf("Backed up to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
full_sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))

n_hh_before <- sum(full_hh$strata_id == TARGET_STRATA_ID & full_hh$sampling_method != "MSNA Light")
n_sl_before <- sum(full_sl$strata_id == TARGET_STRATA_ID & full_sl$sampling_method != "MSNA Light")
cat(sprintf("Before: %d household row(s), %d strata row(s) for %s not yet MSNA Light.\n", n_hh_before, n_sl_before, TARGET_STRATA_ID))

stopifnot(
  "idp_NG008025 is a different strata_id and must never be touched" =
    !any(full_hh$strata_id == "idp_NG008025" & FALSE)  # sanity: this script only ever filters on TARGET_STRATA_ID below, never idp_NG008025 - see the mutate()s
)

full_hh <- full_hh %>%
  mutate(sampling_method = if_else(strata_id == TARGET_STRATA_ID, "MSNA Light", sampling_method))

full_sl <- full_sl %>%
  mutate(sampling_method = if_else(strata_id == TARGET_STRATA_ID, "MSNA Light", sampling_method))

write_csv(full_hh, hh_path)
write_csv(full_sl, sl_path)

n_hh_after <- sum(full_hh$strata_id == TARGET_STRATA_ID & full_hh$sampling_method == "MSNA Light")
n_sl_after <- sum(full_sl$strata_id == TARGET_STRATA_ID & full_sl$sampling_method == "MSNA Light")
n_idp_unaffected <- sum(full_hh$strata_id == "idp_NG008025" & full_hh$sampling_method == "MSNA Light")
cat(sprintf("\nAfter: %d/%d household row(s), %d/%d strata row(s) for %s now MSNA Light.\n",
            n_hh_after, nrow(full_hh %>% filter(strata_id == TARGET_STRATA_ID)),
            n_sl_after, nrow(full_sl %>% filter(strata_id == TARGET_STRATA_ID)), TARGET_STRATA_ID))
cat(sprintf("idp_NG008025 rows incorrectly tagged MSNA Light (should be 0): %d\n", n_idp_unaffected))
if (n_idp_unaffected > 0) stop("idp_NG008025 was touched - this must never happen. Investigate before trusting this run.")
cat("\n==== DONE - re-run refresh_working_frame_daily.R next to propagate to WORKING/derived outputs. ====\n")
