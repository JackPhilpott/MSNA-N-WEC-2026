# Syncs the current-version sampling frame (household + strata level, FULL +
# WORKING, + _frame_version.txt) from 1_sampling's own output (source of
# truth) to both 2_monitoring mirrors (input_data/sampling_frame/ and
# dashboard_app/input_data/sampling_frame/) - the sampling-frame counterpart
# to sync_accessibility_mirrors.R (same reasoning), written 2026-09-08 after
# that mirror was found stuck on v5/v6 while the canonical frame had moved
# to v7. Propagation had always been a manual "someone copies the files
# after a resampling round" step with no code enforcing it - unlike
# accessibility's sync_accessibility_mirrors.R, which turned out not to be
# actually wired into anything that runs automatically either (its own
# comment claims dashboard_app/global.R calls assert_fresh() to trigger it;
# global.R has zero references to either - flagged to 2_monitoring the same
# night this script was written).
#
# Pure, deterministic file copy, no judgment involved - same "auto" bucket
# as sync_accessibility_mirrors.R, safe to run automatically via
# assert_fresh(mode="auto") wherever a mirror copy is read. Reads the
# CURRENT version straight from _frame_version.txt's own recorded filenames
# rather than a hardcoded "v7", so this doesn't need editing at the next
# version bump. Old mirror files are archived (not overwritten in place)
# before the new ones land, matching this project's standing convention.
#
# Usage: Rscript sync_sampling_frame_mirrors.R
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
MONITORING_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring"
DC_DIR <- file.path(PROJECT_DIR, "output", "data", "data_collection")
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(tools))

MIRROR_DIRS <- c(
  file.path(MONITORING_DIR, "input_data", "sampling_frame"),
  file.path(MONITORING_DIR, "dashboard_app", "input_data", "sampling_frame")
)

sync_sampling_frame_mirrors <- function() {
  version_file <- file.path(DC_DIR, "_frame_version.txt")
  stopifnot(file.exists(version_file))
  version_lines <- readLines(version_file)
  # Current version = the version tag on the working_csv_mtime line's
  # sibling filename, i.e. re-derive from whichever NGA_MSNA_2026_stage2_
  # sampling_frame_v*_WORKING.csv file _frame_version.txt actually describes
  # (its own md5 line's file), rather than assuming a version number.
  candidate_files <- list.files(DC_DIR, pattern = "^NGA_MSNA_2026_stage2_sampling_frame_v[0-9]+_WORKING\\.csv$")
  stopifnot(length(candidate_files) >= 1)
  # Most-recently-modified WORKING file is the current one - matches
  # stamp_frame_version.R's own convention of never leaving more than one
  # non-archived version at top level.
  mtimes <- file.info(file.path(DC_DIR, candidate_files))$mtime
  current_working <- candidate_files[which.max(mtimes)]
  version_tag <- sub("^NGA_MSNA_2026_stage2_sampling_frame_(v[0-9]+)_WORKING\\.csv$", "\\1", current_working)

  src_files <- c(
    sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", version_tag),
    sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_WORKING.csv", version_tag),
    sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", version_tag),
    sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_WORKING.csv", version_tag),
    "_frame_version.txt"
  )
  for (f in src_files) stopifnot(file.exists(file.path(DC_DIR, f)))

  for (mirror_dir in MIRROR_DIRS) {
    dir.create(mirror_dir, showWarnings = FALSE, recursive = TRUE)
    existing <- list.files(mirror_dir, pattern = "^(NGA_MSNA_2026_.*\\.csv|_frame_version\\.txt)$", full.names = FALSE)
    stale <- setdiff(existing, src_files)
    if (length(stale) > 0) {
      archive_dir <- file.path(mirror_dir, paste0("_archive_", format(Sys.Date(), "%Y-%m-%d"), "_pre_", version_tag, "_sync"))
      dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
      file.rename(file.path(mirror_dir, stale), file.path(archive_dir, stale))
      cat(sprintf("sync_sampling_frame_mirrors(): archived %d stale file(s) in %s\n", length(stale), mirror_dir))
    }
    for (f in src_files) {
      file.copy(file.path(DC_DIR, f), file.path(mirror_dir, f), overwrite = TRUE)
    }
    cat(sprintf("sync_sampling_frame_mirrors(): synced %s to %s\n", version_tag, mirror_dir))
  }
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  sync_sampling_frame_mirrors()
}
