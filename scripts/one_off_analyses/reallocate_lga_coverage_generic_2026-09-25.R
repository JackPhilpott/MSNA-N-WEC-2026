# ==============================================================================
# Generic frame-side partner reallocation (successor to reallocate_lga_coverage_2026-09-25.R, which
# hard-coded Chibok/Damboa). Same mechanism, driven by two small CSVs, WITH a real dry-run.
#
# Usage: Rscript reallocate_lga_coverage_generic_2026-09-25.R <moves.csv> <credited.csv> <mode> <stage_dir> [snapshot_dir]
#   moves.csv     adm1_name, adm2_name, from, to, reason, decided_by      (one row per LGA)
#   credited.csv  strata_id, credited_at_move, credited_basis             (one row per stratum of those LGAs)
#   mode          dry     read-only: computes and verifies everything in memory, writes ONLY <stage_dir>/coverage_change_log_ROWS_TO_APPEND.csv
#                 execute snapshots the 4 frame files + stamp + the 1_sampling Partnerscoverage.xlsx into <snapshot_dir> (md5-checked),
#                         THEN patches the 4 live frame files and appends the log rows. Needs Jack's direct go.
# The Excel edit itself is a separate step (the staged, diff-verified workbook is prepared next to this).
#
# Per file (strata + stage2, FULL + WORKING): partners_covering token-swap (from -> to) on the moved LGAs, coverage_reallocated_on = today
# on those rows, original_partner_covering left as it is (already stamped 2026-09-25). Nothing else may change: verified against the
# file as read, cell by cell. FULL's row roster is unchanged, so this is an in-place fix, not a version bump.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr); library(stringr); library(tibble) })
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 4)
MOVES_CSV <- args[1]; CREDITED_CSV <- args[2]; MODE <- args[3]; STAGE_DIR <- args[4]
SNAP_DIR <- if (length(args) >= 5) args[5] else NA_character_
stopifnot(MODE %in% c("dry", "execute"))
if (MODE == "execute") stopifnot(!is.na(SNAP_DIR))

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"; V <- "v13"; TODAY <- format(Sys.Date(), "%Y-%m-%d")
LOG_CSV <- file.path(DC_DIR, "coverage_change_log.csv")
EXCEL <- "input_data/boundaries/partner_coverage/Partnerscoverage.xlsx"
files <- c(strata_FULL = sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", V),
           strata_WORKING = sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_WORKING.csv", V),
           stage2_FULL = sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", V),
           stage2_WORKING = sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_WORKING.csv", V))
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

moves <- read_csv(MOVES_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
credited <- read_csv(CREDITED_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
stopifnot(all(c("adm1_name", "adm2_name", "from", "to", "reason", "decided_by") %in% names(moves)),
          all(c("strata_id", "credited_at_move", "credited_basis") %in% names(credited)))
cat(sprintf("== %s | %d LGA move(s): %s ==\n", toupper(MODE), nrow(moves), paste(sprintf("%s %s->%s", moves$adm2_name, moves$from, moves$to), collapse = "; ")))

swap_token <- function(x, from, to) {
  if (is.na(x)) return(x)
  tok <- str_trim(str_split(x, ",")[[1]]); stopifnot(from %in% tok)
  tok[tok == from] <- to; paste(unique(tok), collapse = ", ")
}
read_c <- function(p) read_csv(p, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- execute: snapshot first, verified ----
if (MODE == "execute") {
  stopifnot(!dir.exists(SNAP_DIR) || length(list.files(SNAP_DIR)) == 0)
  dir.create(SNAP_DIR, recursive = TRUE, showWarnings = FALSE)
  for (f in c(files, "_frame_version.txt", "coverage_change_log.csv")) if (file.exists(file.path(DC_DIR, f))) file.copy(file.path(DC_DIR, f), file.path(SNAP_DIR, f), copy.date = TRUE)
  file.copy(EXCEL, file.path(SNAP_DIR, "Partnerscoverage.xlsx"), copy.date = TRUE)
  for (f in c(files, "_frame_version.txt", "Partnerscoverage.xlsx")) {
    live <- if (f == "Partnerscoverage.xlsx") EXCEL else file.path(DC_DIR, f)
    stopifnot(tools::md5sum(live) == tools::md5sum(file.path(SNAP_DIR, f)))
  }
  cat("snapshot written and md5-verified:", SNAP_DIR, "\n")
}

hh_rows_by_strata <- NULL
for (name in names(files)) {
  path <- file.path(DC_DIR, files[[name]])
  cur <- read_c(path)
  stopifnot(all(c("original_partner_covering", "coverage_reallocated_on") %in% names(cur)))
  key <- paste(cur$adm1_name, cur$adm2_name, sep = "|"); mv_key <- paste(moves$adm1_name, moves$adm2_name, sep = "|")
  hit <- key %in% mv_key
  new <- cur
  before_vals <- character(0)
  for (i in which(hit)) {
    m <- moves[match(key[i], mv_key), ]
    before_vals <- c(before_vals, cur$partners_covering[i])
    new$partners_covering[i] <- swap_token(cur$partners_covering[i], m$from, m$to)
    new$coverage_reallocated_on[i] <- TODAY
  }
  stopifnot(nrow(new) == nrow(cur),
            isTRUE(all.equal(new %>% select(-partners_covering, -coverage_reallocated_on), cur %>% select(-partners_covering, -coverage_reallocated_on), check.attributes = FALSE)),
            identical(new$partners_covering[!hit], cur$partners_covering[!hit]),
            identical(new$coverage_reallocated_on[!hit], cur$coverage_reallocated_on[!hit]),
            all(new$coverage_reallocated_on[hit] == TODAY))
  for (i in seq_len(nrow(moves))) stopifnot(!any(str_detect(new$partners_covering[key == mv_key[i]], fixed(moves$from[i]))) | grepl(",", moves$to[i]))
  cat(sprintf("%-15s %7d rows | %6d rows matched | partners_covering before: {%s} -> after: {%s} | all other cells identical (checked)\n",
              name, nrow(new), sum(hit), paste(sort(unique(before_vals)), collapse = " | "), paste(sort(unique(new$partners_covering[hit])), collapse = " | ")))
  if (name == "stage2_FULL") hh_rows_by_strata <- cur[hit, ] %>% count(strata_id, name = "household_rows_reassigned_full")
  if (MODE == "execute") write_csv(new, path)
}

# ---- change-log rows ----
strata_full <- read_c(file.path(DC_DIR, files[["strata_FULL"]]))
lg <- strata_full %>% inner_join(moves, by = c("adm1_name", "adm2_name")) %>%
  transmute(date_moved = TODAY, adm1_name, adm2_name, adm2_pcode, strata_id, pop_type, from_partner = from, to_partner = to, reason,
            target_moved = as.numeric(target_sample)) %>%
  left_join(credited, by = "strata_id") %>% left_join(hh_rows_by_strata, by = "strata_id") %>%
  mutate(credited_at_move = as.numeric(credited_at_move)) %>%
  left_join(moves %>% select(adm2_name, decided_by), by = "adm2_name") %>%
  mutate(frame_version = V, source_script = "reallocate_lga_coverage_generic_2026-09-25.R")
stopifnot(nrow(lg) > 0, !anyNA(lg$credited_at_move), nrow(lg) == nrow(credited))
prev <- if (file.exists(LOG_CSV)) read_c(LOG_CSV) else NULL
start_i <- if (is.null(prev)) 0L else sum(prev$date_moved == TODAY)
lg <- lg %>% mutate(change_id = sprintf("%s-%02d", gsub("-", "", TODAY), start_i + row_number())) %>% relocate(change_id) %>%
  mutate(across(everything(), as.character))
cat(sprintf("\nlog rows to append: %d | target moved %s | credited at move %s\n", nrow(lg), sum(as.numeric(lg$target_moved)), sum(as.numeric(lg$credited_at_move))))
print(as.data.frame(lg %>% select(change_id, adm2_name, strata_id, from_partner, to_partner, target_moved, credited_at_move, household_rows_reassigned_full)))
write_csv(lg, file.path(STAGE_DIR, "coverage_change_log_ROWS_TO_APPEND.csv"))
if (MODE == "execute") { write_csv(if (is.null(prev)) lg else bind_rows(prev, lg), LOG_CSV); cat("appended to", LOG_CSV, "\n") }
cat(if (MODE == "dry") "\n(dry run) NO live frame, log or Excel file was written; only the staged log rows above.\n" else "\nDONE. Next: edit the Excel (staged copy is ready), stamp_frame_version.R, canonical sync_sampling_frame_mirrors.R, 2_monitoring copies.\n")
