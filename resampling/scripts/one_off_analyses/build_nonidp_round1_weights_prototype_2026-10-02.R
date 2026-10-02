# Non-IDP Round 1 design weights - PROTOTYPE (2 Oct 2026, Coordinator, overnight).
#
# Implements the Non-IDP half of the 7-step repeat-draw fix Jack accepted on 1 Oct (option ii,
# full cluster-level design weights; see memory project_dual_round_representativity_design_2026-10-01):
#   1-2. a physical hex drawn more than once (separate cluster records for one uuid_hex, Tier 2
#        repeats) is ONE sampling unit in the weighting layer; frame cluster_ids are untouched
#   3.   second stage = real interviews / households for EVERY unit (realized, not design target)
#   4.   weights calibrated so each stratum sums to its accessible households
#        (N_hh x GIS accessible share - the same denominator as representativity)
#   5.   Kish unequal-weighting effect per stratum, before (as recorded) and after the fix
# First stage reuses piece 2's formula unchanged (build_nonidp_realized_psu_probability_2026-09-28.R):
#   psu_probability = 1 for certainty strata, else min(1, (design + supplementary clusters) * MOS / total_MOS)
# Not decided, so set aside and flagged rather than guessed: MSNA Light clusters (different design),
# clusters whose hex has no population record (no first-stage probability), and the capping rule.
#
# Usage (PowerShell; sf segfaults from Git Bash):
#   Rscript build_nonidp_round1_weights_prototype_2026-10-02.R <submissions_dir> <out_dir>
# <submissions_dir> holds real_submissions.csv + CONFIRMED_DELETIONS_OVERLAY.csv. Read-only on every input.
suppressMessages({ library(dplyr); library(sf); library(readr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
source("scripts/shared/realized_weights.R")
args <- commandArgs(trailingOnly = TRUE)
SUBS_DIR <- if (length(args) >= 1) args[1] else "../2_monitoring/data"
OUT <- if (length(args) >= 2) args[2] else "resampling/output/full_weighting_build_2026-09-28/round1_prototype_2026-10-02"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE)
strata <- read_csv("output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv", show_col_types = FALSE)
gis <- read_csv("resampling/output/gis/accessible_area_lga_ward_portions.csv", show_col_types = FALSE)

# ---- clusters + first stage (piece 2, unchanged) ----
# A cluster can carry BOTH sampling methods on different rows (Ngala NI's 29 Sep Light conversion was
# scoped to Accessible-ward rows only, e.g. non_idp_NG008025_16), so method is summarised per cluster:
# any Light row makes the cluster Light for weighting purposes (set aside, not weighted here).
cl <- full %>%
  filter(pop_type == "non_idp", !is.na(supplementary_cluster)) %>%
  group_by(cluster_id) %>% mutate(sampling_method = if (any(sampling_method == "MSNA Light")) "MSNA Light" else first(sampling_method)) %>% ungroup() %>%
  distinct(cluster_id, strata_id, adm2_pcode, uuid_hex, certainty_stratum, supplementary_cluster,
           households_in_cluster, target_households, sampling_method)
stopifnot(!anyDuplicated(cl$cluster_id))
counts <- cl %>% group_by(strata_id) %>%
  summarise(clusters_design = n_distinct(cluster_id[!supplementary_cluster]),
            n_supplementary = n_distinct(cluster_id[supplementary_cluster]), .groups = "drop")
hex_live <- readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds") %>% st_drop_geometry() %>% select(uuid_hex, adm2_pcode, pop_hh)
hex_arch <- readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_non_idp.rds") %>% st_drop_geometry() %>% select(uuid_hex, adm2_pcode, pop_hh)
hex <- bind_rows(hex_live, hex_arch %>% filter(!uuid_hex %in% hex_live$uuid_hex))
tot <- hex %>% group_by(adm2_pcode) %>% summarise(total_MOS = sum(pop_hh, na.rm = TRUE), .groups = "drop")
cl <- cl %>%
  left_join(hex %>% select(uuid_hex, MOS = pop_hh), by = "uuid_hex") %>%
  left_join(counts, by = "strata_id") %>% left_join(tot, by = "adm2_pcode") %>%
  mutate(psu_probability = case_when(certainty_stratum ~ 1, is.na(MOS) | is.na(total_MOS) ~ NA_real_,
                                     TRUE ~ pmin(1, (clusters_design + n_supplementary) * MOS / total_MOS)))

# ---- Round 1 interviews (canonical is_achieved, via the shared helper) ----
subs <- read_csv(file.path(SUBS_DIR, "real_submissions.csv"), col_types = cols(.default = col_character()))
dels <- read_csv(file.path(SUBS_DIR, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = cols(.default = col_character()))
del_uuids <- dels$uuid[dels$status %in% c("confirmed", "contested")]
iv <- subs %>%
  filter(interview_outcome == "completed", !is.na(matched_survey_id), !(submission_uuid %in% del_uuids)) %>%
  select(submission_uuid, cluster_id = matched_cluster_id, strata_id = matched_strata_id) %>%
  inner_join(cl %>% select(cluster_id, uuid_hex, sampling_method, psu_probability, households_in_cluster,
                           target_households, certainty_stratum), by = "cluster_id")
stopifnot(identical(sum(compute_achieved_by_cluster(subs, dels)$n_achieved[compute_achieved_by_cluster(subs, dels)$cluster_id %in% cl$cluster_id]), nrow(iv)))

# Non-IDP achieved interviews whose cluster is outside the weighting scope (MSNA Light clusters carry no
# supplementary_cluster flag, so the scope filter above drops them) - counted, never silently lost
nonidp_ach <- subs %>% filter(interview_outcome == "completed", !is.na(matched_survey_id), matched_survey_id != "NA",
                              !(submission_uuid %in% del_uuids), pop_type == "non_idp")
out_scope <- nonidp_ach %>% filter(!(matched_cluster_id %in% cl$cluster_id))
fm <- full %>% group_by(cluster_id) %>% summarise(m = paste(sort(unique(sampling_method)), collapse = "+"), .groups = "drop")
out_scope_m <- out_scope %>% left_join(fm, by = c("matched_cluster_id" = "cluster_id"))
tab <- table(out_scope_m$m, useNA = "ifany")
cat(sprintf("Non-IDP achieved (canonical): %d | outside weighting scope: %d (%s)\n", nrow(nonidp_ach), nrow(out_scope),
            paste(sprintf("%s x%d", names(tab), as.integer(tab)), collapse = ", ")))
light <- iv %>% filter(sampling_method == "MSNA Light")
no_mos <- iv %>% filter(sampling_method != "MSNA Light", is.na(psu_probability))
w <- iv %>% filter(sampling_method != "MSNA Light", !is.na(psu_probability))

# ---- (before) weights as recorded: one unit per cluster record, realized SSU only when topped up ----
rec <- w %>% count(cluster_id, name = "n_rec") %>% left_join(cl %>% select(cluster_id, psu_probability, households_in_cluster, target_households), by = "cluster_id")
rw <- compute_realized_weight_for_cluster(rec$psu_probability, rec$target_households, rec$households_in_cluster, rec$n_rec)
rec$ssu_before <- ifelse(rw$topped_up, rw$ssu_probability, pmin(1, rec$target_households / rec$households_in_cluster))
w <- w %>% left_join(rec %>% transmute(cluster_id, w_before = 1 / (psu_probability * ssu_before)), by = "cluster_id")

# ---- (after) steps 1-3: pool records of one physical hex, realized SSU for every unit ----
units <- w %>% group_by(strata_id, uuid_hex) %>%
  summarise(n_unit = n(), n_records = n_distinct(cluster_id),
            psu_u = first(psu_probability), psu_spread = max(psu_probability) - min(psu_probability),
            hh_u = first(households_in_cluster), hh_spread = max(households_in_cluster) - min(households_in_cluster), .groups = "drop") %>%
  mutate(ssu_u = pmin(1, n_unit / hh_u), w_unit_each = 1 / (psu_u * ssu_u))
inconsistent <- units %>% filter(psu_spread > 1e-9 | hh_spread > 0)
w <- w %>% left_join(units %>% select(strata_id, uuid_hex, w_after = w_unit_each), by = c("strata_id", "uuid_hex"))

# ---- step 4: calibrate each stratum to its accessible households ----
acc <- gis %>% group_by(adm2_pcode, pop_type) %>%
  summarise(pct = 100 * sum(pop_total[accessible_status == "Accessible"]) / sum(pop_total), .groups = "drop") %>%
  filter(pop_type == "Non-IDP")
n_acc <- strata %>% filter(pop_type == "non_idp") %>% select(strata_id, adm2_pcode, adm1_name, adm2_name, N_hh) %>%
  left_join(acc %>% select(adm2_pcode, pct), by = "adm2_pcode") %>% mutate(N_acc = N_hh * coalesce(pct, 0) / 100)
w <- w %>% left_join(n_acc %>% select(strata_id, N_acc), by = "strata_id") %>%
  group_by(strata_id) %>% mutate(w_cal = w_after * N_acc / sum(w_after)) %>% ungroup()

# ---- step 5: Kish per stratum, before vs after ----
kish <- function(x) length(x) * sum(x^2) / sum(x)^2
summ <- w %>% group_by(strata_id) %>%
  summarise(n = n(), units = n_distinct(uuid_hex), cluster_records = n_distinct(cluster_id),
            pooled_repeat_hexes = sum(table(uuid_hex[!duplicated(cluster_id)]) > 1),
            kish_before = kish(w_before), kish_after = kish(w_after),
            N_acc = first(N_acc), sum_w_cal = sum(w_cal), .groups = "drop") %>%
  left_join(n_acc %>% select(strata_id, State = adm1_name, LGA = adm2_name), by = "strata_id") %>%
  arrange(desc(kish_after))

write_csv(w %>% select(submission_uuid, strata_id, cluster_id, uuid_hex, psu_probability, w_before, w_after, w_cal), file.path(OUT, "nonidp_round1_weights_by_interview.csv"))
write_csv(summ, file.path(OUT, "nonidp_round1_weights_by_stratum.csv"))
write_csv(units, file.path(OUT, "nonidp_round1_weighting_units.csv"))

cat(sprintf("\nNon-IDP Round 1 interviews: %d | weighted %d | MSNA Light set aside %d | no first-stage probability (hex not in grid) %d\n",
            nrow(iv), nrow(w), nrow(light), nrow(no_mos)))
if (nrow(no_mos)) cat("   no-MOS clusters:", paste(unique(no_mos$cluster_id), collapse = ", "), "\n")
cat(sprintf("weighting units: %d from %d cluster records; physical hexes holding >1 record (pooled repeat draws): %d in %d strata\n",
            nrow(units), n_distinct(w$cluster_id), sum(units$n_records > 1), n_distinct(units$strata_id[units$n_records > 1])))
cat(sprintf("units whose records disagree on psu_probability or households (should be 0): %d\n", nrow(inconsistent)))
if (nrow(inconsistent)) print(as.data.frame(inconsistent %>% left_join(w %>% distinct(uuid_hex, cluster_id, psu_probability, households_in_cluster), by = "uuid_hex")))
cat(sprintf("calibration: every stratum sums to its accessible households: %s (max abs diff %.6f)\n",
            isTRUE(all.equal(summ$sum_w_cal, summ$N_acc)), max(abs(summ$sum_w_cal - summ$N_acc))))
cat(sprintf("Kish weighting effect across %d strata - BEFORE (as recorded): median %.2f, 90th %.2f, max %.2f | AFTER (pooled, realized): median %.2f, 90th %.2f, max %.2f\n",
            nrow(summ), median(summ$kish_before), quantile(summ$kish_before, .9), max(summ$kish_before),
            median(summ$kish_after), quantile(summ$kish_after, .9), max(summ$kish_after)))
cat("top 8 strata by Kish after the fix:\n"); print(as.data.frame(head(summ %>% select(State, LGA, n, units, pooled_repeat_hexes, kish_before, kish_after) %>% mutate(across(c(kish_before, kish_after), ~ round(.x, 2))), 8)))
yauri <- summ %>% filter(LGA == "Yauri"); if (nrow(yauri)) { cat("Yauri check:\n"); print(as.data.frame(yauri)) }
cat("wrote", OUT, "\n")
