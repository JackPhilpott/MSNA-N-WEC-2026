# ==============================================================================
# Adds/reconciles msna_light_settlement_name on the household-level FULL
# frame - documents a change that was applied directly to the live FULL CSV
# earlier today (2026-09-14) without a saved script, found and flagged during
# Jack's requested independent re-verification of the MSNA Light fixes ahead
# of tomorrow's collection. This script exists so the column is reproducible
# and durable, not just a one-time hand edit with no record of how to redo it.
#
# WHY THIS COLUMN EXISTS: the government-negotiated MSNA Light arrangement
# (Abadam/Nganzai/Guzamala, see CLAUDE.md "Update 2026-09-11") collects
# through government enumerators using the KoBo tool's ward dropdown.
# Guzamala and Nganzai's real settlement each equals their single GRID3 ward
# name, so this is a no-op for them - but Malam Fatori's real settlement
# straddles 3 differently-named GRID3 wards (Kessa'A/Busuna/Kudokurgo), and a
# government enumerator on the ground has no way to know which of the three
# to pick. This column gives the KoBo dropdown a single, correct, settlement-
# level name to source from instead of the raw (and for Malam Fatori,
# ambiguous) GRID3 ward name. Wiring the actual KoBo cascading-select to this
# column is a separate tool-config task, not done here - this script is the
# data side only.
#
# SCOPE: keyed off sampling_method == "MSNA Light" (not a per-LGA hardcode in
# the filter itself), but the actual settlement-name VALUES are a small,
# explicit, disclosed 3-row lookup - these are 3 specific, named, real-world
# government arrangements, not something that should be inferred generically.
# NA (literal missing, not the character string "NA") everywhere else.
#
# IDEMPOTENT: safe to rerun. Only touches msna_light_settlement_name; every
# other column is carried through unchanged. If the column and values already
# match, this is a genuine no-op (verified true the first time this script
# was run, since it's reproducing an edit that was already correctly applied
# by hand earlier the same day).
#
# WORKING is NOT touched by this script and does not need to be - it's
# rebuilt fresh from FULL on every refresh_working_frame_daily.R run via a
# generic `select(all_of(names(full_df)))` pass-through (see that script,
# ~line 311), so this column propagates into WORKING automatically the next
# time that runs. No separate WORKING-side patch needed.
#
# Usage: Rscript patch_msna_light_settlement_name_2026-09-14.R
# ==============================================================================
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tools)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- file.path("output", "data", "data_collection")
FULL_CSV <- file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv")

# The 3 disclosed MSNA Light LGAs and their real-world settlement names -
# see CLAUDE.md "Update 2026-09-11 (MSNA Light)" for the full negotiation
# context. Keyed by adm2_pcode, not adm2_name, to avoid any name-spelling
# ambiguity.
SETTLEMENT_LOOKUP <- tibble::tibble(
  adm2_pcode = c("NG008001", "NG008026", "NG008010"),
  adm2_name_expected = c("Abadam", "Nganzai", "Guzamala"),
  msna_light_settlement_name_new = c("Malam Fatori", "Gajiram", "Mairari")
)

full_df <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))

# Sanity check before touching anything - the lookup's LGA names must match
# what's actually on disk, or this is stale and needs a human look rather
# than silently mis-tagging a different LGA under an old pcode.
mismatch <- full_df %>%
  distinct(adm2_pcode, adm2_name) %>%
  inner_join(SETTLEMENT_LOOKUP, by = "adm2_pcode") %>%
  filter(adm2_name != adm2_name_expected)
if (nrow(mismatch) > 0) {
  stop("patch_msna_light_settlement_name: adm2_pcode/adm2_name mismatch vs SETTLEMENT_LOOKUP - frame may have changed, check before proceeding:\n",
       paste(capture.output(print(mismatch)), collapse = "\n"))
}

before_col <- if ("msna_light_settlement_name" %in% names(full_df)) full_df$msna_light_settlement_name else rep(NA_character_, nrow(full_df))

full_df_new <- full_df %>%
  left_join(SETTLEMENT_LOOKUP %>% select(adm2_pcode, msna_light_settlement_name_new), by = "adm2_pcode") %>%
  mutate(
    msna_light_settlement_name = if_else(
      sampling_method == "MSNA Light" & !is.na(msna_light_settlement_name_new),
      msna_light_settlement_name_new,
      NA_character_
    )
  ) %>%
  select(-msna_light_settlement_name_new)

n_changed <- sum(before_col != full_df_new$msna_light_settlement_name |
                  (is.na(before_col) != is.na(full_df_new$msna_light_settlement_name)), na.rm = TRUE)
n_changed <- n_changed + sum(is.na(before_col) != is.na(full_df_new$msna_light_settlement_name))

cat(sprintf("patch_msna_light_settlement_name: %d row(s) changed (0 expected if the earlier hand-edit was already correct).\n", n_changed))
cat("Post-patch counts by settlement:\n")
print(full_df_new %>% filter(!is.na(msna_light_settlement_name)) %>% count(adm2_name, msna_light_settlement_name))

if (n_changed > 0) {
  archive_dir <- file.path(DC_DIR, "_archive", paste0(Sys.Date(), "_pre_msna_light_settlement_name_script_patch"))
  dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(FULL_CSV, file.path(archive_dir, basename(FULL_CSV)))
  write_csv(full_df_new, FULL_CSV, na = "NA")
  cat("Changes found and written; backup taken first at", archive_dir, "\n")
} else {
  cat("No changes needed - FULL already matches this script's output exactly. Not rewriting the file.\n")
}
