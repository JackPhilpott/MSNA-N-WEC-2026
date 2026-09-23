# ==============================================================================
# frame_status.R - canonical achieved/accessibility/cluster-status logic,
# 2026-09-13. Built to close a real, confirmed drift: refresh_working_frame_
# daily.R and merge_partner_resample_batch.R independently computed strata-
# level achieved_clusters/achieved_sample, and had already drifted twice -
# the below-4-accessible-primary-HH threshold (2026-09-05) and the MSNA
# Light sampling_method exclusion (2026-09-11) both landed in the first,
# confirmed missing from the second when this file was written. Unlike the
# rest of this project's "duplicated, not imported, per this project's
# standalone-script convention" pattern (deliberate everywhere else - see
# CLAUDE.md), this one file is a genuine shared `source()`, because THIS
# specific logic has now drifted twice in a way a comment convention alone
# didn't prevent. Both R scripts source() this file and call these
# functions directly - no copy-pasting the bodies back into either script.
#
# build_partner_dc_packages.py (Python) still keeps its own mirror of the
# core is_achieved()/threshold logic - a literal shared call across the R/
# Python boundary is a bigger, separate architecture decision than this
# file's scope, not attempted here. Flagged to Jack, not silently done.
#
# CORE PRINCIPLE (Jack's methodology call, 2026-09-13): a completed
# household interview is permanent and never retroactively excluded by
# later accessibility loss. Current accessibility only gates what's still
# PLANNED but not yet completed. The project's codebase had already
# independently arrived at most of this on 2026-09-05 ("stranded-achieved
# credit") - this file formalizes it and closes the drift gap, not a new
# direction.
#
# Four functions, meant to be called in this order:
#   1. compute_achieved_lookup()    - which specific submissions count as achieved
#   2. compute_cluster_accessibility() - which rows/clusters are currently reachable
#   3. compute_strata_achieved()    - strata-level achieved_clusters/achieved_sample
#   4. compute_cluster_status()     - per-cluster completed/partial/not-started status
# realized_moe_unequal() is a separate, later addition (Task 4, distribution-
# aware DEFF) - see its own header below.
# ==============================================================================
suppressMessages({ library(dplyr) })

#' Cluster-level accessibility overlay (2026-09-13): the set of cluster_ids a
#' partner has explicitly reported inaccessible at CLUSTER level (as opposed
#' to the ward-level status every other mechanism here runs on), built by
#' resampling/scripts/build_cluster_accessibility_overlay.py from
#' resampling_requests_log.csv. Precedence rule (Jack, 2026-09-13): this only
#' ever ADDS an exclusion on top of ward-level status, never overrides it in
#' either direction - a cluster-level "Yes" on an inaccessible ward does NOT
#' get read from this file at all (build_cluster_accessibility_overlay.py
#' only ever emits the "No" set), so there is nothing here that could
#' override a ward-level exclusion back to accessible.
#'
#' Missing file returns character(0) (no exclusions) rather than erroring -
#' this overlay is additive/optional, unlike CONFIRMED_DELETIONS_OVERLAY.csv
#' which every caller already requires to exist.
load_cluster_accessibility_overlay <- function(path = "resampling/output/cluster_accessibility_overlay.csv") {
  if (!file.exists(path)) return(character(0))
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(.default = "c"))$cluster_id
}

#' Target-correction drop list (Task 5, 2026-09-13): clusters removed from
#' active capacity NOT because they're inaccessible, but because the
#' stratum's TRUE requirement (target_sample_representativity, Task 2) needs
#' fewer clusters than are currently assigned - excess, least-progressed-
#' first capacity, per resampling/scripts/compute_target_correction_drops.R.
#'
#' Deliberately excluded from compute_cluster_status()'s currently_
#' accessible/status computation (these clusters remain genuinely
#' accessible in the real world - being unneeded isn't the same fact as
#' being unreachable, and compute_target_correction_drops.R's own candidate
#' selection depends on "not_started_other" continuing to mean exactly
#' that). Folded ONLY into compute_cluster_accessibility()'s covered_
#' accessible (below) - which correctly (a) excludes these clusters from
#' WORKING, (b) still lets compute_strata_achieved() apply stranded-achieved
#' credit for any real progress a dropped cluster already had (19 of the
#' first 51 flagged did - this is not a hypothetical), and (c) correctly
#' zeroes Task 1's n_accessible_primary_post_threshold for them, since that
#' column is meant to mirror "real active capacity," which dropping
#' genuinely changes.
#'
#' Missing file returns character(0), same convention as the cluster-
#' accessibility overlay above.
load_target_correction_drops <- function(path = "resampling/output/target_correction_dropped_clusters.csv") {
  if (!file.exists(path)) return(character(0))
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(.default = "c"))$cluster_id
}

#' Which specific submissions count as "achieved" - the canonical is_achieved()
#' definition, mirrored from 2_monitoring/dashboard_app/global.R (duplicated
#' there deliberately, per this project's cross-repo convention - this file
#' only unifies the two R scripts WITHIN 1_sampling).
#'
#' @param subs_df real_submissions.csv, read as characters (col_types="c") -
#'   both existing call sites read it that way, so this function does too.
#' @param deletions_overlay_df CONFIRMED_DELETIONS_OVERLAY.csv, same read
#'   convention.
#' @return list(non_idp_survey_ids, idp_counts, n_total, n_achieved)
compute_achieved_lookup <- function(subs_df, deletions_overlay_df) {
  # 2026-09-13 fix, found while consolidating: build_partner_dc_packages.py
  # was fixed 2026-09-11 to treat "contested" as terminal alongside
  # "confirmed" (2_monitoring's own TERMINAL_STATUSES = {"confirmed",
  # "contested"} in issue_tracker.R) - a contest reviewed and REJECTED means
  # the deletion stands, equally final as a plain "confirmed" one. That fix
  # never made it into either R script (both only ever checked status ==
  # "confirmed") - verified directly: 10 "contested" rows exist nationally,
  # every one's resolution text reads "contest reviewed and rejected -
  # deletion stands", genuinely terminal, not "still pending review". Both R
  # scripts had been silently still counting these 10 as achieved since
  # 2026-09-11. Fixed here, in the one place both scripts now read from.
  #
  # 2026-09-14 fix (Coordinator's cross-check, msna-n-wec-2026-91): a
  # SEPARATE, independent `is_duplicate != "TRUE"` condition here was
  # excluding real_submissions.csv's own raw/automated duplicate-candidate
  # flag - a PENDING signal, not a confirmed deletion decision - on top of
  # the overlay check above. This silently reimposed the pre-2026-09-11
  # pessimistic policy (Jack: "the team would rather risk asking a field
  # team to go back for a specific interview later than have them oversample
  # now against a pessimistic count") through a side door the 2026-09-08
  # quality_exclusion_reason audit never looked at, since it's a different
  # column. Verified nationally before removing: 1,323 real completed
  # interviews were being wrongly excluded this way (is_duplicate=="TRUE"
  # but never actually confirmed/contested in the overlay) - about 7% of all
  # completed interviews. Only the overlay's confirmed/contested status is
  # authoritative for exclusion now, matching 2_monitoring's global.R
  # is_achieved() exactly - no independent raw-flag check here.
  TERMINAL_DELETION_STATUSES <- c("confirmed", "contested")
  confirmed_deletion_uuids <- deletions_overlay_df %>% filter(status %in% TERMINAL_DELETION_STATUSES) %>% pull(uuid)
  achieved <- subs_df %>%
    filter(
      interview_outcome == "completed",
      !(matched_survey_id %in% c(NA, "", "NA")),
      !(submission_uuid %in% confirmed_deletion_uuids)
    )
  list(
    non_idp_survey_ids = achieved %>% filter(pop_type == "non_idp") %>% pull(matched_survey_id) %>% unique(),
    idp_counts = achieved %>% filter(pop_type == "idp") %>% count(matched_cluster_id, matched_status, name = "n_achieved"),
    n_total = nrow(subs_df),
    n_achieved = nrow(achieved)
  )
}

#' Which rows/clusters are currently reachable - covered-and-not-excluded,
#' ward-accessible, and (Non-IDP only) above the below-4-accessible-primary-
#' household threshold. IDP is unaffected by the threshold - single-point
#' sites, no straddling-hex/accessible-household-count concept applies,
#' same reasoning documented at both existing call sites.
#'
#' @param full_df household-level FULL (or FULL+staged-new-rows) frame.
#' @param non_idp_min_accessible_primary_hh the threshold (4 at every
#'   existing call site - Jack's 2026-09-05 decision, CLAUDE.md "Revision
#'   2026-09-05").
#' @param cluster_overlay_excluded character vector of cluster_ids explicitly
#'   reported inaccessible at CLUSTER level (see load_cluster_accessibility_
#'   overlay() above) - additive on top of ward-level status, default reads
#'   the live overlay file. Pass character(0) to disable (e.g. for a
#'   before/after comparison).
#' @param target_correction_dropped character vector of cluster_ids excess
#'   to a stratum's corrected target (Task 5, see load_target_correction_
#'   drops() above) - default reads the live drop-list file. NOT an
#'   accessibility signal (these clusters are genuinely still reachable) -
#'   deliberately excluded from compute_cluster_status()'s own accessible/
#'   status computation, see that function's own comment.
#' @param ward_exempt_sampling_methods sampling_method values exempt from the
#'   ward_accessible_status gate below (default "MSNA Light" -
#'   government-negotiated, unverifiable collection that must stay available
#'   to field teams regardless of ward_accessible_status, per Jack's
#'   2026-09-11 design decision - see CLAUDE.md "Update 2026-09-11"). Found
#'   2026-09-14: this function had NO such exemption despite one already
#'   existing in compute_strata_achieved() below (added 2026-09-11, for the
#'   achieved-sample AGGREGATE only) - the two were never the same
#'   protection. Concretely, all 156 Guzamala/Mairari MSNA Light rows were
#'   silently absent from WORKING the entire time Mairari's ward was
#'   Inaccessible (Abadam/Nganzai only survived because their own wards
#'   happened to be Accessible - no code protected them either). Fixed here,
#'   generically, rather than per-LGA - protects all 3 MSNA Light LGAs now
#'   and any future one, not just today's Guzamala case.
#' @return list(covered, covered_accessible, below_threshold_clusters,
#'   cluster_overlay_excluded, target_correction_dropped)
compute_cluster_accessibility <- function(full_df, non_idp_min_accessible_primary_hh = 4,
                                           cluster_overlay_excluded = load_cluster_accessibility_overlay(),
                                           target_correction_dropped = load_target_correction_drops(),
                                           ward_exempt_sampling_methods = "MSNA Light") {
  covered <- full_df %>% filter(coverage_status == "covered", exclusion_reason == "none")

  # A row clears the ward gate either by a real Accessible ward status, or by
  # belonging to ward_exempt_sampling_methods (see @param above). NA
  # (unmatched ward geography) still counts as excluded for everyone else -
  # 2026-09-08 rebuild-wide rule, unaffected by this exemption. sampling_method
  # is NA for the vast majority of rows (pre-dates the column) - %in% against
  # NA correctly evaluates FALSE, not NA, so no separate is.na() guard is
  # needed on the exemption side (unlike not_msna_light() below, which
  # inverts the condition and so does need one).
  ward_gate <- function(df) {
    df %>% filter(
      (sampling_method %in% ward_exempt_sampling_methods) |
      (!is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible")
    )
  }

  # 2026-09-19 fix: a cluster with ZERO accessible primary rows never
  # survives ward_gate() at all, so a plain count(cluster_id) on the
  # ward-gated rows never produces a row for it (count() doesn't emit a
  # zero-count row for an empty group) - meaning it was invisible to the
  # below-threshold filter below and could never be captured by it, even
  # though 0 accessible primaries is the most extreme case the <4 threshold
  # is meant to catch (see the header note above this constant in
  # refresh_working_frame_daily.R: "Whole-cluster inaccessible clusters (0
  # accessible) already worked this way; this only extends the SAME
  # treatment to the 1-3-accessible case" - true only under the original,
  # simpler ward-only check; this count()-based threshold computation
  # reintroduced exactly that gap for the specific case where the cluster's
  # OTHER (non-primary) rows include one in a currently-accessible ward).
  # Found via build_partner_dc_packages.py's new standing UUID-
  # reconciliation check (2026-09-19) - 17 clusters/24 reserve rows
  # nationally were leaking into WORKING/KML this way. Fixed by starting
  # from the full set of primary cluster_ids (pre-ward-gate) and explicitly
  # filling in 0 for any cluster absent from the ward-gated count, instead
  # of filtering an already-incomplete count table.
  # 2026-09-21: the set to test must be EVERY Non-IDP cluster that has any
  # row at all, not only those with a primary row. The 2026-09-19 fix
  # started from primary cluster_ids, which still let a cluster with ZERO
  # primary rows (only reserve rows) through: it is absent from the primary
  # set, so it is never tested, so its reserve rows survive into WORKING/
  # KML even though 0 accessible primaries is the most below-threshold a
  # cluster can be. Found by the standing UUID reconciliation check on the
  # v11 packages: non_idp_NG036011_supp4 (FACT, Machina) was drawn by a
  # Tier 2 repeat draw with a single reserve household and no primary -
  # itself a draw_supplementary_clusters_batch.R gap fixed the same night
  # (it dropped zero-HOUSEHOLD clusters, not zero-PRIMARY ones). The Python
  # side (build_partner_dc_packages.py's Counter.get(cid, 0)) already read
  # such a cluster as 0 accessible primaries; this makes the R side agree.
  all_primary_clusters <- covered %>%
    filter(pop_type == "non_idp") %>%
    distinct(cluster_id)
  cluster_accessible_primary_n <- covered %>%
    filter(pop_type == "non_idp", status == "primary") %>%
    ward_gate() %>%
    count(cluster_id, name = "n_accessible_primary")
  below_threshold_clusters <- all_primary_clusters %>%
    left_join(cluster_accessible_primary_n, by = "cluster_id") %>%
    mutate(n_accessible_primary = coalesce(n_accessible_primary, 0L)) %>%
    filter(n_accessible_primary < non_idp_min_accessible_primary_hh) %>%
    pull(cluster_id)

  covered_accessible <- covered %>%
    ward_gate() %>%
    filter(!(cluster_id %in% below_threshold_clusters)) %>%
    filter(!(cluster_id %in% cluster_overlay_excluded)) %>%
    filter(!(cluster_id %in% target_correction_dropped))

  list(covered = covered, covered_accessible = covered_accessible,
       below_threshold_clusters = below_threshold_clusters,
       cluster_overlay_excluded = cluster_overlay_excluded,
       target_correction_dropped = target_correction_dropped)
}

#' Strata-level achieved_clusters/achieved_sample - the DESIGN-capacity
#' metric (how many primary slots the design has assigned that are
#' currently accessible OR were completed before access was lost), compared
#' against target_sample. NOT a count of real field interviews on its own -
#' see refresh_working_frame_daily.R's header for the terminology note this
#' project has needed twice already.
#'
#' Two modes, matching both scripts' existing behaviour exactly:
#'   filter_ward_accessible = TRUE  (WORKING): ward-accessible + above-
#'     threshold rows, PLUS stranded-achieved credit for now-excluded rows
#'     that already have a real completed interview (so the shortfall never
#'     double-asks for work already done).
#'   filter_ward_accessible = FALSE (FULL): every primary row ever drawn for
#'     the stratum, completely unfiltered - FULL is the complete historical
#'     record regardless of current accessibility.
#'
#' 2026-09-22 (R6, Jack approved directly): MSNA Light now counts toward
#' strata-level achieved_clusters/achieved_sample same as Full Design -
#' this function used to strip sampling_method %in% exclude_sampling_methods
#' (default "MSNA Light") out of the WORKING-mode figure; that exclusion and
#' its parameter are removed. See 05_build_accessibility_impact_workbook.py's
#' main() for the fuller R6 note (same policy, same day, mirrored here since
#' this is the one shared - not duplicated - copy of the aggregation logic).
#'
#' @param full_df household-level FULL (or FULL+staged-new-rows) frame.
#' @param achieved_lookup from compute_achieved_lookup().
#' @param accessibility from compute_cluster_accessibility() - required only
#'   when filter_ward_accessible = TRUE.
#' @param filter_ward_accessible see above.
#' @return list(agg = tibble(strata_id, achieved_clusters, achieved_sample),
#'   cluster_sizes = tibble(strata_id, cluster_id, n) for Task 4's
#'   distribution-aware DEFF, stranded_rows)
compute_strata_achieved <- function(full_df, achieved_lookup, accessibility = NULL,
                                     filter_ward_accessible) {
  if (!filter_ward_accessible) {
    eligible <- full_df %>% filter(status == "primary")
    agg <- eligible %>% group_by(strata_id) %>%
      summarise(achieved_clusters = n_distinct(cluster_id), achieved_sample = n(), .groups = "drop")
    cluster_sizes <- eligible %>% count(strata_id, cluster_id, name = "n")
    return(list(agg = agg, cluster_sizes = cluster_sizes, stranded_rows = full_df[0, ]))
  }

  stopifnot(!is.null(accessibility))
  covered <- accessibility$covered
  covered_accessible <- accessibility$covered_accessible
  below_threshold_clusters <- accessibility$below_threshold_clusters
  cluster_overlay_excluded <- accessibility$cluster_overlay_excluded
  target_correction_dropped <- accessibility$target_correction_dropped

  excluded_primary <- covered %>%
    filter(status == "primary") %>%
    filter(
      (is.na(ward_accessible_status) | ward_accessible_status == "Inaccessible") |
      (pop_type == "non_idp" & cluster_id %in% below_threshold_clusters) |
      (cluster_id %in% cluster_overlay_excluded) |
      (cluster_id %in% target_correction_dropped)
    )

  stranded_non_idp <- excluded_primary %>% filter(pop_type == "non_idp", survey_id %in% achieved_lookup$non_idp_survey_ids)

  idp_excluded <- excluded_primary %>% filter(pop_type == "idp")
  idp_cluster_stranded_n <- idp_excluded %>%
    count(cluster_id, name = "n_excluded") %>%
    left_join(achieved_lookup$idp_counts %>% filter(matched_status == "primary") %>% select(cluster_id = matched_cluster_id, n_achieved), by = "cluster_id") %>%
    mutate(n_achieved = coalesce(n_achieved, 0L), n_stranded = pmin(n_excluded, n_achieved)) %>%
    filter(n_stranded > 0)
  stranded_idp <- idp_excluded %>%
    inner_join(idp_cluster_stranded_n %>% select(cluster_id, n_stranded), by = "cluster_id") %>%
    mutate(interview_number_num = as.integer(interview_number)) %>%
    group_by(cluster_id) %>%
    arrange(interview_number_num, .by_group = TRUE) %>%
    filter(row_number() <= n_stranded) %>%
    ungroup() %>%
    select(-interview_number_num)

  stranded_rows <- bind_rows(stranded_non_idp, stranded_idp)

  eligible <- bind_rows(
    covered_accessible %>% filter(status == "primary"),
    stranded_rows
  )
  agg <- eligible %>% group_by(strata_id) %>%
    summarise(achieved_clusters = n_distinct(cluster_id), achieved_sample = n(), .groups = "drop")
  cluster_sizes <- eligible %>% count(strata_id, cluster_id, name = "n")

  list(agg = agg, cluster_sizes = cluster_sizes, stranded_rows = stranded_rows)
}

#' Real per-cluster status (Task 3, 2026-09-13): completed / partially_
#' completed_access_lost / not_started_access_lost / not_started_other -
#' so a cluster with some completed households and access lost before the
#' rest could be reached is distinctly flagged, not folded into the below-
#' threshold "drop the whole cluster" treatment.
#'
#' Definitions (documented explicitly - the "not_started_other" label is a
#' residual/catch-all, not literally "zero achieved"):
#'   completed: achieved count >= this cluster's target_households, REGARDLESS
#'     of current accessibility (once done, always done).
#'   partially_completed_access_lost: 0 < achieved < target, AND currently
#'     inaccessible (ward-inaccessible, or - Non-IDP only - below the 4-
#'     accessible-primary-HH threshold).
#'   not_started_access_lost: achieved == 0, AND currently inaccessible.
#'   not_started_other: everything else - covers BOTH a genuinely
#'     not-yet-visited cluster that's still accessible AND a partially-
#'     completed cluster that's still accessible (ordinary, ongoing
#'     fieldwork - not an access-loss story either way). Named to match
#'     the 4-value taxonomy as specified; if a caller needs to distinguish
#'     "0 achieved, accessible" from "partial, accessible" specifically,
#'     that's a real 5th category this function does not currently produce
#'     - flagged as a scoping choice, not an oversight.
#'
#' No automatic nonresponse weight adjustment happens here or anywhere else
#' in this codebase - this function only labels status. Any future weight
#' adjustment for the access-lost categories must be a small, capped,
#' explicitly documented exception applied elsewhere, never a default this
#' function triggers.
#'
#' 2026-09-13 (Task 1 of the target-inflation-fix batch): also carries
#' n_accessible_primary_post_threshold - the count of this cluster's primary
#' rows that survive compute_cluster_accessibility()'s FULL filter chain
#' (ward-accessible, above the below-4-threshold, not cluster-overlay-
#' excluded), i.e. exactly what's actually in covered_accessible for this
#' cluster - 0 for a fully-excluded cluster, otherwise the real accessible-
#' row count (which can be less than the cluster's full primary count for a
#' straddling cluster with a partially-inaccessible ward split). This is the
#' single source of truth 05_build_accessibility_impact_workbook.py's
#' build_cluster_level() now reads instead of recomputing its own raw
#' per-row count - the two were disagreeing for every straddling/below-
#' threshold cluster before this (see project memory
#' project_resampling_target_inflation_fix_2026-09-13 for the full
#' before/after).
#'
#' @return tibble(cluster_id, pop_type, target_households, n_achieved,
#'   currently_accessible, n_accessible_primary_post_threshold, status) -
#'   one row per covered cluster.
compute_cluster_status <- function(full_df, achieved_lookup, accessibility, non_idp_min_accessible_primary_hh = 4,
                                    ward_exempt_sampling_methods = "MSNA Light") {
  covered <- accessibility$covered
  covered_accessible <- accessibility$covered_accessible
  below_threshold_clusters <- accessibility$below_threshold_clusters
  cluster_overlay_excluded <- accessibility$cluster_overlay_excluded
  primary <- covered %>% filter(status == "primary")

  accessible_primary_n <- covered_accessible %>%
    filter(status == "primary") %>%
    count(cluster_id, name = "n_accessible_primary_post_threshold")

  # 2026-09-14 (found during Jack's requested post-MSNA-Light audit): this
  # function had the SAME missing ward_exempt_sampling_methods gap that was
  # just fixed in compute_cluster_accessibility() above - a fix landed in
  # one function of this file's 4-function family, not propagated to a
  # sibling computing a related but separate concept (per-cluster STATUS,
  # not WORKING membership). Currently a latent gap, not a live wrong
  # output - every MSNA Light ward happens to be Accessible right now, so
  # any_inaccessible already evaluates FALSE for them regardless of this
  # exemption - but the moment any MSNA Light ward is ever reported
  # Inaccessible again (exactly the scenario today's fix exists for), this
  # would have mislabelled those clusters "not_started_access_lost"/
  # "partially_completed_access_lost" even though their rows correctly stay
  # in WORKING - a visible, confusing inconsistency between cluster_status
  # and WORKING membership for the exact clusters this mechanism protects.
  cluster_accessible <- primary %>%
    group_by(cluster_id, pop_type) %>%
    summarise(any_inaccessible = any(
      !(sampling_method %in% ward_exempt_sampling_methods) &
      (is.na(ward_accessible_status) | ward_accessible_status == "Inaccessible")
    ), .groups = "drop") %>%
    mutate(currently_accessible = !any_inaccessible & !(cluster_id %in% below_threshold_clusters) & !(cluster_id %in% cluster_overlay_excluded)) %>%
    select(-any_inaccessible)

  achieved_non_idp_n <- primary %>%
    filter(pop_type == "non_idp", survey_id %in% achieved_lookup$non_idp_survey_ids) %>%
    count(cluster_id, name = "n_achieved")
  achieved_idp_n <- achieved_lookup$idp_counts %>%
    filter(matched_status == "primary") %>%
    transmute(cluster_id = matched_cluster_id, n_achieved)
  achieved_by_cluster <- bind_rows(achieved_non_idp_n, achieved_idp_n)

  target_by_cluster <- primary %>%
    mutate(target_households = as.numeric(target_households)) %>%
    group_by(cluster_id) %>%
    summarise(target_households = dplyr::first(target_households), .groups = "drop")

  cluster_accessible %>%
    left_join(achieved_by_cluster, by = "cluster_id") %>%
    left_join(target_by_cluster, by = "cluster_id") %>%
    left_join(accessible_primary_n, by = "cluster_id") %>%
    mutate(
      n_achieved = coalesce(n_achieved, 0L),
      n_accessible_primary_post_threshold = coalesce(n_accessible_primary_post_threshold, 0L),
      status = case_when(
        n_achieved >= target_households ~ "completed",
        n_achieved > 0 & !currently_accessible ~ "partially_completed_access_lost",
        n_achieved == 0 & !currently_accessible ~ "not_started_access_lost",
        TRUE ~ "not_started_other"
      )
    ) %>%
    select(cluster_id, pop_type, target_households, n_achieved, currently_accessible,
           n_accessible_primary_post_threshold, status)
}

#' Task 4 (2026-09-13, Jack's call: proper formula, not the simple average-
#' size correction): distribution-aware realized MoE. The pre-existing
#' realized_moe() used deff <- 1 + (m-1)*ICC with the nominal cluster size m
#' uniformly - blind to how unevenly achieved sample is actually distributed
#' across full vs. partial clusters once Task 3's per-cluster status makes
#' that variability real and common (a partially_completed_access_lost
#' cluster can have far fewer achieved households than a completed one).
#'
#' Kish's (1965) approximate design effect for unequal cluster sizes:
#'   deff = 1 + [(cv^2 + 1) * m_bar - 1] * ICC
#' where m_bar = mean achieved cluster size, cv = coefficient of variation
#' of achieved cluster sizes (sd/mean). When cv = 0 (all clusters exactly
#' m_bar households - the uniform case), this reduces EXACTLY to the
#' original 1 + (m_bar - 1) * ICC formula - verified algebraically, not
#' just asserted: (0^2+1)*m_bar - 1 = m_bar - 1. So this is a strict
#' generalization, not a different formula for the common case.
#'
#' @param achieved_sample total achieved primary sample for the stratum.
#' @param N_hh stratum population.
#' @param cluster_sizes numeric vector - achieved primary count per cluster
#'   in this stratum (from compute_strata_achieved()'s cluster_sizes output,
#'   filtered to this strata_id and pulled as a vector).
#' @param ICC intra-cluster correlation.
#' @return realized MoE as a proportion (multiply by 100 for a percentage,
#'   matching the existing realized_moe_pct column's convention).
realized_moe_unequal <- function(achieved_sample, N_hh, cluster_sizes, ICC, Z = qnorm(0.95), p = 0.5) {
  cluster_sizes <- cluster_sizes[!is.na(cluster_sizes) & cluster_sizes > 0]
  if (length(cluster_sizes) == 0) return(NA_real_)
  m_bar <- mean(cluster_sizes)
  cv <- if (length(cluster_sizes) > 1 && m_bar > 0) sd(cluster_sizes) / m_bar else 0
  if (is.na(cv)) cv <- 0
  deff  <- 1 + ((cv^2 + 1) * m_bar - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}
