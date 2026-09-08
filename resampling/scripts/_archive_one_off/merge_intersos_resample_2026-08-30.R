# ==============================================================================
# Merge INTERSOS's resample (Gusau/NG037007, Maru/NG037010 - Non-IDP + IDP)
# into the live FULL/WORKING frame. FACT's staged output is NOT touched here -
# deferred per RESAMPLING_DECISION_RULES.md sec 6 (revising their own coverage).
#
# Precondition (done 2026-08-30): the current output/data/data_collection/
# was copied byte-for-byte to _archive/2026-08-30_pre_intersos_resample_merge/
# before this script writes anything - safe to defer back to at any point.
#
# Inputs (all staged, verified, not yet live):
#   resampling/output/resample_runs/2026-08-30_intersos_fact_pilot/
#     new_clusters.csv / new_households.csv            (Non-IDP, INTERSOS+FACT combined)
#     new_clusters_idp.csv / new_households_idp.csv     (IDP genuinely-new, INTERSOS+FACT)
#     existing_cluster_target_increases_idp.csv         (IDP existing-cluster increases, INTERSOS+FACT)
#     existing_cluster_household_additions_idp.csv      (IDP existing-cluster new rows, INTERSOS+FACT)
# All four filtered here to adm2_pcode %in% c("NG037007","NG037010") - INTERSOS only.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(tibble) })

STAGING <- "resampling/output/resample_runs/2026-08-30_intersos_fact_pilot"
DC_DIR  <- "output/data/data_collection"
INTERSOS_PCODES <- c("NG037007", "NG037010")

log_lines <- character(0)
log_msg <- function(...) { m <- sprintf(...); cat(m, "\n"); log_lines <<- c(log_lines, m) }

log_msg("==== Merge INTERSOS resample into live frame - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

# ---- Load live frame ----
full_hh    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv"), show_col_types = FALSE)
working_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"), show_col_types = FALSE)
full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v2_WORKING.csv"), show_col_types = FALSE)

live_survey_ids <- union(full_hh$survey_id, working_hh$survey_id)
live_cluster_ids <- union(full_hh$cluster_id, working_hh$cluster_id)

# ---- Load staged INTERSOS-only rows ----
new_clusters_nonidp  <- read_csv(file.path(STAGING, "new_clusters.csv"), show_col_types = FALSE) %>% filter(adm2_pcode %in% INTERSOS_PCODES)
new_hh_nonidp        <- read_csv(file.path(STAGING, "new_households.csv"), show_col_types = FALSE) %>% filter(cluster_id %in% new_clusters_nonidp$cluster_id)
new_clusters_idp      <- read_csv(file.path(STAGING, "new_clusters_idp.csv"), show_col_types = FALSE) %>% filter(adm2_pcode %in% INTERSOS_PCODES)
new_hh_idp            <- read_csv(file.path(STAGING, "new_households_idp.csv"), show_col_types = FALSE) %>% filter(cluster_id %in% new_clusters_idp$cluster_id)
target_increases_idp   <- read_csv(file.path(STAGING, "existing_cluster_target_increases_idp.csv"), show_col_types = FALSE) %>%
  filter(cluster_id %in% (working_hh %>% filter(adm2_pcode %in% INTERSOS_PCODES) %>% pull(cluster_id)))
additions_idp           <- read_csv(file.path(STAGING, "existing_cluster_household_additions_idp.csv"), show_col_types = FALSE) %>%
  filter(cluster_id %in% target_increases_idp$cluster_id)

log_msg("Loaded: %d new Non-IDP cluster(s)/%d hh, %d new IDP cluster(s)/%d hh, %d existing IDP cluster(s) to expand/%d additional hh.",
        nrow(new_clusters_nonidp), nrow(new_hh_nonidp), nrow(new_clusters_idp), nrow(new_hh_idp),
        nrow(target_increases_idp), nrow(additions_idp))

# ---- Pre-flight: nothing here should already exist live ----
stopifnot(
  "New Non-IDP cluster_ids already exist live" = !any(new_clusters_nonidp$cluster_id %in% live_cluster_ids),
  "New IDP cluster_ids already exist live" = !any(new_clusters_idp$cluster_id %in% live_cluster_ids),
  "New survey_ids collide with the live frame" = !any(c(new_hh_nonidp$survey_id, new_hh_idp$survey_id, additions_idp$survey_id) %in% live_survey_ids),
  "Existing clusters to expand are NOT currently live" = all(target_increases_idp$cluster_id %in% live_cluster_ids)
)
log_msg("Pre-flight checks passed: no ID collisions with the live frame.")

# ---- Add coverage columns to genuinely-new cluster household rows ----
# Every INTERSOS LGA in this batch is already coverage_status == "covered",
# exclusion_reason == "none", partners_covering == "INTERSOS" in the live
# frame (verified directly, 2026-08-30) - new rows in an already-covered LGA
# inherit the same values, not recomputed.
add_coverage_cols <- function(df) {
  df %>% mutate(coverage_status = "covered", exclusion_reason = "none", partners_covering = "INTERSOS")
}
new_hh_nonidp <- add_coverage_cols(new_hh_nonidp)
new_hh_idp    <- add_coverage_cols(new_hh_idp)
# additions_idp rows were templated directly off an existing live row (see
# draw_supplementary_idp_clusters_pilot_2026-08-30.R Stage F) - they already
# carry the correct coverage columns from that template, untouched here.

# gpkg-only / geometry columns present in the staged sf-derived CSVs but not
# in the live household-level CSV schema - drop before binding.
non_schema_cols <- setdiff(names(new_hh_nonidp), names(working_hh))
if (length(non_schema_cols) > 0) {
  log_msg("Dropping %d non-schema column(s) from staged Non-IDP rows before merge: %s", length(non_schema_cols), paste(non_schema_cols, collapse = ", "))
  new_hh_nonidp <- new_hh_nonidp %>% select(-all_of(non_schema_cols))
}
non_schema_cols_idp <- setdiff(names(new_hh_idp), names(working_hh))
if (length(non_schema_cols_idp) > 0) {
  log_msg("Dropping %d non-schema column(s) from staged IDP rows before merge: %s", length(non_schema_cols_idp), paste(non_schema_cols_idp, collapse = ", "))
  new_hh_idp <- new_hh_idp %>% select(-all_of(non_schema_cols_idp))
}

# CSV round-trip type harmonization: readr's type-guessing can disagree
# between files on a digit-only pcode column (e.g. adm3_pcode values like
# "40107" guess as character in one file, double in another, since there's
# no letter prefix to force character the way adm2_pcode's "NG..." shape
# does) - found 2026-08-30 via a bind_rows() type-mismatch error. Fix
# generically: cast every shared column in each new-rows frame to whatever
# type it has in the live working_hh frame (the authoritative schema),
# rather than hardcoding which specific column disagreed this time.
harmonize_types <- function(df, reference) {
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
new_hh_nonidp <- harmonize_types(new_hh_nonidp, working_hh)
new_hh_idp    <- harmonize_types(new_hh_idp, working_hh)
additions_idp <- harmonize_types(additions_idp, working_hh)

all_new_rows <- bind_rows(new_hh_nonidp, new_hh_idp, additions_idp) %>%
  select(all_of(names(working_hh)))

if (anyDuplicated(all_new_rows$survey_id) > 0) stop("Duplicate survey_id within the new-rows batch itself.")
log_msg("Total new household row(s) to append (both FULL and WORKING - all INTERSOS LGAs are covered): %d", nrow(all_new_rows))

# ---- Update target_households/reserve_households/selection_count on the 4 existing IDP clusters being expanded ----
apply_target_increase <- function(hh_df) {
  hh_df %>%
    left_join(target_increases_idp %>% select(cluster_id, increase_target, increase_reserve), by = "cluster_id") %>%
    mutate(
      target_households = if_else(!is.na(increase_target), target_households + increase_target, target_households),
      reserve_households = if_else(!is.na(increase_reserve), reserve_households + increase_reserve, reserve_households),
      selection_count = if_else(!is.na(increase_target), selection_count + as.integer(increase_target / 6L), selection_count)
    ) %>%
    select(-increase_target, -increase_reserve)
}
full_hh    <- apply_target_increase(full_hh)
working_hh <- apply_target_increase(working_hh)
log_msg("Updated target_households/reserve_households/selection_count on existing rows for %d expanded cluster(s) (both FULL and WORKING).", nrow(target_increases_idp))

# ---- Append new rows ----
full_hh_new    <- bind_rows(full_hh, all_new_rows)
working_hh_new <- bind_rows(working_hh, all_new_rows)

# ---- Verification, not assumed ----
if (anyDuplicated(full_hh_new$survey_id) > 0) stop("Duplicate survey_id in merged FULL frame.")
if (anyDuplicated(working_hh_new$survey_id) > 0) stop("Duplicate survey_id in merged WORKING frame.")
expected_full    <- nrow(full_hh) + nrow(all_new_rows)
expected_working <- nrow(working_hh) + nrow(all_new_rows)
if (nrow(full_hh_new) != expected_full) stop("FULL row count mismatch after merge.")
if (nrow(working_hh_new) != expected_working) stop("WORKING row count mismatch after merge.")
log_msg("Verified: zero duplicate survey_ids, row counts match exactly. FULL %d -> %d, WORKING %d -> %d.",
        nrow(full_hh), nrow(full_hh_new), nrow(working_hh), nrow(working_hh_new))

# ---- Strata-level CSV: recompute achieved_clusters/achieved_sample/realized_moe_pct ----
# directly from the merged household data for the 4 affected strata, rather
# than incrementing stored values - self-deriving from source data avoids
# compounding an error into a second, independently-tracked total.
# target_sample/clusters_target_stage1/projected_moe_pct are left untouched -
# per CLAUDE.md's 2026-07-15 fix, target_sample is the FULL FRAME design
# target and must never double-count a supplementary cluster's own nominal
# target; that logic still holds for a resample the same way it did for the
# original 28 below-target strata.
realized_moe <- function(achieved_sample, N_hh, m, ICC, Z = qnorm(0.95), p = 0.5) {
  deff  <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0    <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

recompute_strata <- function(sl_df, hh_df) {
  affected_strata <- unique(all_new_rows$strata_id)
  agg <- hh_df %>%
    filter(strata_id %in% affected_strata, status == "primary") %>%
    group_by(strata_id) %>%
    summarise(achieved_clusters_new = n_distinct(cluster_id), achieved_sample_new = n(), .groups = "drop")

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
full_sl_new    <- recompute_strata(full_sl, full_hh_new)
working_sl_new <- recompute_strata(working_sl, working_hh_new)

changed_rows <- working_sl_new %>% filter(strata_id %in% unique(all_new_rows$strata_id)) %>%
  select(strata_id, achieved_clusters, achieved_sample, realized_moe_pct)
log_msg("Strata-level updated for %d affected stratum/strata:", nrow(changed_rows))
for (i in seq_len(nrow(changed_rows))) {
  log_msg("  %s: achieved_clusters=%d, achieved_sample=%d, realized_moe_pct=%.2f%%",
          changed_rows$strata_id[i], changed_rows$achieved_clusters[i], changed_rows$achieved_sample[i], changed_rows$realized_moe_pct[i])
}

# ---- Write ----
write_csv(full_hh_new, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv"))
write_csv(working_hh_new, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"))
write_csv(full_sl_new, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv"))
write_csv(working_sl_new, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v2_WORKING.csv"))
log_msg("Written: FULL + WORKING household-level and strata-level CSVs in %s.", DC_DIR)

writeLines(log_lines, file.path(STAGING, "merge_intersos_log.txt"))
log_msg("==== DONE. Previous frame archived at _archive/2026-08-30_pre_intersos_resample_merge/. ====")
