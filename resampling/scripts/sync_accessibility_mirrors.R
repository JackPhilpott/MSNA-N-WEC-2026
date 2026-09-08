# ==============================================================================
# Syncs the 3 copies of the master accessibility files (ward CSV, LGA CSV) -
# 1_sampling's own (source of truth) plus the two 2_monitoring mirrors
# (input_data/accessibility/ and dashboard_app/input_data/accessibility/).
#
# Written 2026-09-08: audit found NO code anywhere synced these three copies
# - they were only in sync because someone copied all three by hand during
# the 2026-09-07 incident redo. This is a pure, deterministic file copy with
# no judgment involved, so it's the "auto" bucket of this rebuild's
# freshness split - safe to run automatically via assert_fresh(mode="auto"),
# unlike the ward shapefile/IDP site frame rebuilds themselves.
#
# Also writes the shared _accessibility_version.txt stamp (previously a
# separately-maintained file that itself went stale - found still claiming
# the ward shapefile was from 09-03, three days after it was actually
# rebuilt, because writing the stamp was a separate step nobody remembered
# mid-incident. This script IS what maintains that stamp now, every time it
# runs, so it can't drift from what it's describing.
#
# Usage: Rscript sync_accessibility_mirrors.R
# (Called automatically via assert_fresh(mode="auto") wherever a mirror
# copy is read - see e.g. dashboard_app/global.R.)
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
MONITORING_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/2_monitoring"
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(tools))

SOURCE_FILES <- c(
  "resampling/output/master_accessibility_status_ward_level.csv",
  "resampling/output/master_accessibility_status_lga_level.csv"
)
MIRROR_DIRS <- c(
  file.path(MONITORING_DIR, "input_data", "accessibility"),
  file.path(MONITORING_DIR, "dashboard_app", "input_data", "accessibility")
)

sync_accessibility_mirrors <- function() {
  for (src in SOURCE_FILES) {
    stopifnot(file.exists(src))
  }
  for (mirror_dir in MIRROR_DIRS) {
    dir.create(mirror_dir, showWarnings = FALSE, recursive = TRUE)
    for (src in SOURCE_FILES) {
      dest <- file.path(mirror_dir, basename(src))
      file.copy(src, dest, overwrite = TRUE)
    }
    cat(sprintf("sync_accessibility_mirrors(): synced to %s\n", mirror_dir))
  }

  stamp_lines <- c(
    sprintf("stamped_at: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("ward_csv_source: %s", file.path(PROJECT_DIR, SOURCE_FILES[1])),
    sprintf("ward_csv_mtime: %s", format(file.info(SOURCE_FILES[1])$mtime, "%Y-%m-%d %H:%M:%S")),
    sprintf("ward_csv_md5: %s", unname(md5sum(SOURCE_FILES[1]))),
    sprintf("lga_csv_source: %s", file.path(PROJECT_DIR, SOURCE_FILES[2])),
    sprintf("lga_csv_mtime: %s", format(file.info(SOURCE_FILES[2])$mtime, "%Y-%m-%d %H:%M:%S")),
    sprintf("lga_csv_md5: %s", unname(md5sum(SOURCE_FILES[2])))
  )
  for (mirror_dir in MIRROR_DIRS) {
    writeLines(stamp_lines, file.path(mirror_dir, "_accessibility_version.txt"))
  }
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  sync_accessibility_mirrors()
}
