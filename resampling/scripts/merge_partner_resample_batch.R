# ==============================================================================
# Generalized from merge_intersos_resample_2026-08-30.R - merges one
# partner's staged resample (Non-IDP + IDP) into the live FULL/WORKING
# frame. Same verified mechanism, parameterized by partner name / staging
# dir / shortfalls CSVs instead of hardcoding INTERSOS's own paths.
#
# Usage: Rscript merge_partner_resample_batch.R <PartnerName> <staging_dir> <shortfalls_csv> <shortfalls_idp_csv>
#
# PRECONDITION: archive output/data/data_collection/ before running this -
# not done automatically here, since the archive should capture the state
# BEFORE this specific partner's merge, and the caller knows the right
# archive label for that.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(tibble) })
source("scripts/shared/assert_fresh.R")
source("scripts/shared/assert_plausible.R")
MASTER_WARD_CSV <- "resampling/output/master_accessibility_status_ward_level.csv"

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("Usage: Rscript merge_partner_resample_batch.R <PartnerName> <staging_dir> <shortfalls_csv> <shortfalls_idp_csv>")
PARTNER <- args[1]
STAGING <- args[2]
SHORTFALLS_CSV <- args[3]
SHORTFALLS_IDP_CSV <- args[4]
DC_DIR  <- "output/data/data_collection"

PARTNER_PCODES <- unique(c(
  read_csv(SHORTFALLS_CSV, show_col_types = FALSE)$adm2_pcode,
  read_csv(SHORTFALLS_IDP_CSV, show_col_types = FALSE)$adm2_pcode
))

log_lines <- character(0)
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); log_lines <<- c(log_lines, m) }

log_msg("==== Merge %s resample into live frame - %s ====", PARTNER, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
log_msg("Partner LGAs (%d): %s", length(PARTNER_PCODES), paste(PARTNER_PCODES, collapse = ", "))

# ---- Load live frame ----
full_hh    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
working_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE)
full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"), show_col_types = FALSE)

live_survey_ids <- union(full_hh$survey_id, working_hh$survey_id)
live_cluster_ids <- union(full_hh$cluster_id, working_hh$cluster_id)

# ---- Load staged rows (each file may be genuinely empty - a partner can
# fully clear Non-IDP but need nothing for IDP, or vice versa; the batch
# draw scripts write empty-but-present CSVs for that case rather than
# omitting the file) ----
read_or_empty <- function(path) {
  if (!file.exists(path)) return(tibble())
  df <- read_csv(path, show_col_types = FALSE)
  if (nrow(df) == 0) return(tibble())
  df
}
# ---- Freshness gate (2026-09-08 rebuild): the 2026-09-07 incident happened
# because nothing checked the staged household files were actually stamped
# with CURRENT ward accessibility before merging - stamp_ward_accessible_
# status.py existed but nothing enforced running it. This blocks rather than
# silently trusting whatever's in the staged file. mode="stop" deliberately -
# this writes into a staged file a human may be actively constructing, so it
# never gets auto-run, only ever blocks with the exact command to fix it.
for (staged_name in c("new_households.csv", "new_households_idp.csv")) {
  staged_path <- file.path(STAGING, staged_name)
  if (file.exists(staged_path)) {
    assert_fresh(
      artifact_path = staged_path,
      source_paths = MASTER_WARD_CSV,
      mode = "stop",
      fix_hint = sprintf('python "scripts/shared/../../resampling/scripts/stamp_ward_accessible_status.py" "%s"', staged_path),
      label = staged_name
    )
  }
}

new_clusters_nonidp <- read_or_empty(file.path(STAGING, "new_clusters.csv"))
new_hh_nonidp        <- if (nrow(new_clusters_nonidp) > 0) read_or_empty(file.path(STAGING, "new_households.csv")) %>% filter(cluster_id %in% new_clusters_nonidp$cluster_id) else tibble()
new_clusters_idp      <- read_or_empty(file.path(STAGING, "new_clusters_idp.csv"))
new_hh_idp            <- if (nrow(new_clusters_idp) > 0) read_or_empty(file.path(STAGING, "new_households_idp.csv")) %>% filter(cluster_id %in% new_clusters_idp$cluster_id) else tibble()
target_increases_idp  <- read_or_empty(file.path(STAGING, "existing_cluster_target_increases_idp.csv"))
additions_idp         <- if (nrow(target_increases_idp) > 0) read_or_empty(file.path(STAGING, "existing_cluster_household_additions_idp.csv")) %>% filter(cluster_id %in% target_increases_idp$cluster_id) else tibble()

# Site-level IDP batch (Option B, draw_supplementary_idp_sites_batch.R,
# decided 2026-09-02 - see project memory "IDP site-level PSU redesign").
# Separate files (new_clusters_idp_sitelevel.csv / new_households_idp_
# sitelevel.csv) rather than overloading the hex-based names, since the two
# mechanisms coexist going forward (existing IDP clusters stay hex-based;
# new ones from here on are site-based) and staging output should make that
# obvious at a glance, not just via the psu_definition_version column.
new_clusters_idp_site <- read_or_empty(file.path(STAGING, "new_clusters_idp_sitelevel.csv"))
new_hh_idp_site       <- if (nrow(new_clusters_idp_site) > 0) read_or_empty(file.path(STAGING, "new_households_idp_sitelevel.csv")) %>% filter(cluster_id %in% new_clusters_idp_site$cluster_id) else tibble()

log_msg("Loaded: %d new Non-IDP cluster(s)/%d hh, %d new IDP cluster(s) [hex_v1]/%d hh, %d new IDP cluster(s) [site_v2]/%d hh, %d existing IDP cluster(s) to expand/%d additional hh.",
        nrow(new_clusters_nonidp), nrow(new_hh_nonidp), nrow(new_clusters_idp), nrow(new_hh_idp),
        nrow(new_clusters_idp_site), nrow(new_hh_idp_site),
        nrow(target_increases_idp), nrow(additions_idp))

if (nrow(new_hh_nonidp) == 0 && nrow(new_hh_idp) == 0 && nrow(new_hh_idp_site) == 0 && nrow(additions_idp) == 0) {
  log_msg("==== DONE. Nothing to merge for %s - all staged batches were empty. ====", PARTNER)
  quit(save = "no", status = 0)
}

# ---- Pre-flight: nothing here should already exist live ----
stopifnot(
  "New Non-IDP cluster_ids already exist live" = !any(new_clusters_nonidp$cluster_id %in% live_cluster_ids),
  "New IDP cluster_ids already exist live" = !any(new_clusters_idp$cluster_id %in% live_cluster_ids),
  "New site-level IDP cluster_ids already exist live" = !any(new_clusters_idp_site$cluster_id %in% live_cluster_ids),
  "New survey_ids collide with the live frame" = !any(c(new_hh_nonidp$survey_id, new_hh_idp$survey_id, new_hh_idp_site$survey_id, additions_idp$survey_id) %in% live_survey_ids),
  "Existing clusters to expand are NOT currently live" = all(target_increases_idp$cluster_id %in% live_cluster_ids)
)
log_msg("Pre-flight checks passed: no ID collisions with the live frame.")

# ---- Add coverage columns to genuinely-new cluster household rows ----
# Verified directly (2026-08-30) that every one of this partner's LGAs is
# already single-partner covered in the live frame - new rows inherit the
# same values, not recomputed.
add_coverage_cols <- function(df) {
  if (nrow(df) == 0) return(df)
  df %>% mutate(coverage_status = "covered", exclusion_reason = "none", partners_covering = PARTNER)
}
new_hh_nonidp   <- add_coverage_cols(new_hh_nonidp)
new_hh_idp      <- add_coverage_cols(new_hh_idp)
new_hh_idp_site <- add_coverage_cols(new_hh_idp_site)

# ---- Backfill psu_definition_version on the LIVE frame before schema
# comparison (2026-09-02, first run after the site-level IDP mechanism
# exists) - every row fielded before today is hex-based; only IDP rows get
# a real tag (Non-IDP has always been single-mechanism, no ambiguity to
# track). Must happen before drop_non_schema() below, which uses
# names(working_hh) as the reference schema - if this column didn't exist
# on working_hh yet, a genuinely-new site_v2 row's own tag would be silently
# dropped as "non-schema" rather than backfilling the old rows.
if (!"psu_definition_version" %in% names(full_hh)) {
  full_hh$psu_definition_version    <- if_else(full_hh$pop_type == "idp", "hex_v1", NA_character_)
  working_hh$psu_definition_version <- if_else(working_hh$pop_type == "idp", "hex_v1", NA_character_)
  log_msg("Added psu_definition_version column - backfilled 'hex_v1' on %d existing IDP row(s) (FULL) / %d (WORKING); NA for Non-IDP.",
          sum(full_hh$pop_type == "idp"), sum(working_hh$pop_type == "idp"))
}

drop_non_schema <- function(df, label) {
  if (nrow(df) == 0) return(df)
  non_schema_cols <- setdiff(names(df), names(working_hh))
  if (length(non_schema_cols) > 0) {
    log_msg("Dropping %d non-schema column(s) from staged %s rows before merge: %s", length(non_schema_cols), label, paste(non_schema_cols, collapse = ", "))
    df <- df %>% select(-all_of(non_schema_cols))
  }
  df
}
new_hh_nonidp   <- drop_non_schema(new_hh_nonidp, "Non-IDP")
new_hh_idp      <- drop_non_schema(new_hh_idp, "IDP")
new_hh_idp_site <- drop_non_schema(new_hh_idp_site, "IDP site-level")

# CSV round-trip type harmonization (see merge_intersos_resample_2026-08-30.R
# for why this is needed - digit-only pcode columns guess inconsistently).
harmonize_types <- function(df, reference) {
  if (nrow(df) == 0) return(df)
  for (col in intersect(names(df), names(reference))) {
    target_class <- class(reference[[col]])[1]
    df[[col]] <- switch(target_class,
      character = as.character(df[[col]]),
      numeric = as.numeric(df[[col]]),
      integer = as.integer(df[[col]]),
      logical = as.logical(df[[col]]),
      df[[col]]
    )
  }
  df
}
new_hh_nonidp   <- harmonize_types(new_hh_nonidp, working_hh)
new_hh_idp      <- harmonize_types(new_hh_idp, working_hh)
new_hh_idp_site <- harmonize_types(new_hh_idp_site, working_hh)
additions_idp   <- harmonize_types(additions_idp, working_hh)

all_new_rows <- bind_rows(new_hh_nonidp, new_hh_idp, new_hh_idp_site, additions_idp)
if (nrow(all_new_rows) > 0) {
  # tier2_fallback_used/site_radius_m were added to the LIVE frame via a
  # one-off patch script (patch_site_radius_and_tier2_flag.R), never folded
  # into finalize_households()/select_stage2_idp_sites() itself - so a
  # freshly-drawn batch never carries them natively. Last night's INTERSOS/
  # IMC/FACT merges accidentally had a non-empty additions_idp (existing-
  # cluster IDP rows, template-copied directly from the live frame) that
  # happened to carry these columns and silently backfilled them for the
  # whole batch via bind_rows() - found broken 2026-08-31 on COOPI, which
  # has zero IDP shortfall and so no such lucky source. Fix generically:
  # add any of working_hh's columns missing from this batch as NA before
  # selecting, rather than assuming every column is already present.
  missing_cols <- setdiff(names(working_hh), names(all_new_rows))
  if (length(missing_cols) > 0) {
    log_msg("Adding %d column(s) missing from every staged source this batch, as NA: %s", length(missing_cols), paste(missing_cols, collapse = ", "))
    for (col in missing_cols) all_new_rows[[col]] <- NA
  }
  all_new_rows <- all_new_rows %>% select(all_of(names(working_hh)))
}

if (anyDuplicated(all_new_rows$survey_id) > 0) stop("Duplicate survey_id within the new-rows batch itself.")
log_msg("Total new household row(s) to append (both FULL and WORKING - all %s LGAs are covered): %d", PARTNER, nrow(all_new_rows))

# ---- Append new rows ----
# WORKING must exclude any new row whose ward is ward_accessible_status ==
# "Inaccessible" - this matters specifically for the Stage F "repeat-site
# merge" path (draw_supplementary_idp_clusters_batch.R): build_additional_
# rows() templates a new row directly off an EXISTING cluster's own row,
# which correctly carries that cluster's real ward_accessible_status - so
# if the repeat-site draw merged into an already-inaccessible cluster (as
# happened 2026-09-02: idp_NG021014_6/Funtua and 4 other FACT clusters),
# the new rows are themselves genuinely inaccessible too, not just their
# stale siblings. Appending unconditionally to working_hh (as this used to
# do) put 60 such rows live in WORKING - a stratum with zero real
# achievable IDP sample was showing a nonzero achieved_sample/realized_moe
# as a result.
#
# CORRECTED 2026-09-08 (was wrong, and was the root cause of the 2026-09-07
# incident): the paragraph above used to also claim a genuinely new cluster's
# ward_accessible_status gets computed on 04_build_master_accessibility_
# status.py's "next run", and let NA default to included on that basis.
# Traced during the incident: that claim was false, no script ever performed
# that join - the freshness gate above (stamp_ward_accessible_status.py,
# enforced via assert_fresh()) is what actually guarantees this column is
# populated before we get here, not a later run of anything. Given that, a
# row that's STILL NA at this point means the stamping script couldn't match
# its ward at all (a genuine geography reconciliation gap, not "not yet
# computed") - per the 2026-09-08 rebuild's accessibility rules, unmatched/
# unknown defaults to EXCLUDED, not accessible (asymmetric risk: wrongly
# excluding costs a review cycle, wrongly including risks fielding somewhere
# we don't actually know is safe). Excluded-for-unmatched rows are logged
# below, not silently dropped.
full_hh_new    <- bind_rows(full_hh, all_new_rows)
unmatched_ward_rows <- all_new_rows %>% filter(is.na(ward_accessible_status))
if (nrow(unmatched_ward_rows) > 0) {
  log_msg("WARNING: %d new row(s) have no ward_accessible_status match (unmatched geography, not 'not yet computed') - excluded from WORKING pending review: %s",
          nrow(unmatched_ward_rows), paste(unique(unmatched_ward_rows$cluster_id), collapse = ", "))
  needs_review_path <- file.path(STAGING, "NEEDS_REVIEW_unmatched_ward_status.csv")
  write_csv(unmatched_ward_rows, needs_review_path)
  log_msg("Unmatched rows written to %s for the accessibility review queue.", needs_review_path)
}
working_new_rows <- all_new_rows %>% filter(!is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible")

# 2026-09-05, Jack's threshold decision (same evening, discussed after the
# ward-accessibility fix above): a Non-IDP cluster with FEWER than
# NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH (4) accessible primary households
# total is excluded from WORKING entirely, not just its individually-
# inaccessible rows - those few remaining accessible households sit
# closest to the inaccessible ward's boundary (least reliable to safely
# collect), a dedicated visit for 1-3 households is inefficient, and the
# stratum-level supplementary draw is expected to close the gap instead.
# See 1_sampling/CLAUDE.md's Revision 2026-09-05. Mirrored (duplicated,
# not imported) from the identical logic in refresh_working_frame_daily.R
# and build_partner_dc_packages.py - same threshold, same counting basis.
# Computed from full_hh_new (existing + this batch's new rows together) so
# a repeat-site merge that pushes an EXISTING cluster below the threshold
# is caught too, not just brand-new clusters. This is defense-in-depth,
# not the sole enforcement point: refresh_working_frame_daily.R rebuilds
# WORKING wholesale on its own repeatable cadence and would catch this
# regardless the next time it runs - this just closes the gap between a
# merge and that next run. IDP is unaffected (single-point sites, no
# straddling-hex/accessible-household-count concept applies).
NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH <- 4
# 2026-09-08: flipped from is.na(...) | != "Inaccessible" (NA counted as
# accessible) to !is.na(...) & != "Inaccessible" (NA excluded) - same
# rationale as the freshness-gated exclusion above, applied consistently
# here so this threshold check can't be fooled by an unmatched row either.
cluster_accessible_primary_n <- full_hh_new %>%
  filter(pop_type == "non_idp", status == "primary", !is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible") %>%
  count(cluster_id, name = "n_accessible_primary")
below_threshold_clusters <- cluster_accessible_primary_n %>%
  filter(n_accessible_primary < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH) %>%
  pull(cluster_id)
n_before_threshold <- nrow(working_new_rows)
working_new_rows <- working_new_rows %>% filter(!(pop_type == "non_idp" & cluster_id %in% below_threshold_clusters))
n_excluded_below_threshold <- n_before_threshold - nrow(working_new_rows)
if (n_excluded_below_threshold > 0) {
  log_msg("Excluding %d further new row(s) from WORKING - their Non-IDP cluster has fewer than %d accessible primary households total.", n_excluded_below_threshold, NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH)
}

n_excluded_from_working <- nrow(all_new_rows) - nrow(working_new_rows)
if (n_excluded_from_working > 0) {
  log_msg("Excluding %d new row(s) from WORKING total (ward_accessible_status == \"Inaccessible\" and/or below-threshold cluster - included in FULL only).", n_excluded_from_working)
}
working_hh_new <- bind_rows(working_hh, working_new_rows)

# ---- Update target_households/reserve_households/selection_count on expanded existing IDP clusters ----
# Applied AFTER binding, to every row of an affected cluster_id uniformly -
# this must include the newly-appended additions_idp rows themselves, which
# draw_supplementary_idp_clusters_batch.R's build_additional_rows() templates
# off the cluster's PRE-increase value (a direct copy of an existing row, at
# the point before this increase is known) - applying the increase only to
# the pre-bind rows (as this used to do) leaves those appended rows carrying
# the stale target forever. Found 2026-09-02 (FACT merge): the old ordering
# left 20 expanded clusters with target_households/selection_count that
# differed across their own rows - some updated, some not. Safe to add
# increase_target once uniformly post-bind because every row of an affected
# cluster - old and newly-templated alike - still holds the same pre-
# increase baseline value at this point, before this function has touched
# any of them.
apply_target_increase <- function(hh_df) {
  if (nrow(target_increases_idp) == 0) return(hh_df)
  hh_df %>%
    left_join(target_increases_idp %>% select(cluster_id, increase_target, increase_reserve), by = "cluster_id") %>%
    mutate(
      target_households = if_else(!is.na(increase_target), target_households + increase_target, target_households),
      reserve_households = if_else(!is.na(increase_reserve), reserve_households + increase_reserve, reserve_households),
      selection_count = if_else(!is.na(increase_target), selection_count + as.integer(increase_target / 6L), selection_count)
    ) %>%
    select(-increase_target, -increase_reserve)
}
full_hh_new    <- apply_target_increase(full_hh_new)
working_hh_new <- apply_target_increase(working_hh_new)
if (nrow(target_increases_idp) > 0) {
  log_msg("Updated target_households/reserve_households/selection_count uniformly across all rows (existing + newly-appended) for %d expanded cluster(s) (both FULL and WORKING).", nrow(target_increases_idp))
}

# ---- Verification, not assumed ----
if (anyDuplicated(full_hh_new$survey_id) > 0) stop("Duplicate survey_id in merged FULL frame.")
if (anyDuplicated(working_hh_new$survey_id) > 0) stop("Duplicate survey_id in merged WORKING frame.")
expected_full    <- nrow(full_hh) + nrow(all_new_rows)
expected_working <- nrow(working_hh) + nrow(working_new_rows)
if (nrow(full_hh_new) != expected_full) stop("FULL row count mismatch after merge.")
if (nrow(working_hh_new) != expected_working) stop("WORKING row count mismatch after merge.")
log_msg("Verified: zero duplicate survey_ids, row counts match exactly. FULL %d -> %d, WORKING %d -> %d.",
        nrow(full_hh), nrow(full_hh_new), nrow(working_hh), nrow(working_hh_new))

# ---- Strata-level CSV: recompute achieved_clusters/achieved_sample/realized_moe_pct ----
# target_sample/clusters_target_stage1/projected_moe_pct left untouched, per
# CLAUDE.md's 2026-07-15 fix and Jack's 2026-08-30 call to batch the
# target_sample recalibration separately at the end of this partner round.
#
# 2026-09-05 fix: recompute_strata() previously counted every primary row
# for a stratum regardless of ward_accessible_status - only the NEW-row
# append above (working_new_rows, line ~196) ever excluded an inaccessible
# row, and only at the moment it's first merged in. A cluster accessible
# when drawn but marked inaccessible LATER (a ward-level accessibility
# update, independent of any merge) was never rechecked - its rows stayed
# counted in WORKING's achieved_sample forever after, even though row-level
# ward_accessible_status on the SAME row correctly showed "Inaccessible".
# Found 2026-09-04/05 (Jack: FACT's dashboard achieved 6,946 vs this
# workbook's 7,118 - traced to strata where achieved_sample was up to 2x
# target_sample, which should be structurally impossible under a correctly
# capped supplementary-draw mechanism). Verified nationally: applying this
# filter resolves 63 of 75 affected strata completely (2,897 -> 51
# household gap). FULL is deliberately NOT filtered here - it's the
# complete, unfiltered historical record of every row ever drawn (verified
# self-consistent, 0 mismatches nationally, 2026-09-05) and stays that way;
# only WORKING's achieved figures are meant to reflect "currently fieldable
# right now", which requires this filter.
#
# 2026-09-05, SAME EVENING - stranded-achieved credit, plus a related fix
# to what this function reads its row-set FROM. Jack asked what happens to
# real, already-collected data when its area later becomes inaccessible, or
# a straddling cluster drops below the 4-accessible-HH threshold added
# earlier tonight - answer: it was being silently treated as still-
# outstanding capacity, inflating the shortfall the supplementary draw gets
# sized against (asking for NEW households to replace work already done).
# Fixed the same way as refresh_working_frame_daily.R's identical fix: a
# row now excluded (ward_accessible_status == "Inaccessible") that ALREADY
# has a real completed interview is added back into achieved_sample
# specifically - not into household-level WORKING, which correctly still
# excludes it. Non-IDP: exact survey_id join. IDP: count-based per cluster,
# capped at min(excluded rows, achieved count).
#
# This requires this function to read from full_hh_new (every row ever
# drawn, achieved or not, accessible or not), not working_hh_new as before
# - found while implementing the above that working_hh_new was actually the
# WRONG source for this function's WORKING call even before today's fix:
# working_hh (loaded fresh from the on-disk WORKING CSV) already has
# field-achieved rows dropped by the last daily refresh (that CSV is the
# household-level to-do list, not a design-capacity record), so counting
# achieved_sample from it silently UNDER-counted "currently accessible
# design capacity" by however many rows the to-do-list drop had already
# removed - the opposite-direction sibling of the stranded-achieved
# over-exclusion this section fixes. Both are fixed together by having this
# function do its OWN complete ward-accessible filtering (and stranded-
# achieved crediting) from full_hh_new, rather than trusting a pre-filtered
# hh_df - self-contained, matching refresh_working_frame_daily.R's approach
# exactly (which computes strata-level achieved_sample from FULL-derived
# covered_accessible, never from the household-level WORKING output, for
# precisely this reason). In practice this under-count was transient - the
# next daily refresh always overwrote it - but there's no reason to leave a
# merge's own immediate output wrong in the meantime.
# 2026-09-07, superseding the 2026-09-06 hardcoded-list stopgap: the
# permanent mechanism is ready now - reads 2_monitoring's
# CONFIRMED_DELETIONS_OVERLAY.csv directly (status=="confirmed"), same as
# refresh_working_frame_daily.R's identical block and
# 05_build_accessibility_impact_workbook.py's load_real_achieved(). Found
# during the pre-resampling-run readiness check that the tracker had grown
# past duration_under_20/fcs_zero since the previous night (639 confirmed,
# up from 627) via the genuine partner-confirmation channel - the old
# hardcoded list would have silently missed those. See
# refresh_working_frame_daily.R for the full reasoning.
CONFIRMED_DELETIONS_OVERLAY_CSV <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv"
deletions_overlay <- read_csv(CONFIRMED_DELETIONS_OVERLAY_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
confirmed_deletion_uuids <- deletions_overlay %>% filter(status == "confirmed") %>% pull(uuid)

# 2026-09-08 audit fix: was the dashboard_app/data/ bundled mirror, only
# refreshed as a side effect of a full dashboard deploy - same bug class
# already fixed in refresh_working_frame_daily.R and build_partner_dc_
# packages.py (see their own fix notes) but missed here. Byte-identical to
# canonical at the time of the fix (verified via md5), so this was a live
# landmine, not yet a wrong number - would have silently drifted the next
# time canonical updated without an intervening deploy.
REAL_SUBMISSIONS_CSV <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring/data/real_submissions.csv"
subs <- read_csv(REAL_SUBMISSIONS_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
achieved <- subs %>%
  filter(
    interview_outcome == "completed",
    is_duplicate != "TRUE",
    !(matched_survey_id %in% c(NA, "", "NA")),
    !(submission_uuid %in% confirmed_deletion_uuids)
  )
achieved_non_idp_survey_ids <- achieved %>% filter(pop_type == "non_idp") %>% pull(matched_survey_id) %>% unique()
achieved_idp_counts <- achieved %>% filter(pop_type == "idp") %>% count(matched_cluster_id, matched_status, name = "n_achieved")

realized_moe <- function(achieved_sample, N_hh, m, ICC, Z = qnorm(0.95), p = 0.5) {
  deff  <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

recompute_strata <- function(sl_df, hh_df, filter_ward_accessible = FALSE) {
  affected_strata <- unique(all_new_rows$strata_id)
  base <- hh_df %>% filter(strata_id %in% affected_strata, status == "primary")
  if (filter_ward_accessible) {
    # 2026-09-08: flipped so NA (unmatched geography) counts as excluded, not
    # accessible - consistent with the merge-time gate above. NA rows still
    # correctly flow into `excluded` below, so the stranded-achieved credit
    # logic still protects a genuinely-completed interview even when the
    # reason it's excluded is an unmatched ward rather than a confirmed
    # Inaccessible status - a data-matching gap shouldn't cost a real
    # achievement any more than a confirmed accessibility change should.
    accessible <- base %>% filter(!is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible")
    excluded <- base %>% filter(is.na(ward_accessible_status) | ward_accessible_status == "Inaccessible")

    stranded_non_idp <- excluded %>% filter(pop_type == "non_idp", survey_id %in% achieved_non_idp_survey_ids)

    idp_excluded <- excluded %>% filter(pop_type == "idp")
    idp_stranded_n <- idp_excluded %>%
      count(cluster_id, name = "n_excluded") %>%
      left_join(achieved_idp_counts %>% filter(matched_status == "primary") %>% select(cluster_id = matched_cluster_id, n_achieved), by = "cluster_id") %>%
      mutate(n_achieved = coalesce(n_achieved, 0L), n_stranded = pmin(n_excluded, n_achieved)) %>%
      filter(n_stranded > 0)
    stranded_idp <- idp_excluded %>%
      inner_join(idp_stranded_n %>% select(cluster_id, n_stranded), by = "cluster_id") %>%
      mutate(interview_number_num = as.integer(interview_number)) %>%
      group_by(cluster_id) %>%
      arrange(interview_number_num, .by_group = TRUE) %>%
      filter(row_number() <= n_stranded) %>%
      ungroup() %>%
      select(-interview_number_num)

    if (nrow(stranded_non_idp) + nrow(stranded_idp) > 0) {
      log_msg("  Stranded-achieved credit added back for this merge's affected strata: %d Non-IDP + %d IDP.", nrow(stranded_non_idp), nrow(stranded_idp))
    }
    eligible <- bind_rows(accessible, stranded_non_idp, stranded_idp)
  } else {
    eligible <- base
  }
  agg <- eligible %>%
    group_by(strata_id) %>%
    summarise(achieved_clusters_new = n_distinct(cluster_id), achieved_sample_new = n(), .groups = "drop")
  if (filter_ward_accessible) {
    # every affected stratum must appear here, even one filtered down to
    # zero eligible rows - otherwise left_join below can't distinguish
    # "not in agg because untouched by this run" (keep the old value) from
    # "not in agg because every one of its rows is now ward-inaccessible"
    # (should coalesce to 0, not silently keep a stale nonzero value).
    agg <- tibble(strata_id = affected_strata) %>%
      left_join(agg, by = "strata_id") %>%
      mutate(achieved_clusters_new = coalesce(achieved_clusters_new, 0L), achieved_sample_new = coalesce(achieved_sample_new, 0L))
  }

  sl_df %>%
    left_join(agg, by = "strata_id") %>%
    mutate(
      achieved_clusters = if_else(!is.na(achieved_clusters_new), achieved_clusters_new, achieved_clusters),
      achieved_sample = if_else(!is.na(achieved_sample_new), achieved_sample_new, achieved_sample),
      realized_moe_pct = if_else(
        !is.na(achieved_sample_new) & achieved_sample_new > 0 & achieved_sample_new < N_hh,
        100 * realized_moe(achieved_sample_new, N_hh, m_used, ICC),
        realized_moe_pct
      )
    ) %>%
    select(-achieved_clusters_new, -achieved_sample_new)
}
full_sl_new    <- recompute_strata(full_sl, full_hh_new, filter_ward_accessible = FALSE)
working_sl_new <- recompute_strata(working_sl, full_hh_new, filter_ward_accessible = TRUE)

changed_rows <- working_sl_new %>% filter(strata_id %in% unique(all_new_rows$strata_id)) %>%
  select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)
log_msg("Strata-level updated for %d affected stratum/strata:", nrow(changed_rows))
for (i in seq_len(nrow(changed_rows))) {
  log_msg("  %s: achieved_clusters=%d, achieved_sample=%d, realized_moe_pct=%.2f%%",
          changed_rows$strata_id[i], changed_rows$achieved_clusters[i], changed_rows$achieved_sample[i], changed_rows$realized_moe_pct[i])
}

# ---- Output-plausibility gate (2026-09-08 audit, pass 4) - same two checks
# as refresh_working_frame_daily.R, see that script for the full reasoning.
n_working_in_inaccessible_ward <- working_hh_new %>%
  filter(!is.na(ward_accessible_status), ward_accessible_status == "Inaccessible") %>%
  nrow()
assert_plausible("WORKING rows in a currently-Inaccessible ward", n_working_in_inaccessible_ward, c(0, 0),
                  context = "must always be exactly 0 - this is the 2026-09-07 incident's core invariant")

n_over_target <- working_sl_new %>% filter(achieved_sample > target_sample) %>% nrow()
assert_plausible("strata with achieved_sample > target_sample", n_over_target, c(0, 40),
                  context = "should be a small ordinary-rounding residual, not systemic overcounting")

# ---- Write ----
write_csv(full_hh_new, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"))
write_csv(working_hh_new, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"))
write_csv(full_sl_new, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"))
write_csv(working_sl_new, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"))
log_msg("Written: FULL + WORKING household-level and strata-level CSVs in %s.", DC_DIR)

writeLines(log_lines, file.path(STAGING, paste0("merge_", tolower(gsub("[^A-Za-z0-9]", "_", PARTNER)), "_log.txt")))
log_msg("==== DONE merging %s. ====", PARTNER)
