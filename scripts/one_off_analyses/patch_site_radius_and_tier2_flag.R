# ==============================================================================
# Targeted patch (not a pipeline rerun) - fixes two data-quality issues in
# the delivered household-level sampling frame, flagged 2026-08-01:
#
#   1. site_radius_m is stale - uniformly 150m for every IDP row, left over
#      from the superseded single-radius method. The concept doesn't apply
#      to most of the current design at all (in-camp Tier 1 is bounded by
#      "visible camp extent," not a radius; host-community listing is
#      bounded by social recognition, not geography) - the only rows where
#      a real radius genuinely exists are the 15 flagged large in-camp
#      sites with a backup GPS point, where a real delineated extent (or
#      the 300m fallback) was already computed
#      (analysis_idp_camp_backup_points_part2.R). Fix: NA everywhere
#      except those 15 sites' rows, which get their real radius.
#
#   2. tier2_fallback_used doesn't exist yet. Can't be computed - whether
#      Tier 2 gets triggered is a field-team, real-time decision that
#      hasn't happened (fieldwork hasn't started). This is a schema fix,
#      not a data fix: add the column, FALSE for every in-camp IDP row
#      (ready for field teams to populate), NA for every other row (not
#      applicable to Non-IDP or host-community rows).
#
# Patches output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_{FULL,WORKING}.csv
# in place. Reversible via git (both files are tracked).
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(here)
})

output_dir <- here("output")
sf_dir     <- here(output_dir, "data", "data_collection")

# ---------------------------------------------------------------------------
# Real delineated radius per flagged camp - same logic as Part 2's own
# final_radius_m (if_else(delineation_failed, FALLBACK_RADIUS_M, radius_m))
# ---------------------------------------------------------------------------
FALLBACK_RADIUS_M <- 300

review <- read_csv(
  here(output_dir, "data", "supporting_analysis", "idp_camp_backup_points", "manual_visual_review.csv"),
  show_col_types = FALSE
) %>%
  mutate(final_radius_m = if_else(delineation_failed, FALLBACK_RADIUS_M, radius_m)) %>%
  select(cluster_id, final_radius_m)

cat("Real delineated radius available for", nrow(review), "flagged camps:\n")
print(review)

patch_file <- function(path) {
  cat("\n=== Patching", path, "===\n")
  df <- read_csv(path, show_col_types = FALSE)

  n_before_150 <- sum(df$site_radius_m == 150, na.rm = TRUE)

  df <- df %>%
    left_join(review, by = "cluster_id") %>%
    mutate(
      site_radius_m = final_radius_m,  # NA for every row with no match - correct, the concept doesn't apply
      tier2_fallback_used = case_when(
        idp_population_category == "idps in camp" ~ FALSE,
        TRUE ~ NA
      )
    ) %>%
    select(-final_radius_m)

  n_after_populated <- sum(!is.na(df$site_radius_m))
  n_tier2_col <- sum(!is.na(df$tier2_fallback_used))

  cat("  site_radius_m: was 150 for", n_before_150, "rows -> now populated (real radius) for", n_after_populated, "rows, NA elsewhere\n")
  cat("  tier2_fallback_used added: FALSE for", n_tier2_col, "in-camp IDP rows, NA elsewhere\n")

  write_csv(df, path, na = "NA")
  cat("  Wrote:", path, "\n")
}

patch_file(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"))
patch_file(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv"))

cat("\n=== PATCH COMPLETE ===\n")
