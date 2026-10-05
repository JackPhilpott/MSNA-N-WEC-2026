# ==============================================================================
# 2026-10-05 one-off (Jack's go in Resampling's window ~06:25, "Strata capacity fix": staged + tested first, reported
# before and after). Recomputes the STRATA FULL frame's achieved_clusters / achieved_sample / realized_moe_pct with
# the UNUSED spare clusters left out: the same computation as merge_partner_resample_batch.R's recompute_strata() for
# FULL (filter_ward_accessible = FALSE), now with exclude_cluster_ids (scripts/shared/spare_clusters.R). Needed once
# because the daily refresh only ever rewrites the strata WORKING frame, while last night's spare merges wrote
# spare-inflated capacity into both.
# All 323 spares are unused, so "spares count nowhere" means exactly the pre-spares (v15) strata FULL file. --write
# restores that file byte for byte, and only after proving the spares are the ONLY difference:
#   (a) live vs v15 differ only in achieved_clusters / achieved_sample / realized_moe_pct, only for strata that hold a
#       spare; (b) recomputing those strata with the unused spares left out gives v15's achieved_clusters and
#       achieved_sample exactly.
# realized_moe_pct is restored, not recomputed: strata FULL's MoE is only ever recomputed when a merge touches a
# stratum, so v15 still holds older-method values for some strata (34 of the 165, found in the 5 Oct sandbox test:
# 0.001-2.4 pts from the current unequal-size formula). Recomputing would silently re-method them - not this fix.
# The before/after table lists the current-method MoE for information.
# Usage (from 1_sampling): Rscript recompute_strata_full_capacity_unused_spares_2026-10-05.R <pre-spares archive> [--write]
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr) })
source("scripts/shared/frame_status.R")
source("scripts/shared/spare_clusters.R")

args <- commandArgs(trailingOnly = TRUE)
ARCHIVE <- args[1]
WRITE <- "--write" %in% args
DC_DIR <- "output/data/data_collection"
SL_NAME <- "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"
MON <- file.path("..", "2_monitoring", "data")

full_hh <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
subs <- read_csv(file.path(MON, "real_submissions.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
overlay <- read_csv(file.path(MON, "CONFIRMED_DELETIONS_OVERLAY.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
register <- load_spare_register(path = file.path(DC_DIR, SPARE_REGISTER_NAME))
unused <- unused_spare_ids(register, achieved_by_cluster(subs, deletion_excluded_uuids(overlay)))
affected <- unique(register$strata_id)
cat(sprintf("register %d spare(s) in %d strata; unused %d\n", nrow(register), length(affected), length(unused)))

# as recompute_strata(sl, hh, filter_ward_accessible = FALSE), restricted to the strata that hold a spare
result <- compute_strata_achieved(full_hh %>% filter(strata_id %in% affected), compute_achieved_lookup(subs, overlay),
                                  filter_ward_accessible = FALSE, exclude_cluster_ids = unused)
agg <- result$agg %>% rename(achieved_clusters_new = achieved_clusters, achieved_sample_new = achieved_sample)
sizes <- split(result$cluster_sizes$n, result$cluster_sizes$strata_id)
sl <- read_csv(file.path(DC_DIR, SL_NAME), show_col_types = FALSE)  # type-guessed, as the merge reads/writes it
j <- sl %>% left_join(agg, by = "strata_id")
new_moe <- mapply(function(sid, a, N_hh, ICC) {
  if (is.na(a) || !(a > 0 & a < N_hh)) return(NA_real_)
  s <- sizes[[sid]]
  if (is.null(s)) return(NA_real_)
  100 * realized_moe_unequal(a, N_hh, s, ICC)
}, j$strata_id, j$achieved_sample_new, j$N_hh, j$ICC)
j$realized_moe_pct <- ifelse(is.na(j$achieved_clusters_new), j$realized_moe_pct, new_moe)
sl_new <- j %>%
  mutate(achieved_clusters = if_else(!is.na(achieved_clusters_new), achieved_clusters_new, achieved_clusters),
         achieved_sample = if_else(!is.na(achieved_sample_new), achieved_sample_new, achieved_sample)) %>%
  select(-achieved_clusters_new, -achieved_sample_new)

v15 <- read_csv(file.path(ARCHIVE, SL_NAME), show_col_types = FALSE)
cmp <- sl_new %>% select(strata_id, ac = achieved_clusters, as = achieved_sample, moe = realized_moe_pct) %>%
  inner_join(v15 %>% select(strata_id, ac0 = achieved_clusters, as0 = achieved_sample, moe0 = realized_moe_pct), by = "strata_id") %>%
  inner_join(sl %>% select(strata_id, ac1 = achieved_clusters, as1 = achieved_sample, moe1 = realized_moe_pct), by = "strata_id")
same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) < 1e-9)
# (b) the recomputed counts of the spare strata equal v15
bad_counts <- cmp %>% filter(strata_id %in% affected, !(same(ac, ac0) & same(as, as0)))
moe_method <- cmp %>% filter(strata_id %in% affected, !same(moe, moe0))
# (a) live vs v15: the only differences are the three capacity columns of the spare strata
sl_chr <- read_csv(file.path(DC_DIR, SL_NAME), col_types = cols(.default = "c"), show_col_types = FALSE)
v15_chr <- read_csv(file.path(ARCHIVE, SL_NAME), col_types = cols(.default = "c"), show_col_types = FALSE)
stopifnot(identical(sl_chr$strata_id, v15_chr$strata_id))
cap <- c("achieved_clusters", "achieved_sample", "realized_moe_pct")
diff_other_cols <- names(sl_chr)[vapply(names(sl_chr), function(c) !(c %in% cap) && !identical(sl_chr[[c]], v15_chr[[c]]), logical(1))]
eq <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
diff_rows <- sl_chr$strata_id[Reduce(`|`, lapply(cap, function(c) !eq(sl_chr[[c]], v15_chr[[c]])))]
stray <- setdiff(diff_rows, affected)
cat(sprintf("strata FULL: %d spare strata; recomputed counts equal to v15: %d of %d; live-vs-v15 differences outside the 3 capacity columns: %d; outside the spare strata: %d\n",
            length(affected), length(affected) - nrow(bad_counts), length(affected), length(diff_other_cols), length(stray)))
cat(sprintf("realized_moe_pct: %d of %d spare strata keep an older-method v15 value (restored as is; current-method value in the table)\n",
            nrow(moe_method), length(affected)))
dir.create(file.path("resampling", "output", "spares_2026-10-05"), recursive = TRUE, showWarnings = FALSE)
write_csv(cmp %>% filter(strata_id %in% affected) %>%
            transmute(strata_id, achieved_clusters_before = ac1, achieved_clusters_after = ac0, achieved_sample_before = as1,
                      achieved_sample_after = as0, realized_moe_pct_before = moe1, realized_moe_pct_after = moe0,
                      realized_moe_pct_current_method_without_spares = moe),
          file.path("resampling", "output", "spares_2026-10-05", "strata_FULL_capacity_fix_before_after.csv"))
if (nrow(bad_counts) > 0 || length(diff_other_cols) > 0 || length(stray) > 0) {
  print(head(bad_counts, 5)); print(diff_other_cols); print(head(stray))
  stop("STOP: the spares are not the only difference from v15 - nothing written", call. = FALSE)
}
if (WRITE) {
  file.copy(file.path(ARCHIVE, SL_NAME), file.path(DC_DIR, SL_NAME), overwrite = TRUE)
  ok <- unname(tools::md5sum(file.path(DC_DIR, SL_NAME))) == unname(tools::md5sum(file.path(ARCHIVE, SL_NAME)))
  cat("restored v15 strata FULL:", file.path(DC_DIR, SL_NAME), "| md5 equal to the archive:", ok, "\n")
  if (!ok) stop("STOP: the restored file's md5 differs from the archive", call. = FALSE)
} else {
  cat("check PASS - nothing written (add --write)\n")
}
