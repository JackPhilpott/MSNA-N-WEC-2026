# ==============================================================================
# Builds the geospatial accessible/inaccessible area layer, LGA-ward grain,
# split by pop_type - one row per (State, LGA, Ward, Pop Type) that was
# actually ELIGIBLE for selection at Stage 1 (i.e. within the post-border-
# buffer accessible geography), for a covered LGA x pop_type.
#
# FIXED 2026-08-27 (see ../../CLAUDE.md's Revision 2026-08-27 for the full
# incident writeup): the original version pulled every GRID3 ward
# geometrically touching a covered LGA - far broader than the actual
# sampling universe - and defaulted anything that didn't match the master
# status file to "Accessible". 1,977 of 4,047 rows (49%) nationally were
# spurious this way: wards excluded by the international border buffer (or
# other Stage-1 exclusions) showing as "Accessible, not yet reported" when
# they were never part of the design at all. Found via the user noticing
# Damasak/Mobbar showing wrongly in the monitoring dashboard, confirmed via
# a systematic ward-key comparison against the true universe - 100% of the
# extra rows carried the identical default_unreported/no-partner signature,
# and zero real universe wards were missing the other way (ruling out a
# naming-mismatch explanation instead).
#
# The universe is now genuinely "eligible at Stage 1", not "raw geography"
# and not "has an actual drawn cluster" - deliberately, per the user's own
# reasoning (2026-08-27): random PPS sampling could, by chance, not draw any
# hexagon in a ward that was fully eligible, and that ward's accessibility
# still needs tracking (especially since it's exactly the kind of ward a
# future resample would draw from - see remaining_eligible_pool below).
# Split by pop_type because eligibility genuinely differs - e.g. Gwandu
# (Kebbi) has real Non-IDP coverage but its IDP stratum was certainty-
# excluded before this design was ever fielded (Revision 2026-07-23) - a
# blanket LGA-level "covered" test would wrongly show Gwandu's IDP portion
# as in-scope, and does exactly that in analysis_remaining_eligible_pool.R
# today (see that script's own 2026-08-27 fix, same root cause).
#
# Non-IDP eligibility: a ward-portion is included if it geometrically
# intersects ANY hex in accessible_hex.rds (the SAME national candidate hex
# grid Stage 1 draws from, already border-buffer-filtered - see
# analysis_remaining_eligible_pool.R's own header, which already reuses
# this exact object for a closely related purpose), AND its LGA has Non-IDP
# WORKING coverage.
#
# IDP eligibility: a ward-portion is included if it contains at least one
# raw DTM site (same IOM source analysis_remaining_eligible_pool.R reads),
# AND its LGA has IDP WORKING coverage.
#
# Status (accessible/inaccessible/reason/reporting partner) still comes
# from master_accessibility_status_ward_level.csv, joined by (State, LGA,
# Ward) only - NOT by pop_type, since partner reports are pop-type-blind at
# ward level (the Ward Accessibility sheet has no Pop Type column, unlike
# Cluster Accessibility) - the same status applies to both pop-type rows of
# a ward where both exist.
#
# STANDALONE RECOMPUTE, not a pipeline rerun - deliberate choice, discussed
# with the user: this reclassifies the ALREADY-DELIVERED clusters/sites (the
# ones partners are actually fielding right now) as inside/outside the
# newly-accessible geography, and re-sums population/area against that -
# it does NOT redraw a new sample for a shrunken universe. That's the correct
# tool for a *descriptive* report on the current situation; a from-scratch
# redesign is a different, not-yet-decided, future task (the user is leaning
# against reallocating into the accessible remainder at all, for coverage-
# bias reasons - see resampling/README.md's 2026-08-24 policy).
#
# Inputs:
# - resampling/output/master_accessibility_status_ward_level.csv (built by
#   04_build_master_accessibility_status.py) - the LGA-scoped ward accessible/
#   inaccessible status, universe-wide, already reconciled against every
#   ingested partner report.
# - input_data/boundaries/nga_admin_boundaries/nga_admin2.shp - OCHA/COD LGA
#   polygons (same layer the WORKING frame's adm2_pcode/adm2_name come from).
# - input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/ - GRID3 ward polygons
#   (same layer households are point-in-polygon joined against in Stage 2 -
#   see 03_stage2_household_selection.R's finalize_households()).
# - input_data/boundaries/nga_hexagons/accessible_hex.rds - Stage 1's own
#   border-buffer-filtered candidate hex grid (Non-IDP eligibility source).
# - input_data/population/iom/IMPACT_IOM_DTM_{NCNW_R18,NGA_R51_NE}.csv - raw
#   DTM site lists (IDP eligibility source), same files analysis_remaining_
#   eligible_pool.R reads.
# - input_data/population/worldpop/worldpop_nga_2026_projected.rds - the
#   SAME projected (EPSG:31028) population raster Stage 1 PPS draws from,
#   already cached by 01_sampling_pipeline_main.R's load_population().
#
# Ward polygons are geometrically clipped to the LGA boundary (st_intersection
# of GRID3 wards x OCHA/COD admin2), never matched by ward name alone - same
# reasoning as everywhere else in this project (README's "why every ward row
# is scoped to a specific LGA"): GRID3/OCHA boundaries disagree by tens of
# metres at borders, and a ward can genuinely span >1 LGA. A real geometric
# clip handles this correctly regardless of naming; a name-only match
# wouldn't.
#
# Output:
# - resampling/output/gis/accessible_area_lga_ward_portions.{shp,csv} - one
#   polygon per (adm2_pcode, ward, pop_type), attributed with accessible
#   status, area (km2), and gridded population sum within that specific
#   polygon. The Non-IDP and IDP rows of a dual-eligible ward share
#   IDENTICAL geometry (there's no separate "IDP polygon" concept - IDP
#   eligibility is a site-presence test, not a different shape) - this is
#   intentional, not a duplication bug. Downstream consumers that sum
#   area/population per LGA MUST filter or group by pop_type first, or a
#   dual-eligible ward's area double-counts (see 05_build_accessibility_
#   impact_workbook.py's load_lga_area_pop_fractions() for the pattern).
# ==============================================================================
library(sf)
library(terra)
library(dplyr)
library(exactextractr)
library(readr)

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

mycrs <- 31028  # same projected CRS 01_sampling_pipeline_main.R uses throughout

# FULL, not WORKING (2026-09-01 fix - was WORKING right after the v2->v4
# path bump, wrong for this script): "covered" LGAs below decides the
# universe this layer reports ward accessibility for - v4 WORKING already
# drops rows sitting in a currently-inaccessible ward, so a fully-
# inaccessible LGA would show zero WORKING rows and silently fall out of
# "covered" entirely, when it should still appear (correctly marked
# Inaccessible). Filtered below to exclude only never-covered-at-all rows,
# same scope 04_build_master_accessibility_status.py now uses - keeps
# population-floor/certainty-excluded LGAs (e.g. Dandume/Faskari) visible,
# since this is a status picture, not a "still needs resampling" list.
WORKING_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv"
MASTER_WARD_CSV <- "resampling/output/master_accessibility_status_ward_level.csv"
ADMIN2_SHP <- "input_data/boundaries/nga_admin_boundaries/nga_admin2.shp"
WARDS_SHP <- "input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp"
POP_RDS <- "input_data/population/worldpop/worldpop_nga_2026_projected.rds"
ACCESSIBLE_HEX_RDS <- "input_data/boundaries/nga_hexagons/accessible_hex.rds"
PENDING_ADHOC_PROPOSALS_CSV <- "resampling/input/ad_hoc_reports/pending_adhoc_proposals.csv"
IOM_NCNW_CSV <- "input_data/population/iom/IMPACT_IOM_DTM_NCNW_R18.csv"
IOM_NE_CSV <- "input_data/population/iom/IMPACT_IOM_NGA_R51_NE.csv"

GIS_OUT_DIR <- "resampling/output/gis"
dir.create(GIS_OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("Loading inputs...\n")
working <- read_csv(WORKING_CSV, show_col_types = FALSE) %>% filter(coverage_status != "not_covered")
master_ward <- read_csv(MASTER_WARD_CSV, show_col_types = FALSE)

# Per-pop_type coverage, not blanket LGA coverage (2026-08-27 fix) - a LGA
# can have real coverage for one pop_type and none for the other.
covered_pcodes_non_idp <- working %>% filter(pop_type == "non_idp") %>% distinct(adm2_pcode) %>% pull(adm2_pcode)
covered_pcodes_idp <- working %>% filter(pop_type == "idp") %>% distinct(adm2_pcode) %>% pull(adm2_pcode)
covered_pcodes_any <- union(covered_pcodes_non_idp, covered_pcodes_idp)
cat(sprintf("Covered LGAs - Non-IDP: %d, IDP: %d, either: %d\n",
            length(covered_pcodes_non_idp), length(covered_pcodes_idp), length(covered_pcodes_any)))

covered_lgas <- working %>% distinct(adm1_pcode, adm1_name, adm2_pcode, adm2_name) %>%
  filter(adm2_pcode %in% covered_pcodes_any)

admin2 <- st_read(ADMIN2_SHP, quiet = TRUE) %>% st_make_valid()
admin2_covered <- admin2 %>% filter(adm2_pcode %in% covered_lgas$adm2_pcode)
cat(sprintf("Covered LGAs (either pop_type): %d (of %d in admin2 layer nationally)\n", nrow(admin2_covered), nrow(admin2)))

wards <- st_read(WARDS_SHP, quiet = TRUE) %>% st_make_valid()

covered_union <- st_union(admin2_covered)
wards_near <- wards[st_intersects(wards, covered_union, sparse = FALSE)[, 1], ]
cat(sprintf("Wards touching covered LGAs: %d (of %d nationally)\n", nrow(wards_near), nrow(wards)))

cat("Intersecting wards x LGA boundaries (this is the real LGA-ward clip)...\n")
pieces <- st_intersection(
  wards_near %>% select(wardname, wardcode, statename),
  admin2_covered %>% select(adm2_pcode, adm2_name, adm1_pcode, adm1_name)
)
pieces <- pieces[st_is(pieces, c("POLYGON", "MULTIPOLYGON")), ]
cat(sprintf("Raw intersection pieces: %d\n", nrow(pieces)))

cat("Dissolving multi-part slivers per (LGA, ward)...\n")
dissolved <- pieces %>%
  group_by(adm2_pcode, adm2_name, adm1_pcode, adm1_name, wardname) %>%
  summarise(.groups = "drop")

dissolved_proj <- st_transform(dissolved, mycrs)
dissolved_proj$area_km2 <- as.numeric(st_area(dissolved_proj)) / 1e6

cat("Extracting gridded population per LGA-ward portion...\n")
pop_raster <- readRDS(POP_RDS)
dissolved_proj$pop_total <- exact_extract(pop_raster, dissolved_proj, "sum", progress = FALSE)

# ---- Eligibility test 1: Non-IDP (intersects >=1 Stage-1 accessible hex) --
cat("Testing Non-IDP eligibility (intersects Stage 1's accessible hex grid)...\n")
accessible_hex <- readRDS(ACCESSIBLE_HEX_RDS) %>%
  filter(adm2_pcode %in% covered_pcodes_non_idp) %>%
  st_transform(mycrs)
# Pairwise intersects against the hex SET (not a union - unioning tens of
# thousands of hex polygons is a needless, slow geometry op when a direct
# spatial-indexed intersects test does the same job).
non_idp_hits <- st_intersects(dissolved_proj, accessible_hex)
non_idp_eligible <- lengths(non_idp_hits) > 0

# ---- Eligibility test 2: IDP (contains >=1 raw DTM site) -------------------
cat("Testing IDP eligibility (contains >=1 DTM site)...\n")
iom_ncnw <- read_csv(IOM_NCNW_CSV, show_col_types = FALSE, name_repair = "minimal")
iom_ne <- read_csv(IOM_NE_CSV, show_col_types = FALSE, name_repair = "minimal")
iom_ncnw_clean <- iom_ncnw %>% transmute(lat = `Latitude N?`, lon = `Longitude E?`)
iom_ne_clean <- iom_ne %>% transmute(lat = `Latitude N`, lon = `Longitude E`)
iom_all <- bind_rows(iom_ncnw_clean, iom_ne_clean) %>% filter(!is.na(lat), !is.na(lon))
iom_sf <- st_as_sf(iom_all, coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>% st_transform(mycrs)

dtm_hits <- st_intersects(dissolved_proj, iom_sf)
idp_eligible <- lengths(dtm_hits) > 0

cat(sprintf("Ward-portions: %d total | Non-IDP eligible: %d | IDP eligible (has DTM site): %d\n",
            nrow(dissolved_proj), sum(non_idp_eligible), sum(idp_eligible)))

# ---- Build pop-type-specific rows, restricted to that pop_type's covered LGAs ----
build_pop_type_layer <- function(base, eligible_mask, pop_type_label, covered_pcodes_this) {
  out <- base[eligible_mask & base$adm2_pcode %in% covered_pcodes_this, ]
  out$pop_type <- pop_type_label
  out
}
non_idp_layer <- build_pop_type_layer(dissolved_proj, non_idp_eligible, "Non-IDP", covered_pcodes_non_idp)
idp_layer <- build_pop_type_layer(dissolved_proj, idp_eligible, "IDP", covered_pcodes_idp)
final_layer <- rbind(non_idp_layer, idp_layer)

cat(sprintf("Final layer rows: %d (%d Non-IDP, %d IDP)\n", nrow(final_layer), nrow(non_idp_layer), nrow(idp_layer)))

cat("Joining accessible status from the master ward-level status file...\n")
master_join <- master_ward %>%
  transmute(
    adm1_name = State, adm2_name = LGA, wardname = `Ward (GRID3)`,
    accessible_status = `Accessible status`, status_source = `Status source`,
    reporting_partners = `Reporting partner(s)`, reason_category = `Reason category`,
    ward_covering_partners = `Partners covering this LGA-ward portion`
  )

final_layer <- final_layer %>%
  left_join(master_join, by = c("adm1_name", "adm2_name", "wardname"))

n_unmatched <- sum(is.na(final_layer$accessible_status))
cat(sprintf("Ward-portion x pop_type rows: %d | matched to a status row: %d | unmatched: %d\n",
            nrow(final_layer), nrow(final_layer) - n_unmatched, n_unmatched))
if (n_unmatched > 0) {
  cat("Unmatched (genuinely-eligible ward with no cluster/site yet reported on - expected, defaults Accessible below; NOT a name mismatch, since these already passed the eligibility test above):\n")
  print(head(st_drop_geometry(final_layer %>% filter(is.na(accessible_status)) %>%
                            select(adm1_name, adm2_name, wardname, pop_type)), 10))
}
# An eligible ward-portion with no status row yet (no partner's cluster has
# touched it) defaults Accessible, same universe-wide default as
# 04_build_master_accessibility_status.py - this is now a genuine "not yet
# reported" case, not a spurious out-of-universe one, since eligibility was
# already tested above.
final_layer$accessible_status[is.na(final_layer$accessible_status)] <- "Accessible"
final_layer$status_source[is.na(final_layer$status_source)] <- "default_unreported"

# ---- Pending ad-hoc proposal override (added 2026-08-28) ------------------
# Narrow, explicit exception - NOT a change to the universal default_
# unreported -> Accessible rule above, which stays exactly as-is everywhere
# else. This is for the specific, rare case of a ward that's genuinely
# eligible and unreported (so it WOULD get the normal default) but where
# we've made a live, specific, still-unanswered ask to a partner about it
# (e.g. resampling/input/ad_hoc_reports/*.xlsx) - Jack's call 2026-08-28
# (the Mobbar/FHI 360 case): showing that ward as "Accessible" in the
# interim overstates what we actually know, since it's contingent on a
# pending response, not a generic gap. pending_adhoc_proposals.csv is a
# small, hand-maintained registry (see its own header) for exactly this -
# add a row there for any future case; don't hardcode wards into this
# script. Only overrides rows that are still the plain default_unreported
# case (a real partner report, if one ever lands here, always wins).
if (file.exists(PENDING_ADHOC_PROPOSALS_CSV)) {
  pending_proposals <- read_csv(PENDING_ADHOC_PROPOSALS_CSV, show_col_types = FALSE) %>%
    distinct(state, lga, wardname)
  is_pending <- final_layer$status_source == "default_unreported" &
    paste(final_layer$adm1_name, final_layer$adm2_name, final_layer$wardname) %in%
      paste(pending_proposals$state, pending_proposals$lga, pending_proposals$wardname)
  cat(sprintf("Pending ad-hoc proposal override: %d ward-portion row(s) moved from default-Accessible to pending/excluded.\n", sum(is_pending)))
  final_layer$accessible_status[is_pending] <- "Inaccessible"
  final_layer$status_source[is_pending] <- "pending_adhoc_proposal_response"
}

# ---- Covering partner(s) - who to show on unreported wards (2026-08-28) ---
# "Reported by"/reporting_partners only has a value once someone has actually
# submitted something - for the majority-unreported case (no cluster ever
# drawn there, or a covering partner just hasn't sent a report back yet) it's
# blank, which reads as "nobody's responsible" rather than "nobody's told us
# yet". ward_covering_partners (from master_ward, ward-grain, built from
# actual cluster assignment) covers most wards; the small remainder that
# never got a cluster drawn at all (so never appear in master_ward - see
# n_unmatched above) fall back to the WORKING frame's own LGA x pop_type
# partners_covering column, which is coverage-assignment data independent of
# whether any cluster/report exists yet.
# partners_covering in the WORKING frame is comma-joined (see
# 01_generate_accessibility_reports.py's own docstring, e.g. "DRC, IRC,
# LHI"); ward_covering_partners (from master_ward, above) is semicolon-
# joined, which is what accessibility_partner_label() in the dashboard's
# global.R splits on. Normalized to semicolons here so covering_partners has
# one consistent separator regardless of which of the two sources filled it
# - otherwise the comma-joined fallback silently fails to split downstream.
lga_covering_lookup <- working %>%
  mutate(pop_type_label = if_else(pop_type == "non_idp", "Non-IDP", "IDP")) %>%
  distinct(adm2_pcode, pop_type_label, partners_covering) %>%
  transmute(
    pop_type = pop_type_label,
    adm2_pcode = adm2_pcode,
    lga_covering_partners = gsub(",\\s*", "; ", partners_covering)
  )

final_layer <- final_layer %>%
  left_join(lga_covering_lookup, by = c("adm2_pcode", "pop_type")) %>%
  mutate(covering_partners = if_else(
    !is.na(ward_covering_partners) & ward_covering_partners != "",
    ward_covering_partners, lga_covering_partners
  )) %>%
  select(-ward_covering_partners, -lga_covering_partners)

st_write(final_layer, file.path(GIS_OUT_DIR, "accessible_area_lga_ward_portions.shp"),
         delete_layer = TRUE, quiet = TRUE)
write_csv(st_drop_geometry(final_layer), file.path(GIS_OUT_DIR, "accessible_area_lga_ward_portions.csv"))

cat(sprintf("\nWrote %d LGA-ward-portion x pop_type rows to %s\n", nrow(final_layer), GIS_OUT_DIR))
for (pt in c("Non-IDP", "IDP")) {
  sub <- final_layer %>% filter(pop_type == pt)
  inacc <- sub %>% filter(accessible_status == "Inaccessible")
  cat(sprintf("%s: %d portions | area: %.0f km2 total, %.1f%% inaccessible | population: %.0f total, %.1f%% inaccessible\n",
              pt, nrow(sub), sum(sub$area_km2),
              100 * sum(inacc$area_km2) / sum(sub$area_km2),
              sum(sub$pop_total),
              100 * sum(inacc$pop_total) / sum(sub$pop_total)))
}
