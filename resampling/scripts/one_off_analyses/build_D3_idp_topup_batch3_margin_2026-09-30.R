# ==============================================================================
# D3 top-up batch 3 (2026-09-30, Jack's direct instruction, in-window):
# "make sure we're leaving enough headroom/buffering... aim for 9-9.5% moe"
# rather than just <=10%, wherever real headroom allows it.
#
# Two purposes in one batch:
# 1. REINFORCEMENT of 3 already-executed batch-2 strata that landed close to
#    10% (Sokoto North IDP 9.53%, Tambuwal 9.85%, Maradun 9.75%) - additional
#    real interviews computed via the same certainty-safe capped search,
#    retargeted at 9.25% instead of 10%. Malumfashi (9.79%) deliberately NOT
#    included - already at its real physical ceiling (197 of 208 requested
#    allocated last batch; the capped-supply search confirms 9.25% is not
#    reachable, 9.79% is the honest best achievable) - reported, not forced.
# 2. Keana IDP's FIRST real execution, at the corrected 9.25%-target total
#    (434, not the earlier 390/418 figures - both of those relied on either
#    the certainty-flip artifact or the plain <=10% target respectively).
#
# Per-cluster amounts: search_to_target(), same capped-supply mechanism as
# batch 2 (selection_count==1 clusters capped at +5/batch, already-certainty
# clusters use real headroom uncapped) - verified feasible for all 4.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE)

PLAN <- list(
  DRC = list(
    idp_NG034016_14 = 2, idp_NG034016_supp1 = 4, idp_NG034016_supp2 = 4, idp_NG034016_supp3 = 4   # Sokoto North IDP reinforcement, +14
  ),
  ZOA = list(
    idp_NG034018_10 = 5, idp_NG034018_15 = 5, idp_NG034018_16 = 5,
    idp_NG034018_supp1 = 5, idp_NG034018_supp2 = 5, idp_NG034018_supp4 = 6                        # Tambuwal reinforcement, +31
  ),
  FACT = list(
    idp_NG037009_7 = 25, idp_NG037009_13 = 2                                                      # Maradun reinforcement, +27
  ),
  CARE = list(
    idp_NG026005_1 = 424, idp_NG026005_14 = 5, idp_NG026005_15 = 5                                 # Keana IDP, first execution, +434
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
  STAGE <- file.path("resampling/output/resample_runs", partner, "2026-09-30_D3_batch3_margin")
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
