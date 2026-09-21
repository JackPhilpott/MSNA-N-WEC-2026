# ==============================================================================
# Combined shortfalls extraction for the 2026-09-14 comprehensive resampling
# draw - all strata with a real, positive "Additional clusters needed"
# figure in the freshly-rebuilt impact workbook, across every partner at
# once. Same source/logic as extract_partner_shortfalls.R (self-deriving
# from the live workbook, not a hardcoded list) - generalized to skip the
# per-partner PARTNER filter, since today's 9 shortfall partners (FACT,
# INTERSOS, CARE, Solidarites, NRC, IRC, Malteser, FHI 360, IMC) were
# checked directly and have fully disjoint LGA sets, so one combined draw is
# safe (same precedent as the 2026-09-08 "_batch5" 6-partner combined draw) -
# staged output gets split by adm2_pcode into per-partner folders before
# merge_partner_resample_batch.R runs, once per partner (that script tags
# every row with ONE partner name).
#
# Excludes the "Not closeable" (pool exhausted) and "Negligible gap" strata
# automatically - those never got a positive additional_clusters_needed in
# the first place, so they're naturally absent here without a separate
# filter.
# ==============================================================================
suppressMessages({ library(readxl); library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
OUT_DIR <- "resampling/output/resample_runs/_combined/2026-09-14_comprehensive"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

s <- read_excel("resampling/output/NGA_MSNA_2026_accessibility_impact_workbook.xlsx", sheet = "Strata Level")
names(s) <- make.names(names(s))
s$additional_num <- suppressWarnings(as.numeric(s$Additional.clusters.needed.for.10..MoE..at.m.6.))

shortfall_rows <- s %>%
  filter(!is.na(additional_num), additional_num > 0) %>%
  transmute(
    strata_id = Strata.ID,
    pop_type = ifelse(Pop.type == "IDP", "idp", "non_idp"),
    adm2_pcode = ifelse(pop_type == "idp", sub("^idp_", "", Strata.ID), sub("^non_idp_", "", Strata.ID)),
    additional_clusters_needed = additional_num,
    state = State,
    lga = LGA,
    partners = Partners.covering
  )

non_idp_rows <- shortfall_rows %>% filter(pop_type == "non_idp") %>%
  select(strata_id, adm2_pcode, pop_type, additional_clusters_needed, state, lga, partners)
idp_rows <- shortfall_rows %>% filter(pop_type == "idp") %>%
  select(strata_id, adm2_pcode, pop_type, additional_clusters_needed, state, lga, partners)

write_csv(non_idp_rows, file.path(OUT_DIR, "shortfalls_non_idp.csv"))
write_csv(idp_rows, file.path(OUT_DIR, "shortfalls_idp.csv"))

cat(sprintf("Combined: %d Non-IDP strata (%d clusters needed), %d IDP strata (%d clusters needed)\n",
            nrow(non_idp_rows), sum(non_idp_rows$additional_clusters_needed),
            nrow(idp_rows), sum(idp_rows$additional_clusters_needed)))
print(non_idp_rows)
print(idp_rows)
