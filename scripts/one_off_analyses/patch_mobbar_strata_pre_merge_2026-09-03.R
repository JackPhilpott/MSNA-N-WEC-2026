# ==============================================================================
# Pre-merge strata patch for the Mobbar/FHI 360 expansion, 2026-09-03.
#
# merge_partner_resample_batch.R (the standard partner-merge script, reused
# unmodified for this) only RECOMPUTES achieved_clusters/achieved_sample/
# realized_moe_pct for strata that already have a row in the strata-level
# CSVs - it does not create new rows or touch coverage_status/N_hh/n_hex/
# target_sample. Two things need doing here first:
#
#   1. non_idp_NG008023: flip coverage_status "excluded" -> "covered",
#      exclusion_reason "accessibility_loss_below_population_threshold" ->
#      "none" (real, substantial accessible population now exists - Damasak
#      + Zanna Umarti, 10,919 new households), and update N_hh/n_hex/n_pop
#      to the true combined total. target_sample/clusters_target_stage1 are
#      NOT changed - independently recomputed 2026-09-03 with the combined
#      population and confirmed identical (17 clusters/102 households; the
#      FPC-adjusted formula saturates at this population scale regardless of
#      whether the old-only or combined N_hh is used). Add a row to strata
#      WORKING too (didn't exist there at all while excluded).
#   2. idp_NG008023: brand new stratum, never existed before today (Mobbar
#      had zero IDP stratum - fully border-buffer-excluded at Stage 1).
#      Insert into both strata FULL and WORKING.
#
# achieved_clusters/achieved_sample/realized_moe_pct are left as placeholders
# (0/0/NA) here - merge_partner_resample_batch.R recomputes them immediately
# after, from the real merged household rows.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"

full_sl    <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_FULL.csv"), show_col_types = FALSE)
working_sl <- read_csv(file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"), show_col_types = FALSE)

# ---- Combined Non-IDP population, verified 2026-09-03 ----
NEW_N_HEX <- 16L
NEW_N_POP <- 65516.06
NEW_N_HH  <- 10919.34

old_row <- full_sl %>% filter(strata_id == "non_idp_NG008023")
stopifnot(nrow(old_row) == 1)
cat("Before:\n"); print(as.data.frame(old_row))

full_sl <- full_sl %>%
  mutate(
    n_pop = if_else(strata_id == "non_idp_NG008023", n_pop + NEW_N_POP, n_pop),
    N_hh  = if_else(strata_id == "non_idp_NG008023", N_hh + NEW_N_HH, N_hh),
    n_hex = if_else(strata_id == "non_idp_NG008023", n_hex + NEW_N_HEX, n_hex),
    coverage_status  = if_else(strata_id == "non_idp_NG008023", "covered", coverage_status),
    exclusion_reason = if_else(strata_id == "non_idp_NG008023", "none", exclusion_reason)
  )

new_row_check <- full_sl %>% filter(strata_id == "non_idp_NG008023")
cat("\nAfter:\n"); print(as.data.frame(new_row_check))

# ---- Add non_idp_NG008023 to strata WORKING (didn't exist there while excluded) ----
stopifnot(!("non_idp_NG008023" %in% working_sl$strata_id))
working_sl <- bind_rows(working_sl, new_row_check %>% mutate(achieved_clusters = 0, achieved_sample = 0, realized_moe_pct = NA_real_))
cat("\nAdded non_idp_NG008023 placeholder to strata WORKING (achieved figures recomputed next by the merge script).\n")

# ---- New idp_NG008023 row (both FULL and WORKING) ----
stopifnot(!("idp_NG008023" %in% full_sl$strata_id), !("idp_NG008023" %in% working_sl$strata_id))

idp_row <- tibble::tibble(
  region = "NE", adm1_pcode = "NG008", adm1_name = "Borno",
  adm2_pcode = "NG008023", adm2_name = "Mobbar", pop_type = "idp",
  strata_id = "idp_NG008023",
  n_pop = 89388, N_hh = 15913, n_hex = 10L,
  selection_type = "pps", certainty_stratum = FALSE, excluded_infeasible = FALSE,
  clusters_target_stage1 = 17, achieved_clusters = 0, m_used = 6,
  ICC = 0.06, DEFF = 1.3, expected_households_stage1 = 102, target_sample = 102,
  achieved_sample = 0, confidence_level_pct = 90, target_moe_pct = 10,
  projected_moe_pct = NA_real_, realized_moe_pct = NA_real_,
  coverage_status = "covered", exclusion_reason = "none", partners_covering = "FHI 360"
)
stopifnot(setequal(names(idp_row), names(full_sl)))
full_sl <- bind_rows(full_sl, idp_row %>% select(names(full_sl)))
working_sl <- bind_rows(working_sl, idp_row %>% select(names(working_sl)))
cat("\nAdded new idp_NG008023 row to strata FULL and WORKING:\n")
print(as.data.frame(idp_row))

# ---- Verify + write ----
stopifnot(!anyDuplicated(full_sl$strata_id), !anyDuplicated(working_sl$strata_id))
write_csv(full_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_FULL.csv"))
write_csv(working_sl, file.path(DC_DIR, "NGA_MSNA_2026_strata_level_sampling_frame_v4_WORKING.csv"))
cat("\nWritten. Strata FULL:", nrow(full_sl), "rows. Strata WORKING:", nrow(working_sl), "rows.\n")
