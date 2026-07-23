# MSNA N-WEC 2026 — Sampling design

## Pending — IDP Stage 2 field-methodology split (not yet decided)

`idp_population_category` ("idps in camp" / "idps in host") was added
2026-07-22 as prep work only. The actual field-methodology split HQ wants
— camp sites use a randomised walk, host-community sites use a household
listing — is **not yet designed or implemented**; `site_radius_m` is still
150m uniformly for every IDP cluster. This is the next piece of work
(paused end of day 2026-07-22 to pick up fresh). Whatever gets decided
will require changes in three places, not just the field protocol itself:
the methodology doc (§3's IDP subsection currently describes one uniform
method), the two IDP maps (`methodology_map_idp_site.png`/`_closeup.png`,
untouched by the 2026-07-22 revision, still depict the single-method
150m-radius approach), and the Stage 2 weighting calculation (currently
`ssu_probability = target_households / DTM-reported households` for every
IDP cluster uniformly — a listing-based method may need a different
formula than a walk-based one). See the end of the 2026-07-22 conversation
for discussion starting points (randomised-walk protocol, listing
protocol, whether 150m radius still fits both, weighting formula impact).

**Status: complete and frozen**, revised three times since initial
submission — see "Revision 2026-07-22", "Revision 2026-07-23", and
"Revision 2026-07-24" below for the current design; the rest of this file
predates those revisions except where updated. Final sampling frame
originally submitted 2026-07-15 (git commit `9510d15`, pushed to
`origin/master`); revised 2026-07-22, 2026-07-23, and 2026-07-24 (see
below) at HQ's/the user's request. This
project moved from `5. GIS\sampling\R Sampling\MSNA N-WEC 2026\` to this
location on 2026-07-16 — if you're picking this up in a fresh session,
prior session memory tied to the old project path may not be attached here
automatically. This file exists so that context isn't lost.

On 2026-07-16 the project root was also cleaned up: superseded/one-off
scripts moved to `archive/`, and all active scripts renamed and moved into
`scripts/` with numbering that reflects workflow order (`00_` shared
functions through `08_`, see table below) rather than the old ad-hoc
`02_`–`05_` + inconsistently-named files. If you see any lingering
reference to an old filename (`sampling_MSNA_NGA_2026_v3.R`,
`02_building_ingestion.R`, etc.) anywhere outside this project, it's stale
— the table below is current.

| Old name | Current name |
|---|---|
| `global_sampling_source.R` | `scripts/00_shared_functions.R` |
| `sampling_MSNA_NGA_2026_v3.R` | `scripts/01_sampling_pipeline_main.R` |
| `02_building_ingestion.R` | `scripts/02_stage2_building_ingestion.R` |
| `03_household_selection.R` | `scripts/03_stage2_household_selection.R` |
| `04_cluster_reallocation.R` | `scripts/04_stage2_cluster_reallocation.R` |
| `05_idp_site_assignment.R` | `scripts/05_stage2_idp_site_assignment.R` |
| `review_final_output.R` | `scripts/06_output_review.R` |
| `build_sampling_workbook.py` | `scripts/07_build_workbook.py` |
| `render_methodology_maps_v2.R` | `scripts/08_render_methodology_maps.R` |
| `run_pipeline_watchdog.ps1` | `scripts/run_pipeline_watchdog.ps1` (unchanged name - runs in parallel, not sequential) |

Scripts are still meant to be **run with the working directory at the
project root** (not from inside `scripts/`) — every `source()`/`readLines()`
call between them uses a `scripts/...` relative path on that assumption.

## What this project is

Stratified two-stage cluster sample for the 2026 MSNA (North-West/East/
Central Nigeria), Non-IDP + IDP populations (see "Revision 2026-07-22" for
why "Non-IDP" and not "host"), ~86,394 total planned interview rows across
5,779 clusters (see "Revision 2026-07-23" for why this is lower than the
~86,670/5,802 figures from the prior revision). See
`msna_methodology_summary_portable.md` in this folder
for the full methodology writeup (also published online as a shareable
document — ask the user for the link if you need to update it, don't
create a new one). As of 2026-07-22, this doc's final section carries only
the region-level summary table, not the full per-LGA breakdown (previously
~700 rows across two tables) — LGA-level detail is provided separately, not
in this document. Don't reintroduce the full per-LGA tables here if
regenerating this section again; `strata_level_sampling_frame.csv` remains
the authoritative row-level source either way.

- **PSU**: hexagon grid cells, PPS-selected (Non-IDP: gridded population;
  IDP: IOM DTM population).
- **SSU — Non-IDP**: Google Open Buildings footprint draw within each
  selected hexagon; zero-building clusters get reallocated to a different
  hexagon in the same stratum.
- **SSU — IDP**: the DTM site's own GPS point directly (no buildings), 150m
  field radius, field-team self-listing. Every IDP record also carries
  `idp_population_category` ("idps in camp" / "idps in host", returnees
  discarded) since 2026-07-22, recorded for a future field-methodology
  split that hasn't been implemented yet — the 150m single-radius method
  is still applied uniformly to both today.
- **Cluster size**: 6 for every Non-IDP and IDP stratum, uniformly, since
  2026-07-22 — any stratum whose achieved sample falls short of its
  `target_sample` gets the minimum number of brand-new supplementary
  clusters (still at m=6) needed to close that specific gap, checked
  across every stratum rather than a hardcoded list. Currently 28 Non-IDP
  strata across 9 states needed this, converging to 9.03–9.27% realized
  MoE. See the methodology doc §4 for the full list and rationale.
- **Certainty-stratum exclusion**: since 2026-07-23, a certainty stratum is
  excluded entirely (zero clusters/interviews) if even full enumeration
  can't project to a 10% MoE — certainty strata have no supplementary-
  cluster option, unlike PPS strata, since every eligible site is already
  included. Currently **all 18** of today's certainty-eligible IDP strata
  fail this check and are excluded — see "Revision 2026-07-23" below.

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
   a while. **Resolved 2026-07-22**: `strata_level_sampling_frame.csv` is
   now generated by tracked code (see below), removing the untracked/ad hoc
   step that let this drift happen in the first place.

## Revision 2026-07-22 — HQ-approved design changes

Three changes, implemented together and requiring one full pipeline
rerun (not the trivial byte-identical kind — this genuinely changed which
clusters get selected for ~28 strata):

1. **MoE correction mechanism replaced.** The old approach hardcoded a
   list of 10 conflict-affected LGAs and blanket-raised their cluster size
   from m=6 to m=7 (+421 interviews for those 10). This over-corrected:
   raising `m` also raises the design effect (`1+(m-1)*ICC`), so part of
   every extra interview bought this way is spent servicing worse DEFF,
   not shrinking MoE. Replaced with: draw every Non-IDP stratum uniformly
   at m=6, then check `achieved_sample < target_sample` (already the
   correct, buffer-inclusive trigger — `target_sample` already encodes the
   10% MoE design target plus the 10% attrition buffer) across **every**
   stratum, and add the minimum number of new supplementary clusters
   (still m=6) needed to close each one's own gap. A raw MoE-percentage
   threshold was considered and rejected: 303 of 323 Non-IDP strata that
   already hit target sit at 9.24–9.31% purely from the buffer's own
   rounding, so a percentage cutoff near there either false-flags on-target
   strata or just rediscovers the `achieved < target` check. Result: 28
   strata corrected (not the original 10) for 254 total extra interviews,
   converging to 9.03–9.27% realized MoE — see methodology doc §4.
   `realized_moe()` (in `01_sampling_pipeline_main.R`, next to
   `build_sampling_plan()`) is used for **reporting** this figure, not as
   the correction trigger.
2. **`idp_population_category` added.** New column on every IDP record,
   derived from IOM DTM's raw `Population Category` field via
   `classify_idp_population_category()` — "idps in camp" / "idps in host"
   (returnees still discarded, unchanged). Prep work for a future
   field-methodology split (camp = randomised walk, host community =
   household listing) that is **not implemented yet** — `site_radius_m`
   stays 150m for all IDP clusters today.
3. **`pop_type` "host" → "non_idp" throughout**, plus all user-facing
   "Host" → "Non-IDP" (methodology doc, workbook, map labels). Framing as
   IDP/Non-IDP rather than IDP/host avoids the ambiguity that "host" also
   means "the community an IDP lives embedded within" in humanitarian
   usage (one of the IDP Population Category values is literally "in a
   host community"). This changes `cluster_id`/`strata_id`/`uuid_hex_pop`
   values too, since they're derived from `pop_type` at runtime — no
   separate code change needed there, but it means every ID in the frame
   changed shape (`host_NG...` → `non_idp_NG...`).

**Gotcha hit during this revision, worth knowing before ever renaming
`pop_type` again**: `load_building_footprints()`
(`02_stage2_building_ingestion.R`) bakes each building's assigned
`uuid_hex_pop` into its own cache at `output/cache/buildings/` — a cache
whose *directory name* didn't change and so wasn't obviously invalidated
by the rename, but whose *contents* were, causing ~4,548 clusters to
silently show zero eligible buildings on the first rerun attempt (joins
against `uuid_hex_pop` failed because the cache still had the old
`host_...` prefix baked in). Fixed by clearing `output/cache/buildings/`
entirely and letting it rebuild (it's resumable via
`nga_buildings_part*_progress.rds` checkpoint files if interrupted, e.g.
by power loss mid-run — just rerun the same script, don't delete the
partial cache). Any future change to how `pop_type`/`uuid_hex_pop` values
are constructed must clear this cache too, not just caches whose own path
depends on the old naming.

`strata_level_sampling_frame.csv` generation (including `strata_id` and
`idp_population_category`-adjacent columns) is now tracked code in
`01_sampling_pipeline_main.R`, right after the Stage 2 output writes —
this closes the drift gap bug #2 below used to describe; there is no
longer an untracked/ad hoc step producing this file.

## Revision 2026-07-23 — certainty-stratum exclusion

One HQ-approved change: certainty strata (IDP populations too small to
sample from meaningfully, so every eligible site is enumerated instead —
see "What this project is" above and methodology doc §2) that still can't
project to the assessment's 10% MoE target even at full enumeration are now
**excluded from the sample entirely** — zero clusters, zero interviews —
rather than fielded and reported as indicative, which is what the design
did before today. Rationale: unlike a PPS stratum falling short of target,
a certainty stratum has no supplementary-cluster option (every eligible
site is already included, so there's nowhere left to draw an additional
cluster from); HQ judged the field effort of visiting these sites not worth
the indicative-only data it would produce.

**Mechanism** (`scripts/01_sampling_pipeline_main.R`, right after
`idp_sampling <- build_sampling_plan(hex_grid_idp)`, ~line 986): for every
certainty stratum, `realized_moe()` (already used for reporting, see
"Revision 2026-07-22" above) is reused to project the MoE at the maximum
achievable sample (`n_hex * m` — every eligible site, capped at `m`
households each). Strata projecting above 10% have their hexagons dropped
from `idp_sampling$sampling_frame` via `anti_join()` **before**
`select_pps_clusters()` runs, so no code changes were needed anywhere
downstream (Stage 2, weighting, output writes) — those strata simply never
enter cluster selection and their `achieved_clusters`/`achieved_sample`
naturally coalesce to 0 in `strata_level_sampling_frame.csv`'s existing
left-join logic. The same check is independently re-derived, generically,
when that CSV is built (`excluded_infeasible` = `certainty_stratum &
projected_moe_pct > 10`, using only that file's own columns) rather than
threading the early filter's result all the way through — so the exclusion
decision is auditable directly from the delivered CSV, not hidden state.
This rule is **not hardcoded to IDP or to today's 18 strata** — it runs
generically off `certainty_stratum`, so a future DTM data refresh growing
any of these LGAs' population enough to pass the check would make it
eligible again (as certainty or PPS) with no design change required.

**Result on the current population data: all 18** of today's
certainty-eligible strata (all IDP; there are no Non-IDP certainty strata)
fail the check and are excluded — none remain in the achieved sample. This
removes 362 DTM-recorded IDP households / 23 sites / 138 interviews (276
planned rows incl. reserves) across 4 states (14 in Kano, 2 in Niger, 1
each in Kaduna and Kebbi) — dropping the total achieved sample from 52,384
to 52,246 and total clusters from 5,802 to 5,779. **Kebbi State loses IDP
coverage entirely** (Gwandu was its only IDP stratum) — no IDP estimate of
any kind is possible for Kebbi under this design. Kano/Niger/Kaduna retain
partial IDP coverage (16/30, 11/13, 21/22 LGAs respectively). Full detail,
the affected-LGA table, and reporting guidance: methodology doc §5
(rewritten from "Precision limitations in certainty strata" to "Excluded
strata: the certainty-stratum coverage gap") and §6 (weighting coverage-gap
note).

**Gotcha hit during this revision**: `select_stage2_idp_sites()`
(`05_stage2_idp_site_assignment.R`) caches its full result at
`output/cache/idp_sites/stage2_idp_sites.rds` and is called with
`rebuild = FALSE` — unlike the Stage-1 hex-grid caches, this cache has
**no dependency on the exclusion filter's inputs**, so a stale cache from
before this change would silently keep serving the old (unfiltered)
IDP site assignment on rerun. Deleted before the 2026-07-23 rerun; delete
`output/cache/idp_sites/stage2_idp_sites.rds` again before any future
rerun that changes which IDP hexagons reach `select_stage2_idp_sites()`
(this exclusion filter, or anything upstream of it).

New `strata_level_sampling_frame.csv` columns: `excluded_infeasible`
(bool) and `projected_moe_pct` (certainty strata only, NA for PPS strata —
the figure `excluded_infeasible` is derived from). `07_build_workbook.py`
updated to type, width, highlight (red), and document both.

## Revision 2026-07-24 — dropped `uuid`, deferred weighting columns/methodology

Two changes, found during a full pre-resubmission diagnostic sweep and
made at the user's request; neither reruns cluster/household selection
(no caches invalidated, no change to which locations are sampled) — both
are export-schema-only, applied to the final `stage2_households` object
right before the CSV/gpkg writes in `01_sampling_pipeline_main.R`
(`stage2_households_export`), leaving the underlying `stage2_households`
object itself untouched.

1. **Dropped the `uuid` column** from `stage2_sampling_frame*.csv/.gpkg`
   and the workbook. Found during the diagnostic sweep to not contain what
   it claimed to (see the 2026-07-23→24 commit history): it's actually the
   hexagon's local, non-globally-unique index number (`uuid = paste0("hex_",
   row_number())`, set at line ~447 — this internal field still exists and
   is still used to build `uuid_hex`, just no longer exported on its own).
   The real per-record location identifiers were already present in their
   own columns (`building_id` for Non-IDP, `iom_site_id` for IDP,
   `uuid_hex` for the hexagon) and are unaffected.
2. **Dropped `psu_probability`, `ssu_probability`, `base_weight`** from the
   same export files, and genericized methodology doc §6 from a detailed
   weighting-mechanics writeup to a brief forward-looking statement. Reason:
   the IDP Stage 2 field-methodology decision (see "Pending" note at the
   top of this file — camp vs. host-community, listing vs. randomised walk)
   is still unresolved and will change the `ssu_probability` formula for
   IDP records specifically; publishing exact weighting mechanics now would
   describe a formula that's about to change. The actual probability
   computation is untouched internally (still needed for the supplementary-
   cluster recompute logic and any future interactive use) — only the
   exported columns and the doc's level of detail changed. Weighting
   columns and a full methodology writeup are expected to return once the
   field-methodology decision lands and actual data collection outcomes are
   available to weight against.

`06_output_review.R`'s `=== WEIGHTS ===` section was removed (read directly
from the now-column-stripped CSV, would otherwise error). `07_build_workbook.py`'s
"Design and weighting" SF_DEFS group renamed to "Design".

## Rules for extending or rerunning this pipeline

- **Don't rerun this pipeline casually.** The frame is submitted and
  frozen. If you do rerun it (e.g. to test a fix), everything is
  cached (`cache_rds()`, `rebuild=FALSE` throughout) so a full rerun is
  fast and — if nothing changed — reproduces byte-identical output. Verify
  with `git diff --stat` after any rerun before assuming something changed.
  This does NOT hold if you're changing `pop_type`/`uuid_hex_pop`
  construction — see the buildings-cache gotcha in "Revision 2026-07-22"
  above; a stale `output/cache/buildings/` cache silently breaks the join
  instead of erroring cleanly.
- Downstream projects (`../2_monitoring/`, `../3_analysis/`) should treat
  this project's outputs as **static input files** to copy into their own
  `input_data/`, never as code to `source()` or a live path to read from.
- `reference_data_dir` in `scripts/01_sampling_pipeline_main.R` points to
  `C:/Users/JackPHILPOTT/Personal - Documents/GIS` (Google Open Buildings
  source) — genuinely external to this project, unaffected by moving this
  folder, but is a single-machine dependency worth knowing about.
- `scripts/07_build_workbook.py` (builds the combined Excel workbook, kept
  out of git intentionally due to size) derives its own path from
  `__file__`, so it's portable to future moves.
- Shared functions `draw_cluster()`, `finalize_households()`,
  `merge_repeated_psu_draws()` (`scripts/03_stage2_household_selection.R`)
  are reused by all three Stage 2 paths (Non-IDP draw, Non-IDP
  reallocation, IDP site assignment) — extend the shared schema there
  rather than duplicating logic if adding output columns.
