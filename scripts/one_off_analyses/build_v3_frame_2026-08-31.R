# ==============================================================================
# Build the v3 sampling frame - Jack's calls, 2026-08-31, made before he had
# to step out (must be self-contained, no follow-up questions possible):
#
#   1. REVERT FACT's 39 wrongly-drawn Non-IDP clusters (348 hh) across 5
#      strata under the <10% population-remaining floor (RESAMPLING_
#      DECISION_RULES.md #2). Zero submissions exist against them - clean
#      removal from both FULL and WORKING.
#   2. EXCLUDE all strata under that floor (the 5 above + others never
#      resampled) - coverage_status="excluded", exclusion_reason=
#      "accessibility_loss_below_population_threshold" - same mechanism
#      analysis_partner_coverage.py already uses to derive WORKING from
#      FULL (WORKING = FULL filtered to coverage_status=="covered" &
#      exclusion_reason=="none").
#   3. NEW REQUIREMENT (Jack, 2026-08-31): WORKING must be a true "still to
#      collect" list, not just "still in an active stratum" - it must also
#      drop already-ACHIEVED household slots (canonical is_achieved formula
#      + deletion log, same definition load_real_achieved() in
#      05_build_accessibility_impact_workbook.py uses), so nothing surplus
#      goes to the data officer's KoBo tool refresh tonight.
#        - Non-IDP: exact join on survey_id <-> real_submissions'
#          matched_survey_id (identical ID scheme - HH##/R## - both sides).
#        - IDP: real_submissions' matched_survey_id uses on-site LISTING
#          numbers (L#/W#), NOT the frame's HH##/R## slot labels - there's
#          no fixed physical building pre-assigned per IDP slot the way
#          there is for Non-IDP, so an exact ID join isn't meaningful here.
#          Falls back to a COUNT-based removal per (cluster, primary/
#          reserve): drop the lowest interview_number/replacement_rank
#          slots first, one per achieved submission of that type in that
#          cluster. Functionally correct ("how many more households does
#          this site still need") even though it can't say WHICH exact
#          labelled slot a given past visit corresponds to.
#   4. Renamed v2 -> v3 throughout (Jack's explicit call, so Arnold can see
#      at a glance the frame changed while he was out). v2 files are left
#      exactly as they are - the frozen last-known-good, not deleted.
#
# Archived pre-change copy: _archive/2026-08-31_pre_fact_revert_and_exclusion_writeback/
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(here)
  library(openxlsx)
})

output_dir <- here("output")
sf_dir     <- here(output_dir, "data", "data_collection")
resamp_dir <- here("resampling")
monitoring_dir <- here("..", "2_monitoring")

POP_FLOOR_PCT <- 10
EXCLUSION_REASON <- "accessibility_loss_below_population_threshold"

log_lines <- character(0)
log_msg <- function(...) {
  m <- sprintf(...)
  cat(m, "\n")
  log_lines <<- c(log_lines, m)
}

# =============================================================================
# STEP 1: derive sub-floor strata live from the accessibility workbook
# =============================================================================
strata_sheet <- read.xlsx(
  here(resamp_dir, "output", "NGA_MSNA_2026_accessibility_impact_workbook.xlsx"),
  sheet = "Strata Level"
)
names(strata_sheet) <- make.names(names(strata_sheet))
pct_col <- grep("population.remaining", names(strata_sheet), value = TRUE)[1]

subfloor <- strata_sheet %>%
  filter(!is.na(.data[[pct_col]]), .data[[pct_col]] < POP_FLOOR_PCT) %>%
  transmute(strata_id = Strata.ID, state = State, lga = LGA, pop_type = Pop.type,
            pct_remaining = .data[[pct_col]], partners = Partners.covering)
subfloor_ids <- unique(subfloor$strata_id)
log_msg("Sub-floor strata (<%s%% population remaining): %d", POP_FLOOR_PCT, length(subfloor_ids))
for (i in seq_len(nrow(subfloor))) log_msg("  %s | %s / %s | %s | %.1f%% remaining",
  subfloor$strata_id[i], subfloor$state[i], subfloor$lga[i], subfloor$pop_type[i], subfloor$pct_remaining[i])

# =============================================================================
# STEP 2: figure out which sub-floor strata FACT wrongly drew NEW clusters for
# =============================================================================
v2_full   <- read_csv(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv"), show_col_types = FALSE)
v2_working<- read_csv(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"), show_col_types = FALSE)
strata_pcode_map <- v2_full %>% distinct(strata_id, adm2_pcode)

fact_new_clusters <- read_csv(
  here(resamp_dir, "output", "resample_runs", "FACT", "2026-08-30", "new_clusters_non_idp.csv"),
  show_col_types = FALSE
)
# IMPORTANT: fact_new_clusters is Non-IDP only, so the pcode filter below
# must be restricted to Non-IDP subfloor strata specifically - an LGA can
# have its IDP stratum under the floor while its Non-IDP stratum in the
# SAME LGA (same adm2_pcode) is legitimately still being resampled (e.g.
# Kankara, Matazu: IDP subfloor, Non-IDP not). Matching on "any subfloor
# strata's pcode" would wrongly sweep up that LGA's genuinely-valid new
# Non-IDP clusters too - caught by inspecting this run's own output
# (65 clusters flagged instead of the expected 39) before writing anything
# downstream of it.
subfloor_non_idp_ids <- subfloor %>% filter(pop_type == "Non-IDP") %>% pull(strata_id)
subfloor_pcode_map <- strata_pcode_map %>% filter(strata_id %in% subfloor_non_idp_ids)
revert_cluster_ids <- fact_new_clusters %>%
  filter(adm2_pcode %in% subfloor_pcode_map$adm2_pcode) %>%
  pull(cluster_id) %>% unique()
reverted_strata_ids <- subfloor_pcode_map %>%
  filter(adm2_pcode %in% (fact_new_clusters %>% filter(cluster_id %in% revert_cluster_ids) %>% pull(adm2_pcode) %>% unique())) %>%
  pull(strata_id) %>% unique()

log_msg("\nClusters to revert (wrongly drawn, zero submissions): %d", length(revert_cluster_ids))
log_msg("Strata restored to pre-FACT-merge values: %s", paste(reverted_strata_ids, collapse = ", "))

# =============================================================================
# STEP 3: build FULL v3 = v2 FULL, revert the 39 clusters, restore those 5
#         strata's strata-level stats, tag ALL 12 sub-floor strata excluded
# =============================================================================
full_v3 <- v2_full %>% filter(!(cluster_id %in% revert_cluster_ids))
n_removed_full <- nrow(v2_full) - nrow(full_v3)
log_msg("\nFULL v3 household-level: %d -> %d rows (removed %d)", nrow(v2_full), nrow(full_v3), n_removed_full)

full_v3 <- full_v3 %>%
  mutate(
    coverage_status  = if_else(strata_id %in% subfloor_ids, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id %in% subfloor_ids, EXCLUSION_REASON, exclusion_reason)
  )

strata_full_v2 <- read_csv(here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv"), show_col_types = FALSE)
strata_archive <- read_csv(
  here("_archive", "2026-08-30_pre_fact_resample_merge", "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv"),
  show_col_types = FALSE
)
restore_rows <- strata_archive %>% filter(strata_id %in% reverted_strata_ids)
strata_full_v3 <- strata_full_v2 %>%
  filter(!(strata_id %in% reverted_strata_ids)) %>%
  bind_rows(restore_rows) %>%
  mutate(
    coverage_status  = if_else(strata_id %in% subfloor_ids, "excluded", coverage_status),
    exclusion_reason = if_else(strata_id %in% subfloor_ids, EXCLUSION_REASON, exclusion_reason)
  )
log_msg("Strata-level FULL v3: restored %d row(s), marked %d row(s) excluded",
        nrow(restore_rows), sum(strata_full_v3$strata_id %in% subfloor_ids))

# =============================================================================
# STEP 4: derive ACHIEVED household slots from real_submissions.csv (canonical
#         is_achieved formula + latest deletion log), same definition
#         05_build_accessibility_impact_workbook.py's load_real_achieved() uses
# =============================================================================
del_dir <- here(monitoring_dir, "cleaning", "real", "handoff_for_resampling")
del_candidates <- list.files(del_dir, pattern = "^revised_deletion_log_for_resampling_.*\\.csv$", full.names = TRUE)
deletion_log_path <- del_candidates[which.max(file.mtime(del_candidates))]
log_msg("\nUsing deletion log: %s", basename(deletion_log_path))
deletion_uuids <- read_csv(deletion_log_path, show_col_types = FALSE)$uuid

subs <- read_csv(here(monitoring_dir, "dashboard_app", "data", "real_submissions.csv"), show_col_types = FALSE)
subs <- subs %>%
  mutate(achieved = interview_outcome == "completed" &
                     is_duplicate != "TRUE" &
                     !(matched_survey_id %in% c(NA, "", "NA")) &
                     !(submission_uuid %in% deletion_uuids))
achieved <- subs %>% filter(achieved)
log_msg("Real achieved (canonical, post-deletion): %d of %d submissions", nrow(achieved), nrow(subs))

# Non-IDP: exact survey_id join (frame and submissions share the same HH##/R## scheme)
achieved_non_idp_survey_ids <- achieved %>% filter(pop_type == "non_idp") %>% pull(matched_survey_id) %>% unique()
log_msg("Non-IDP achieved survey_ids (exact join): %d", length(achieved_non_idp_survey_ids))

# IDP: count-based per (cluster, primary/reserve) - submissions use on-site
# listing numbers (L#/W#), not the frame's HH##/R## labels
achieved_idp_counts <- achieved %>%
  filter(pop_type == "idp") %>%
  count(matched_cluster_id, matched_status, name = "n_achieved")
log_msg("IDP clusters with achieved interviews (count-based removal): %d", nrow(achieved_idp_counts))

# =============================================================================
# STEP 5: build WORKING v3 = FULL v3 filtered to covered & not excluded,
#         MINUS achieved rows (exact for Non-IDP, count-based for IDP)
# =============================================================================
covered_v3 <- full_v3 %>% filter(coverage_status == "covered", exclusion_reason == "none")
log_msg("\nWORKING v3 candidate pool (covered, not excluded): %d rows", nrow(covered_v3))

non_idp_rows <- covered_v3 %>% filter(pop_type == "non_idp")
idp_rows     <- covered_v3 %>% filter(pop_type == "idp")

# --- Non-IDP: drop exact achieved survey_ids ---
n_non_idp_before <- nrow(non_idp_rows)
non_idp_rows <- non_idp_rows %>% filter(!(survey_id %in% achieved_non_idp_survey_ids))
log_msg("Non-IDP: %d -> %d rows (dropped %d achieved)", n_non_idp_before, nrow(non_idp_rows), n_non_idp_before - nrow(non_idp_rows))

# --- IDP: drop the lowest-numbered N primary / N reserve slots per cluster ---
idp_primary <- idp_rows %>% filter(status == "primary") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "primary") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  group_by(cluster_id) %>%
  arrange(interview_number, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>%
  filter(rn > n_achieved) %>%
  ungroup() %>%
  select(-n_achieved, -rn)

idp_reserve <- idp_rows %>% filter(status == "reserve") %>%
  left_join(achieved_idp_counts %>% filter(matched_status == "reserve") %>% select(matched_cluster_id, n_achieved),
            by = c("cluster_id" = "matched_cluster_id")) %>%
  mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  group_by(cluster_id) %>%
  arrange(replacement_rank, .by_group = TRUE) %>%
  mutate(rn = row_number()) %>%
  filter(rn > n_achieved) %>%
  ungroup() %>%
  select(-n_achieved, -rn)

n_idp_before <- nrow(idp_rows)
idp_rows <- bind_rows(idp_primary, idp_reserve)
log_msg("IDP: %d -> %d rows (dropped %d achieved, count-based)", n_idp_before, nrow(idp_rows), n_idp_before - nrow(idp_rows))

working_v3 <- bind_rows(non_idp_rows, idp_rows) %>% select(all_of(names(full_v3)))
log_msg("\nWORKING v3 final: %d rows, %d distinct clusters", nrow(working_v3), n_distinct(working_v3$cluster_id))

# strata-level WORKING v3: same derivation rule as analysis_partner_coverage.py
strata_working_v3 <- strata_full_v3 %>% filter(coverage_status == "covered", exclusion_reason == "none")

# =============================================================================
# STEP 6: write v3 files (v2 left untouched, frozen)
# =============================================================================
write_csv(full_v3,          here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv") %>% sub("_v2_", "_v3_", .), na = "NA")
write_csv(working_v3,       here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv") %>% sub("_v2_", "_v3_", .), na = "NA")
write_csv(strata_full_v3,   here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv") %>% sub("_v2_", "_v3_", .), na = "NA")
write_csv(strata_working_v3,here(sf_dir, "NGA_MSNA_2026_strata_level_sampling_frame_v2_WORKING.csv") %>% sub("_v2_", "_v3_", .), na = "NA")

log_msg("\nWrote v3 files to %s", sf_dir)
writeLines(log_lines, here(sf_dir, "_v3_build_log_2026-08-31.txt"))
cat("\n=== v3 BUILD COMPLETE ===\n")
