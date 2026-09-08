# Standalone utility, not part of the numbered 00-08 pipeline sequence and
# never touches pipeline state/cache/RNG — just inspects the CURRENT
# contents of output/data/data_collection/ and writes a small version
# marker (_frame_version.txt) next to them.
#
# Why this exists (2026-08-22): downstream projects (../2_monitoring/,
# ../3_analysis/) are correctly told elsewhere (see this file's own
# CLAUDE.md, "Rules for extending or rerunning this pipeline") to copy
# these outputs in as static files, never read them live. That rule
# prevents an unwanted live coupling, but on its own gives downstream no
# way to tell whether their copy has gone stale — confirmed as a real,
# not hypothetical, problem: 2_monitoring's copy was found 13 days out of
# date (missing a column) before this was built, and a design-frame
# archive path in its prep script was two real revisions behind. This
# marker is what a downstream sanity check compares its own copied marker
# against, to catch that automatically instead of relying on someone
# remembering to re-copy.
#
# ---- Run this after ANY refresh of output/data/data_collection/ --------
# (a coverage-only refresh via analysis_partner_coverage.py, a full
# pipeline rerun archived under a new _archive/YYYY-MM-DD_.../, etc.)
# It's cheap (file hashing only, no recomputation) and safe to rerun any
# number of times.

suppressPackageStartupMessages(library(tools))

DATA_COLLECTION_DIR <- "output/data/data_collection"

# The _archive/YYYY-MM-DD_.../ folder that output/data/data_collection/'s
# GEOMETRY (selected_clusters_final.rds — the household/strata CSVs here
# don't carry geometry) is currently based on. Can't be auto-detected
# reliably: not every dated _archive/ folder is a frame-lineage successor
# (some are unrelated scenario tests or one-off favours moved there only
# for folder-convention consistency — see e.g. 2026-08-20_CMR_far_north_
# scenario_test's own README). UPDATE THIS MANUALLY whenever a new
# archive folder actually supersedes the current one, same moment you'd
# update any downstream DESIGN_FRAME_PATH-style constant.
CURRENT_DESIGN_FRAME_ARCHIVE <- "2026-08-06_design_frame_post_nw_targeted_resample"

stamp_file <- function(path) {
  list(
    mtime = format(file.info(path)$mtime),
    md5 = unname(md5sum(path))
  )
}

working_csv <- file.path(DATA_COLLECTION_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv")
strata_csv <- file.path(DATA_COLLECTION_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv")
stopifnot(file.exists(working_csv), file.exists(strata_csv))

working_stamp <- stamp_file(working_csv)
strata_stamp <- stamp_file(strata_csv)

# row/cluster counts as a human-legible cross-check alongside the hash —
# an md5 alone tells you SOMETHING changed but not roughly how much.
working_lines <- length(readLines(working_csv)) - 1L
cluster_col <- which(strsplit(readLines(working_csv, n = 1), ",")[[1]] == "cluster_id")
cluster_ids <- unique(vapply(strsplit(readLines(working_csv, n = -1L)[-1], ","), `[`, character(1), cluster_col))

lines <- c(
  paste0("stamped_at: ", format(Sys.time())),
  paste0("current_design_frame_archive: ", CURRENT_DESIGN_FRAME_ARCHIVE),
  paste0("working_csv_mtime: ", working_stamp$mtime),
  paste0("working_csv_md5: ", working_stamp$md5),
  paste0("working_csv_rows: ", working_lines),
  paste0("working_csv_clusters: ", length(cluster_ids)),
  paste0("strata_working_csv_mtime: ", strata_stamp$mtime),
  paste0("strata_working_csv_md5: ", strata_stamp$md5)
)
writeLines(lines, file.path(DATA_COLLECTION_DIR, "_frame_version.txt"))

cat("Wrote", file.path(DATA_COLLECTION_DIR, "_frame_version.txt"), "\n")
cat(paste(lines, collapse = "\n"), "\n")

# ---- Archive superseded sampling-frame versions (2026-09-01) -------------
# Whenever this script's hardcoded v-number above gets bumped to a new
# version (the existing per-version-bump step - see working_csv/strata_csv
# above), older stage2/strata_level FULL+WORKING CSVs and that version's own
# build log get moved out of DATA_COLLECTION_DIR into
# _archive_superseded_versions/ - the version number is derived from
# working_csv itself, not a second constant to remember to update. Keeps
# this folder down to just the current version instead of accumulating
# every past one side by side (was v2+v3+v4 all sitting together before
# 2026-09-01). Safe to rerun: only ever moves files strictly older than the
# version named above, never touches the current one.
current_version <- as.integer(sub(".*_v([0-9]+)_WORKING\\.csv$", "\\1", working_csv))
ARCHIVE_DIR <- file.path(DATA_COLLECTION_DIR, "_archive_superseded_versions")

frame_files <- list.files(DATA_COLLECTION_DIR, pattern = "^NGA_MSNA_2026_(stage2|strata_level)_sampling_frame_v[0-9]+_(FULL|WORKING)\\.csv$")
frame_file_versions <- as.integer(sub(".*_v([0-9]+)_(FULL|WORKING)\\.csv$", "\\1", frame_files))
build_logs <- list.files(DATA_COLLECTION_DIR, pattern = "^_v[0-9]+_build_log_.*\\.txt$")
build_log_versions <- as.integer(sub("^_v([0-9]+)_build_log_.*$", "\\1", build_logs))

to_archive <- c(frame_files[frame_file_versions < current_version], build_logs[build_log_versions < current_version])
if (length(to_archive) > 0) {
  dir.create(ARCHIVE_DIR, showWarnings = FALSE, recursive = TRUE)
  invisible(file.rename(file.path(DATA_COLLECTION_DIR, to_archive), file.path(ARCHIVE_DIR, to_archive)))
  cat(sprintf("\nArchived %d file(s) older than v%d to %s:\n", length(to_archive), current_version, ARCHIVE_DIR))
  cat(paste(" -", to_archive), sep = "\n")
  cat("\n")
} else {
  cat("\nNo superseded sampling-frame versions found to archive.\n")
}

# ---- Sweep stray ad hoc "PRE_*_backup" files into _archive/ (2026-09-08) --
# The block above only ever caught files matching the clean
# ..._v<N>_{FULL,WORKING}.csv / _v<N>_build_log_*.txt patterns - it never
# caught the ad hoc safety-net copies scripts take before an IN-PLACE fix
# (e.g. NGA_MSNA_2026_stage2_sampling_frame_v5_WORKING_PRE_WARD_FILTER_FIX_
# backup_2026-09-05.csv), because those don't match either pattern. Found
# 2026-09-08: 8 such files (19-23MB each) had accumulated at top level,
# un-swept, going back to 2026-09-04 - the correct destination
# (_archive/<date>_<reason>/, same convention as this folder's own
# 2026-09-03 examples) exists and was used correctly twice, then not
# followed for every fix since. This block catches anything left behind by
# that lapse, every time this script runs (i.e. every version bump), so a
# missed archive-immediately step gets caught at the next bump rather than
# accumulating for days. The correct habit is still to archive at the moment
# of the fix (see archive_before_fix() in this same file) - this is the
# safety net behind that habit, not a replacement for it.
stray_backups <- list.files(DATA_COLLECTION_DIR, pattern = "_PRE_.*\\.(csv|txt)$")
if (length(stray_backups) > 0) {
  for (f in stray_backups) {
    date_match <- regmatches(f, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", f))
    archive_date <- if (length(date_match) > 0 && nzchar(date_match)) date_match else format(file.info(file.path(DATA_COLLECTION_DIR, f))$mtime, "%Y-%m-%d")
    reason_raw <- sub("^.*_PRE_", "", f)
    reason_raw <- sub("_backup.*$", "", reason_raw)
    reason_raw <- sub("\\.(csv|txt)$", "", reason_raw)
    reason <- tolower(gsub("[^A-Za-z0-9]+", "_", reason_raw))
    dest_dir <- file.path(DATA_COLLECTION_DIR, "_archive", paste0(archive_date, "_", reason))
    dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
    file.rename(file.path(DATA_COLLECTION_DIR, f), file.path(dest_dir, f))
    cat(sprintf("Swept stray backup into archive: %s -> %s\n", f, dest_dir))
  }
} else {
  cat("No stray PRE_*_backup files found at top level.\n")
}

# ---- archive_before_fix() - the habit this sweep is a safety net for -----
# Any script about to overwrite a WORKING/FULL file IN PLACE (a value
# correction, not a version bump - see 1_sampling/CLAUDE.md's rebuild notes
# on the distinction) should call this FIRST, not write its own ad hoc
# "_PRE_X_backup" copy at top level. Moves the CURRENT file straight into
# _archive/<date>_<reason>/, matching the convention this whole block
# exists to keep consistent, so there's nothing left for the sweep above to
# ever need to catch going forward.
archive_before_fix <- function(reason, files = c(
  file.path(DATA_COLLECTION_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"),
  file.path(DATA_COLLECTION_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv")
)) {
  reason_clean <- tolower(gsub("[^A-Za-z0-9]+", "_", reason))
  dest_dir <- file.path(DATA_COLLECTION_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", reason_clean))
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  for (f in files) {
    if (file.exists(f)) {
      file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE)
    }
  }
  cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", dest_dir))
  invisible(dest_dir)
}
