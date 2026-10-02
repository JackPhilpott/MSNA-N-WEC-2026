# =====================================================================================================
# MSNA N-WEC 2026 - ROUND 1 SURVEY WEIGHTS (FINAL, 2 Oct 2026)
# Built by Coordinator; every rule below is a decision Jack made (see the methodology guide for dates/quotes).
#
# One weight per Round 1 interview that is used in weighted analysis tables:
#   weight = calibrated, capped design weight = 1 / (first-stage prob x second-stage prob), then
#            (a) capped at 4x the stratum median (iterative) and (b) calibrated so each stratum sums to its
#            accessible households (the same denominator the Round 1 representativity gate uses).
#
# FIRST STAGE (selection probability of the cluster)
#   Non-IDP: min(1, (design clusters + supplementary clusters) x hex MOS / stratum total MOS), 1 in certainty
#            strata (piece 2's formula, unchanged). Hexes not in the cached grids (6 Jibia/Mashi clusters from
#            the 6 Aug NW resample, 4 Mobbar supplementary clusters from the 3 Sep Mobbar draw) take MOS and
#            total MOS from the RECORD of the draw that selected them (6 Aug design archive / draw staging).
#            Repeat draws of one physical hex (separate cluster records, same stratum + uuid_hex; all 112
#            groups verified co-located) are POOLED into one weighting unit (repeat-draw fix, Jack 1 Oct).
#   IDP (Option 3, Jack 2 Oct): July hex_v1 clusters use the 6 Aug design probability (draws after 6 Aug:
#            supplementary formula on the July grid). Mixed strata: two-phase, site-level
#            pi = pi_July + (1 - pi_July) x pi_site; post-2-Sep sites pi = pi_site. July-only strata: the
#            surveyed site stands in for its whole hex (weight from hex households / pi_July).
#            pi_site = per-batch table from Resampling when present (idp_site_v2_pi2_per_batch_2026-10-02.csv),
#            for strata graded EXACT/OK; else the single-pool approximation min(1, k2 x site hh / pool hh).
#            July sites in mixed strata use the SAME pools as their post-2-Sep neighbours, with the site added to
#            its own counterfactual pool (T2 + hh). July probabilities use the stratum's cumulative July draws.
#            (These four refinements - F1/F3/F4/F5 - and F2 below came from Resampling's independent verification.)
# SECOND STAGE (realized, every unit): interviews / households in the unit (capped at 1).
# INCLUDED: strata labelled Representative or Indicative in the Round 1 table - including strata that lost
#   accessibility after collection, at their collection-period accessible population (Jack 2 Oct).
# EXCLUDED, counted: MSNA Light interviews (Jack 2 Oct: excluded from weighted tables); Dropped strata (<20).
#
# Usage (PowerShell): Rscript build_round1_weights_FINAL_2026-10-02.R <submissions_dir> <round1_strata.csv> <out_dir>
# Read-only on every input. Writes only <out_dir>.
# =====================================================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
sf_use_s2(FALSE)
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
args <- commandArgs(trailingOnly = TRUE)
SUBS_DIR <- args[1]; R1_STRATA <- args[2]; OUT <- args[3]
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
CAP_K <- 4
chr <- cols(.default = col_character())

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", col_types = chr)
r1 <- read_csv(R1_STRATA, show_col_types = FALSE) %>%
  transmute(strata_id, State, LGA, pop = `Pop type`, label = `Round 1 label`, N_acc = `Accessible households`, basis = `Accessible-population basis`)
included <- r1$strata_id[r1$label != "Dropped"]

subs <- read_csv(file.path(SUBS_DIR, "real_submissions.csv"), col_types = chr)
dels <- read_csv(file.path(SUBS_DIR, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = chr)
del_uuids <- dels$uuid[dels$status %in% c("confirmed", "contested")]
ach <- subs %>% filter(interview_outcome == "completed", !is.na(matched_survey_id), matched_survey_id != "NA", !(submission_uuid %in% del_uuids)) %>%
  select(submission_uuid, pop_type, cluster_id = matched_cluster_id, strata_id = matched_strata_id)
cat(sprintf("Round 1 achieved interviews: %d\n", nrow(ach)))

method <- full %>% group_by(cluster_id) %>% summarise(light = any(sampling_method == "MSNA Light"), .groups = "drop")
ach <- ach %>% left_join(method, by = "cluster_id") %>% mutate(light = coalesce(light, FALSE))
excl_light <- ach %>% filter(light)
excl_dropped <- ach %>% filter(!light, !(strata_id %in% included))
use <- ach %>% filter(!light, strata_id %in% included)
cat(sprintf("excluded: MSNA Light %d | Dropped strata %d | to weight %d\n", nrow(excl_light), nrow(excl_dropped), nrow(use)))

# ------------------------------------------- NON-IDP -------------------------------------------
cl <- full %>% filter(pop_type == "non_idp", !is.na(supplementary_cluster)) %>%
  distinct(cluster_id, strata_id, adm2_pcode, uuid_hex, certainty_stratum, supplementary_cluster, households_in_cluster) %>%
  group_by(cluster_id) %>% slice(1) %>% ungroup() %>%
  mutate(supp = supplementary_cluster == "TRUE", hh = as.numeric(households_in_cluster), cert = certainty_stratum == "TRUE")
counts <- cl %>% group_by(strata_id) %>% summarise(k_design = n_distinct(cluster_id[!supp]), n_supp = n_distinct(cluster_id[supp]), .groups = "drop")
hex_live <- st_drop_geometry(readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds")) %>% select(uuid_hex, adm2_pcode, pop_hh)
hex_arch <- st_drop_geometry(readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_non_idp.rds")) %>% select(uuid_hex, adm2_pcode, pop_hh)
hex <- bind_rows(hex_live, hex_arch %>% filter(!uuid_hex %in% hex_live$uuid_hex))
tot <- hex %>% group_by(adm2_pcode) %>% summarise(T_grid = sum(pop_hh, na.rm = TRUE), .groups = "drop")
# draw records for hexes absent from the cached grids: 6 Aug design archive, then draw staging files
d6 <- st_drop_geometry(readRDS("_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds"))
rec <- d6 %>% filter(pop_type == "non_idp") %>% transmute(cluster_id, MOS_rec = MOS, T_rec = total_MOS, rec_src = "6 Aug design archive")
stg_files <- list.files("resampling/output/resample_runs", pattern = "^new_clusters\\.csv$", recursive = TRUE, full.names = TRUE)
stg <- bind_rows(lapply(stg_files, function(f) tryCatch(read_csv(f, col_types = chr) %>% select(any_of(c("cluster_id", "uuid_hex", "MOS", "total_MOS", "psu_probability"))) %>% mutate(src = f), error = function(e) NULL)))
cl <- cl %>% left_join(hex %>% select(uuid_hex, MOS = pop_hh), by = "uuid_hex") %>% left_join(tot, by = "adm2_pcode") %>% left_join(counts, by = "strata_id") %>%
  left_join(rec, by = "cluster_id")
miss <- cl %>% filter(is.na(MOS)) %>% pull(cluster_id)
stg_hit <- stg %>% filter(cluster_id %in% miss, !is.na(MOS)) %>% group_by(cluster_id) %>% slice(1) %>% ungroup() %>%
  transmute(cluster_id, MOS_stg = as.numeric(MOS), T_stg = as.numeric(total_MOS), psu_stg = as.numeric(psu_probability), stg_src = src)
cl <- cl %>% left_join(stg_hit, by = "cluster_id") %>% mutate(
  mos_basis = case_when(!is.na(MOS) ~ "cached hex grid", !is.na(MOS_rec) ~ "6 Aug design archive", !is.na(MOS_stg) ~ "draw staging record", TRUE ~ "NONE"),
  ratio = case_when(!is.na(MOS) ~ MOS / T_grid, !is.na(MOS_rec) ~ MOS_rec / T_rec, !is.na(MOS_stg) ~ MOS_stg / T_stg),
  # F2 (Resampling verification, 2 Oct): a staging record's total_MOS is that draw's OWN pool, drawn with its
  # own k - so for these clusters use the record's own psu_probability, not the stratum's cumulative k x MOS/T.
  # (6 Aug archive records keep the formula: their T equals the LGA grid total.)
  psu = case_when(cert ~ 1, mos_basis == "draw staging record" ~ psu_stg, TRUE ~ pmin(1, (k_design + n_supp) * ratio)))
cat("Non-IDP first-stage basis:", paste(names(table(cl$mos_basis)), table(cl$mos_basis), collapse = " | "), "\n")
ni <- use %>% filter(pop_type == "non_idp") %>% inner_join(cl %>% select(cluster_id, uuid_hex, psu, hh, mos_basis), by = "cluster_id")
stopifnot(all(!is.na(ni$psu)))
ni_units <- ni %>% group_by(strata_id, uuid_hex) %>%
  summarise(n_unit = n(), records = n_distinct(cluster_id), psu = first(psu), hh = max(hh), .groups = "drop") %>%
  mutate(ssu = pmin(1, n_unit / hh), W_unit = 1 / (psu * ssu) * n_unit)
ni <- ni %>% left_join(ni_units %>% select(strata_id, uuid_hex, psu_u = psu, ssu_u = ssu, W_unit, n_unit), by = c("strata_id", "uuid_hex")) %>%
  mutate(base_weight = W_unit / n_unit, unit_id = paste(strata_id, uuid_hex, sep = "|"))

# --------------------------------------------- IDP ---------------------------------------------
d6i <- d6 %>% filter(pop_type == "idp") %>% transmute(cluster_id, MOS_july = MOS, T1 = total_MOS, k1 = clusters, pi_july = psu_probability)
facts <- read_csv("resampling/output/full_weighting_build_2026-09-28/idp_cluster_psu_facts_2026-10-02.csv", show_col_types = FALSE) %>%
  select(cluster_id, net_draws = selection_count_net_of_topups)
icl <- full %>% filter(pop_type == "idp") %>% distinct(cluster_id, .keep_all = TRUE) %>%
  transmute(cluster_id, strata_id, adm2_pcode, ver = psu_definition_version, hh = as.numeric(households_in_cluster), uuid_hex,
            lat = as.numeric(latitude), lon = as.numeric(longitude)) %>%
  left_join(d6i, by = "cluster_id") %>% left_join(facts, by = "cluster_id")
grid <- readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_idp.rds")
gm <- st_drop_geometry(grid) %>% select(uuid_hex, MOS_g = pop_hh)
k1T1 <- d6i %>% left_join(full %>% distinct(cluster_id, strata_id), by = "cluster_id") %>% distinct(strata_id, k1s = k1, T1s = T1)
supp_n <- icl %>% filter(ver == "hex_v1", is.na(pi_july)) %>% count(strata_id, name = "n_supp_hex")
icl <- icl %>% left_join(gm, by = "uuid_hex") %>% left_join(k1T1, by = "strata_id") %>% left_join(supp_n, by = "strata_id") %>%
  mutate(supp_hex = ver == "hex_v1" & is.na(pi_july),
         MOS_july = ifelse(supp_hex, MOS_g, MOS_july),
         # F4 (Resampling verification, 2 Oct): every July-mechanism cluster in a stratum uses the stratum's
         # CUMULATIVE July-mechanism draws (design + post-6-Aug hex draws), as Non-IDP does; design probability 1 stays 1
         pi_july = ifelse(!supp_hex & pi_july >= 1, 1, pmin(1, (k1s + coalesce(n_supp_hex, 0L)) * MOS_july / T1s)))
kind <- icl %>% filter(cluster_id %in% use$cluster_id) %>% group_by(strata_id) %>%
  summarise(kind = if (n_distinct(ver) == 2) "mixed" else paste0(first(ver), " only"), .groups = "drop")
icl <- icl %>% left_join(kind, by = "strata_id")
PI2 <- "resampling/output/full_weighting_build_2026-09-28/idp_site_v2_pi2_per_batch_2026-10-02.csv"
if (file.exists(PI2)) {
  # Per-batch probabilities only for strata Resampling graded EXACT or OK (self-check passed); strata graded
  # POOL BASIS UNRELIABLE or AMBIGUOUS use the single-pool fallback for ALL their post-2-Sep clusters, so each
  # stratum uses one method (calibration is within stratum, so that is what keeps weights consistent).
  rel <- read_csv(sub("_per_batch_", "_strata_reliability_", PI2), show_col_types = FALSE)
  good <- rel$strata_id[grepl("^(EXACT|OK)", rel$reliability)]
  pi2 <- read_csv(PI2, show_col_types = FALSE) %>% filter(strata_id %in% good, !is.na(pi2)) %>%
    group_by(cluster_id) %>% summarise(pi_site = first(pi2), .groups = "drop")
  icl <- icl %>% left_join(pi2, by = "cluster_id") %>%
    left_join(rel %>% select(strata_id, reliability), by = "strata_id") %>%
    mutate(pi_site_basis = ifelse(is.na(pi_site), NA, paste0("per-batch, nearest preserved snapshot (", sub(" .*", "", reliability), ")")))
  cat(sprintf("IDP post-2-Sep probabilities: per-batch table found; used for %d strata graded EXACT/OK, fallback for the other %d\n",
              length(good), nrow(rel) - length(good)))
} else {
  icl$pi_site <- NA_real_; icl$pi_site_basis <- NA_character_
  cat("IDP post-2-Sep probabilities: per-batch table NOT found - single-pool approximation\n")
}
# fallback single-pool approximation (also used for any cluster the per-batch table does not cover)
sites <- readRDS("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds")
stopifnot(!anyDuplicated(sites$uuid_site))
sites <- st_transform(sites, st_crs(grid))
hexpts <- st_as_sf(icl %>% filter(ver == "hex_v1", !is.na(lat)), coords = c("lon", "lat"), crs = 4326) %>% st_transform(st_crs(grid))
near <- lengths(st_is_within_distance(sites, hexpts, dist = 30)) > 0
pool <- st_drop_geometry(sites)[!near & !is.na(sites$accessible_status) & sites$accessible_status != "Inaccessible", ]
T2 <- pool %>% group_by(adm2_pcode) %>% summarise(T2 = sum(pop_hh, na.rm = TRUE), .groups = "drop")
# LGAs closed after collection (empty pool in today's frame): pool from the 21 Sep pre-refresh snapshot,
# the nearest preserved state while they were open (Resampling's snapshot mapping, 2 Oct)
s0921 <- readRDS("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-21.rds.bak")
stopifnot(!anyDuplicated(s0921$uuid_site))
s0921 <- st_transform(s0921, st_crs(grid))
near0921 <- lengths(st_is_within_distance(s0921, hexpts, dist = 30)) > 0
T2_0921 <- st_drop_geometry(s0921)[!near0921 & !is.na(s0921$accessible_status) & s0921$accessible_status != "Inaccessible", ] %>%
  group_by(adm2_pcode) %>% summarise(T2_0921 = sum(pop_hh, na.rm = TRUE), .groups = "drop")
k2 <- icl %>% filter(ver == "site_v2") %>% count(strata_id, name = "k2")
icl <- icl %>% left_join(T2, by = "adm2_pcode") %>% left_join(T2_0921, by = "adm2_pcode") %>% left_join(k2, by = "strata_id") %>%
  mutate(use_0921 = is.na(pi_site) & ver == "site_v2" & (is.na(T2) | T2 <= 0) & !is.na(T2_0921) & T2_0921 > 0,
         pi_site_basis = case_when(!is.na(pi_site) ~ pi_site_basis,
                                   ver == "site_v2" & use_0921 ~ "single-pool approximation (21 Sep snapshot; LGA closed since)",
                                   ver == "site_v2" ~ "single-pool approximation (current frame)", TRUE ~ pi_site_basis),
         pi_site = case_when(!is.na(pi_site) ~ pi_site,
                             use_0921 ~ pmin(1, k2 * hh / T2_0921),
                             !is.na(k2) & !is.na(T2) & T2 > 0 ~ pmin(1, k2 * hh / T2), TRUE ~ NA_real_))
# F1 + F5 (Resampling verification, 2 Oct): a July site's phase-2 term in a MIXED stratum is the probability it
# would have been drawn post-2-Sep had July not selected it - so (F1) it uses the SAME pools as its post-2-Sep
# neighbours (per-batch in EXACT/OK strata, single pool otherwise; 21 Sep snapshot where the LGA closed since),
# and (F5) that counterfactual pool includes the site itself (T2 + its households): the real pools excluded it
# only because July had already fielded it.
pb <- if (file.exists(PI2)) read_csv(sub("_per_batch_", "_batches_", PI2), show_col_types = FALSE) %>%
  filter(strata_id %in% good) %>% transmute(strata_id, k_b = as.numeric(k_b), T2_b = as.numeric(T2_b)) else
  tibble(strata_id = character(), k_b = numeric(), T2_b = numeric())
hex_mixed <- icl %>% filter(ver == "hex_v1", kind == "mixed") %>% select(cluster_id, strata_id, hh)
pi_site_hex_pb <- hex_mixed %>% inner_join(pb, by = "strata_id", relationship = "many-to-many") %>%
  group_by(cluster_id) %>% summarise(pi_site_hex = 1 - prod(1 - pmin(1, k_b * hh / (T2_b + hh))), .groups = "drop")
icl <- icl %>% left_join(pi_site_hex_pb, by = "cluster_id") %>% mutate(
  T2_fb = ifelse(!is.na(T2) & T2 > 0, T2, T2_0921),
  pi_site_hex = case_when(ver != "hex_v1" | kind != "mixed" ~ NA_real_,
                          !is.na(pi_site_hex) ~ pi_site_hex,
                          !is.na(k2) & !is.na(T2_fb) & T2_fb > 0 ~ pmin(1, k2 * hh / (T2_fb + hh)),
                          TRUE ~ NA_real_))
stopifnot("every July site in a mixed stratum needs a phase-2 probability (F1)" = all(!is.na(icl$pi_site_hex[icl$ver == "hex_v1" & icl$kind %in% "mixed"])))
n_by_cluster <- use %>% filter(pop_type == "idp") %>% count(cluster_id, name = "n_unit")
icl <- icl %>% left_join(n_by_cluster, by = "cluster_id") %>% mutate(
  pi = case_when(ver == "hex_v1" & kind == "mixed" ~ pi_july + (1 - pi_july) * pi_site_hex,
                 ver == "site_v2" ~ pi_site, TRUE ~ pi_july),
  # F3 (Resampling verification, 2 Oct): second stage capped at 1, as for Non-IDP - a cluster with more interviews
  # than its recorded households stands for its interviews (each interview weight = 1/pi), not for fewer households
  W_total = case_when(ver == "hex_v1" & kind == "mixed" ~ pmax(hh, coalesce(n_unit, 0L)) / pi,
                      ver == "hex_v1" ~ pmax(MOS_july, coalesce(n_unit, 0L)) / pi_july,
                      TRUE ~ pmax(hh, coalesce(n_unit, 0L)) / pi))
idp <- use %>% filter(pop_type == "idp") %>% inner_join(icl %>% select(cluster_id, ver, kind, pi, W_total, pi_site_basis), by = "cluster_id")
noweight <- idp %>% filter(!is.finite(W_total) | W_total <= 0)
if (nrow(noweight)) { cat("IDP interviews with no usable first stage (STOP - investigate):\n"); print(noweight %>% count(strata_id, cluster_id, pi_site_basis)); stop("unweighted IDP interviews") }
idp <- idp %>% add_count(cluster_id, name = "n_unit") %>% mutate(base_weight = W_total / n_unit, unit_id = cluster_id)

# --------------------------------- cap 4x median + calibrate ---------------------------------
allw <- bind_rows(ni %>% transmute(submission_uuid, strata_id, pop_type, cluster_id, unit_id, base_weight, first_stage = psu_u, basis_note = mos_basis),
                  idp %>% transmute(submission_uuid, strata_id, pop_type, cluster_id, unit_id, base_weight, first_stage = pi, basis_note = paste(ver, kind, coalesce(pi_site_basis, ""))))
stopifnot(nrow(allw) == nrow(use), !anyDuplicated(allw$submission_uuid))
cap_cal <- function(w, total, k = CAP_K, iters = 100) {
  w <- w * total / sum(w)
  for (i in seq_len(iters)) { cap <- k * median(w); if (all(w <= cap + 1e-9)) break; w <- pmin(w, cap); w <- w * total / sum(w) }
  w
}
allw <- allw %>% left_join(r1 %>% select(strata_id, N_acc, basis), by = "strata_id") %>% group_by(strata_id) %>%
  mutate(weight_uncapped = base_weight * N_acc / sum(base_weight), weight = cap_cal(base_weight, first(N_acc)),
         capped = weight < weight_uncapped - 1e-9) %>% ungroup()
kish <- function(x) length(x) * sum(x^2) / sum(x)^2
by_s <- allw %>% group_by(strata_id, pop_type) %>% summarise(n = n(), units = n_distinct(unit_id), N_acc = first(N_acc), sum_weight = sum(weight),
                                                            kish_uncapped = kish(weight_uncapped), kish_final = kish(weight), n_capped = sum(capped),
                                                            max_over_median = max(weight) / median(weight), basis = first(basis), .groups = "drop") %>%
  left_join(r1 %>% select(strata_id, State, LGA, label), by = "strata_id")
stopifnot(isTRUE(all.equal(by_s$sum_weight, by_s$N_acc)), all(by_s$max_over_median <= CAP_K + 1e-6))

write_csv(allw %>% select(submission_uuid, strata_id, pop_type, cluster_id, weighting_unit = unit_id, first_stage_probability = first_stage,
                          base_weight, weight_uncapped, weight, capped, accessible_population_basis = basis, first_stage_basis = basis_note),
          file.path(OUT, "ROUND1_WEIGHTS_FINAL_2026-10-02.csv"))
write_csv(by_s %>% select(State, LGA, pop_type, strata_id, label, n, units, N_acc, sum_weight, kish_uncapped, kish_final, n_capped, basis),
          file.path(OUT, "ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv"))
write_csv(bind_rows(excl_light %>% mutate(reason = "MSNA Light - excluded from weighted tables (Jack 2 Oct)"),
                    excl_dropped %>% mutate(reason = "stratum Dropped in Round 1 (<20 achieved)")) %>% select(submission_uuid, strata_id, cluster_id, reason),
          file.path(OUT, "ROUND1_UNWEIGHTED_interviews_2026-10-02.csv"))
cat(sprintf("\nweighted %d interviews in %d strata (%d Non-IDP, %d IDP) | calibration exact: TRUE | every stratum max weight <= %dx median: TRUE\n",
            nrow(allw), nrow(by_s), sum(allw$pop_type == "non_idp"), sum(allw$pop_type == "idp"), CAP_K))
cat(sprintf("Kish median uncapped %.2f -> final %.2f | 90th %.2f -> %.2f | strata where the cap binds: %d\n",
            median(by_s$kish_uncapped), median(by_s$kish_final), quantile(by_s$kish_uncapped, .9), quantile(by_s$kish_final, .9), sum(by_s$n_capped > 0)))
cat(sprintf("unweighted (listed in ROUND1_UNWEIGHTED_interviews): %d = %d MSNA Light + %d in Dropped strata\n", nrow(excl_light) + nrow(excl_dropped), nrow(excl_light), nrow(excl_dropped)))
cat(sprintf("check: weighted + unweighted = %d = Round 1 achieved %d\n", nrow(allw) + nrow(excl_light) + nrow(excl_dropped), nrow(ach)))
