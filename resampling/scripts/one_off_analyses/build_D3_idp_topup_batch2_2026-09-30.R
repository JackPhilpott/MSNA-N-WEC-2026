# ==============================================================================
# D3 top-up batch 2 (2026-09-30, Task 3 - "close the other 15", Jack/Coordinator
# approved, Jack's own direct in-window confirmation covers this batch too):
# 5 of the 10 candidate IDP strata that are SAFELY closeable at their buffered
# target WITHOUT flipping any currently-non-certainty cluster (selection_count
# ==1) to certainty status via a >=6 single-batch jump - the same collision
# class found for Obi/Odobu on 2026-09-27 and again tonight, this time
# checked and capped BEFORE computing the plan (every selection_count==1
# cluster capped at +5 max in this batch; already-certainty clusters use
# their real headroom uncapped).
#
# The other 5 candidates (Madagali, Magumeri, Keana, Bukkuyum, Bungudu) are
# NOT in this batch - under the same safe cap, 4 of them cannot reach 10%
# MoE at all (the sweep table's "Yes" verdict for those 4 was an uncaught
# certainty-flip artifact, not a real result) and Keana needs a corrected,
# larger total (418, not 390) with no buffer margin achievable. Reported
# separately, not executed here - see project memory.
#
# Per-cluster amounts: compute_D3_topup_plan (capped-supply variant),
# idp_batch2_plan_2026-09-30.json, verified feasible (<=10% MoE) for all 5.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE)

PLAN <- list(
  FACT = list(
    idp_NG021025_8 = 76, idp_NG021025_10 = 91, idp_NG021025_supp4 = 30,                          # Malumfashi, +197
    idp_NG037009_7 = 216, idp_NG037009_13 = 100                                                   # Maradun, +316
  ),
  CRS = list(
    idp_NG032002_1 = 4, idp_NG032002_2 = 12, idp_NG032002_supp1 = 12                              # Bassa, +28
  ),
  DRC = list(
    idp_NG034016_1 = 21, idp_NG034016_14 = 22, idp_NG034016_supp1 = 22,
    idp_NG034016_supp2 = 22, idp_NG034016_supp3 = 22                                              # Sokoto North IDP, +109
  ),
  ZOA = list(
    idp_NG034018_10 = 5, idp_NG034018_15 = 5, idp_NG034018_16 = 4,
    idp_NG034018_supp1 = 5, idp_NG034018_supp2 = 5, idp_NG034018_supp4 = 8                        # Tambuwal, +32
  )
)

for (partner in names(PLAN)) {
  plan <- PLAN[[partner]]
  if (length(plan) == 0) { cat(sprintf("\n==== %s: HELD, skipping ====\n", partner)); next }
  cids <- names(plan)
  incs <- unlist(plan)
  cat(sprintf("\n==== %s: %d cluster(s), %d total interviews ====\n", partner, length(cids), sum(incs)))

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

  target_increases <- tibble(cluster_id = cids, increase_target = as.integer(incs), increase_reserve = as.integer(incs)) %>%
    left_join(existing_current, by = "cluster_id") %>%
    mutate(new_target = old_target + increase_target, new_reserve = old_reserve + increase_reserve)
  STAGE <- file.path("resampling/output/resample_runs", partner, "2026-09-30_D3_batch2")
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
  additions <- purrr::pmap_dfr(
    target_increases %>% select(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve),
    function(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve) {
      build_additional_rows(cluster_id, increase_target, increase_reserve, old_max_primary, old_max_reserve)
    }
  )
  if (anyDuplicated(c(additions$survey_id, working$survey_id)) > 0) {
    stop(sprintf("%s: new survey_id(s) collide with the live frame or each other.", partner))
  }
  write_csv(additions, file.path(STAGE, "existing_cluster_household_additions_idp.csv"))
  cat(sprintf("  %d new interview-slot row(s) built (%d primary + %d reserve), verified: zero survey_id collisions with the live frame.\n",
              nrow(additions), sum(additions$status == "primary"), sum(additions$status == "reserve")))
  stopifnot("every new survey_id is genuinely new, not a relabeled existing row" = !any(additions$survey_id %in% working$survey_id))
  cat("  CONFIRMED: every new row is a fresh survey_id; zero existing rows touched or relabeled.\n")
}
cat("\n==== DONE. Staged only - nothing merged. Run merge_partner_resample_batch.R per partner next. ====\n")
