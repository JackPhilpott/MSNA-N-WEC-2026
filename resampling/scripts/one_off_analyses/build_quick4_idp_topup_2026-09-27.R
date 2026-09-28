# ==============================================================================
# "Quick 4" IDP top-up (2026-09-27, Jack's direct approval in-window: "yes to
# top up the quick 4 mentioned here"), time-boxed ahead of the DO handoff.
# Same tested append-only mechanism as tonight's earlier D3 batch (6 real
# applications already) - see build_D3_idp_topup_2026-09-27.R's header for
# the full mechanism rationale; not re-derived here.
#
# Per-cluster allocation for Shinkafi/Mubi North/Kaga: replayed topup_search()
# (model B, design-weighted) directly from tonight's fresh build_
# representativity_review.py run via quick4_percluster.json - not re-derived,
# not hand-guessed. Every increment is exactly 1 (Shinkafi 2 clusters, Mubi
# North 3, Kaga 5) - nowhere near the /6 selection_count-flip risk found for
# Obi/Bassa (held separately, untouched by this script).
#
# Faskari uses a DIFFERENT, already-accepted route: the R3 certainty-site
# top-up (adopted 21 Sep), not the generic R4 mechanism - single cluster
# idp_NG021013_supp2, +3, per S5_topup_list.csv from the same fresh run.
# Structurally identical append-only pattern either way (raise target on
# the cluster, append new primary+reserve rows) - the two mechanisms differ
# only in which route decided the interview count, not in how it's applied.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv", show_col_types = FALSE)

# cluster_id -> extra PRIMARY interviews (reserve increase mirrors it 1:1, same convention as D3 tonight)
PLAN <- list(
  FACT = list(idp_NG037011_supp1 = 1, idp_NG037011_supp2 = 1,                                   # Shinkafi, +2
              idp_NG008014_1 = 1, idp_NG008014_supp2 = 1, idp_NG008014_supp3 = 1,                # Kaga, +5
              idp_NG008014_supp5 = 1, idp_NG008014_supp7 = 1,
              idp_NG021013_supp2 = 3),                                                            # Faskari (R3 route), +3
  NRC  = list(idp_NG002014_12 = 1, idp_NG002014_13 = 1, idp_NG002014_16 = 1)                      # Mubi North, +3
)

for (partner in names(PLAN)) {
  plan <- PLAN[[partner]]
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
  STAGE <- file.path("resampling/output/resample_runs", partner, "2026-09-27_quick4")
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
