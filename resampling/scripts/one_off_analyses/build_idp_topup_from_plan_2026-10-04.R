# ==============================================================================
# 2026-10-04: build_D3_idp_topup_batch3_margin_2026-09-30.R driven by a plan CSV instead of a hand-typed PLAN list
# (plan_idp_topups_150rule_2026-10-04.py writes it). Same row-building and checks, except that the survey_id
# collision check now runs against FULL (stricter than the 30 Sep version, which checked WORKING only):
# per planned cluster, +increase primary slots (interview_number continues after the cluster's highest in FULL) and
# the same number of reserve slots (replacement_rank continues), copied from the cluster's first FULL row; stops on
# any survey_id collision or a cluster that is not live in FULL and WORKING. STAGING ONLY: writes per partner
#   resampling/output/resample_runs/<Partner>/<label>/existing_cluster_target_increases_idp.csv
#   resampling/output/resample_runs/<Partner>/<label>/existing_cluster_household_additions_idp.csv
#   resampling/output/resample_runs/<Partner>/<label>/empty_shortfalls.csv   (merge_partner_resample_batch.R's 2 shortfall args)
# The merge (merge_partner_resample_batch.R per partner) is a separate, live step.
# Usage: Rscript build_idp_topup_from_plan_2026-10-04.R <plan_by_cluster.csv> <label>
#   A shared stratum ("PLAN, FACT") is staged under its first partner's folder; the rows keep the frame's own
#   partners_covering.
# ==============================================================================
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript build_idp_topup_from_plan_2026-10-04.R <plan_by_cluster.csv> <label>")
PLAN_CSV <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
LABEL <- args[2]
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(purrr) })
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE)
plan_all <- read_csv(PLAN_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  mutate(increase = as.integer(increase), folder = trimws(sub(",.*$", "", partner)))
stopifnot("plan has rows" = nrow(plan_all) > 0, "every increase is a positive integer" = all(plan_all$increase > 0),
          "each cluster planned once" = !anyDuplicated(plan_all$cluster_id))

for (partner in sort(unique(plan_all$folder))) {
  # .env$: inside filter(), a bare `partner` would be the plan's own column, not this loop variable
  plan <- plan_all %>% filter(folder == .env$partner)
  cids <- plan$cluster_id
  cat(sprintf("\n==== %s: %d cluster(s), %d total interviews ====\n", partner, length(cids), sum(plan$increase)))
  existing_current <- full %>%
    filter(cluster_id %in% cids) %>%
    group_by(cluster_id) %>%
    summarise(
      old_target = first(target_households), old_reserve = first(reserve_households),
      old_max_primary = suppressWarnings(max(as.integer(interview_number), na.rm = TRUE)),
      old_max_reserve = suppressWarnings(max(as.integer(replacement_rank), na.rm = TRUE)),
      .groups = "drop"
    )
  stopifnot("every planned cluster_id is currently live in the frame" = nrow(existing_current) == length(cids))
  stopifnot("every planned cluster_id is currently live in WORKING too (not fully excluded)" = all(cids %in% working$cluster_id))
  stopifnot("no old_max_primary/old_max_reserve is -Inf (a cluster with zero current primary or reserve rows)" =
              all(is.finite(existing_current$old_max_primary)), all(is.finite(existing_current$old_max_reserve)))
  target_increases <- tibble(cluster_id = cids, increase_target = plan$increase, increase_reserve = plan$increase) %>%
    left_join(existing_current, by = "cluster_id") %>%
    mutate(new_target = old_target + increase_target, new_reserve = old_reserve + increase_reserve)
  STAGE <- file.path("resampling/output/resample_runs", partner, LABEL)
  if (dir.exists(STAGE) && length(list.files(STAGE)) > 0) stop(sprintf("%s already holds files - choose a new label", STAGE))
  dir.create(STAGE, recursive = TRUE, showWarnings = FALSE)
  write_csv(target_increases, file.path(STAGE, "existing_cluster_target_increases_idp.csv"))
  print(as.data.frame(target_increases %>% select(cluster_id, old_target, increase_target, new_target, old_reserve, increase_reserve, new_reserve)), row.names = FALSE)
  build_additional_rows <- function(cid, inc_target, inc_reserve, old_max_p, old_max_r) {
    template <- full %>% filter(cluster_id == cid) %>% slice(1)
    primary_new <- template[rep(1, inc_target), ] %>%
      mutate(status = "primary", interview_number = old_max_p + seq_len(inc_target), replacement_rank = NA_real_,
             survey_id = sprintf("%s_HH%02d", cid, old_max_p + seq_len(inc_target)))
    reserve_new <- template[rep(1, inc_reserve), ] %>%
      mutate(status = "reserve", interview_number = NA_real_, replacement_rank = old_max_r + seq_len(inc_reserve),
             survey_id = sprintf("%s_R%02d", cid, old_max_r + seq_len(inc_reserve)))
    bind_rows(primary_new, reserve_new)
  }
  additions <- pmap_dfr(
    target_increases %>% select(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve),
    function(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve) {
      build_additional_rows(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve)
    }
  )
  if (anyDuplicated(c(additions$survey_id, full$survey_id)) > 0) {
    stop(sprintf("%s: new survey_id(s) collide with the live FULL frame or each other.", partner))
  }
  write_csv(additions, file.path(STAGE, "existing_cluster_household_additions_idp.csv"))
  writeLines("strata_id,adm2_pcode,pop_type,additional_clusters_needed,state,lga,partners", file.path(STAGE, "empty_shortfalls.csv"))
  cat(sprintf("  %d new interview-slot row(s) built (%d primary + %d reserve); zero survey_id collisions with the live FULL frame.\n",
              nrow(additions), sum(additions$status == "primary"), sum(additions$status == "reserve")))
}
cat("\n==== DONE. Staged only - nothing merged. Run merge_partner_resample_batch.R per partner next. ====\n")
