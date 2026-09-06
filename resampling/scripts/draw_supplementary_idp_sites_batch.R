# ==============================================================================
# Site-level IDP supplementary draw - Option B mechanism (decided 2026-09-02,
# see project memory "IDP site-level PSU redesign" / "The IDP Hex Problem").
#
# Sibling to draw_supplementary_idp_clusters_batch.R (the hex-based
# mechanism, kept unchanged and still authoritative for every already-
# fielded IDP cluster) - this is its replacement for all NEW IDP draws
# going forward. The PSU is now the individual, deduped DTM site itself
# (build_idp_site_level_psu_2026-09-02.R's output) - PPS-weighted by that
# site's own household count, no hex, no "largest site in the hex wins"
# resolution step. Because the PSU already IS the final visited location,
# this script is meaningfully SIMPLER than the hex version: no
# select_stage2_idp_sites()-style site-matching/collapsing stage, no
# n_other_sites_in_hex bookkeeping - what gets drawn is what gets visited.
#
# STAGING ONLY - writes to resampling/output/resample_runs/<date>/, does NOT
# touch the live WORKING/FULL frame. Every new cluster gets
# psu_definition_version = "site_v2" (vs "hex_v1" for every existing IDP
# cluster) so weighting at analysis time can branch correctly per cluster -
# see the project memory above for why this column matters.
#
# Usage: Rscript draw_supplementary_idp_sites_batch.R <shortfalls_idp_csv> <staging_dir> <seed_base>
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) stop("Usage: Rscript draw_supplementary_idp_sites_batch.R <shortfalls_idp_csv> <staging_dir> <seed_base>")
SHORTFALLS_IDP_CSV <- args[1]
STAGING_DIR <- args[2]
SEED_BASE <- as.integer(args[3])
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(STAGING_DIR, "run_log_idp_sitelevel.txt"), open = "wt")
log_msg <- function(...) { msg <- sprintf(...); cat(msg, "\n"); cat(msg, "\n", file = log_con) }
log_msg("==== Site-level IDP supplementary draw run (Option B) - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

suppressMessages({ library(dplyr); library(sf); library(readr); library(purrr) })
sf::sf_use_s2(FALSE)
mycrs <- 31028

# ---- Stage A: load the site-level PSU frame + shortfalls ----
site_frame <- readRDS("input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds") %>%
  st_transform(mycrs)
log_msg("Site-level PSU candidate frame: %d sites nationally.", nrow(site_frame))

shortfalls <- read_csv(SHORTFALLS_IDP_CSV, show_col_types = FALSE) %>%
  transmute(adm2_pcode = adm2_pcode, households_needed = additional_clusters_needed * 6)
log_msg("%d stratum/strata in shortfalls, %d total households needed.", nrow(shortfalls), sum(shortfalls$households_needed))

# ---- Stage B: exclude already-used sites (both mechanisms) + inaccessible wards ----
# "Already used" must catch sites drawn under EITHER the old hex mechanism
# (matched by proximity, since old clusters carry no uuid_site) or this new
# one (matched by uuid_site_pop directly, once any exist). Proximity match
# uses the same site-identity logic as select_stage2_idp_sites()'s own
# 30m dedup radius - a live cluster's GPS point within 30m of a candidate
# site is the same physical site already fielded.
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv", show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  filter(pop_type == "idp") %>%
  mutate(latitude = as.numeric(latitude), longitude = as.numeric(longitude)) %>%
  distinct(cluster_id, latitude, longitude)
live_idp_pts <- st_as_sf(full, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>% st_transform(mycrs)

nearest_dist <- st_distance(site_frame, st_union(st_geometry(live_idp_pts)))
already_used <- as.numeric(nearest_dist) <= 30
log_msg("Stage B: %d of %d candidate sites already fielded under the existing (hex-based) mechanism - excluded from redraw (matched by GPS proximity, 30m).", sum(already_used), nrow(site_frame))

candidate_pool <- site_frame %>%
  mutate(already_used_flag = already_used) %>%
  filter(!already_used_flag, accessible_status != "Inaccessible", adm2_pcode %in% shortfalls$adm2_pcode)
log_msg("Stage B complete: %d fresh, accessible candidate site(s) remain across the %d shortfall LGA(s).", nrow(candidate_pool), n_distinct(shortfalls$adm2_pcode))

# ---- Stage C: PPS-weighted-without-replacement draw, per stratum, Tier 1 (fresh) then Tier 2 (repeat allowed within THIS batch's own already-drawn sites) ----
draw_sites <- function(shortfalls_df, pool, seed) {
  set.seed(seed)
  purrr::map_dfr(seq_len(nrow(shortfalls_df)), function(i) {
    row <- shortfalls_df[i, ]
    this_pool <- pool %>% filter(adm2_pcode == row$adm2_pcode)
    n_needed <- ceiling(row$households_needed / 6)
    if (nrow(this_pool) == 0 || n_needed == 0) return(NULL)
    ordered <- this_pool[sample.int(nrow(this_pool), size = nrow(this_pool), prob = this_pool$pop_hh), ]
    ordered[seq_len(min(n_needed, nrow(ordered))), ] %>%
      mutate(n_drawn_this_stratum = min(n_needed, nrow(ordered)), n_needed_this_stratum = n_needed)
  })
}
is_empty <- function(x) is.null(x) || nrow(x) == 0

log_msg("Stage C: Tier 1 (fresh sites) draw...")
tier1 <- draw_sites(shortfalls, candidate_pool, seed = SEED_BASE + 1L)
log_msg("  Tier 1: %d site(s) drawn.", if (is_empty(tier1)) 0 else nrow(tier1))

tier1_drawn_by_stratum <- if (is_empty(tier1)) {
  tibble::tibble(adm2_pcode = character(0), n_drawn_this_stratum = integer(0))
} else {
  tier1 %>% st_drop_geometry() %>% distinct(adm2_pcode, n_drawn_this_stratum)
}
shortfall_check <- shortfalls %>%
  mutate(n_needed_this_stratum = ceiling(households_needed / 6)) %>%
  left_join(tier1_drawn_by_stratum, by = "adm2_pcode") %>%
  mutate(n_drawn_this_stratum = coalesce(n_drawn_this_stratum, 0L))
print(shortfall_check)

unresolved <- shortfall_check %>% filter(n_drawn_this_stratum < n_needed_this_stratum)
if (nrow(unresolved) > 0) {
  log_msg("  %d stratum/strata still short after Tier 1 - trying Tier 2 (repeat draws allowed, same-batch sites eligible again)...", nrow(unresolved))
  tier2_shortfalls <- unresolved %>%
    mutate(households_needed = (n_needed_this_stratum - n_drawn_this_stratum) * 6) %>%
    select(adm2_pcode, households_needed)
  tier2 <- draw_sites(tier2_shortfalls, candidate_pool, seed = SEED_BASE + 2L)
  log_msg("  Tier 2: %d site(s) drawn.", if (is_empty(tier2)) 0 else nrow(tier2))
} else {
  tier2 <- NULL
  log_msg("  Nothing unresolved after Tier 1 - no Tier 2 needed.")
}

all_sites <- dplyr::bind_rows(Filter(function(x) !is_empty(x), list(tier1, tier2)))
final_check <- shortfalls %>%
  left_join(
    if (is_empty(all_sites)) tibble::tibble(adm2_pcode = character(0), n_sites = integer(0))
    else all_sites %>% st_drop_geometry() %>% count(adm2_pcode, name = "n_sites"),
    by = "adm2_pcode"
  ) %>%
  mutate(n_sites = coalesce(n_sites, 0L), n_hh_covered = n_sites * 6,
         n_needed = ceiling(households_needed / 6) * 6, fully_closed = n_hh_covered >= n_needed)
log_msg("Final closure: %d of %d strata fully closed.", sum(final_check$fully_closed), nrow(final_check))
print(final_check %>% select(adm2_pcode, n_sites, n_hh_covered, n_needed, fully_closed))
if (any(!final_check$fully_closed)) {
  short <- final_check %>% filter(!fully_closed)
  log_msg("  Still short (candidate site pool genuinely exhausted under current DTM data): %s",
          paste(sprintf("%s (needs %d more hh)", short$adm2_pcode, short$n_needed - short$n_hh_covered), collapse = "; "))
}

log_msg("Stage C complete: %d total new IDP site(s) selected.", nrow(all_sites))

if (nrow(all_sites) == 0) {
  log_msg("==== DONE. 0 sites drawn - every shortfall LGA's candidate pool was already exhausted or inaccessible. ====")
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_clusters_idp_sitelevel.csv"))
  write_csv(tibble::tibble(), file.path(STAGING_DIR, "new_households_idp_sitelevel.csv"))
  close(log_con)
  quit(save = "no", status = 0)
}

# ---- Stage D: build cluster + household rows directly - no site-resolution step needed, the drawn row IS the site ----
# Collapse repeat draws of the SAME site (uuid_site_pop) - possible whenever
# Tier 2 (repeat-allowed) redraws a site Tier 1 already picked in this same
# batch, or a stratum's shortfall needs more households than distinct fresh
# sites exist. Mirrors merge_repeated_psu_draws()'s own collapsing step for
# the hex-based mechanism (group by PSU key, keep one row, selection_count
# = n()) - missing this exact step here first produced 4 duplicate-site
# cluster_ids in the Funtua/2026-09-02 test run (Layin Hassan Basa, Ammani
# Road, Unguwar Mata, Unguwar Dutse each drawn twice as SEPARATE cluster_ids
# instead of one cluster with selection_count=2) - the precise class of bug
# already found and fixed once tonight in the live frame (idp_NG021001_9/
# _supp1, Nadabo Primary School Camp) - not repeating it here.
all_sites <- all_sites %>%
  mutate(.orig_row = row_number()) %>%
  group_by(uuid_site_pop) %>%
  mutate(selection_count = n()) %>%
  slice_min(.orig_row, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(
    strata_id = paste0("idp_", adm2_pcode),
    target_households = 6L * selection_count,
    reserve_households = 6L * selection_count,
    cluster_id_temp = paste0(strata_id, "_TEMPSITE", .orig_row)
  )

# Renumber continuing each stratum's real existing _supp sequence (identical pattern to the hex-based script)
existing_ids <- full$cluster_id
id_map <- all_sites %>% st_drop_geometry() %>%
  distinct(cluster_id_temp, strata_id, .keep_all = TRUE) %>%
  group_by(strata_id) %>% mutate(.rank_in_batch = row_number()) %>% ungroup() %>%
  rowwise() %>%
  mutate(.existing_max = {
    existing_supp <- existing_ids[grepl(paste0("^", strata_id, "_supp[0-9]+$"), existing_ids)]
    if (length(existing_supp) > 0) max(as.integer(sub(".*_supp", "", existing_supp))) else 0L
  }) %>% ungroup() %>%
  mutate(new_cluster_id = paste0(strata_id, "_supp", .existing_max + .rank_in_batch)) %>%
  select(cluster_id_temp, new_cluster_id)

all_sites <- all_sites %>% left_join(id_map, by = "cluster_id_temp") %>%
  mutate(cluster_id = new_cluster_id)

still_colliding <- intersect(all_sites$cluster_id, existing_ids)
if (length(still_colliding) > 0) stop("Collision with live frame: ", paste(still_colliding, collapse = ", "))
if (anyDuplicated(all_sites$cluster_id) > 0) stop("Duplicate cluster_id within this batch.")
log_msg("Stage D: renumbered %d new site-level cluster(s) across %d strata, continuing each stratum's real _supp sequence. Verified: zero collisions, zero within-batch duplicates.",
        n_distinct(all_sites$cluster_id), n_distinct(all_sites$strata_id))

build_slots <- function(cid, target_hh, reserve_n) {
  bind_rows(
    tibble::tibble(cluster_id = cid, status = "primary", interview_number = seq_len(target_hh), replacement_rank = NA_integer_),
    tibble::tibble(cluster_id = cid, status = "reserve", interview_number = NA_integer_, replacement_rank = seq_len(reserve_n))
  )
}
clusters_df <- all_sites %>% st_drop_geometry() %>% distinct(cluster_id, .keep_all = TRUE)
household_slots <- purrr::pmap(
  list(clusters_df$cluster_id, clusters_df$target_households, clusters_df$reserve_households),
  build_slots
) %>% bind_rows()

# Attach adm3_name/adm3_pcode (GRID3) and admin3_cod_pcode/admin3_cod_name
# (official COD boundary) via the SAME two-step spatial join
# finalize_households() itself uses (03_stage2_household_selection.R lines
# ~524-555) - do not trust the PSU frame's own DTM-self-reported `ward`
# text field for this (known unreliable - see the Funtua "Maska"/
# "Nasarawa" GRID3-vs-DTM naming mismatch already documented elsewhere in
# this project). Kept as its own light join here rather than depending on
# the PSU frame already carrying it, since the PSU frame's `ward`/
# `accessible_status` join was built for accessibility-status matching,
# not the official adm3 attribution downstream consumers expect.
nga_wards <- sf::st_read(
  file.path("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
) %>% st_transform(mycrs) %>% select(adm3_pcode = wardcode, adm3_name = wardname) %>% mutate(admin3_source = "GRID3")

nga_admin3_cod <- sf::st_read(
  file.path("input_data", "boundaries", "nga_admin_boundaries", "nga_admin3.shp"),
  quiet = TRUE
) %>% st_transform(mycrs) %>% select(admin3_cod_pcode = adm3_pcode, admin3_cod_name = adm3_name)

sites_unique <- all_sites %>% distinct(cluster_id, .keep_all = TRUE)
sites_unique <- st_join(sites_unique, nga_wards, join = st_within, left = TRUE)
sites_unique <- st_join(sites_unique, nga_admin3_cod, join = st_within, left = TRUE)

geom_lookup <- sites_unique %>% st_transform(4326) %>%
  mutate(longitude = st_coordinates(.)[,1], latitude = st_coordinates(.)[,2]) %>%
  st_drop_geometry() %>%
  select(cluster_id, latitude, longitude, adm3_pcode, adm3_name, admin3_source, admin3_cod_pcode, admin3_cod_name)
log_msg("Attached GRID3 ward + COD admin3 via spatial join for %d cluster(s) - %d unmatched to a GRID3 ward, %d unmatched to a COD admin3 (both left NA, same as finalize_households()'s own left_join behaviour for an edge-of-boundary point).",
        nrow(geom_lookup), sum(is.na(geom_lookup$adm3_name)), sum(is.na(geom_lookup$admin3_cod_name)))

households <- household_slots %>%
  left_join(clusters_df %>% select(cluster_id, adm2_pcode, adm2_name, adm1_name, adm1_pcode, region, strata_id,
                                     site_id_ssid, site_name, site_type, ward, idp_population_category,
                                     pop, pop_hh, uuid_site, uuid_site_pop, target_households, reserve_households,
                                     selection_count, accessible_status),
            by = "cluster_id") %>%
  left_join(geom_lookup, by = "cluster_id") %>%
  mutate(
    survey_id = if_else(status == "primary", sprintf("%s_HH%02d", cluster_id, interview_number), sprintf("%s_R%02d", cluster_id, replacement_rank)),
    pop_type = "idp",
    households_in_cluster = pop_hh,
    below_target_cluster = pop_hh < target_households,
    location_source = "idp_site_point_v2",
    households_in_cluster_source = "DTM_estimate_provisional",
    site_radius_m = 150,
    building_id = NA_character_, confidence = NA_real_, building_area_m2 = NA_real_,
    psu_definition_version = "site_v2",
    # adm3_name/adm3_pcode/admin3_source/admin3_cod_* already came in via
    # the geom_lookup join above (real GRID3 + COD spatial joins) -
    # deliberately NOT overwritten with DTM's raw `ward` text field here.
    iom_site_id = site_id_ssid, iom_site_name = site_name, iom_site_type = site_type, iom_site_ward = ward,
    ward_accessible_status = accessible_status,
    n_other_sites_in_hex = 0L, uuid_hex = uuid_site, uuid_hex_pop = uuid_site_pop,
    # Matches the existing convention already on every hex-based
    # supplementary IDP cluster (checked directly: 13 existing "_supp*"
    # IDP clusters all carry selection_type="pps", supplementary_cluster=
    # FALSE, reallocated=FALSE - not TRUE/NA as the naming might suggest;
    # this project's supplementary-cluster flags were never wired up for
    # IDP the way add_supplementary_clusters() does for Non-IDP - see
    # resampling/README.md's "No add_supplementary_clusters()-equivalent
    # exists for IDP"). Reproduced here rather than left NA, so this
    # doesn't introduce a new, inconsistent category alongside the old one.
    selection_type = "pps", supplementary_cluster = FALSE, reallocated = FALSE
  )

if (anyDuplicated(households$survey_id) > 0) stop("Duplicate survey_id.")
log_msg("Stage E: built %d household interview slot(s) across %d cluster(s). Verified: survey_ids unique.", nrow(households), n_distinct(households$cluster_id))

clusters_final <- clusters_df %>%
  left_join(geom_lookup, by = "cluster_id") %>%
  mutate(psu_definition_version = "site_v2",
         iom_site_id = site_id_ssid, iom_site_name = site_name, iom_site_type = site_type, iom_site_ward = ward,
         ward_accessible_status = accessible_status)

write_csv(households, file.path(STAGING_DIR, "new_households_idp_sitelevel.csv"))
write_csv(clusters_final, file.path(STAGING_DIR, "new_clusters_idp_sitelevel.csv"))

# Also write a .gpkg (2026-09-03 fix) - 2_monitoring/cleaning/prep/
# prep_psu_geometries.R scans resample_runs/*/*/ for "new_clusters*.gpkg" to
# build the Coverage Map's PSU geometry layer; this script previously wrote
# CSV only, so every site-level IDP batch's clusters were silently invisible
# on the Coverage Map (found on the Mobbar/FHI 360 batch tonight - fixed
# there via a standalone geometry-only rebuild from the already-drawn CSV,
# no redraw). Fixing at the source here so no future batch repeats the gap.
clusters_final_sf <- sites_unique %>%
  st_transform(4326) %>%
  mutate(pop_type = "idp", selection_type = "pps") %>%
  select(any_of(c("cluster_id", "strata_id", "pop_type", "region", "adm1_name", "adm1_pcode",
                   "adm2_name", "adm2_pcode", "selection_type", "site_name", "site_type",
                   "idp_population_category")), geometry) %>%
  rename(any_of(c(iom_site_name = "site_name", iom_site_type = "site_type")))
st_write(clusters_final_sf, file.path(STAGING_DIR, "new_clusters_idp.gpkg"), delete_layer = TRUE, quiet = TRUE)
log_msg("Wrote new_clusters_idp.gpkg (%d rows) for the Coverage Map's PSU geometry scan.", nrow(clusters_final_sf))

summary_by_stratum <- clusters_final %>% group_by(strata_id, adm2_pcode) %>%
  summarise(new_clusters = n(), new_households = sum(target_households), .groups = "drop")
write_csv(summary_by_stratum, file.path(STAGING_DIR, "summary_by_stratum_idp_sitelevel.csv"))
print(as.data.frame(summary_by_stratum))

log_msg("==== DONE. %d new site-level IDP cluster(s) (%d household rows) across %d strata. ====",
        nrow(clusters_final), nrow(households), n_distinct(clusters_final$strata_id))
log_msg("Staged in: %s. NOT merged into the live WORKING/FULL frame.", STAGING_DIR)
close(log_con)
