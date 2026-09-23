# ==============================================================================
# Task 5 (2026-09-13/14) follow-up: per-partner summary of the target-
# correction drop list, for wrapping into the end-of-batch partner emails
# Jack asked for. Read-only - just summarizes resampling/output/target_
# correction_dropped_clusters.csv, doesn't touch anything live.
#
# Usage: Rscript summarize_target_correction_drops_by_partner.R
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(tidyr) })

drops <- read_csv("resampling/output/target_correction_dropped_clusters.csv", show_col_types = FALSE)
strata <- read_csv("output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v13_FULL.csv",
                    show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  distinct(strata_id, adm1_name, adm2_name, partners_covering)

detail <- drops %>% left_join(strata, by = "strata_id")

by_partner <- detail %>%
  separate_rows(partners_covering, sep = ",\\s*") %>%
  group_by(partners_covering) %>%
  summarise(
    n_clusters_dropped = n(),
    n_households_dropped = sum(as.integer(target_households)),
    n_already_achieved_in_dropped = sum(as.integer(n_achieved)),
    n_strata_affected = n_distinct(strata_id),
    .groups = "drop"
  ) %>%
  arrange(desc(n_clusters_dropped))

cat("=== By partner ===\n")
print(as.data.frame(by_partner))
write_csv(by_partner, "resampling/output/target_correction_drops_by_partner_summary.csv")

out <- detail %>%
  separate_rows(partners_covering, sep = ",\\s*") %>%
  select(partners_covering, adm1_name, adm2_name, strata_id, cluster_id, target_households, n_achieved) %>%
  arrange(partners_covering, adm1_name, adm2_name, strata_id)
write_csv(out, "resampling/output/target_correction_drops_by_partner_for_emails.csv")

cat(sprintf("\nWrote resampling/output/target_correction_drops_by_partner_summary.csv (per-partner totals) and "))
cat("target_correction_drops_by_partner_for_emails.csv (full per-cluster detail).\n")
cat(sprintf("\nTotals: %d clusters dropped, %d nominal households, %d already-achieved households preserved (stranded credit) across %d partners.\n",
            sum(by_partner$n_clusters_dropped), sum(by_partner$n_households_dropped), sum(by_partner$n_already_achieved_in_dropped), nrow(by_partner)))
