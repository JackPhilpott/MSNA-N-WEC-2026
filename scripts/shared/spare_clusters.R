# ==============================================================================
# R twin of scripts/shared/spare_clusters.py (2026-10-05): the spare-cluster register and THE one "unused spare" rule.
# A spare is UNUSED while it has 0 achieved interviews; unused, it counts nowhere (targets, design capacity, MoE,
# weights); used, it is an ordinary cluster. "Achieved" is the canonical rule shared by 05, the partner packages, the
# daily workbooks and 2_monitoring's global.R:
#   interview_outcome == "completed", matched_survey_id present (not NA / "" / "NA"), submission_uuid not a confirmed
#   or contested deletion (CONFIRMED_DELETIONS_OVERLAY.csv), counted per matched_cluster_id.
# SELF-CONTAINED on purpose (base R only, sources nothing): 2_monitoring ships a byte-identical copy in
# dashboard_app/R/, which cannot reach 1_sampling. Other 1_sampling R code sources this file, never the reverse.
# ==============================================================================

SPARE_REGISTER_NAME <- "buffer_cluster_register.csv"
SPARE_REGISTER_COLUMNS <- c("cluster_id", "strata_id", "pop_type", "partner", "buffer_rank", "drawn_batch",
                            "drawn_at", "source_note")
DELETION_TERMINAL_STATUSES <- c("confirmed", "contested")

spare_register_path <- function(sampling_dir) {
  file.path(sampling_dir, "output", "data", "data_collection", SPARE_REGISTER_NAME)
}

# The register as a data frame of character columns (0 rows when there is none). Stops on a malformed or duplicated
# register, like the Python twin: a silently half-read register would count spares as ordinary clusters.
load_spare_register <- function(sampling_dir = NULL, path = spare_register_path(sampling_dir)) {
  if (!file.exists(path)) {
    return(as.data.frame(setNames(replicate(length(SPARE_REGISTER_COLUMNS), character(0), simplify = FALSE),
                                  SPARE_REGISTER_COLUMNS), stringsAsFactors = FALSE))
  }
  reg <- utils::read.csv(path, colClasses = "character", check.names = FALSE, na.strings = character(0),
                         encoding = "UTF-8", fileEncoding = "UTF-8-BOM")
  missing <- setdiff(SPARE_REGISTER_COLUMNS, names(reg))
  if (length(missing) > 0) stop(sprintf("STOP: %s lacks column(s) %s", path, paste(missing, collapse = ", ")), call. = FALSE)
  if (anyDuplicated(reg$cluster_id) > 0) stop(sprintf("STOP: %s lists a cluster_id more than once", path), call. = FALSE)
  reg
}

# uuids of confirmed or contested deletions, from CONFIRMED_DELETIONS_OVERLAY.csv's rows (columns uuid, status).
deletion_excluded_uuids <- function(overlay) {
  unique(as.character(overlay$uuid[overlay$status %in% DELETION_TERMINAL_STATUSES]))
}

# data.frame(cluster_id, n_achieved) under the canonical achieved rule. subs needs interview_outcome,
# matched_survey_id, matched_cluster_id and submission_uuid (e.g. 2_monitoring/data/real_submissions.csv).
achieved_by_cluster <- function(subs, excluded_uuids) {
  absent <- function(x) is.na(x) | x %in% c("", "NA")
  keep <- !is.na(subs$interview_outcome) & subs$interview_outcome == "completed" &
    !absent(subs$matched_survey_id) & !absent(subs$matched_cluster_id) &
    !(subs$submission_uuid %in% excluded_uuids)
  n <- table(as.character(subs$matched_cluster_id[keep]))
  data.frame(cluster_id = names(n), n_achieved = as.integer(n), stringsAsFactors = FALSE)
}

# Register clusters with 0 achieved interviews: the clusters to leave out of every count, target, capacity and MoE.
unused_spare_ids <- function(register, achieved) {
  used <- achieved$cluster_id[achieved$n_achieved > 0]
  setdiff(as.character(register$cluster_id), used)
}
