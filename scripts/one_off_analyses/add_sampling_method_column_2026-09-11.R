# ==============================================================================
# Adds a `sampling_method` column to all four v7 frame files (strata/household
# x FULL/WORKING), 2026-09-11. Every existing row gets "MSNA Full Design" -
# purely additive, same convention as coverage_status/exclusion_reason
# (Section 8 of the methodology doc): a new column layered on, nothing
# removed or restructured.
#
# Purpose: Jack agreed to a negotiated, non-standard data collection
# arrangement for Malam Fatori (Abadam's urban core, government enumerators,
# no georeferencing/verification possible - see CLAUDE.md for the full
# discussion). That data will NEVER be counted in state/regional/national
# aggregation or cross-LGA comparison, only reported as disclosed LGA-level
# findings. Rather than keep it in a separate file (easy to lose track of,
# easy to forget to re-merge), Jack's explicit call: keep it IN the normal
# FULL/WORKING frame so it benefits from every existing pipeline step, but
# make it structurally impossible to miss - hence a dedicated column, not
# a note in a README. "MSNA Light" rows (added by a follow-up script, not
# this one) must never silently enter any aggregation without this column
# being checked first.
#
# This script only adds the column and backfills the existing-row default -
# it does not add any "MSNA Light" rows itself (that's the Malam Fatori
# urban-draw script, run after this).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

files <- c(
  "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv",
  "NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv",
  "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv",
  "NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"
)

for (f in files) {
  path <- file.path(DC_DIR, f)
  df <- read_csv(path, show_col_types = FALSE)
  stopifnot(!"sampling_method" %in% names(df))
  df <- df %>% mutate(sampling_method = "MSNA Full Design")
  write_csv(df, path)
  cat(f, ":", nrow(df), "rows, all tagged 'MSNA Full Design'.\n")
}
cat("\nDone. No 'MSNA Light' rows added yet - that's the next script.\n")
