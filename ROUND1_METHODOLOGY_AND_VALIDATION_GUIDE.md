# MSNA N-WEC 2026: Round 1 methodology and validation guide

**For:** the Data Officer completing the Round 1 analysis tables, and the HQ validation team.
**Prepared:** 2 October 2026, at the hand-over from the MSNA lead (Jack Philpott).
**Purpose:** every methodological decision behind the Round 1 dataset, representativity labels and survey weights, with the formula, the reason, and the line of code that implements it. Use it to check any number end to end.

The original sampling design (July–August) is documented in [msna_methodology_summary_portable.md](msna_methodology_summary_portable.md). This guide covers that design briefly and everything decided since.

**Path conventions.** Paths are relative to the workspace folder `MSNA N-WEC 2026/`. It holds three projects:
- `1_sampling/`: frame, draws, representativity, weights;
- `2_monitoring/`: data pipeline, cleaning, dashboard;
- `3_analysis/`: analysis.

The standing check suite lives in `validity_checks/`. Line numbers are as of 2 Oct 2026 (git commits listed in section 11).

---

## 1. Round 1 at a glance

| Item | Value | Source |
|---|---|---|
| Round 1 submissions | **28,046** (every record in the anonymised export at the close of Round 1) | `2_monitoring/data/ROUND1_MEMBERSHIP.csv` |
| Removed (settled deletions) | **2,599** (incl. 90 consent refusals) | `2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv`, md5 `2636cefa08fc74ba5bbef676ee55d2fc` |
| **Achieved interviews** | **25,447** (12,878 Non-IDP + 12,569 IDP) | `2_monitoring/data/real_submissions.csv`, md5 `24db61ae699e6de4bc6890f346a3b774` |
| Frozen copy used for all Round 1 outputs | the three files above | `1_sampling/resampling/output/round1_final_snapshot_v2_2026-10-02/` (with `MD5.txt`) |
| Strata (LGA × population group) | 327 in scope (305 covered + 22 excluded) | `1_sampling/output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv` |
| Round 1 representativity | **216 Representative / 67 Indicative / 44 Dropped** strata; 121 / 44 / 12 LGAs; all 11 states Representative | section 7 |
| Weighted interviews | **24,855** in 280 strata (+ 592 unweighted: 477 MSNA Light, 115 in Dropped strata) | section 8 |
| Deletion & correction log for the DO | 6,528 rows: removals, corrections, flags kept | `2_monitoring/reports/partner_data_recovery/outputs/_round1_closeout/MSNA_N-WEC_2026_Round1_deletion_log_2026-10-02.xlsx` |

---

## 2. Decision log (who decided what, and why)

All decisions were made by the MSNA lead (Jack Philpott) unless stated otherwise. Quotes are his words.

| Date | Decision | Rationale / quote |
|---|---|---|
| 2 Sep | IDP sampling unit switched from 5 km hex to individual DTM site (going forward, not retroactive) | The hex design only ever surveyed the largest site in a hex. Smaller co-located sites had zero chance of selection. |
| 10 Sep | Achieved = completed, matched to a sampled point, not a settled deletion. Only confirmed deletions exclude | "Only confirmed deletions exclude." Pending flags never reduce Achieved. |
| 10 Sep | `fcs_zero` (zero food consumption score) is a flag, not a deletion reason | Downgraded to a logical-error flag; no exclusion effect. |
| 20 Sep | Oversampled interviews count in Achieved (uncapped) | "Include ALL oversampled interviews in achieved counts, without inflating stratum target." |
| 22 Sep | MSNA Light interviews count as achieved in their stratum | Light LGAs (Abadam, Nganzai, Guzamala; Ngala Non-IDP from 29 Sep) are real collected data. |
| 29 Sep | Round 1 reporting categories: Representative / Indicative – meets reporting threshold / Dropped | "Indicative – meets reporting threshold" = MoE > 10% but ≥ 20 interviews. |
| 30 Sep | Top-ups aim for 9–9.5% MoE, not just ≤ 10% | Margin so a later deletion cannot tip a stratum back. |
| 1 Oct | **Two representativity rules:** Round 1 = simplified (design effect 1); Round 2 = the strict cluster-aware formula | HQ technical meeting. "I could only justify something that is consistent": the Round 1 rule is applied uniformly to every stratum. |
| 1 Oct | Round 1 = every record in the anonymised export at the close of Round 1 (28,046), assigned by processed date | "All data that we currently have within the anonymised data to this moment in time should be considered Round 1." |
| 1 Oct | Certainty-site MoE treatment dropped for Round 1 (kept for Round 2) | It changes no verdict under design effect 1. |
| 1 Oct | Dropped strata are excluded from every aggregate | "We're excluding them and pretending as if they're not in the [design] at all." |
| 1 Oct | Aggregates: Strata → LGA → State, each with its own MoE; combined and IDP/Non-IDP views; dual labels plus footnotes | |
| 1 Oct | Analysis tables declare weights + strata, no clusters (option b) | Consistent with the Round 1 gate. |
| 1 Oct | Weights = full cluster-level design weights (option ii), with the repeat-draw fix | "We don't want them [over-collected clusters] to completely dominate the analysis results." |
| 2 Oct | **Strata that lost accessibility after their interviews were collected are included**, assessed at their collection-period accessible population | "We always want to include any data collected wherever possible." |
| 2 Oct | IDP weights: **Option 3** (count each household once, by the best route available) | See section 8.3 and `1_sampling/resampling/output/full_weighting_build_2026-09-28/idp_psu_probability_decision_report_2026-10-02.md` |
| 2 Oct | Weights **capped at 4× the stratum median**, then re-calibrated | Standard weight trimming. |
| 2 Oct | **No design-effect (Kish) term in the Round 1 gate** | Analysis-table MoEs carry the weighting effect; footnoted. |
| 2 Oct | **MSNA Light interviews excluded from weighted tables** | They have no probability design. They stay in the counts and representativity. |
| 2 Oct | **Duration rule:** remove for short duration only if the audit-trail duration rounded to one decimal is below 20.0 min (< 19.95) | Matches the DO's own check. Reinstated 5 interviews (25,442 → 25,447). |

---

## 3. Sampling design (original, July–August)

**Strata.** Each LGA × population group (Non-IDP / IDP) is a stratum.

**Non-IDP first stage.** A 5 km hexagon grid over WorldPop. Clusters (hexes) are selected by systematic PPS, with measure of size (MOS) = estimated households in the hex.

**IDP first stage.** The same hex grid over IOM DTM sites, then the largest DTM site in each selected hex was surveyed. This was replaced by site-level selection from 2 Sep (section 4).

**Sample size**, in `build_sampling_plan()` at [scripts/01_sampling_pipeline_main.R:786](scripts/01_sampling_pipeline_main.R#L786):
- Z = qnorm(0.95) (90% confidence), p = 0.5, e = 10%;
- m = 6 households per cluster, ICC = 0.06;
- deff = 1 + (m − 1) × ICC ([line 799](scripts/01_sampling_pipeline_main.R#L799));
- n0 = Z² p (1 − p) / e² ([line 801](scripts/01_sampling_pipeline_main.R#L801)), then the finite-population correction, ×deff, a 10% buffer, and rounding to multiples of m;
- strata with fewer households than m × 6 are certainty (take-all) strata ([line 869](scripts/01_sampling_pipeline_main.R#L869)).

**First-stage probability**, at [scripts/01_sampling_pipeline_main.R:944](scripts/01_sampling_pipeline_main.R#L944):
```
psu_probability = 1                                            (certainty stratum)
                = min(1, clusters × MOS_hex / total_MOS_stratum) (otherwise)
```

**Second stage.** Households are selected within the cluster ([scripts/03_stage2_household_selection.R:520](scripts/03_stage2_household_selection.R#L520)):
```
ssu_probability = min(1, target_households / households_in_cluster)
base_weight     = 1 / (psu_probability × ssu_probability)
```
These design-time weights are superseded by the realized Round 1 weights in section 8.

**IDP hex → site.** [scripts/05_stage2_idp_site_assignment.R:79](scripts/05_stage2_idp_site_assignment.R#L79): `select_stage2_idp_sites()` keeps the largest DTM site in the hex (`slice_max(households)`, line 203). The other sites are recorded as `n_other_sites_in_hex`.

**Authoritative July design.** The archive `_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds` is the design after the 6 Aug NW targeted resample. Do **not** use `_cache/idp_sites/stage2_idp_sites.rds` (3 Aug). It predates that resample: 14 of its cluster IDs point at different hexes, and it lacks 41 NW clusters.

---

## 4. Changes to the sample during fieldwork

**Supplementary draws (accessibility shortfalls)**
- Non-IDP: `resampling/scripts/draw_supplementary_clusters_batch.R`.
- IDP: `resampling/scripts/draw_supplementary_idp_sites_batch.R`.
- Tier 1 draws fresh units. Tier 2 allows repeats when the fresh pool is exhausted.
- Merged into the frame by `resampling/scripts/merge_partner_resample_batch.R`.

**IDP site-level redesign (2 Sep)**, in `draw_supplementary_idp_sites_batch.R`:
- **Stage B** ([line 119](resampling/scripts/draw_supplementary_idp_sites_batch.R#L119)): the candidate pool is accessible DTM sites in the LGA, excluding any site within 30 m of an existing cluster (line 133).
- **Stage C** ([line 159](resampling/scripts/draw_supplementary_idp_sites_batch.R#L159)): a sequential PPS draw without replacement, weighted by site households; `ceiling(households needed / 6)` sites per batch.
- Each frame row carries `psu_definition_version` = `hex_v1` (July mechanism) or `site_v2` (post-2 Sep).

**Depth top-ups (D3, 27–30 Sep).** Extra interviews in existing clusters to reach the 9–9.5% MoE target.
- **Known side effect:** `merge_partner_resample_batch.R:433` adds `floor(increase / 6)` to `selection_count`. That is correct for a genuine repeat draw, but it also fired for top-ups. 21 IDP clusters therefore carry about 200 spurious "draws".
- **Never read the live `selection_count` as a draw count.** Use `selection_count_net_of_topups` in `resampling/output/full_weighting_build_2026-09-28/idp_cluster_psu_facts_2026-10-02.csv` (verified against the 6 Aug design).

**MSNA Light.** Negotiated, LGA-level enumeration with no probability design, in Abadam, Nganzai, Guzamala, and Ngala Non-IDP from 29 Sep.

**Partner reallocations and LGA closures.** These are recorded in `output/data/data_collection/_pipeline_changelog.csv` and in the frame columns `coverage_status`, `exclusion_reason` and `original_partner_covering`. FACT closed 10 LGAs on 28 Sep, after their data had been collected (see section 7.3).

---

## 5. Accessibility and the accessible population

**Pipeline**
1. Partner accessibility reports.
2. Master ward status: `resampling/scripts/04_build_master_accessibility_status.py`, giving `resampling/output/master_accessibility_status_ward_level.csv`.
3. GIS ward-portion layer: `resampling/scripts/analysis_accessible_area_layer.R`, giving `resampling/output/gis/accessible_area_lga_ward_portions.{shp,csv}`.

**Accessible population** of a stratum ([resampling/scripts/05_build_accessibility_impact_workbook.py:740](resampling/scripts/05_build_accessibility_impact_workbook.py#L740) and line 1226):
```
pct_pop_accessible = 100 × (population in Accessible ward portions) / (population in all ward portions)   [per LGA × pop group]
N_hh_accessible    = N_hh × pct_pop_accessible / 100
```
The layer is used only as a share. Reported totals come from the frame's `N_hh`. This is the denominator of every MoE in section 7 and the calibration total in section 8.

**Fixed 2 Oct: Tangaza/Zuru duplicate rows.**
- **Cause:** Tangaza and Zuru are jointly covered by IRC and LHI, and the frame carried two partner strings for them. The layer's covering-partner lookup therefore doubled every ward portion of 3 LGA × group keys.
- **Fix:** collapse the lookup to one row per key, and stop if the join changes the row count ([analysis_accessible_area_layer.R:299–317](resampling/scripts/analysis_accessible_area_layer.R#L299)).
- **Effect:** shares were never affected, so no MoE or label changed. Two readers that joined spatially against the layer were also guarded: `refresh_idp_site_frame_accessibility.R` and `analysis_remaining_eligible_pool.R`.

---

## 6. Data: what counts as an interview

**Achieved**, identical in every consumer:
- dashboard `is_achieved()` at [2_monitoring/dashboard_app/global.R:1116](../2_monitoring/dashboard_app/global.R#L1116);
- 05 `load_real_achieved()` at [resampling/scripts/05_build_accessibility_impact_workbook.py:1040](resampling/scripts/05_build_accessibility_impact_workbook.py#L1040);
- R mirror `compute_achieved_lookup()` at [scripts/shared/frame_status.R:95](scripts/shared/frame_status.R#L95).
```
achieved = interview_outcome == "completed"
           AND matched_survey_id present (matched to a sampled point)
           AND uuid NOT in CONFIRMED_DELETIONS_OVERLAY with status confirmed or contested
```
"Contested" means appealed and rejected, so the deletion stands. Pending flags never reduce Achieved.

**Deletion reasons.** These are short duration, no consent, and the recovery-workbook outcomes (missing or unrecoverable sampling information, duplicate household).
- **Duration rule:** see section 2. It is implemented in `2_monitoring/_working_files/scripts/round1_build_deletion_log.py:56` (`DURATION_RULE_MS = 1,197,000`, i.e. 19.95 min), with a hard stop at line 247.
- `fcs_zero` has no deletion effect.

**Round 1 membership.** `2_monitoring/data/ROUND1_MEMBERSHIP.csv` holds the 28,046 uuids. Every Round 1 output is guarded to exactly this set; the standing check is `three_way_reconciliation`.

**Recovery closeout (1–2 Oct).**
- Partner recovery workbooks were resolved into one final value per interview and field: `2_monitoring/data/ROUND1_CORRECTIONS.csv`, applied in `prep_real_submissions.R` section 3b ([2_monitoring/cleaning/real/prep_real_submissions.R:506](../2_monitoring/cleaning/real/prep_real_submissions.R#L506)).
- 19 CRS interviews unmatched in the field were placed by device GPS, and 1 was deleted.

**Deletion log for the DO.** It uses the DO's 29 master-log columns plus 5 traceability columns. It was verified independently on 2 Oct:
- removals equal the CONFIRMED overlay exactly (2,599);
- every uuid is in Round 1 membership;
- no removed interview is counted as achieved;
- 28,046 − 2,599 = 25,447.

---

## 7. Representativity

### 7.1 Round 1 rule (simplified, design effect 1)
Script: [resampling/scripts/one_off_analyses/build_round1_representativity_prototype_2026-10-02.py](resampling/scripts/one_off_analyses/build_round1_representativity_prototype_2026-10-02.py). It reuses 05's own loaders by import.
```
n     = achieved interviews in the stratum (section 6)
N     = accessible households (section 5; section 7.3 for strata that lost access)
ndeff = n × (N − 1) / (N − n)                 (finite-population correction)
MoE   = 100 × Z × sqrt(p(1 − p) / ndeff),  Z = 1.6449, p = 0.5   (MoE = 0 if n ≥ N)
```
**Labels**
- **Representative:** MoE ≤ 10%.
- **Indicative – meets reporting threshold:** MoE > 10% and n ≥ 20.
- **Dropped:** excluded with no data, or n < 20.

### 7.2 Round 2 rule (strict, unchanged)
This is the same formula with a cluster design effect for unequal cluster sizes:
- deff = 1 + ((CV² + 1) × m̄ − 1) × ICC, ICC = 0.06 (`realized_moe_unequal()`, [scripts/shared/frame_status.R:480](scripts/shared/frame_status.R#L480); Python twin at 05:190);
- the certainty-site treatment `realized_moe_certainty_aware()` is at 05:251.

On the same Round 1 data, for reference: 84 Representative under the strict rule against 216 under the Round 1 rule.

### 7.3 Strata that lost accessibility after collection (2 Oct)
- **Which strata:** those with Round 1 interviews that now show zero accessible population, or were excluded for accessibility loss. These are FACT's 28 Sep closure, plus Tsafe IDP, Shagari Non-IDP and Gubio.
- **Why it's valid:** every such interview predates 26 Sep.
- **Denominator:** the larger of the stratum's accessible shares in the 8 Sep and 26 Sep archived layers. Gubio IDP was never recorded as accessible, so it uses total households. Both are conservative, because a larger N gives a larger MoE.
  - `_archive/2026-09-08_pre_fact_return_ingest/accessible_area_lga_ward_portions.csv`
  - `resampling/output/_archive_gis_pre_final_2026-09-26/accessible_area_lga_ward_portions.csv`
- **Result:** 19 strata (1,065 interviews) become 6 Representative, 9 Indicative and 4 Dropped (< 20).
- **Traceability:** each row's `Accessible-population basis` column records the basis used.

### 7.4 Aggregates (LGA and State)
```
MoE_aggregate = 100 × Z × sqrt( Σ_h W_h² × p(1 − p) / ndeff_h ),   W_h = N_h / Σ N_h  over the INCLUDED strata only
```
Dropped strata are left out entirely. Every aggregate reports the share of households it speaks for. Combined IDP + Non-IDP aggregates rely on the ToR assumption that WorldPop Non-IDP estimates exclude IDPs.

**Outputs:** `1_sampling/resampling/output/round1_representativity_prototype_2026-10-02/`
- `round1_strata.csv`
- `round1_lga.csv`
- `round1_state.csv`
- `Round1_representativity_PROTOTYPE_2026-10-02.xlsx` (README sheet with the rules)

The dashboard's Round 1/Round 2 toggle reproduces these exactly (324/324 strata, 176/176 LGAs). It is staged, flag `MSNA_FEATURE_ROUND1_TOGGLE`, and not deployed.

---

## 8. Survey weights (Round 1)

Script: [resampling/scripts/build_round1_weights_FINAL_2026-10-02.R](resampling/scripts/build_round1_weights_FINAL_2026-10-02.R). Its header restates every rule.

Output: `1_sampling/resampling/output/full_weighting_build_2026-09-28/round1_FINAL_2026-10-02/`
- `ROUND1_WEIGHTS_FINAL_2026-10-02.csv`: one row per weighted interview. Use the column `weight`.
- `ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv`
- `ROUND1_UNWEIGHTED_interviews_2026-10-02.csv`: the 592 interviews deliberately given no weight, with the reason for each.

### 8.1 Structure
```
base weight  = 1 / (first-stage probability × second-stage probability)
final weight = base weights capped at 4 × stratum median (iteratively), each stratum re-calibrated so Σ weight = N (section 5/7.3)
```

### 8.2 Non-IDP
- **First stage:** min(1, (design clusters + supplementary clusters) × MOS_hex / total MOS), or 1 in certainty strata. MOS comes from the cached hex grids.
  - 26 clusters whose hex IDs are absent from those grids take MOS from the record of the draw that selected them: the 6 Aug design archive (11) or the draw staging file (15). Their grid versions were renumbered later.
  - Nothing is imputed.
- **Repeat draws:** records of one physical hex in one stratum are one weighting unit. That covers 112 groups, all verified co-located (cluster centroids within 3 km).
- **Second stage:** interviews in the unit / households in the unit, for every unit. This adjusts for both over- and under-collection.

### 8.3 IDP: Option 3
- **July clusters (`hex_v1`):** probability from the 6 Aug design (`psu_probability`). The 6 clusters drawn after 6 Aug use the supplementary formula.
- **Mixed strata** (July and post-2 Sep clusters):
  - two-phase, site-level: π = π_July + (1 − π_July) × π_site;
  - post-2 Sep sites: π = π_site;
  - each cluster stands for its own site's households.
- **July-only strata:** the surveyed site stands in for its whole hex (cluster total = hex households / π_July).
- **π_site (post-2 Sep site selection):** per batch, k_b × site households / pool households, combined as 1 − Π(1 − π_b). The pool is taken from the preserved site-frame snapshot nearest the batch: 3 Sep, 7 Sep, 21 Sep or current. The per-batch table is `idp_site_v2_pi2_per_batch_2026-10-02.csv` (Resampling). Where unavailable, a single-pool approximation is used. FACT-closed LGAs use the 21 Sep snapshot, and every cluster's basis is recorded in `first_stage_basis`.
- **Second stage:** realized (interviews / site households), using the DTM site-household estimate.
- **Why Option 3:** in mixed strata, post-2 Sep sites stand for households the July design never surveyed. Without that, they'd be represented by a neighbouring camp. Full comparison: `resampling/output/full_weighting_build_2026-09-28/idp_psu_probability_decision_report_2026-10-02.md`.

### 8.4 Exclusions (no weight; listed in `ROUND1_UNWEIGHTED_interviews`)
- 477 MSNA Light interviews (no probability design, decision 2 Oct). A cluster with any Light row counts as Light.
- 115 interviews in strata Dropped by the < 20 floor.

### 8.5 Effect of the cap (all 280 weighted strata)
| | Kish weighting effect, median | 90th percentile |
|---|---|---|
| Uncapped | 1.23 | 1.93 |
| Final (4× cap) | 1.22 | 1.49 |

The cap binds in 90 strata. No weight exceeds 4× its stratum median.

### 8.6 Analysis design to declare (option b, decision 1 Oct)
```r
library(survey)
des <- svydesign(ids = ~1, strata = ~strata_id, weights = ~weight, data = round1_with_weights)
```
Strata and weights only, no cluster IDs. For any estimate in a Representative stratum, the analysis MoE can exceed 10% because of the weighting effect. This is expected (the Round 1 gate has no Kish term, decision 2 Oct) and footnoted: "Representative under the Round 1 rule; the weighted confidence interval may be wider."

---

## 9. How to validate

### 9.1 Standing check suite (85 checks, 13 modules)
```
cd validity_checks
Rscript run_all_checks.R                     # everything (run from PowerShell on Windows; the sf package crashes under Git Bash)
Rscript run_all_checks.R --module three_way_reconciliation
```
- **Catalogue:** `validity_checks/CHECK_CATALOG.md`.
- **Results:** every run writes a CSV to `validity_checks/run_history/`.
- **`three_way_reconciliation`** (new, 2 Oct) compares, stratum by stratum, the dashboard's figures, a canonical recompute from the submissions and deletions overlay, and every partner workbook's Strata Summary.
- **Staged builds:** set the env var `MSNA_PKG_ROOT` to point the package checks at a staged partner-package build instead of the live folder.

**Result on the live state, 2 Oct 03:23: 81 pass / 4 warn / 0 fail.** All 4 warnings are explained:
1. 18 zero-population strata have no 05 representativity target, by design.
2. The feasibility sheet's 327 rows include 22 excluded strata, by design.
3. The latest draw folder is a merge-staging folder.
4. One coverage-decision row (Shagari) is housekeeping.

### 9.2 Reproduce each output
| Output | Command (from `1_sampling/`) |
|---|---|
| Round 1 representativity | `python resampling/scripts/one_off_analyses/build_round1_representativity_prototype_2026-10-02.py <snapshot_dir> <out_dir>` |
| Round 1 weights | `Rscript resampling/scripts/build_round1_weights_FINAL_2026-10-02.R <snapshot_dir> <round1_strata.csv> <out_dir>` |
| IDP options evidence | `Rscript resampling/scripts/one_off_analyses/idp_psu_options_comparison_2026-10-02.R` |

Here `<snapshot_dir>` = `resampling/output/round1_final_snapshot_v2_2026-10-02`. The weights script stops itself if:
- any weighted interview lacks a probability;
- calibration is not exact;
- any weight exceeds 4× its stratum median.

### 9.3 Independent checks already performed (2 Oct)
- Deletion log against the overlay and membership (section 6).
- Achieved, target and remaining identical across dashboard, canonical recompute and all 17 partner workbooks (308 rows, 0 differences).
- Dashboard toggle against the representativity CSVs (exact).
- Weights: Non-IDP + IDP weighted + unweighted = 25,447; calibration exact in every stratum.

---

## 10. Known limitations (state these in the methodology note)

1. **Post-2 Sep pools are approximate.** The draw script saved no candidate pools, so IDP site-selection probabilities use the nearest preserved snapshot of the site frame (3 Sep, 7 Sep, 21 Sep or current), not the exact pool at each draw.
2. **Co-located IDP sites in July-only strata** (no post-2 Sep draw) are represented by the surveyed site in their hex. That is a local substitution assumption, not a selection probability.
3. **IDP second stage** uses the DTM provisional site-household estimate.
4. **The selection probabilities for the 26 records-only Non-IDP hexes** use their draw-time MOS, while all other clusters use the cached grids. Both are the same population source.
5. **Weight capping** trades a small bias for lower variance (4× median, re-calibrated).
6. **Analysis MoE vs. labels:** some Representative strata will show a weighted MoE above 10% (section 8.6).
7. **MSNA Light** contributes to counts and representativity but not to weighted estimates.
8. **Accessible population** is GIS-derived (ward polygons × WorldPop/DTM shares) and frozen at Round 1. Strata that lost access are assessed at their collection-period population (section 7.3).
9. **Second-household encoding.** When two households were interviewed at one sampled point, the second carries a `_b` suffix on its point/listing fields. Row counts (dashboard, workbooks, 05, weights) count both. The legacy frame field `achieved_sample` counts points and reads up to 464 lower. **Use row counts.**
10. **Gubio IDP** is assessed against total households, because it was never recorded as accessible (conservative).

---

## 11. Code versions and files

**Git**
- `1_sampling`: eb76349 (accessibility-layer fix), 7be4797, 8d51f06 (prototypes), e09e72a (OneDrive conflict guard).
- `2_monitoring`: 6511280 (duration rule, allowlist), 1521f8a (Round 1 closeout).

The final weights script and this guide are committed with the hand-over.

**Pending at hand-over** (status at time of writing; the MSNA team will update):
- Partner workbooks and the live dashboard currently reflect 25,442. They are being refreshed to the final 25,447.
- The per-batch IDP site-probability table is replacing the single-pool approximation in the weights (section 8.3).
- Request to Posit support to purge an old dashboard bundle (12636193) that briefly contained a raw GPS extract. The bundle was not served by the app.
