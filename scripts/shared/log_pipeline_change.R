# ==============================================================================
# log_pipeline_change() - shared, append-only changelog for anything that
# materially changes household-level WORKING (2026-09-14, Jack-approved,
# Coordinator co-designed - Part 1 of the "2_monitoring sat stale on our
# fixes" two-part fix; Part 2, a recurring drift-check cron comparing
# 1_sampling's stamps against 2_monitoring's mirrors, is 2_monitoring's own
# side, already built there).
#
# Purpose: a real, human-and-cron-readable audit trail of WHEN WORKING
# changed and by how much, so a stale downstream mirror (2_monitoring, or
# any future consumer) has something concrete to diff against instead of
# discovering staleness by accident - which is exactly how tonight's Bug
# 1/2/3 fixes and the 9-cluster drop sat unreflected in 2_monitoring until
# flagged directly. Pure logging, no judgment calls: every call appends
# exactly one row, nothing is ever edited or removed (matches this
# project's standing archive-don't-overwrite convention).
#
# NOT an assert_fresh()/assert_plausible() replacement - those gate whether
# a script may proceed; this only records what happened, after the fact,
# for anything with a `to` field once it already did.
#
# Where the file lives: 1_sampling's own output tree
# (output/data/data_collection/_pipeline_changelog.csv), NOT a new
# workspace-root location - matches this project's standing folder-
# placement rule (see 1_sampling's feedback_output_folder_placement
# memory) and the established convention that downstream projects
# (2_monitoring) copy/sync FROM 1_sampling's own output, never the other
# way round. 2_monitoring's drift-check cron reads this path directly or
# via its own sync step - whichever it already uses for the frame CSVs
# sitting right next to it.
#
# Usage - call AFTER the change has already happened, with real before/
# after counts you captured yourself (this function never re-derives them,
# to stay a pure logger with no data-loading side effects of its own):
#   source("scripts/shared/log_pipeline_change.R")
#   log_pipeline_change(
#     script = "refresh_working_frame_daily.R",
#     description = "routine daily refresh",
#     old_rows = 38631, new_rows = 38577,
#     old_clusters = 2935, new_clusters = 2933
#   )
# ==============================================================================
CHANGELOG_CSV_DEFAULT <- "output/data/data_collection/_pipeline_changelog.csv"

log_pipeline_change <- function(script, description, old_rows, new_rows,
                                 old_clusters, new_clusters,
                                 changelog_path = CHANGELOG_CSV_DEFAULT) {
  row <- data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    script = script,
    description = description,
    old_rows = old_rows, new_rows = new_rows, delta_rows = new_rows - old_rows,
    old_clusters = old_clusters, new_clusters = new_clusters, delta_clusters = new_clusters - old_clusters,
    stringsAsFactors = FALSE
  )
  write_header <- !file.exists(changelog_path)
  # append=TRUE + col.names=write_header: adds the header only on the very
  # first-ever write, every subsequent call appends a bare data row -
  # write.csv() has no native append-with-conditional-header mode.
  suppressWarnings(
    write.table(row, changelog_path, append = !write_header, sep = ",",
                row.names = FALSE, col.names = write_header, qmethod = "double",
                quote = c(1, 2, 3))  # timestamp/script/description only - numeric columns unquoted
  )
  cat(sprintf("log_pipeline_change: %s - rows %d -> %d (%+d), clusters %d -> %d (%+d)\n",
              script, old_rows, new_rows, new_rows - old_rows,
              old_clusters, new_clusters, new_clusters - old_clusters))
  invisible(row)
}
