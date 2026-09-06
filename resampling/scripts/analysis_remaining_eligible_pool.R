# ==============================================================================
# Computes the REMAINING, UNSELECTED candidate pool within the currently-
# accessible area, per stratum - feeds the "how many more clusters could we
# realistically add" feasibility question (2026-08-25).
#
# Non-IDP: hexagon-level. accessible_hex.rds is the SAME national candidate
# hex grid Stage 1 draws from (already filtered by the international border
# buffer only, NOT the new partner-reported ward accessibility). Each hex's
# centroid is point-in-polygon joined against the new ward-clipped
# accessible/inaccessible layer, and cross-referenced against the delivered
# WORKING frame's own uuid_hex list to separate already-selected from
# unselected. CAVEAT (kept in the output, not hidden): this is a HEXAGON
# count, not a building-validated count - a hex counted here as "remaining"
# could still turn out to have zero eligible buildings once actually drawn
# (same situation reallocate_zero_building_clusters() already handles for a
# real resample). Treat this as an upper bound on the true eligible pool, not
# an exact figure - re-running the full building-eligibility check against
# the Google Open Buildings cache was judged too heavy for this reporting
# exercise (see analysis_accessible_area_layer.R's header on why a standalone,
# lighter recompute was chosen over touching pipeline machinery).
#
# IDP: site-level, and exact rather than a proxy - every individual DTM site
# (both source files) is point-in-polygon joined against the same ward layer
# directly from its own Lat/Lon, so accessible/inaccessible is a real
# geometric fact per site, not an approximation. Cross-referenced against the
# delivered frame's iom_site_id list for used/unused.
#
# FIXED 2026-08-27 (see ../../CLAUDE.md's Revision 2026-08-27, and
# analysis_accessible_area_layer.R's own header for the full incident):
# `covered_pcodes` was previously one blanket LGA list used for BOTH pop
# types - wrong whenever a LGA has real coverage for one pop_type but not
# the other (Gwandu/Kebbi: Non-IDP yes, IDP certainty-excluded before this
# design was ever fielded). That let a LGA's IDP DTM sites count toward the
# "remaining eligible IDP pool" even where no IDP design/coverage exists at
# all. Now computed separately per pop_type. The ward layer itself
# (accessible_area_lga_ward_portions.shp) is also now split by pop_type
# (same fix) - each join below is filtered to the matching pop_type first,
# otherwise a hex/site sitting in a ward with BOTH Non-IDP and IDP rows
# would match twice (same geometry, two ward_layer features) and silently
# double-count that hex/site in the pool.
#
# Output: resampling/output/gis/remaining_eligible_pool_non_idp.csv,
#         resampling/output/gis/remaining_eligible_pool_idp.csv
# Both keyed by adm2_pcode (join key back to the strata CSV).
# ==============================================================================
library(sf)
library(dplyr)
library(readr)

# 2026-08-30: a centroid landing in NO ward polygon used to default straight
# to Accessible everywhere below - same failure shape as the original 49%-
# spurious-rows bug (silently treating "couldn't determine" as "fine").
# Checked directly against the real national join: 72 of 21,709 Non-IDP hex
# centroids fall into this case, 5 of them in Maru (Zamfara) - one of
# INTERSOS's own tightest strata. Distances to the nearest real ward polygon
# are almost all floating-point-scale slivers (median 1.75cm - the dissolve
# in analysis_accessible_area_layer.R doesn't perfectly snap adjacent ward-
# portions' shared edges), with a handful of genuine small gaps up to ~2.4km
# (likely unmapped/water slivers, not sliver artifacts) - still small
# relative to ward size, so nearest-ward is used for all of them, capped at
# GAP_FALLBACK_MAX_DIST_M for safety on a future rerun with different
# geometry (falls back to the old Accessible default, loudly, beyond that -
# never silently resolves a genuinely distant point to a possibly-unrelated
# ward). Of the 72 found this way, 20 actually resolve to Inaccessible, not
# Accessible - this was a real, live misclassification, not a theoretical
# one. Used for BOTH the Non-IDP hex join and the IDP site join below (same
# failure shape, same fix).
GAP_FALLBACK_MAX_DIST_M <- 5000

resolve_ward_gaps <- function(pts, ward_layer, label) {
  na_idx <- which(is.na(pts$accessible_status))
  if (length(na_idx) == 0) return(pts)
  nearest_idx <- st_nearest_feature(pts[na_idx, ], ward_layer)
  dists <- as.numeric(st_distance(pts[na_idx, ], ward_layer[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= GAP_FALLBACK_MAX_DIST_M
  pts$accessible_status[na_idx[within_cap]] <- ward_layer$accessible_status[nearest_idx[within_cap]]
  n_defaulted <- sum(!within_cap)
  cat(sprintf(
    "  %s: %d centroid(s) outside any ward polygon - %d resolved via nearest ward (max %.0fm away), %d beyond %dm defaulted to Accessible (flagged).\n",
    label, length(na_idx), sum(within_cap), if (any(within_cap)) max(dists[within_cap]) else 0,
    n_defaulted, GAP_FALLBACK_MAX_DIST_M
  ))
  if (n_defaulted > 0) {
    pts$accessible_status[na_idx[!within_cap]] <- "Accessible"
  }
  pts
}

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
mycrs <- 31028

# FULL, not WORKING (2026-09-01 fix - was WORKING right after the v2->v4
# path bump, wrong for this script): this computes how much accessible,
# unselected pool is left to draw from - v4 WORKING already drops rows in
# a currently-inaccessible ward, so a fully-inaccessible LGA would fall out
# of "covered" and be silently skipped rather than correctly show zero
# pool. Filtered below to drop BOTH never-covered rows AND population-
# floor/certainty-excluded strata (unlike the ward-status scripts, which
# keep excluded strata visible) - a stratum we've already permanently
# dropped shouldn't show a "remaining pool" at all, since RESAMPLING_
# DECISION_RULES.md says never draw there again regardless.
WORKING_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv"
ACCESSIBLE_HEX_RDS <- "input_data/boundaries/nga_hexagons/accessible_hex.rds"
WARD_LAYER_SHP <- "resampling/output/gis/accessible_area_lga_ward_portions.shp"
ADMIN2_SHP <- "input_data/boundaries/nga_admin_boundaries/nga_admin2.shp"
IOM_NCNW_CSV <- "input_data/population/iom/IMPACT_IOM_DTM_NCNW_R18.csv"
IOM_NE_CSV <- "input_data/population/iom/IMPACT_IOM_NGA_R51_NE.csv"
GIS_OUT_DIR <- "resampling/output/gis"

cat("Loading inputs...\n")
working <- read_csv(WORKING_CSV, show_col_types = FALSE) %>%
  filter(coverage_status == "covered", exclusion_reason == "none")
# Per-pop_type coverage, not blanket LGA coverage (2026-08-27 fix) - see
# module header and analysis_accessible_area_layer.R for why.
covered_pcodes_non_idp <- working %>% filter(pop_type == "non_idp") %>% distinct(adm2_pcode) %>% pull(adm2_pcode)
covered_pcodes_idp <- working %>% filter(pop_type == "idp") %>% distinct(adm2_pcode) %>% pull(adm2_pcode)

ward_layer_raw <- st_read(WARD_LAYER_SHP, quiet = TRUE) %>% st_transform(mycrs)
# Restore full column names lost to the shapefile's abbreviation (10-char limit) -
# confirmed exact truncated names via direct inspection, not guessed.
ward_layer_raw <- ward_layer_raw %>% rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ)
# One row per (ward, pop_type) now (2026-08-27) - split before each join
# below so a dual-eligible ward's two rows (identical geometry) don't both
# match the same hex/site centroid and double-count it.
ward_layer_non_idp <- ward_layer_raw %>% filter(pop_type == "Non-IDP")
ward_layer_idp <- ward_layer_raw %>% filter(pop_type == "IDP")

# ---- NON-IDP: hexagon pool ----
cat("Processing Non-IDP hexagon pool...\n")
hexes <- readRDS(ACCESSIBLE_HEX_RDS) %>%
  filter(adm2_pcode %in% covered_pcodes_non_idp) %>%
  st_transform(mycrs)
hex_centroids <- st_centroid(hexes)

hex_status <- st_join(hex_centroids, ward_layer_non_idp["accessible_status"], join = st_within)
hex_status <- resolve_ward_gaps(hex_status, ward_layer_non_idp, "Non-IDP hexes")

used_non_idp_hex <- working %>% filter(pop_type == "non_idp") %>% distinct(uuid_hex) %>% pull(uuid_hex)

hex_status_df <- st_drop_geometry(hex_status) %>%
  mutate(is_selected = uuid_hex %in% used_non_idp_hex)

non_idp_pool <- hex_status_df %>%
  group_by(adm2_pcode) %>%
  summarise(
    total_candidate_hexes = n(),
    accessible_candidate_hexes = sum(accessible_status == "Accessible"),
    accessible_unselected_hexes = sum(accessible_status == "Accessible" & !is_selected),
    .groups = "drop"
  )
write_csv(non_idp_pool, file.path(GIS_OUT_DIR, "remaining_eligible_pool_non_idp.csv"))
cat(sprintf("Non-IDP: %d LGAs, %d total accessible-unselected hexes nationally\n",
            nrow(non_idp_pool), sum(non_idp_pool$accessible_unselected_hexes)))

# ---- IDP: DTM site pool ----
cat("Processing IDP DTM site pool...\n")
iom_ncnw <- read_csv(IOM_NCNW_CSV, show_col_types = FALSE, name_repair = "minimal")
iom_ne <- read_csv(IOM_NE_CSV, show_col_types = FALSE, name_repair = "minimal")

iom_ncnw_clean <- iom_ncnw %>%
  transmute(site_id = `Site ID (SSID)`, lga_name = LGA, lat = `Latitude N?`, lon = `Longitude E?`,
            households = Households, individuals = Individuals)
iom_ne_clean <- iom_ne %>%
  transmute(site_id = `Site ID (SSID)`, lga_pcode = `LGA Pcode`, lga_name = LGA,
            lat = `Latitude N`, lon = `Longitude E`, households = Households, individuals = Individuals)

iom_all <- bind_rows(iom_ncnw_clean, iom_ne_clean) %>%
  filter(!is.na(lat), !is.na(lon), !is.na(site_id))

iom_sf <- st_as_sf(iom_all, coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>%
  st_transform(mycrs)

site_status <- st_join(iom_sf, ward_layer_idp[c("adm2_pcode", "accessible_status")], join = st_within)

# Gap fix (2026-08-30): a site with no ward match loses BOTH adm2_pcode and
# accessible_status (both come from the same joined ward feature) - unlike
# the Non-IDP hex case above, this means such a site was silently DROPPED
# by the covered_pcodes_idp filter below entirely, never defaulted to
# Accessible at all (that ifelse a few lines down never actually fired -
# checked directly, 0 rows ever had accessible_status NA with adm2_pcode
# non-NA). Checked what this actually meant: of 2,089 sites with no ward
# match nationally, only 2 are genuinely within a covered IDP LGA's
# boundary at all - the other 2,087 are simply outside the 14 assessment
# states/covered LGAs, correctly excluded, not a bug. For the 2 genuine
# cases, resolve both fields via the same nearest-ward fallback as the
# Non-IDP hex join.
admin2_covered_idp <- st_read(ADMIN2_SHP, quiet = TRUE) %>% st_make_valid() %>%
  st_transform(mycrs) %>% filter(adm2_pcode %in% covered_pcodes_idp)

na_site_idx <- which(is.na(site_status$adm2_pcode))
if (length(na_site_idx) > 0) {
  in_covered <- st_join(site_status[na_site_idx, ], admin2_covered_idp["adm2_pcode"], join = st_within)
  truly_in_scope <- na_site_idx[!is.na(in_covered$adm2_pcode.y)]
  cat(sprintf("  IDP sites: %d outside any ward polygon (%d genuinely in a covered LGA, %d correctly out of scope)...\n",
              length(na_site_idx), length(truly_in_scope), length(na_site_idx) - length(truly_in_scope)))
  if (length(truly_in_scope) > 0) {
    nearest_idx <- st_nearest_feature(site_status[truly_in_scope, ], ward_layer_idp)
    dists <- as.numeric(st_distance(site_status[truly_in_scope, ], ward_layer_idp[nearest_idx, ], by_element = TRUE))
    within_cap <- dists <= GAP_FALLBACK_MAX_DIST_M
    resolved <- truly_in_scope[within_cap]
    site_status$adm2_pcode[resolved] <- ward_layer_idp$adm2_pcode[nearest_idx[within_cap]]
    site_status$accessible_status[resolved] <- ward_layer_idp$accessible_status[nearest_idx[within_cap]]
    cat(sprintf("  IDP sites: %d resolved via nearest ward (max %.0fm away).\n",
                length(resolved), if (any(within_cap)) max(dists[within_cap]) else 0))
  }
}

site_status_df <- st_drop_geometry(site_status) %>%
  filter(!is.na(adm2_pcode), adm2_pcode %in% covered_pcodes_idp)  # keep only sites that actually fall inside a covered LGA polygon

used_idp_sites <- working %>% filter(pop_type == "idp") %>% distinct(iom_site_id) %>% pull(iom_site_id)

site_status_df <- site_status_df %>%
  mutate(is_selected = site_id %in% used_idp_sites)

idp_pool <- site_status_df %>%
  group_by(adm2_pcode) %>%
  summarise(
    total_candidate_sites = n(),
    accessible_candidate_sites = sum(accessible_status == "Accessible"),
    accessible_unselected_sites = sum(accessible_status == "Accessible" & !is_selected),
    accessible_unselected_individuals = sum(individuals[accessible_status == "Accessible" & !is_selected], na.rm = TRUE),
    .groups = "drop"
  )
write_csv(idp_pool, file.path(GIS_OUT_DIR, "remaining_eligible_pool_idp.csv"))
cat(sprintf("IDP: %d LGAs, %d total accessible-unselected sites nationally\n",
            nrow(idp_pool), sum(idp_pool$accessible_unselected_sites)))
