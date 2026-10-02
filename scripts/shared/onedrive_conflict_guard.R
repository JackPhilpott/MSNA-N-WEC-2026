# OneDrive conflict-copy guard (2026-10-02, Coordinator, Jack-approved as part
# of "fix everything related to the OneDrive incident").
#
# Why this exists: around 30 Sep/1 Oct 2026 an OneDrive sync conflict kept
# the OLDER 30 Sep 01:38 versions of 10 1_sampling files (the live v14 frame
# among them) under their real names, and renamed the correct 30 Sep 12:12
# versions to "<name>-IMPNGA-PW072DNF.<ext>". Nothing in the pipeline
# noticed. sync_sampling_frame_mirrors.R mirrored the old frame into
# 2_monitoring, and swept the mirrors' own conflict copies into an archive
# folder as if they were ordinary stale files. It took a manual repo-wide
# search a day later to find it. Every script that writes, stamps or
# propagates the canonical frame now calls stop_if_onedrive_conflict_copies()
# first, so the same situation stops the run instead.
#
# How a conflict copy is recognised: OneDrive names it
# "<stem>-<COMPUTERNAME>.<ext>", and Windows computer names are letters,
# digits and hyphens (max 15 chars). So the check is derived from each
# protected file's own name, with no machine names hardcoded. It never picks
# a winner. The un-suffixed file is NOT necessarily the newer one (on 1 Oct
# it was the older), so it stops and names the files to compare.

find_onedrive_conflict_copies <- function(dir, files) {
  present <- list.files(dir, all.files = TRUE, no.. = TRUE)
  hits <- lapply(files, function(f) {
    stem <- tools::file_path_sans_ext(f)
    ext <- tools::file_ext(f)
    cand <- present[startsWith(present, paste0(stem, "-")) & tools::file_ext(present) == ext]
    suffix <- substring(tools::file_path_sans_ext(cand), nchar(stem) + 2L)
    cand[grepl("^[A-Za-z0-9-]{1,20}$", suffix)]
  })
  unique(unlist(hits))
}

stop_if_onedrive_conflict_copies <- function(dir, files, context) {
  conflicts <- find_onedrive_conflict_copies(dir, files)
  if (length(conflicts) > 0) {
    stop(sprintf(paste0(
      "%s: REFUSING TO CONTINUE - %d OneDrive conflict cop%s next to files this step reads, in %s:\n  %s\n",
      "Each is a second version of the file with the same name minus the '-<COMPUTERNAME>' suffix. ",
      "The un-suffixed file is NOT necessarily the newer one (on 1 Oct 2026 it was the older). ",
      "Compare mtimes and row counts, keep the correct version under the main name, ",
      "move the other into an _archive folder, then re-run."),
      context, length(conflicts), if (length(conflicts) == 1) "y" else "ies", dir,
      paste(conflicts, collapse = "\n  ")), call. = FALSE)
  }
  invisible(TRUE)
}
