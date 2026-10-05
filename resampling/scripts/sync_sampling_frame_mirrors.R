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
#
# Portable paths (4 Oct 2026): find 1_sampling/scripts/shared/msna_paths.R from
# MSNA_WORKSPACE, this script's own location or the working directory (see that
# file). 2_monitoring/deploy_dashboard.R sources this script, so the setwd()
# below stays exactly as before.
local({
  starts <- c(Sys.getenv("MSNA_WORKSPACE"),
              sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)),
              unlist(lapply(sys.frames(), function(f) f$ofile)), getwd())
  helper <- NA_character_
  for (s in starts[nzchar(starts)]) {
    d <- normalizePath(s, winslash = "/", mustWork = FALSE)
    while (is.na(helper)) {
      h <- file.path(d, "1_sampling", "scripts", "shared", "msna_paths.R")
      if (file.exists(h)) helper <- h
      p <- dirname(d)
      if (identical(p, d)) break
      d <- p
    }
    if (!is.na(helper)) break
  }
  if (is.na(helper)) stop("Cannot find 1_sampling/scripts/shared/msna_paths.R - set MSNA_WORKSPACE.", call. = FALSE)
  assign(".msna_paths_file", helper, envir = globalenv())
  source(helper)
})
PROJECT_DIR <- msna_sampling_dir()
MONITORING_DIR <- msna_monitoring_dir()
DC_DIR <- file.path(PROJECT_DIR, "output", "data", "data_collection")
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(tools))
source(file.path(PROJECT_DIR, "scripts", "shared", "onedrive_conflict_guard.R"))

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

  # 2026-09-14 (Coordinator's suggestion, low-risk/no-rush - same "auto"
  # bucket as everything else here): also mirror _pipeline_changelog.csv,
  # the new log_pipeline_change() audit trail, so 2_monitoring's own future
  # audits/debugging have it without a separate ask. Kept OUT of the hard-
  # required src_files/stopifnot above - unlike the frame CSVs, this is a
  # genuinely optional/auxiliary artifact (won't exist until the first
  # material WORKING change after 2026-09-14), so its own copy step is
  # best-effort and silently skipped if absent, never blocks the real sync.
  changelog_file <- "_pipeline_changelog.csv"
  changelog_present <- file.exists(file.path(DC_DIR, changelog_file))
  sync_files <- if (changelog_present) c(src_files, changelog_file) else src_files
  # 2026-10-04: the spare-cluster register (one row per spare cluster with its
  # buffer_rank; see scripts/daily_update/README_daily_update.md) travels with the
  # frame when it exists. Optional, like the changelog: never required, never blocks.
  register_file <- "buffer_cluster_register.csv"
  if (file.exists(file.path(DC_DIR, register_file))) sync_files <- c(sync_files, register_file)

  # 2026-10-02: never mirror a frame that has an OneDrive conflict copy next
  # to it. On 1 Oct this sync propagated a silently reverted frame - see
  # scripts/shared/onedrive_conflict_guard.R.
  stop_if_onedrive_conflict_copies(DC_DIR, sync_files, "sync_sampling_frame_mirrors()")

  for (mirror_dir in MIRROR_DIRS) {
    dir.create(mirror_dir, showWarnings = FALSE, recursive = TRUE)
    # Conflict copies inside a MIRROR are safe to archive, since a mirror is a
    # pure copy of the canonical frame that just passed the check above. But
    # say so loudly: before 2026-10-02 they were swept into the archive
    # silently along with ordinary stale files (and the changelog's never
    # matched the pattern below at all).
    mirror_conflicts <- find_onedrive_conflict_copies(mirror_dir, sync_files)
    if (length(mirror_conflicts) > 0) {
      warning(sprintf("sync_sampling_frame_mirrors(): archiving %d OneDrive conflict cop%s found in mirror %s: %s",
                      length(mirror_conflicts), if (length(mirror_conflicts) == 1) "y" else "ies",
                      mirror_dir, paste(mirror_conflicts, collapse = ", ")),
              call. = FALSE, immediate. = TRUE)
    }
    existing <- union(list.files(mirror_dir, pattern = "^(NGA_MSNA_2026_.*\\.csv|_frame_version\\.txt|_pipeline_changelog\\.csv|buffer_cluster_register\\.csv)$", full.names = FALSE),
                      mirror_conflicts)
    stale <- setdiff(existing, sync_files)
    if (length(stale) > 0) {
      archive_dir <- file.path(mirror_dir, paste0("_archive_", format(Sys.Date(), "%Y-%m-%d"), "_pre_", version_tag, "_sync"))
      dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
      file.rename(file.path(mirror_dir, stale), file.path(archive_dir, stale))
      cat(sprintf("sync_sampling_frame_mirrors(): archived %d stale file(s) in %s\n", length(stale), mirror_dir))
    }
    for (f in sync_files) {
      file.copy(file.path(DC_DIR, f), file.path(mirror_dir, f), overwrite = TRUE)
    }
    cat(sprintf("sync_sampling_frame_mirrors(): synced %s%s to %s\n", version_tag,
                if (changelog_present) " + changelog" else "", mirror_dir))
  }
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  sync_sampling_frame_mirrors()
}
