# ==============================================================================
# Task R6 (2026-09-22, Jack approved directly - the INTERSOS-triggered
# review). Frame-level half of "MSNA Light counts everywhere including 05/
# representativity": reinstates Guzamala, tags the 3 affected strata rows
# for the dashboard's new MSNA Light column (Coordinator's dependency), and
# retires the 72 dead Nganzai supplementary points confirmed to have zero
# real submissions (checked directly by both sessions before this ran).
#
# Scope self-derives from sampling_method == "MSNA Light" already present
# in the frame (Abadam/Nganzai/Guzamala today - not a hardcoded LGA list,
# per this project's own convention), except the Nganzai point retirement,
# which is one specific, already-identified set of 8 clusters (georeferenced
# work in an LGA the government-enumerator Light arrangement has replaced -
# not a rule that generalizes to "every Light LGA's Full Design clusters").
#
# 1. Guzamala reinstatement: coverage_status excluded -> covered,
#    exclusion_reason -> none, on BOTH the strata-level and household-level
#    FULL rows for non_idp_NG008010. Same pattern as the 2026-09-20 Mobbar
#    coverage_status reinstatement patch. Population basis: deliberately
#    NOT hand-computed here - checked directly first (both this and its
#    Light siblings have every Light cluster sitting in a ward already
#    marked Accessible in the master ward status, and Guzamala already has
#    real per-ward entries in accessible_area_lga_ward_portions.csv) - 05
#    computes N_hh_accessible fresh every run from N_hh (the frame's
#    existing whole-LGA design figure, untouched by this script) x the GIS
#    accessible fraction, the exact same mechanism Abadam/Nganzai already
#    use. That is what "based on the Light design's LGA-wide coverage"
#    resolves to here - not a bespoke formula.
# 2. Strata-level sampling_method tag (Coordinator's dependency): the
#    dashboard's new MSNA Light column reads the STRATA row's own
#    sampling_method, which currently reads "MSNA Full Design" for all 3
#    even though their household rows already say "MSNA Light". Set to
#    "MSNA Light" on non_idp_NG008001/NG008026/NG008010's strata rows only.
# 3. Nganzai retirement: non_idp_NG008026_5 + 7 supplementary clusters
#    (_supp21/22/23/25/26/28/29) - the 72 points a resampling round drew
#    when Nganzai's achieved figure wrongly read 0 (MSNA Light excluded).
#    Confirmed zero real submissions on any of them or their clusters
#    before this ran (both sessions checked independently). Removed from
#    household-level FULL entirely (not just excluded) - they were never
#    real Full Design capacity Nganzai needs; retiring them here means
#    WORKING/KML naturally drop them on the next refresh + package rebuild,
#    no separate WORKING/KML edit needed.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v12"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))
sl_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv", FRAME_VERSION))

GUZAMALA_STRATA_ID <- "non_idp_NG008010"
LIGHT_STRATA_IDS <- c("non_idp_NG008001", "non_idp_NG008026", "non_idp_NG008010")
# 2026-09-22, SPLIT FROM THIS RUN: the Coordinator's relayed cluster list
# ("_5 + supp21/22/23/25/26/28/29") does not sum to 72 rows against the live
# frame (checked directly - _5 alone is 24 rows; that set is well over 72) -
# asked for the exact, verified list rather than guess on a live frame edit.
# Nganzai retirement now runs as its own separate script once confirmed;
# this run does Guzamala reinstatement + the strata sampling_method tag only.
NGANZAI_RETIRE_CLUSTERS <- character(0)

archive_reason <- "r6_msna_light_frame_changes"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
file.copy(sl_path, file.path(archive_dir, basename(sl_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
full_sl <- read_csv(sl_path, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- Sanity checks before touching anything --------------------------------
guz_sl <- full_sl %>% filter(strata_id == GUZAMALA_STRATA_ID)
stopifnot(nrow(guz_sl) == 1, guz_sl$coverage_status == "excluded",
          guz_sl$exclusion_reason == "accessibility_loss_below_population_threshold")
cat("Guzamala strata-level FULL, before:\n")
print(as.data.frame(guz_sl %>% select(strata_id, coverage_status, exclusion_reason, N_hh, target_sample, sampling_method)))

to_retire <- full_hh %>% filter(cluster_id %in% NGANZAI_RETIRE_CLUSTERS)
cat(sprintf("\nNganzai clusters to retire THIS run: %d rows across %d clusters (0/0 expected - split out, see note above).\n", nrow(to_retire), n_distinct(to_retire$cluster_id)))
stopifnot(nrow(to_retire) == 0)

n_light_sl_before <- sum(full_sl$strata_id %in% LIGHT_STRATA_IDS & full_sl$sampling_method != "MSNA Light")
stopifnot(n_light_sl_before == 3)

# ---- 1. Guzamala reinstatement (strata + household FULL) -------------------
full_sl <- full_sl %>%
  mutate(
    coverage_status = if_else(strata_id == GUZAMALA_STRATA_ID, "covered", coverage_status),
    exclusion_reason = if_else(strata_id == GUZAMALA_STRATA_ID, "none", exclusion_reason)
  )
full_hh <- full_hh %>%
  mutate(
    coverage_status = if_else(strata_id == GUZAMALA_STRATA_ID & coverage_status == "excluded", "covered", coverage_status),
    exclusion_reason = if_else(strata_id == GUZAMALA_STRATA_ID & exclusion_reason == "accessibility_loss_below_population_threshold", "none", exclusion_reason)
  )

# ---- 2. Strata-level sampling_method tag (all 3, dashboard dependency) -----
full_sl <- full_sl %>%
  mutate(sampling_method = if_else(strata_id %in% LIGHT_STRATA_IDS, "MSNA Light", sampling_method))

# ---- 3. Retire the dead Nganzai points (none this run - see note above) ----
n_hh_before <- nrow(full_hh)
full_hh <- full_hh %>% filter(!(cluster_id %in% NGANZAI_RETIRE_CLUSTERS))
stopifnot(n_hh_before == nrow(full_hh))  # this run retires nothing - confirms the split is real, not silently doing both

# ---- Verify + write ----------------------------------------------------------
guz_sl_after <- full_sl %>% filter(strata_id == GUZAMALA_STRATA_ID)
guz_hh_after <- full_hh %>% filter(strata_id == GUZAMALA_STRATA_ID)
stopifnot(guz_sl_after$coverage_status == "covered", guz_sl_after$exclusion_reason == "none",
          all(guz_hh_after$coverage_status == "covered"), all(guz_hh_after$exclusion_reason == "none"))
n_light_sl_after <- sum(full_sl$strata_id %in% LIGHT_STRATA_IDS & full_sl$sampling_method == "MSNA Light")
stopifnot(n_light_sl_after == 3)
stopifnot(!any(full_hh$cluster_id %in% NGANZAI_RETIRE_CLUSTERS))
cat(sprintf("\nAfter: Guzamala covered/none (strata + %d household rows). %d/3 strata rows tagged MSNA Light. %d Nganzai rows retired.\n",
            nrow(guz_hh_after), n_light_sl_after, n_hh_before - nrow(full_hh)))

write_csv(full_hh, hh_path)
write_csv(full_sl, sl_path)
cat(sprintf("\nWritten. Household FULL: %d rows (%d fewer than before). Strata FULL: %d rows (unchanged count).\n",
            nrow(full_hh), n_hh_before - nrow(full_hh), nrow(full_sl)))
