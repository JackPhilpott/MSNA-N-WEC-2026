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
orig <- site_frame
before <- table(site_frame$accessible_status, useNA = "always")

# 2026-10-02 FIX (Coordinator instruction under Jack's approval): one row per
# site, enforced loudly. st_join(st_within) returns a site once PER matching
# polygon; accessible_area_lga_ward_portions.shp had exact-duplicate IDP
# polygons for Tangaza (NG034019), and because this script overwrites its own
# input, each run doubled those sites again: 64 copies of 10 sites by 29 Sep
# (3,581 rows for 2,951 sites). First seen 26-27 Sep and fixed only in a
# one-off variant (one_off_analyses/refresh_idp_site_frame_accessibility_
# dedup_2026-09-27.R) while this standing script stayed unpatched. The
# collapse rule below is ported from that variant unchanged; the STOP guards
# are new, so a repeat can never compound silently again.
n_sites_in <- nrow(site_frame)
if (anyDuplicated(site_frame$uuid_site) > 0) {
  stop(sprintf("STOP: input site frame already has %d duplicate uuid_site row(s) - deduplicate it first (see one_off_analyses/dedup_idp_site_frame_tangaza_2026-10-02.R). Nothing written.",
               sum(duplicated(site_frame$uuid_site))))
}

ward_layer_raw <- st_read(WARD_LAYER_SHP, quiet = TRUE) %>% st_transform(mycrs) %>%
  rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ)
ward_layer_idp <- ward_layer_raw %>% filter(pop_type == "IDP")

site_frame$.rid <- seq_len(n_sites_in)
site_frame <- site_frame %>% select(-any_of("accessible_status"))
joined <- st_join(site_frame, ward_layer_idp["accessible_status"], join = st_within)

# Collapse to one row per site: Inaccessible if ANY matching polygon says so,
# else Accessible if any does, else NA (never fires when duplicates agree).
per_site <- joined %>% st_drop_geometry() %>% group_by(.rid) %>%
  summarise(n_match = n(),
            n_distinct_status = n_distinct(accessible_status, na.rm = TRUE),
            status = if (any(accessible_status == "Inaccessible", na.rm = TRUE)) "Inaccessible"
                     else if (any(accessible_status == "Accessible", na.rm = TRUE)) "Accessible"
                     else NA_character_,
            .groups = "drop")
cat(sprintf("sites matched by >1 ward polygon: %d | of which the matches DISAGREE on status: %d\n",
            sum(per_site$n_match > 1), sum(per_site$n_distinct_status > 1)))
joined <- joined[!duplicated(joined$.rid), ]
joined <- joined[order(joined$.rid), ]
joined$accessible_status <- per_site$status[match(joined$.rid, per_site$.rid)]
if (nrow(joined) != n_sites_in || anyDuplicated(joined$uuid_site) > 0 || !identical(joined$.rid, seq_len(n_sites_in))) {
  stop(sprintf("STOP: after the ward join the frame has %d rows / %d distinct sites, input had %d - refusing to write.",
               nrow(joined), dplyr::n_distinct(joined$uuid_site), n_sites_in))
}

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

site_frame <- joined %>% select(-.rid)
site_frame <- site_frame[, names(orig)]   # restore the input's column order (sf keeps geometry)

# Verify before writing (ported from the 27 Sep variant): only accessible_status may change.
o_df <- st_drop_geometry(orig); f_df <- st_drop_geometry(site_frame)
other_cols <- setdiff(names(o_df), "accessible_status")
col_ok <- vapply(other_cols, function(cn) identical(o_df[[cn]], f_df[[cn]]), logical(1))
chk <- c(rows_equal = nrow(site_frame) == n_sites_in,
         one_row_per_site = anyDuplicated(site_frame$uuid_site) == 0,
         non_status_columns_identical = all(col_ok),
         geometry_identical = isTRUE(all.equal(st_coordinates(orig), st_coordinates(site_frame))),
         crs_same = identical(st_crs(site_frame), st_crs(orig)))
if (!all(chk)) {
  print(chk); print(names(col_ok)[!col_ok])
  stop("STOP: verification failed - nothing written.")
}
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
