# MSNA N-WEC 2026 — Sampling design

**Status: complete and frozen.** Final sampling frame submitted 2026-07-15
(git commit `9510d15`, pushed to `origin/master`). This project moved from
`5. GIS\sampling\R Sampling\MSNA N-WEC 2026\` to this location on 2026-07-16
— if you're picking this up in a fresh session, prior session memory tied
to the old project path may not be attached here automatically. This file
exists so that context isn't lost.

## What this project is

Stratified two-stage cluster sample for the 2026 MSNA (North-West/East/
Central Nigeria), host + IDP populations, ~86,754 total planned interview
rows across 5,780 clusters. See `msna_methodology_summary_portable.md` in
this folder for the full methodology writeup (also published online as a
shareable document — ask the user for the link if you need to update it,
don't create a new one).

- **PSU**: hexagon grid cells, PPS-selected (host: gridded population;
  IDP: IOM DTM population).
- **SSU — host**: Google Open Buildings footprint draw within each
  selected hexagon; zero-building clusters get reallocated to a different
  hexagon in the same stratum.
- **SSU — IDP**: the DTM site's own GPS point directly (no buildings), 150m
  field radius, field-team self-listing.
- **Cluster size**: 6 standard; **7 + supplementary clusters** in 10
  conflict-affected host LGAs (Abadam, Dikwa, Kaga, Kala/Balge, Mafa,
  Marte, Ngala, Nganzai, Makoda, Bursari) — satellite building footprints
  undercount real households there. All 10 sit at 8.51–8.73% realized MoE
  after the fix (target 10%).

## Two subtle bugs fixed 2026-07-15 (both reporting-only, not the delivered sample)

1. `output/strata_level_sampling_frame.csv`'s `target_sample` column must
   be `clusters_target_stage1 * m_used` (PPS strata) or
   `achieved_clusters * m_used` (certainty strata) — **never**
   `sum(target_households)` across a stratum's clusters, which
   double-counts supplementary clusters' own nominal targets. Certainty
   strata cap Stage 2 at `m` per hexagon too, they do NOT fully enumerate
   `N_hh` — verified exactly against all 18 certainty strata.
2. The methodology doc's boosted-strata "before/after" narrative and table
   must be regenerated from the *current* `output/stage2_sampling_frame.csv`
   whenever anything about the boosted strata changes — it previously drifted
   out of sync with a stale, superseded pipeline run and wasn't caught for
   a while.

## Rules for extending or rerunning this pipeline

- **Don't rerun this pipeline casually.** The frame is submitted and
  frozen. If you do rerun it (e.g. to test a fix), everything is
  cached (`cache_rds()`, `rebuild=FALSE` throughout) so a full rerun is
  fast and — if nothing changed — reproduces byte-identical output. Verify
  with `git diff --stat` after any rerun before assuming something changed.
- Downstream projects (`../2_monitoring/`, `../3_analysis/`) should treat
  this project's outputs as **static input files** to copy into their own
  `input_data/`, never as code to `source()` or a live path to read from.
- `reference_data_dir` in `sampling_MSNA_NGA_2026_v3.R` points to
  `C:/Users/JackPHILPOTT/Personal - Documents/GIS` (Google Open Buildings
  source) — genuinely external to this project, unaffected by moving this
  folder, but is a single-machine dependency worth knowing about.
- `build_sampling_workbook.py` (builds the combined Excel workbook, kept
  out of git intentionally due to size) derives its own path from
  `__file__`, so it's portable to future moves.
- Shared functions `draw_cluster()`, `finalize_households()`,
  `merge_repeated_psu_draws()` (`03_household_selection.R`) are reused by
  all three Stage 2 paths (host draw, host reallocation, IDP site
  assignment) — extend the shared schema there rather than duplicating
  logic if adding output columns.
