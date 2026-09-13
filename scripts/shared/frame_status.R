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
  TERMINAL_DELETION_STATUSES <- c("confirmed", "contested")
  confirmed_deletion_uuids <- deletions_overlay_df %>% filter(status %in% TERMINAL_DELETION_STATUSES) %>% pull(uuid)
  achieved <- subs_df %>%
    filter(
      interview_outcome == "completed",
      is_duplicate != "TRUE",
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
#' @return list(covered, covered_accessible, below_threshold_clusters)
compute_cluster_accessibility <- function(full_df, non_idp_min_accessible_primary_hh = 4) {
  covered <- full_df %>% filter(coverage_status == "covered", exclusion_reason == "none")

  # NA (unmatched ward geography) counts as excluded, not accessible -
  # 2026-09-08 rebuild-wide rule, both existing call sites already agree.
  cluster_accessible_primary_n <- covered %>%
    filter(pop_type == "non_idp", status == "primary", !is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible") %>%
    count(cluster_id, name = "n_accessible_primary")
  below_threshold_clusters <- cluster_accessible_primary_n %>%
    filter(n_accessible_primary < non_idp_min_accessible_primary_hh) %>%
    pull(cluster_id)

  covered_accessible <- covered %>%
    filter(!is.na(ward_accessible_status) & ward_accessible_status != "Inaccessible") %>%
    filter(!(cluster_id %in% below_threshold_clusters))

  list(covered = covered, covered_accessible = covered_accessible, below_threshold_clusters = below_threshold_clusters)
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
#'     double-asks for work already done), MINUS sampling_method rows in
#'     `exclude_sampling_methods` (MSNA Light etc. - government-negotiated,
#'     unverifiable collection that must never blend into a stratum's
#'     normal design-capacity figure).
#'   filter_ward_accessible = FALSE (FULL): every primary row ever drawn for
#'     the stratum, completely unfiltered - FULL is the complete historical
#'     record regardless of current accessibility AND regardless of
#'     sampling_method (an MSNA Light row genuinely was drawn; FULL doesn't
#'     distinguish sampling methods, only WORKING's operational figure does).
#'
#' @param full_df household-level FULL (or FULL+staged-new-rows) frame.
#' @param achieved_lookup from compute_achieved_lookup().
#' @param accessibility from compute_cluster_accessibility() - required only
#'   when filter_ward_accessible = TRUE.
#' @param filter_ward_accessible see above.
#' @param exclude_sampling_methods character vector of sampling_method
#'   values to exclude from the WORKING-mode figure. Default "MSNA Light".
#' @return list(agg = tibble(strata_id, achieved_clusters, achieved_sample),
#'   cluster_sizes = tibble(strata_id, cluster_id, n) for Task 4's
#'   distribution-aware DEFF, stranded_rows)
compute_strata_achieved <- function(full_df, achieved_lookup, accessibility = NULL,
                                     filter_ward_accessible, exclude_sampling_methods = "MSNA Light") {
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

  not_msna_light <- function(df) df %>% filter(is.na(sampling_method) | !(sampling_method %in% exclude_sampling_methods))

  excluded_primary <- covered %>%
    filter(status == "primary") %>%
    filter(
      (is.na(ward_accessible_status) | ward_accessible_status == "Inaccessible") |
      (pop_type == "non_idp" & cluster_id %in% below_threshold_clusters)
    ) %>%
    not_msna_light()

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
    covered_accessible %>% filter(status == "primary") %>% not_msna_light(),
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
#' @return tibble(cluster_id, pop_type, target_households, n_achieved,
#'   currently_accessible, status) - one row per covered cluster.
compute_cluster_status <- function(full_df, achieved_lookup, accessibility, non_idp_min_accessible_primary_hh = 4) {
  covered <- accessibility$covered
  below_threshold_clusters <- accessibility$below_threshold_clusters
  primary <- covered %>% filter(status == "primary")

  cluster_accessible <- primary %>%
    group_by(cluster_id, pop_type) %>%
    summarise(any_inaccessible = any(is.na(ward_accessible_status) | ward_accessible_status == "Inaccessible"), .groups = "drop") %>%
    mutate(currently_accessible = !any_inaccessible & !(cluster_id %in% below_threshold_clusters)) %>%
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
    mutate(
      n_achieved = coalesce(n_achieved, 0L),
      status = case_when(
        n_achieved >= target_households ~ "completed",
        n_achieved > 0 & !currently_accessible ~ "partially_completed_access_lost",
        n_achieved == 0 & !currently_accessible ~ "not_started_access_lost",
        TRUE ~ "not_started_other"
      )
    ) %>%
    select(cluster_id, pop_type, target_households, n_achieved, currently_accessible, status)
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
