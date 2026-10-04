# MSNA N-WEC 2026: methodology of the whole process

**For:** the HQ validation team, the data officer, and anyone reviewing how the MSNA N-WEC 2026 data were sampled, collected, cleaned, weighted and assessed for representativity.
**Status:** 4 October 2026. This document describes the process end to end and points to the detailed documents and code for each step. It does not repeat them.

| For the detail of… | Read |
|---|---|
| The original sampling design (July–August) | [msna_methodology_summary_portable.md](msna_methodology_summary_portable.md) |
| Every Round 1 decision, formula and code location, and how to validate it | [ROUND1_METHODOLOGY_AND_VALIDATION_GUIDE.md](ROUND1_METHODOLOGY_AND_VALIDATION_GUIDE.md) |
| The Round 1 weights and how to use them | `2_monitoring/reports/round1_weighting_package_2026-10-02/README_Round1_weighting.md` |
| Day-to-day operation of the pipeline | [2_monitoring/DO_HANDOVER_RUNBOOK.md](../2_monitoring/DO_HANDOVER_RUNBOOK.md) |
| What each standing check verifies | [validity_checks/CHECK_CATALOG.md](../validity_checks/CHECK_CATALOG.md) |

---

## 1. Scope

- **Assessment:** household Multi-Sectoral Needs Assessment in North-East, North-West and North-Central Nigeria.
  - **Sampling frame:** 14 states. North-East: Adamawa, Borno, Yobe. North-West: Kaduna, Kano, Katsina, Kebbi, Sokoto, Zamfara. North-Central: Benue, Kogi, Nasarawa, Niger, Plateau.
  - **Fieldwork reached 11 states;** Kano, Kogi and Niger have no data.
- **Population groups:** IDP (sites recorded by IOM DTM, returnee sites excluded) and Non-IDP (everyone else). They are two separate sampling frames.
- **Strata:** LGA × population group. There are 327 strata in scope: 305 covered by a partner and 22 excluded, e.g. not covered or too small to sample. Each stratum is an independent sampling domain with its own sample size, cluster selection and weights.
- **Collection:** 17 partner organisations collect with a shared KoBo tool.
  - Each partner receives a package: sampling-point workbooks, KML maps and cluster field guides.
  - A monitoring dashboard tracks progress daily: https://impact-nga-jp.shinyapps.io/dashboard_app/

---

## 2. Sampling design (summary)

Full detail and rationale: [msna_methodology_summary_portable.md](msna_methodology_summary_portable.md).

- **Frame:**
  - A regular hexagonal grid over the accessible area, carrying two population layers: WorldPop gridded population for Non-IDPs, and DTM site household counts for IDPs.
  - Cells with 5 or fewer households are dropped.
  - Border buffers and areas assessed as inaccessible are removed before sampling.
- **Stage 1: clusters.**
  - Selection is probability-proportional-to-size (PPS) on household population, systematic with a fixed seed.
  - A cell drawn more than once becomes one cluster with a larger household quota.
  - Strata too small to sample are excluded, as are strata where including everything still cannot reach the precision target: 18 strata.
- **Sample size per stratum:**
  - 90% confidence, p = 0.5, 10% margin of error;
  - a design effect from an assumed intra-cluster correlation, with 6 households per cluster;
  - a finite-population correction;
  - a 10% buffer.
- **Stage 2: households.**
  - **Non-IDP:** a random draw of building footprints (6 primary households plus an equal ranked reserve list).
  - **IDP in-camp:** a full listing, then a random draw on the tablet. The fallback is a random walk from a pre-assigned backup point.
  - **IDP in host communities:** a listing compiled with the chief or head of settlement, covering every sub-area, then a random draw.

---

## 3. What changed during fieldwork

Each change was decided by the MSNA lead. The decisions that affect Round 1 estimates are listed with dates in the decision log of the Round 1 guide (section 2).

1. **IDP sampling unit, from 2 September.**
   - The July design selected 5 km hexagons and surveyed the largest DTM site in each, so smaller co-located sites had no chance of selection.
   - From 2 September, IDP clusters are individual DTM sites drawn by PPS ("site_v2"). It was not applied retroactively.
   - The two designs are combined in the weights (Round 1 guide, section 8.3).
2. **Accessibility.**
   - Partners report ward-level accessibility, held in a master accessibility status file and an accessible-area GIS layer.
   - Sample points in inaccessible wards are taken out of the active ("WORKING") frame. Interviews already collected there still count.
   - Strata that lost access after collection are assessed at their collection-period accessible population (2 Oct).
3. **Partner coverage.** LGAs were reallocated between partners where needed, e.g. Dikwa to FACT, and ACF's LGAs to ZOA. Every LGA without a partner is flagged until it is resolved.
4. **Resampling and top-ups.**
   - Where a stratum fell short because clusters were inaccessible or had too few households, new clusters were drawn from its remaining accessible pool by the same PPS method, in successive rounds.
   - Where the pool was exhausted, IDP strata were topped up with more households in existing clusters ("depth top-ups"). The Non-IDP equivalent needs a new building-footprint draw and has not been built.
   - Standing rule: keep drawing until each non-Representative stratum's pool is exhausted. Top-ups aim for a 9–9.5% margin of error, so later deletions cannot tip a stratum back.
   - Every draw records its own selection probabilities. They feed the weights.
5. **MSNA Light.** In a few Borno Non-IDP LGAs without a usable household frame (Abadam, Guzamala, Nganzai; Ngala from 29 Sep), data were collected with a lighter, non-probability approach.
   - These interviews count toward achieved totals and representativity.
   - They are excluded from weighted tables (2 Oct).
6. **Repeat draws** of the same hexagon across rounds are pooled into one weighting unit (1 Oct).

---

## 4. Data pipeline

```
KoBo download ─► anonymisation (data officer) ─► anonymised export (daily, 2_monitoring/cleaning/.../anonymised_data/)
   ─► 2_monitoring prep: match each interview to its sampled point; apply deletion decisions; checks
   ─► dashboard (deployed)          ─► 1_sampling: WORKING frame refresh ─► partner workbooks + KML maps
   ─► data officer's cleaning pipeline (cleaned dataset for analysis)
```

- **Matching.** Each interview is matched to the sampled point (Non-IDP) or cluster (IDP) it claims. When two interviews claim one point, the first live claimant keeps it (25 Sep).
- **Deletions.**
  - Data-quality removals are decided in a deletion tracker and published as a deletions overlay. Only settled deletions (confirmed, or contested and rejected) remove an interview; pending flags never do.
  - Reasons: interview shorter than 20 minutes (audit duration rounded to one decimal is below 20.0); no consent; and recovery-workbook outcomes, such as unrecoverable sampling information or a duplicate household.
- **Achieved** = completed, matched to a sampled point, and not a settled deletion. One definition is used everywhere: dashboard, partner workbooks, frame refresh, representativity and weights.
- **Monitoring products.**
  - The dashboard shows **all data collected**, cumulative across rounds. A dotted line marks the end of Round 1 (30 Sep).
  - The WORKING frame (points still to collect) and the partner packages are refreshed from the same data.
- **The data officer's cleaning pipeline** produces the cleaned analysis dataset (IMPACT format, with raw and clean sheets and logs). It applies the deletion log plus the data officer's own quality checks.

---

## 5. Round 1

Full detail: [ROUND1_METHODOLOGY_AND_VALIDATION_GUIDE.md](ROUND1_METHODOLOGY_AND_VALIDATION_GUIDE.md).

- **Data.**
  - The frozen Round 1 set is the 28,046 submissions in the 1 Oct anonymised export.
  - 2,599 are settled deletions, leaving 25,447 achieved.
  - The data officer's cleaned dataset uses a submission-date cut-off (30 Sep) and applies extra quality deletions; aligning the weights with it is pending (section 9).
- **Analysis coverage (2 Oct):** North-East and North-West states only (Adamawa, Borno, Yobe, Katsina, Sokoto, Zamfara, Kaduna). Kebbi and the North-Central states are excluded.
  - In coverage: 21,705 achieved; 21,135 weighted in 233 strata.
- **Representativity rule (1 Oct; HQ technical meeting):**
  - A simplified rule with design effect 1, applied uniformly to every stratum:
    - MoE = 100 × 1.645 × √(0.25 / n_eff), with n_eff = n(N − 1)/(N − n);
    - N = the stratum's accessible households.
  - **Labels:**
    - **Representative:** MoE ≤ 10%;
    - **Indicative – meets reporting threshold:** n ≥ 20;
    - **Dropped:** otherwise.
  - LGA and State margins combine their included strata, weighted by accessible households. Dropped strata are excluded from every aggregate.
  - In coverage: 188 / 48 / 33 strata and 101 / 27 / 10 LGAs are Representative / Indicative / Dropped, and all 7 states are Representative.
- **Weights:**
  - one design weight per interview, 1 / (P(cluster) × P(household | cluster)), using the probabilities recorded at each draw;
  - repeat draws are pooled; IDP July and post-2 Sep designs are combined (Option 3);
  - trimmed at 4 × the stratum median, then calibrated so each stratum sums to its accessible households;
  - not weighted: MSNA Light, and Dropped strata;
  - independently verified (29 of 29 checks).
- **Analysis design:** strata plus weights, without a cluster term. The same weights serve every reporting level.

---

## 6. Round 2 (from 1 October)

- Collection continues, with the dashboard showing cumulative data.
- **Representativity uses the full design rule:**
  - design effect = 1 + ((CV² + 1) m̄ − 1) × ICC, with ICC = 0.06, applied cluster-aware;
  - certainty sites are treated separately.
- The dashboard's margin-of-error switch compares this "full design" margin with the simplified Round 1 margin. It is off by default.
- Top-ups and new draws follow the standing rules in section 3.4. None run during 5–11 October.

---

## 7. Quality assurance and validation

- **Standing validity suite** (`validity_checks/`, about 85 checks in 13 modules). It checks:
  - frame integrity, accessibility consistency and achieved definitions;
  - that partner packages match the frame;
  - that mirrors are current;
  - that deletions are identical across consumers;
  - a three-way reconciliation (dashboard vs. canonical recompute vs. every partner workbook, per stratum).

  It runs after every refresh. A FAIL blocks partner publication.
- **Independent verification:** the Round 1 weights, the weighting package and its cluster table were each re-derived by a separate session from the frozen inputs, with zero differences.
- **Provenance:** every frozen input and output is recorded with its MD5 checksum. File dates in the shared OneDrive folder are not evidence of freshness, because a rewritten file can keep its old date; checks compare content.

---

## 8. Known limitations

1. **Accessibility.** The accessible population is GIS-derived (ward polygons × population shares) and moves with partner-reported access.
2. **IDP second stage.** It relies on DTM site household estimates, and host-community listings depend on informants.
3. **Reconstructed IDP pools.** Post-2 Sep IDP selection pools are reconstructed for weighting in 26 strata rather than recorded (Round 1 guide, section 10).
4. **MSNA Light** has no probability design: it is counted but not weighted.
5. **Simplified Round 1 rule.** It ignores clustering and weighting; weighted analysis margins of error can exceed the label's 10%, and this is footnoted.
6. **Tier 2 random walk.** Where used, it is a systematic rather than a simple random sample.

---

## 9. Open items at 4 October

- **[Decision pending, MSNA lead]** Align the Round 1 weights with the data officer's cleaned dataset. Inside coverage it has 277 fewer weighted households:
  - 198 duplicated or low-quality interviews the data officer removed;
  - 79 interviews submitted on 1 Oct, which the cleaned dataset treats as Round 2.

  A re-calibrated candidate has been prepared and is not yet adopted.
- **[Decision pending]** Keep Kaduna (North-West, 4 strata) in the Round 1 coverage.
- **No resampling during 5–11 October.** A top-up draw is being prepared for the MSNA lead's go-ahead.
