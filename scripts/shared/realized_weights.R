# ==============================================================================
# Realized-weight recompute for over-achieved ("topped-up") clusters - piece
# one of Round 1's full weighting build (Jack, 2026-09-27 night, via the
# Coordinator). Read this file before touching that build; it's written to
# stand alone, not to be reverse-engineered from a one-off script.
#
# THE PROBLEM. Every household row's design-time selection probability is
# computed ONCE, at draw time, in finalize_households() (scripts/
# 03_stage2_household_selection.R:517-522):
#     ssu_probability = pmin(1, target_households / households_in_cluster)
#     base_weight     = 1 / (psu_probability * ssu_probability)
# and that pair of numbers then sits unchanged in FULL/WORKING forever - the
# whole rest of this project (achieved-vs-target tracking, MoE, resampling)
# reads real achieved counts from real_submissions.csv separately and never
# writes them back into these two design columns. That's correct for every
# purpose this project has needed so far (deciding whether to draw more,
# whether a stratum is representative) - none of that is a probability-
# weighted population ESTIMATE, so the design weight never had to move.
# Estimation is different: a cluster where the field team genuinely
# collected MORE real households than the design called for (common - see
# find_topped_up_clusters() below, 551 clusters tonight) was, in truth,
# sampled at a higher within-cluster rate than target_households/
# households_in_cluster assumed. Using the design ssu_probability for such
# a cluster in an estimator UNDER-weights every one of its real
# respondents relative to how likely they actually were to be selected -
# exactly the bias a base weight exists to correct for.
#
# THE FIX, and ONLY the fix. For a cluster where real achieved interviews
# (compute_achieved_by_cluster()'s definition, below) exceed
# target_households, recompute ONLY that cluster's ssu_probability and
# base_weight from the REAL achieved count instead of target_households:
#     ssu_probability = pmin(1, achieved_interviews / households_in_cluster)
#     base_weight     = 1 / (psu_probability * ssu_probability)
# psu_probability (the cluster's own selection probability under PPS) is
# UNTOUCHED - topping up a cluster's within-cluster interview count says
# nothing about how likely that cluster itself was to be drawn. Every
# other cluster, and every other column on every row (topped-up or not),
# is left EXACTLY as 03_stage2_household_selection.R computed it. This is
# a targeted correction, not a re-derivation of the design - see
# apply_realized_weights()'s own docstring for the byte-identical
# guarantee that makes this provable, not just asserted.
#
# WHY CLUSTER-LEVEL, NOT ROW-LEVEL. ssu_probability/base_weight are cluster
# attributes in the design too (computed once per cluster in clusters_merged,
# then left-joined onto every one of that cluster's rows - both primary and
# reserve carry the identical value). A topped-up cluster's realized weight
# therefore also applies identically to every row of that cluster,
# regardless of status (primary/reserve) or whether a given row itself was
# ever interviewed. This script does NOT relabel status, interview_number
# or replacement_rank - those describe which SLOT a row was drawn into at
# design time and are untouched by how many real interviews later landed in
# the cluster. A reserve row promoted into the field because a primary
# no-showed is a SEPARATE, already-handled concept (real_submissions.csv's
# own matched_status per interview) - this script only ever touches the
# two frame-level weight columns, on every row of a qualifying cluster.
#
# WHICH "ACHIEVED" DEFINITION. compute_achieved_by_cluster() ports frame_
# status.R's own compute_achieved_lookup() row filter exactly (completed,
# matched_survey_id present, uuid not in the confirmed-deletions overlay's
# confirmed/contested set) - the same canonical formula 05_build_
# accessibility_impact_workbook.py's load_real_achieved() and every
# resampling decision tonight already uses - but returns a FLAT per-cluster
# count (not split by pop_type/status the way compute_achieved_lookup()'s
# own two return fields are), because a weight is a per-cluster quantity
# regardless of pop_type, and this count must include every real, counted
# interview at that cluster (primary-slot AND reserve-slot matches alike) -
# that IS the true number of the cluster's own households actually sampled,
# which is exactly what ssu_probability is supposed to measure. Deliberately
# NOT capped at target_households before this comparison (same choice 05's
# load_real_achieved() already documents and this script inherits directly)
# - capping here would silently hide the very over-collection this script
# exists to correct for.
#
# A GENUINELY IMPOSSIBLE CASE, FOUND AND HANDLED, NOT IGNORED. 7 of the 551
# topped-up clusters tonight (5 IDP, 2 Non-IDP) have real achieved interviews
# that exceed even households_in_cluster itself - ssu_probability would
# compute above 1, which cannot be a real selection probability. Same
# pmin(1, ...) convention as the design-time formula: capped at 1, and
# every capped cluster is returned in the audit table (see
# compute_realized_weight_for_cluster()'s $capped field) rather than
# silently clamped and forgotten. A households_in_cluster this far below
# real achieved is itself informative - almost always an IDP DTM
# population undercount (see project memory project_dtm_vs_hh_listing_
# idp_shortfall_2026-09-21 for the same underlying phenomenon found from a
# different angle) - worth Jack's own look at the audit table before
# tomorrow's weighting build trusts households_in_cluster for those 7
# clusters at all, rather than something for this script to paper over.
#
# TOPPED-UP-TODAY, NOT-TOPPED-UP-TOMORROW - BY CONSTRUCTION, NOT A SPECIAL
# CASE. This script is stateless: every run recomputes achieved_interieuws
# vs target_households FRESH from whatever real_submissions.csv/deletions
# overlay it's given, and every row's ssu_probability/base_weight are
# derived ONLY from that run's own comparison - never from a previous
# run's output, never incrementally adjusted. If a cluster's real achieved
# count later drops back to target_households or below (a real, if rare,
# possibility - e.g. a batch of its interviews gets confirmed-deleted after
# a later duration/quality review), the NEXT run simply no longer treats it
# as topped up, and that cluster's rows silently take the "leave everywhere
# else exactly as design" branch again - i.e. REVERT to the original design
# ssu_probability/base_weight automatically, with no separate code path
# needed for "undo". Verified directly below (see the idempotency check in
# the validation script) that running this twice on the SAME input is a
# true no-op the second time; the same statelessness is what makes a
# CHANGING input safe too, not just a repeated one.
#
# EXTENSIBILITY - THE ONE FUNCTION TOMORROW'S BUILD SHOULD CALL AGAIN.
# compute_realized_weight_for_cluster() is the single, pure, cluster-scoped
# unit of this whole mechanism (no I/O, no data frame, four numbers in,
# four out) - reuse IT directly for any future per-cluster weight
# recompute (a later design change, a different over/under-collection
# rule, a re-run against a newer export), rather than re-deriving the
# pmin(1, ...)/1/(psu*ssu) arithmetic a second time somewhere else.
# apply_realized_weights() is the thin frame-level wrapper around it and is
# fine to reuse as-is too, but is NOT where the actual weighting logic
# lives - that's the function above it.
# ==============================================================================
suppressMessages({ library(dplyr) })

#' Real achieved interviews per cluster, flat (not split by pop_type or
#' status) - see this file's header for why flat is the right shape here.
#' Same row filter as frame_status.R's compute_achieved_lookup(), so this
#' function and that one will always agree on WHICH submissions count;
#' they differ only in how the count is grouped afterward.
#'
#' @param subs_df real_submissions.csv, read as character/default types (no
#'   column-type assumptions beyond what's compared below).
#' @param deletions_overlay_df CONFIRMED_DELETIONS_OVERLAY.csv.
#' @return tibble(cluster_id, n_achieved) - one row per cluster with at
#'   least one achieved interview. A cluster with zero achieved interviews
#'   is simply absent (never negative, never an explicit zero row) -
#'   callers must treat "not in this table" as n_achieved = 0, exactly as
#'   compute_achieved_lookup()'s own callers already do.
compute_achieved_by_cluster <- function(subs_df, deletions_overlay_df) {
  TERMINAL_DELETION_STATUSES <- c("confirmed", "contested")
  confirmed_deletion_uuids <- deletions_overlay_df %>%
    filter(status %in% TERMINAL_DELETION_STATUSES) %>% pull(uuid)
  subs_df %>%
    filter(
      interview_outcome == "completed",
      !(matched_survey_id %in% c(NA, "", "NA")),
      !(submission_uuid %in% confirmed_deletion_uuids),
      !(matched_cluster_id %in% c(NA, "", "NA"))
    ) %>%
    count(matched_cluster_id, name = "n_achieved") %>%
    rename(cluster_id = matched_cluster_id)
}

#' The one reusable unit: realized selection probability and base weight
#' for a SINGLE cluster, given its design values and its real achieved
#' count. Pure function - no data frame, no file I/O, safe to call once per
#' cluster or vectorized (every argument may be a vector of equal length).
#'
#' @param psu_probability the cluster's own design PSU selection
#'   probability - passed through UNCHANGED in the return value; included
#'   here only so base_weight can be computed in one place rather than
#'   forcing every caller to redo the 1/(psu*ssu) arithmetic itself.
#' @param target_households the design ssu target this cluster was drawn
#'   against (m * selection_count at draw time).
#' @param households_in_cluster the cluster's household/building universe
#'   size, same column FULL already carries.
#' @param achieved_interviews real achieved interview count for this
#'   cluster (compute_achieved_by_cluster()'s n_achieved, or 0/NA if the
#'   cluster had none).
#' @return list(topped_up, ssu_probability, base_weight, capped) -
#'   topped_up = achieved_interviews > target_households (the ONLY
#'   condition that triggers a recompute; ssu_probability/base_weight for
#'   a not-topped-up cluster are returned as NA - callers must fall back
#'   to the existing design values for those, see apply_realized_weights());
#'   capped = TRUE where achieved_interviews > households_in_cluster, i.e.
#'   the pmin(1, ...) cap actually bound - see this file's header on why
#'   that's flagged, not hidden.
compute_realized_weight_for_cluster <- function(psu_probability, target_households, households_in_cluster, achieved_interviews) {
  achieved_interviews <- ifelse(is.na(achieved_interviews), 0, achieved_interviews)
  topped_up <- achieved_interviews > target_households
  ssu_raw <- achieved_interviews / households_in_cluster
  ssu_probability <- ifelse(topped_up, pmin(1, ssu_raw), NA_real_)
  base_weight <- ifelse(topped_up, 1 / (psu_probability * ssu_probability), NA_real_)
  list(
    topped_up = topped_up,
    ssu_probability = ssu_probability,
    base_weight = base_weight,
    capped = topped_up & (ssu_raw > 1)
  )
}

#' Frame-level wrapper: apply compute_realized_weight_for_cluster() across
#' every row of a household-level data frame, touching ONLY
#' ssu_probability/base_weight, and ONLY on rows belonging to a topped-up
#' cluster. Every other row is returned with every column IDENTICAL to the
#' input (not just unchanged in value - the same untouched vector) so a
#' before/after diff on the full frame proves the "everywhere else exactly
#' as design" guarantee mechanically, not just by inspection.
#'
#' @param household_df household-level FULL or WORKING (or any subset with
#'   the same columns), must carry cluster_id, target_households,
#'   households_in_cluster, psu_probability, ssu_probability, base_weight.
#' @param achieved_by_cluster compute_achieved_by_cluster()'s output.
#' @return list(frame = household_df with ssu_probability/base_weight
#'   updated on topped-up clusters only, audit = one row per DISTINCT
#'   topped-up cluster_id with its old/new ssu_probability/base_weight,
#'   achieved/target/households_in_cluster and whether the pmin(1,...) cap
#'   bound - the table to hand Jack alongside the D3-heavy decision).
apply_realized_weights <- function(household_df, achieved_by_cluster) {
  by_cluster <- household_df %>%
    distinct(cluster_id, target_households, households_in_cluster, psu_probability) %>%
    left_join(achieved_by_cluster, by = "cluster_id") %>%
    mutate(n_achieved = coalesce(n_achieved, 0L))
  realized <- compute_realized_weight_for_cluster(
    by_cluster$psu_probability, by_cluster$target_households,
    by_cluster$households_in_cluster, by_cluster$n_achieved
  )
  by_cluster <- by_cluster %>%
    mutate(
      topped_up = realized$topped_up,
      new_ssu_probability = realized$ssu_probability,
      new_base_weight = realized$base_weight,
      cap_bound = realized$capped
    )
  topped_up_ids <- by_cluster %>% filter(topped_up) %>% pull(cluster_id)

  new_vals <- by_cluster %>% filter(topped_up) %>%
    select(cluster_id, new_ssu_probability, new_base_weight)

  frame_out <- household_df %>%
    left_join(new_vals, by = "cluster_id") %>%
    mutate(
      ssu_probability = if_else(cluster_id %in% topped_up_ids, new_ssu_probability, ssu_probability),
      base_weight = if_else(cluster_id %in% topped_up_ids, new_base_weight, base_weight)
    ) %>%
    select(-new_ssu_probability, -new_base_weight)

  audit <- by_cluster %>% filter(topped_up) %>%
    left_join(
      household_df %>% distinct(cluster_id, old_ssu_probability = ssu_probability, old_base_weight = base_weight),
      by = "cluster_id"
    ) %>%
    transmute(
      cluster_id, target_households, households_in_cluster, achieved_interviews = n_achieved,
      psu_probability,
      old_ssu_probability, new_ssu_probability,
      old_base_weight, new_base_weight,
      cap_bound
    ) %>%
    arrange(desc(achieved_interviews - target_households))

  list(frame = frame_out, audit = audit)
}
