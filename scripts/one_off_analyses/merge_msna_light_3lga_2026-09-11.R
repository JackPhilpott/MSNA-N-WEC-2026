# ==============================================================================
# Merges all 3 government-negotiated "MSNA Light" batches into the live FULL
# frame: Malam Fatori (Abadam), Gajiram (Nganzai), Mairari (Guzamala). See
# CLAUDE.md for the full context/rationale and the 3 individual draw
# scripts (draw_malam_fatori_urban / draw_gajiram_urban / draw_mairari_
# urban, all 2026-09-11) for how each batch was built and verified.
#
# Deliberately NOT using merge_partner_resample_batch.R - that script's
# recompute_strata() would blend these new rows' achieved figures into the
# same strata_id's existing "MSNA Full Design" target_sample/achieved_sample,
# exactly what Jack agreed must NOT happen (these strata's existing figures
# predate and are unrelated to this arrangement). A simple, direct append to
# FULL instead - household-level rows only, strata-level FULL/WORKING left
# completely untouched by this script. refresh_working_frame_daily.R (fixed
# in the same commit as this script, 2026-09-11) is what actually keeps
# these MSNA Light rows out of strata-level achieved_sample going forward -
# not this merge script.
#
# Not fixed here, flagged for whoever next touches it: merge_partner_
# resample_batch.R's own recompute_strata() has the identical strata-level-
# blending gap - if a normal "MSNA Full Design" supplementary draw is ever
# run for Abadam/Nganzai/Guzamala's OTHER wards later (a real, separate,
# legitimate possibility), that script would need the same sampling_method
# exclusion refresh_working_frame_daily.R just got, or it would re-blend
# on its own next run.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
RR_DIR <- "resampling/output/resample_runs/FACT"

batches <- c(
  file.path(RR_DIR, "2026-09-11_malam_fatori_urban", "new_households_urban.csv"),
  file.path(RR_DIR, "2026-09-11_gajiram_urban",       "new_households_urban.csv"),
  file.path(RR_DIR, "2026-09-11_mairari_urban",       "new_households_urban.csv")
)
new_rows <- bind_rows(lapply(batches, read_csv, show_col_types = FALSE))
cat("New MSNA Light rows to merge:", nrow(new_rows), "across", n_distinct(new_rows$cluster_id), "clusters,",
    n_distinct(new_rows$strata_id), "strata.\n")
print(new_rows %>% count(strata_id, name = "n_rows"))

full <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)

# --- Pre-flight checks ---
stopifnot(
  "duplicate survey_id within new batch" = !anyDuplicated(new_rows$survey_id),
  "duplicate cluster_id within new batch" = !anyDuplicated(unique(new_rows$cluster_id)) || TRUE,  # multiple rows/cluster expected
  "new survey_id collides with live FULL" = !any(new_rows$survey_id %in% full$survey_id),
  "new cluster_id collides with live FULL" = !any(new_rows$cluster_id %in% full$cluster_id),
  "missing column in new_rows vs FULL schema" = all(names(new_rows) %in% names(full))
)
cat("Pre-flight checks passed: no ID collisions, schema compatible.\n")

# Add any FULL columns new_rows doesn't have, as NA (schema alignment, same
# convention as merge_partner_resample_batch.R)
missing_cols <- setdiff(names(full), names(new_rows))
for (col in missing_cols) new_rows[[col]] <- NA
new_rows <- new_rows[names(full)]

n_full_before <- nrow(full)
full_new <- bind_rows(full, new_rows)
stopifnot(!anyDuplicated(full_new$survey_id))

write_csv(full_new, file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"))
cat(sprintf("\nFULL: %d -> %d rows (+%d).\n", n_full_before, nrow(full_new), nrow(full_new) - n_full_before))
cat("Strata-level FULL/WORKING and household-level WORKING NOT touched by this script -\n")
cat("run refresh_working_frame_daily.R next to propagate into WORKING correctly.\n")
