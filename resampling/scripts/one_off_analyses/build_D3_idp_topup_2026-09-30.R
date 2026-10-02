# ==============================================================================
# D3 top-up (2026-09-30, Jack's direct approval, relayed via Coordinator +
# confirmed directly in-window: "I have spoke and given instructions to
# Coordinator regarding needed redraws... I approve you performing these
# tasks and doing all redraws as necessary here tonight"): raises
# target_households/reserve_households on already-LIVE IDP clusters and
# appends brand-new primary+reserve interview slots for the increase.
#
# Ported from build_D3_idp_topup_2026-09-27.R (27 Sep, real, tested, merged
# for FACT+NRC that night) - SAME logic unchanged, only: v13 -> v14 frame
# files, tonight's PLAN, tonight's staging folder. Per-cluster amounts come
# from compute_D3_topup_plan_2026-09-30.py (real topup_search-derived
# greedy, design-weighted model B allocation, fixed to hit each stratum's
# BUFFERED target: buffered = ceil(new_target * 1.10), except Obi IDP which
# uses Jack's own explicit override (66) directly, no buffer applied).
#
# Obi IDP (idp_NG026011_13, Odobu): EXCLUDED from the allocation - currently
# selection_count=1 (non-certainty), and its computed share (+14) would trip
# merge_partner_resample_batch.R's own
# `selection_count = selection_count + as.integer(increase_target/6L)`
# formula, silently flipping it to certainty status - the EXACT SAME
# collision class found and held for this exact stratum on 2026-09-27 (see
# that script's own PLAN comment). Odobu's share was redistributed across
# Obi's other 3 already-certainty clusters instead (all have ample real
# headroom) - nothing held this time, the full 66 is allocated cleanly.
#
# Usage: Rscript build_D3_idp_topup_2026-09-30.R
# Writes existing_cluster_target_increases_idp.csv and existing_cluster_
# household_additions_idp.csv into EACH partner's resample_runs/<Partner>/
# 2026-09-30_D3/ staging folder (created if missing). Does NOT merge -
# merge_partner_resample_batch.R is run separately, per partner, after this.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", show_col_types = FALSE)

# cluster_id -> extra interviews (compute_D3_topup_plan_2026-09-30.py, verified feasible, fully allocated, for every stratum)
PLAN <- list(
  CARE = list(
    idp_NG021006_12 = 3, idp_NG021006_supp1 = 3, idp_NG021006_supp2 = 3,        # Charanchi IDP, +15
    idp_NG021006_supp3 = 2, idp_NG021006_supp4 = 2, idp_NG021006_supp5 = 2,
    idp_NG026011_1 = 22, idp_NG026011_4 = 22, idp_NG026011_9 = 22               # Obi IDP, +66 (Odobu excluded, see header)
  ),
  CRS = list(
    idp_NG034021_9 = 20, idp_NG034021_supp1 = 21, idp_NG034021_supp2 = 20, idp_NG034021_supp3 = 20  # Wamako IDP, +81
  ),
  FACT = list(
    idp_NG037011_3 = 2, idp_NG037011_5 = 3, idp_NG037011_12 = 1,                # Shinkafi IDP, +21
    idp_NG037011_supp1 = 4, idp_NG037011_supp2 = 4, idp_NG037011_supp3 = 3, idp_NG037011_supp4 = 4
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
  STAGE <- file.path("resampling/output/resample_runs", partner, "2026-09-30_D3")
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
