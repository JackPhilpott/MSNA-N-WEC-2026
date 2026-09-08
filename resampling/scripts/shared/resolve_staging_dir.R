# Canonical resample_runs/<Partner>/<date>[_<suffix>]/ staging-directory
# builder for draw_supplementary_clusters_batch.R / draw_supplementary_
# idp_sites_batch.R's STAGING_DIR argument (2026-09-08 folder-structure
# fix). Both draw scripts already take STAGING_DIR as a plain CLI argument -
# the drift that produced FACT / FACT_DandumeFaskari / FACT_MatazuMusawaSabuwa,
# FHI360 / FHI360_Mobbar, "Save the Children" / "SavetheChildren",
# COMBINED_10PARTNER, _batch5 etc. as separate top-level folders happened
# entirely at the CALL SITE, where each day's one-off orchestration script
# hand-typed its own staging_dir string. Source this and call it instead of
# hand-typing one.
#
# 2_monitoring/cleaning/prep/prep_psu_geometries.R globs exactly
# resample_runs/*/*/new_clusters*.gpkg (non-recursive, 2 levels deep) to
# build the Coverage Map's PSU geometry layer - resolve_staging_dir() always
# returns a path exactly 2 levels under resample_runs/, so its output stays
# visible to that glob by construction. Don't nest a further subfolder (e.g.
# idp_draw/non_idp_draw) under what this returns - that reintroduces the
# depth-3 bug fixed in the 2026-09-08 resample_runs reorg, where 21 batches'
# geometry had silently stopped showing on the Coverage Map.

resolve_staging_dir <- function(partner, date = format(Sys.Date(), "%Y-%m-%d"), suffix = NULL,
                                 root = "resampling/output/resample_runs") {
  stopifnot(is.character(partner), nchar(partner) > 0, !grepl("[/\\\\]", partner))
  date_slug <- if (!is.null(suffix)) paste0(date, "_", suffix) else date
  file.path(root, partner, date_slug)
}
