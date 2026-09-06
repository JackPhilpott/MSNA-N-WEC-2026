# ==============================================================================
# Found 2026-09-02, immediately after merge_partner_resample_batch.R's FACT
# run: two problems in the live FULL/WORKING frame, both traced to that
# merge, not to anything before it.
#
# 1. The 20 clusters merge_partner_resample_batch.R expanded via Stage F's
#    "repeat-site merge" path (existing_cluster_target_increases_idp.csv)
#    ended up with target_households/reserve_households/selection_count
#    that are NOT uniform across that cluster_id's own rows - some rows
#    show the old (pre-increase) value, some show the new one. Root cause:
#    apply_target_increase() updates the rows already in full_hh/working_hh
#    at load time, but the newly-appended rows (existing_cluster_household_
#    additions_idp.csv, built by draw_supplementary_idp_clusters_batch.R's
#    build_additional_rows() off a template copied BEFORE the increase was
#    known) are bound on afterward with the template's stale value baked
#    in - never re-normalized. Fixed here directly from
#    existing_cluster_target_increases_idp.csv's own new_target/new_reserve
#    (ground truth for what every row of that cluster_id should show),
#    applied uniformly, rather than guessed from row counts (which can
#    legitimately differ cluster-to-cluster for unrelated reasons, e.g.
#    real-world deletions flowing back from 2_monitoring - not this bug).
#
# 2. idp_NG021001_supp1 (Nadabo Primary School Camp, Bakori) reappeared as
#    a live duplicate of idp_NG021001_9 - the exact same collision fixed
#    earlier tonight by patch_merge_nadabo_duplicate_cluster_2026-09-02.R.
#    Cause: that fix freed up the "_supp1" id, and FACT's very next IDP
#    batch (run immediately after) renumbered its own new Bakori draw
#    starting from ".existing_max + 1" - i.e. it silently reused the just-
#    vacated id. That draw's own site-collision safety check (Stage F)
#    should have caught this (both resolve to iom_site_id "New Camp" /
#    iom_site_name "Nadabo Primary School Camp") but reported it as
#    "genuinely new" instead - the mismatch between the check's own log
#    output and the final merged data needs separate investigation, not
#    done here; this patch only fixes the resulting live data, using the
#    same already-established merge-not-duplicate policy as before.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

increases <- read_csv("resampling/output/resample_runs/FACT/2026-09-02/existing_cluster_target_increases_idp.csv", show_col_types = FALSE) %>%
  transmute(cluster_id, new_target = as.character(new_target), new_reserve = as.character(new_reserve),
            new_selection_count = as.character(as.integer(new_target) / 6L))

normalize_targets <- function(path) {
  df <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c"))
  before_mismatch <- df %>% filter(cluster_id %in% increases$cluster_id) %>%
    group_by(cluster_id) %>% summarise(n_distinct_target = n_distinct(target_households), .groups = "drop") %>%
    filter(n_distinct_target > 1) %>% nrow()
  df <- df %>%
    left_join(increases, by = "cluster_id") %>%
    mutate(
      target_households = if_else(!is.na(new_target), new_target, target_households),
      reserve_households = if_else(!is.na(new_reserve), new_reserve, reserve_households),
      selection_count = if_else(!is.na(new_selection_count), new_selection_count, selection_count)
    ) %>%
    select(-new_target, -new_reserve, -new_selection_count)
  write_csv(df, path)
  cat(sprintf("  %s: normalized %d cluster(s) that had internal inconsistency (of %d total expanded clusters checked).\n",
              basename(path), before_mismatch, nrow(increases)))
}

cat("Fixing target_households/reserve_households/selection_count uniformity on FACT-expanded clusters...\n")
normalize_targets(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"))
normalize_targets(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"))

# ---- Re-merge the reappeared Nadabo duplicate (idp_NG021001_supp1 -> idp_NG021001_9) ----
KEEP_ID <- "idp_NG021001_9"
DROP_ID <- "idp_NG021001_supp1"

merge_household_frame <- function(path) {
  df <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c"))
  keep_rows <- df %>% filter(cluster_id == KEEP_ID)
  drop_rows <- df %>% filter(cluster_id == DROP_ID)
  if (nrow(drop_rows) == 0) {
    cat(sprintf("  %s: no %s rows present - nothing to re-merge here.\n", basename(path), DROP_ID))
    return(invisible(NULL))
  }
  other_rows <- df %>% filter(!cluster_id %in% c(KEEP_ID, DROP_ID))

  old_max_primary <- max(as.integer(keep_rows$interview_number), na.rm = TRUE)
  old_max_reserve <- max(as.integer(keep_rows$replacement_rank), na.rm = TRUE)
  new_target <- as.integer(keep_rows$target_households[1]) + as.integer(drop_rows$target_households[1])
  new_reserve <- as.integer(keep_rows$reserve_households[1]) + as.integer(drop_rows$reserve_households[1])
  new_selection_count <- as.integer(keep_rows$selection_count[1]) + as.integer(drop_rows$selection_count[1])

  drop_primary <- drop_rows %>% filter(status == "primary") %>% arrange(as.integer(interview_number)) %>%
    mutate(interview_number = as.character(old_max_primary + seq_len(n())),
           survey_id = sprintf("%s_HH%02d", KEEP_ID, old_max_primary + seq_len(n())), cluster_id = KEEP_ID)
  drop_reserve <- drop_rows %>% filter(status == "reserve") %>% arrange(as.integer(replacement_rank)) %>%
    mutate(replacement_rank = as.character(old_max_reserve + seq_len(n())),
           survey_id = sprintf("%s_R%02d", KEEP_ID, old_max_reserve + seq_len(n())), cluster_id = KEEP_ID)

  keep_rows_updated <- bind_rows(keep_rows, drop_primary, drop_reserve) %>%
    mutate(target_households = as.character(new_target), reserve_households = as.character(new_reserve),
           selection_count = as.character(new_selection_count))

  out <- bind_rows(other_rows, keep_rows_updated)
  if (anyDuplicated(out$survey_id) > 0) stop("Duplicate survey_id after re-merge in ", path)
  write_csv(out, path)
  cat(sprintf("  %s: re-merged %d %s row(s) into %s (target now %s). Rows %d -> %d.\n",
              basename(path), nrow(drop_rows), DROP_ID, KEEP_ID, new_target, nrow(df), nrow(out)))
}

cat("\nRe-merging reappeared Nadabo duplicate...\n")
merge_household_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"))
merge_household_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"))

recompute_strata_file <- function(sl_path, hh_path, strata) {
  sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))
  hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
  agg <- hh %>% filter(strata_id == strata, status == "primary") %>%
    summarise(achieved_clusters = n_distinct(cluster_id), achieved_sample = n())
  if (nrow(agg) == 0 || !strata %in% sl$strata_id) return(invisible(NULL))
  old <- sl %>% filter(strata_id == strata) %>% select(achieved_clusters, achieved_sample)
  sl <- sl %>% mutate(
    achieved_clusters = if_else(strata_id == strata, as.character(agg$achieved_clusters), achieved_clusters),
    achieved_sample = if_else(strata_id == strata, as.character(agg$achieved_sample), achieved_sample)
  )
  write_csv(sl, sl_path)
  cat(sprintf("  %s: %s achieved_clusters %s->%s, achieved_sample %s->%s.\n",
              basename(sl_path), strata, old$achieved_clusters[1], agg$achieved_clusters, old$achieved_sample[1], agg$achieved_sample))
}
cat("\nRecomputing idp_NG021001 strata-level figures...\n")
recompute_strata_file(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_FULL.csv"),
                       file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"), "idp_NG021001")
recompute_strata_file(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"),
                       file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"), "idp_NG021001")

cat("\nDONE.\n")
