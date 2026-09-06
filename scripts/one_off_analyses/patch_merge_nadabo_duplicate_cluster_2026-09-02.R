# ==============================================================================
# Found 2026-09-02 while running FACT's IDP supplementary draw for this
# week's swap/Funtua batch: draw_supplementary_idp_clusters_batch.R's own
# (iom_site_id, iom_site_name) 1:1 precondition check failed for "New Camp /
# Nadabo Primary School Camp" - idp_NG021001_9 (original design cluster,
# selection_count=4, target/reserve=24, from a repeat-hex merge - i.e. this
# physical site was drawn 4 times in the original PPS draw and correctly
# merged into ONE cluster_id via merge_repeated_psu_draws()) and
# idp_NG021001_supp1 (a supplementary cluster added during an earlier FACT
# resample batch this week, target/reserve=6, selection_count=1) are two
# SEPARATE cluster_ids in the live v4 FULL/WORKING frame that share the
# exact same uuid_hex/lat-lon - the same physical DTM camp got fielded
# twice under two different cluster_ids. Confirmed nationally isolated: the
# only (iom_site_id, iom_site_name) pair in the entire IDP frame mapping to
# >1 cluster_id (checked directly, not assumed).
#
# Root cause not fully traced (predates this session's involvement -
# idp_NG021001_supp1 already existed as of last night's Tier-2 backup-point
# patch) - likely the earlier ad hoc/pilot supplementary draw that created
# it ran before draw_supplementary_idp_clusters_batch.R's site-collision
# check existed in its current form. Not investigated further; this patch
# fixes the resulting live-frame data, which is the actionable problem
# (both clusters are in WORKING - two field visits were being planned to
# one camp).
#
# Fix, per Jack's own already-established policy for this exact scenario
# (2026-08-30, documented in draw_supplementary_idp_clusters_batch.R's own
# header): MERGE the duplicate into the original cluster rather than ship/
# keep two cluster_ids for one site. idp_NG021001_supp1's 6 primary + 6
# reserve household rows are renumbered and reattached under
# idp_NG021001_9 (continuing its existing interview_number/replacement_rank
# sequence), target_households/reserve_households/selection_count updated
# on ALL of idp_NG021001_9's rows, and idp_NG021001_supp1 is dropped
# entirely - applied to both FULL and WORKING. idp_NG021001_supp1's row in
# idp_camp_backup_points.csv (added by this session last night, before this
# duplicate was found) is also dropped - idp_NG021001_9 already has its own
# backup point from the original 2026-08-05 blanket expansion, so no
# backup-point coverage is lost.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

KEEP_ID <- "idp_NG021001_9"
DROP_ID <- "idp_NG021001_supp1"

merge_household_frame <- function(path) {
  df <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c"))
  keep_rows <- df %>% filter(cluster_id == KEEP_ID)
  drop_rows <- df %>% filter(cluster_id == DROP_ID)
  if (nrow(drop_rows) == 0) {
    cat(sprintf("  %s: no %s rows present - nothing to merge here.\n", basename(path), DROP_ID))
    return(invisible(NULL))
  }
  other_rows <- df %>% filter(!cluster_id %in% c(KEEP_ID, DROP_ID))

  old_max_primary <- max(as.integer(keep_rows$interview_number), na.rm = TRUE)
  old_max_reserve <- max(as.integer(keep_rows$replacement_rank), na.rm = TRUE)
  new_target <- as.integer(keep_rows$target_households[1]) + as.integer(drop_rows$target_households[1])
  new_reserve <- as.integer(keep_rows$reserve_households[1]) + as.integer(drop_rows$reserve_households[1])
  new_selection_count <- as.integer(keep_rows$selection_count[1]) + as.integer(drop_rows$selection_count[1])

  drop_primary <- drop_rows %>% filter(status == "primary") %>% arrange(as.integer(interview_number))
  drop_reserve <- drop_rows %>% filter(status == "reserve") %>% arrange(as.integer(replacement_rank))

  drop_primary <- drop_primary %>%
    mutate(
      interview_number = as.character(old_max_primary + seq_len(n())),
      survey_id = sprintf("%s_HH%02d", KEEP_ID, old_max_primary + seq_len(n())),
      cluster_id = KEEP_ID
    )
  drop_reserve <- drop_reserve %>%
    mutate(
      replacement_rank = as.character(old_max_reserve + seq_len(n())),
      survey_id = sprintf("%s_R%02d", KEEP_ID, old_max_reserve + seq_len(n())),
      cluster_id = KEEP_ID
    )

  keep_rows_updated <- bind_rows(keep_rows, drop_primary, drop_reserve) %>%
    mutate(
      target_households = as.character(new_target),
      reserve_households = as.character(new_reserve),
      selection_count = as.character(new_selection_count)
    )

  out <- bind_rows(other_rows, keep_rows_updated)
  if (anyDuplicated(out$survey_id) > 0) stop("Duplicate survey_id after Nadabo merge in ", path)
  write_csv(out, path)
  cat(sprintf("  %s: merged %d %s row(s) into %s (target %s->%s, reserve %s->%s, selection_count %s->%s). Rows %d -> %d.\n",
              basename(path), nrow(drop_rows), DROP_ID, KEEP_ID,
              keep_rows$target_households[1], new_target, keep_rows$reserve_households[1], new_reserve,
              keep_rows$selection_count[1], new_selection_count, nrow(df), nrow(out)))
}

cat("Merging Nadabo duplicate cluster in household-level frames...\n")
merge_household_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"))
merge_household_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"))

# ---- Recompute strata-level achieved_clusters/achieved_sample for idp_NG021001 ----
recompute_strata_file <- function(sl_path, hh_path) {
  sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))
  hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
  agg <- hh %>% filter(strata_id == "idp_NG021001", status == "primary") %>%
    summarise(achieved_clusters = n_distinct(cluster_id), achieved_sample = n())
  if (nrow(agg) == 0 || !"idp_NG021001" %in% sl$strata_id) {
    cat(sprintf("  %s: idp_NG021001 not present - skipped.\n", basename(sl_path)))
    return(invisible(NULL))
  }
  old <- sl %>% filter(strata_id == "idp_NG021001") %>% select(achieved_clusters, achieved_sample)
  sl <- sl %>% mutate(
    achieved_clusters = if_else(strata_id == "idp_NG021001", as.character(agg$achieved_clusters), achieved_clusters),
    achieved_sample = if_else(strata_id == "idp_NG021001", as.character(agg$achieved_sample), achieved_sample)
  )
  write_csv(sl, sl_path)
  cat(sprintf("  %s: idp_NG021001 achieved_clusters %s->%s, achieved_sample %s->%s.\n",
              basename(sl_path), old$achieved_clusters[1], agg$achieved_clusters, old$achieved_sample[1], agg$achieved_sample))
}

cat("\nRecomputing strata-level achieved_clusters/achieved_sample...\n")
recompute_strata_file(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_FULL.csv"),
                       file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv"))
recompute_strata_file(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"),
                       file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"))

# ---- Drop idp_NG021001_supp1's row from the Tier-2 backup points CSV ----
bp_path <- file.path(DC_DIR, "idp_camp_backup_points.csv")
bp <- read_csv(bp_path, show_col_types = FALSE)
n_before <- nrow(bp)
bp <- bp %>% filter(site_id != DROP_ID)
write_csv(bp, bp_path)
cat(sprintf("\n%s: dropped %d row(s) for %s (already covered by %s's own backup point). %d -> %d rows.\n",
            basename(bp_path), n_before - nrow(bp), DROP_ID, KEEP_ID, n_before, nrow(bp)))

cat("\nDONE.\n")
