# ==============================================================================
# Step 2: DRC Cluster Accessibility sheet. Cluster-level Accessible (Y/N)
# comes from the live frame directly (each cluster's own true status).
# needs_attention is scoped precisely, not inherited wholesale from the
# ward - matching the same fix applied to FACT's workbook on Jack's
# feedback: only the specific clusters DRC's report actually named get
# flagged, not every cluster sharing that ward.
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr); library(stringr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
norm <- function(x) str_squish(coalesce(x, ""))

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                  show_col_types = FALSE, col_types = cols(.default = "c"))

drc_clusters <- full %>%
  filter(str_detect(partners_covering, "DRC")) %>%
  distinct(cluster_id, adm1_name, adm2_name, adm3_name, pop_type, idp_population_category,
           target_households, reserve_households, ward_accessible_status) %>%
  mutate(`Accessible (Y/N)` = if_else(ward_accessible_status == "Accessible", "Yes", "No"),
         needs_attention = FALSE, flag_reason = NA_character_, `Reason category` = NA_character_, `Reason notes` = NA_character_)

# ---- Kaura Namoda: exactly these 4 clusters ----
kn_clusters <- c("idp_NG037008_12", "idp_NG037008_16", "idp_NG037008_17", "idp_NG037008_2")
idx <- which(drc_clusters$cluster_id %in% kn_clusters)
drc_clusters$`Accessible (Y/N)`[idx] <- "No"
drc_clusters$`Reason category`[idx] <- "Insecurity / conflict"
drc_clusters$`Reason notes`[idx] <- "Reported 2026-09-03: inaccessible due to insecurity (DRC's own submission)."
drc_clusters$needs_attention[idx] <- TRUE
drc_clusters$flag_reason[idx] <- "You reported this site as inaccessible - please confirm whether target was reached here via reserves, or supplementary/replacement clusters are needed."

# ---- Illela + Sokoto South: exactly the clusters DRC named (not the whole ward) ----
illela_survey_ids <- c("non_idp_NG034008_4_HH01","non_idp_NG034008_2_HH02","non_idp_NG034008_3_HH03","non_idp_NG034008_6_HH04",
  "non_idp_NG034008_5_HH06","non_idp_NG034008_12_HH06","non_idp_NG034008_10_HH01","non_idp_NG034008_9_HH06",
  "non_idp_NG034008_7_HH04","non_idp_NG034008_7_HH01","non_idp_NG034008_13_HH06","non_idp_NG034008_12_HH05",
  "non_idp_NG034008_12_HH03","non_idp_NG034008_11_HH02","non_idp_NG034008_8_HH02")
south_survey_ids <- c("non_idp_NG034017_2_HH03", "non_idp_NG034017_2_HH36")
flagged_hh <- full %>% filter(survey_id %in% c(illela_survey_ids, south_survey_ids)) %>%
  mutate(reason_txt = if_else(survey_id %in% south_survey_ids, "Military barrack", "Insecurity / conflict")) %>%
  count(cluster_id, reason_txt, name = "n_flagged")

idx2 <- match(flagged_hh$cluster_id, drc_clusters$cluster_id)
drc_clusters$`Reason notes`[idx2] <- paste0("Reported 2026-09-03: ", flagged_hh$n_flagged, " of this cluster's households flagged individually (reason: ", flagged_hh$reason_txt, ") - not the whole cluster. Accessible left as Yes pending confirmation.")
drc_clusters$needs_attention[idx2] <- TRUE
drc_clusters$flag_reason[idx2] <- "Only specific households in this cluster were flagged, not the whole cluster - please confirm this is household-specific rather than the wider ward being affected."

# ---- Isa: every cluster (no more granular info available) ----
idx3 <- which(drc_clusters$adm2_name == "Isa")
drc_clusters$`Reason notes`[idx3] <- "LGA reported 2026-09-03 as 'All location' with no further detail - not applied, needs clarification (Isa is also covered by IRC and LHI)."
drc_clusters$needs_attention[idx3] <- TRUE
drc_clusters$flag_reason[idx3] <- "Your submission said 'all location' for this LGA with no cluster-level detail - please confirm which clusters specifically, and why."

cluster_out <- drc_clusters %>%
  transmute(
    State = adm1_name, LGA = adm2_name, `Ward (GRID3)` = adm3_name,
    `Pop Type` = if_else(pop_type == "idp", "IDP", "Non-IDP"),
    `Cluster ID` = cluster_id,
    `IDP Category` = if_else(pop_type == "idp",
                              if_else(idp_population_category == "idps in camp", "In-camp", "In-host"), NA_character_),
    `Target HHs (primary)` = as.integer(target_households),
    `Reserve HHs` = as.integer(reserve_households),
    `Accessible (Y/N)`, `Reason category`, `Reason notes`,
    needs_attention, flag_reason
  ) %>%
  arrange(State, LGA, `Ward (GRID3)`, `Cluster ID`)

cat(sprintf("Cluster Accessibility rows: %d (%d needing attention)\n", nrow(cluster_out), sum(cluster_out$needs_attention)))
write_csv(cluster_out, "resampling/output/resample_runs/DRC/2026-09-03/drc_accessibility_cluster_reconciled.csv")
cat("Wrote resampling/output/resample_runs/DRC/2026-09-03/drc_accessibility_cluster_reconciled.csv\n")
