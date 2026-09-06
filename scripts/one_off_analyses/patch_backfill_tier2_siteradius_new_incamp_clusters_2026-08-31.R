# ==============================================================================
# Targeted patch - backfills two columns for in-camp IDP clusters created by
# this week's resampling batches (INTERSOS/IMC/FACT, 2026-08-30/31), which
# never went through patch_site_radius_and_tier2_flag.R (2026-08-01) and so
# carry that patch's *pre-fix* defaults instead of its rule:
#
#   1. site_radius_m == 150 (the stale single-radius leftover the 2026-08-01
#      patch eliminated everywhere except the 15 flagged large in-camp sites
#      with a real delineated extent) -> should be NA, since none of the
#      newly-drawn clusters are among those 15 flagged sites.
#   2. tier2_fallback_used is NA for some newly-drawn in-camp rows that
#      should carry the same default the 2026-08-01 patch set for every
#      other in-camp row: FALSE (ready for field teams to populate).
#
# Self-deriving, not a hardcoded cluster list: re-applies the exact same
# rules as the 2026-08-01 patch, scoped to rows currently sitting on the
# pre-patch default (site_radius_m == 150, or tier2_fallback_used is NA for
# an in-camp row). This is safe to rerun any time new in-camp clusters are
# merged - it will never touch a row a field team has already updated,
# because those rows are no longer sitting on the default.
#
# Patches output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_{FULL,WORKING}.csv
# in place. Archived pre-patch copy: _archive/2026-08-31_pre_tier2_siteradius_backfill_patch/
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(here)
})

output_dir <- here("output")
sf_dir     <- here(output_dir, "data", "data_collection")

patch_file <- function(path) {
  cat("\n=== Patching", path, "===\n")
  df <- read_csv(path, show_col_types = FALSE)

  n_stale_radius <- sum(df$site_radius_m == 150, na.rm = TRUE)
  n_stale_tier2  <- sum(df$idp_population_category == "idps in camp" &
                           is.na(df$tier2_fallback_used), na.rm = TRUE)
  clusters_radius <- sort(unique(df$cluster_id[which(df$site_radius_m == 150)]))
  clusters_tier2  <- sort(unique(df$cluster_id[which(
    df$idp_population_category == "idps in camp" & is.na(df$tier2_fallback_used)
  )]))

  df <- df %>%
    mutate(
      site_radius_m = if_else(site_radius_m == 150, NA_real_, site_radius_m),
      tier2_fallback_used = if_else(
        idp_population_category == "idps in camp" & is.na(tier2_fallback_used),
        FALSE,
        tier2_fallback_used
      )
    )

  cat("  site_radius_m: cleared stale 150 on", n_stale_radius, "row(s) across",
      length(clusters_radius), "cluster(s):", paste(clusters_radius, collapse = ", "), "\n")
  cat("  tier2_fallback_used: backfilled FALSE on", n_stale_tier2, "row(s) across",
      length(clusters_tier2), "cluster(s):", paste(clusters_tier2, collapse = ", "), "\n")

  write_csv(df, path, na = "NA")
  cat("  Wrote:", path, "\n")
}

patch_file(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"))
patch_file(here(sf_dir, "NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv"))

cat("\n=== PATCH COMPLETE ===\n")
