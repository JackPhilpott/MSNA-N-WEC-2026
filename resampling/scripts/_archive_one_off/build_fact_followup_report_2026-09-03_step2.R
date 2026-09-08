# ==============================================================================
# Step 2: derive the Cluster Accessibility sheet's data. A cluster's own
# Accessible (Y/N) comes directly from its live ward_accessible_status in
# today's FULL frame - the most precise, current signal for that exact
# cluster - not purely inherited from the ward-level aggregate.
#
# REVISED 2026-09-03 (v3), per Jack: cluster-level needs_attention is no
# longer a blanket inherit-from-ward flag - a "mixed" ward (some clusters
# accessible, some not) does NOT mean every cluster in it is uncertain,
# since each cluster already has its own clear live status. Flagging rule
# per ward-level flag_type (from step 1):
#   - kebbi_update / matazu_update / never_reported: whole-ward partner
#     report/ask - cascades to every cluster in the ward, since there's no
#     cluster-level distinction to make for these.
#   - drift (live status changed since last report): cascades ONLY to the
#     specific cluster(s) whose own live status doesn't match what was
#     previously reported for the ward - i.e. the clusters actually
#     responsible for the drift, not every cluster in it.
#   - mixed_info_only: does NOT cascade to any cluster at all.
#   - no ward-level flag at all: a cluster still gets flagged on its own if
#     it simply has no live accessible-status signal (genuinely unknown).
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr); library(stringr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
norm <- function(x) str_squish(coalesce(x, ""))

ward <- read_csv("resampling/output/resample_runs/FACT/2026-09-03/fact_followup_ward_reconciled.csv", show_col_types = FALSE) %>%
  mutate(state_k = norm(State), lga_k = norm(LGA), ward_k = norm(`Ward (GRID3)`))
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                  show_col_types = FALSE, col_types = cols(.default = "c"))

clusters <- full %>%
  filter(str_detect(partners_covering, "FACT")) %>%
  distinct(cluster_id, adm1_name, adm2_name, adm3_name, pop_type, idp_population_category,
           target_households, reserve_households, ward_accessible_status) %>%
  mutate(state_k = norm(adm1_name), lga_k = norm(adm2_name), ward_k = norm(adm3_name),
         live_cluster_access = case_when(ward_accessible_status == "Accessible" ~ "Yes",
                                          ward_accessible_status == "Inaccessible" ~ "No", TRUE ~ NA_character_))

# ward-level historical status, for the "which cluster caused the drift" test
ward_hist <- ward %>% select(state_k, lga_k, ward_k, ward_flag_type = flag_type,
                              ward_flag_reason = flag_reason, Reason, Notes, `Date reported`)

cluster_out <- clusters %>%
  left_join(ward_hist, by = c("state_k", "lga_k", "ward_k")) %>%
  mutate(
    cluster_flagged = case_when(
      is.na(live_cluster_access) ~ TRUE,  # this specific cluster's own status is genuinely unknown
      ward_flag_type %in% c("kebbi_update", "matazu_update", "never_reported") ~ TRUE,
      ward_flag_type == "drift" & live_cluster_access == "Yes" ~ TRUE,  # the cluster(s) actually driving the drift
      TRUE ~ FALSE
    ),
    cluster_flag_reason = case_when(
      is.na(live_cluster_access) ~ "This specific cluster has no accessibility status recorded - please confirm.",
      cluster_flagged ~ ward_flag_reason,
      TRUE ~ NA_character_
    )
  ) %>%
  transmute(
    State = adm1_name, LGA = adm2_name, `Ward (GRID3)` = adm3_name,
    `Pop Type` = if_else(pop_type == "idp", "IDP", "Non-IDP"),
    `Cluster ID` = cluster_id,
    `IDP Category` = if_else(pop_type == "idp",
                              if_else(idp_population_category == "idps in camp", "In-camp", "In-host"), NA_character_),
    `Target HHs (primary)` = as.integer(target_households),
    `Reserve HHs` = as.integer(reserve_households),
    `Accessible (Y/N)` = live_cluster_access, `Reason category` = Reason, `Reason notes` = Notes,
    `Date reported`,
    needs_attention = cluster_flagged, flag_reason = cluster_flag_reason
  ) %>%
  arrange(State, LGA, `Ward (GRID3)`, `Cluster ID`)

cat(sprintf("Cluster Accessibility rows: %d (%d needing attention, was 321 before this fix)\n",
            nrow(cluster_out), sum(cluster_out$needs_attention)))
cat(sprintf("Clusters with no live accessible-status signal at all: %d\n", sum(is.na(cluster_out$`Accessible (Y/N)`))))
write_csv(cluster_out, "resampling/output/resample_runs/FACT/2026-09-03/fact_followup_cluster_reconciled.csv")
cat("Wrote resampling/output/resample_runs/FACT/2026-09-03/fact_followup_cluster_reconciled.csv\n")
