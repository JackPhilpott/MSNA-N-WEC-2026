# ==============================================================================
# 2026-10-02 READ-ONLY (Resampling, at Coordinator's request): independent check of the
# FINAL Round 1 weights - build_round1_weights_FINAL_2026-10-02.R as committed in b3738d0,
# i.e. AFTER the Coordinator adopted Resampling's verification fixes F1-F5.
# Recomputes every weight from the raw records (snapshot v2 submissions + overlay,
# round1_strata, 6 Aug design archive, hex grids, FULL, draw-staging records, site frame +
# 21 Sep snapshot, per-batch pi2 tables) under the final rules and compares with the
# build's outputs. Writes nothing; prints PASS/FAIL per check and a one-line verdict.
# The pre-rebuild version (which wrote the F1-F5 suggestion CSVs) is kept for provenance
# next to those CSVs in round1_FINAL_verification_2026-10-02/.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
sf_use_s2(FALSE)
options(width = 230, dplyr.summarise.inform = FALSE)
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
chr <- cols(.default = col_character())
say <- function(...) cat(sprintf(...), "\n", sep = "")
show <- function(x, n = 40) print(as.data.frame(head(x, n)), row.names = FALSE)
fails <- character(); n_checks <- 0
check <- function(ok, label) {
  ok <- isTRUE(ok); n_checks <<- n_checks + 1
  if (!ok) fails <<- c(fails, label)
  say("  [%s] %s", if (ok) "PASS" else "FAIL", label)
}
cap_cal <- function(w, total, k = 4, iters = 100) {
  w <- w * total / sum(w)
  for (i in seq_len(iters)) { cap <- k * median(w); if (all(w <= cap + 1e-9)) break; w <- pmin(w, cap); w <- w * total / sum(w) }
  w
}
B <- "resampling/output/full_weighting_build_2026-09-28/"
# 2026-10-04: optional arguments so the same checks can run on a candidate rebuild (defaults = the FINAL weights):
#   --weights-dir DIR  --snapshot-dir DIR  --strata-csv FILE  --expect-md5 "<subs8>,<overlay8>" | none
.args <- commandArgs(trailingOnly = TRUE)
argval <- function(flag, default) { i <- match(flag, .args); if (is.na(i) || i == length(.args)) default else .args[i + 1] }
WDIR <- argval("--weights-dir", paste0(B, "round1_FINAL_2026-10-02"))
SNAP <- argval("--snapshot-dir", "resampling/output/round1_final_snapshot_v2_2026-10-02")
R1_CSV <- argval("--strata-csv", "resampling/output/round1_representativity_prototype_2026-10-02/round1_strata.csv")
EXPECT_MD5 <- argval("--expect-md5", "24db61ae,2636cefa")
say("weights %s | snapshot %s | strata %s", WDIR, SNAP, R1_CSV)

W <- read_csv(file.path(WDIR, "ROUND1_WEIGHTS_FINAL_2026-10-02.csv"), show_col_types = FALSE)
U <- read_csv(file.path(WDIR, "ROUND1_UNWEIGHTED_interviews_2026-10-02.csv"), show_col_types = FALSE)
BS <- read_csv(file.path(WDIR, "ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv"), show_col_types = FALSE)
r1 <- read_csv(R1_CSV, show_col_types = FALSE) %>%
  transmute(strata_id, State, LGA, label = `Round 1 label`, N_acc = `Accessible households`)
subs <- read_csv(file.path(SNAP, "real_submissions.csv"), col_types = chr)
dels <- read_csv(file.path(SNAP, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = chr)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", col_types = chr)
d6 <- st_drop_geometry(readRDS("_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds"))
p2 <- read_csv(paste0(B, "nonidp_realized_psu_probability_2026-09-28.csv"), show_col_types = FALSE)
pi2 <- read_csv(paste0(B, "idp_site_v2_pi2_per_batch_2026-10-02.csv"), show_col_types = FALSE)
rel <- read_csv(paste0(B, "idp_site_v2_pi2_strata_reliability_2026-10-02.csv"), show_col_types = FALSE)
pb <- read_csv(paste0(B, "idp_site_v2_pi2_batches_2026-10-02.csv"), show_col_types = FALSE)
sugg <- read_csv(paste0(B, "round1_FINAL_verification_2026-10-02/idp_hex_v1_mixed_strata_suggested_probabilities_2026-10-02.csv"), show_col_types = FALSE)

md5 <- substr(unname(tools::md5sum(c(file.path(SNAP, "real_submissions.csv"), file.path(SNAP, "CONFIRMED_DELETIONS_OVERLAY.csv")))), 1, 8)
say("== inputs ==")
if (EXPECT_MD5 != "none") {
  check(identical(md5, strsplit(EXPECT_MD5, ",")[[1]]), sprintf("submissions are the expected snapshot (real_submissions %s, overlay %s)", md5[1], md5[2]))
} else say("  inputs: real_submissions %s, overlay %s (no expected md5 given)", md5[1], md5[2])
live <- full %>% group_by(cluster_id) %>% summarise(
  pop_type = first(pop_type), strata_id = first(strata_id), adm2_pcode = first(adm2_pcode), uuid_hex = first(uuid_hex),
  n_hex = n_distinct(uuid_hex), ver = first(psu_definition_version), hh = as.numeric(first(households_in_cluster)),
  n_hh_vals = n_distinct(households_in_cluster), supp = first(supplementary_cluster), cert = first(certainty_stratum),
  lat = as.numeric(first(latitude)), lon = as.numeric(first(longitude)))
check(all(live$n_hex == 1) && all(live$n_hh_vals == 1), sprintf("every live cluster (%d) has one hex/site and one household count in FULL", nrow(live)))

# ------------------------------------------------------------------------------
say("\n== 0. coverage (b) and calibration/cap (c) ==")
del_ids <- dels$uuid[dels$status %in% c("confirmed", "contested")]
ach <- subs %>% filter(interview_outcome == "completed", !is.na(matched_survey_id), matched_survey_id != "NA", !(submission_uuid %in% del_ids))
listed <- c(W$submission_uuid, U$submission_uuid)
say("achieved (independent) %d | weighted %d | unweighted %d", nrow(ach), nrow(W), nrow(U))
check(!anyDuplicated(listed), "no interview listed twice")
check(length(listed) == nrow(ach) && setequal(listed, ach$submission_uuid), "weighted + unweighted = every achieved interview, exactly once")
mm <- W %>% inner_join(ach %>% select(submission_uuid, ms = matched_strata_id, mc = matched_cluster_id, matched_survey_id), by = "submission_uuid")
check(nrow(mm) == nrow(W) && all(mm$strata_id == mm$ms) && all(mm$cluster_id == mm$mc), "weighted rows carry the submission's own matched stratum and cluster")
inc <- r1$strata_id[r1$label != "Dropped"]
check(all(W$strata_id %in% inc), "no weighted interview in a Dropped stratum")
own <- full %>% distinct(survey_id, .keep_all = TRUE) %>% select(survey_id, sampling_method)
Uo <- U %>% left_join(ach %>% select(submission_uuid, matched_survey_id), by = "submission_uuid") %>% left_join(own, by = c("matched_survey_id" = "survey_id"))
Wo <- mm %>% left_join(own, by = c("matched_survey_id" = "survey_id"))
isL <- grepl("^MSNA Light", Uo$reason); isD <- grepl("^stratum Dropped", Uo$reason)
check(all(isL | isD), "every unweighted interview has one of the two documented reasons")
check(all(Uo$sampling_method[isL] == "MSNA Light"), sprintf("all %d Light exclusions are MSNA Light at interview level", sum(isL)))
# IDP interviews are matched to listing ids (e.g. idp_NG002020_6_L24, _L1_b) that are never FULL survey_ids,
# so their method is read from their cluster's rows instead (a cluster with any Light row would count against it)
cl_light <- full %>% group_by(cluster_id) %>% summarise(any_light = any(sampling_method == "MSNA Light"))
Wo <- Wo %>% left_join(cl_light, by = "cluster_id")
unres <- is.na(Wo$sampling_method)
check(all(Wo$pop_type[unres] == "idp") && all(Wo$sampling_method[!unres] != "MSNA Light") && !any(Wo$any_light[unres]),
      sprintf("no weighted interview is MSNA Light (%d by their own frame row, %d IDP listing-matched by their cluster's rows)", sum(!unres), sum(unres)))
check(all(!Uo$strata_id[isD] %in% inc), sprintf("all %d 'Dropped' exclusions are in Dropped strata", sum(isD)))
nw <- setdiff(inc, unique(W$strata_id))
allL <- vapply(nw, function(s) sum(ach$matched_strata_id == s) == sum(Uo$strata_id == s & isL), logical(1))
check(all(allL), sprintf("included strata without weights are entirely MSNA Light (%s)", paste(r1$LGA[match(nw, r1$strata_id)], collapse = ", ")))
cal <- W %>% left_join(r1 %>% select(strata_id, N_acc), by = "strata_id") %>% group_by(strata_id) %>%
  mutate(w_re = cap_cal(base_weight, first(N_acc))) %>%
  summarise(n = n(), N_acc = first(N_acc), s = sum(weight), mx_md = max(weight) / median(weight), bad = sum(!(weight > 0)), dev = max(abs(w_re / weight - 1)))
check(all(abs(cal$s / cal$N_acc - 1) < 1e-9), sprintf("all %d strata sum to their accessible households", nrow(cal)))
check(all(cal$mx_md <= 4 + 1e-6), sprintf("max weight <= 4x the stratum median everywhere (max %.6f)", max(cal$mx_md)))
check(sum(cal$bad) == 0, "no zero, negative or missing weights")
check(max(cal$dev) < 1e-9, "final weight = cap + calibration of base_weight, recomputed independently")
bs <- BS[match(cal$strata_id, BS$strata_id), ]
check(nrow(BS) == nrow(cal) && all(bs$n == cal$n) && all(abs(bs$sum_weight - cal$s) < 1e-6), "by-stratum file agrees with the interview file")

# ------------------------------------------------------------------------------
say("\n== 1. id-only joins to historical records (cluster ids get reused) ==")
j6 <- live %>% inner_join(d6 %>% transmute(cluster_id, hex6 = uuid_hex), by = "cluster_id")
check(all(j6$uuid_hex == j6$hex6), sprintf("all %d live ids found in the 6 Aug archive point at the same hex", nrow(j6)))
stg_files <- list.files("resampling/output/resample_runs", pattern = "^new_clusters\\.csv$", recursive = TRUE, full.names = TRUE)
hl <- st_drop_geometry(readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds")) %>% select(uuid_hex, adm2_pcode, pop_hh)
ha <- st_drop_geometry(readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_non_idp.rds")) %>% select(uuid_hex, adm2_pcode, pop_hh)
mos <- bind_rows(hl, ha %>% filter(!uuid_hex %in% hl$uuid_hex))
wn_ids <- unique(W$cluster_id[W$pop_type == "non_idp"])
rec_ids <- live$cluster_id[live$cluster_id %in% wn_ids & !live$uuid_hex %in% mos$uuid_hex & !live$cluster_id %in% d6$cluster_id]
stg <- bind_rows(lapply(stg_files, function(f) tryCatch(read_csv(f, col_types = chr) %>% filter(cluster_id %in% rec_ids) %>%
  select(any_of(c("cluster_id", "uuid_hex", "MOS", "total_MOS", "clusters", "psu_probability"))) %>% mutate(src = f), error = function(e) NULL)))
stg <- stg %>% left_join(live %>% select(cluster_id, live_hex = uuid_hex), by = "cluster_id") %>%
  group_by(cluster_id) %>% mutate(first_with_mos = row_number() == which(!is.na(MOS))[1]) %>% ungroup()
stg1 <- stg %>% filter(first_with_mos)
check(length(rec_ids) == nrow(stg1) && all(stg1$uuid_hex == stg1$live_hex),
      sprintf("the %d staging-record clusters each have a staging row on the same hex", length(rec_ids)))

# ------------------------------------------------------------------------------
say("\n== 2. Non-IDP: first stage + base weight under the final rules ==")
say("hex grids: live %d hexes | archived-only %d", nrow(hl), nrow(mos) - nrow(hl))
ncl <- live %>% filter(pop_type == "non_idp")
cnt <- ncl %>% filter(!is.na(supp)) %>% group_by(strata_id) %>% summarise(k_d = sum(supp == "FALSE"), n_s = sum(supp == "TRUE"))
rec6 <- d6 %>% filter(pop_type == "non_idp") %>% transmute(cluster_id, MOS_rec = MOS, T_rec = total_MOS)
Tu <- mos %>% group_by(adm2_pcode) %>% summarise(T = sum(pop_hh, na.rm = TRUE))
wn <- W %>% filter(pop_type == "non_idp")
hand <- wn %>% group_by(cluster_id, strata_id) %>% summarise(fsp = first(first_stage_probability), n_fsp = n_distinct(first_stage_probability), basis = first(first_stage_basis), .groups = "drop") %>%
  left_join(ncl %>% select(cluster_id, adm2_pcode, uuid_hex, cert, hh), by = "cluster_id") %>% left_join(cnt, by = "strata_id") %>%
  left_join(mos %>% select(uuid_hex, MOS = pop_hh), by = "uuid_hex") %>% left_join(Tu, by = "adm2_pcode") %>% left_join(rec6, by = "cluster_id") %>%
  left_join(stg1 %>% transmute(cluster_id, psu_rec = as.numeric(psu_probability), batch_k = clusters), by = "cluster_id") %>%
  mutate(psu_hand = case_when(cert == "TRUE" ~ 1,
                              !is.na(MOS) ~ pmin(1, (k_d + n_s) * MOS / T),
                              !is.na(MOS_rec) ~ pmin(1, (k_d + n_s) * MOS_rec / T_rec),
                              TRUE ~ psu_rec))
check(all(hand$n_fsp == 1) && all(abs(hand$fsp - hand$psu_hand) < 1e-9),
      sprintf("NI first-stage probability = rule, all %d weighted clusters (incl. F2 staging records)", nrow(hand)))
show(hand %>% filter(is.na(MOS)) %>% transmute(cluster_id, basis, k = k_d + n_s, MOS = coalesce(MOS_rec, NA_real_), T_rec, batch_k, psu_rec, psu_hand, fsp))
u2 <- wn %>% left_join(hand %>% select(cluster_id, psu_hand, hh), by = "cluster_id") %>% group_by(weighting_unit) %>%
  mutate(n_unit = n(), hh_u = max(hh), records = n_distinct(cluster_id), psu_u = first(psu_hand), psu_spread = max(psu_hand) - min(psu_hand),
         base_hand = 1 / (psu_u * pmin(1, n_unit / hh_u))) %>% ungroup()
check(all(u2$psu_spread < 1e-12), sprintf("pooled repeat-draw units (%d) have one probability across their records", n_distinct(u2$weighting_unit[u2$records > 1])))
check(all(abs(u2$base_weight / u2$base_hand - 1) < 1e-9), sprintf("NI base weight = 1/(psu x min(1, n/hh)) per unit, all %d interviews", nrow(u2)))
cmpp <- hand %>% left_join(p2 %>% select(cluster_id, p2 = psu_probability, k2p = clusters_design, n2p = n_supplementary), by = "cluster_id") %>%
  mutate(why = case_when(is.na(p2) ~ "not in piece 2 (records-only or drawn after 28 Sep)", abs(fsp / p2 - 1) < 1e-6 ~ "same as piece 2",
                         (k_d + n_s) != (k2p + n2p) ~ "k changed since 28 Sep", TRUE ~ "OTHER - investigate"))
say("vs piece 2 (28 Sep):"); show(cmpp %>% count(why, name = "clusters"))
check(!any(cmpp$why == "OTHER - investigate"), "every difference from piece 2 is explained")

# ------------------------------------------------------------------------------
say("\n== 3. IDP: first stage + base weight under the final rules (F1, F3, F4, F5) ==")
d6i <- d6 %>% filter(pop_type == "idp") %>% transmute(cluster_id, s6 = strata_id, k1 = clusters, T1 = total_MOS, MOS6 = MOS, pi6 = psu_probability)
kT <- d6i %>% group_by(strata_id = s6) %>% summarise(k1s = first(k1), T1s = first(T1), nk = n_distinct(k1), nT = n_distinct(T1))
check(all(kT$nk == 1 & kT$nT == 1), "6 Aug design: one (draw count, total MOS) per IDP stratum")
gi <- st_drop_geometry(readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_idp.rds")) %>% select(uuid_hex, MOS_g = pop_hh)
icl <- live %>% filter(pop_type == "idp") %>% left_join(d6i, by = "cluster_id") %>% left_join(kT %>% select(strata_id, k1s, T1s), by = "strata_id") %>%
  left_join(gi, by = "uuid_hex") %>% mutate(july = ver == "hex_v1" & !is.na(pi6), suppx = ver == "hex_v1" & is.na(pi6)) %>%
  group_by(strata_id) %>% mutate(n_suppx = sum(suppx)) %>% ungroup()
jc <- icl %>% filter(july, pi6 < 1)
check(all(abs(jc$pi6 - jc$k1s * jc$MOS6 / jc$T1s) < 1e-9), sprintf("6 Aug design probability = k x MOS / T for all %d July clusters below certainty", nrow(jc)))
# F4: cumulative July-mechanism draws, derived from the design's own probability (independent of the build's formula path)
icl <- icl %>% mutate(MOS_j = ifelse(july, MOS6, MOS_g),
                      pi_hex = case_when(july & pi6 >= 1 ~ 1, july ~ pmin(1, pi6 * (k1s + n_suppx) / k1s),
                                         suppx ~ pmin(1, (k1s + n_suppx) * MOS_g / T1s), TRUE ~ NA_real_))
wi <- W %>% filter(pop_type == "idp") %>% group_by(cluster_id) %>%
  summarise(n_w = n(), fsp = first(first_stage_probability), base = first(base_weight), nb = n_distinct(base_weight), nf = n_distinct(first_stage_probability))
check(all(wi$nb == 1 & wi$nf == 1), "IDP: one probability and one base weight per cluster")
w <- icl %>% inner_join(wi, by = "cluster_id")
kind <- w %>% group_by(strata_id) %>% summarise(kind = if (n_distinct(ver) == 2) "mixed" else paste0(first(ver), " only"))
w <- w %>% left_join(kind, by = "strata_id")
# phase-2 pools: current site frame and the 21 Sep snapshot, minus sites within 30 m of any hex_v1 point
grid_crs <- st_crs(readRDS("_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_idp.rds"))
hexpts <- st_as_sf(icl %>% filter(ver == "hex_v1", !is.na(lat)), coords = c("lon", "lat"), crs = 4326) %>% st_transform(grid_crs)
pool_T <- function(path, name) {
  s <- st_transform(readRDS(path), grid_crs)
  stopifnot(!anyDuplicated(s$uuid_site))
  near <- lengths(st_is_within_distance(s, hexpts, dist = 30)) > 0
  st_drop_geometry(s)[!near & !is.na(s$accessible_status) & s$accessible_status != "Inaccessible", ] %>%
    group_by(adm2_pcode) %>% summarise(!!name := sum(pop_hh, na.rm = TRUE))
}
T2 <- pool_T("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds", "T2")
T2s <- pool_T("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-21.rds.bak", "T2_0921")
k2 <- icl %>% filter(ver == "site_v2") %>% count(strata_id, name = "k2")
good <- rel$strata_id[grepl("^(EXACT|OK)", rel$reliability)]
pbg <- pb %>% filter(strata_id %in% good)
say("per-batch pool rows in EXACT/OK strata: %d (missing k_b/T2_b: %d)", nrow(pbg), sum(is.na(pbg$k_b) | is.na(pbg$T2_b)))
per_batch_self <- function(sid, h) { bb <- pbg[pbg$strata_id == sid, ]; if (!nrow(bb)) NA_real_ else 1 - prod(1 - pmin(1, bb$k_b * h / (bb$T2_b + h))) }
p2t <- pi2 %>% filter(strata_id %in% good, !is.na(pi2)) %>% group_by(cluster_id) %>% summarise(pi2 = first(pi2))
w <- w %>% left_join(T2, by = "adm2_pcode") %>% left_join(T2s, by = "adm2_pcode") %>% left_join(k2, by = "strata_id") %>% left_join(p2t, by = "cluster_id") %>%
  mutate(T2_fb = ifelse(!is.na(T2) & T2 > 0, T2, T2_0921),
         pis_v2 = case_when(!is.na(pi2) ~ pi2, !is.na(T2) & T2 > 0 ~ pmin(1, k2 * hh / T2), !is.na(T2_0921) & T2_0921 > 0 ~ pmin(1, k2 * hh / T2_0921)),
         v2_basis = case_when(!is.na(pi2) ~ "per-batch (EXACT/OK)", !is.na(T2) & T2 > 0 ~ "single pool, current frame", TRUE ~ "single pool, 21 Sep snapshot"))
w$pis_hex_pb <- mapply(per_batch_self, w$strata_id, w$hh)
w <- w %>% mutate(
  pis_hex = ifelse(strata_id %in% good & !is.na(pis_hex_pb), pis_hex_pb, pmin(1, k2 * hh / (T2_fb + hh))),
  group = case_when(ver == "site_v2" ~ paste("site_v2,", v2_basis), kind == "mixed" & july ~ "July site, mixed stratum",
                    kind == "mixed" ~ "post-6-Aug hex, mixed stratum", july ~ "July site, July-only stratum", TRUE ~ "post-6-Aug hex, July-only stratum"),
  pi_exp = case_when(ver == "site_v2" ~ pis_v2, kind == "mixed" ~ pi_hex + (1 - pi_hex) * pis_hex, TRUE ~ pi_hex),
  size = ifelse(ver == "hex_v1" & kind != "mixed", MOS_j, hh),
  base_exp = pmax(size, n_w) / pi_exp / n_w)
res <- w %>% group_by(group) %>% summarise(clusters = n(), interviews = sum(n_w), prob_match = sum(abs(fsp - pi_exp) < 1e-9, na.rm = TRUE),
                                           base_match = sum(abs(base / base_exp - 1) < 1e-9, na.rm = TRUE))
show(res)
check(all(abs(w$fsp - w$pi_exp) < 1e-9), sprintf("IDP first-stage probability = final rule, all %d weighted clusters", nrow(w)))
check(all(abs(w$base / w$base_exp - 1) < 1e-9), sprintf("IDP base weight = max(units, interviews)/pi/interviews, all %d weighted clusters", nrow(w)))
hxw <- w %>% filter(ver == "hex_v1", kind == "mixed")
sx <- hxw %>% inner_join(sugg %>% select(cluster_id, pi_total_F1_F4_F5), by = "cluster_id")
check(nrow(sx) == nrow(hxw) && all(abs(sx$fsp - sx$pi_total_F1_F4_F5) < 1e-9),
      sprintf("all %d weighted hex sites in mixed strata equal the values Resampling suggested (%d in that table)", nrow(hxw), nrow(sugg)))
ov <- w %>% filter(n_w > size)
check(all(abs(ov$base - 1 / ov$fsp) < 1e-9), sprintf("F3: the %d clusters with more interviews than units give each interview 1/pi", nrow(ov)))
say("previously flagged clusters, now:")
show(w %>% filter(cluster_id %in% c("idp_NG002007_1", "idp_NG002007_2", "idp_NG008016_6", "idp_NG036015_14", "idp_NG034001_2", "idp_NG021010_7")) %>%
       transmute(cluster_id, group, pi6 = round(pi6, 4), pi_hex = round(pi_hex, 4), pis_hex = round(pis_hex, 4), pi_exp = round(pi_exp, 4), fsp = round(fsp, 4), size, n_w, base = round(base, 3)))

# ------------------------------------------------------------------------------
say("\n== 4. where the 4x cap binds (information) ==")
cb <- W %>% group_by(strata_id, pop_type) %>% summarise(n = n(), n_capped = sum(capped), shift_pct = 100 * sum(pmax(0, weight_uncapped - weight)) / sum(weight))
say("strata where the cap binds: %d of %d (NI %d, IDP %d) | interviews trimmed: %d | weight moved: median %.1f%%, max %.1f%% of the stratum",
    sum(cb$n_capped > 0), nrow(cb), sum(cb$n_capped > 0 & cb$pop_type == "non_idp"), sum(cb$n_capped > 0 & cb$pop_type == "idp"),
    sum(cb$n_capped), median(cb$shift_pct[cb$n_capped > 0]), max(cb$shift_pct))
show(cb %>% filter(n_capped > 0) %>% arrange(desc(shift_pct)) %>% left_join(r1 %>% select(strata_id, State, LGA), by = "strata_id"), 6)

say("\nVERDICT: %s", if (length(fails)) sprintf("%d of %d checks FAIL: %s", length(fails), n_checks, paste(fails, collapse = " | ")) else sprintf("all %d checks PASS", n_checks))
