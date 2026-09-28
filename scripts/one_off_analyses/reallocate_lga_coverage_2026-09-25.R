# ==============================================================================
# Partner reallocation, frame side: Chibok + Damboa (Borno) IMC -> FACT.
# Jack's decision (2026-09-25, relayed by the Coordinator msna-n-wec-2026-94):
# IMC's field teams are gone; FACT takes both LGAs (4 strata: non_idp/idp x
# NG008006, NG008007; target 4 x 102 = 408). Attribution rule "option C":
# credit, target and Still Needed follow the CURRENT LGA owner.
#
# What this does (frame only; NO submissions read):
#   1. Token-aware swap of partners_covering (from -> to) for the moved LGAs in
#      all 4 live frame files (strata + stage2, FULL + WORKING). Token-aware,
#      not an exact-string swap like patch_dikwa_reassignment_to_fact_2026-09-16.py:
#      the frame carries comma lists ("DRC, IRC, LHI"), so the "from" token is
#      replaced inside the list, order kept, duplicates dropped.
#   2. Stamps two columns on EVERY row of all 4 files (parity: WORKING is derived
#      from FULL's columns): original_partner_covering (partners_covering as it
#      was before this change) and coverage_reallocated_on (date, NA if the row
#      was never reallocated). Rows drawn after this stamp will not carry them
#      until merge_partner_resample_batch.R sets them - NA there means
#      "not stamped", not "never reallocated".
#   3. Appends one row per LGA x stratum to coverage_change_log.csv.
# Nothing is added or removed: FULL's row roster is unchanged, so this is an
# in-place fix, not a version bump (see 1_sampling/CLAUDE.md, "Sampling-frame
# versioning"). The caller must have snapshotted the 4 files first (asserted).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr); library(stringr); library(tibble) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

DC_DIR <- "output/data/data_collection"
V <- "v13"
TODAY <- "2026-09-25"
SNAP_DIR <- file.path(DC_DIR, "_archive", "2026-09-25_chibok_damboa_imc_to_fact")
LOG_CSV <- file.path(DC_DIR, "coverage_change_log.csv")

MOVES <- tribble(
  ~adm1_name, ~adm2_name, ~from, ~to,
  "Borno", "Chibok", "IMC", "FACT",
  "Borno", "Damboa", "IMC", "FACT"
)
# credited at move: IMC workbook Strata Summary (2026-09-24 13:57 daily refresh), min(achieved, target) per stratum;
# sums to 194, the figure the Coordinator confirmed from the dashboard. Read from the workbook, not from 2_monitoring/data/.
CREDITED_AT_MOVE <- c(non_idp_NG008006 = 34, idp_NG008006 = 67, non_idp_NG008007 = 23, idp_NG008007 = 70)
REASON <- "IMC field teams withdrawn; Jack reallocated Chibok and Damboa from IMC to FACT (attribution rule option C: credit/target/Still Needed follow the current LGA owner)"
DECIDED_BY <- "Jack (relayed by Coordinator msna-n-wec-2026-94, 2026-09-25)"

files <- c(
  strata_FULL    = sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", V),
  strata_WORKING = sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_WORKING.csv", V),
  stage2_FULL    = sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", V),
  stage2_WORKING = sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_WORKING.csv", V)
)
for (f in files) stopifnot(file.exists(file.path(SNAP_DIR, f)))   # snapshot present
stopifnot(!file.exists(LOG_CSV) || !any(read_csv(LOG_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))$date_moved == TODAY &
                                        read_csv(LOG_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))$adm2_name %in% MOVES$adm2_name))

swap_token <- function(x, from, to) {
  if (is.na(x)) return(x)
  tok <- str_trim(str_split(x, ",")[[1]])
  stopifnot(from %in% tok)
  tok[tok == from] <- to
  paste(unique(tok), collapse = ", ")
}

patch_file <- function(name) {
  path <- file.path(DC_DIR, files[[name]])
  old <- read_csv(file.path(SNAP_DIR, files[[name]]), show_col_types = FALSE, col_types = cols(.default = "c"))
  cur <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c"))
  stopifnot(isTRUE(all.equal(old, cur, check.attributes = FALSE)), !("original_partner_covering" %in% names(cur)))   # untouched since the snapshot
  key <- paste(cur$adm1_name, cur$adm2_name, sep = "|")
  mv_key <- paste(MOVES$adm1_name, MOVES$adm2_name, sep = "|")
  hit <- key %in% mv_key
  new <- cur %>% mutate(original_partner_covering = partners_covering, coverage_reallocated_on = NA_character_)
  for (i in which(hit)) {
    m <- MOVES[match(key[i], mv_key), ]
    new$partners_covering[i] <- swap_token(cur$partners_covering[i], m$from, m$to)
    new$coverage_reallocated_on[i] <- TODAY
  }
  # ---- verify against the snapshot ----
  stopifnot(nrow(new) == nrow(old),
            isTRUE(all.equal(new[, names(old)] %>% select(-partners_covering), old %>% select(-partners_covering), check.attributes = FALSE)),
            identical(new$original_partner_covering, old$partners_covering),
            identical(new$partners_covering[!hit], old$partners_covering[!hit]),
            all(new$partners_covering[hit] == "FACT"),
            !any(str_detect(new$partners_covering[hit], "IMC")),
            sum(!is.na(new$coverage_reallocated_on)) == sum(hit))
  write_csv(new, path)
  cat(sprintf("%-15s %7d rows | %6d reallocated | non-moved rows identical | columns +2 -> %d\n", name, nrow(new), sum(hit), ncol(new)))
  invisible(cur[hit, ])
}

cat("== patching ==\n")
moved_full_hh <- NULL
res <- lapply(names(files), function(n) { r <- patch_file(n); if (n == "stage2_FULL") moved_full_hh <<- r; r })

# ---- change log: one row per LGA x stratum ----
strata_full <- read_csv(file.path(SNAP_DIR, files[["strata_FULL"]]), show_col_types = FALSE, col_types = cols(.default = "c"))
lg <- strata_full %>% inner_join(MOVES, by = c("adm1_name", "adm2_name")) %>%
  transmute(date_moved = TODAY, adm1_name, adm2_name, adm2_pcode, strata_id, pop_type,
            from_partner = from, to_partner = to, reason = REASON,
            target_moved = as.numeric(target_sample),
            credited_at_move = unname(CREDITED_AT_MOVE[strata_id]),
            credited_basis = "IMC workbook Strata Summary 2026-09-24 13:57, min(achieved, target); total 194 confirmed by Coordinator",
            decided_by = DECIDED_BY, frame_version = V, source_script = "reallocate_lga_coverage_2026-09-25.R")
stopifnot(nrow(lg) == 4, !anyNA(lg$credited_at_move), sum(lg$target_moved) == 408, sum(lg$credited_at_move) == 194)
hh_n <- moved_full_hh %>% count(strata_id, name = "household_rows_reassigned_full")
lg <- lg %>% left_join(hh_n, by = "strata_id") %>%
  mutate(change_id = sprintf("%s-%02d", gsub("-", "", TODAY), row_number())) %>%
  relocate(change_id)
if (file.exists(LOG_CSV)) {
  prev <- read_csv(LOG_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
  lg <- bind_rows(prev, lg %>% mutate(across(everything(), as.character)))
} else lg <- lg %>% mutate(across(everything(), as.character))
write_csv(lg, LOG_CSV)
cat("\n== coverage_change_log.csv ==\n"); print(as.data.frame(read_csv(LOG_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>% select(change_id, adm2_name, strata_id, from_partner, to_partner, target_moved, credited_at_move, household_rows_reassigned_full)))
cat("\nDONE. Next: stamp_frame_version.R, then canonical sync_sampling_frame_mirrors.R. WORKING refresh deliberately NOT run.\n")
