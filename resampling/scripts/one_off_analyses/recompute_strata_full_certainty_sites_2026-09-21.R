# ==============================================================================
# Companion fix to add_certainty_site_interviews_2026-09-21.py (same night).
# That script added primary rows to household-level FULL for 4 certainty
# clusters but did not recompute strata-level FULL, which every partner merge
# does (merge_partner_resample_batch.R's recompute_strata(), FULL branch).
# Coordinator's validity suite caught it: frame_integrity "strata-level FULL
# achieved_sample equals the real primary-row count in household-level FULL"
# failed on exactly those 4 strata, by exactly the rows added (+31/+5/+2/+1).
# strata-level WORKING was already right - refresh_working_frame_daily.R
# recomputes it every run ("4 changed achieved_sample").
#
# Applies the SAME recompute the merge applies (compute_strata_achieved() from
# scripts/shared/frame_status.R, filter_ward_accessible = FALSE; realized_moe_
# pct from realized_moe_unequal() over the returned cluster sizes) to those 4
# strata only, and refuses to write unless the new achieved_sample equals the
# household-level primary-row count for each.
# Usage: Rscript recompute_strata_full_certainty_sites_2026-09-21.R
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(tibble) })
source("scripts/shared/frame_status.R")

DC_DIR <- "output/data/data_collection"
MONITORING_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring"
AFFECTED <- c("idp_NG008023", "idp_NG021032", "idp_NG021007", "idp_NG021017")
SL_FULL <- file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v11_FULL.csv")

full_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv"), show_col_types = FALSE)
full_sl <- read_csv(SL_FULL, show_col_types = FALSE)
subs <- read_csv(file.path(MONITORING_DIR, "data", "real_submissions.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
deletions_overlay <- read_csv(file.path(MONITORING_DIR, "data", "CONFIRMED_DELETIONS_OVERLAY.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
achieved_lookup <- compute_achieved_lookup(subs, deletions_overlay)

base <- full_hh %>% filter(strata_id %in% AFFECTED)
result <- compute_strata_achieved(base, achieved_lookup, filter_ward_accessible = FALSE)
agg <- result$agg
sizes <- split(result$cluster_sizes$n, result$cluster_sizes$strata_id)

expected <- base %>% filter(status == "primary", sampling_method != "MSNA Light" | is.na(sampling_method)) %>% count(strata_id, name = "primaries")
check <- agg %>% left_join(expected, by = "strata_id")
print(check)
if (nrow(check) != length(AFFECTED) || any(check$achieved_sample != check$primaries)) {
  stop("STOP: recomputed achieved_sample does not equal the household-level primary-row count for every affected stratum - nothing written.")
}

before <- full_sl %>% filter(strata_id %in% AFFECTED) %>% select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)
full_sl_new <- full_sl %>%
  left_join(agg %>% rename(ac_new = achieved_clusters, as_new = achieved_sample), by = "strata_id") %>%
  mutate(
    realized_moe_pct = ifelse(is.na(as_new), realized_moe_pct,
      mapply(function(sid, a, N, icc) {
        if (is.na(a) || !(a > 0 & a < N)) return(NA_real_)
        100 * realized_moe_unequal(a, N, sizes[[sid]], icc)
      }, strata_id, as_new, N_hh, ICC)),
    achieved_clusters = if_else(!is.na(ac_new), ac_new, achieved_clusters),
    achieved_sample = if_else(!is.na(as_new), as_new, achieved_sample)
  ) %>%
  select(-ac_new, -as_new)
stopifnot(nrow(full_sl_new) == nrow(full_sl), identical(names(full_sl_new), names(full_sl)))

dir.create(file.path(DC_DIR, "_archive", "2026-09-21_pre_strata_full_certainty_fix"), recursive = TRUE, showWarnings = FALSE)
file.copy(SL_FULL, file.path(DC_DIR, "_archive", "2026-09-21_pre_strata_full_certainty_fix", basename(SL_FULL)), overwrite = TRUE)
write_csv(full_sl_new, SL_FULL)

after <- full_sl_new %>% filter(strata_id %in% AFFECTED) %>% select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)
cat("\nBEFORE\n"); print(before)
cat("\nAFTER\n"); print(after)
n_other_changed <- sum(full_sl_new$achieved_sample != full_sl$achieved_sample & !(full_sl$strata_id %in% AFFECTED), na.rm = TRUE)
cat(sprintf("\nStrata outside the 4 changed: %d (must be 0)\n", n_other_changed))
stopifnot(n_other_changed == 0)
