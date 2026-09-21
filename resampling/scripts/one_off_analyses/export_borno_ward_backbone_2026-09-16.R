# ==============================================================================
# Exports the FULL, real Borno State ward list (every ward in every LGA, per
# GRID3's national admin3 boundary product - the same source this project
# already treats as authoritative for ward-level detail everywhere else) -
# NOT scoped to the current sampling frame/WORKING universe.
#
# Why this is needed (2026-09-16, Jack's explicit hard requirement, relayed
# via the coordinating session for the Borno FACT accessibility review
# workbook): the existing master_accessibility_status_ward_level.csv (04_
# build_master_accessibility_status.py) is deliberately scoped to wards
# whose LGA has coverage_status != "not_covered" in the current sampling
# frame - real, correct for that script's own purpose (a resampling/status
# tool), but wrong for this one. Checked directly before building anything:
# Marte LGA (Borno) has ZERO partner coverage in Partnerscoverage.xlsx and
# is therefore completely ABSENT from the master status file and every
# downstream accessibility output - exactly the "silently omitted ward/LGA"
# failure Jack does not want FACT to see. This script's whole job is to be
# the one place a ward can't just vanish because nobody's been assigned
# there yet.
#
# Standalone, read-only, no pipeline state touched - safe to rerun any time.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

OUT_CSV <- "resampling/output/borno_ward_backbone_2026-09-16.csv"

w <- st_read("input_data/boundaries/nga_admin_boundaries/nga_admin3.shp", quiet = TRUE) %>%
  st_drop_geometry()

borno <- w %>%
  filter(adm1_name == "Borno") %>%
  select(adm1_name, adm2_name, adm2_pcode, adm3_name, adm3_pcode) %>%
  arrange(adm2_name, adm3_name)

stopifnot(nrow(borno) > 0, n_distinct(borno$adm2_name) == 27)  # Borno has 27 LGAs - hard sanity check, not a soft warning

write_csv(borno, OUT_CSV)
cat(sprintf("Wrote %d ward rows across %d LGAs to %s\n", nrow(borno), n_distinct(borno$adm2_name), OUT_CSV))
