# ==============================================================================
# msna_paths.R - where things live, on any machine (written 4 Oct 2026 for the
# data officer's week; same convention as msna_paths.py and as
# 2_monitoring/scripts/shared/project_root.R).
#
# The WORKSPACE is the folder holding both 1_sampling/ and 2_monitoring/.
# Resolution order:
#   1. env MSNA_WORKSPACE. It must hold both folders, otherwise STOP. Never fall
#      back silently: a sandbox run must not write into the live workspace.
#   2. walk up from this file's own folder;
#   3. walk up from the working directory;
#   4. Jack's original path, so his machine keeps working unchanged.
#
# Also:
#   msna_python()   env MSNA_PYTHON (a python.exe, or a command such as "py -3"),
#                   else the first of python3 / python / py that runs and can
#                   import openpyxl; returns that interpreter's own path.
#   msna_pkg_root() env MSNA_PKG_ROOT, else the partner package folder that sits
#                   beside "4. Data" in the same synced library.
#
# Scripts find this file with the short bootstrap block at their top, which
# sets .msna_paths_file before sourcing it.
# ==============================================================================
.MSNA_LEGACY_WORKSPACE <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026"
.msna_paths_dir <- if (exists(".msna_paths_file", envir = globalenv())) {
  dirname(normalizePath(get(".msna_paths_file", envir = globalenv()), winslash = "/", mustWork = FALSE))
} else NA_character_

msna_is_workspace <- function(d) {
  length(d) == 1 && !is.na(d) && nzchar(d) &&
    dir.exists(file.path(d, "1_sampling")) && dir.exists(file.path(d, "2_monitoring"))
}

msna_find_workspace_from <- function(start) {
  if (length(start) != 1 || is.na(start) || !nzchar(start)) return(NA_character_)
  d <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    if (msna_is_workspace(d)) return(d)
    parent <- dirname(d)
    if (identical(parent, d)) return(NA_character_)
    d <- parent
  }
}

msna_workspace <- function() {
  env <- Sys.getenv("MSNA_WORKSPACE")
  if (nzchar(env)) {
    if (!msna_is_workspace(env)) {
      stop(sprintf("MSNA_WORKSPACE='%s' does not hold both 1_sampling/ and 2_monitoring/.", env), call. = FALSE)
    }
    return(normalizePath(env, winslash = "/"))
  }
  for (start in c(.msna_paths_dir, getwd())) {
    ws <- msna_find_workspace_from(start)
    if (!is.na(ws)) return(ws)
  }
  if (msna_is_workspace(.MSNA_LEGACY_WORKSPACE)) return(.MSNA_LEGACY_WORKSPACE)
  stop("Cannot find the MSNA workspace (the folder holding 1_sampling/ and 2_monitoring/). Set MSNA_WORKSPACE.", call. = FALSE)
}

msna_sampling_dir <- function() file.path(msna_workspace(), "1_sampling")
msna_monitoring_dir <- function() file.path(msna_workspace(), "2_monitoring")

msna_pkg_root <- function() {
  env <- Sys.getenv("MSNA_PKG_ROOT")
  if (nzchar(env)) return(normalizePath(env, winslash = "/", mustWork = FALSE))
  normalizePath(file.path(dirname(dirname(msna_workspace())), "3. External coordination", "NGA MSNA 2026 Package"),
                winslash = "/", mustWork = FALSE)
}

msna_python <- function() {
  env <- trimws(Sys.getenv("MSNA_PYTHON"))
  cands <- if (nzchar(env)) list(env) else list("python3", "python", "py -3")
  probe <- shQuote("import sys, openpyxl; print(sys.executable)")
  for (cand in cands) {
    if (file.exists(cand)) {
      exe <- cand; pre <- character(0)
    } else {
      parts <- strsplit(cand, "[[:space:]]+")[[1]]
      exe <- unname(Sys.which(parts[1])); pre <- parts[-1]
    }
    if (!nzchar(exe)) next
    out <- tryCatch(suppressWarnings(system2(exe, c(pre, "-c", probe), stdout = TRUE, stderr = FALSE)),
                    error = function(e) structure(character(0), status = 1L))
    path <- trimws(utils::tail(out, 1))
    if (is.null(attr(out, "status")) && length(path) == 1 && file.exists(path)) {
      return(normalizePath(path, winslash = "/"))
    }
  }
  stop(sprintf("No Python that can import openpyxl was found (tried: %s). Set MSNA_PYTHON to a python.exe.",
               paste(unlist(cands), collapse = ", ")), call. = FALSE)
}

# ------------------------------------------------------------------ frame version (proposal #25, 9 Oct)
# Same rule as msna_paths.py: the version is read off output/data/data_collection - exactly one stage2 WORKING
# frame, with every file of its family present - else STOP (a half-done bump or a sync caught midway).
MSNA_FRAME_FAMILY <- c(
  stage2_FULL = "NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv",
  stage2_WORKING = "NGA_MSNA_2026_stage2_sampling_frame_%s_WORKING.csv",
  strata_FULL = "NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv",
  strata_WORKING = "NGA_MSNA_2026_strata_level_sampling_frame_%s_WORKING.csv",
  cluster_status = "NGA_MSNA_2026_cluster_status_%s.csv"
)

msna_data_collection_dir <- function() file.path(msna_sampling_dir(), "output", "data", "data_collection")

msna_frame_version <- function(dc = msna_data_collection_dir()) {
  f <- list.files(dc, pattern = "^NGA_MSNA_2026_stage2_sampling_frame_v[0-9]+_WORKING\\.csv$")
  found <- sort(unique(sub("^NGA_MSNA_2026_stage2_sampling_frame_(v[0-9]+)_WORKING\\.csv$", "\\1", f)))
  if (length(found) != 1) {
    stop(sprintf("frame version: expected exactly one stage2 WORKING frame in %s, found %s - a version bump is half done or still syncing; wait, or finish/roll back the bump.",
                 dc, if (length(found)) paste(found, collapse = ", ") else "none"), call. = FALSE)
  }
  missing <- sprintf(MSNA_FRAME_FAMILY, found)[!file.exists(file.path(dc, sprintf(MSNA_FRAME_FAMILY, found)))]
  if (length(missing)) stop(sprintf("frame version %s: missing %s in %s", found, paste(missing, collapse = ", "), dc), call. = FALSE)
  found
}

msna_frame_file <- function(kind, dc = msna_data_collection_dir()) {
  file.path(dc, sprintf(MSNA_FRAME_FAMILY[[kind]], msna_frame_version(dc)))
}
