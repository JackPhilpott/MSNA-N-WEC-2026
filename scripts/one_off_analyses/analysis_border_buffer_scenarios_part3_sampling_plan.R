# Step 3: combine affected-LGA (scenario-varying) + unaffected-LGA (constant,
# reused from the live cached national hex grids) results into a full
# national per-scenario hex table, apply build_sampling_plan()'s exact
# formulas (copied verbatim, same defaults) to get target_sample/clusters
# per stratum per scenario, apply the same certainty-stratum MoE exclusion
# check, then produce LGA/state/region/national comparison tables.
suppressMessages({ library(sf); library(dplyr); library(here); library(readr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")

affected_pcodes <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/affected_adm2_pcodes.rds")
results_non_idp <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/scenario_non_idp_affected.rds")
results_idp <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/scenario_idp_affected.rds")

## ---- cached scenario-1 (current, live) national hex grids ----
hex_grid_non_idp_cached <- readRDS(here("input_data","population","sampling_frame","hex_grid_non_idp.rds")) %>%
  st_drop_geometry()
hex_grid_idp_cached <- readRDS(here("input_data","population","sampling_frame","hex_grid_idp.rds")) %>%
  st_drop_geometry()

unaffected_non_idp <- hex_grid_non_idp_cached %>% filter(!(adm2_pcode %in% affected_pcodes))
unaffected_idp <- hex_grid_idp_cached %>% filter(!(adm2_pcode %in% affected_pcodes))
cat("Unaffected-LGA hexes (constant across all scenarios): non_idp =", nrow(unaffected_non_idp), " idp =", nrow(unaffected_idp), "\n")

## sanity check: affected-LGA S1 recompute should match cached S1 for the same LGAs (validates the whole re-derivation pipeline)
affected_non_idp_S1 <- results_non_idp[["S1_current"]] %>% select(-scenario)
cached_affected_non_idp_S1 <- hex_grid_non_idp_cached %>% filter(adm2_pcode %in% affected_pcodes)
cat("\nSANITY CHECK - S1 recompute vs live cache, affected LGAs, Non-IDP:\n")
cat("  Recomputed total N_hh:", sum(affected_non_idp_S1$pop_hh), " | Cached (live) total N_hh:", sum(cached_affected_non_idp_S1$pop_hh), "\n")
cat("  Recomputed hex count:", nrow(affected_non_idp_S1), " | Cached hex count:", nrow(cached_affected_non_idp_S1), "\n")

affected_idp_S1 <- results_idp[["S1_current"]] %>% select(-scenario)
cached_affected_idp_S1 <- hex_grid_idp_cached %>% filter(adm2_pcode %in% affected_pcodes)
cat("SANITY CHECK - S1 recompute vs live cache, affected LGAs, IDP:\n")
cat("  Recomputed total N_hh:", sum(affected_idp_S1$pop_hh), " | Cached (live) total N_hh:", sum(cached_affected_idp_S1$pop_hh), "\n")
cat("  Recomputed hex count:", nrow(affected_idp_S1), " | Cached hex count:", nrow(cached_affected_idp_S1), "\n")

## ---- build_sampling_plan formula (copied verbatim from 01_sampling_pipeline_main.R) ----
build_sampling_plan_summary <- function(hex_grid, Z = qnorm(0.95), p = 0.5, e = 0.10, m = 6, ICC = 0.06, buffer = 0.10, certainty_threshold = NULL) {
  deff <- 1 + (m - 1) * ICC
  n0 <- Z^2 * p * (1 - p) / e^2
  ndeff <- n0 * deff
  if (is.null(certainty_threshold)) certainty_threshold <- m * 6
  round_up_multiple <- function(x, multiple) ceiling(x / multiple) * multiple

  hex_grid %>%
    group_by(pop_type, adm2_pcode, adm2_name, adm1_pcode, adm1_name, region) %>%
    summarise(n_pop = sum(pop, na.rm = TRUE), N_hh = sum(pop_hh, na.rm = TRUE), n_hex = n(), .groups = "drop") %>%
    mutate(
      hh_sample_raw = N_hh * ndeff / (N_hh + ndeff - 1),
      hh_sample = round_up_multiple(hh_sample_raw, m),
      hh_sample_buffer = round_up_multiple(hh_sample * (1 + buffer), m),
      clusters_raw = ceiling(hh_sample_buffer / m),
      certainty_stratum = N_hh < certainty_threshold,
      selection_type = ifelse(certainty_stratum, "certainty", "pps"),
      clusters = case_when(certainty_stratum ~ 1, TRUE ~ pmin(clusters_raw, ceiling(N_hh / m))),
      # For certainty strata, every eligible hex is its own cluster (achieved_clusters = n_hex),
      # not the "clusters=1" placeholder used only in the PSU-probability calc.
      clusters_target_stage1 = case_when(certainty_stratum ~ n_hex, TRUE ~ clusters),
      target_sample = clusters_target_stage1 * m,
      m_used = m
    )
}

realized_moe <- function(achieved_sample, N_hh, m, ICC = 0.06, Z = qnorm(0.95), p = 0.5) {
  deff <- 1 + (m - 1) * ICC
  ndeff <- achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
  n0 <- ndeff / deff
  sqrt(Z^2 * p * (1 - p) / n0)
}

## ---- assemble national hex table per scenario, run the sampling plan + certainty check ----
scenario_names <- c("S1_current", "S2_5km_all", "S3_no_buffer")
strata_by_scenario <- list()

for (scen in scenario_names) {
  non_idp_full <- bind_rows(unaffected_non_idp, results_non_idp[[scen]] %>% select(-scenario)) %>% mutate(pop_type = "non_idp")
  idp_full <- bind_rows(unaffected_idp, results_idp[[scen]] %>% select(-scenario)) %>% mutate(pop_type = "idp")

  non_idp_plan <- build_sampling_plan_summary(non_idp_full)
  idp_plan <- build_sampling_plan_summary(idp_full)

  idp_infeasible <- idp_plan %>%
    filter(certainty_stratum, 100 * realized_moe(n_hex * m_used, N_hh, m_used) > 10) %>%
    distinct(adm2_pcode)

  idp_plan <- idp_plan %>%
    mutate(
      excluded_infeasible = certainty_stratum & adm2_pcode %in% idp_infeasible$adm2_pcode,
      target_sample = if_else(excluded_infeasible, 0, target_sample),
      clusters_target_stage1 = if_else(excluded_infeasible, 0, clusters_target_stage1)
    )
  non_idp_plan <- non_idp_plan %>% mutate(excluded_infeasible = FALSE)  # no Non-IDP certainty strata exist currently

  strata_by_scenario[[scen]] <- bind_rows(non_idp_plan, idp_plan) %>% mutate(scenario = scen)
}

all_strata <- bind_rows(strata_by_scenario)
write_csv(all_strata, "C:/Users/JACKPH~1/AppData/Local/Temp/claude/border_scenarios_strata_level.csv")

cat("\n\n=== NATIONAL TOTALS BY SCENARIO AND POP_TYPE ===\n")
national_totals <- all_strata %>% group_by(scenario, pop_type) %>%
  summarise(N_hh = sum(N_hh), target_sample = sum(target_sample), n_hex_selected = sum(clusters_target_stage1), n_strata_excluded = sum(excluded_infeasible), .groups = "drop")
print(as.data.frame(national_totals))

cat("\nSaved:", "C:/Users/JACKPH~1/AppData/Local/Temp/claude/border_scenarios_strata_level.csv\n")
