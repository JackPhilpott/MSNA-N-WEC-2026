# ==============================================================================
# Builds the reconciled FACT ward + cluster accessibility data for the
# 2026-09-03 follow-up workbook, per Jack's review of Talatu's two messy
# raw-comms submissions - see the published review artifact for the full
# evidence behind every decision made here.
#
# REVISED 2026-09-03 (v2): the first version used
# master_accessibility_status_ward_level.csv (built 2026-09-01 14:42) as
# the source of truth for the Accessible Y/N value itself. Jack caught
# that this can go stale - specifically, 9 wards (Bakori, Kafur, Safana,
# Dan Musa, Funtua) had a NEW accessible cluster added by this session's
# own resampling work AFTER that snapshot was taken, and the old file
# still showed them as fully inaccessible. Fixed by making the LIVE FULL
# frame (today, current) the authoritative source for Accessible Y/N -
# master_accessibility_status is now used only for reason/notes/provenance
# text layered on top, and any place where that historical reason
# contradicts today's live status gets flagged generically rather than
# trusted blindly.
#
# A ward can legitimately have mixed cluster-level ward_accessible_status
# (part of it accessible, part not - a real, correct representation of
# partial-ward access, not corruption; confirmed 45 such wards nationally
# for FACT alone). Ward-level Accessible = "Yes" if ANY currently-covered
# FACT cluster in that ward is accessible, "No" only if all are - flagged
# separately as "mixed" so it's visible rather than silently averaged away.
# Join keys are trimmed/normalised throughout after the first version hit
# a silent string-mismatch bug that made 37 real wards look unmatched.
#
# Layers applied on top of the live-frame base, in this order:
#   1. Generic contradiction fixes on the historical reason text (Yes-
#      implying reason but a real access issue described, etc.)
#   2. The 2026-09-03 Kebbi security update (13 wards from her file + 6
#      matched from her email text but never applied there)
#   3. The Matazu subcontractor notes (2 flipped, 6 unresolved)
#   4. Anything never reported at all
#   5. NEW: anywhere today's live status disagrees with what the
#      historical report implied - e.g. the 9 Bakori/Kafur/Safana/etc.
#      wards this bug fix exists for - flagged as "status has changed
#      since it was last reported."
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr); library(stringr); library(tidyr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
log_msg <- function(...) cat(sprintf(...), "\n")

master <- read_csv("resampling/output/master_accessibility_status_ward_level.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                  show_col_types = FALSE, col_types = cols(.default = "c"))

norm <- function(x) str_squish(coalesce(x, ""))

# ---- 1. Ward universe + live Accessible Y/N, built fresh from today's FULL frame ----
fact_clusters <- full %>%
  filter(str_detect(partners_covering, "FACT")) %>%
  mutate(state_k = norm(adm1_name), lga_k = norm(adm2_name), ward_k = norm(adm3_name))

ward_live <- fact_clusters %>%
  distinct(state_k, lga_k, ward_k, adm1_name, adm2_name, adm3_name, admin3_cod_name,
           cluster_id, ward_accessible_status) %>%
  group_by(state_k, lga_k, ward_k) %>%
  summarise(
    State = first(adm1_name), LGA = first(adm2_name), `Ward (GRID3)` = first(adm3_name),
    `Ward (OCHA/COD)` = first(na.omit(admin3_cod_name)),
    n_clusters_total = n_distinct(cluster_id),
    n_accessible = n_distinct(cluster_id[ward_accessible_status == "Accessible"]),
    n_inaccessible = n_distinct(cluster_id[ward_accessible_status == "Inaccessible"]),
    live_access = case_when(
      n_accessible > 0 ~ "Yes",
      n_inaccessible > 0 ~ "No",
      TRUE ~ NA_character_
    ),
    mixed = n_accessible > 0 & n_inaccessible > 0,
    .groups = "drop"
  )
log_msg("Ward universe built fresh from today's live frame: %d wards (FACT).", nrow(ward_live))
log_msg("  Mixed wards (some clusters accessible, some not): %d", sum(ward_live$mixed))
log_msg("  Wards with no live_access signal at all (no cluster carries a status): %d", sum(is.na(ward_live$live_access)))

# ---- 2. Layer on historical reason/notes/provenance from master status (normalised keys) ----
master_k <- master %>% mutate(state_k = norm(State), lga_k = norm(LGA), ward_k = norm(`Ward (GRID3)`)) %>%
  filter(str_detect(`Partners covering this LGA-ward portion`, "FACT")) %>%
  distinct(state_k, lga_k, ward_k, .keep_all = TRUE) %>%
  rename(hist_Accessible = `Accessible status`, Reason = `Reason category`, Notes = `Reason notes`,
         hist_date = `Last reported date`) %>%
  mutate(hist_Accessible = case_when(hist_Accessible == "Accessible" ~ "Yes", hist_Accessible == "Inaccessible" ~ "No", TRUE ~ NA_character_)) %>%
  select(state_k, lga_k, ward_k, hist_Accessible, Reason, Notes, hist_date, `Non-IDP clusters`, `IDP clusters`, `Total target HHs (primary)`)

fact <- ward_live %>% left_join(master_k, by = c("state_k", "lga_k", "ward_k")) %>%
  mutate(Accessible = live_access, needs_attention = FALSE, flag_reason = NA_character_, flag_type = NA_character_)
log_msg("Wards with no matching historical record at all (brand new since master status was built): %d", sum(is.na(fact$hist_Accessible) & is.na(fact$Reason)))

# ---- 3. Generic contradiction fixes (on the historical reason, before we trust it for Notes) ----
contradiction <- fact$hist_Accessible == "Yes" & !is.na(fact$Reason) & fact$Reason != "N/A - fully accessible"
log_msg("Generic fix: historical Yes + non-N/A reason contradiction -> %d row(s)", sum(contradiction, na.rm = TRUE))
fact$Reason[which(contradiction)] <- fact$Reason[which(contradiction)]  # keep the real reason, just don't trust hist_Accessible=Yes from it
fact$hist_Accessible[which(contradiction)] <- "No"

# ---- 4. Mark where LIVE status disagrees with the historical report (the bug this fix exists for) ----
# flag_type = "drift" - at cluster level (step 2), this cascades ONLY to the
# specific cluster(s) that are newly accessible, not every cluster in the
# ward - a ward flipping No -> Yes because ONE new cluster was added doesn't
# mean every other (still-inaccessible) cluster in it is suddenly uncertain.
drift <- !is.na(fact$Accessible) & !is.na(fact$hist_Accessible) & fact$Accessible != fact$hist_Accessible
fact$needs_attention[drift] <- TRUE
fact$flag_type[drift] <- "drift"
fact$flag_reason[drift] <- paste0(
  "Our current sampling frame shows this ward as ", fact$Accessible[drift],
  ", which is different from what was last reported (", fact$hist_Accessible[drift],
  ") - likely because it changed since your last report. Please confirm."
)
log_msg("Wards where live status disagrees with the last historical report: %d", sum(drift))

# "mixed" (some clusters accessible, some not) is NOT flagged at all, per
# Jack's 2026-09-03 feedback: a mixed ward is correctly Yes (there IS
# accessible population there), the inaccessible clusters within it are
# already handled by the normal resample-that-cluster mechanism, and the
# Cluster Accessibility sheet already shows the real per-cluster truth
# regardless. There's no confirmation or decision to actually ask Talatu
# for here - flagging it was describing normal system behaviour, not
# raising something that needs her input. `mixed` is kept as a column for
# internal/future use but does not set needs_attention or flag_type.
log_msg("Mixed (partial-access) wards, NOT flagged (informational only, no action needed): %d", sum(fact$mixed))

# ---- 5. Kebbi security update (2026-09-03 v2 email + file) ----
kebbi_confirmed <- tribble(
  ~LGA, ~Ward,
  "Fakai", "Bangu", "Fakai", "Gulbin Kuka", "Fakai", "Isgogo Dago", "Fakai", "Kangi", "Fakai", "Marafa", "Fakai", "Peni Peni",
  "Ngaski", "Garin Baka", "Ngaski", "Kambuwa",
  "Wasagu/Danko", "Ayu", "Wasagu/Danko", "Dan Umaru Mairairai", "Wasagu/Danko", "Kanya", "Wasagu/Danko", "Maza Maza", "Wasagu/Danko", "Wasagu"
) %>% mutate(source = "applied_in_her_file")
kebbi_matched_from_email <- tribble(
  ~LGA, ~Ward,
  "Fakai", "Atuwo", "Fakai", "Fakku", "Fakai", "Danko Maga",
  "Wasagu/Danko", "Bena", "Wasagu/Danko", "Kyaram", "Wasagu/Danko", "Dankolo"
) %>% mutate(source = "matched_from_her_email_not_in_file")
kebbi_all <- bind_rows(kebbi_confirmed, kebbi_matched_from_email) %>% mutate(lga_k = norm(LGA), ward_k = norm(Ward))

for (i in seq_len(nrow(kebbi_all))) {
  idx <- which(fact$lga_k == kebbi_all$lga_k[i] & fact$ward_k == kebbi_all$ward_k[i])
  if (length(idx) == 0) { log_msg("  WARNING: no ward-row match for %s / %s", kebbi_all$LGA[i], kebbi_all$Ward[i]); next }
  fact$Accessible[idx] <- "No"
  fact$Reason[idx] <- "Insecurity / conflict"
  fact$Notes[idx] <- "Reported 2026-09-03: persistent banditry and Lakurawa activity (FACT subcontracted partner report, Kebbi)."
  fact$needs_attention[idx] <- TRUE
  fact$flag_type[idx] <- "kebbi_update"
  fact$flag_reason[idx] <- if (kebbi_all$source[i] == "applied_in_her_file")
    "New security report (2026-09-03) - please confirm this is correct. (Note: our live frame currently still shows this as accessible, since this update hasn't been formally applied to the sampling frame yet - that's expected, not an error.)"
  else
    "Named in your 2026-09-03 email as affected, but wasn't reflected in your file - matched to this ward directly. Please confirm."
}
log_msg("Kebbi security update applied to %d ward(s) (%d already in her file, %d matched from her email text only)",
        nrow(kebbi_all), sum(kebbi_all$source == "applied_in_her_file"), sum(kebbi_all$source == "matched_from_her_email_not_in_file"))

# ---- 6. Matazu subcontractor notes ----
matazu_flipped <- norm(c("Matazu A", "Matazu B"))
matazu_unresolved <- norm(c("Dissi", "Gwarjo", "Kogari", "Mazoji A", "Rinjin Idi", "Sayaya"))
idx_f <- which(fact$lga_k == norm("Matazu") & fact$ward_k %in% matazu_flipped)
fact$Accessible[idx_f] <- "Yes"
fact$Reason[idx_f] <- "N/A - fully accessible"
fact$Notes[idx_f] <- "Reported 2026-09-03: to be covered by a FACT subcontracted partner."
fact$needs_attention[idx_f] <- TRUE
fact$flag_type[idx_f] <- "matazu_update"
fact$flag_reason[idx_f] <- "You marked this Yes with a subcontracted-partner note - please confirm which partner, so we can record it properly. (Note: our live frame currently still shows this as inaccessible, since this update hasn't been formally applied yet - expected, not an error.)"
idx_u <- which(fact$lga_k == norm("Matazu") & fact$ward_k %in% matazu_unresolved)
fact$Notes[idx_u] <- "Reported 2026-09-03: to be covered by a FACT subcontracted partner (status not updated in your file)."
fact$needs_attention[idx_u] <- TRUE
fact$flag_type[idx_u] <- "matazu_update"
fact$flag_reason[idx_u] <- "Same subcontracted-partner note as Matazu A/B, but left as No here - please confirm whether this should also be Yes, and which partner."
log_msg("Matazu subcontractor notes applied to %d ward(s) (%d flipped, %d unresolved)", length(idx_f) + length(idx_u), length(idx_f), length(idx_u))

# ---- 7. Never-reported wards (no historical record AND no live status either) ----
never <- is.na(fact$Accessible) & is.na(fact$hist_Accessible)
fact$needs_attention[never] <- TRUE
fact$flag_type[never] <- ifelse(is.na(fact$flag_type[never]), "never_reported", fact$flag_type[never])
fact$flag_reason[never] <- ifelse(is.na(fact$flag_reason[never]), "Never reported - please provide Accessible Y/N and a reason.", fact$flag_reason[never])
log_msg("Never-reported wards flagged: %d", sum(never))

log_msg("\nTotal wards needing attention: %d of %d", sum(fact$needs_attention), nrow(fact))

out <- fact %>% select(State, LGA, `Ward (GRID3)`, `Ward (OCHA/COD)`, `Non-IDP clusters`, `IDP clusters`,
                        `Total target HHs (primary)`, Accessible, Reason, Notes, `Date reported` = hist_date,
                        needs_attention, flag_reason, flag_type, mixed)
write_csv(out, "resampling/output/resample_runs/FACT/2026-09-03/fact_followup_ward_reconciled.csv")
log_msg("Wrote resampling/output/resample_runs/FACT/2026-09-03/fact_followup_ward_reconciled.csv")
