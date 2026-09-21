# ==============================================================================
# INTERSOS / Magumeri (Borno) - Kareram + Hoyo Chingua supplementary draw,
# 2026-09-14.
#
# Context: INTERSOS's own _1409 accessibility-follow-up email (not the
# attached spreadsheet - the email body itself) states "While most locations
# in Magumeri are currently inaccessible, Kareram and Hoyo wards are
# accessible; however, these two wards were not included in the clustering
# for this exercise." Confirmed directly before building this: both are real
# GRID3 wards within Magumeri (Hoyo Chingua ~37,100 / Kareram ~12,400 WorldPop
# population), and BOTH already sit inside Stage 1's accessible_hex candidate
# grid (the Non-IDP eligibility test in accessible_area_lga_ward_portions.csv
# passes for both) - unlike Abadam/Guzamala's MSNA Light settlements, this is
# NOT a ward-boundary-location problem needing a hand-drawn urban extent; it's
# the plain "eligible the whole time, never happened to get drawn" case Jack
# himself flagged as the likely explanation.
#
# Scope decision (Jack: "we should offer the opportunity for partners to
# collect there if we can" - go the full build): Magumeri's Non-IDP stratum
# (non_idp_NG008020) is already close to its statistically-saturated target
# (102 households / 17 clusters - N_hh=57,820 already saturates the MoE
# formula regardless of exactly how much of that includes Kareram/Hoyo, same
# behaviour seen for Maru/Mayanchi the same night) - currently at 96/16
# clusters, a 1-cluster (6hh) shortfall that predates and is unrelated to
# these 2 wards specifically. Rather than draw 1 more cluster LGA-wide (which
# could land anywhere accessible in Magumeri, not necessarily Kareram/Hoyo -
# the exact "included in theory, still invisible in practice" gap INTERSOS
# is flagging), this draws ONE cluster in EACH of the two wards specifically
# (2 clusters / 12 households total) - a small, deliberate, easily-justified
# 1-cluster departure above the pure statistical target (same "achieved
# slightly over target - expected and fine" pattern already accepted
# elsewhere in this project), guaranteeing both wards get real, visitable
# points rather than leaving it to LGA-wide PPS chance.
#
# Mechanism: same add_supplementary_clusters() used by every partner's
# supplementary Non-IDP draw this round (draw_supplementary_clusters_batch.R)
# - NOT Mobbar's "Stage A0 inject brand-new hexes" pattern, since these hexes
# already exist in non_idp_sampling$sampling_frame (no injection needed).
# The one structural difference from the standard script: an ALLOW-LIST
# restriction (zero MOS on every OTHER Magumeri Non-IDP hex) rather than the
# standard ward-INaccessibility EXCLUDE-list - two separate restricted draws,
# one per ward, so PPS can't accidentally put both new clusters in the larger
# of the two (Hoyo Chingua, ~3x Kareram's population) and leave the other
# untouched.
#
# STAGING ONLY - writes to resampling/output/resample_runs/INTERSOS/
# 2026-09-14_kareram_hoyo/, does NOT touch the live WORKING/FULL frame. A
# separate, explicit merge step (after review) does that.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
source("resampling/scripts/shared/resolve_staging_dir.R")
STAGING_DIR <- resolve_staging_dir("INTERSOS", suffix = "kareram_hoyo")
SEED_BASE <- 90914L
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(STAGING_DIR, "run_log.txt"), open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== INTERSOS Kareram + Hoyo Chingua supplementary draw - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

# ---- Stage A: source the deterministic pipeline prefix (no set.seed before line 1194) ----
log_msg("Stage A: sourcing pipeline prefix through build_sampling_plan()...")
lines <- readLines("scripts/01_sampling_pipeline_main.R")
writeLines(lines[1:1002], "temp_kareram_hoyo_draw_prefix.R")
source("temp_kareram_hoyo_draw_prefix.R")
file.remove("temp_kareram_hoyo_draw_prefix.R")
log_msg("  non_idp_sampling$sampling_frame: %d rows", nrow(non_idp_sampling$sampling_frame))

source("scripts/02_stage2_building_ingestion.R")
source("scripts/03_stage2_household_selection.R")
source("scripts/04_stage2_cluster_reallocation.R")

building_data_dir <- file.path("C:/Users/JackPHILPOTT/Personal - Documents/GIS", "Google_Open_Buildings")
library(dplyr); library(sf); library(readr)
nga_wards <- sf::st_read(
  here::here("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
) %>% st_transform(mycrs)

# ---- Stage B: real building-footprint check, matching the settlement-
# legitimacy verification precedent (Abadam/Mairari/Mobbar) - confirms these
# are genuine, dense settlements before drawing anything, not just a raster
# population estimate. ----
log_msg("Stage B: real Google Open Buildings footprint check for both wards...")
magumeri_hexes_all <- non_idp_sampling$sampling_frame %>% filter(adm2_pcode == "NG008020", pop_type == "non_idp")
ward_targets <- nga_wards %>% filter(wardname %in% c("Kareram", "Hoyo Chingua"))
stopifnot(nrow(ward_targets) == 2)

hex_centroids_all <- st_centroid(magumeri_hexes_all %>% select(uuid_hex, uuid_hex_pop, pop_hh))
hex_ward_join <- st_join(hex_centroids_all, ward_targets["wardname"], join = st_within) %>%
  st_drop_geometry() %>% filter(!is.na(wardname))
log_msg("  Magumeri Non-IDP hexes whose centroid falls in Kareram/Hoyo Chingua: %d (%s)",
        nrow(hex_ward_join), paste(table(hex_ward_join$wardname), names(table(hex_ward_join$wardname)), collapse = "; "))
for (w in c("Kareram", "Hoyo Chingua")) {
  hx_ids <- hex_ward_join %>% filter(wardname == w) %>% pull(uuid_hex_pop)
  log_msg("    %s: %d candidate hex(es), %.0f total pop_hh (WorldPop-derived)", w, length(hx_ids),
          sum(magumeri_hexes_all$pop_hh[magumeri_hexes_all$uuid_hex_pop %in% hx_ids]))
}

# ---- Stage C: two separate restricted draws, one per ward (allow-list: MOS
# zeroed on every hex outside the target ward), 1 cluster (6 households)
# each. ----
draw_one_ward <- function(ward_name, tag, seed) {
  log_msg("Stage C.%s: restricted draw for %s (allow-list, 1 cluster / 6 households)...", tag, ward_name)
  ward_hex_ids <- hex_ward_join %>% filter(wardname == ward_name) %>% pull(uuid_hex_pop)
  if (length(ward_hex_ids) == 0) {
    log_msg("  WARNING: 0 candidate hexes for %s - cannot draw, skipping.", ward_name)
    return(list(new_clusters = NULL, new_households = NULL, unresolved = NULL))
  }
  sampling_restricted <- non_idp_sampling
  sampling_restricted$sampling_frame <- non_idp_sampling$sampling_frame %>%
    mutate(MOS = if_else(adm2_pcode == "NG008020" & pop_type == "non_idp" & !(uuid_hex_pop %in% ward_hex_ids), 0, MOS))
  n_eligible <- sum(sampling_restricted$sampling_frame$adm2_pcode == "NG008020" &
                       sampling_restricted$sampling_frame$pop_type == "non_idp" &
                       sampling_restricted$sampling_frame$MOS > 0)
  log_msg("  %d hex(es) with MOS>0 after restriction (should equal %d candidate hexes for %s).", n_eligible, length(ward_hex_ids), ward_name)

  working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv", show_col_types = FALSE)
  already_used_hex <- working %>% filter(pop_type == "non_idp") %>%
    mutate(uuid_hex_pop = paste0(pop_type, "_", uuid_hex)) %>% distinct(uuid_hex_pop) %>% pull(uuid_hex_pop)

  shortfall <- data.frame(pop_type = "non_idp", adm2_pcode = "NG008020", households_needed = 6)
  res <- add_supplementary_clusters(
    shortfalls = shortfall,
    already_used_hexagons = already_used_hex,
    non_idp_sampling = sampling_restricted,
    building_data_dir = building_data_dir,
    wards = nga_wards,
    admin3 = NGA_shapes_all_cleaned$nga_admin3,
    mycrs = mycrs,
    cache_directory = file.path(STAGING_DIR, paste0("cache_", tag)),
    m = 6,
    seed = seed,
    rebuild = FALSE
  )
  n_clusters <- if (is.null(res$new_clusters)) 0 else nrow(res$new_clusters)
  log_msg("  %s: %d new cluster(s) drawn", ward_name, n_clusters)
  if (!is.null(res$unresolved) && nrow(res$unresolved) > 0) {
    log_msg("  %s unresolved:", ward_name); print(res$unresolved)
  }
  if (!is.null(res$new_clusters)) { res$new_clusters$.source <- tag; res$new_households$.source <- tag }
  res
}

kareram_res <- draw_one_ward("Kareram", "kareram", SEED_BASE + 1L)
hoyo_res <- draw_one_ward("Hoyo Chingua", "hoyo", SEED_BASE + 2L)

log_msg("Stage D: combining both wards' results...")
all_new_clusters <- dplyr::bind_rows(kareram_res$new_clusters, hoyo_res$new_clusters)
all_new_households <- dplyr::bind_rows(kareram_res$new_households, hoyo_res$new_households)

if (nrow(all_new_clusters) == 0) {
  log_msg("==== DONE. 0 new cluster(s) drawn. ====")
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_clusters.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_households.csv"))
  close(log_con)
  quit(save = "no", status = 0)
}

# ---- Stage D.1: same-hex-within-batch dedupe (identical pattern to the
# standard script - kept for safety even though 2 separate wards means this
# is not expected to fire). ----
hex_dup_counts <- all_new_clusters %>% sf::st_drop_geometry() %>%
  dplyr::count(uuid_hex_pop, name = "n_in_batch") %>% dplyr::filter(n_in_batch > 1)
if (nrow(hex_dup_counts) > 0) {
  stop("Unexpected: a hex was drawn in both the Kareram and Hoyo Chingua restricted draws - investigate before proceeding: ",
       paste(hex_dup_counts$uuid_hex_pop, collapse = ", "))
} else {
  log_msg("Stage D.1: no hex drawn more than once across the two wards - as expected, nothing to merge.")
}

empty_cluster_ids <- setdiff(unique(all_new_clusters$cluster_id), unique(all_new_households$cluster_id))
if (length(empty_cluster_ids) > 0) {
  log_msg("  Dropping %d cluster(s) that were added as candidates but yielded zero real households: %s",
          length(empty_cluster_ids), paste(empty_cluster_ids, collapse = ", "))
  all_new_clusters <- all_new_clusters %>% dplyr::filter(!(cluster_id %in% empty_cluster_ids))
}

# ---- Stage E: renumber cluster IDs, continuing the real _supp sequence, verify ----
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv", show_col_types = FALSE)
existing_ids <- working$cluster_id

all_new_clusters <- all_new_clusters %>% dplyr::mutate(.old_cluster_id = cluster_id, .row_key = dplyr::row_number())
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
log_msg("Stage E: renumbered %d new cluster(s), continuing the real existing _supp sequence.", nrow(id_map))

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
summary_by_strata <- st_drop_geometry(all_new_clusters) %>% group_by(strata_id, adm2_pcode, .source) %>%
  summarise(new_clusters = n(), new_households = sum(target_households), .groups = "drop")
write_csv(summary_by_strata, file.path(STAGING_DIR, "summary_by_stratum.csv"))

log_msg("==== DONE. %d total new cluster(s), %d new household row(s). ====", nrow(all_new_clusters), nrow(all_new_households))
log_msg("Staged in: %s. NOT merged into the live WORKING/FULL frame.", STAGING_DIR)
close(log_con)
