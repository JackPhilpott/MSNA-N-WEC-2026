# ==============================================================================
# Builds DRC's first-ever accessibility report - Ward + Cluster Accessibility,
# same standard template shape every other partner has (README + Ward
# Accessibility + Cluster Accessibility), which DRC has never been sent
# before now (confirmed: 0 rows for DRC in either accessibility_reports_
# generated/returned, and every one of their 63 wards shows "default_
# unreported" or an unflagged blank row in master_accessibility_status_
# ward_level.csv).
#
# Pre-filled with what we already know: the live sampling frame (current,
# authoritative - see the 2026-09-03 FACT fix for why this matters) as the
# base, then DRC's own 2026-09-03 "inaccessible location.xlsx" submission
# layered on top, applied at the SAME granularity DRC actually reported it:
#   - Kaura Namoda: 4 whole IDP clusters reported inaccessible (insecurity)
#     -> Accessible = No, flagged for DRC to confirm whether reserves
#     already covered the shortfall or supplementary clusters are needed
#     (Kaura Namoda is currently well below target on both pop types).
#   - Illela (12 clusters) + Sokoto South (1 cluster): only 1-3 of each
#     cluster's 6 households were flagged, never all 6 - kept Accessible =
#     Yes (matches both the live frame and the evidence), but the specific
#     affected household count is carried in Notes and the ward is flagged
#     asking DRC to confirm this is genuinely household-specific rather
#     than ward-wide (Illela has already hit 100% of target either way).
#   - Isa: DRC's own submission just says "All location" with no detail,
#     shared with IRC/LHI who haven't reported anything similar - left as
#     Accessible (unchanged) and flagged for clarification, NOT marked
#     inaccessible off one vague unconfirmed line.
# Everything else (DRC's other ~46 wards, zero report of any kind) is left
# as the live frame shows it (currently Accessible for all of DRC), NOT
# flagged - this is a "here's what we can fill in so far" pass per Jack,
# not a full first-time audit demand from a brand-new partner.
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr); library(stringr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
log_msg <- function(...) cat(sprintf(...), "\n")
norm <- function(x) str_squish(coalesce(x, ""))

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                  show_col_types = FALSE, col_types = cols(.default = "c"))

drc_clusters <- full %>%
  filter(str_detect(partners_covering, "DRC")) %>%
  mutate(state_k = norm(adm1_name), lga_k = norm(adm2_name), ward_k = norm(adm3_name))

# ---- Ward-level universe, live-frame Accessible Y/N as base ----
ward <- drc_clusters %>%
  distinct(state_k, lga_k, ward_k, adm1_name, adm2_name, adm3_name, admin3_cod_name,
           cluster_id, pop_type, ward_accessible_status) %>%
  group_by(state_k, lga_k, ward_k) %>%
  summarise(
    State = first(adm1_name), LGA = first(adm2_name), `Ward (GRID3)` = first(adm3_name),
    `Ward (OCHA/COD)` = first(na.omit(admin3_cod_name)),
    `Non-IDP clusters` = n_distinct(cluster_id[pop_type == "non_idp"]),
    `IDP clusters` = n_distinct(cluster_id[pop_type == "idp"]),
    Accessible = if_else(any(ward_accessible_status == "Accessible"), "Yes", "No"),
    .groups = "drop"
  ) %>%
  mutate(Reason = NA_character_, Notes = NA_character_, needs_attention = FALSE, flag_reason = NA_character_)

target_hh <- drc_clusters %>% filter(status == "primary") %>% count(state_k, lga_k, ward_k, name = "Total target HHs (primary)")
ward <- ward %>% left_join(target_hh, by = c("state_k", "lga_k", "ward_k")) %>%
  mutate(`Total target HHs (primary)` = coalesce(`Total target HHs (primary)`, 0L))

log_msg("DRC ward universe: %d wards, %d Non-IDP clusters, %d IDP clusters", nrow(ward), sum(ward$`Non-IDP clusters`), sum(ward$`IDP clusters`))

# ---- Kaura Namoda: 4 whole clusters flagged inaccessible ----
kn_clusters <- c("idp_NG037008_12", "idp_NG037008_16", "idp_NG037008_17", "idp_NG037008_2")
kn_wards <- drc_clusters %>% filter(cluster_id %in% kn_clusters) %>% distinct(lga_k, ward_k, adm3_name)
idx <- which(ward$lga_k == norm("Kaura Namoda") & ward$ward_k %in% kn_wards$ward_k)
ward$Accessible[idx] <- "No"
ward$Reason[idx] <- "Insecurity / conflict"
ward$Notes[idx] <- "Reported 2026-09-03: inaccessible due to insecurity (DRC's own submission)."
ward$needs_attention[idx] <- TRUE
ward$flag_reason[idx] <- "You reported this site as inaccessible - please confirm whether your team was able to reach target here using reserve households, or whether this needs supplementary/replacement clusters."
log_msg("Kaura Namoda: %d ward(s) marked inaccessible from your report", length(idx))

# ---- Illela + Sokoto South: household-specific reports, kept Accessible, flagged for confirmation ----
illela_survey_ids <- c("non_idp_NG034008_4_HH01","non_idp_NG034008_2_HH02","non_idp_NG034008_3_HH03","non_idp_NG034008_6_HH04",
  "non_idp_NG034008_5_HH06","non_idp_NG034008_12_HH06","non_idp_NG034008_10_HH01","non_idp_NG034008_9_HH06",
  "non_idp_NG034008_7_HH04","non_idp_NG034008_7_HH01","non_idp_NG034008_13_HH06","non_idp_NG034008_12_HH05",
  "non_idp_NG034008_12_HH03","non_idp_NG034008_11_HH02","non_idp_NG034008_8_HH02")
south_survey_ids <- c("non_idp_NG034017_2_HH03", "non_idp_NG034017_2_HH36")

hh_level <- full %>% filter(survey_id %in% c(illela_survey_ids, south_survey_ids)) %>%
  mutate(state_k = norm(adm1_name), lga_k = norm(adm2_name), ward_k = norm(adm3_name),
         reason_txt = if_else(survey_id %in% south_survey_ids, "Military barrack", "Insecurity / conflict")) %>%
  group_by(state_k, lga_k, ward_k) %>%
  summarise(n_flagged_hh = n(), reason_txt = first(reason_txt), .groups = "drop")

idx2 <- match(paste(hh_level$state_k, hh_level$lga_k, hh_level$ward_k),
              paste(ward$state_k, ward$lga_k, ward$ward_k))
ward$Notes[idx2] <- paste0("Reported 2026-09-03: ", hh_level$n_flagged_hh, " of the households in this ward's cluster(s) flagged individually (reason: ", hh_level$reason_txt, ") - not the whole cluster.")
ward$needs_attention[idx2] <- TRUE
ward$flag_reason[idx2] <- "Only specific households were flagged here, not the whole cluster - please confirm this is genuinely household-specific rather than the wider ward being affected."
log_msg("Illela + Sokoto South: %d ward(s) flagged for household-specific confirmation (Accessible left as-is)", length(idx2))

# ---- Isa: vague "all location" claim, shared with IRC/LHI ----
idx3 <- which(ward$lga_k == norm("Isa"))
ward$Notes[idx3] <- "Reported 2026-09-03 as 'All location' with no further detail - not applied, needs clarification (Isa is also covered by IRC and LHI, who have reported nothing similar)."
ward$needs_attention[idx3] <- TRUE
ward$flag_reason[idx3] <- "Your submission said 'all location' for this LGA with no detail - please confirm specifically which wards and why before we treat this as ward-wide, since Isa is shared with two other partners."
log_msg("Isa: %d ward(s) flagged for clarification (Accessible left as-is - not marked inaccessible on an unconfirmed blanket claim)", length(idx3))

log_msg("\nTotal wards flagged: %d of %d", sum(ward$needs_attention), nrow(ward))

out <- ward %>% select(State, LGA, `Ward (GRID3)`, `Ward (OCHA/COD)`, `Non-IDP clusters`, `IDP clusters`,
                        `Total target HHs (primary)`, Accessible, Reason, Notes, needs_attention, flag_reason)
dir.create("resampling/output/resample_runs/DRC/2026-09-03", recursive = TRUE, showWarnings = FALSE)
write_csv(out, "resampling/output/resample_runs/DRC/2026-09-03/drc_accessibility_ward_reconciled.csv")
log_msg("Wrote resampling/output/resample_runs/DRC/2026-09-03/drc_accessibility_ward_reconciled.csv")
