# v5 -> v6 change summary — 2026-09-07

Version cutover following tonight's comprehensive resampling run (FACT's
full supplementary batch + the combined-10-partner batch, which resolved
to a single real draw for Mafa/FHI 360 once the stale pre-merge workbook
was regenerated — see `1_sampling/CLAUDE.md`, "Update 2026-09-07" through
"Update 2026-09-07c", for the full narrative). Same procedure as the
2026-08-31 v2->v3 and 2026-09-03 v4->v5 cutovers: current (post-tonight)
content copied forward under the new version name; the old version name
rolled back to its state immediately before tonight's run and archived,
frozen, rather than left live.

## What v5 represents (frozen, in `_archive_superseded_versions/`)

The frame as it stood at the start of tonight's run — i.e. immediately
after 2_monitoring's deletion-tracker review (639 confirmed / 10
contested) but before any supplementary clusters were drawn. Row counts:
FULL 110,950 / WORKING 45,348.

## What v6 represents (now live in `output/data/data_collection/`)

The frame after both parts of tonight's run: FACT's full batch (114
Non-IDP clusters/1,308hh + 10 IDP site-level clusters/120hh) and the
Mafa/FHI 360 draw (15 clusters/108hh). Row counts: FULL 112,486 / WORKING
46,865.

## Verified totals

| | v5 (frozen) | v6 (live) | delta |
|---|---:|---:|---:|
| FULL rows | 110,950 | 112,486 | +1,536 |
| WORKING rows | 45,348 | 46,865 | +1,517 |
| Strata changed | — | — | 53 |
| `achieved_sample` added (WORKING) | — | — | +936hh |
| `achieved_clusters` added (WORKING) | — | — | +217 |

## By partner

| Partner | Households added | Strata touched |
|---|---:|---:|
| FACT | 872 | 52 |
| FHI 360 | 64 | 1 |

## By state

| State | Households added | Strata touched |
|---|---:|---:|
| Katsina | 253 | 13 |
| Borno | 226 | 9 |
| Sokoto | 140 | 10 |
| Zamfara | 112 | 8 |
| Kebbi | 102 | 6 |
| Adamawa | 70 | 5 |
| Yobe | 33 | 2 |

## Top 10 strata by households added

| Stratum | LGA | Partner | Achieved sample | MoE |
|---|---|---|---|---|
| `non_idp_NG008019` | Mafa | FHI 360 | 28 -> 92 (+64) | 17.70% -> 9.74% |
| `non_idp_NG008026` | Nganzai | FACT | 77 -> 121 (+44) | 10.67% -> 8.51% |
| `non_idp_NG008010` | Guzamala | FACT | 81 -> 118 (+37) | 10.41% -> 8.62% |
| `non_idp_NG021019` | Kankara | FACT | 83 -> 114 (+31) | 10.29% -> 8.77% |
| `non_idp_NG008017` | Kukawa | FACT | 83 -> 110 (+27) | 10.28% -> 8.93% |
| `non_idp_NG021001` | Bakori | FACT | 83 -> 110 (+27) | 10.28% -> 8.93% |
| `non_idp_NG022017` | Shanga | FACT | 86 -> 111 (+25) | 10.10% -> 8.89% |
| `non_idp_NG021009` | Danja | FACT | 86 -> 110 (+24) | 10.10% -> 8.92% |
| `non_idp_NG021012` | Dutsin-Ma | FACT | 87 -> 111 (+24) | 10.04% -> 8.89% |
| `non_idp_NG037003` | Birnin Magaji | FACT | 84 -> 108 (+24) | 10.22% -> 9.01% |

Full per-stratum before/after is reconstructable at any time by diffing
`_archive_superseded_versions/NGA_MSNA_2026_strata_level_sampling_frame_v5_WORKING.csv`
against the live v6 file — not reproduced here in full since this is a
summary, not the record of truth.

## Scripts repointed (`_v5_` -> `_v6_`)

23 durable/reusable scripts, verified zero `_v5_` references remain in any
of them: `analysis_remaining_eligible_pool.R`, `draw_supplementary_
clusters_batch.R`, `merge_partner_resample_batch.R`, `refresh_working_
frame_daily.R`, `05_build_accessibility_impact_workbook.py`, `build_
partner_dc_packages.py`, `draw_supplementary_idp_sites_batch.R`, `build_
partner_coverage_workbook.py`, `stamp_frame_version.R`, `analysis_
coverage_map2_lga_zoom_inset.R`, `analysis_coverage_map2.R`, `qa_cluster_
factsheets_batch.py`, `build_lga_summary_maps.R`, `build_cluster_map_
examples.R`, `build_cluster_maps_production.R`, `build_cluster_
factsheets.py`, `analysis_poi_nearest_non_idp.R`, `draw_supplementary_
idp_clusters_batch.R`, `analysis_sanity_check_accessibility_workflow.py`,
`analysis_review_returned_reports.py`, `analysis_partner_overview.py`,
`analysis_accessible_area_layer.R`, `04_build_master_accessibility_
status.py`, `01_generate_accessibility_reports.py`.

Also caught and fixed a related gap the mechanical `_v5_` (with trailing
underscore) pattern missed: `build_partner_coverage_workbook.py`'s own
output filename was `..._workbook_v5.xlsx` (no trailing underscore before
`.xlsx`), plus two in-workbook text references (`(v5)` title, "current v5
CSVs" body text) and one comment in `refresh_working_frame_daily.R`
("same v5 filenames"). All four fixed by hand after the mechanical pass;
re-ran the workbook build afterward to confirm it now saves correctly as
`NGA_MSNA_2026_sampling_frame_workbook_v6.xlsx`.

**Deliberately left un-renamed** (dated one-off/patch scripts — historically
accurate as written, matching this project's standing convention):
`scripts/one_off_analyses/add_tier2_backup_point_gsss_damasak_2026-09-03.R`.
`CLAUDE.md`'s own historical narrative text is also left untouched — it
describes what already happened, at the version number that was live when
it happened.

## `_frame_version.txt`

Re-stamped via `stamp_frame_version.R` (now itself pointing at v6). New
stamp: `working_csv_rows: 46865`, `working_csv_clusters: 3258`. Superseded
v5 CSVs archived automatically to this same folder by that script's own
existing logic — not a new mechanism, just its documented job.
