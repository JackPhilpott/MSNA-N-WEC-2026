# ==============================================================================
# Extract a partner's Non-IDP/IDP shortfall strata directly from the current
# accessibility impact workbook's Strata Level sheet - a proper, reusable
# version of the by-hand extraction used for the INTERSOS+FACT pilot
# (2026-08-30), so pulling a new partner's (e.g. IMC's) shortfall list
# doesn't mean hand-building a CSV again. Self-deriving from the live
# workbook rather than a hardcoded list, per the project's own convention.
#
# Usage: Rscript extract_partner_shortfalls.R <PartnerName> <output_dir>
# Writes <output_dir>/<partner>_shortfalls.csv (Non-IDP) and
# <output_dir>/<partner>_shortfalls_idp.csv (IDP), same schema
# draw_supplementary_clusters_pilot_2026-08-30.R / draw_supplementary_idp_
# clusters_pilot_2026-08-30.R already expect.
# ==============================================================================
suppressMessages({ library(readxl); library(dplyr); library(readr) })

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript extract_partner_shortfalls.R <PartnerName> <output_dir>")
PARTNER <- args[1]
OUT_DIR <- args[2]
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

s <- read_excel("resampling/output/NGA_MSNA_2026_accessibility_impact_workbook.xlsx", sheet = "Strata Level")
names(s) <- make.names(names(s))
s$additional_num <- suppressWarnings(as.numeric(s$Additional.clusters.needed.for.10..MoE..at.m.6.))

# Strata.ID (the workbook's "Strata ID" column) is already the FULL
# <pop_type>_<adm2_pcode> string (e.g. "non_idp_NG008006") - confirmed
# directly against the workbook 2026-08-30, not a bare pcode. An earlier
# version of this script wrongly re-prefixed it (paste0(pop_type, "_",
# Strata.ID)), producing "non_idp_non_idp_NG008006" and, worse, feeding
# that same malformed string into adm2_pcode - which silently zeroed every
# candidate hex pool downstream (adm2_pcode never matched anything) and
# was misread as "candidate pool exhausted" rather than the real bug.
# Fixed: strata_id IS Strata.ID; adm2_pcode strips the pop_type_ prefix off it.
# sub()'s `pattern` argument does not vectorize per-row (only pattern[1] is
# ever used) - stripping a per-row-varying prefix needs one fixed pattern
# per branch (via ifelse), not a pattern built from a column.
partner_rows <- s %>%
  filter(grepl(PARTNER, Partners.covering, fixed = TRUE), !is.na(additional_num), additional_num > 0) %>%
  transmute(
    strata_id = Strata.ID,
    pop_type = ifelse(Pop.type == "IDP", "idp", "non_idp"),
    adm2_pcode = ifelse(pop_type == "idp", sub("^idp_", "", Strata.ID), sub("^non_idp_", "", Strata.ID)),
    additional_clusters_needed = additional_num,
    state = State,
    lga = LGA,
    partners = PARTNER
  )

non_idp_rows <- partner_rows %>% filter(pop_type == "non_idp") %>% select(-pop_type) %>%
  mutate(pop_type = "non_idp") %>% select(strata_id, adm2_pcode, pop_type, additional_clusters_needed, state, lga, partners)
idp_rows <- partner_rows %>% filter(pop_type == "idp") %>%
  mutate(pop_type = "idp") %>% select(strata_id, adm2_pcode, pop_type, additional_clusters_needed, state, lga, partners)

write_csv(non_idp_rows, file.path(OUT_DIR, paste0(tolower(gsub("[^A-Za-z0-9]", "_", PARTNER)), "_shortfalls.csv")))
write_csv(idp_rows, file.path(OUT_DIR, paste0(tolower(gsub("[^A-Za-z0-9]", "_", PARTNER)), "_shortfalls_idp.csv")))

cat(sprintf("%s: %d Non-IDP strata (%d clusters needed), %d IDP strata (%d clusters needed)\n",
            PARTNER, nrow(non_idp_rows), sum(non_idp_rows$additional_clusters_needed),
            nrow(idp_rows), sum(idp_rows$additional_clusters_needed)))
