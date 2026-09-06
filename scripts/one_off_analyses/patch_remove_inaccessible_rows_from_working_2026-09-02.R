# ==============================================================================
# Found 2026-09-02, after merging FACT's staged resample: merge_partner_
# resample_batch.R appended new/expanded-cluster household rows to WORKING
# unconditionally, without checking ward_accessible_status - so wherever a
# repeat-site draw merged into an EXISTING cluster that's ward-inaccessible
# (idp_NG021014_6/Funtua and 4 other FACT clusters), the new rows (which
# correctly carry that cluster's real "Inaccessible" status, templated
# directly off the existing cluster's own row) ended up live in WORKING
# anyway. 60 rows across 5 clusters, 4 strata. Fixed permanently in
# merge_partner_resample_batch.R (working_new_rows filter, added same day);
# this patch removes the 60 rows already written to the live WORKING CSV
# before that fix existed, and recomputes the 4 affected strata's
# achieved_clusters/achieved_sample/realized_moe_pct from the corrected
# WORKING rows.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

full <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
working <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))

bad_survey_ids <- full %>%
  filter(survey_id %in% working$survey_id, ward_accessible_status == "Inaccessible") %>%
  pull(survey_id)

cat("Removing", length(bad_survey_ids), "inaccessible-ward row(s) from WORKING...\n")
affected_strata <- full %>% filter(survey_id %in% bad_survey_ids) %>% distinct(strata_id) %>% pull(strata_id)
cat("Affected strata:", paste(affected_strata, collapse = ", "), "\n")

working_fixed <- working %>% filter(!survey_id %in% bad_survey_ids)
cat("WORKING rows:", nrow(working), "->", nrow(working_fixed), "\n")
write_csv(working_fixed, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"))

# ---- Recompute strata-level WORKING for affected strata ----
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
agg <- working_fixed %>% filter(strata_id %in% affected_strata, status == "primary") %>%
  group_by(strata_id) %>% summarise(achieved_clusters_new = n_distinct(cluster_id), achieved_sample_new = n(), .groups = "drop")

realized_moe <- function(achieved_sample, N_hh, m, ICC, Z = qnorm(0.95), p = 0.5) {
  deff  <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

working_sl_fixed <- working_sl %>%
  left_join(agg, by = "strata_id") %>%
  mutate(
    achieved_clusters_new = coalesce(achieved_clusters_new, 0L),
    achieved_sample_new = coalesce(achieved_sample_new, 0L),
    achieved_clusters = if_else(strata_id %in% affected_strata, as.character(achieved_clusters_new), achieved_clusters),
    achieved_sample = if_else(strata_id %in% affected_strata, as.character(achieved_sample_new), achieved_sample),
    realized_moe_pct = if_else(
      strata_id %in% affected_strata & achieved_sample_new > 0 & achieved_sample_new < as.numeric(N_hh),
      as.character(100 * realized_moe(achieved_sample_new, as.numeric(N_hh), as.numeric(m_used), as.numeric(ICC))),
      if_else(strata_id %in% affected_strata & achieved_sample_new == 0, NA_character_, realized_moe_pct)
    )
  ) %>%
  select(-achieved_clusters_new, -achieved_sample_new)

write_csv(working_sl_fixed, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"))

cat("\nCorrected strata-level WORKING figures:\n")
print(as.data.frame(working_sl_fixed %>% filter(strata_id %in% affected_strata) %>%
  select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)))

cat("\nDONE.\n")
