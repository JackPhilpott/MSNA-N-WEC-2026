# ==============================================================================
# Validation harness for scripts/shared/realized_weights.R (piece one of
# Round 1's weighting build - see that file's own header for the mechanism
# and its documented assumptions). READ-ONLY on every live/canonical file:
# writes only into resampling/output/realized_weights_validation_2026-09-27/.
# No merge, no live frame write.
#
# STRUCTURAL FINDING, discovered running this validation, reported not
# worked around: psu_probability/ssu_probability/base_weight are NOT
# present anywhere in the live FULL/WORKING frame (58 columns, checked
# directly), nor in output/gis/selected_clusters_v13_current.rds (the
# cluster-selection output, 23 columns, also checked directly). They exist
# ONLY transiently, on a freshly-staged, not-yet-merged supplementary draw's
# new_households.csv (finalize_households() computes them correctly there,
# confirmed on tonight's own D0 batches) - and merge_partner_resample_
# batch.R then explicitly drops them as "non-schema columns" before merging
# (its own log tonight: "Dropping 5 non-schema column(s)... psu_probability,
# ssu_probability, base_weight..."), because FULL's OWN established schema
# never had them to merge INTO. This is not something that broke tonight -
# every column-presence check below is against the LIVE frame as it already
# stood before any of tonight's draws, and the original cluster-selection
# .rds is a design-time artifact untouched by tonight's work. So: real
# psu_probability is NOT retrievable for any of the ~8,022 already-live
# clusters (original design + every supplementary draw ever merged) without
# a separate re-derivation from the underlying stratum-level MOS/total_MOS
# - out of tonight's scope, a genuine prerequisite this validation surfaces
# for tomorrow's full weighting build, not something this script invents an
# answer for. See this file's own printed section for the detail; nothing
# below pretends the gap doesn't exist.
#
# GIVEN THAT, what this validation actually proves, honestly:
#   1/3. Mechanism correctness (byte-identical-elsewhere, idempotency) -
#        proven on SYNTHETIC test vectors (a pure function is normal and
#        sufficient to unit-test this way) AND, separately, on REAL rows
#        from tonight's own staged draws (real psu_probability, just not
#        yet a topped-up case - see the two-part check below).
#   2.   A REAL worked example - real achieved/target/households_in_cluster
#        from an actual over-collected cluster tonight. The ssu_probability
#        change and the base_weight RATIO (new/old) are shown fully real
#        and exact, because base_weight is proportional to 1/ssu_probability
#        - that ratio needs no psu_probability at all, it cancels out
#        algebraically. The ABSOLUTE base_weight is shown too, clearly
#        labeled as using an ILLUSTRATIVE psu_probability (not a real one),
#        since a real one isn't retrievable for this cluster - never
#        blended with the real numbers without that label.
#   4.   Assumptions are documented in realized_weights.R's header; this
#        script's own header above is the newly-found addition to them.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr) })
source("scripts/shared/realized_weights.R")

OUT <- "resampling/output/realized_weights_validation_2026-09-27"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
lines <- character(0)
say <- function(...) { m <- sprintf(...); cat(m, "\n"); lines <<- c(lines, m) }

say("==== Realized-weight validation - %s ====", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
say("Read-only. Nothing merged, nothing written outside %s.\n", OUT)

full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv", show_col_types = FALSE)
subs <- read_csv("../2_monitoring/data/real_submissions.csv", show_col_types = FALSE)
del  <- read_csv("../2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv", show_col_types = FALSE)

say("---- STRUCTURAL CHECK: is psu_probability actually in the live frame? ----")
has_psu <- "psu_probability" %in% names(full)
say("psu_probability in live FULL frame's %d columns: %s", ncol(full), has_psu)
sel <- readRDS("output/gis/selected_clusters_v13_current.rds")
say("psu_probability in output/gis/selected_clusters_v13_current.rds's %d columns: %s", ncol(sel), "psu_probability" %in% names(sel))
say("=> CONFIRMED: no live, already-merged source of psu_probability exists for any of the frame's %d clusters. This predates tonight (checked the frame as it already stood). Full explanation in this script's own header.\n", n_distinct(full$cluster_id))

achieved_by_cluster <- compute_achieved_by_cluster(subs, del)
say("---- CHECK 4 data point: topped-up clusters on real achieved-vs-target (using columns FULL DOES have) ----")
real_candidates <- full %>% distinct(cluster_id, pop_type, target_households, households_in_cluster) %>%
  left_join(achieved_by_cluster, by = "cluster_id") %>% mutate(n_achieved = coalesce(n_achieved, 0L)) %>%
  filter(n_achieved > target_households)
n_capped <- sum(real_candidates$n_achieved > real_candidates$households_in_cluster, na.rm = TRUE)
say("%d real clusters are topped up tonight (achieved > target_households); %d of those would also hit the pmin(1,...) cap (achieved > households_in_cluster too).\n",
    nrow(real_candidates), n_capped)

say("---- CHECK 1 & 3 (mechanism correctness), part A: SYNTHETIC test vectors ----")
syn <- tibble(
  cluster_id = c("A_not_topped", "B_topped_normal", "C_topped_capped", "D_zero_achieved"),
  target_households = c(6, 6, 6, 6),
  households_in_cluster = c(200, 200, 10, 200),
  psu_probability = c(0.10, 0.10, 0.10, 0.10),
  ssu_probability = pmin(1, c(6, 6, 6, 6) / c(200, 200, 10, 200)),
  n_achieved = c(4, 24, 24, NA)  # A: under target (not topped up); B: over target, under households_in_cluster; C: over BOTH (cap binds); D: no achieved rows at all (NA -> treated as 0)
) %>% mutate(base_weight = 1 / (psu_probability * ssu_probability))
syn_ab <- syn %>% rename(n_achieved_input = n_achieved) %>%
  left_join(tibble(cluster_id = syn$cluster_id, n_achieved = syn$n_achieved), by = "cluster_id")
result_syn <- apply_realized_weights(syn %>% select(-n_achieved), tibble(cluster_id = syn$cluster_id, n_achieved = syn$n_achieved) %>% filter(!is.na(n_achieved)))
say("synthetic rows in: %d, out: %d (must match, no rows added/dropped): %s", nrow(syn), nrow(result_syn$frame), nrow(syn) == nrow(result_syn$frame))
chk_a <- result_syn$frame$ssu_probability[result_syn$frame$cluster_id == "A_not_topped"] == syn$ssu_probability[syn$cluster_id == "A_not_topped"]
chk_d <- result_syn$frame$ssu_probability[result_syn$frame$cluster_id == "D_zero_achieved"] == syn$ssu_probability[syn$cluster_id == "D_zero_achieved"]
say("A (achieved 4 < target 6): untouched, ssu_probability unchanged: %s", chk_a)
say("D (no achieved row at all -> treated as 0, well under target): untouched: %s", chk_d)
b_new <- result_syn$frame$ssu_probability[result_syn$frame$cluster_id == "B_topped_normal"]
say("B (achieved 24 > target 6, households_in_cluster 200): new ssu_probability = 24/200 = %.4f (expected 0.1200): %s", b_new, isTRUE(all.equal(b_new, 0.12)))
c_new <- result_syn$frame$ssu_probability[result_syn$frame$cluster_id == "C_topped_capped"]
say("C (achieved 24 > households_in_cluster 10): new ssu_probability CAPPED at 1.0 (raw would be 2.4): %s", isTRUE(all.equal(c_new, 1.0)))
c_capped_flag <- result_syn$audit$cap_bound[result_syn$audit$cluster_id == "C_topped_capped"]
say("C is flagged cap_bound = TRUE in the audit table (not silently clamped): %s\n", isTRUE(c_capped_flag))

result_syn2 <- apply_realized_weights(result_syn$frame, tibble(cluster_id = syn$cluster_id, n_achieved = syn$n_achieved) %>% filter(!is.na(n_achieved)))
frame_idempotent <- identical(result_syn$frame, result_syn2$frame)
new_vals_idempotent <- identical(result_syn$audit$new_ssu_probability, result_syn2$audit$new_ssu_probability) &&
                        identical(result_syn$audit$new_base_weight, result_syn2$audit$new_base_weight)
say("IDEMPOTENCY (synthetic): applying again to its own output is a no-op on the PRODUCTION output: frame identical = %s, audit's new_ssu_probability/new_base_weight identical = %s",
    frame_idempotent, new_vals_idempotent)
say("  (audit's old_ssu_probability/old_base_weight columns are DELIBERATELY relative-to-input, not idempotent by design - run 2's 'old' correctly equals run 1's 'new', confirmed: %s. That is the audit doing its job, not a flaw - only new_ssu_probability/new_base_weight ever get written to the frame, and those are proven identical above.)",
    identical(result_syn$audit$new_ssu_probability, result_syn2$audit$old_ssu_probability))
other_cols_syn <- setdiff(names(syn %>% select(-n_achieved)), c("ssu_probability", "base_weight"))
byte_ident_syn <- all(sapply(other_cols_syn, function(cn) identical((syn %>% select(-n_achieved))[[cn]], result_syn$frame[[cn]])))
say("Every column other than ssu_probability/base_weight is untouched (synthetic): %s\n", byte_ident_syn)

say("---- CHECK 1 & 3 part B: REAL rows, using tonight's own staged draws (real psu_probability, real target/households) ----")
staged <- read_csv("resampling/output/resample_runs/FACT/2026-09-27_D0_buffer/new_households.csv", show_col_types = FALSE) %>%
  select(cluster_id, target_households, households_in_cluster, psu_probability, ssu_probability, base_weight) %>% distinct()
say("Loaded %d real (cluster_id, target, households_in_cluster, psu/ssu_probability, base_weight) rows from tonight's own FACT draw (real design values, not synthetic).", nrow(staged))
say("None of these clusters are topped up yet (drawn tonight, 0 real interviews so far) - expected outcome is a pure no-op; this proves apply_realized_weights() leaves REAL, non-synthetic design rows exactly alone when nothing qualifies, on top of the synthetic A/D cases above.")
result_staged <- apply_realized_weights(staged, achieved_by_cluster)
byte_ident_staged <- all(sapply(names(staged), function(cn) identical(staged[[cn]], result_staged$frame[[cn]])))
say("Real staged rows completely untouched (0 of %d clusters topped up, all columns identical): %s\n", nrow(staged), byte_ident_staged)

say("---- CHECK 2: worked example on a REAL over-collected cluster ----")
clean <- real_candidates %>% filter(n_achieved <= households_in_cluster) %>% arrange(desc(n_achieved - target_households)) %>% slice(1)
old_ssu <- pmin(1, clean$target_households / clean$households_in_cluster)
new_ssu <- pmin(1, clean$n_achieved / clean$households_in_cluster)
say("Cluster %s (%s): target_households = %d, households_in_cluster = %s, REAL achieved interviews = %d (all real numbers, from live FULL + real_submissions.csv).",
    clean$cluster_id, clean$pop_type, clean$target_households, format(clean$households_in_cluster), clean$n_achieved)
say("  DESIGN ssu_probability = min(1, %d/%s) = %.6f", clean$target_households, format(clean$households_in_cluster), old_ssu)
say("  REAL   ssu_probability = min(1, %d/%s) = %.6f  (%.1fx the design value)", clean$n_achieved, format(clean$households_in_cluster), new_ssu, new_ssu / old_ssu)
say("  base_weight RATIO (new/old) = old_ssu_probability/new_ssu_probability = %.6f/%.6f = %.4f - EXACT and fully real: psu_probability cancels out of this ratio algebraically, so it needs no assumption at all.",
    old_ssu, new_ssu, old_ssu / new_ssu)
say("  Meaning: every real respondent at this cluster should count for about %.0f%% as much real-household representation as the design assumed, because the field team genuinely interviewed %.1fx more real households there than the design's own target.",
    100 * old_ssu / new_ssu, new_ssu / old_ssu)
illustrative_psu <- 0.15  # a representative mid-range value only, NOT this cluster's real one - real psu_probability is not retrievable, see the structural finding above
say("  ILLUSTRATIVE ONLY (psu_probability = %.2f is a representative placeholder, NOT this cluster's real value - unavailable per the structural finding above): design base_weight = 1/(%.2f*%.6f) = %.2f, realized base_weight = 1/(%.2f*%.6f) = %.2f.",
    illustrative_psu, illustrative_psu, old_ssu, 1/(illustrative_psu*old_ssu), illustrative_psu, new_ssu, 1/(illustrative_psu*new_ssu))

capped_example <- real_candidates %>% filter(n_achieved > households_in_cluster) %>% arrange(desc(n_achieved)) %>% slice(1)
if (nrow(capped_example) > 0) {
  say("\n  Separately, the pmin(1,...) cap DOES bind for %d real clusters tonight; worst case %s (%s): achieved %d vs households_in_cluster only %s - ssu_probability capped at 1.0. Full list in topped_up_clusters_audit.csv's cap_bound column.",
      nrow(capped_example %>% bind_rows(real_candidates %>% filter(n_achieved > households_in_cluster)) %>% distinct()) - 1 + 1,
      capped_example$cluster_id, capped_example$pop_type, capped_example$n_achieved, format(capped_example$households_in_cluster))
}

say("\n---- EXTRA: statelessness under a DROPPING achieved count (real cluster, simulated count only) ----")
sim_cluster <- clean$cluster_id
sim_target <- clean$target_households
achieved_dropped <- achieved_by_cluster %>% mutate(n_achieved = if_else(cluster_id == sim_cluster, as.integer(sim_target), n_achieved))
one_row <- full %>% filter(cluster_id == sim_cluster) %>% slice(1) %>%
  mutate(psu_probability = illustrative_psu, ssu_probability = old_ssu, base_weight = 1/(illustrative_psu*old_ssu))
res_drop <- apply_realized_weights(one_row, achieved_dropped)
say("If %s's achieved count later dropped back to exactly its target_households (%d, e.g. after a confirmed deletion), its ssu_probability reverts to the design value %.6f automatically (got %.6f) - no special-case code, purely because topped_up becomes FALSE again on that run: %s",
    sim_cluster, sim_target, old_ssu, res_drop$frame$ssu_probability, isTRUE(all.equal(res_drop$frame$ssu_probability, old_ssu)))

audit_out <- real_candidates %>% transmute(cluster_id, pop_type, target_households, households_in_cluster, achieved_interviews = n_achieved,
                                            design_ssu_probability = pmin(1, target_households/households_in_cluster),
                                            realized_ssu_probability = pmin(1, achieved_interviews/households_in_cluster),
                                            base_weight_ratio_new_over_old = pmin(1, target_households/households_in_cluster) / pmin(1, achieved_interviews/households_in_cluster),
                                            cap_bound = achieved_interviews > households_in_cluster) %>%
  arrange(desc(achieved_interviews - target_households))
write_csv(audit_out, file.path(OUT, "topped_up_clusters_audit.csv"))

overall <- chk_a && chk_d && isTRUE(all.equal(b_new, 0.12)) && isTRUE(all.equal(c_new, 1.0)) && isTRUE(c_capped_flag) &&
  frame_idempotent && new_vals_idempotent && byte_ident_syn && byte_ident_staged
say("\n==== OVERALL: %s ====", if (overall) "ALL CHECKS PASS" else "SOME CHECKS FAILED - do not treat as validated")
writeLines(lines, file.path(OUT, "VALIDATION_REPORT.txt"))
say("Wrote %s/VALIDATION_REPORT.txt and topped_up_clusters_audit.csv (%d real topped-up clusters, ratios only - no psu_probability assumed).", OUT, nrow(audit_out))
