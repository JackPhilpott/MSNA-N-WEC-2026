# ==============================================================================
# Exports the FULL, real national ward list (every ward in every LGA) for the
# 2026-09-16 ward-completeness fix (Jack, direct, explicit go-ahead - see
# 1_sampling/CLAUDE.md). Used to expand all 19 partners' accessibility
# reports to a complete ward list per LGA, and to rebuild the Borno/FACT
# review workbook on the corrected source (see the "wrong source" note
# below).
#
# CORRECTED after a real bug caught mid-build: the first version of this
# script (and the earlier Borno-only export_borno_ward_backbone_2026-09-16.R)
# read input_data/boundaries/nga_admin_boundaries/nga_admin3.shp, assuming it
# was the GRID3 national product because of its generic filename. Checked
# directly before trusting it further: that file only covers 3 states
# (Borno/Adamawa/Yobe, 714 rows total) - it's actually the OCHA/COD NE-only
# admin3 product this project already uses for the separate "Ward (OCHA/COD)"
# cross-reference column, not GRID3's national one. Confirmed via a direct
# name check against known-correct current ward names (Magumeri's "Kareram"/
# "Hoyo Chingua" - the exact wards INTERSOS was drawn into earlier tonight):
# the household frame's own adm3_name matches input_data/boundaries/GRID3_
# NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp's wardname
# EXACTLY ("Kareram"/"Hoyo Chingua"), not nga_admin3.shp's version
# ("Kararam"/"Hoyo Chingowa" - same wards, different spelling convention).
# Total ward COUNT happened to match for Borno (310 in both) so this wasn't
# caught by a row-count sanity check alone - only a direct name comparison
# surfaced it. The already-built Borno/FACT workbook used the wrong source
# and needs rebuilding on this corrected one before anything is sent.
#
# GRID3's own embedded lganame occasionally disagrees with this project's
# OCHA/COD-sourced LGA spelling at punctuation level (confirmed: "Askira Uba"
# vs "Askira/Uba", "Kala Balge" vs "Kala/Balge" - the same known GRID3-vs-
# OCHA/COD LGA-label discrepancy already documented project-wide, e.g.
# build_partner_dc_packages.py's LGA_WARD_SOURCE_NOTE). Reconciled below by
# matching on a normalised (state, lga) key (strip "/", "-", extra spaces -
# same normalisation pattern already used throughout this project, e.g.
# analysis_partner_coverage.py's norm()) against the CANONICAL LGA list from
# the current sampling frame's own strata-level CSV, so every ward row in
# the output carries the project's own authoritative LGA spelling, not
# GRID3's raw embedded one - consistent with "LGA is always OCHA/COD-sourced"
# throughout this project. GRID3's wardname is used as-is for the ward name
# (the reliable match key, matching adm3_name everywhere else).
#
# Standalone, read-only, no pipeline state touched - safe to rerun any time.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr); library(stringr) })

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

GRID3_SHP <- "input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp"
STRATA_CSV <- "output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v9_FULL.csv"
STAGE2_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v9_FULL.csv"
OUT_CSV <- "resampling/output/national_ward_backbone_2026-09-16.csv"

norm_key <- function(s) {
  s <- tolower(trimws(s))
  s <- str_replace_all(s, "[/\\-]", " ")
  s <- str_squish(s)
  s
}

# Canonical (State, LGA) list - authoritative spelling, from the current
# sampling frame (OCHA/COD-sourced LGA names throughout this project).
strata <- read_csv(STRATA_CSV, show_col_types = FALSE)
canonical_lgas <- strata %>%
  distinct(adm1_name, adm2_name, adm2_pcode) %>%
  mutate(key = paste(norm_key(adm1_name), norm_key(adm2_name)))
stopifnot(!any(duplicated(canonical_lgas$key)))  # one canonical LGA per normalised key, or the join below is ambiguous

# GRID3's own embedded lganame vs this project's canonical (OCHA/COD-derived)
# adm2_name spelling, for the 12 real focus-state LGAs where the two genuinely
# don't share a common normalised form (letter transpositions/insertions, not
# just punctuation - e.g. "Makarfi" vs "Markafi", "Wamakko" vs "Wamako") -
# found by checking every canonical LGA that had zero GRID3 match after the
# plain normalised join below, cross-referenced by hand against each state's
# real GRID3 LGA list. Same reconciliation PATTERN this project already uses
# elsewhere for the identical class of problem (see analysis_partner_
# coverage.py's/refresh_partner_workbooks_daily.py's own PROPOSED_
# RECONCILIATION dicts, a different source-pair but the same underlying
# GRID3-vs-OCHA/COD naming drift).
GRID3_LGA_RECONCILIATION <- tribble(
  ~statename,  ~lganame,               ~adm1_name, ~adm2_name,
  "Kaduna",    "Makarfi",              "Kaduna",   "Markafi",
  "Kaduna",    "Zangon Kataf",         "Kaduna",   "Zango-Kataf",
  "Kano",      "Garun Malam",          "Kano",     "Garum Mallam",
  "Kano",      "Nassarawa",            "Kano",     "Nasarawa",
  "Kogi",      "Olamaboro",            "Kogi",     "Olamabolo",
  "Nasarawa",  "Nasarawa Egon",        "Nasarawa", "Nasarawa-Eggon",
  "Niger",     "Munya",                "Niger",    "Muya",
  "Plateau",   "Barkin Ladi",          "Plateau",  "Barikin Ladi",
  "Sokoto",    "Wamakko",              "Sokoto",   "Wamako",
  "Yobe",      "Tarmuwa",              "Yobe",     "Tarmua",
  "Zamfara",   "Birnin Magaji-Kiyaw",  "Zamfara",  "Birnin Magaji",
  "Kebbi",     "Bagudu",               "Kebbi",    "Bagudo",
) %>% mutate(recon_key = paste(norm_key(statename), norm_key(lganame)))

w <- st_read(GRID3_SHP, quiet = TRUE) %>%
  st_drop_geometry() %>%
  as_tibble() %>%
  mutate(key = paste(norm_key(statename), norm_key(lganame)),
         recon_key = key) %>%
  left_join(GRID3_LGA_RECONCILIATION %>% select(recon_key, recon_adm1 = adm1_name, recon_adm2 = adm2_name), by = "recon_key") %>%
  mutate(key = if_else(!is.na(recon_adm2), paste(norm_key(recon_adm1), norm_key(recon_adm2)), key))

grid3_matched <- w %>%
  inner_join(canonical_lgas, by = "key") %>%
  transmute(adm1_name, adm2_name, adm2_pcode, adm3_name = wardname) %>%
  distinct()

unmatched_grid3_lgas <- w %>% filter(!key %in% canonical_lgas$key) %>% distinct(statename, lganame)
unmatched_canonical_lgas <- canonical_lgas %>% filter(!key %in% w$key) %>% distinct(adm1_name, adm2_name)

cat(sprintf("GRID3-only: matched %d ward rows across %d LGAs / %d states.\n",
            nrow(grid3_matched), n_distinct(paste(grid3_matched$adm1_name, grid3_matched$adm2_name)), n_distinct(grid3_matched$adm1_name)))
cat(sprintf("\n%d GRID3 (state, lga) combo(s) did not match any canonical sampling-frame LGA (likely outside this project's 14 focus states - expected, not an error):\n", nrow(unmatched_grid3_lgas)))
print(unmatched_grid3_lgas, n = 50)
cat(sprintf("\n%d canonical sampling-frame LGA(s) had NO matching GRID3 (state, lga) at all (worth checking, not expected):\n", nrow(unmatched_canonical_lgas)))
print(unmatched_canonical_lgas, n = 50)

# ---------------------------------------------------------------------------
# UNION with the sampling frame's own ground truth (2026-09-16, real bug
# caught by Jack checking INTERSOS/Maru directly - see this script's own
# CLAUDE.md writeup for the full story). GRID3's ward polygons don't nest
# cleanly inside OCHA/COD LGA lines - a real, already-documented, project-
# wide fact (see build_partner_dc_packages.py's LGA_WARD_SOURCE_NOTE) - so a
# ward can genuinely have real drawn households whose adm2_name (OCHA/COD,
# authoritative) differs from whichever single LGA GRID3's own attribute
# table happens to claim that ward's polygon belongs to. The GRID3-only
# table above only ever lists a ward under GRID3's own claimed LGA - for a
# household point that's actually Maru (per OCHA/COD, correctly) but sits in
# a ward GRID3 attributes to neighbouring Bungudu, that ward silently never
# appeared under Maru at all. Checked nationally before fixing: 887 distinct
# (state, lga, ward) combinations have real sampling frame rows but were
# entirely missing from the GRID3-only backbone, across 284 LGAs - this was
# not a Maru-specific glitch.
#
# Fix: for any ward that ALREADY has real frame rows, the frame's own
# (adm1_name, adm2_name, adm3_name) is authoritative ground truth - trust it
# over GRID3's raw claim, exactly like every other ward-level fact in this
# project. GRID3's own claim is used ONLY as the fallback for wards that
# have genuinely never had a single cluster drawn (no frame ground truth to
# consult at all) - the "we don't even know this ward exists yet" case this
# whole ward-completeness effort exists to surface. The two sets are UNIONed
# (not one replacing the other), so a straddling ward correctly ends up
# listed under BOTH its GRID3-claimed LGA and its frame-confirmed LGA(s) -
# exactly what "Ward spans multiple LGAs" is designed to show.
frame <- read_csv(STAGE2_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
frame_wards <- frame %>%
  filter(!is.na(adm3_name), adm3_name != "NA", adm3_name != "") %>%
  distinct(adm1_name, adm2_name, adm3_name) %>%
  inner_join(canonical_lgas %>% select(adm1_name, adm2_name, adm2_pcode), by = c("adm1_name", "adm2_name"))

n_frame_only <- frame_wards %>% anti_join(grid3_matched, by = c("adm1_name", "adm2_name", "adm3_name")) %>% nrow()
cat(sprintf("\nFrame ground truth adds %d (state, lga, ward) combination(s) not present under that LGA in the GRID3-only table (straddling wards GRID3 attributes elsewhere, now correctly also listed under their real frame LGA).\n", n_frame_only))

matched <- bind_rows(grid3_matched, frame_wards) %>%
  distinct(adm1_name, adm2_name, adm2_pcode, adm3_name) %>%
  arrange(adm1_name, adm2_name, adm3_name)

cat(sprintf("\nFinal (GRID3 UNION frame ground truth): %d ward rows across %d LGAs / %d states.\n",
            nrow(matched), n_distinct(paste(matched$adm1_name, matched$adm2_name)), n_distinct(matched$adm1_name)))

write_csv(matched, OUT_CSV)
cat(sprintf("\nWrote %s\n", OUT_CSV))
