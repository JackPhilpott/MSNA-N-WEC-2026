# ==============================================================================
# D3 top-up (2026-09-27, Jack's direct approval): raises target_households/
# reserve_households on 8 ALREADY-LIVE IDP clusters and appends brand-new
# primary+reserve interview slots for the increase - the SAME mechanism
# already tested and merged once (INTERSOS, 2026-08-30, existing_cluster_
# target_increases_idp.csv / existing_cluster_household_additions_idp.csv,
# read by merge_partner_resample_batch.R's own dedicated code path). Ported
# from draw_supplementary_idp_clusters_batch.R's Stage F, NOT re-derived -
# same template-row-copy, same sequential-numbering-continuation, same
# collision check. Genuinely NEW here: the per-cluster increase amount is
# hand-specified (from tonight's R4 model-B top-up search, Jack-approved),
# not derived from a newly-drawn repeat-site cluster - everything else is
# the tested logic unchanged.
#
# WHY THIS ANSWERS JACK'S RESERVE-ROW CONCERN (asked tonight, before this
# ran): this mechanism NEVER touches an existing row's status. It only (a)
# raises target_households/reserve_households on the target cluster and (b)
# APPENDS new rows with fresh survey_ids, numbered after the cluster's
# current max interview_number/replacement_rank. No existing reserve row is
# relabeled, removed from a future draw's candidate pool, or double-listed -
# there is nothing for a downstream KML/workbook/pool consumer to duplicate,
# because nothing existing changes. See the pre-flight and post-write
# verification below for the mechanical proof, not just this claim.
#
# Usage: Rscript build_D3_idp_topup_2026-09-27.R
# Writes existing_cluster_target_increases_idp.csv and existing_cluster_
# household_additions_idp.csv into EACH partner's resample_runs/<Partner>/
# 2026-09-27_D3/ staging folder (created if missing). Does NOT merge -
# merge_partner_resample_batch.R is run separately, per partner, after this.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", show_col_types = FALSE)
# FULL, not WORKING, for the cluster's current max interview_number/replacement_rank and the template row: WORKING only carries
# NOT-YET-ACHIEVED rows, so a cluster whose primary slots are already fully achieved (0 primary rows left in WORKING) would
# wrongly compute old_max_primary = -Inf from WORKING alone - caught by this script's own pre-flight check on the first real
# run, not a silent bug. FULL always carries every row regardless of achieved status, so max() there is always correct.
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv", show_col_types = FALSE)

# cluster_id -> named list of interview_number -> extra interviews (from the fresh R4 model-B recompute on tonight's live data, verified feasible for every stratum)
PLAN <- list(
  FACT = list(
    idp_NG021001_supp2 = 3, idp_NG021001_supp3 = 3, idp_NG021001_supp4 = 3,                                     # Bakori, +9
    idp_NG021004_1 = 3, idp_NG021004_2 = 3, idp_NG021004_7 = 2, idp_NG021004_8 = 2, idp_NG021004_13 = 2,        # Baure, +12
    idp_NG021020_supp1 = 1, idp_NG021020_supp2 = 1, idp_NG021020_supp3 = 1, idp_NG021020_supp4 = 1,             # Kankia, +4
    idp_NG037011_5 = 1, idp_NG037011_supp1 = 1, idp_NG037011_supp2 = 1, idp_NG037011_supp3 = 1,                 # Shinkafi, +4
    idp_NG021023_1 = 4, idp_NG021023_4 = 5, idp_NG021023_5 = 2, idp_NG021023_9 = 5, idp_NG021023_supp1 = 5      # Kusada, +21
  ),
  NRC = list(
    idp_NG002004_9 = 2, idp_NG002004_10 = 2, idp_NG002004_supp1 = 1, idp_NG002004_supp2 = 1,                    # Gombi, +9
    idp_NG002004_supp3 = 1, idp_NG002004_supp4 = 1, idp_NG002004_supp5 = 1
  ),
  # Obi (CARE) and Bassa (CRS) HELD for now: 2 of Obi's 4 clusters and 2 of Bassa's 3 clusters get exactly +6 interviews,
  # which trips merge_partner_resample_batch.R's own selection_count = selection_count + as.integer(increase_target/6L)
  # formula (built for whole-cluster merges, not individual-interview top-ups). idp_NG026011_13 and idp_NG032002_1 are
  # CURRENTLY selection_count=1 (not certainty) - this would silently flip them to certainty status, changing how 05
  # computes their MoE in a way tonight's approved R4 numbers never accounted for. Flagged, not pushed through - see
  # this script's own console output / the report to the Coordinator.
  CARE = list(),
  CRS = list()
)

for (partner in names(PLAN)) {
  plan <- PLAN[[partner]]
  if (length(plan) == 0) { cat(sprintf("\n==== %s: HELD, skipping (see comment above PLAN) ====\n", partner)); next }
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
  STAGE <- file.path("resampling/output/resample_runs", partner, "2026-09-27_D3")
  dir.create(STAGE, recursive = TRUE, showWarnings = FALSE)
  write_csv(target_increases, file.path(STAGE, "existing_cluster_target_increases_idp.csv"))
  print(as.data.frame(target_increases %>% select(cluster_id, old_target, increase_target, new_target, old_reserve, increase_reserve, new_reserve)), row.names = FALSE)

  # target_households/reserve_households on the new rows are LEFT AT THE TEMPLATE'S OWN (OLD) VALUE, not pre-set to
  # new_target/new_reserve - merge_partner_resample_batch.R itself adds increase_target/increase_reserve UNIFORMLY
  # across every row of the cluster (existing AND newly-appended) in one pass AFTER binding everything together
  # (its own comment: "increase_target once uniformly post-bind because every row of an affected..."). Pre-setting
  # new_target here would double-apply the increase on these rows once the merge script also adds it. Every other
  # column (ward/GPS/site/etc.) correctly comes from the template unchanged.
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

  # Mechanical proof for Jack's reserve-row concern: no EXISTING survey_id anywhere in `additions`, and no existing row's status changes.
  stopifnot("every new survey_id is genuinely new, not a relabeled existing row" = !any(additions$survey_id %in% working$survey_id))
  cat("  CONFIRMED: every new row is a fresh survey_id; zero existing rows touched or relabeled.\n")
}
cat("\n==== DONE. Staged only - nothing merged. Run merge_partner_resample_batch.R per partner next. ====\n")
