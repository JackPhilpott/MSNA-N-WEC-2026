# ==============================================================================
# Two small, unrelated fixes surfaced by the Coordinator's post-R6 alignment
# sweep (2026-09-22 night / 2026-09-23), both confirmed directly with Jack
# (Gwandu: asked directly via AskUserQuestion, "revert to excluded"; Nganzai:
# relayed as "fix this" - purely mechanical, not a methodology call).
#
# 1. Gwandu IDP (idp_NG022010, Kebbi, Solidarites): coverage_status=="covered"
#    but exclusion_reason=="certainty_stratum_below_moe_threshold" - a
#    contradictory row confirmed to PREDATE R6 entirely (present, identical,
#    in the very first archive snapshot taken today before any R6 edit).
#    N_hh=21, target_sample=0, achieved_clusters=0, zero household rows in
#    FULL or WORKING, zero IDP-matched submissions in Gwandu (the 129
#    completed interviews there are all non_idp_NG022010, untouched by this).
#    It was also the ONLY stratum nationally carrying this exclusion_reason
#    while covered=="covered" - an exclusion category of exactly one, per
#    the Coordinator's own cross-check. Fix: coverage_status -> "excluded"
#    (exclusion_reason already correct, left as-is). Strata-level FULL only -
#    no household rows exist to touch.
#
# 2. Nganzai (non_idp_NG008026) strata-level FULL achieved_sample: stale at
#    391 since retire_nganzai_dead_points_2026-09-22.R removed 83 primary
#    rows from household FULL but never recomputed this stored figure -
#    391 - 83 = 308, matching the real primary-row count directly (my own
#    oversight, not caught until the Coordinator's suite ran the "achieved_
#    sample equals real primary-row count" check). Fixed generically for
#    EVERY stratum via compute_strata_achieved(..., filter_ward_accessible =
#    FALSE) - the exact same shared function 05/refresh_working_frame_daily.R
#    use for this FULL-mode figure (see scripts/shared/frame_status.R) -
#    not just a one-stratum patch, so any other latent drift from a manual
#    row edit gets caught here too, not just Nganzai's.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
source("scripts/shared/frame_status.R")

DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v12"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

archive_reason <- "gwandu_idp_and_nganzai_achieved_fix"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(sl_path, file.path(archive_dir, basename(sl_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
full_sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- Sanity checks before touching anything --------------------------------
gwandu <- full_sl %>% filter(strata_id == "idp_NG022010")
stopifnot(
  nrow(gwandu) == 1,
  gwandu$coverage_status == "covered",
  gwandu$exclusion_reason == "certainty_stratum_below_moe_threshold",
  gwandu$target_sample == "0",
  sum(full_hh$strata_id == "idp_NG022010") == 0
)
cat("Gwandu IDP (idp_NG022010) before:\n")
print(as.data.frame(gwandu %>% select(strata_id, coverage_status, exclusion_reason, target_sample, N_hh, achieved_clusters)))

nganzai_before <- full_sl %>% filter(strata_id == "non_idp_NG008026") %>% pull(achieved_sample) %>% as.numeric()
nganzai_real_primaries <- sum(full_hh$strata_id == "non_idp_NG008026" & full_hh$status == "primary")
cat(sprintf("\nNganzai (non_idp_NG008026) strata-level FULL achieved_sample before: %s | real primary rows in household FULL: %d\n",
            nganzai_before, nganzai_real_primaries))
stopifnot(nganzai_before == 391, nganzai_real_primaries == 308)

# ---- 1. Gwandu IDP: revert coverage_status to excluded ----------------------
full_sl <- full_sl %>%
  mutate(coverage_status = if_else(strata_id == "idp_NG022010", "excluded", coverage_status))

# ---- 2. Recompute strata-level FULL achieved_clusters/achieved_sample for
# EVERY stratum from the real current household FULL row counts (filter_
# ward_accessible = FALSE mode = "every primary row ever drawn, unfiltered",
# exactly matching what strata-level FULL's own achieved_* columns mean). ----
achieved_result <- compute_strata_achieved(full_hh, achieved_lookup = NULL, filter_ward_accessible = FALSE)
agg <- achieved_result$agg %>%
  rename(achieved_clusters_new = achieved_clusters, achieved_sample_new = achieved_sample)

full_sl_before_recompute <- full_sl %>%
  mutate(achieved_sample_old = as.numeric(achieved_sample)) %>%
  select(strata_id, achieved_sample_old)

full_sl <- full_sl %>%
  left_join(agg, by = "strata_id") %>%
  mutate(
    achieved_clusters_new = coalesce(achieved_clusters_new, 0L),
    achieved_sample_new = coalesce(achieved_sample_new, 0L),
    achieved_clusters = as.character(achieved_clusters_new),
    achieved_sample = as.character(achieved_sample_new)
  ) %>%
  select(-achieved_clusters_new, -achieved_sample_new)

changed <- full_sl_before_recompute %>%
  inner_join(full_sl %>% mutate(achieved_sample_new = as.numeric(achieved_sample)) %>% select(strata_id, achieved_sample_new),
             by = "strata_id") %>%
  filter(achieved_sample_old != achieved_sample_new)
cat(sprintf("\nStrata-level FULL achieved_sample recompute: %d stratum/strata changed (Nganzai expected; any others are latent drift this also fixes):\n", nrow(changed)))
print(as.data.frame(changed))

# ---- Verify + write ----------------------------------------------------------
gwandu_after <- full_sl %>% filter(strata_id == "idp_NG022010")
stopifnot(gwandu_after$coverage_status == "excluded", gwandu_after$exclusion_reason == "certainty_stratum_below_moe_threshold")
nganzai_after <- full_sl %>% filter(strata_id == "non_idp_NG008026") %>% pull(achieved_sample) %>% as.numeric()
stopifnot(nganzai_after == 308)
n_contradictory_left <- full_sl %>% filter(coverage_status == "covered", !(exclusion_reason %in% c("none", "", NA))) %>% nrow()
stopifnot(n_contradictory_left == 0)

write_csv(full_sl, sl_path)
cat(sprintf("\nWritten. Gwandu IDP: excluded. Nganzai achieved_sample: %s -> %s. %d other stratum/strata also corrected. 0 contradictory covered/exclusion_reason rows remain.\n",
            nganzai_before, nganzai_after, nrow(changed) - 1))
