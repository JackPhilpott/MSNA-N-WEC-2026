# ==============================================================================
# Refreshes ONLY idp_site_level_psu_frame_2026-09-02.rds's accessible_status
# column from the current ward shapefile - does not touch any other column,
# does not rebuild the frame's own site roster/geometry (that stays frozen
# per this project's "don't rerun casually" rule for this frame).
#
# Written 2026-09-08 to close a real gap: during the 2026-09-07 incident,
# this exact column was found 5 days stale (frozen since the frame's
# 2026-09-02 build) and was fixed ad hoc, with no reusable script saved -
# meaning the next time it went stale, someone would have had to redo that
# ad hoc work from scratch. This is that reusable script, and it's what
# draw_supplementary_idp_sites_batch.R's assert_fresh() gate points to.
#
# METHODOLOGY CORRECTION (2026-09-08, caught before shipping): a first draft
# of this script joined on (adm1_name, adm2_name, ward) text against the
# master CSV's (State, LGA, Ward (GRID3)) - same approach as stamp_ward_
# accessible_status.py uses for the household-level frame. Tested before
# wiring it into anything: 1,489 of 2,765 in-covered-state rows failed to
# match (57%) - not a scope issue, a real one. This frame's `ward` column is
# raw, unreconciled DTM site text ("Sabon-Birni", "Dan Galadima", "Margai -
# B"), never run through GRID3 ward reconciliation the way the household-
# level frame's adm3_name was - so text matching against Ward (GRID3) just
# doesn't work here. The correct, already-proven method is the SPATIAL join
# analysis_remaining_eligible_pool.R and draw_supplementary_clusters_batch.R
# already use for this exact frame/purpose: st_join() against the ward
# SHAPEFILE by point-in-polygon, using each site's real GPS coordinates,
# with a nearest-ward fallback for sites that fall just outside a polygon
# edge. Replicated exactly here rather than re-deriving it.
#
# Genuinely unresolvable sites (no polygon match even via nearest-ward
# within GAP_FALLBACK_MAX_DIST_M) are left NA, not defaulted to Accessible -
# this deliberately differs from analysis_remaining_eligible_pool.R's own
# fallback (which defaults to Accessible, loudly flagged), because that
# script only ever feeds a reporting estimate, while this column directly
# gates a real draw's site inclusion (draw_supplementary_idp_sites_batch.R's
# filter(accessible_status != "Inaccessible")) - the safety-critical path
# this whole rebuild's "unknown excludes, not accessible" rule is for.
#
# Usage: Rscript refresh_idp_site_frame_accessibility.R
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(sf) })
sf::sf_use_s2(FALSE)
mycrs <- 31028
GAP_FALLBACK_MAX_DIST_M <- 5000

RDS_PATH <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds"
WARD_LAYER_SHP <- "resampling/output/gis/accessible_area_lga_ward_portions.shp"

site_frame <- readRDS(RDS_PATH) %>% st_transform(mycrs)
before <- table(site_frame$accessible_status, useNA = "always")

ward_layer_raw <- st_read(WARD_LAYER_SHP, quiet = TRUE) %>% st_transform(mycrs) %>%
  rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ)
ward_layer_idp <- ward_layer_raw %>% filter(pop_type == "IDP")

site_frame <- site_frame %>% select(-any_of("accessible_status"))
joined <- st_join(site_frame, ward_layer_idp["accessible_status"], join = st_within)

na_idx <- which(is.na(joined$accessible_status))
if (length(na_idx) > 0) {
  nearest_idx <- st_nearest_feature(joined[na_idx, ], ward_layer_idp)
  dists <- as.numeric(st_distance(joined[na_idx, ], ward_layer_idp[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= GAP_FALLBACK_MAX_DIST_M
  joined$accessible_status[na_idx[within_cap]] <- ward_layer_idp$accessible_status[nearest_idx[within_cap]]
  cat(sprintf(
    "%d site(s) outside any ward polygon - %d resolved via nearest ward (max %.0fm away), %d beyond %dm left NA (excluded pending review, NOT defaulted to Accessible).\n",
    length(na_idx), sum(within_cap), if (any(within_cap)) max(dists[within_cap]) else 0,
    sum(!within_cap), GAP_FALLBACK_MAX_DIST_M
  ))
}

site_frame <- joined
after <- table(site_frame$accessible_status, useNA = "always")
saveRDS(site_frame, RDS_PATH)

cat("refresh_idp_site_frame_accessibility(): done.\n")
cat("Before:\n"); print(before)
cat("After:\n"); print(after)
n_unmatched <- sum(is.na(site_frame$accessible_status))
if (n_unmatched > 0) {
  unmatched <- site_frame %>% st_drop_geometry() %>% filter(is.na(accessible_status)) %>%
    distinct(adm1_name, adm2_name, ward)
  cat(sprintf("Still-unmatched sites span %d distinct (state, LGA, ward) combos:\n", nrow(unmatched)))
  print(unmatched)
}
