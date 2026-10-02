# Read-only comparison for the IDP psu_probability decision report. Prints to screen only.
setwd("C:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026")
suppressMessages({ library(sf); library(dplyr) })
sf_use_s2(FALSE)

# July design = the 6 Aug design archive (the design stamp_frame_version.R names as current; the 3 Aug
# _cache/idp_sites copy predates the 6 Aug NW targeted resample and is NOT authoritative for NW strata)
d6 <- sf::st_drop_geometry(readRDS("1_sampling/_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds"))
des <- d6[d6$pop_type == "idp", c("cluster_id", "strata_id", "adm2_pcode", "uuid_hex", "MOS", "total_MOS", "clusters", "psu_probability", "selection_count", "n_other_sites_in_hex")]
cat("6 Aug design IDP clusters:", nrow(des), "| psu == min(1, k*MOS/T):", isTRUE(all.equal(des$psu_probability, pmin(1, des$clusters * des$MOS / des$total_MOS))), "| certainty:", sum(des$psu_probability >= 1), "
")
k1T1 <- des %>% distinct(strata_id, adm2_pcode, k1 = clusters, T1 = total_MOS)

# July hex grid (pre-buffer-fix version = the one the 3 Aug design used)
grid <- readRDS("1_sampling/_archive/2026-08-30_stale_hex_grid_pre_buffer_fix/hex_grid_idp.rds")
cat("grid class:", paste(class(grid), collapse = ","), "| rows:", nrow(grid), "| cols:", paste(setdiff(names(grid), "geometry"), collapse = ","), "\n")
gcols <- intersect(c("uuid_hex", "pop_hh", "MOS", "adm2_pcode"), names(grid))
chk <- des %>% inner_join(sf::st_drop_geometry(grid)[, gcols, drop = FALSE] %>% distinct(uuid_hex, .keep_all = TRUE), by = "uuid_hex", suffix = c("", "_grid"))
cat("design hexes found in grid:", nrow(chk), "of", nrow(des), "\n")
if ("pop_hh" %in% gcols) cat("design MOS == grid pop_hh:", round(mean(abs(chk$MOS - chk$pop_hh) < 1), 3), "\n")

# Site frame (all DTM sites, used by the post-2-Sep draws)
sites <- readRDS("1_sampling/input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds")
cat("site frame rows:", nrow(sites), "| cols:", paste(setdiff(names(sites), "geometry"), collapse = ","), "\n")
sites <- st_transform(sites, st_crs(grid))
sites$row_key <- seq_len(nrow(sites))
sites <- st_join(sites, grid %>% select(hex_id = uuid_hex), join = st_within, left = TRUE)
sites <- sites[!duplicated(sites$row_key), ]

# Frame + Round 1 achieved (treat the text "NA" as a value, not missing)
full <- read.csv("1_sampling/output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", stringsAsFactors = FALSE, na.strings = "")
full <- full[full$pop_type == "idp" & !duplicated(full$cluster_id), c("cluster_id", "strata_id", "adm2_pcode", "psu_definition_version", "latitude", "longitude", "households_in_cluster")]
rs <- read.csv("1_sampling/resampling/output/dual_round_prototype_snapshot_2026-10-01_pre_recovery/real_submissions.csv", stringsAsFactors = FALSE, na.strings = "")
rs <- rs[rs$pop_type %in% "idp" & rs$interview_outcome %in% "completed" & !(rs$deletion_status %in% "confirmed"), ]
ach <- as.data.frame(table(cluster_id = rs$matched_cluster_id), stringsAsFactors = FALSE); names(ach)[2] <- "ach"
full <- full %>% left_join(ach, by = "cluster_id") %>% mutate(ach = coalesce(ach, 0L))
cat("\nfielded IDP clusters:", sum(full$ach > 0), "| interviews:", sum(full$ach), "| by version:",
    paste(tapply(full$ach > 0, full$psu_definition_version, sum), collapse = "/"), "clusters,",
    paste(tapply(full$ach, full$psu_definition_version, sum), collapse = "/"), "interviews (hex_v1/site_v2)\n")

# ---- (i) fielded site_v2 sites lying inside a July-SELECTED hex ----
fld <- full %>% filter(ach > 0)
pts <- st_as_sf(fld, coords = c("longitude", "latitude"), crs = 4326) %>% st_transform(st_crs(grid))
pts <- st_join(pts, grid %>% select(pt_hex = uuid_hex), join = st_within, left = TRUE)
pts <- pts[!duplicated(pts$cluster_id), ]
sel_hex <- unique(des$uuid_hex)
sv <- pts %>% filter(psu_definition_version == "site_v2")
cat("\n(i) fielded site_v2 clusters:", nrow(sv), "| inside a July-selected hex:", sum(sv$pt_hex %in% sel_hex),
    "clusters /", sum(sv$ach[sv$pt_hex %in% sel_hex]), "interviews | in no July hex at all:", sum(is.na(sv$pt_hex)), "\n")
inhex <- sv %>% filter(pt_hex %in% sel_hex) %>% left_join(des %>% distinct(uuid_hex, psu_probability), by = c("pt_hex" = "uuid_hex"))
cat("    of those, July hex taken with certainty:", sum(inhex$psu_probability >= 1, na.rm = TRUE), "\n")

co <- full %>% distinct(cluster_id, households_in_cluster) %>% inner_join(des, by = "cluster_id") %>% mutate(share = households_in_cluster / MOS)
cat("
co-location (6 Aug design, all", nrow(co), "IDP clusters): co-located hexes", sum(co$n_other_sites_in_hex > 0),
    "| surveyed site share of hex, median", round(median(co$share[co$n_other_sites_in_hex > 0]), 3),
    "| share < 0.5:", round(mean(co$share[co$n_other_sites_in_hex > 0] < 0.5), 3), "| single-site share==1:", round(mean(abs(co$share[co$n_other_sites_in_hex == 0] - 1) < 0.01), 3), "
")

# ---- (ii) hex-only strata: co-location choice, site-level (a) vs hex-level (b) ----
hv <- full %>% filter(psu_definition_version == "hex_v1", ach > 0) %>% inner_join(des %>% select(cluster_id, MOS, psu_probability, n_other_sites_in_hex), by = "cluster_id") %>% mutate(hh_site = households_in_cluster)
cat("\n(ii) fielded hex_v1 clusters matched to the 6 Aug design:", nrow(hv), "of", sum(full$psu_definition_version == "hex_v1" & full$ach > 0), "\n")
kinds <- full %>% filter(ach > 0) %>% group_by(strata_id) %>% summarise(k = n_distinct(psu_definition_version), .groups = "drop")
pure <- kinds$strata_id[kinds$k == 1]; mixed_ids <- kinds$strata_id[kinds$k == 2]
cmp <- hv %>% filter(strata_id %in% pure) %>% group_by(strata_id) %>%
  mutate(wa = hh_site / psu_probability, wb = MOS / psu_probability, sa = wa / sum(wa), sb = wb / sum(wb)) %>%
  summarise(n_cl = n(), any_co = any(n_other_sites_in_hex > 0), tvd = 0.5 * sum(abs(sa - sb)), .groups = "drop")
cat("    hex-only strata:", nrow(cmp), "| with a co-located cluster:", sum(cmp$any_co), "\n")
cat("    stratum weight moved between clusters, (a) vs (b) [total variation distance] quantiles:\n"); print(round(quantile(cmp$tvd, c(.25, .5, .75, .9, 1)), 3))
cat("    strata where >10% of the weight moves:", sum(cmp$tvd > 0.10), "| >20%:", sum(cmp$tvd > 0.20), "\n")

# ---- (iii) mixed strata: site_v2 share of stratum weight under each option ----
# phase-2 pool approximation per LGA: accessible DTM sites not within 30 m of any hex_v1 cluster point; k2 = site_v2 clusters drawn in the stratum
hexpts <- st_as_sf(full %>% filter(psu_definition_version == "hex_v1"), coords = c("longitude", "latitude"), crs = 4326) %>% st_transform(st_crs(grid))
near <- lengths(st_is_within_distance(sites, hexpts, dist = 30)) > 0
# match the draw script exactly: dplyr::filter(accessible_status != "Inaccessible") also DROPS sites whose status is NA
pool <- sf::st_drop_geometry(sites)[!near & !is.na(sites$accessible_status) & sites$accessible_status != "Inaccessible", ]
cat("\n(iii) phase-2 pool sites:", nrow(pool), "| with NA pop_hh:", sum(is.na(pool$pop_hh)), "| NA accessible_status in site frame:", sum(is.na(sites$accessible_status)), "\n")
T2 <- pool %>% group_by(adm2_pcode) %>% summarise(T2 = sum(pop_hh, na.rm = TRUE), .groups = "drop")
k2 <- full %>% filter(psu_definition_version == "site_v2") %>% count(strata_id, adm2_pcode, name = "k2")
res <- list()
for (s in mixed_ids) {
  f <- full %>% filter(strata_id == s, ach > 0)
  pc <- f$adm2_pcode[1]; kk <- k1T1 %>% filter(strata_id == s); t2 <- T2$T2[T2$adm2_pcode == pc]; kv <- k2$k2[k2$strata_id == s]
  if (nrow(kk) == 0 || length(t2) == 0 || length(kv) == 0) next
  h <- f %>% filter(psu_definition_version == "hex_v1") %>% inner_join(des %>% select(cluster_id, MOS, pi1 = psu_probability, hits = selection_count), by = "cluster_id")
  v <- f %>% filter(psu_definition_version == "site_v2")
  if (nrow(h) == 0 || nrow(v) == 0) next
  hh_h <- h$households_in_cluster; hh_v <- v$households_in_cluster
  pi2_h <- pmin(1, kv * hh_h / t2); pi2_v <- pmin(1, kv * hh_v / t2)
  piB_h <- h$pi1 + (1 - h$pi1) * pi2_h; piB_v <- pi2_v              # site_v2 sites treated as non-representative in July (pi1 = 0) - conservative
  wB <- c(hh_h / piB_h, hh_v / piB_v)                               # (B) two-phase, site-level
  wD <- c(h$hits, rep(1, nrow(v)))                                   # (D) equal per draw
  wBb <- c(h$MOS / h$pi1, hh_v / piB_v)                              # (B) with hex-level phase 1
  n_int <- c(h$ach, v$ach)
  idx <- c(rep(FALSE, nrow(h)), rep(TRUE, nrow(v)))
  # Kish unequal-weighting effect over interviews: each interview's weight = cluster weight / its interviews
  kish <- function(W) { wi <- rep(W / n_int, n_int); length(wi) * sum(wi^2) / sum(wi)^2 }
  res[[s]] <- data.frame(strata_id = s, n = sum(n_int), int_share = sum(n_int[idx]) / sum(n_int),
                         B = sum(wB[idx]) / sum(wB), D = sum(wD[idx]) / sum(wD), Bhex = sum(wBb[idx]) / sum(wBb),
                         kB = kish(wB), kD = kish(wD), kBhex = kish(wBb))
}
res <- bind_rows(res)
cat("\n(iii) mixed strata with a non-finite share (zero/NA households or pool):", sum(!is.finite(res$B) | !is.finite(res$Bhex)), "\n")
bad_hh <- full %>% filter(ach > 0, strata_id %in% mixed_ids, is.na(households_in_cluster) | households_in_cluster <= 0)
cat("    fielded clusters in mixed strata with NA/zero households_in_cluster:", nrow(bad_hh), "\n")
res <- res %>% filter(is.finite(B), is.finite(Bhex))
cat("(iii) mixed strata compared:", nrow(res), "of", length(mixed_ids), "\n")
cat("    site_v2 share of the stratum (median / IQR):\n")
for (col in c("int_share", "D", "B", "Bhex")) cat(sprintf("      %-9s median %.2f | IQR %.2f-%.2f\n", col, median(res[[col]]), quantile(res[[col]], .25), quantile(res[[col]], .75)))
cat("    |B - D| median:", round(median(abs(res$B - res$D)), 3), "| 90th pct:", round(quantile(abs(res$B - res$D), .9), 3), "| strata where |B-D| > 0.10:", sum(abs(res$B - res$D) > 0.10), "\n")
cat("    |B - Bhex| median:", round(median(abs(res$B - res$Bhex)), 3), "| strata where > 0.10:", sum(abs(res$B - res$Bhex) > 0.10), "\n")
cat("    examples:\n"); print(head(res %>% mutate(across(where(is.numeric), ~ round(.x, 2))) %>% arrange(desc(abs(B - D))), 8))
cat("\n    Kish weighting effect in mixed strata (median / 90th pct):\n")
for (col in c("kD", "kBhex", "kB")) cat(sprintf("      %-6s median %.2f | 90th %.2f | max %.2f\n", col, median(res[[col]]), quantile(res[[col]], .9), max(res[[col]])))
# MoE impact at p = 0.5, ignoring FPC: MoE = 1.645 * sqrt(0.25 * k / n)
moe <- function(k, n) 100 * 1.6448536 * sqrt(0.25 * k / n)
res <- res %>% mutate(moeD = moe(kD, n), moeB = moe(kB, n), moeBhex = moe(kBhex, n))
cat("    simple MoE at p=0.5 (no FPC) with the weighting effect included - median: D", round(median(res$moeD), 1), "| Bhex", round(median(res$moeBhex), 1), "| B", round(median(res$moeB), 1), "\n")
cat("    mixed strata under 10% MoE: D", sum(res$moeD <= 10), "| Bhex", sum(res$moeBhex <= 10), "| B", sum(res$moeB <= 10), "of", nrow(res), "\n")

# same weighting effect for hex-only strata, site-level (a) vs hex-level (b)
kp <- hv %>% filter(strata_id %in% pure) %>% group_by(strata_id) %>%
  summarise(ka = { W <- hh_site / psu_probability; wi <- rep(W / ach, ach); length(wi) * sum(wi^2) / sum(wi)^2 },
            kb = { W <- MOS / psu_probability; wi <- rep(W / ach, ach); length(wi) * sum(wi^2) / sum(wi)^2 }, .groups = "drop")
cat("\n    hex-only strata, Kish effect median / 90th: site-level (a)", round(median(kp$ka), 2), "/", round(quantile(kp$ka, .9), 2),
    "| hex-level (b)", round(median(kp$kb), 2), "/", round(quantile(kp$kb, .9), 2), "\n")
w <- warnings(); if (length(w)) { cat("\nwarnings (distinct messages):\n"); print(unique(names(w))) }
