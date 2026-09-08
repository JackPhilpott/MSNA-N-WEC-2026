# ==============================================================================
# Sweeps stray "*_PRE_*_backup*" files out of partner package folders
# (../../3. External coordination/NGA MSNA 2026 Package/<PARTNER>/) into a
# dated _archive/<date>_<reason>/ subfolder each - same convention, same
# reasoning, as stamp_frame_version.R's equivalent sweep for the sampling
# frame folder (2026-09-08 rebuild). Found 1 such file across all 19 partner
# folders when checked (FACT_sampling_points_summary_PRE_2026-09-05_refresh_
# backup.xlsx) - small right now, but the pattern is the same one that
# accumulated to 8 files/19-23MB each in the sampling frame folder before
# being caught, so worth sweeping on the same cadence rather than waiting
# for it to grow.
#
# Usage: Rscript sweep_partner_package_backups.R
# ==============================================================================
PACKAGE_ROOT <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/3. External coordination/NGA MSNA 2026 Package"

partner_dirs <- list.dirs(PACKAGE_ROOT, recursive = FALSE)
partner_dirs <- partner_dirs[!grepl("_archive", basename(partner_dirs))]

n_swept <- 0L
for (pd in partner_dirs) {
  strays <- list.files(pd, pattern = "_PRE_.*\\.(xlsx|csv|kml|docx)$", full.names = FALSE)
  for (f in strays) {
    date_match <- regmatches(f, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", f))
    archive_date <- if (length(date_match) > 0 && nzchar(date_match)) date_match else format(file.info(file.path(pd, f))$mtime, "%Y-%m-%d")
    reason_raw <- sub("^.*_PRE_", "", f)
    reason_raw <- sub("_backup.*$", "", reason_raw)
    reason_raw <- sub("\\.[a-z]+$", "", reason_raw)
    reason <- tolower(gsub("[^A-Za-z0-9]+", "_", reason_raw))
    dest_dir <- file.path(pd, "_archive", paste0(archive_date, "_", reason))
    dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
    file.rename(file.path(pd, f), file.path(dest_dir, f))
    cat(sprintf("Swept: %s/%s -> %s\n", basename(pd), f, dest_dir))
    n_swept <- n_swept + 1L
  }
}
cat(sprintf("sweep_partner_package_backups(): %d file(s) swept across %d partner folder(s).\n", n_swept, length(partner_dirs)))
