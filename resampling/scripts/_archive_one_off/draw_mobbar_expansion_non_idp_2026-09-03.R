# ==============================================================================
# Mobbar Non-IDP supplementary draw - Damasak + Zanna Umarti wards, 2026-09-03.
#
# Adapted from draw_supplementary_clusters_batch.R (the proven, already-used
# mechanism for every partner's supplementary Non-IDP clusters this round) -
# same add_supplementary_clusters() call, real Google Open Buildings draw,
# same collision-safe _supp renumbering. The ONE structural difference: this
# stratum's shortfall isn't being closed from hexes that were already
# candidates (the normal case) - Damasak/Zanna Umarti were NEVER in
# hex_access at all (border-buffer excluded at Stage 1, confirmed zero
# intersection 2026-09-03), so they don't exist in non_idp_sampling$
# sampling_frame to begin with. Stage A0 (new) injects the 16 newly-eligible
# hexes (verified population, computed 2026-09-03) directly into that object
# before the draw, restricted to ONLY these hexes for Mobbar by zeroing MOS
# on every other Mobbar hex explicitly (not relying on the ward-accessibility
# shapefile join used elsewhere - those other 8 wards are excluded for a
# DIFFERENT, unrelated reason (accessibility_loss_below_population_threshold,
# whole-LGA, 2026-08-31), and an explicit allow-list is safer than a derived
# join near a small border-buffer LGA boundary).
#
# Mobbar's design-stage target_sample was independently recomputed 2026-09-03
# both ways (old-only N_hh=24,508.81 and combined N_hh=35,428.15) - identical
# result, 17 clusters/102 households, since the FPC-adjusted formula
# saturates at this population scale. So the shortfall to close is simply
# the stratum's full existing target (0 currently achievable in WORKING,
# since all 17 existing clusters are ward_accessible_status=Inaccessible for
# an unrelated reason) - 17 clusters, 102 households, drawn entirely from
# the new 16-hex pool.
#
# STAGING ONLY - does not touch the live WORKING/FULL frame.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
STAGING_DIR <- "resampling/output/resample_runs/FHI360_Mobbar/2026-09-03"
SEED_BASE <- 90309L
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(STAGING_DIR, "run_log_non_idp.txt"), open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Mobbar Non-IDP expansion draw - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

# ---- Stage A: source the deterministic pipeline prefix (no set.seed before line 1194) ----
log_msg("Stage A: sourcing pipeline prefix through build_sampling_plan()...")
lines <- readLines("scripts/01_sampling_pipeline_main.R")
writeLines(lines[1:1002], "temp_mobbar_draw_prefix.R")
source("temp_mobbar_draw_prefix.R")
file.remove("temp_mobbar_draw_prefix.R")
log_msg("  non_idp_sampling$sampling_frame: %d rows (before injection)", nrow(non_idp_sampling$sampling_frame))

source("scripts/02_stage2_building_ingestion.R")
source("scripts/03_stage2_household_selection.R")
source("scripts/04_stage2_cluster_reallocation.R")

building_data_dir <- file.path("C:/Users/JackPHILPOTT/Personal - Documents/GIS", "Google_Open_Buildings")
nga_wards <- sf::st_read(
  here::here("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

# ---- Stage A0 (NEW): build the 16 new Damasak/Zanna Umarti hexes and inject ----
log_msg("Stage A0: building + injecting the 16 newly-eligible Mobbar hexes (Damasak + Zanna Umarti)...")
library(dplyr); library(sf); library(readr)

bound_hex_clip <- readRDS("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
mob_hex_all <- bound_hex_clip %>% filter(adm2_name == "Mobbar")

grid3 <- sf::st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>%
  st_transform(mycrs)
target_wards <- grid3 %>% filter(wardname %in% c("Damasak", "Zanna Umarti"))
stopifnot(nrow(target_wards) == 2)

new_hexes <- st_intersection(st_make_valid(mob_hex_all), st_make_valid(st_union(target_wards))) %>%
  st_collection_extract("POLYGON") %>% filter(!st_is_empty(geometry))
log_msg("  %d candidate hexes found (Mobbar per-LGA grid ∩ Damasak/Zanna Umarti).", nrow(new_hexes))

acc_hex <- readRDS("input_data/boundaries/nga_hexagons/accessible_hex.rds") %>% filter(adm2_name == "Mobbar")
overlap_check <- st_intersects(new_hexes, acc_hex, sparse = FALSE)
n_overlap <- sum(rowSums(overlap_check) > 0)
if (n_overlap > 0) stop("New hexes overlap an existing accessible hex - not genuinely new, investigate before proceeding.")
log_msg("  Verified: zero overlap with the existing accessible_hex layer (genuinely new).")

new_hexes_pop <- new_hexes %>%
  mutate(
    pop = exactextractr::exact_extract(worldpop_pop, new_hexes, "sum"),
    pop_hh = pop / 6,
    estimated_households = round(pop_hh / 6) * 6,
    pop_type = "non_idp",
    uuid_hex_pop = paste0(pop_type, "_", uuid_hex)
  ) %>%
  filter(pop_hh > 5) %>%
  select(uuid_hex_pop, uuid_hex, pop_type, adm0_name, region, adm1_name, adm1_pcode,
         adm2_name, adm2_pcode, uuid, pop, pop_hh, estimated_households, geometry)
log_msg("  After pop_hh > 5 filter: %d eligible hexes, %.0f total pop_hh, %.0f total pop.",
        nrow(new_hexes_pop), sum(new_hexes_pop$pop_hh), sum(new_hexes_pop$pop))

# Attach the Mobbar Non-IDP stratum's own constant fields (clusters,
# certainty_stratum, selection_type, expected_households - stratum-level,
# not per-hex, so copied straight from the existing sample_plan row rather
# than recomputed) + MOS/total_MOS/psu_probability, matching build_sampling_
# plan()'s own sampling_frame construction exactly.
mob_plan_row <- non_idp_sampling$sample_plan %>% filter(pop_type == "non_idp", adm2_pcode == "NG008023")
stopifnot(nrow(mob_plan_row) == 1)

new_hexes_frame <- new_hexes_pop %>%
  mutate(
    clusters = mob_plan_row$clusters,
    certainty_stratum = mob_plan_row$certainty_stratum,
    selection_type = mob_plan_row$selection_type,
    expected_households = mob_plan_row$expected_households,
    MOS = pop_hh
  )
# total_MOS/psu_probability recomputed per (pop_type, adm2_pcode) group AFTER
# injection below, exactly as build_sampling_plan() does - not meaningful to
# set per-row here since it depends on the full post-injection Mobbar group.

# ---- Inject: append new hexes, then zero MOS on every OTHER Mobbar hex ----
# (the other 8 wards are excluded for an unrelated reason - accessibility_loss_
# below_population_threshold - explicit allow-list, not inferred.)
sf_cols <- names(non_idp_sampling$sampling_frame)
# total_MOS/psu_probability are computed AFTER injection (group_by/mutate
# below, exactly matching build_sampling_plan()'s own construction order) -
# not expected on new_hexes_frame yet at this point.
missing_cols <- setdiff(sf_cols, c(names(new_hexes_frame), "total_MOS", "psu_probability"))
if (length(missing_cols) > 0) stop("New hex frame missing columns present in non_idp_sampling$sampling_frame: ", paste(missing_cols, collapse = ", "))

injected <- bind_rows(
  non_idp_sampling$sampling_frame %>%
    mutate(MOS = if_else(adm2_pcode == "NG008023" & pop_type == "non_idp" & !(uuid_hex_pop %in% new_hexes_frame$uuid_hex_pop), 0, MOS)),
  new_hexes_frame %>% select(all_of(sf_cols[sf_cols %in% names(new_hexes_frame)]))
) %>%
  group_by(pop_type, adm2_pcode) %>%
  mutate(
    total_MOS = sum(MOS),
    psu_probability = case_when(
      first(certainty_stratum) ~ 1,
      TRUE ~ pmin(1, clusters * MOS / total_MOS)
    )
  ) %>%
  ungroup()

n_mob_eligible <- injected %>% filter(adm2_pcode == "NG008023", pop_type == "non_idp", MOS > 0) %>% nrow()
log_msg("  Injection complete: sampling_frame %d -> %d rows. Mobbar Non-IDP hexes with MOS>0 after injection: %d (should equal the %d new hexes exactly).",
        nrow(non_idp_sampling$sampling_frame), nrow(injected), n_mob_eligible, nrow(new_hexes_frame))
if (n_mob_eligible != nrow(new_hexes_frame)) stop("Mobbar's eligible-hex count after injection doesn't match the new-hex count - old wards not fully zeroed out.")

non_idp_sampling_filtered <- non_idp_sampling
non_idp_sampling_filtered$sampling_frame <- injected

# ---- Stage B: shortfall = full existing target (0 currently achievable in WORKING) ----
shortfalls <- tibble::tibble(pop_type = "non_idp", adm2_pcode = "NG008023", households_needed = mob_plan_row$expected_households)
log_msg("Stage B: shortfall = %d households (%d clusters) for non_idp_NG008023.", shortfalls$households_needed, shortfalls$households_needed / 6)

# already_used_hexagons: the 17 EXISTING live Mobbar hexes (already MOS=0 via
# injection above, so this is a redundant second safeguard, not load-bearing -
# kept anyway to match the standard script's own convention exactly).
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv", show_col_types = FALSE)
already_used_hex <- working %>% filter(pop_type == "non_idp") %>%
  mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  distinct(uuid_hex_pop) %>% pull(uuid_hex_pop)

# ---- Stage C: Tier 1 draw ----
log_msg("Stage C: Tier 1 draw (fresh hexes only)...")
tier1 <- add_supplementary_clusters(
  shortfalls = as.data.frame(shortfalls),
  already_used_hexagons = already_used_hex,
  non_idp_sampling = non_idp_sampling_filtered,
  building_data_dir = building_data_dir,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(STAGING_DIR, "cache_tier1_nonidp"),
  m = 6,
  seed = SEED_BASE + 1L,
  rebuild = FALSE
)
n_tier1_clusters <- if (is.null(tier1$new_clusters)) 0 else nrow(tier1$new_clusters)
log_msg("  Tier 1: %d new cluster(s) drawn", n_tier1_clusters)
if (!is.null(tier1$unresolved) && nrow(tier1$unresolved) > 0) {
  log_msg("  Tier 1 unresolved:"); print(tier1$unresolved)
}
saveRDS(tier1, file.path(STAGING_DIR, "tier1_result_nonidp.rds"))

# ---- Stage D: Tier 2 (repeat draws, only 16 hexes for 17 clusters so at least one repeat is expected) ----
if (!is.null(tier1$unresolved) && nrow(tier1$unresolved) > 0) {
  log_msg("Stage D: Tier 2 draw (repeat draws allowed)...")
  tier2_shortfalls <- tier1$unresolved %>%
    transmute(pop_type = sub("_NG.*$", "", strata_key), adm2_pcode = sub("^(non_idp|idp)_", "", strata_key), households_needed = households_still_needed)
  print(tier2_shortfalls)
  tier2 <- add_supplementary_clusters(
    shortfalls = as.data.frame(tier2_shortfalls),
    already_used_hexagons = character(0),
    non_idp_sampling = non_idp_sampling_filtered,
    building_data_dir = building_data_dir,
    wards = nga_wards,
    admin3 = NGA_shapes_all_cleaned$nga_admin3,
    mycrs = mycrs,
    cache_directory = file.path(STAGING_DIR, "cache_tier2_nonidp"),
    m = 6,
    seed = SEED_BASE + 2L,
    rebuild = FALSE
  )
  n_tier2_clusters <- if (is.null(tier2$new_clusters)) 0 else nrow(tier2$new_clusters)
  log_msg("  Tier 2: %d new cluster(s) drawn (repeat draws allowed)", n_tier2_clusters)
  if (!is.null(tier2$unresolved) && nrow(tier2$unresolved) > 0) {
    log_msg("  STILL unresolved after Tier 2:"); print(tier2$unresolved)
  }
  saveRDS(tier2, file.path(STAGING_DIR, "tier2_result_nonidp.rds"))
} else {
  log_msg("Stage D: nothing unresolved after Tier 1 - no Tier 2 needed.")
  tier2 <- list(new_clusters = NULL, new_households = NULL, unresolved = NULL)
}

# ---- Stage E: combine, dedupe same-hex-in-batch, renumber, verify (identical to draw_supplementary_clusters_batch.R) ----
if (!is.null(tier1$new_clusters)) { tier1$new_clusters$.source <- "tier1"; tier1$new_households$.source <- "tier1" }
if (!is.null(tier2$new_clusters)) { tier2$new_clusters$.source <- "tier2"; tier2$new_households$.source <- "tier2" }

log_msg("Stage E: combining results...")
all_new_clusters <- dplyr::bind_rows(tier1$new_clusters, tier2$new_clusters)
all_new_households <- dplyr::bind_rows(tier1$new_households, tier2$new_households)

if (nrow(all_new_clusters) == 0) {
  log_msg("==== DONE. 0 new cluster(s) drawn. ====")
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_clusters.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_households.csv"))
  close(log_con)
  quit(save = "no", status = 0)
}

hex_dup_counts <- all_new_clusters %>% sf::st_drop_geometry() %>%
  dplyr::count(uuid_hex_pop, name = "n_in_batch") %>% dplyr::filter(n_in_batch > 1)

if (nrow(hex_dup_counts) > 0) {
  affected_hexes <- hex_dup_counts$uuid_hex_pop
  log_msg("Stage E.1: %d hex(es) drawn more than once within this batch - merging each into one cluster, redrawn fresh.", length(affected_hexes))
  cache_dirs <- c(file.path(STAGING_DIR, "cache_tier1_nonidp", "final_buildings"), file.path(STAGING_DIR, "cache_tier2_nonidp", "final_buildings"))
  bfiles <- unlist(lapply(cache_dirs, function(d) list.files(d, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE)))
  building_pool_by_hex <- purrr::map(bfiles, function(bf) {
    part <- tryCatch(readRDS(bf), error = function(e) NULL)
    if (is.null(part) || nrow(part) == 0) return(NULL)
    part <- part %>% dplyr::filter(uuid_hex_pop %in% affected_hexes)
    if (nrow(part) == 0) return(NULL)
    coords <- sf::st_coordinates(part)
    part %>% dplyr::mutate(.centroid_key = paste0(round(coords[, "X"], 1), "_", round(coords[, "Y"], 1)))
  }) %>% purrr::compact() %>% dplyr::bind_rows() %>%
    dplyr::distinct(uuid_hex_pop, .centroid_key, .keep_all = TRUE)

  clusters_untouched <- all_new_clusters %>% dplyr::filter(!(uuid_hex_pop %in% affected_hexes))
  hh_ids_to_drop_df <- all_new_clusters %>% sf::st_drop_geometry() %>%
    dplyr::filter(uuid_hex_pop %in% affected_hexes) %>% dplyr::select(.source, cluster_id)
  households_untouched <- all_new_households %>% dplyr::anti_join(hh_ids_to_drop_df, by = c(".source", "cluster_id"))

  merged_cluster_rows <- list(); merged_household_rows <- list()
  for (hx in affected_hexes) {
    grp <- all_new_clusters %>% dplyr::filter(uuid_hex_pop == hx)
    grp_df <- sf::st_drop_geometry(grp)
    merged_target <- sum(grp_df$target_households); merged_reserve <- sum(grp_df$reserve_households); merged_selection_count <- sum(grp_df$selection_count)
    pool_hx <- building_pool_by_hex %>% dplyr::filter(uuid_hex_pop == hx)
    keep_row <- grp[1, ]
    keep_row$target_households <- merged_target; keep_row$reserve_households <- merged_reserve; keep_row$selection_count <- merged_selection_count
    keep_row$.source <- "merged"
    new_id <- keep_row$cluster_id[[1]]
    drawn <- draw_cluster(pool_hx, merged_target, merged_reserve)
    log_msg("  hex %s: merged %d cluster(s) into %s (target %d + reserve %d) - %d real building(s) in pool, %s",
            hx, nrow(grp_df), new_id, merged_target, merged_reserve, nrow(pool_hx), if (is.null(drawn)) "0 drawn" else paste0(nrow(drawn), " drawn"))
    if (!is.null(drawn) && nrow(drawn) > 0) {
      drawn$cluster_id <- new_id
      hh_final <- finalize_households(drawn, keep_row, nga_wards, NGA_shapes_all_cleaned$nga_admin3, mycrs)
      hh_final$.source <- "merged"
      merged_household_rows[[hx]] <- hh_final
    }
    merged_cluster_rows[[hx]] <- keep_row
  }
  all_new_clusters <- dplyr::bind_rows(clusters_untouched, dplyr::bind_rows(merged_cluster_rows))
  all_new_households <- dplyr::bind_rows(households_untouched, dplyr::bind_rows(merged_household_rows))

  still_dup_hexes <- all_new_clusters %>% sf::st_drop_geometry() %>% dplyr::count(uuid_hex_pop, name = "n") %>% dplyr::filter(n > 1)
  if (nrow(still_dup_hexes) > 0) stop("Stage E.1 merge failed - hexes still duplicated: ", paste(still_dup_hexes$uuid_hex_pop, collapse = ", "))
  dup_bids <- all_new_households %>% dplyr::filter(!is.na(building_id)) %>% dplyr::count(cluster_id, building_id) %>% dplyr::filter(n > 1)
  if (nrow(dup_bids) > 0) stop("Stage E.1 merge produced a cluster with the SAME building assigned twice: ", paste(dup_bids$cluster_id, collapse = ", "))
  log_msg("  Verified: no hex appears more than once, no cluster has a duplicate building_id.")
} else {
  log_msg("Stage E.1: no hex was drawn more than once within this batch - nothing to merge.")
}

all_new_clusters <- all_new_clusters %>% dplyr::mutate(.old_cluster_id = cluster_id, .row_key = dplyr::row_number())
existing_ids <- working$cluster_id
id_map <- all_new_clusters %>%
  sf::st_drop_geometry() %>%
  dplyr::select(.row_key, .source, .old_cluster_id, pop_type, adm2_pcode) %>%
  dplyr::mutate(strata_key = paste0(pop_type, "_", adm2_pcode)) %>%
  dplyr::group_by(strata_key) %>%
  dplyr::mutate(.rank_in_batch = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  dplyr::rowwise() %>%
  dplyr::mutate(.existing_max = {
    existing_supp <- existing_ids[grepl(paste0("^", strata_key, "_supp[0-9]+$"), existing_ids)]
    if (length(existing_supp) > 0) max(as.integer(sub(".*_supp", "", existing_supp))) else 0L
  }) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(new_cluster_id = paste0(strata_key, "_supp", .existing_max + .rank_in_batch))
log_msg("  Renumbered %d new cluster(s), continuing the real existing _supp sequence.", nrow(id_map))

all_new_clusters <- all_new_clusters %>%
  dplyr::left_join(id_map %>% dplyr::select(.row_key, new_cluster_id), by = ".row_key") %>%
  dplyr::mutate(cluster_id = new_cluster_id) %>%
  dplyr::select(-.row_key, -new_cluster_id)

all_new_households <- all_new_households %>%
  dplyr::left_join(id_map %>% dplyr::select(.source, .old_cluster_id, new_cluster_id), by = c(".source" = ".source", "cluster_id" = ".old_cluster_id"))
.suffix <- substring(all_new_households$survey_id, nchar(all_new_households$cluster_id) + 1)
all_new_households <- all_new_households %>%
  dplyr::mutate(survey_id = paste0(new_cluster_id, .suffix), cluster_id = new_cluster_id) %>%
  dplyr::select(-new_cluster_id)

still_colliding <- intersect(all_new_clusters$cluster_id, existing_ids)
if (length(still_colliding) > 0) stop("Collision fix failed: ", paste(still_colliding, collapse = ", "))
dup_within_new <- all_new_clusters$cluster_id[duplicated(all_new_clusters$cluster_id)]
if (length(dup_within_new) > 0) stop("Duplicate cluster_id WITHIN the new batch: ", paste(unique(dup_within_new), collapse = ", "))
if (any(is.na(all_new_clusters$cluster_id)) || any(is.na(all_new_households$cluster_id))) stop("NA cluster_id after renumbering.")
if (!setequal(unique(all_new_clusters$cluster_id), unique(all_new_households$cluster_id))) stop("Cluster IDs in new_clusters/new_households disagree.")
log_msg("  Verified: %d new cluster_id(s), all unique, zero collisions with the live frame.", nrow(all_new_clusters))

existing_bids_by_hex <- working %>% dplyr::filter(pop_type == "non_idp", !is.na(building_id)) %>%
  dplyr::mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>%
  dplyr::group_by(uuid_hex_pop) %>% dplyr::summarise(existing_bids = list(unique(building_id)), .groups = "drop")
new_bids_by_cluster <- all_new_households %>% dplyr::filter(!is.na(building_id)) %>%
  dplyr::left_join(st_drop_geometry(all_new_clusters) %>% dplyr::select(cluster_id, uuid_hex_pop), by = "cluster_id") %>%
  dplyr::group_by(cluster_id, uuid_hex_pop) %>% dplyr::summarise(new_bids = list(unique(building_id)), .groups = "drop") %>%
  dplyr::inner_join(existing_bids_by_hex, by = "uuid_hex_pop")
if (nrow(new_bids_by_cluster) > 0) {
  overlap_check <- new_bids_by_cluster %>% dplyr::rowwise() %>% dplyr::mutate(n_overlap = length(intersect(new_bids, existing_bids))) %>% dplyr::ungroup() %>% dplyr::filter(n_overlap > 0)
  log_msg("  Checked %d new cluster(s) sharing a hex with an existing live-frame cluster - %d have a real building_id overlap.", nrow(new_bids_by_cluster), nrow(overlap_check))
  if (nrow(overlap_check) > 0) stop("Real building_id overlap found - do not merge: ", paste(overlap_check$cluster_id, collapse = ", "))
}

st_write(all_new_clusters, file.path(STAGING_DIR, "new_clusters.gpkg"), delete_layer = TRUE, quiet = TRUE)
write_csv(st_drop_geometry(all_new_households), file.path(STAGING_DIR, "new_households.csv"))
write_csv(st_drop_geometry(all_new_clusters), file.path(STAGING_DIR, "new_clusters.csv"))
summary_by_strata <- st_drop_geometry(all_new_clusters) %>% group_by(strata_id, adm2_pcode) %>%
  summarise(new_clusters = n(), new_households = sum(target_households), .groups = "drop")
write_csv(summary_by_strata, file.path(STAGING_DIR, "summary_by_stratum.csv"))

log_msg("==== DONE. %d total new cluster(s), %d new household row(s). ====", nrow(all_new_clusters), nrow(all_new_households))
log_msg("Staged in: %s. NOT merged into the live WORKING/FULL frame.", STAGING_DIR)
close(log_con)
