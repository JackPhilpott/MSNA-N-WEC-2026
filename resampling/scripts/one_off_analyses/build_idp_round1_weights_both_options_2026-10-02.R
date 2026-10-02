# IDP Round 1 design weights under BOTH open options - PROTOTYPE (2 Oct 2026, Coordinator, overnight).
# Jack deferred the choice to the morning; this computes both so the decision is picking a column.
# See full_weighting_build_2026-09-28/idp_psu_probability_decision_report_2026-10-02.md for the options.
#
#   Option 2 - the surveyed site stands in for its whole hex everywhere: every draw (a July hex hit, or a
#              post-2-Sep site draw) represents an equal share of its stratum (weight proportional to draws).
#   Option 3 - each household counted once, by the best route available:
#              mixed strata: real two-phase probability, site-level
#                  pi = pi_July + (1 - pi_July) * pi_site,  pi_site ~ min(1, k2 * site households / pool households)
#                  (July sites: pi_July from the 6 Aug design; post-2-Sep sites: pi_July = 0 - 206 of 249 lie in a
#                   July-SELECTED hex whose surveyed site was a different, larger one, so 0 is exact for them; for
#                   the rest it is a small approximation, flagged)
#              July-only strata: the surveyed site stands in for its hex (weight = hex households / pi_July)
#   Both: second stage realized (interviews / households) for every cluster; each stratum calibrated to its
#         accessible IDP households; Kish effect reported. No capping (that rule is Jack's morning call).
# July design = _archive/2026-08-06_design_frame_post_nw_targeted_resample (NOT the stale 3 Aug cache).
# Draw counts for post-2-Sep sites = Resampling's selection_count_net_of_topups (live column is inflated).
# Usage (PowerShell): Rscript build_idp_round1_weights_both_options_2026-10-02.R <submissions_dir> <out_dir>
suppressMessages({ library(dplyr); library(sf); library(readr) })
sf_use_s2(FALSE)
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
args <- commandArgs(trailingOnly = TRUE)
SUBS_DIR <- if (length(args) >= 1) args[1] else "../2_monitoring/data"
OUT <- if (length(args) >= 2) args[2] else "resampling/output/full_weighting_build_2026-09-28/round1_prototype_2026-10-02"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

d6 <- st_drop_geometry(readRDS("_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds"))
des <- d6[d6$pop_type == "idp", c("cluster_id", "strata_id", "MOS", "total_MOS", "clusters", "psu_probability", "selection_count")]
facts <- read_csv("resampling/output/full_weighting_build_2026-09-28/idp_cluster_psu_facts_2026-10-02.csv", show_col_types = FALSE) %>%
  select(cluster_id, net_draws = selection_count_net_of_topups)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE, col_types = cols(.default = col_character())) %>%
  filter(pop_type == "idp") %>% distinct(cluster_id, .keep_all = TRUE) %>%
  transmute(cluster_id, strata_id, adm2_pcode, ver = psu_definition_version, hh = as.numeric(households_in_cluster),
            lat = as.numeric(latitude), lon = as.numeric(longitude), uuid_hex)
strata <- read_csv("output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv", show_col_types = FALSE) %>% filter(pop_type == "idp")
gis <- read_csv("resampling/output/gis/accessible_area_lga_ward_portions.csv", show_col_types = FALSE)
acc <- gis %>% filter(pop_type == "IDP") %>% group_by(adm2_pcode) %>%
  summarise(pct = 100 * sum(pop_total[accessible_status == "Accessible"]) / sum(pop_total), .groups = "drop")
n_acc <- strata %>% select(strata_id, adm2_pcode, adm1_name, adm2_name, N_hh) %>% left_join(acc, by = "adm2_pcode") %>%
  mutate(N_acc = N_hh * coalesce(pct, 0) / 100)

# ---- Round 1 interviews (canonical is_achieved) ----
subs <- read_csv(file.path(SUBS_DIR, "real_submissions.csv"), col_types = cols(.default = col_character()))
dels <- read_csv(file.path(SUBS_DIR, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = cols(.default = col_character()))
del_uuids <- dels$uuid[dels$status %in% c("confirmed", "contested")]
iv <- subs %>% filter(interview_outcome == "completed", !is.na(matched_survey_id), matched_survey_id != "NA",
                      !(submission_uuid %in% del_uuids), pop_type == "idp") %>%
  select(submission_uuid, cluster_id = matched_cluster_id)
ach <- iv %>% count(cluster_id, name = "ach")
cl <- full %>% inner_join(ach, by = "cluster_id")
cat(sprintf("IDP Round 1 achieved interviews: %d in %d clusters (%d not matched to an IDP frame cluster)\n",
            nrow(iv), nrow(cl), sum(!iv$cluster_id %in% full$cluster_id)))

# ---- first stage ----
cl <- cl %>% left_join(des %>% select(cluster_id, MOS, total_MOS, k1 = clusters, pi_july = psu_probability, july_hits = selection_count), by = "cluster_id") %>%
  left_join(facts, by = "cluster_id")
# July-mechanism clusters drawn after 6 Aug (_supp, not in the design): supplementary formula on the July grid
grid <- readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_idp.rds")
gmos <- st_drop_geometry(grid) %>% select(uuid_hex, pop_hh)
supp_n <- cl %>% filter(ver == "hex_v1", is.na(pi_july)) %>% count(strata_id, name = "n_supp_hex")
k1T1 <- des %>% distinct(strata_id, k1s = clusters, T1 = total_MOS)
cl <- cl %>% left_join(supp_n, by = "strata_id") %>% left_join(k1T1, by = "strata_id") %>% left_join(gmos %>% rename(MOS_g = pop_hh), by = "uuid_hex") %>%
  mutate(supp_hex = ver == "hex_v1" & is.na(pi_july),
         MOS = ifelse(supp_hex, MOS_g, MOS),
         pi_july = ifelse(supp_hex, pmin(1, (k1s + n_supp_hex) * MOS_g / T1), pi_july),
         july_hits = ifelse(supp_hex, coalesce(net_draws, 1), july_hits))
cat(sprintf("July-mechanism clusters drawn after 6 Aug (supplementary formula): %d | with no July probability at all: %d\n",
            sum(cl$supp_hex), sum(cl$ver == "hex_v1" & is.na(cl$pi_july))))

# ---- second phase (post-2-Sep site draws): pool households per LGA, draws per stratum ----
sites <- readRDS("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds")
stopifnot(!anyDuplicated(sites$uuid_site))   # deduped tonight (Tangaza); refuse if duplicated again
sites <- st_transform(sites, st_crs(grid))
hexpts <- st_as_sf(full %>% filter(ver == "hex_v1", !is.na(lat)), coords = c("lon", "lat"), crs = 4326) %>% st_transform(st_crs(grid))
near <- lengths(st_is_within_distance(sites, hexpts, dist = 30)) > 0
pool <- st_drop_geometry(sites)[!near & !is.na(sites$accessible_status) & sites$accessible_status != "Inaccessible", ]
T2 <- pool %>% group_by(adm2_pcode) %>% summarise(T2 = sum(pop_hh, na.rm = TRUE), .groups = "drop")
k2 <- full %>% filter(ver == "site_v2") %>% count(strata_id, name = "k2")
cl <- cl %>% left_join(T2, by = "adm2_pcode") %>% left_join(k2, by = "strata_id") %>%
  mutate(pi_site = ifelse(!is.na(k2) & !is.na(T2) & T2 > 0, pmin(1, k2 * hh / T2), 0))

# ---- stratum type ----
kind <- cl %>% group_by(strata_id) %>% summarise(kind = if (n_distinct(ver) == 2) "mixed" else paste0(first(ver), " only"), .groups = "drop")
cl <- cl %>% left_join(kind, by = "strata_id")

# ---- cluster totals under each option ----
cl <- cl %>% mutate(
  W2 = ifelse(ver == "hex_v1", july_hits, coalesce(net_draws, 1)),
  pi3 = case_when(ver == "hex_v1" & kind == "mixed" ~ pi_july + (1 - pi_july) * pi_site,
                  ver == "site_v2" ~ pi_site,
                  TRUE ~ pi_july),
  W3 = case_when(ver == "hex_v1" & kind == "mixed" ~ hh / pi3,
                 ver == "hex_v1" ~ MOS / pi_july,
                 TRUE ~ hh / pi3))
bad <- cl %>% filter(!is.finite(W2) | !is.finite(W3) | W2 <= 0 | W3 <= 0)
cat(sprintf("clusters with no usable weight under an option (flagged, left out): %d\n", nrow(bad)))
if (nrow(bad)) print(as.data.frame(bad %>% select(cluster_id, strata_id, ver, kind, hh, MOS, pi_july, pi_site, net_draws, ach)))
cl <- cl %>% filter(is.finite(W2), is.finite(W3), W2 > 0, W3 > 0)

# ---- per-interview weights, calibrated per stratum ----
w <- iv %>% inner_join(cl %>% select(cluster_id, strata_id, ver, kind, ach, W2, W3), by = "cluster_id") %>%
  left_join(n_acc %>% select(strata_id, N_acc), by = "strata_id") %>%
  mutate(w2 = W2 / ach, w3 = W3 / ach) %>%
  group_by(strata_id) %>% mutate(w2_cal = w2 * N_acc / sum(w2), w3_cal = w3 * N_acc / sum(w3)) %>% ungroup()
kish <- function(x) length(x) * sum(x^2) / sum(x)^2
summ <- w %>% group_by(strata_id, kind) %>%
  summarise(n = n(), clusters = n_distinct(cluster_id), site_v2_interviews = sum(ver == "site_v2"),
            site_v2_weight_share_opt2 = sum(w2_cal[ver == "site_v2"]) / sum(w2_cal),
            site_v2_weight_share_opt3 = sum(w3_cal[ver == "site_v2"]) / sum(w3_cal),
            kish_opt2 = kish(w2), kish_opt3 = kish(w3), N_acc = first(N_acc), .groups = "drop") %>%
  left_join(n_acc %>% select(strata_id, State = adm1_name, LGA = adm2_name), by = "strata_id")
stopifnot(isTRUE(all.equal(w %>% group_by(strata_id) %>% summarise(s = sum(w3_cal)) %>% pull(s),
                           w %>% group_by(strata_id) %>% summarise(s = first(N_acc)) %>% pull(s))))
write_csv(w %>% select(submission_uuid, strata_id, cluster_id, psu_definition_version = ver, stratum_kind = kind, weight_option2 = w2_cal, weight_option3 = w3_cal),
          file.path(OUT, "idp_round1_weights_by_interview_BOTH_OPTIONS.csv"))
write_csv(summ, file.path(OUT, "idp_round1_weights_by_stratum_BOTH_OPTIONS.csv"))
zero <- summ %>% filter(!(N_acc > 0))
cat(sprintf("strata with zero accessible IDP households today (Dropped under the current rule; weights are all 0, left out of the medians): %d - %s\n",
            nrow(zero), paste(sprintf("%s (%d interviews)", zero$LGA, zero$n), collapse = ", ")))
for (k in c("mixed", "hex_v1 only", "site_v2 only")) {
  s <- summ %>% filter(kind == k, N_acc > 0)
  if (nrow(s)) cat(sprintf("%-12s %3d strata | Kish median opt2 %.2f / opt3 %.2f | 90th opt2 %.2f / opt3 %.2f%s\n", k, nrow(s),
                           median(s$kish_opt2), median(s$kish_opt3), quantile(s$kish_opt2, .9), quantile(s$kish_opt3, .9),
                           if (k == "mixed") sprintf(" | post-2-Sep weight share median opt2 %.2f / opt3 %.2f", median(s$site_v2_weight_share_opt2), median(s$site_v2_weight_share_opt3)) else ""))
}
cat(sprintf("interviews weighted: %d of %d | every stratum calibrated to accessible IDP households: TRUE\nwrote %s\n", nrow(w), nrow(iv), OUT))
