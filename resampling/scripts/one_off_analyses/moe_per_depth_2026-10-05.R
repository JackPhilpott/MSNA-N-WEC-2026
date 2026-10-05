# ==============================================================================
# 2026-10-05 READ-ONLY (for Jack's depth-vs-point-drop decision): achievable planned MoE per depth for the Non-IDP
# depth strata. Basis = the strata frame's design capacity, exactly as realized_moe_pct is computed:
# compute_strata_achieved() with unused spares excluded, MoE by realized_moe_unequal() (unequal cluster sizes,
# DEFF = 1 + ((cv^2 + 1) * m_bar - 1) * ICC). Depth = +k primary households in EVERY covered-accessible cluster:
#   - MoE at k = 6 / 12 / 18 (+1 / +2 / +3 clusters' worth of depth per cluster);
#   - the smallest uniform k reaching 10% and 9.25%, with the households that takes, and the depth limit (k -> inf);
#   - building feasibility: unclaimed accessible buildings in each cluster's hex (latest pool check: 5 Oct spares,
#     else 4 Oct top-up) shared by the clusters in that hex.
# Usage (from 1_sampling): Rscript resampling/scripts/one_off_analyses/moe_per_depth_2026-10-05.R
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr) })
source("scripts/shared/frame_status.R")
source("scripts/shared/spare_clusters.R")
DC <- "output/data/data_collection"
MON <- file.path("..", "2_monitoring", "data")
OUT <- file.path("resampling", "output", "analysis_building_vs_worldpop_2026-10-05")
STRATA <- c(Damboa = "non_idp_NG008007", Dandume = "non_idp_NG021008", Dikwa = "non_idp_NG008008", Magumeri = "non_idp_NG008020",
            Malumfashi = "non_idp_NG021025", Matazu = "non_idp_NG021028", Yauri = "non_idp_NG022020",
            `Kala/Balge` = "non_idp_NG008015", Funtua = "non_idp_NG021014")

full <- read_csv(file.path(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
subs <- read_csv(file.path(MON, "real_submissions.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
ov <- read_csv(file.path(MON, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
unused <- unused_spare_ids(load_spare_register(path = file.path(DC, SPARE_REGISTER_NAME)), achieved_by_cluster(subs, deletion_excluded_uuids(ov)))
acc <- compute_cluster_accessibility(full, 4)
res <- compute_strata_achieved(full, compute_achieved_lookup(subs, ov), acc, filter_ward_accessible = TRUE, exclude_cluster_ids = unused)
sl <- read_csv(file.path(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)

# unclaimed accessible buildings per hex: the 5 Oct spares check wins over the 4 Oct top-up check
pv_files <- c(Sys.glob("resampling/output/resample_runs/*/2026-10-04_nonidp_topup_150rule/pool_validation_by_hex.csv"),
              Sys.glob("resampling/output/resample_runs/*/2026-10-05_spares/pool_validation_by_hex.csv"))
pv <- bind_rows(lapply(pv_files, function(p) {
  x <- read_csv(p, col_types = cols(.default = "c"), show_col_types = FALSE)
  if (nrow(x) == 0) return(NULL)
  x %>% mutate(batch_rank = if (grepl("2026-10-05_spares", p)) 2L else 1L)
})) %>% group_by(uuid_hex_pop) %>% slice_max(batch_rank, n = 1, with_ties = FALSE) %>% ungroup() %>%
  transmute(uuid_hex_pop, n_acc = as.integer(n_acc))
cl_hex <- full %>% filter(status == "primary", strata_id %in% STRATA) %>% distinct(strata_id, cluster_id, uuid_hex) %>%
  mutate(uuid_hex_pop = paste0("non_idp_", uuid_hex))

z <- qnorm(0.95)
out <- list()
for (lga in names(STRATA)) {
  sid <- STRATA[[lga]]
  s <- sl %>% filter(strata_id == sid)
  sizes <- res$cluster_sizes %>% filter(strata_id == sid)
  C <- nrow(sizes); n <- sum(sizes$n); N <- as.numeric(s$N_hh); ICC <- as.numeric(s$ICC)
  moe <- function(k) 100 * realized_moe_unequal(n + C * k, N, sizes$n + k, ICC)
  first_k <- function(target) { for (k in 0:300) if (!is.na(moe(k)) && moe(k) <= target) return(k); NA_integer_ }
  k10 <- first_k(10); k925 <- first_k(9.25)
  feas <- sizes %>% left_join(cl_hex %>% filter(strata_id == sid), by = "cluster_id") %>%
    left_join(pv, by = "uuid_hex_pop") %>% group_by(uuid_hex_pop) %>% mutate(per_cluster = n_acc %/% n()) %>% ungroup()
  out[[lga]] <- tibble(
    lga = lga, strata_id = sid, partners_covering = s$partners_covering, clusters = C, planned_households = n,
    moe_now = round(moe(0), 2), moe_frame = round(as.numeric(s$realized_moe_pct), 2), icc = ICC,
    moe_plus6 = round(moe(6), 2), moe_plus12 = round(moe(12), 2), moe_plus18 = round(moe(18), 2),
    k_to_10 = k10, households_to_10 = if (is.na(k10)) NA_integer_ else as.integer(k10 * C),
    k_to_9.25 = k925, households_to_9.25 = if (is.na(k925)) NA_integer_ else as.integer(k925 * C),
    moe_limit_depth = round(moe(100000), 2), moe_limit_formula = round(100 * z * sqrt(0.25 * ICC / C), 2),
    clusters_with_hex_checked = sum(!is.na(feas$n_acc)),
    clusters_hex_fits_6 = sum(feas$per_cluster >= 6, na.rm = TRUE), clusters_hex_fits_12 = sum(feas$per_cluster >= 12, na.rm = TRUE),
    clusters_hex_fits_18 = sum(feas$per_cluster >= 18, na.rm = TRUE))
}
tab <- bind_rows(out)
write_csv(tab, file.path(OUT, "moe_per_depth_by_stratum.csv"))
print(as.data.frame(tab %>% select(lga, clusters, planned_households, moe_now, moe_frame, moe_plus6, moe_plus12, moe_plus18,
                                   households_to_10, households_to_9.25, moe_limit_depth, clusters_with_hex_checked,
                                   clusters_hex_fits_6, clusters_hex_fits_12, clusters_hex_fits_18)), row.names = FALSE)
cat("written:", file.path(OUT, "moe_per_depth_by_stratum.csv"), "\n")
