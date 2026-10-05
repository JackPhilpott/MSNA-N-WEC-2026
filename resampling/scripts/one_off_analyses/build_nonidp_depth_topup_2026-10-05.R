# ==============================================================================
# 2026-10-05 Non-IDP DEPTH top-up generator. Jack, in Resampling's window on 4 Oct: "yes do the depth tomorrow when
# fresh eyes and daylight"; 5 Oct via the Coordinator: "(a) Today, after re-link", scope under his 150 rule.
# STAGING ONLY: writes per-partner staging folders resample_runs/<Partner>/2026-10-05_nonidp_depth/ holding the merge's
# existing-cluster pair (merge_partner_resample_batch.R reads it, 30 Sep merge layer):
#   existing_cluster_target_increases_non_idp.csv   cluster_id, increase_target, increase_reserve (+ old/new values)
#   existing_cluster_household_additions_non_idp.csv real households drawn at random from the cluster hex's ACCESSIBLE,
#       UNCLAIMED building footprints (the draw's own Stage B2 rules: GRID3 ward Accessible in the master ward file,
#       not already a frame household), numbered on from the cluster's highest _HH / _R, built by finalize_households()
# Depth = repeat selections of an already-selected hex: each step is +6 primaries and +6 reserves, so target_households
# stays 6 x selection_count (the merge adds increase_target / 6 to selection_count).
# Allocation per stratum (greedy): the next step goes to the eligible cluster with the fewest planned households (even
# sizes - realized_moe_unequal penalises unequal ones) until the planned MoE reaches 9.25%; if that needs more than
# 150 extra households, 10%; if that does too, the stratum is skipped (Jack's 150 rule). Eligible = in the stratum's
# planned capacity (covered, accessible, not an unused spare; compute_strata_achieved) and the hex still holds >= 12
# accessible unclaimed buildings per step. Planned MoE uses the same design-capacity basis as realized_moe_pct.
# Usage (from 1_sampling): Rscript resampling/scripts/one_off_analyses/build_nonidp_depth_topup_2026-10-05.R <seed>
# ==============================================================================
args <- commandArgs(trailingOnly = TRUE)
SEED <- as.integer(if (length(args) >= 1) args[1] else 2026100701)
LABEL <- "2026-10-05_nonidp_depth"
OUT <- file.path("resampling", "output", "nonidp_depth_2026-10-05")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
log_con <- file(file.path(OUT, "build_log.txt"), open = "wt")
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); cat(m, "\n", file = log_con) }
STRATA <- c(Magumeri = "non_idp_NG008020", Malumfashi = "non_idp_NG021025", Dandume = "non_idp_NG021008",
            Dikwa = "non_idp_NG008008", Yauri = "non_idp_NG022020", Damboa = "non_idp_NG008007",
            Funtua = "non_idp_NG021014")          # Funtua: staged probe only (Jack decides from the result)
TARGETS <- c(9.25, 10); CAP_HH <- 150; STEP <- 6L; MIN_ACCESSIBLE_BUILDINGS <- 6L

# ---- Stage A: the draw's own environment (pipeline prefix + stage-2 functions + GRID3 wards) ----
log_msg("==== Non-IDP depth top-up generator - %s (seed %d) ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SEED)
lines <- readLines("scripts/01_sampling_pipeline_main.R")
writeLines(lines[1:1002], "temp_depth_prefix.R")
source("temp_depth_prefix.R")
file.remove("temp_depth_prefix.R")
source("scripts/02_stage2_building_ingestion.R")
source("scripts/03_stage2_household_selection.R")
source("scripts/04_stage2_cluster_reallocation.R")
suppressPackageStartupMessages({ library(dplyr); library(sf); library(readr) })
building_data_dir <- file.path("C:/Users/JackPHILPOTT/Personal - Documents/GIS", "Google_Open_Buildings")
nga_wards <- sf::st_read(here::here("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"), quiet = TRUE)
source("scripts/shared/frame_status.R")
source("scripts/shared/spare_clusters.R")

# ---- planned capacity (as realized_moe_pct) ----
DC <- "output/data/data_collection"; MON <- file.path("..", "2_monitoring", "data")
full <- read_csv(file.path(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
sl <- read_csv(file.path(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
subs <- read_csv(file.path(MON, "real_submissions.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
ov <- read_csv(file.path(MON, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
unused <- unused_spare_ids(load_spare_register(path = file.path(DC, SPARE_REGISTER_NAME)), achieved_by_cluster(subs, deletion_excluded_uuids(ov)))
acc <- compute_cluster_accessibility(full, 4)
cap <- compute_strata_achieved(full, compute_achieved_lookup(subs, ov), acc, filter_ward_accessible = TRUE, exclude_cluster_ids = unused)
sizes_all <- cap$cluster_sizes %>% filter(strata_id %in% STRATA)
# Depth only where a team can still collect: the cluster must be in covered_accessible (accessible ward, not
# below-threshold, not overlay-excluded, not target-correction-dropped). Capacity alone is not enough - an excluded
# cluster stays in it through its already-achieved ("stranded") interviews, but new rows there never reach WORKING
# (found in the 5 Oct sandbox test: 120 rows in 6 such clusters, Malumfashi/Dandume/Yauri below their planned MoE).
collectable <- unique(acc$covered_accessible$cluster_id)
cl <- full %>% filter(cluster_id %in% sizes_all$cluster_id) %>% group_by(cluster_id) %>%
  summarise(strata_id = first(strata_id), uuid_hex = first(uuid_hex),
            old_max_primary = suppressWarnings(max(as.integer(interview_number), na.rm = TRUE)),
            old_max_reserve = suppressWarnings(max(as.integer(replacement_rank), na.rm = TRUE)),
            old_target = as.integer(first(target_households)), old_reserve = as.integer(first(reserve_households)), .groups = "drop") %>%
  mutate(uuid_hex_pop = paste0("non_idp_", uuid_hex), old_max_reserve = ifelse(is.finite(old_max_reserve), old_max_reserve, 0L))
log_msg("Planned capacity: %d cluster(s) in %d target strata; %d unused spare(s) excluded nationally.", nrow(cl), length(STRATA), length(unused))

# ---- building pool per involved hex (Stage B2 rules) ----
hexes <- non_idp_sampling$sampling_frame %>% filter(uuid_hex_pop %in% cl$uuid_hex_pop)
master_ward <- read_csv("resampling/output/master_accessibility_status_ward_level.csv", show_col_types = FALSE)
ward_status <- setNames(master_ward$`Accessible status`, paste(master_ward$State, master_ward$LGA, master_ward$`Ward (GRID3)`, sep = "|"))
wards_proj <- sf::st_transform(nga_wards, mycrs) %>% dplyr::select(.ward = wardname)
claimed <- full %>% filter(pop_type == "non_idp", !is.na(latitude), !is.na(longitude)) %>%
  transmute(uuid_hex_pop = paste0("non_idp_", uuid_hex),
            .coord_key = paste0(round(as.numeric(latitude), 6), "_", round(as.numeric(longitude), 6))) %>% distinct()
pool_files <- load_building_footprints(gdb_directory = building_data_dir, accessible_area = hexes, mycrs = mycrs,
                                       cache_directory = file.path(OUT, "cache_depth_pool"), rebuild = FALSE)
pool <- purrr::map(pool_files, function(bf) {
  part <- tryCatch(readRDS(bf), error = function(e) NULL)
  if (is.null(part) || nrow(part) == 0) return(NULL)
  part <- sf::st_transform(part, mycrs)
  xy <- sf::st_coordinates(part)
  part %>% mutate(.centroid_key = paste0(round(xy[, "X"], 1), "_", round(xy[, "Y"], 1)))
}) %>% purrr::compact() %>% bind_rows() %>%
  filter(uuid_hex_pop %in% cl$uuid_hex_pop) %>% distinct(uuid_hex_pop, .centroid_key, .keep_all = TRUE)
hex_names <- hexes %>% sf::st_drop_geometry() %>% distinct(uuid_hex_pop, .adm1 = adm1_name, .adm2 = adm2_name)
pool <- pool %>% left_join(hex_names, by = "uuid_hex_pop")
pool <- sf::st_join(pool, wards_proj, join = sf::st_within, left = TRUE)
pool <- pool[!duplicated(paste(pool$uuid_hex_pop, pool$.centroid_key)), ]
ll <- sf::st_coordinates(sf::st_transform(pool, 4326))
pool$.coord_key <- paste0(round(ll[, "Y"], 6), "_", round(ll[, "X"], 6))
st <- unname(ward_status[paste(pool$.adm1, pool$.adm2, pool$.ward, sep = "|")])
n_raw <- nrow(pool)
pool <- pool[!is.na(st) & st == "Accessible", ] %>% anti_join(claimed, by = c("uuid_hex_pop", ".coord_key"))
log_msg("Building pool: %d footprint(s) in %d hex(es); %d accessible and unclaimed.", n_raw, n_distinct(cl$uuid_hex_pop), nrow(pool))
pool_n <- pool %>% sf::st_drop_geometry() %>% count(uuid_hex_pop, name = "n_pool")
cl <- cl %>% left_join(pool_n, by = "uuid_hex_pop") %>% mutate(n_pool = coalesce(n_pool, 0L))

# ---- allocation (greedy, the 150 rule) ----
plan_c <- list(); plan_s <- list()
for (lga in names(STRATA)) {
  sid <- STRATA[[lga]]
  s <- sl %>% filter(strata_id == sid)
  N <- as.numeric(s$N_hh); ICC <- as.numeric(s$ICC)
  base <- sizes_all %>% filter(strata_id == sid) %>% left_join(cl %>% select(cluster_id, uuid_hex_pop), by = "cluster_id")
  moe <- function(v) 100 * realized_moe_unequal(sum(v), N, v, ICC)
  moe0 <- moe(base$n); chosen <- NULL
  for (tg in TARGETS) {
    sz <- setNames(base$n, base$cluster_id); add <- setNames(integer(nrow(base)), base$cluster_id)
    left <- setNames(cl$n_pool, cl$uuid_hex_pop)            # buildings left per hex (shared by clusters in it)
    extra <- 0L
    while (moe(sz) > tg && extra + STEP <= CAP_HH) {
      ok <- base$cluster_id[left[base$uuid_hex_pop] >= 2L * STEP & base$cluster_id %in% collectable]
      if (length(ok) == 0) break
      c1 <- ok[which.min(sz[ok])]
      sz[c1] <- sz[c1] + STEP; add[c1] <- add[c1] + STEP; extra <- extra + STEP
      h <- base$uuid_hex_pop[base$cluster_id == c1]; left[h] <- left[h] - 2L * STEP
    }
    if (moe(sz) <= tg) { chosen <- list(target = tg, add = add, moe1 = moe(sz), extra = extra); break }
  }
  status <- if (is.null(chosen)) "SKIP (no target reachable within 150 households / buildings)" else
    sprintf("reaches %.2f%% (target %.2f%%)", chosen$moe1, chosen$target)
  plan_s[[lga]] <- tibble(lga = lga, strata_id = sid, partners_covering = s$partners_covering, clusters = nrow(base),
                          planned_households = sum(base$n), moe_now = round(moe0, 2),
                          target = if (is.null(chosen)) NA_real_ else chosen$target,
                          moe_after = if (is.null(chosen)) NA_real_ else round(chosen$moe1, 2),
                          extra_primary_households = if (is.null(chosen)) 0L else chosen$extra,
                          clusters_topped_up = if (is.null(chosen)) 0L else sum(chosen$add > 0),
                          probe_only = lga == "Funtua", status = status)
  if (!is.null(chosen)) plan_c[[lga]] <- tibble(cluster_id = names(chosen$add), increase_target = as.integer(chosen$add)) %>% filter(increase_target > 0)
  log_msg("  %-10s %s: MoE %.2f -> %s, +%d primary households in %d cluster(s)", lga, sid, moe0, status,
          if (is.null(chosen)) 0L else chosen$extra, if (is.null(chosen)) 0L else sum(chosen$add > 0))
}
plan_strata <- bind_rows(plan_s)
plan_cl <- bind_rows(plan_c) %>% left_join(cl, by = "cluster_id") %>% mutate(increase_reserve = increase_target)
write_csv(plan_strata, file.path(OUT, "depth_plan_by_stratum.csv"))

# ---- draw the households (random, seeded), numbered on from each cluster's highest _HH / _R ----
set.seed(SEED)
pool_by_hex <- split(pool, pool$uuid_hex_pop)
tmpl_cols <- c("cluster_id", "pop_type", "strata_id", "region", "adm1_pcode", "adm1_name", "adm2_pcode", "adm2_name", "uuid_hex", "uuid",
               "certainty_stratum", "selection_type", "selection_count", "psu_probability", "target_households", "reserve_households",
               "reallocated", "original_uuid_hex_pop", "supplementary_cluster", "location_source", "households_in_cluster_source",
               "site_radius_m", "iom_site_id", "iom_site_name", "iom_site_type", "iom_site_ward", "n_other_sites_in_hex", "idp_population_category")
rows <- list()
for (i in seq_len(nrow(plan_cl))) {
  p <- plan_cl[i, ]
  hx <- pool_by_hex[[p$uuid_hex_pop]]
  hx <- hx[, setdiff(names(hx), c(".adm1", ".adm2", ".ward", ".coord_key"))]
  drawn <- draw_cluster(hx, p$increase_target, p$increase_reserve)
  if (is.null(drawn) || sum(drawn$status == "primary") < p$increase_target || sum(drawn$status == "reserve") < p$increase_reserve)
    stop(sprintf("STOP: %s's hex no longer holds %d accessible unclaimed buildings", p$cluster_id, p$increase_target + p$increase_reserve))
  pool_by_hex[[p$uuid_hex_pop]] <- hx[!(hx$.centroid_key %in% drawn$.centroid_key), ]   # a hex shared by clusters
  drawn$cluster_id <- p$cluster_id
  drawn$interview_number <- ifelse(drawn$status == "primary", drawn$interview_number + p$old_max_primary, NA_integer_)
  drawn$replacement_rank <- ifelse(drawn$status == "reserve", drawn$replacement_rank + p$old_max_reserve, NA_integer_)
  tmpl <- full %>% filter(cluster_id == p$cluster_id) %>% slice(1)
  crow <- as.data.frame(setNames(lapply(tmpl_cols, function(c) if (c %in% names(tmpl)) tmpl[[c]] else NA), tmpl_cols), stringsAsFactors = FALSE)
  num <- c("selection_count", "psu_probability", "target_households", "reserve_households", "site_radius_m", "n_other_sites_in_hex")
  for (c in num) crow[[c]] <- suppressWarnings(as.numeric(crow[[c]]))
  hh <- finalize_households(drawn, crow, nga_wards, NGA_shapes_all_cleaned$nga_admin3, mycrs)
  hh$households_in_cluster <- suppressWarnings(as.numeric(tmpl$households_in_cluster))   # the cluster's own figure
  # Frame columns finalize_households() does not produce: the cluster's own values (as the IDP top-up's template rows
  # carry them). Without them the merge appends coverage_status/partners_covering = NA, and the next refresh drops
  # the rows as not covered (found in the 5 Oct sandbox test: FULL +1248, WORKING +0, no MoE change).
  for (c in c("coverage_status", "exclusion_reason", "partners_covering", "tier2_fallback_used", "psu_definition_version",
              "sampling_method", "msna_light_settlement_name", "original_partner_covering", "coverage_reallocated_on")) {
    if (c %in% names(tmpl)) hh[[c]] <- tmpl[[c]]
  }
  for (c in c("latitude_original", "longitude_original", "gps_corrected_date", "gps_corrected_source")) hh[[c]] <- NA   # no GPS correction yet
  rows[[i]] <- hh %>% sf::st_drop_geometry()
}
additions <- bind_rows(rows)

# ---- checks (all must hold, or nothing is written) ----
stopifnot(!anyDuplicated(additions$survey_id))
collide <- intersect(additions$survey_id, full$survey_id)
if (length(collide) > 0) stop("STOP: new survey_id(s) collide with FULL, e.g. ", paste(head(collide, 3), collapse = ", "))
acc_new <- unname(ward_status[paste(additions$adm1_name, additions$adm2_name, additions$adm3_name, sep = "|")])
if (any(is.na(acc_new) | acc_new != "Accessible")) stop("STOP: a drawn household falls outside an Accessible ward")
chk <- additions %>% count(cluster_id, status) %>% tidyr::pivot_wider(names_from = status, values_from = n, values_fill = 0) %>%
  left_join(plan_cl %>% select(cluster_id, increase_target, increase_reserve), by = "cluster_id")
if (any(chk$primary != chk$increase_target | chk$reserve != chk$increase_reserve)) stop("STOP: drawn rows differ from the plan")
if (any(additions$uuid_hex != full$uuid_hex[match(additions$cluster_id, full$cluster_id)])) stop("STOP: a household left its cluster's hex")
pc_stratum <- setNames(sl$partners_covering, sl$strata_id)[additions$strata_id]
if (any(is.na(additions$coverage_status) | additions$coverage_status != "covered" | additions$exclusion_reason != "none" |
        is.na(additions$partners_covering) | additions$partners_covering != pc_stratum))
  stop("STOP: a new row is not covered / not excluded / not on its stratum's partners_covering")
log_msg("Checks PASS: %d household row(s) (%d primary, %d reserve) for %d cluster(s); no survey_id collision; all in Accessible wards; all inside their cluster's hex.",
        nrow(additions), sum(additions$status == "primary"), sum(additions$status == "reserve"), nrow(plan_cl))

# ---- per-partner staging folders (the stratum's first partner, as for the spares) ----
first_partner <- function(sid) trimws(strsplit(sl$partners_covering[sl$strata_id == sid], ",")[[1]][1])
plan_cl$folder <- vapply(plan_cl$strata_id, first_partner, character(1))
write_csv(plan_cl %>% select(folder, strata_id, cluster_id, uuid_hex_pop, n_pool, old_target, increase_target, old_reserve, increase_reserve,
                             old_max_primary, old_max_reserve), file.path(OUT, "depth_plan_by_cluster.csv"))
hdr <- "strata_id,adm2_pcode,pop_type,additional_clusters_needed,state,lga,partners"
for (f in unique(plan_cl$folder)) {
  st_dir <- file.path("resampling", "output", "resample_runs", f, LABEL)
  if (dir.exists(st_dir)) stop("STOP: ", st_dir, " already exists")
  dir.create(st_dir, recursive = TRUE)
  pc <- plan_cl %>% filter(folder == f)
  write_csv(pc %>% transmute(cluster_id, increase_target, increase_reserve, old_target, new_target = old_target + increase_target,
                             old_reserve, new_reserve = old_reserve + increase_reserve, old_max_primary, old_max_reserve),
            file.path(st_dir, "existing_cluster_target_increases_non_idp.csv"))
  write_csv(additions %>% filter(cluster_id %in% pc$cluster_id), file.path(st_dir, "existing_cluster_household_additions_non_idp.csv"), na = "")
  srows <- sl %>% filter(strata_id %in% pc$strata_id)
  writeLines(c(hdr, sprintf('%s,%s,non_idp,0,%s,%s,"%s"', srows$strata_id, srows$adm2_pcode, srows$adm1_name, srows$adm2_name, srows$partners_covering)),
             file.path(st_dir, "shortfalls_nonidp.csv"))
  writeLines(hdr, file.path(st_dir, "shortfalls_idp.csv"))
  log_msg("  staged %s: %d cluster(s), %d household row(s) -> %s", f, nrow(pc), sum(additions$cluster_id %in% pc$cluster_id), st_dir)
}
print(as.data.frame(plan_strata %>% select(-strata_id)), row.names = FALSE)
log_msg("==== done %s ====", format(Sys.time(), "%H:%M:%S"))
close(log_con)
