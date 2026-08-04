# `output/` — what's here and what to use

**For data collection (primary/reserve survey points): use
`data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv`.**
See "Data-quality fixes applied" below for what's already been corrected.

## Folder guide

| Folder | Contents |
|---|---|
| **`data/data_collection/`** | Every data file (CSV/XLSX) relevant to field teams and current fielding: the WORKING/FULL sampling frames (household- and strata-level), `NGA_MSNA_2026_coverage_summary_v2.csv` (LGA-level coverage decisions), `idp_camp_backup_points.csv` (in-camp Tier 2 fallback backup GPS points, 81 in-camp sites/15 flagged — a genuine field deliverable), and `NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx` (all of the above combined into one workbook: README + Sampling Frame (FULL) + Strata-Level Summary (FULL) + Coverage Summary + IDP Camp Backup Points sheets — no separate `.xlsx` per dataset, one workbook covers everything) |
| **`data/supporting_analysis/`** | Data files relevant to understanding *how* the design was built, but not needed by field teams: `idp_camp_backup_points/` (camp ranking, footprint evidence, the hand-completed visual review sheet that fed the backup-point generation) and `idp_host_feasibility/` (host-community site density/caseload feasibility flags) |
| **`maps/`** | Every map/figure PNG used in the ToR methodology section, plus `maps/supporting_evidence/` (in-camp backup-point verification images — working evidence, not ToR figures themselves) |
| **`gis/training_examples/`** | Shapefiles (points + real Stage 1 hexagons) — one example site per Stage 2 field scenario, for GIS colleague training |

## Design frame vs. working frame

| | Interviews | LGAs | What it is |
|---|---|---|---|
| **DESIGN frame** | 52,246 | 323 | What the approved sampling design calls for, before any partner-coverage check. Preserved, re-derivable — nothing changes here when coverage is reconfirmed. |
| **WORKING frame** | 31,051 | 176 | The DESIGN frame filtered to LGAs a partner has confirmed they can cover, minus the small-population certainty-stratum exclusions. **This is what will actually be fielded.** (61,837 household-level rows, i.e. primary + reserve interview slots, vs. 104,190 in the FULL frame — see "Reserve-list scaling fix" below for why this grew from 50,653/86,394.) |

The original, pre-coverage-layer DESIGN-only outputs (now superseded twice —
first by the 2026-07-30 partner-coverage revision, then by the 2026-08-04
reserve-list scaling fix, see below) have been moved to
**`../_archive/2026-07-23_design_frame_pre_coverage/`** and
**`../_archive/2026-08-04_design_frame_pre_coverage/`** respectively
(superseded by the `_v2_FULL` files in `data/data_collection/`, which carry
the same design plus coverage columns — kept for reference only, do not use
for fielding). Pipeline recompute caches live in **`../_cache/`** (not a
deliverable — load-bearing for fast pipeline reruns only).

## Reserve-list scaling fix, 2026-08-04

`reserve_households` (new column) now scales 1:1 with `target_households`
for every cluster, replacing a flat 6-reserve cap that previously applied
regardless of primary target size — see `CLAUDE.md`'s "Revision 2026-08-04"
for the full rationale and mechanism. This is a **file-size-only** change:
no primary interview counts, cluster locations, or field-team workload
changed (52,246 DESIGN / 31,051 WORKING primary interviews, same as
before) — only how many backup/replacement household slots are printed
for clusters formed by merging multiple repeated PPS draws of the same
hexagon. Household-level row counts grew accordingly: FULL 86,394 →
104,190 (+20.6%), WORKING 50,653 → 61,837 (+22.1%).

## Data-quality fixes applied 2026-08-01

- **`site_radius_m`** — was stale (uniformly 150m for every IDP row, left
  over from the superseded single-radius method). Patched
  (`scripts/patch_site_radius_and_tier2_flag.R`): now `NA` for every row
  except the 15 flagged large in-camp sites with a backup GPS point, which
  carry their real delineated extent (or the 300m fallback) instead — the
  radius concept doesn't apply anywhere else in the current design
  (Tier 1 is bounded by visible camp extent, not a radius; host-community
  listing is bounded by social recognition, not geography).
- **`tier2_fallback_used`** — didn't exist. Added as a schema-readiness
  column: `FALSE` for every in-camp IDP row (ready for field teams to set
  `TRUE` during data collection if the Tier 2 random-walk fallback is
  triggered), `NA` for Non-IDP/host-community rows it doesn't apply to.
  Can't be computed in advance — whether Tier 2 gets used is a field-team,
  real-time decision.

## If you rerun the pipeline

`01_sampling_pipeline_main.R` still writes fresh DESIGN-only files to
`output/*.csv` (top level) — that's normal, expected behaviour. If you do
rerun it, archive the newly-written files into a fresh dated
`_archive/YYYY-MM-DD_design_frame_pre_coverage/` folder afterward (or rerun
`analysis_partner_coverage.py` + `build_partner_coverage_workbook.py` to
refresh `data/data_collection/` instead, if only the coverage layer
changed — note this will need the `patch_site_radius_and_tier2_flag.R` fix
reapplied afterward too, since regenerating from scratch doesn't carry the
2026-08-01 patch forward), so `output/` doesn't silently drift back into
having stale and current frames sitting side by side.
