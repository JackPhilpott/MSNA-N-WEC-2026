# ==============================================================================
# Save the Children asked (2026-09-23, via Jack) to drop idp_NG021024
# (IDP-Mai'adua, Katsina) as a stratum - their claim is the IDP population is
# no longer present at this site. Verified before acting: 0 rows in
# 2_monitoring/data/real_submissions.csv ever matched_strata_id ==
# "idp_NG021024" (vs. 80 real matches under non_idp_NG021024 in the same LGA,
# so Save IS actively collecting in Mai'adua generally - this isn't a case of
# the team simply not having started work there yet). Jack confirmed directly
# (AskUserQuestion, 2026-09-23): drop it now, coverage_status -> "excluded",
# and the exclusion_reason must trace the REAL reason (population no longer
# present, partner-reported) rather than reusing the unrelated accessibility/
# population-threshold mechanism's reason string.
#
# 6 clusters affected, all currently coverage_status=="covered": idp_NG021024_1
# (Mai'Adua A, target 54), idp_NG021024_10 (Ubandawaki B, target 6), and 4
# supplementary clusters (supp1 Mai'Adua C, supp2 Koza, supp3 Mai'Adua A,
# supp4 Natsalle, target 6 each) = 84 target HH raw / 51 in the impact
# workbook's "true requirement incl. 5% margin" figure. Achieved_clusters/
# achieved_sample are left untouched (historical record), matching how every
# other already-excluded stratum in this frame already behaves (checked
# directly: accessibility_loss_below_population_threshold rows keep their
# pre-exclusion achieved_* figures too) - only coverage_status/exclusion_reason
# flip, same minimal pattern as retire_nganzai_dead_points_2026-09-22.R /
# fix_gwandu_idp_and_nganzai_achieved_2026-09-23.R.
#
# New exclusion_reason: "idp_population_no_longer_present_partner_reported" -
# deliberately its OWN string, not a reuse of "accessibility_loss_below_
# population_threshold" (that mechanism means something different: an
# accessibility-driven population recompute crossing the 10% floor, owned by
# recheck_population_threshold_exclusions.py, which should keep rechecking
# ONLY its own cases). To still get the same "excluded from every partner-
# level total" README-headline treatment Jack wants for traceability, the two
# partner-package generators' constant is widened from a single string to a
# named set (see the companion edit in build_partner_dc_packages.py /
# refresh_partner_workbooks_daily.py, same commit).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v13"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

STRATA_ID <- "idp_NG021024"
EXCLUSION_REASON <- "idp_population_no_longer_present_partner_reported"

archive_reason <- "idp_maiadua_exclusion"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
file.copy(sl_path, file.path(archive_dir, basename(sl_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
full_sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- Verify: 0 real submissions ever matched to this stratum ----------------
rs <- read_csv("../2_monitoring/data/real_submissions.csv", show_col_types = FALSE, col_types = cols(.default = "c"))
n_collected <- sum(rs$matched_strata_id == STRATA_ID, na.rm = TRUE)
cat(sprintf("Real submissions matched to %s: %d\n", STRATA_ID, n_collected))
stopifnot(n_collected == 0)

hh_before <- full_hh %>% filter(strata_id == STRATA_ID)
sl_before <- full_sl %>% filter(strata_id == STRATA_ID)
stopifnot(
  nrow(sl_before) == 1,
  sl_before$coverage_status == "covered",
  sl_before$exclusion_reason == "none",
  nrow(hh_before) > 0,
  all(hh_before$coverage_status == "covered"),
  all(hh_before$exclusion_reason == "none")
)
cat(sprintf("\n%s before: %d household rows across %d cluster(s), strata-level target_sample=%s, achieved_sample=%s\n",
            STRATA_ID, nrow(hh_before), n_distinct(hh_before$cluster_id), sl_before$target_sample, sl_before$achieved_sample))

n_hh_before <- nrow(full_hh)
n_sl_before <- nrow(full_sl)

# ---- Exclude: household FULL + strata-level FULL, coverage_status/exclusion_
# reason flip only - FULL never drops rows, achieved_* left untouched -------
full_hh <- full_hh %>%
  mutate(
    coverage_status = if_else(strata_id == STRATA_ID, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id == STRATA_ID, EXCLUSION_REASON, exclusion_reason)
  )
full_sl <- full_sl %>%
  mutate(
    coverage_status = if_else(strata_id == STRATA_ID, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id == STRATA_ID, EXCLUSION_REASON, exclusion_reason)
  )

# ---- Verify + write ----------------------------------------------------------
stopifnot(n_hh_before == nrow(full_hh), n_sl_before == nrow(full_sl))

hh_after <- full_hh %>% filter(strata_id == STRATA_ID)
sl_after <- full_sl %>% filter(strata_id == STRATA_ID)
stopifnot(
  all(hh_after$coverage_status == "excluded"), all(hh_after$exclusion_reason == EXCLUSION_REASON),
  sl_after$coverage_status == "excluded", sl_after$exclusion_reason == EXCLUSION_REASON,
  sl_after$achieved_sample == sl_before$achieved_sample, sl_after$achieved_clusters == sl_before$achieved_clusters
)

write_csv(full_hh, hh_path)
write_csv(full_sl, sl_path)
cat(sprintf("\nWritten. %s: coverage_status -> excluded, exclusion_reason -> '%s'. %d household rows, 1 strata-level row. Row counts unchanged (FULL never drops rows).\n",
            STRATA_ID, EXCLUSION_REASON, nrow(hh_after)))
