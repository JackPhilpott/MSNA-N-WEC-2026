# ==============================================================================
# CORRECTED RE-RUN of convert_ngala_nonidp_to_msna_light_2026-09-29.R - the
# first version was a real mistake, found and reverted the same night (see
# the incident note this script's own header restates for the record, and
# feedback_cross_session_mistake_pattern_tracking on why this gets written
# down plainly, not quietly fixed).
#
# THE MISTAKE: v1 tagged ALL 315 non_idp_NG008025 household rows "MSNA
# Light", including 129 rows sitting in a ward already marked Inaccessible.
# frame_status.R's own ward_gate() (compute_cluster_accessibility()) EXEMPTS
# sampling_method=="MSNA Light" rows from the ward-accessibility check
# entirely - a deliberate design feature, but one the 3 precedent Light
# strata (Abadam/Nganzai/Guzamala) only ever relied on because they were
# EACH CHECKED DIRECTLY BEFOREHAND to sit entirely in Accessible wards (see
# apply_r6_msna_light_frame_changes_2026-09-22.R's own comment: "both this
# and its Light siblings have every Light cluster sitting in a ward already
# marked Accessible"). Ngala NI was never checked the same way - it does NOT
# sit entirely in Accessible wards (129 of 315 rows, 41%, are Inaccessible).
# Tagging those rows Light would have silently exempted them from the ward
# gate, making them eligible for WORKING/KML as if collectible even though
# the ward is genuinely inaccessible - a real location-safety risk, caught
# by refresh_working_frame_daily.R's own standing plausibility gate ("WORKING
# rows in a currently-Inaccessible ward" must be exactly 0, the 2026-09-07
# incident's core invariant) before anything got written or trusted.
#
# THE FIX: only tag household rows where ward_accessible_status=="Accessible"
# (186 of 315). The 129 Inaccessible-ward rows are left as "MSNA Full
# Design" - not because they're being collected that way, but because
# leaving them untagged means they keep getting the SAME correct treatment
# every other inaccessible row gets (excluded by the normal ward gate),
# which is what should happen to them regardless of methodology. Jack's own
# decision (relabel outstanding points as Light, continue under relaxed
# rules, no fresh draw) is about the REACHABLE points - it was never about
# exempting genuinely inaccessible ones from the accessibility rule itself.
# Strata-level tag is unchanged from v1 (still "MSNA Light" on the one
# non_idp_NG008025 strata row - that tag is whole-stratum by its own nature,
# same as the 3 precedents, and isn't what caused the problem).
#
# Reverted v1's changes to the household-level FULL frame from the backup
# BEFORE this ran (output/data/data_collection/_archive/2026-09-29_ngala_
# nonidp_msna_light_conversion/) - this script starts from that same
# pre-conversion state, not from v1's (wrong) output.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v14"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

TARGET_STRATA_ID <- "non_idp_NG008025"

archive_reason <- "ngala_nonidp_msna_light_conversion_v2_corrected"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
file.copy(sl_path, file.path(archive_dir, basename(sl_path)), overwrite = TRUE)
cat(sprintf("Backed up (confirmed pre-conversion state, post-revert) to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
full_sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))

target_rows <- full_hh %>% filter(strata_id == TARGET_STRATA_ID)
n_accessible <- sum(target_rows$ward_accessible_status == "Accessible", na.rm = TRUE)
n_inaccessible <- sum(target_rows$ward_accessible_status == "Inaccessible", na.rm = TRUE)
n_other <- nrow(target_rows) - n_accessible - n_inaccessible
cat(sprintf("Before: %d row(s) for %s - %d Accessible (will be tagged Light), %d Inaccessible (left untouched, stay Full Design), %d other/NA.\n",
            nrow(target_rows), TARGET_STRATA_ID, n_accessible, n_inaccessible, n_other))

full_hh <- full_hh %>%
  mutate(sampling_method = if_else(
    strata_id == TARGET_STRATA_ID & !is.na(ward_accessible_status) & ward_accessible_status == "Accessible",
    "MSNA Light", sampling_method
  ))

full_sl <- full_sl %>%
  mutate(sampling_method = if_else(strata_id == TARGET_STRATA_ID, "MSNA Light", sampling_method))

write_csv(full_hh, hh_path)
write_csv(full_sl, sl_path)

after_rows <- full_hh %>% filter(strata_id == TARGET_STRATA_ID)
n_light_after <- sum(after_rows$sampling_method == "MSNA Light")
n_light_inaccessible_after <- sum(after_rows$sampling_method == "MSNA Light" & after_rows$ward_accessible_status == "Inaccessible", na.rm = TRUE)
n_idp_unaffected <- sum(full_hh$strata_id == "idp_NG008025" & full_hh$sampling_method == "MSNA Light")
cat(sprintf("\nAfter: %d/%d household row(s) for %s tagged MSNA Light.\n", n_light_after, nrow(after_rows), TARGET_STRATA_ID))
cat(sprintf("Light rows still sitting in an Inaccessible ward (must be 0 - this is the exact bug being fixed): %d\n", n_light_inaccessible_after))
cat(sprintf("idp_NG008025 rows incorrectly tagged MSNA Light (must be 0): %d\n", n_idp_unaffected))
if (n_light_inaccessible_after > 0) stop("A Light row is still sitting in an Inaccessible ward - the fix did not work. Do not proceed.")
if (n_idp_unaffected > 0) stop("idp_NG008025 was touched - this must never happen. Investigate before trusting this run.")
cat("\n==== DONE - re-run refresh_working_frame_daily.R next. ====\n")
