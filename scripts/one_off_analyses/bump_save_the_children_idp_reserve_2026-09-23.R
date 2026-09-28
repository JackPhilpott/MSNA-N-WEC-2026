# ==============================================================================
# Save the Children asked for excess samples / more field options (2026-09-23).
# Jack approved (AskUserQuestion): bump reserve households from the project-
# wide 1.0x-of-target standard to 1.5x, for Save's clusters only - IDP side
# only (idp_NG007011, Kwande - Save's only remaining live IDP stratum after
# idp_NG021024's drop earlier today). Non-IDP reserve is handled separately
# (extra buffer clusters instead - see draw_supplementary_clusters_batch.R's
# 2026-09-23_excess_buffer_round2 run), since Non-IDP reserve rows are each
# tied to a real building and no "add reserve, keep primary fixed" draw tool
# exists yet; building one under time pressure on a live frame was judged too
# risky for tonight (Jack's own call).
#
# IDP reserve rows carry NO building_id and all share their site's single
# lat/lon (checked directly: idp_NG007011_1's 12 reserve rows are identical
# except survey_id/replacement_rank) - they're simple numbered placeholder
# slots, not real household draws (the real list is built by field teams on
# arrival, per the 2026-08-04 reserve-scaling revision's own IDP rationale).
# Safe to extend by cloning the template row's static fields and continuing
# the replacement_rank sequence - no building/GIS draw involved.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

DC_DIR <- "output/data/data_collection"
hh_path <- file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv")

STRATA_ID <- "idp_NG007011"
RESERVE_MULTIPLIER <- 1.5

archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_save_the_children_idp_reserve_bump"))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))

clusters <- full_hh %>%
  filter(strata_id == STRATA_ID, coverage_status == "covered") %>%
  distinct(cluster_id) %>% pull(cluster_id)
cat(sprintf("%d active cluster(s) in %s: %s\n", length(clusters), STRATA_ID, paste(clusters, collapse = ", ")))

n_hh_before <- nrow(full_hh)
new_rows_list <- list()
summary_rows <- list()

for (cid in clusters) {
  crows <- full_hh %>% filter(cluster_id == cid)
  target_hh <- as.integer(crows$target_households[1])
  current_reserve <- as.integer(crows$reserve_households[1])
  stopifnot(current_reserve == target_hh)  # confirmed 1.0x baseline before this bump, every cluster
  reserve_rows <- crows %>% filter(status == "reserve")
  stopifnot(nrow(reserve_rows) == current_reserve)

  new_reserve_target <- ceiling(target_hh * RESERVE_MULTIPLIER)
  n_to_add <- new_reserve_target - current_reserve
  summary_rows[[length(summary_rows) + 1]] <- tibble(cluster_id = cid, target_hh = target_hh,
                                                       reserve_before = current_reserve,
                                                       reserve_after = new_reserve_target, n_added = n_to_add)
  if (n_to_add <= 0) next

  template <- reserve_rows[1, ]
  max_rank <- max(as.integer(reserve_rows$replacement_rank))
  for (k in seq_len(n_to_add)) {
    new_row <- template
    rank <- max_rank + k
    new_row$replacement_rank <- as.character(rank)
    new_row$survey_id <- sprintf("%s_R%02d", cid, rank)
    new_rows_list[[length(new_rows_list) + 1]] <- new_row
  }
}

summary_df <- bind_rows(summary_rows)
cat("\nPer-cluster reserve bump (1.0x -> 1.5x of target, rounded up):\n")
print(as.data.frame(summary_df))
cat(sprintf("\nTotal new reserve row(s) to add: %d\n", sum(summary_df$n_added)))

new_rows_df <- bind_rows(new_rows_list)
stopifnot(nrow(new_rows_df) == sum(summary_df$n_added))
stopifnot(!anyDuplicated(c(full_hh$survey_id, new_rows_df$survey_id)))

full_hh <- bind_rows(full_hh, new_rows_df) %>%
  mutate(reserve_households = if_else(
    cluster_id %in% clusters,
    as.character(summary_df$reserve_after[match(cluster_id, summary_df$cluster_id)]),
    reserve_households
  ))

# ---- Verify + write ----------------------------------------------------------
stopifnot(nrow(full_hh) == n_hh_before + nrow(new_rows_df))
check <- full_hh %>% filter(cluster_id %in% clusters) %>%
  group_by(cluster_id) %>%
  summarise(n_reserve = sum(status == "reserve"), reserve_households = first(reserve_households), .groups = "drop") %>%
  left_join(summary_df %>% select(cluster_id, reserve_after), by = "cluster_id")
stopifnot(all(check$n_reserve == as.integer(check$reserve_households)), all(as.integer(check$reserve_households) == check$reserve_after))

write_csv(full_hh, hh_path)
cat(sprintf("\nWritten. %d household rows before -> %d after (+%d reserve rows across %d cluster(s)).\n",
            n_hh_before, nrow(full_hh), nrow(new_rows_df), length(clusters)))
