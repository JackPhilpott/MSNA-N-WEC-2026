# CM004003 (Mayo-Danay) coverage scenario study — Cameroon Far North

**Archived 2026-08-20, corrected 2026-08-21 — complete, not blocked on
anything.** Was `1_sampling/resampling/CMR_far_north_scenario_test/` (a
standalone favor for a colleague running the Cameroon Far North assessment
— never part of the NGA MSNA 2026 project); moved here, into this
project's own `_archive/` dated-folder convention, once the piece of work
was finished.

**Flagged by the user (2026-08-20) as the template for a similar document
they expect to need for NGA**, once comparable resampling/representativity
questions come up there during data collection. If that happens: start
from `output/mayo_danay_coverage_analysis.html` (same file published as
the "Mayo-Danay Coverage Analysis" artifact) as the structural template —
representativity theory → per-group scenario → per-group options →
parameter sensitivity → recommendations + explicit do/don't — and
`scripts/moe_scenario_tool.py` as the calculation engine template. Swap in
NGA's own population/coverage data and design parameters; the methodology
(proportional-share targets per stratum, MoE projected against each
stratum's full target population, per-group representativity never
pooled) is general, not Cameroon-specific — **and the per-stratum
correction below is exactly the kind of thing to get right from the start
next time, not rediscover.** The published artifact itself is **private**
— re-publish (or ask the user for the current sharing status) before
assuming anyone else can open the link.

## The question this answered

For admin-2 CM004003 (Mayo-Danay, 11 admin-3s), how many admin-3s need
partner coverage before the estimate can be called representative at 90%
CL / 10% MoE, versus indicative — and what design levers (if any) could
change that — given only 3/11 admin-3s had a confirmed partner (Maga→ACF,
Vele→ACF, Yagoua→JRS).

## Correction, 2026-08-21 — representativity must be assessed per stratum

The 2026-08-20 first pass answered this with one **pooled, admin-2-wide**
MoE across all population groups combined (host/IDP/returnee/refugee),
finding "8/11 admin-3s needed." **This was the wrong unit of analysis.**
MSNA indicators are reported *by population group* — the source design
itself computes separate sample-size targets per group, exactly because
host, IDP, and returnee needs differ. Checked directly: at the old "8/11 =
representative" point, **none of the three actual population groups had
individually crossed 10% MoE** — PND (host) itself sat at 10.7%. The
pooled figure crossed early because its formula weights each group's
variance contribution by its *squared* population share — for a
94%-host-weighted population like this one, that shrinks the dominant
group's contribution by roughly 15%, letting a blended number dip under
10% while the group that weight represents has not. **A pooled/blended
metric can show "representative" while every individual population group
is still indicative** — this is now flagged explicitly in the document
(Part 1's "trap" callout, and the Don't list) as a general risk, not just
a one-off fix.

Per-stratum (per population-group) representativity is now the **primary**
analysis throughout (`group_order()`/`group_scenarios()` in
`moe_scenario_tool.py`); the pooled metric (`pooled_moe()`/`run_scenario()`)
is kept only as a clearly-labelled, non-primary "aggregate blended effort"
figure, documented as not a substitute for the per-group numbers.

**Also fixed while correcting this**: a floating-point boundary bug where
a group that had delivered its own full target *exactly* (verified
algebraically and numerically to agree to 1e-14) was nonetheless flagged
"indicative" by a too-strict `<=` comparison — `MOE_TOLERANCE` absorbs
float noise only, it does not mask any real precision gap (see its
comment in `moe_scenario_tool.py`).

## Answer (corrected)

Each population group needs a **different set, not just a different
count**, of admin-3s — three genuinely separate operational problems:

| Group | Population | Admin-3s needed | Which ones |
|---|---|---|---|
| Host (PND) | 394,342 (all 11 admin-3s) | **11 / 11** | Full geographic saturation — no shortcut |
| IDP (PDI) | 4,352 (only 5 admin-3s) | **5 / 11** | Maga, Vele, Yagoua (confirmed) + Kai-Kai, Gobo — 2 admin-3s away |
| Returnees | 28,030 (10 of 11 admin-3s) | **10 / 11** | All except Kalfou |
| Refugees | 0 | n/a | No population in this admin-2 |

IDP representativity is realistically achievable this cycle (2 more
specific partners); host and returnee representativity are not, and
should be tracked/resourced as separate, longer-run tracks rather than
held to the same near-term bar. This is the analysis the user
specifically asked to have flagged clearly to the team — see
`output/mayo_danay_coverage_analysis.html` Part 3, "Representativity
options, by population group."

**Cluster size (M) / design effect (DEFF) do NOT change any of these
counts.** Swept M from 1 to 30 (DEFF 1.00 to 2.74) **per group**
(`scripts/cluster_size_sensitivity.py`, corrected 2026-08-21 to check
per-group rather than the old pooled figure): PND stayed at 11, PDI at 5,
Retournees at 10, unchanged throughout. Only the total interview count and
cluster count moved. Algebraic reason unchanged from the first pass: each
admin-3's target scales with DEFF in exact proportion to the MoE formula's
own DEFF term, so the two cancel for populations this large — **DEFF/
cluster-size is a cost lever, not a coverage lever**, confirmed to hold
independently for every group, not just in aggregate.

## Data sources

- `input/CMR - Far north - Preperatory Excel v2.xlsb` — the partner/
  coverage assignment file initially provided. **Does not contain raw
  population** — every PND/PDI/Réfugiés/Retournées figure in it is already
  a pre-computed sample size (confirmed three independent ways: a
  recurring ~102 ceiling value typical of a saturating MoE formula; the
  `Budget NWSW` sheet's column literally named "Nb surveys"; the
  `Costing`/`Costing (2)` sheets' column literally named "Sample size" for
  that same figure). Useful for coverage/confirmed status per admin-3, not
  for population.
- `input/Sampling_MSNA_2026_Extreme-Nord Admin 3.xlsx` — provided
  afterward, contains the actual raw population (`Pop admin3` column,
  `host`/`IDP`/`ret`/`ref` sheets = PND/PDI/Retournées/Réfugiés) *and* an
  explicit `Parametres` sheet documenting the real methodology (90% CL,
  10% MoE, p=0.5 governance-flagged, ICC=0.06, cluster size M=6, 10%
  non-response buffer) — this is what confirmed DEFF=1.3 = 1+(6-1)×0.06
  was derived, not guessed.
- `input/population_by_admin3_CM004003_TEMPLATE.csv` /
  `..._REAL.csv` — the blank template and the final populated version
  actually used for the results above.

## Scripts

- `scripts/moe_scenario_tool.py` — the calculation engine, per-stratum
  representativity as the primary analysis (see the correction above).
  Methodology mirrors the NGA project's own `realized_moe()`/certainty-
  stratum pattern (see `../../CLAUDE.md`): full target per population
  group via the standard finite-population-corrected MoE formula; each
  admin-3's target = its proportional population share of that; for a
  given covered-subset scenario, achieved sample = sum of covered admin-3s'
  targets FOR THAT GROUP, projected against that group's **full**
  population (not just the covered slice — deliberate, see the artifact's
  Part 1). All parameters (CL, MoE, DEFF, buffer) are named constants at
  the top of the file, plus explicit `deff` passthrough on
  `compute_targets()`/`realized_moe()`/`pooled_moe()` specifically so
  sensitivity sweeps can override it per call — Python binds default-
  argument values once at function definition, so mutating the module-level
  constant after the fact silently does *not* flow through the default-arg
  chain (hit and fixed during the first build; still documented in
  `pooled_moe()`'s docstring since the same trap applies to any future
  parameter).
- `scripts/cluster_size_sensitivity.py` — the M/DEFF sweep behind the
  "cost lever, not coverage lever" finding, corrected 2026-08-21 to check
  per group rather than the old pooled figure.

Both run cleanly from this archived location (paths verified 2026-08-21).

## Output

- `output/CM004003_coverage_scenarios.csv` — full scenario table: primary
  per-group rows (`analysis=per_group`, one set per population group,
  each group's own operational order) plus the secondary pooled/aggregate
  rows (`analysis=pooled_secondary`), clearly tagged apart.
- `output/mayo_danay_coverage_analysis.html` — the source file behind the
  published "Mayo-Danay Coverage Analysis" artifact (same URL across both
  the 2026-08-20 and 2026-08-21 versions — republished in place, not a new
  artifact). Self-contained single HTML file (inline CSS, hand-built SVG
  charts including a 3-series per-group line chart using the dataviz
  skill's validated categorical palette, light/dark theme tokens) — open
  directly in a browser, or republish as an Artifact from a future session
  using this same file path to get a fresh shareable link.
