# MSNA N-WEC 2026 — Sampling design

## IDP Stage 2 field-methodology split — DECIDED 2026-07-28

`idp_population_category` ("idps in camp" / "idps in host") was added
2026-07-22 as prep work; the field-methodology split it was prepping for
was finalised 2026-07-28, in the ToR (not via this codebase — the decision
was made in a separate Claude web session working from the ToR document,
then relayed here for the methodology doc/pipeline to catch up to). See
"Revision 2026-07-28" below for the full mechanism and what has/hasn't
been updated in this codebase yet — notably, **`site_radius_m` in the
delivered sampling frame is still 150m uniformly for every IDP cluster**,
which is now stale relative to the finalised design (in-camp Tier 1 is
bounded by "visible camp extent," not a fixed radius at all; host-community
listing was never radius-bound). Regenerating this column is a pipeline
rerun and has **not** been done — treat any further pipeline changes here
as requiring explicit user sign-off first, per the existing "don't rerun
casually" rule below, and flag this staleness explicitly if asked to
touch Stage 2 IDP code again.

**Status: complete and frozen**, revised five times since initial
submission — see "Revision 2026-07-22", "Revision 2026-07-23",
"Revision 2026-07-24", "Revision 2026-07-28", and "Revision 2026-07-30"
below for the current design; the rest of this file predates those
revisions except where updated. Final sampling frame originally submitted
2026-07-15 (git commit `9510d15`, pushed to `origin/master`); revised
2026-07-22, 2026-07-23, 2026-07-24, 2026-07-28, and 2026-07-30 (see below)
at HQ's/the user's request. This
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
- **SSU — IDP**: the DTM site's own GPS point directly (no buildings).
  Every IDP record also carries `idp_population_category` ("idps in camp" /
  "idps in host", returnees discarded) since 2026-07-22. As of 2026-07-28
  this now drives two different field methods (see "Revision 2026-07-28"
  below): in-camp sites get a two-tier list-then-RNG / fallback-walk
  method, host-community sites get a chief/head-of-settlement listing
  bounded by local social recognition. **Not yet reflected in the pipeline
  or delivered CSV** — `site_radius_m` is still 150m for every IDP row,
  stale relative to this decision; this is a methodology-doc/ToR-alignment
  update only so far, not a pipeline rerun.
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

## Revision 2026-07-28 — IDP Stage 2 field-methodology finalised (ToR alignment, no pipeline rerun)

The IDP field-methodology split flagged as pending since 2026-07-22 was
decided **in the ToR itself**, worked out in a separate Claude web session
against the ToR document (not in this codebase) and relayed here as a
decisions-summary doc plus the full ToR PDF, to bring the methodology doc
into alignment. This revision updates `msna_methodology_summary_portable.md`
(§1, §3, §4, §6) to match the ToR's language. **It does not touch the
pipeline, the delivered CSVs, or `site_radius_m`** — see the "not yet done"
list at the end of this section.

**The decision, in brief** (full detail: methodology doc §3, "IDP clusters:
site-based household selection"):

1. **In-camp sites — two-tier, list-then-RNG with a pre-assigned fallback.**
   Tier 1 (always attempted first): full household listing at the DTM GPS
   point, bounded by the *visible extent of the camp* (not a fixed radius —
   this replaces the old 150m-for-everyone approach entirely), entered into
   Kobo for automatic RNG selection. Tier 2 (fallback, triggered by a field
   team's own on-arrival judgement that Tier 1 isn't feasible — **not** a
   published numeric threshold): a random walk with a **pre-assigned**
   bearing (from a randomised bearing table, not chosen in the field) and a
   fixed interval — deliberately *not* a literal on-the-spot "pen-drop"
   method (that's Mali MSNA's approach, explicitly rejected here — Mali's
   own docs downgrade IDP data to "quasi-representative" as a result, and
   preserving full representativity was the point of avoiding it). The
   walk interval (*n*) and reserve-continuation count are **still
   placeholders in the ToR** (`[interval to be confirmed with field
   operations]`) — do not invent a number if asked to build anything
   depending on it.
2. **Backup GPS points (this is the task from earlier today —
   `scripts/analysis_idp_camp_backup_points_part{1,2}.R`,
   `output/analysis_idp_camp_backup_points/`).** For a subset of the
   largest in-camp sites only, a second randomised GPS point exists for
   use *only if* Tier 2 triggers — addresses the risk that the DTM point is
   a registration desk, not a camp centroid, which would bias a walk
   starting from it. Generated via satellite-imagery extent delineation
   (9 of 15 camps) or a fixed-radius fallback where delineation wasn't
   confident (6 of 15). **The specific caseload threshold used to select
   which camps got this treatment (>2,000hh in this pass) is an internal
   working parameter — the ToR deliberately does NOT publish it as a
   design rule**, since field teams' in-the-moment Tier 2 trigger is
   judgement-based, not threshold-based. Don't write a specific numeric
   threshold into ToR-facing text as if it were a fixed rule; the
   methodology doc follows this same restraint (states the mechanism,
   points to the dataset for current-pass specifics, doesn't cite ">2,000").
3. **Host-community sites — chief/head-of-settlement listing, not a
   radius.** No GPS-radius method at all for this group. Field teams ask
   the site's chief/head of settlement for a full listing bounded by local
   social recognition of "belonging to this settlement"; where a settlement
   has multiple named sub-areas, a contact within each is asked and the
   lists are pooled — one uniform instruction, not a separate rule for
   "urban" vs. "rural" sites. This was informed by the host-community
   feasibility review already done earlier today (density + caseload
   across all 1,099 sites, `output/analysis_idp_host_feasibility/`) — but
   note the ToR uses **two different combined thresholds for two different
   purposes**, not the one this repo's earlier artifact emphasised:
   - **406/1,099 (37%)** at the *inclusive* pairing (p90 density **OR**
     150+hh) — used in the ToR only as *context*, to show the variation is
     too continuous to define a clean "urban" subgroup. Not an operational
     trigger.
   - **18/1,099** at the *strict* pairing (p95 density **AND** 200+hh,
     both required — note: AND, not OR) — this is the figure actually used
     operationally, for flagging sites where field coordinators should give
     closer supervision and a larger reserve list. Same method, more
     oversight — not a different method.
   Both figures were already computed correctly in this repo's earlier
   `idp_host_community_feasibility_flags.csv` (`combined_flag_default` =
   the 406 OR-pairing; `combined_flag_both_p95_200` = the 18 AND-pairing) —
   no recomputation needed, just correct citation.
4. **CCCM/B.R.a.Ve registration data — explicitly not used.** Considered
   and rejected as a substitute for field listing: CCCM presence is
   Borno/Adamawa-only (minimal in Yobe, none in NW/NC), the formal-camp
   landscape is shrinking (Borno directive to close all official camps),
   and data-sharing terms weren't confirmed. Survives only as an informal,
   no-infrastructure field check ("does a list already exist?") — not
   something to build pipeline support for.

**Terminology to use consistently** (methodology doc, any future data
dictionary, any code comments): "Tier 1 / Tier 2" or "primary listing /
fallback walk" — never "pen-drop" (that's Mali's method, which this design
deliberately differs from). "In-camp" / "host community" (matching DTM's
own `Population Category` values) — never "on-site" / "off-site" (also
Mali terminology).

**Not yet done — flag before assuming any of this is implemented in data**:
- `site_radius_m` is still 150m for every IDP row in the delivered CSV/gpkg
  — stale relative to the finalised design. No rerun has happened.
- No `tier2_fallback_used` (or similar) flag exists yet in the data
  dictionary or output schema — the ToR narrative requires one exist before
  fieldwork, per the Tier 2 limitation, but it hasn't been added.
- **Update 2026-07-31**: the two outdated IDP example maps have been
  replaced with four new maps — "IDP in camp" and "IDP in host" (each
  wide + close-up) — built from the Claude-web prompt the user eventually
  supplied (the Word-comment text referenced below), then revised twice
  against direct user feedback. `scripts/analysis_idp_tor_maps_part1.R`
  renders IDP-in-camp (hexagon boundary, DTM point, backup point);
  `_part2.R` renders IDP-in-host (hexagon boundary, DTM point, hand-
  delineated illustrative boundary). Output:
  `output/images/methodology_map_idp_{camp,host}_v2.png` + `_closeup.png`
  (old `methodology_map_idp_site.png`/`_closeup.png` deleted, untracked).
  Style matches the real Figure 4 convention (in-image bold title + grey
  subtitle, legend along the bottom) — not Figure 1's boxed side-panel
  convention, which the pasted prompt's wording conflated with Figure 4's.
  **This is the current draft pending final user sign-off — not yet
  committed to git.**
  - **IDP-in-camp site: `idp_NG008013_17`** (Shuwari-Kaleri Housing Unit
    Camp, Jere, Borno) — the original pick, kept after all. Its Stage 1
    hexagon is genuinely adm2-boundary-clipped (15 vertices, 17.2km²,
    confirmed directly against `hex_access`, not a plotting bug), so it
    renders as an irregular, non-hexagonal shape — the map's subtitle now
    says so explicitly. Two clean-hexagon alternatives were tried instead
    (`idp_NG008011_8` Reception/Transit Camp, Gwoza; then `idp_NG008003_1`
    Gssss Camp Bama and `idp_NG008019_1` GGSS Mafa) but the user preferred
    reverting: Shuwari-Kaleri's camp visually fills almost the whole framed
    hexagon with very little empty space, which none of the clean-hex
    alternatives matched (Reception/Transit's camp sits in one small corner
    of its hexagon; Bama's camp blends into the edge of Bama town at this
    zoom and its 35,519hh caseload looks like a data outlier; Mafa's camp
    is contiguous with surrounding town on one side). **Net decision: an
    intact hexagon is not worth a materially worse illustration — prefer
    site quality over hexagon regularity for this figure.**
  - **IDP-in-host site: `idp_NG021005_2`** (Rugar Tsara, Bindawa, Katsina),
    confirmed as the right site by the user. Found after four rounds of
    candidates: (1) `idp_NG002017_1` Anguwan Tula — user rejected it, the
    traced boundary didn't visibly follow a real edge; (2) four more of the
    18 density+caseload dual-flagged sites, smaller by caseload but still
    high-density by construction — all sat in continuous urban fabric with
    no visible boundary at all; (3) four near-zero-density rural sites —
    imagery too coarse/low-res to show any structures at all; (4) a
    moderate-density band (300–2,000 people/km², deliberately outside the
    18-site subset) — Rugar Tsara showed a small, tight, regular settlement
    block clearly separated from surrounding farmland, a genuinely
    delineable case. The boundary is a hand-specified irregular polygon
    (bearing/distance vertices from the DTM point, seeded jitter for
    organic shape) — explicitly not derived from footprint/imagery
    analysis, matching the actual field method (no GPS radius or boundary
    of any kind behind it in the field).
    - **v1→v2 fixes, both per direct user feedback**: (a) the wide view now
      shows the Stage 1 hexagon too, at the same zoomed-out extent as the
      IDP-in-camp wide view, not just a tight crop around the illustrative
      boundary; (b) the illustrative boundary rendered ~50-90m too far
      north relative to the visible rooftop cluster in v1 (confirmed by
      direct pixel comparison against the rendered PNG — the boundary's
      hand-drawn shape was correct, this was a rendering/estimation offset,
      not a re-draw). Likely cause: the boundary's bearing/distance
      vertices were originally eyeballed off a non-square candidate review
      image (7in × 7.5in rendered onto a squarish geographic extent, which
      can letterbox unevenly and throw off a pixel-based read). Fixed with
      an empirical constant `SHIFT_SOUTH_M = 85` (tuned by rendering 75m
      and 100m test versions and comparing directly against the basemap),
      not by re-deriving vertices from the flawed source image. The DTM
      point and hexagon are both in the map legend now (shares one combined
      legend with the illustrative boundary, matching IDP-in-camp's
      convention).
  - Scratch diagnostic/candidate-search scripts used to reach these picks
    (`diag_hex_shape{2,3}.R`, `analysis_idp_tor_maps_part1{b,c,d}.R`,
    `tmp_host_closeup_iter.R`, and all `candidate*`/`test_shift_*` review
    images) have been deleted — the reasoning is captured here instead.
    `part1.R`/`part2.R` are the only scripts needed to reproduce the final
    four images.
  - **Still open**: Section 3's feasibility-review paragraph says the 18
    dual-flagged sites are "concentrated in Zamfara, Benue, Borno and
    Adamawa States" — re-checking the actual list found Borno, Kaduna,
    Adamawa, Zamfara, Katsina, and Yobe (no Benue; Kaduna missing from the
    doc's sentence). User confirmed this should be fixed next time Section
    3 is touched, not immediately.
- Weighting formula/columns remain deferred (per Revision 2026-07-24) —
  now additionally blocked on the Tier 2 interval/reserve-count still
  being placeholders, not just the broad method choice.

## Revision 2026-07-30 — partner coverage layer (additive, operational only) + two terminology decisions

**Partner coverage layer.** A new, separate, additive layer on top of the
design frame - which LGAs a partner has actually confirmed they can cover.
Does **not** touch the design frame's own strata, sample sizes, or the
52,246-interview Section 7 total, which remains correct as "what the
approved design calls for." Scripts:
`scripts/analysis_partner_coverage.py` (matching + FULL/WORKING frame
generation) and `scripts/build_partner_coverage_workbook.py` (builds the
v2 workbook from the first script's pickled state). Source:
`input_data/boundaries/partner_coverage/Partnerscoverage.xlsx` (3 sheets,
NE/NW/NC, one row per LGA, a `COUNT` column - no adm2 pcodes, so matching
is by normalized state+LGA name against the frame's own pcodes).

Result: 269 of 323 LGAs matched cleanly by name; 10 matched via a
manually-reviewed name-variant reconciliation (hardcoded dict in the
script, e.g. "Otukpo"→Oturkpo, "Munya"→Muya - typos/spelling/hyphenation
differences, confirmed correct by user 2026-07-30); all 44 Kano State LGAs
were entirely absent from the coverage file (not a naming issue - Kano
just isn't in the source at all) and are **confirmed treated as
`not_covered`** (user, 2026-07-30: "Kano is a completely excluded state,
no partner is wanting to cover it") - not left as an unresolved/unknown
status. `coverage_status` ("covered"/"not_covered") and `exclusion_reason`
("none", or `partner_coverage_declined` and/or
`certainty_stratum_below_moe_threshold`, joined with "; ") were added to
both Sampling Frame and Strata-Level Summary. FULL frame = original +
these 2 columns, unchanged otherwise, fully re-derivable if coverage is
reconfirmed later. WORKING frame = FULL filtered to `coverage_status ==
"covered" & exclusion_reason == "none"`.

National: 52,246 (design) → 31,051 (WORKING) interviews, 323 → 176 LGAs.
Cross-verified exactly: WORKING stage2 primary-row count == strata-level
WORKING achieved_sample sum, both = 31,051. NC is hit hardest (99→18
LGAs); NE is near-complete (65→64); NW loses 65 of 159 (21 explicitly
declined + all 44 Kano). **17** LGAs are excluded for both coverage and
the small-population reason at once (corrected 2026-07-31 — see "Revision
2026-07-31" below; the original "3 LGAs" figure only counted Niger/Katcha,
Niger/Lapai, Kaduna/Markafi and missed all 14 Kano LGAs, whose IDP strata
were already certainty-excluded before Kano was separately folded into
"not covered"). Full detail, per-LGA: `output/analysis_partner_coverage/`
- `NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx` (README + Strata-Level
Summary FULL + Coverage Summary), `NGA_MSNA_2026_coverage_summary_v2.csv`
(the clean per-LGA table), and FULL/WORKING CSVs at both strata and
household level. Methodology doc §8 documents this in full.

**Terminology decision 1 — 150m radius fully removed from the methodology
doc.** Per explicit user instruction (2026-07-30): the old single-radius
IDP method was never actually presented to the ToR audience and referring
to it risked being "quietly carried through to the main working
documents." All historical "this replaces the old 150m method" framing
was stripped from `msna_methodology_summary_portable.md` (§3's IDP
subsections, the PSU-attribution limitation, both IDP map placeholders) -
the doc now just describes the current two-tier/host-community design
directly, with no comparison to what preceded it. **This is a
documentation-only change** - the code/data (`site_radius_m` column,
still 150m per the "not yet done" list above) and CLAUDE.md's own
technical history are untouched and should stay untouched; this decision
is about the external-facing methodology narrative, not the pipeline.

**Terminology decision 2 — "certainty stratum" de-emphasized in the
methodology doc, kept in code/data.** User's stated reasoning (2026-07-30):
"this is an old term ... for a step in the design which we aren't
carrying forward." Checked this precisely before touching anything: the
mechanism is **not** deprecated (`build_sampling_plan()`'s
`certainty_threshold <- m * 6` is live, generic code, applies to every
stratum), but the *outcome* genuinely is what the user described - **all
18 certainty-eligible strata are currently excluded (Revision 2026-07-23),
so zero strata are actually fielded via full inclusion today.** Given
that, user chose to de-emphasize rather than keep explaining the
mechanism as a named step: `msna_methodology_summary_portable.md` no
longer uses "certainty stratum"/"certainty-eligible"/"sampled with
certainty" anywhere in prose (§2, §4, §5's title and body, §7's footnote,
§8) - rewritten as plain "small-population stratum" / "small enough to
qualify for full inclusion" language throughout, describing the same
facts without the named term. **One deliberate exception**: §8 keeps the
literal `certainty_stratum_below_moe_threshold` `exclusion_reason` value
as-is (with a one-line note that the field name is retained from the
data build) - **do not rename this CSV/workbook field value** to match
the doc's prose; that would require rerunning the partner-coverage join
and regenerating every output above. If asked to touch certainty-stratum
code/data again, the mechanism itself is unchanged and still called
`certainty_stratum`/`certainty_threshold`/`selection_type` in the
pipeline (01_sampling_pipeline_main.R) and in this file - only the
polished methodology document's prose changed.

**Output cleanup (2026-07-30).** Removed from local `output/` (none of
this was git-tracked, so no history was affected): `output/_archive/`
(188MB of pre-restructuring, host-terminology, June/early-July exploratory
data - fully obsolete); `output/analysis_idp_host_feasibility/`'s
`chart_data.json`/`flagged_rows.html`/`.rds` (intermediates behind the
already-published standalone HTML artifact, not needed going forward);
`output/analysis_idp_camp_backup_points/camp_review_images/` (14MB of the
15 satellite-review PNGs + footprint RDS files used during visual
delineation - the actual decisions are captured in
`manual_visual_review.csv`, kept) and its `part1_state.rds` handoff
pickle; `output/analysis_partner_coverage/_pipeline_state.pkl` (same kind
of script-to-script handoff artifact). `output/cache/` (234MB, pipeline
recompute caches) was **not** touched - still load-bearing for fast
reruns. `output/images/` (5 current methodology map PNGs) was **not**
touched - all current.

## Revision 2026-07-31 — LGA-level partner-coverage maps for the main ToR methodology section

Six exploratory variants were built first (`scripts/analysis_coverage_map.R`,
now deleted); the user picked two to take forward and requested a further
round of styling/content changes on both. Final state below.

**Two final scripts**, each standalone (not part of the numbered 00-08
pipeline):
- `scripts/analysis_coverage_map1.R` → `coverage_map1_partner_coverage.png`
  — plain binary partner-coverage map (the old "v2"). Lightweight load:
  sources `01_sampling_pipeline_main.R` only up to `NGA_shapes_all_cleaned`
  (~line 294), no Stage 1/hex/worldpop needed.
- `scripts/analysis_coverage_map2.R` → `coverage_map2_full_design.png` —
  the main, comprehensive sampling-design map (the old "v5 combined").
  Heavy load: sources up to `selected_clusters` (~line 1236) for the actual
  Stage 1 hexagon geometries, which also picks up `restricted`/
  `accessible_area` (the border-buffer/FACT-inaccessible layer) at no
  extra cost.

Both mirror `methodology_map_overview_legend_inset.png` (Figure 1)'s
extent/style: same 14-state/neighbouring-country view, boxed legend-inset
panel bottom-right, no in-image title. `ggnewscale` isn't installed —
anywhere a plot needs two fill scales at once, the main map layer uses a
single precomputed hex-colour column + `scale_fill_identity()` instead; the
small legend-extraction plots (`cowplot::get_legend()`, matching Figure 1's
own pattern) each keep their own natural scale so legends still render
with proper labels.

**Both maps, per user feedback 2026-07-31**, now also show:
- A **regional boundary** (NC/NE/NW, dissolved from a hardcoded 14-state→
  region lookup — simpler/safer than depending on a region column existing
  on the raw admin1 shapefile) styled like the old state layer (solid navy,
  medium weight, `#1B2A4A`).
- A **state boundary**, now thin grey (`grey55`, 0.3 linewidth) so it
  doesn't compete visually with the region layer.
- A **Nigeria national boundary** (from `admin0_wa_proj`, filtered to
  `adm0_pcode == "NG"`), solid near-black, thickest of the three
  (linewidth 1.0).
- All three boundary layers in the legend, as one combined `linetype`
  scale with `override.aes` (same technique Figure 1 already used for its
  "Assessment states (14)" entry).

**Map 1** (`coverage_map1_partner_coverage.png`) — binary sampled (green)
/ excluded (grey), plus the boundary layers above. Legend whitespace
tightened (boxed panel height reduced, `legend.margin`/`legend.spacing.y`
minimised throughout).

**Map 2** (`coverage_map2_full_design.png`) — the bigger rework:
- Legend title for the fill scale: "Achieved sample per LGA (WORKING)" →
  "Planned interviews per hex" (renamed once to plain "Planned sample",
  then the whole metric moved from LGA-level to hex-level, so the label
  tracks the granularity change).
- **LGA-level colour-by-sample-count replaced with actual Stage 1
  hexagons** — the ~3,300 selected clusters themselves, not a whole-LGA
  wash, per the user's own reasoning ("hexagon is the lowest granular
  information we have"). Restricted to `(adm2_pcode, pop_type)` pairs in
  the WORKING frame; a hex's fill reflects total planned households
  there — `m_used`, summed across repeat systematic-PPS draws of the same
  hex (`selected_clusters`' `uuid_hex_pop`, deduplicated).
  - **Finding, flagged but not investigated further**: 676 of 3,302
    selected hexes (~20%) were drawn more than once by the systematic PPS
    draw (up to 17×, 102 households, in very-small-population strata) —
    far more common than expected. One legend swatch per distinct value
    would have meant 16+ near-identical dark-green rows, so all repeats
    are collapsed into one "12+ households (hex selected more than once)"
    category against a plain "6 households (single draw)" baseline.
  - **Separate finding, RESOLVED 2026-07-31 (user-confirmed)**: every
    single selected hex nationally has `m_used == 6` — none has
    `m_used == 7`. The map was originally going to distinguish "6
    households (standard stratum)" vs "7 households (boosted stratum)"
    per the user's own framing, but that turned out to be stale: the
    m=6→7 boost for a hand-picked list of 10 conflict-affected LGAs was
    **superseded 2026-07-22** by the current minimal-supplementary-cluster
    approach (28 strata topped up at the standard m=6 instead — see
    Section 4 of the methodology doc, "Non-IDP strata with a below-target
    shortfall," which already documents this supersession accurately and
    needed no correction). `m_used == 7` not appearing anywhere is exactly
    what that means in practice — confirmed correct, not a data bug. The
    "Change 1" plan file (`snappy-petting-bird.md`) initially misled the
    investigation by describing this as an *unexecuted* future change
    ("replaces the m=6→7 blanket boost") — it had, in fact, already been
    executed and delivered; that plan file is stale/superseded and should
    not be treated as representing pending work. Legend correctly ships
    with just "6 households (single draw)" / "12+ households (hex
    selected more than once)" — no boosted-stratum category exists to
    show.
- **Excluded areas simplified to exactly two categories**, replacing the
  old 3-way (coverage-only / certainty-only / both) split:
  - **"Excluded: no partner coverage"** (grey) — whole LGA has zero
    working hexes because its Non-IDP stratum isn't covered, and it isn't
    otherwise design-excluded.
  - **"Excluded: design effect"** (`#8B4A4A`) — covers two structurally
    different but conceptually related things under one colour: (a) LGAs
    whose exclusion is structural rather than operational — not covered
    AND its IDP stratum was already certainty-excluded under Annex 1.5, so
    it would have been excluded regardless of partner coverage (the same
    17 LGAs from Revision 2026-07-31b, rendered as a whole-LGA fill); and
    (b) the geographic border-buffer/FACT-inaccessible zone
    (`restricted`/`accessible_area`, clipped to the 14 focus states),
    drawn as a semi-transparent overlay in the same colour, mirroring how
    `methodology_map_overview` shows it. These are geometrically distinct
    layers (whole-LGA fill vs. a buffer-zone overlay that mostly cuts
    *within* otherwise-sampled LGAs, sub-LGA/admin-3 level) but share one
    legend swatch, per the user's explicit request to simplify to two
    exclusion categories total.

**Cleanup**: the six exploratory variants and their script
(`analysis_coverage_map.R`, `coverage_v{1,2,3,4a,4b,5}_*.png`) were
deleted — the two final maps and scripts above are the only ones kept.
**Awaiting the user's final review — nothing committed to git.**

## Revision 2026-07-31b — corrected the Section 8 "overlap between exclusion reasons" count (3 → 17)

The methodology doc's Section 8 previously said 3 LGAs are excluded under
both `partner_coverage_declined` and `certainty_stratum_below_moe_threshold`
at once (Niger/Katcha, Niger/Lapai, Kaduna/Markafi). Recomputed directly
from `coverage_status`/`excluded_infeasible` in
`NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv` (bypassing the
existing `exclusion_reason`/summary-table logic entirely, precisely to
check it independently): the correct count is **17**, all IDP strata,
zero Non-IDP — the original 3, plus all 14 Kano LGAs (Bebeji, Dambatta,
Dawakin Kudu, Dawakin Tofa, Gwale, Gwarzo, Kunchi, Makoda, Minjibir, Rimin
Gado, Rogo, Shanono, Tofa, Warawa), whose IDP strata were already
certainty-excluded in the original design and which were separately
confirmed `not_covered` when Kano was folded in wholesale on 2026-07-30
(Revision 2026-07-30 above). The "3 LGAs" figure was written before that
Kano decision and never recomputed against it.

Also checked (per user request) whether this reflects a real code bug —
it doesn't. `exclusion_reason_for()` in `analysis_partner_coverage.py`
already joins both reasons with `"; "` when both apply (no folding/
collapsing), and the per-region LGA-counts table
(`region_lga_counts`/lines ~406-424 of that script) was *always*
documented in its own print statement as "not mutually exclusive," a
caveat the methodology doc already carries in prose. The apparent
arithmetic mismatch a user found (region LGA-count columns not summing to
the region total) is expected, intentional behaviour, not a regression —
confirmed by an independent from-scratch mutually-exclusive 4-category
recount (covered-clean / covered-but-certainty-excluded /
not-covered-clean / not-covered-and-certainty-excluded) built directly
from raw flags, which sums exactly to the design LGA total in every
region × population-type cell.

Fixed: the Section 8 overlap paragraph (count, full state-grouped LGA
list, explicit "IDP-only" statement) and the matching "3 LGAs" reference
in this file's "Revision 2026-07-30" section (above). No other paragraph
or table in Section 8 depended on the old count — the per-region
"Excluded: small population" column (2/0/16, NC/NE/NW) was already
correct, since it was always an independent (non-exclusive) tally, not
derived from the overlap paragraph's count.

## Revision 2026-07-31c — cleaned up `output/` so DESIGN vs WORKING frames aren't ambiguous

User feedback: the coverage-confirmed WORKING frame (31,051 interviews)
lives in `output/analysis_partner_coverage/`, but the *original*, now-
superseded DESIGN-only frame (52,246 interviews) sat right at
`output/` top level with the more prominent, simpler filenames
(`stage2_sampling_frame.csv`, `strata_level_sampling_frame.csv`, etc.) —
easy to mistake for the current deliverable at a glance.

Moved (via `git mv`, so history is preserved) into
`output/archive_design_only_pre_coverage/`:
`stage2_sampling_frame.{csv,gpkg}`, `stage2_sampling_frame_{idp,non_idp}.csv`,
`strata_level_sampling_frame.csv`, `selected_clusters_final.rds`, and the
untracked `MSNA_2026_sampling_frame_workbook.xlsx` (plain `mv`, wasn't
git-tracked). Added `output/README.md` (force-added past the `output/`
gitignore, same convention as other tracked output files) explaining the
DESIGN-vs-WORKING distinction and which files are current, front and
centre.

**Every script that reads these files by their old top-level path was
updated to the new archive path** (all still work without a pipeline
rerun): `06_output_review.R`, `08_render_methodology_maps.R`,
`analysis_idp_camp_backup_points_part1.R`,
`analysis_idp_host_feasibility_flagging.R`, `analysis_partner_coverage.py`,
`07_build_workbook.py`, `build_training_examples_shapefile.R`. **Not
changed**: `01_sampling_pipeline_main.R` still *writes* fresh copies to the
old top-level `output/*.csv` paths — that's its normal, correct behaviour.
This means **if the pipeline is ever rerun, the top-level clutter comes
back** and needs re-archiving by hand (`output/README.md` says so
explicitly) — rerunning this pipeline is already meant to be rare/
deliberate per the rule below, so this was judged an acceptable tradeoff
against the more invasive alternative of changing the pipeline's own write
paths on a frozen, submitted deliverable.

## Revision 2026-07-31d — full `output/` restructure (naming/folders, second cleanup pass)

The 2026-07-31c cleanup (archiving the pre-coverage DESIGN frame) fixed the
most urgent ambiguity but left `output/` with inconsistent, ad hoc folder
naming (`analysis_<thing>` folders each holding a mix of CSVs/xlsx/PNGs,
duplicate copies of every ToR map living in both `images/` and the
`analysis_*` folder that produced it, plus `cache/` and the newly-archived
DESIGN frame both still sitting inside `output/` itself). User asked for a
second pass: one folder for all Excel outputs, one for all images, cache
and the DESIGN-frame archive moved out of `output/` entirely into the
project's actual archiving location, and better naming throughout.

**Final structure** (all moves via `git mv` for tracked files, preserving
history):
- **`_cache/`** (new, root-level, sibling to `output/` and `_archive/`) ←
  was `output/cache/`. Deliberately **not** folded into `_archive/` even
  though the user's original ask grouped "cache and archive" together —
  cache is a live build artifact (load-bearing for fast pipeline reruns),
  not historical/superseded material, so mixing it into `_archive/` would
  have been confusing later. Flagged this distinction to the user
  explicitly before executing; no objection raised.
- **`_archive/2026-07-23_design_frame_pre_coverage/`** ← was
  `output/archive_design_only_pre_coverage/`, one level up. Date-stamped
  per the user's own convention already used for `_archive/`'s existing
  scripts (e.g. `02_building_ingestion.R.before_assist_fix_2026-07-10.bak`).
- **`output/excel_workbooks/`** ← both `.xlsx` deliverables, from
  `analysis_partner_coverage/` and `analysis_idp_camp_backup_points/`
  respectively. Filenames themselves left unchanged (only their folder
  moved) — deliberately did not rename the data files themselves, since
  filenames like `NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv` were
  already communicated/in active use in-conversation; renaming those
  specifically would have been a different, riskier kind of change than
  reorganising which folder they sit in.
- **`output/maps/`** (renamed from `output/images/`) ← every ToR map PNG,
  now with exactly one copy of each (previously duplicated in both
  `images/` and whichever `analysis_coverage_map`/`analysis_idp_tor_maps`
  folder produced it — deleted the redundant untracked copies) +
  `output/maps/supporting_evidence/` (the 3 camp-backup-point verification
  images, git-tracked, moved from `analysis_idp_camp_backup_points/`).
- **`output/sampling_frame_current/`** (renamed from
  `analysis_partner_coverage/`) ← the 5 current-frame CSVs
  (`coverage_summary`/`stage2_*_FULL`/`stage2_*_WORKING`/
  `strata_*_FULL`/`strata_*_WORKING`) + the internal `_pipeline_state.pkl`
  handoff. Name change reflects that this folder's real role is "the
  current sampling frame," not just "an analysis output."
- **`output/analysis_supporting/idp_camp_backup_points/`** and
  **`output/analysis_supporting/idp_host_feasibility/`** (renamed from
  `analysis_idp_camp_backup_points/`/`analysis_idp_host_feasibility/`) —
  the CSV/rds planning-analysis outputs only, now that the xlsx/PNGs that
  used to sit alongside them have moved to their own folders.
- `output/training_examples/` unchanged (already a clean, self-contained
  deliverable type).

**Every script updated to match** (paths only — no pipeline rerun needed,
verified via `grep` sweep for stale references before/after):
`06_output_review.R`, `08_render_methodology_maps.R`,
`analysis_idp_camp_backup_points_part1.R` and `_part2.R`,
`analysis_idp_host_feasibility_flagging.R`, `analysis_partner_coverage.py`
(`OUT_DIR` now points at `sampling_frame_current/`),
`build_partner_coverage_workbook.py` (reads the pkl handoff from
`sampling_frame_current/`, writes the xlsx to `excel_workbooks/` — these
are two different directories now, previously the same one),
`07_build_workbook.py` (both its read paths *and* its own xlsx output now
point into `_archive/2026-07-23_design_frame_pre_coverage/`, since that
script's whole output is the now-superseded pre-coverage workbook),
`analysis_coverage_map1.R`/`_map2.R` and `analysis_idp_tor_maps_part1.R`/
`_part2.R` (all four now write directly to `output/maps/` — no more
separate analysis-staging folder that then gets copied, which is what
caused the duplication in the first place), `build_training_examples_shapefile.R`.
`01_sampling_pipeline_main.R` intentionally **not** changed — see
2026-07-31c above, same reasoning still applies.

`output/README.md` rewritten to describe the new structure — still the
first thing to read when unsure what's current.

## Revision 2026-08-01 — patched `site_radius_m` and added `tier2_fallback_used` (targeted CSV patch, not a pipeline rerun)

Two data-quality gaps flagged while pointing the user at
`sampling_frame_current/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv`
for data collection — both now fixed via
`scripts/patch_site_radius_and_tier2_flag.R`, a targeted in-place patch of
the WORKING and FULL household-level CSVs (same pattern as the earlier
`strata_id` CSV patch — no pipeline rerun, no cache invalidation, fully
reversible via git since both files are tracked).

- **`site_radius_m`** was stale — uniformly 150m for every IDP row
  (17,910 WORKING / 26,316 FULL rows), left over from the superseded
  single-radius method. The concept doesn't apply to most of the current
  design at all: in-camp Tier 1 is bounded by "visible camp extent" (no
  radius), Tier 2 starts from a point with no radius either, and
  host-community listing is bounded by social recognition, not geography.
  The only rows with a genuine radius are the 15 flagged large in-camp
  sites with a backup GPS point (`analysis_supporting/idp_camp_backup_points/
  manual_visual_review.csv`'s `radius_m`, or the 300m fallback where
  delineation failed — identical logic to
  `analysis_idp_camp_backup_points_part2.R`'s own `final_radius_m`). Fixed:
  `NA` everywhere except those 15 sites' rows (786 WORKING / 786 FULL rows
  populated with their real radius — same count in both, since none of the
  15 flagged camps are coverage-excluded).
- **`tier2_fallback_used`** didn't exist. Added as a schema-readiness
  column, not a computed one — whether Tier 2 gets triggered is a
  field-team, real-time decision that hasn't happened yet (fieldwork
  hasn't started), so there's nothing to compute. `FALSE` for every
  in-camp IDP row (2,316 WORKING / 2,676 FULL), `NA` for Non-IDP/
  host-community rows it doesn't apply to.

Verified directly against the patched files (not assumed): a flagged-camp
in-camp row shows its real radius + `FALSE`; a Non-IDP row and a
host-community row both show `NA`/`NA`.

`output/README.md`'s caveat section rewritten from "known issues" to
"fixes applied 2026-08-01."

## Revision 2026-08-01b — `output/` restructured again (data/maps/gis), workbook rebuilt with household frame

The 2026-07-31d restructure grouped things by *what analysis produced them*
(`sampling_frame_current/`, `excel_workbooks/`, `analysis_supporting/`).
User clarified the intent was different: group by *file type and audience*
instead. Final structure:

- **`output/data/data_collection/`** — every CSV/XLSX a field team or
  current-fielding-plan user needs, all in one flat folder (no more
  Excel-vs-CSV split): the 5 current sampling-frame CSVs (household- and
  strata-level, FULL and WORKING, plus the coverage summary), the combined
  workbook, `idp_camp_backup_points.csv`/`.xlsx` (a genuine field
  deliverable — Tier 2 fallback backup GPS points), and the internal
  `_pipeline_state.pkl` handoff. Was `sampling_frame_current/` +
  `excel_workbooks/` + part of `analysis_supporting/idp_camp_backup_points/`.
- **`output/data/supporting_analysis/`** — data files that explain *how*
  the design was built but aren't needed by field teams:
  `idp_camp_backup_points/` (ranking, footprint evidence, the manual visual
  review sheet) and `idp_host_feasibility/` (feasibility flags). Was
  `analysis_supporting/`.
- **`output/maps/`** — unchanged.
- **`output/gis/training_examples/`** — was `output/training_examples/`,
  now grouped under a `gis/` parent alongside any future GIS-specific
  deliverables.

Every script's paths updated again (4th pass on some): `analysis_coverage_map1.R`/
`_map2.R`, `analysis_idp_tor_maps_part1.R`/`_part2.R`,
`analysis_partner_coverage.py`, `analysis_idp_camp_backup_points_part1.R`/
`_part2.R` (Part 2 now writes its CSV/XLSX deliverable to
`data/data_collection/` while still *reading* Part 1's rds/review-sheet
from `data/supporting_analysis/` — two different directories now, where
previously one `analysis_dir` served both roles),
`analysis_idp_host_feasibility_flagging.R`, `build_training_examples_shapefile.R`,
`patch_site_radius_and_tier2_flag.R`, `build_partner_coverage_workbook.py`.

**While rebuilding the workbook, found `_pipeline_state.pkl` was missing**
(an untracked, ephemeral handoff file that didn't survive the moves across
two restructures). Fixed by rerunning `analysis_partner_coverage.py` —
this regenerates the 5 CSVs + pkl fresh from the `_archive/` DESIGN frame
and reproduced byte-for-byte-equivalent figures (86,394 FULL / 50,653
WORKING rows, 176/147 coverage split, all region-level before/after
numbers unchanged — a clean reproducibility check). **This also
overwrote the 2026-08-01 `site_radius_m`/`tier2_fallback_used` patch**,
which was then reapplied via `patch_site_radius_and_tier2_flag.R` — same
output as the first application (786 rows get a real radius, 2,316/2,676
in-camp rows get `tier2_fallback_used = FALSE`). **Anyone regenerating
`analysis_partner_coverage.py`'s output in future must rerun the patch
script immediately afterward** — `output/README.md` says so explicitly.

**Workbook rebuilt with real, substantive content changes**, not just a
relocation — user asked me to check it was current (its file date was
older than the sampling-frame CSVs it's supposed to summarise) and update
it with the FULL sampling frame:
- Added a **"Sampling Frame (FULL)" sheet** — the actual household-level
  frame (86,394 rows, one row per planned interview), read directly from
  the patched CSV on disk rather than from the (older, patch-unaware)
  pickled state, specifically so it carries the 2026-08-01
  `site_radius_m`/`tier2_fallback_used` fixes. This sheet didn't exist
  before — the original design deliberately left it out ("too large to
  embed usefully here... delivered as separate CSVs"); the user's request
  overrode that. Verified directly (not just from the build log): both new
  columns present in the sheet header, and a flagged-camp row shows the
  right values (`site_radius_m = 230`, `tier2_fallback_used = FALSE`).
- **Fixed the same stale "3 LGAs" overlap figure** in the README sheet's
  text that was already caught and corrected in the methodology doc
  (Revision 2026-07-31b) — this workbook-generating script's README text
  had never been updated to match. Now says 17, with the full state-grouped
  list and the "IDP-only" clarification, matching the doc's corrected
  language.
- Row/column counts throughout the README sheet's prose double-checked
  against the actual regenerated files rather than assumed (86,394 FULL /
  50,653 WORKING).

`output/README.md` rewritten again to match the new structure.

## Revision 2026-08-02 — folded IDP Camp Backup Points into the main workbook, deleted its standalone .xlsx

User flagged `data_collection/idp_camp_backup_points.csv` and
`idp_camp_backup_points.xlsx` as confusingly duplicate-named. Resolved by
folding the backup-points data into `NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx`
as a new **"IDP Camp Backup Points"** sheet (`build_partner_coverage_workbook.py`,
read directly from the CSV on disk, same pattern as the household Sampling
Frame sheet) and deleting the standalone `.xlsx`
(`analysis_idp_camp_backup_points_part2.R` no longer writes one — comment
left in its place explaining why). The `.csv` stays as the raw-data file.

Caught and fixed a bug in the new sheet's own description while doing
this: the note initially said the sheet held "the 81 largest in-camp IDP
sites (flagged_camp = TRUE)" — wrong, conflating the sheet's total row
count (81, every in-camp site) with the flagged subset (15, the ones that
actually have a populated backup GPS point). Verified the corrected text
directly against the rebuilt sheet before considering this done.

## Revision 2026-08-04 — reserve-list scaling fixed for repeat-drawn clusters (uniform Option A)

**Problem, flagged by a separate Claude web session writing field guides**:
the reserve/replacement household list was a flat 6 for every cluster,
regardless of how large its primary target was. For a single-draw cluster
(the vast majority) this is a 1:1 ratio and was fine. For a cluster formed
by merging multiple repeated PPS draws of the same hexagon (up to 17 draws
in very-small-population strata, `selection_count` > 1 - see "Map 2" under
Revision 2026-07-31 for how common this actually is, ~20% of selected
hexes), the primary target scales with `selection_count` (`m *
selection_count`) but reserve never did - so a 30-primary in-camp cluster
still carried only 6 reserves, a ~1:5 ratio, proportionally the thinnest
safety margin exactly where the most listing/replacement activity happens.

**Decision** (user, after weighing several options): uniform Option A -
`reserve_households = target_households` (both `m * selection_count`),
applied identically to Non-IDP and IDP clusters. Rejected an asymmetric
Non-IDP/IDP-only option considered first, on the user's explicit reasoning
that consistency and simplicity across population groups was more
defensible than an unverified operational-cost assumption. Confirmed this
adds **zero field-team effort** - field teams already collect the same
number of primary interviews; this only changes how large the printed
backup list is, i.e. file size, not fieldwork.

**Mechanism** (mirrors `target_households` exactly, just extended to a
new column):
- `merge_repeated_psu_draws()` (`03_stage2_household_selection.R`) now
  also computes `reserve_households = m * selection_count`, alongside the
  existing `target_households = m * selection_count`.
- `draw_households_from_files()`/`finalize_cluster()` (same file) look up
  a per-cluster `reserve_n_i` from `clusters_lookup$reserve_households`
  instead of taking a flat `reserve_n = m` scalar - the `reserve_n`
  parameter was removed from `draw_households_from_files()` and
  `select_stage2_households()` entirely.
- `reallocate_zero_building_clusters()` and `add_supplementary_clusters()`
  (`04_stage2_cluster_reallocation.R`) propagate the same per-cluster
  `reserve_households` through their own replacement/new-cluster rows.
- `select_stage2_idp_sites()`/`build_slots()`
  (`05_stage2_idp_site_assignment.R`) take `reserve_n_i` as a 3rd per-
  cluster argument (was a flat closure-captured `reserve_n`).
- **Capping behaviour deliberately differs by population type, matching
  each side's EXISTING primary-target capping philosophy exactly** (not a
  new rule invented for reserves): Non-IDP reserve is naturally capped by
  building-pool availability (`draw_cluster()`'s existing `min(n_pool,
  target_hh + reserve_n)`), same as Non-IDP primary already is. IDP
  reserve is left **uncapped** against DTM-recorded site population, same
  as IDP primary always has been - the real household list is built by
  field teams on arrival, not drawn from a pre-existing pool, so a DTM
  estimate below the planned total isn't grounds to plan fewer reserves
  than primaries any more than it's grounds to plan fewer primaries. 55 of
  676 WORKING repeat-drawn IDP clusters would exceed their recorded DTM
  population under naive full reserve scaling (e.g. `idp_NG034007_1`: 84
  primary, needs 168 total, only 85 recorded) - this is expected and does
  not break anything, since IDP reserve was never capped in the first
  place.

**New column**: `reserve_households` on both the strata-level and
household-level sampling frame, alongside `target_households`.

**Impact**: no change to primary interview counts, cluster locations, or
field-team workload (52,246 DESIGN / 31,051 WORKING primary interviews,
unchanged) - only household-level row counts (primary + reserve slots)
grew: FULL 86,394 -> 104,190 rows (+20.6%), WORKING 50,653 -> 61,837 rows
(+22.1%). Repeat-drawn clusters are cut by the partner-coverage layer at
roughly the same rate as clusters generally (~60% retained), so the
WORKING-frame growth rate is not meaningfully smaller than FULL's, contrary
to an initial hypothesis that it would be - checked directly rather than
assumed.

**Gotcha hit during this rerun, worth knowing before ever adding a new
per-cluster column here again**: three separate `select()` calls needed
updating to thread `reserve_households` through
(`04_stage2_cluster_reallocation.R`'s `zero_building_clusters` builder,
and `03_stage2_household_selection.R`'s `finalize_households()` final
export `select()`) - missing one didn't error cleanly the first time: R's
`dplyr::mutate(col = df$nonexistent_col[1])` silently assigns `NULL`
(dropping the column entirely) rather than erroring, so the actual `Can't
select columns that don't exist` error only surfaced several steps later,
downstream of the real mistake. Also hit: the pipeline had been launched
piped through `tail -200` (`Rscript ... | tail -200`) - a piped command's
reported exit code is `tail`'s, not `Rscript`'s, so a genuine mid-run
failure was masked as "exit 0, completed" and looked like an unexplained
early stop instead of an error. **Always redirect a background pipeline
run straight to a log file (`> log 2>&1`) rather than piping through
`tail`**, so the real exit code and full output are both preserved.
Separately: a stale `output/cache/stage2_non_idp/stage2_households.rds`
(cached from an earlier attempt, before the `finalize_households()` export
fix landed) silently kept serving pre-fix rows for the bulk Non-IDP draw
even after the code was corrected and the pipeline re-ran successfully -
`rebuild = FALSE` caches key on the cache directory path only, not on
whether the generating code changed, so any code fix touching a cached
function's output schema needs that specific cache cleared before the fix
can actually take effect, not just a clean rerun.

Design frame re-archived to
`_archive/2026-08-04_design_frame_pre_coverage/` (superseding
`_archive/2026-07-23_design_frame_pre_coverage/` as the source
`analysis_partner_coverage.py` reads from - its `STRATA_CSV`/`STAGE2_CSV`
constants updated accordingly). `patch_site_radius_and_tier2_flag.R` and
`build_partner_coverage_workbook.py` re-run against the new frame per the
existing required sequence (see `output/README.md`'s "If you rerun the
pipeline" section). **Not yet committed to git** - awaiting user review
of the regenerated frame before treating this as final.

## Revision 2026-08-05 — Tier 2 backup GPS points extended to every in-camp cluster; partner data-collection KML packages built

**Partner data-collection packages (new, operational deliverable, outside
this repo).** `scripts/build_partner_dc_packages.py` builds
`../../6. Outputs/partner_dc_files/<Partner>/<State>/<LGA>/` — KML files
for field teams to load in Maps.me/Google Maps for tomorrow's pilot. Splits
the WORKING household-level frame by partner using
`input_data/boundaries/partner_coverage/Partnerscoverage.xlsx`'s per-LGA
partner columns (same LGA-name matching/reconciliation logic as
`analysis_partner_coverage.py`, duplicated rather than imported per this
project's standalone-script convention). Per LGA folder: up to 3 files —
`non_idp_households_primary.kml` (one point per primary HH survey),
`non_idp_households_reserve.kml` (same, reserve rows — kept in a **separate
file**, not mixed with primary, at the user's explicit request so field
teams can't confuse the two), `idp_clusters_primary.kml` (one point per IDP
cluster — primary and reserve HH rows share an identical site coordinate
within a cluster, so there is no separate IDP reserve file). An LGA covered
by >1 partner gets identical folders duplicated into each partner's tree
(currently only Sokoto/Isa: DRC + IRC/LHI). Not git-tracked (lives outside
`1_sampling/` entirely) and not part of the numbered pipeline.

**Tier 2 backup GPS points extended from 15 to all 81 in-camp clusters**
(`scripts/analysis_idp_camp_backup_points_part3.R`, run once, in-place
patch of `output/data/data_collection/idp_camp_backup_points.csv`).
Context: while building the partner KML packages, partners at the ToT
raised concern (day before pilot start) that Tier 1 (full household
listing) feasibility is a broader worry than the original design
anticipated — the existing backup-point mechanism (Revision 2026-07-28,
`analysis_idp_camp_backup_points_part{1,2}.R`) only covered the 15 largest
camps (>2,000hh, individually reviewed via satellite imagery), on the
rationale that only those camps' DTM point (often a registration desk, not
a camp centroid) posed a meaningful walk-starting-point bias risk. User
decision: extend a backup point to every in-camp cluster as a just-in-case
safety net, using the **same fixed-radius-buffer fallback method** Part 2
already uses for camps where imagery delineation wasn't confident (300m
radius around the DTM point, uniform over the circle's area via `r =
300*sqrt(u)`, `set.seed(1234)`), rather than attempting manual imagery
delineation for 66 more camps overnight — not feasible before tomorrow's
pilot start, and the buffer fallback is already an accepted, documented
method in this same dataset. **Does not touch the original 15 flagged
camps' points** (9 imagery-delineated + 6 already-fallback, from Part 2) —
only fills in the 66 previously-`NA` `backup_gps_lat`/`lon` rows. New
`backup_point_method` column distinguishes all three provenances
(`imagery_delineated` / `fixed_radius_fallback_flagged_camp` /
`fixed_radius_fallback_standard_camp`), since "has a backup point" and "was
individually reviewed" are no longer the same thing after this change.
`flagged_camp` itself is untouched — it still means "was in the original
>2,000hh review subset," not "has a backup point."

**Fixed a mislabeling bug found while building the KML packages**: the
first KML-generation pass described the backup point as "use if the DTM
point above looks wrong on the ground" — wrong framing. Per the
methodology doc's actual Tier 1/Tier 2 design (§3), the backup point is
specifically the **Tier 2 random-walk starting point**, used only when a
full Tier 1 listing isn't feasible on arrival; for camps without a backup
point, Tier 1 and Tier 2 both use the same DTM point. Corrected in both
`build_partner_dc_packages.py`'s placemark text and this file.

`build_partner_coverage_workbook.py` rerun after Part 3 so the "IDP Camp
Backup Points" sheet reflects all 81 rows populated (was rerun already for
Revision 2026-08-04's reserve-scaling fix; this is a second, independent
rerun for Part 3's change).

## Revision 2026-08-06 — region-differentiated Niger border buffer, via TARGETED resample (not a full rerun)

**Decision.** Following the border-buffer scenario test-runs earlier the same
day (see the two entries above this one — full-pipeline reruns of "5km on
all borders" and "5km IDP / current Non-IDP"), the user made a third,
different decision: keep the **20km Niger buffer in NE** (Borno/Yobe),
reduce it to **5km in NC/NW**. Checked precisely before doing anything: only
**31 LGAs nationally are within 20km of the Niger border** (7 in NE, 24 in
NW, **zero in NC** — Niger State's only border-adjacent LGA, Borgu, borders
Benin, not the Niger republic, so "5km in NC" has no practical effect).
Chad/Cameroon/Benin buffers are unchanged (5km) everywhere, always.

**Explicitly NOT a full pipeline rerun.** The user was clear after the day's
earlier scenario work that a full national rerun for a change this scoped
was the wrong call in principle — it churns every LGA's specific drawn
points (buildings/IDP sites) even where nothing about that LGA's accessible
area changed at all, invalidating already-distributed partner field
material nationwide for a change that only affects 4 states. Instead: a
**targeted resample of only the 24 NW LGAs**, spliced into the existing,
already-delivered design frame; the other 299 LGAs (including the 7 Niger-
adjacent NE LGAs, which keep 20km unchanged) are byte-identical to before —
verified directly (all 97,012 unaffected household-level rows compared
field-by-field against a pre-change snapshot, zero differences).

**24 targeted LGAs**: Katsina (Batsari, Baure, Daura, Jibia, Kaita, Katsina,
Mai'adua, Mashi, Sandamu, Zango — 10), Kebbi (Arewa-Dandi, Bagudo, Bunza,
Dandi — 4), Sokoto (Gada, Goronyo, Gudu, Gwadabawa, Illela, Isa, Sabon
Birni, Tangaza — 8), Zamfara (Shinkafi, Zurmi — 2).

**Mechanism**:
1. A throwaway, fully isolated copy of the project (`1_sampling_targeted_
   resample_nw24/`, outside the tracked repo, junctioned to the live
   project's static input data) ran the *unmodified* Stage 1/2 selection
   code with two changes: `NGA_shapes_all_cleaned$nga_admin2` filtered to
   just the 24 target pcodes (inserted right after that object is built,
   before the IDP DTM join and before the hex grid is constructed — this
   single filter cascades correctly through every downstream step using the
   exact same unmodified functions, not a reimplementation), and the
   international-buffer rule set to a uniform 5000m (correct here since
   every LGA remaining after the filter *is* one of the 24 getting 5km).
   Its own `set.seed(1234)` gives a fresh, independent, reproducible draw
   for just these 24 LGAs.
2. Why isolated-and-spliced rather than "rerun the national script with a
   smarter buffer condition": R's PPS/building/site draws all consume a
   single shared, sequential RNG stream. Even with an accessible-area
   change correctly scoped to only the 24 LGAs, a national rerun would let
   an earlier-processed affected stratum consuming a different number of
   random calls than before silently shift *every later stratum's* draw —
   including LGAs whose own accessible area never changed. An isolated
   resample with its own seed, spliced in afterward, has no such risk by
   construction.
3. Two in-camp IDP clusters were newly selected by the resample and not
   already in the 81-site national in-camp list (`analysis_idp_camp_backup_
   points_part1-3.R`) — Sabon Birni's Tsamaye Primary School (267hh) and
   Unguwar Lalle Primary School (781hh). Two other newly-drawn in-camp
   cluster IDs coincidentally matched existing site_ids by chance of
   cluster-numbering position, but were checked and confirmed to be the
   *same actual physical site* (identical iom_site_id/name/coordinates) —
   not new, no action needed. The two genuinely new sites got a Tier 2
   backup point via `analysis_idp_camp_backup_points_part4_targeted_
   resample_additions.R`, same fixed-radius-buffer fallback method as
   Part 3 (300m, uniform over the circle's area) — now 83 in-camp sites
   with a backup point (was 81).
4. `merge_targeted_resample_nw24.py` and `merge_selected_clusters_final_
   nw24.R` spliced the resample's 24-LGA rows into the live design frame —
   dropped the 24 LGAs' old rows from `_archive/2026-08-04_design_frame_
   pre_coverage/{stage2_sampling_frame.csv,strata_level_sampling_frame.csv,
   selected_clusters_final.rds}`, appended the resample's rows for those
   LGAs, wrote the result to a new dated archive,
   `_archive/2026-08-06_design_frame_post_nw_targeted_resample/` — this is
   now the current design-frame source of truth, same role
   `2026-08-04_design_frame_pre_coverage/` played before it.
5. `analysis_partner_coverage.py`'s `STRATA_CSV`/`STAGE2_CSV` (and
   `build_partner_dc_packages.py`'s `STRATA_CSV`) repointed to the new
   archive folder, rerun — this is a deterministic, no-randomness join, so
   safe to rerun wholesale on the merged frame; reproduces identical
   `coverage_status`/`exclusion_reason` for all 299 untouched LGAs and
   correct new values for the 24. `patch_site_radius_and_tier2_flag.R` and
   `build_partner_coverage_workbook.py` rerun after, per the existing
   required sequence.
6. **International-buffer logic in `01_sampling_pipeline_main.R` itself
   updated** to the new region-differentiated rule (NE 20km / NC+NW 5km),
   as the script's permanent, documented behaviour going forward — but this
   was a documentation/future-rerun-accuracy update to the deterministic
   boundary/buffer section only (well before `set.seed(1234)`), **not** how
   the actually-delivered design was produced (that was the isolated
   resample above). Implementation: buffers Niger's border line at both
   20km and 5km, intersects the 20km version with NE's admin1 union and the
   5km version with NC+NW's admin1 union, and unions the two pieces
   together — verified directly (a known NW point 12km from the border,
   Sandamu town, now falls outside the buffer; Mobbar, NE, correctly still
   has zero IDP sample since NE's 20km rule is unchanged there).
7. **Cache gotcha, same class as the buildings/idp_sites ones already
   documented above**: `input_data/boundaries/nga_hexagons/accessible_hex.
   rds` is keyed by a fixed path, not by buffer distance — deleted so it
   regenerates fresh against the new buffer logic rather than silently
   serving the stale pre-2026-08-06 result. `hexa_by_admin2.rds` (the
   pre-accessibility hex grid) is buffer-independent and was correctly left
   alone/reused throughout.

**Maps**: `analysis_coverage_map1.R` needed no changes (LGA-level only,
reads `coverage_summary` which was already correctly regenerated).
`analysis_coverage_map2.R` previously re-sourced the *entire* pipeline
script through Stage 1 selection (`temp_stage1_map2.R`) to get hex
geometries — safe only when that reproduced the exact national draw every
time; now that the delivered design is a splice rather than one national
draw, this was changed to source only the deterministic boundary/buffer
prefix (through `hex_access`, no randomness anywhere in that range) and
load hex geometries directly from the merged archive's
`selected_clusters_final.rds` instead of re-deriving them. Both maps
regenerated. Methodology example maps (`08_render_methodology_maps.R`,
`analysis_idp_tor_maps_part1/2.R`) checked and confirmed **not** affected —
none of their fixed example-cluster IDs (`non_idp_NG023010_1` Kogi,
`idp_NG008013_17` Borno, `idp_NG021005_2` Katsina/Bindawa) fall within the
24 targeted LGAs.

**Partner resources**: `build_partner_dc_packages.py` — output root moved
2026-08-06 by the user from `6. Outputs\partner_dc_files` to
`3. External coordination\NGA MSNA 2026 Package` (same structure, script
updated to match). IDP Tier 2 backup points now get their **own KML file**
per LGA folder (`idp_clusters_tier2_backup.kml`, separate from `idp_
clusters_primary.kml`) rather than being bundled as extra placemarks inside
the primary file — the points were always present, just not separately
discoverable, which is what prompted this split. Per-partner summary
workbook restructured from a single sheet to two: **README** (Point Type/
column definitions, plus a per-State/LGA target-sample summary table
computed straight from that partner's own points) and **Sampling Points**
(the full row-level table, unchanged from before). Regenerated for all 19
partners; DRC's was skipped (file open/locked at run time) — rerun
`build_partner_dc_packages.py` once it's closed.

**National achieved sample (WORKING, post-coverage)**: 31,051 → 31,559
(+508 interviews, entirely IDP — Non-IDP total is materially unchanged
since Non-IDP sample size is precision-driven and saturates well before
these LGAs' population scale). Newly-reportable IDP LGAs (zero achieved
sample before, real sample now): Sandamu (84), Illela (84), Baure (84),
Jibia (78), Mai'adua (60) — Zango and the NE's Mobbar remain unreportable
even at 5km (their DTM sites are within 5km of the border too, not just
20km — a full buffer removal, not tested here, would be needed to reach
them). None of the 18 already-excluded small-population IDP strata (Kano
×14, Kaduna/Markafi, Kebbi/Gwandu, Niger/Katcha, Niger/Lapai) are affected —
none border Niger within 20km.

**Safety copies, not superseded by this change**: `_archive/2026-08-06_
pre_border_buffer_scenario_test/output/` — a full copy of `output/` taken
before any of this day's work (both the earlier full-national scenario test
runs and this targeted resample) — kept as the pre-2026-08-06 reference
point if ever needed. `1_sampling_scenario1_5km_all/` and `1_sampling_
scenario2_asymmetric/` (the day's earlier full-rerun test scenarios,
superseded by this targeted approach) are left on disk outside the tracked
repo, not cleaned up automatically.

**Update 2026-08-06b — methodology doc brought in line, a map rendering bug
fixed, DRC's partner workbook regenerated.**

- `msna_methodology_summary_portable.md` updated: Section 1's assessment-
  area map caption and Section 4's border-buffer paragraph now describe the
  region-differentiated rule; Sections 7 and 8's national/North-West tables
  (design and WORKING) updated to the merged frame's real figures, MoE
  ranges recomputed directly from the CSVs (North-West/National WORKING MoE
  range 6.1%–9.3% → 7.1%–9.3%; North-Central/North-East rows and Section
  7's design-frame MoE ranges are unchanged at displayed precision, since
  those regions' underlying strata didn't change); the below-target-cluster
  count (§4) corrected 85/5,779 → 88/5,864.

**Update 2026-08-06c — the "28 below-target Non-IDP strata" open item
resolved.** Checked directly against `supplementary_cluster == TRUE` rows
in the current merged household frame (not the log line originally cited,
which turned out to be misremembered — see below): exactly **one** LGA
swap happened, not a net change in count. **Sokoto/Tangaza** no longer
needs a supplementary cluster (the buffer relaxation freed enough
additional building pool in Sokoto generally that Tangaza's own gap closed
without one); **Kebbi/Arewa-Dandi** now needs one it didn't before (one
standard 6-household supplementary cluster, achieved sample 99→105,
realized MoE 9.41%→9.13%, computed with the identical `realized_moe()`
formula and cross-checked exactly against the strata CSV's own value).
Net effect: total count stays at **28**, total additional interviews stays
at **254** (both LGAs needed exactly one cluster), and the realized-MoE
range across all 28 stays **9.03–9.27%** (the min/max, Mafa/Kaga, are both
Borno — nowhere near this change). Only the **state list** changes:
Sokoto drops out, Kebbi enters — "Benue, Borno, Kogi, Nasarawa, Niger,
Plateau, Sokoto, Yobe, Zamfara" → "Benue, Borno, Kebbi, Kogi, Nasarawa,
Niger, Plateau, Yobe, Zamfara". `msna_methodology_summary_portable.md` §4
updated (prose + the per-LGA table row) to match; the ToR-update prompt
file's "please don't independently resolve this" caveat replaced with the
resolved figures.

**Root cause of the original miscue, worth remembering**: the "28
stratum/strata" figure first cited as uncertain came from conflating two
different log files — a `grep`/memory slip pulled the number from the
**earlier, unrelated, full-national Scenario 2 test run's** log ("49
supplementary cluster(s) added across 27 stratum/strata" — a superseded
test run, never part of the delivered design) rather than the actual
targeted 24-LGA resample's own log ("2 supplementary cluster(s) added
across 2 stratum/strata" — the real number for that scoped run, which the
Arewa-Dandi finding above traces back to correctly). Always re-derive a
figure like this from the current on-disk data (`supplementary_cluster`
flag) rather than trusting a remembered log line, especially after several
different runs have produced similarly-shaped log output in the same
session.
- `output/data/data_collection/DRC_sampling_points_summary.xlsx`-equivalent
  (in the partner package, not this folder) was skipped in the first
  `build_partner_dc_packages.py` run (file open/locked) — closed by the
  user and rerun; all 19 partner workbooks now current.
- `analysis_coverage_map1.R` given the same NC/NE/NW region-code labels
  `analysis_coverage_map2.R` already carries (`region_labels_focus`, same
  point-on-surface + NC nudge technique) — map1 previously had the region
  boundary line and legend entry but no text label. Re-rendered.
- **Map bug found and fixed**: `analysis_coverage_map2.R`'s
  `coverage_map2_alt2_popgroup_all_hexes.png` rendered every **IDP-only**
  hex as a point marker instead of a filled hexagon, while Non-IDP-only and
  mixed hexes rendered correctly. Root cause: `selected_clusters_final.rds`
  (the object this map now reads hex geometry from, since the 2026-08-06a
  fix above) does NOT carry a uniform geometry type — Non-IDP rows carry
  the hex polygon, but IDP rows (`idp_sites$clusters_final`, from
  `05_stage2_idp_site_assignment.R`) carry the DTM site's own POINT
  geometry instead, which is what Stage 2 actually needs for IDP but is
  wrong for a hex-fill map. The old Stage-1-only `selected_clusters` this
  script used to re-derive via sourcing never had this problem (Stage 1
  hex selection assigns proper hex-grid geometry regardless of pop_type),
  so the bug only surfaced now that hex geometry comes from the post-
  Stage-2 merged archive. Fixed generically, not just for this one map: a
  new `hex_polygons` object (canonical hex geometry, keyed by `uuid_hex`,
  sourced from `hex_access`, `st_make_valid()`'d both before and after the
  projected→geographic CRS transform since one pre-existing degenerate
  ring only surfaced as invalid after reprojecting) is now the *only*
  source of hex geometry anywhere in this script — every join that used to
  pull geometry from `selected_clusters` itself now pulls attributes only
  from it and geometry from `hex_polygons`. Verified directly: 0 POINT
  geometries remain anywhere in the map's hex layers (was 552 for the
  IDP-only category alone). Re-rendered; `coverage_map2_alt2_popgroup_
  all_hexes.png` and `coverage_map1_partner_coverage.png` both current.
- `claude_web_prompt_2026-08-06_border_buffer_tor_update.md` (project
  root) — a self-contained prompt for the separate Claude web session
  working from the ToR document, summarising this revision and the
  updated figures for that document to be brought into line, same relay
  pattern already used for the 2026-07-28 IDP methodology decision.

**Still not yet done**: `output/README.md` not updated for the new archive
folder name. Not committed to git — awaiting user review.

## Revision 2026-08-27 — accessibility-workflow provenance columns + Solidarités partner-name fix (resampling/, not the core pipeline)

Two independent fixes inside `resampling/` (see `resampling/README.md` for
full operational detail — this entry is a summary/pointer, not the primary
record), plus one cross-cutting data-integrity fix that touched the core
sampling-frame outputs directly.

**1. Provenance tracking added to the accessibility-report workflow.**
Closes the `resampling/README.md` "Not yet done" item that flagged
`source_channel` as hardcoded to `"partner_excel_return"` regardless of
whether a partner or a coordinator actually typed a given answer. Two new
columns — `Reported by (Partner / IMPACT-default)` and `Source channel` —
added to `01_generate_accessibility_reports.py`'s Ward/Cluster Accessibility
sheets (dropdown-validated `INPUT_COLUMNS`, standardised choice lists) and
to `02_ingest_accessibility_reports.py`'s `LOG_FIELDS` (read from the sheet
if filled in, defaulting to `Partner` / `Partner's own template` otherwise
— true for most returns, since these columns are for internal use, not
something partners normally touch). The master log's existing 2,052 rows
were migrated (`scripts/patch_add_reported_by_column.py`, git-tracked,
idempotent) — NOT by defaulting everything to `Partner`, since that's
known to be wrong for specific rows (Save the Children's 42 "Yes" rows
were coordinator-assumed, not partner-typed). 1,866 rows confirmed and
backfilled; 186 left deliberately blank ("needs review") rather than
guessed — IMC (102), FHI 360 (22), Save the Children's 42 unverified "Yes"
rows, and 20 rows tied to FACT's 11 coordinator-corrected wards. **Still
open**: those 186 rows' actual provenance hasn't been individually
verified — do that before treating the master log's `reported_by` column
as complete. `02_ingest_accessibility_reports.py` now also prints an
explicit NOTE whenever a returned file predates these columns (expected
for every partner's already-distributed copy, since the columns were only
added today) instead of silently applying the default with no visibility.

**2. Solidarités partner-name fix.** Root cause: the raw
`input_data/boundaries/partner_coverage/Partnerscoverage.xlsx` (NW sheet,
header cell J1) stored the org's name truncated to `Solidarité` (missing
the trailing "s") — genuinely valid UTF-8 throughout, NOT mojibake, despite
that being the first (wrong) diagnosis on record (see the now-corrected
`resampling/scripts/analysis_sanity_check_accessibility_workflow.py`
"6. Encoding" check). Fixed at the source, then propagated through every
derived file carrying a partner-name column or filename: the WORKING/FULL
sampling frame CSVs (household + strata level, 1,233 cell-level
occurrences), the coverage summary,
`NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx` (616 cells), and
`resampling`'s master log / GIS layer / generated+returned report files /
raw-comms folder — plus the live External-coordination partner package
folder (KML, LGA maps, summary workbook, and all 35 per-cluster field
guides, via `build_partner_dc_packages.py` and `build_cluster_factsheets.py`).

**`Rscript` was not on PATH in this session's shells**, which at the time
was read as "R unavailable" and ruled out the documented "rerun
`analysis_partner_coverage.py` + `build_partner_coverage_workbook.py`,
then reapply `patch_site_radius_and_tier2_flag.R`" sequence for refreshing
`output/data/data_collection/` — direct-patching the already-generated
CSV/xlsx files was used instead (see the new bullet under "Rules for
extending or rerunning this pipeline" below). `_frame_version.txt` was
refreshed by manually replicating `stamp_frame_version.R`'s
hash/mtime/row-count logic in Python (same output shape, just not R).
**CORRECTED same day**: R is in fact installed
(`C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\x64\
Rscript.exe`, all needed packages present) - just not on PATH for this
session. The patches above were still the right call at the time (small,
targeted, git-diffable, and already verified correct) and don't need
redoing, but a future session hitting an R script should call the full
path above rather than assuming R is unavailable - see the "Rules" bullet
below.

**Two new, permanent, opt-in single-partner scoping hooks** were added,
both default OFF (normal full-19-partner behaviour is unchanged unless the
var is set): a `BUILD_DC_ONLY_PARTNER` env var, read by both
`scripts/field_guide_production/build_partner_dc_packages.py` and
`build_cluster_factsheets.py`. Useful again any time a fix needs to touch
one partner's live package folder without regenerating/re-touching the
other 18's already-delivered files.

**Mistake made and corrected mid-fix, worth remembering before ever
touching a partner's top-level package folder again**:
`resampling/scripts/distribute_to_partner_folders.py`'s own header
comment states a hard constraint — a partner's top-level folder in
`3. External coordination\NGA MSNA 2026 Package\` must NEVER be deleted
or recreated, only renamed/written into in place, since SharePoint
sharing is tied to the folder's item ID, not its path/name. The first
attempt at this fix created a **new** `Solidarités` folder alongside the
existing (still-shared) `Solidarité` one, rather than renaming the
existing one in place — exactly the dangerous pattern that comment warns
against. Caught before anything was shared/communicated externally; fixed
by deleting the mistakenly-created new folder and renaming the original
in place instead. A plain filesystem rename preserves OneDrive/SharePoint
item identity; delete+recreate does not.

`resampling/output/distribution_log.csv` was deliberately left with its
old (2026-08-20) truncated partner-name entries — it's a historical audit
log of what literally happened at the time, not a live join key, so
correcting it would falsify the record rather than fix anything.

## Update 2026-08-27b — accessible-area ward-universe bug: wrong scope, not just wrong values

Found by the user (via Damasak wrongly showing "Accessible" in the
monitoring dashboard), same day as the fixes above, and materially bigger:
`analysis_accessible_area_layer.R` was pulling **every GRID3 ward
geometrically touching a covered LGA** for the accessibility GIS layer -
not the actual sampling universe - and defaulting anything that didn't
match the master status file to "Accessible". **1,977 of 4,047 rows (49%)
nationally were spurious**, and **all 176 of 176 LGAs** had at least one -
this wasn't a Mobbar-specific glitch. Worst distortions: Damboa reported
62.6% accessible (should exclude non-universe wards entirely), Mobbar
28.8% (should be 0% under the narrow definition). This also silently
corrupted the "Strata Level" sheet's "% of population remaining" figures -
the ones the monitoring dashboard displays directly to users - not just an
internal workbook sheet, since both are fed by the same
`load_lga_area_pop_fractions()`.

**The real fix isn't "narrow the universe to wards with actual clusters"
either** - the user's own correction, argued through explicitly before any
code changed: random PPS sampling can, by chance, not draw a hexagon in a
ward that was fully eligible, and that ward's accessibility still needs
tracking (it's exactly the kind of ward a future resample would draw from -
see `analysis_remaining_eligible_pool.R`). The universe is now "eligible at
Stage 1" (post-border-buffer, pre-random-draw) - neither raw geography nor
actually-drawn-clusters-only:
- **Non-IDP eligibility**: a ward-portion is included if it intersects
  `input_data/boundaries/nga_hexagons/accessible_hex.rds` (Stage 1's own
  border-buffer-filtered candidate hex grid - already reused by
  `analysis_remaining_eligible_pool.R` for a closely related purpose).
- **IDP eligibility**: a ward-portion is included if it contains at least
  one raw DTM site (same IOM source `analysis_remaining_eligible_pool.R`
  reads).
- Both restricted to LGAs with **WORKING coverage for that specific
  pop_type** (not blanket LGA coverage) - a related, previously-unnoticed
  bug found while implementing this: Gwandu (Kebbi) has real Non-IDP
  coverage (Solidarités, 204 households) but its IDP stratum was
  certainty-excluded before this design was ever fielded (Revision
  2026-07-23) - the OLD blanket-LGA `covered_pcodes` check in
  `analysis_remaining_eligible_pool.R` would have (and, checked directly,
  DID) treat Gwandu's raw DTM sites as part of the "remaining eligible IDP
  pool" with zero real IDP design presence there at all.
- **Split by pop_type** (user's explicit choice, see the two-question
  discussion this session): one row per (State, LGA, Ward, Pop Type), not
  one blended row per ward - because eligibility genuinely differs by
  pop_type (Gwandu again). The Non-IDP and IDP rows of a dual-eligible ward
  share IDENTICAL geometry (IDP eligibility is a site-presence test, not a
  different shape) - intentional, not a duplication bug, but any consumer
  summing area/population per LGA MUST group by pop_type first or double-
  counts a dual-eligible ward (`05_build_accessibility_impact_workbook.py`'s
  `load_lga_area_pop_fractions()` now keys by `(adm2_pcode, pop_type)` for
  exactly this reason - the LGA Summary sheet's area columns are now two
  separate "Non-IDP: ..." / "IDP: ..." pairs instead of one blended figure).

**Verified precisely, not assumed**: Damasak (the original finding) is now
correctly excluded - confirmed 0% geometric overlap with the accessible hex
area. Two other originally-spurious Mobbar wards (Bogum, Gudumbali West)
still show as eligible after the fix - checked directly, not waved away:
Gudumbali West is 100% within the accessible hex area, Bogum 72% - both
genuinely eligible, just never drawn by chance, exactly the case the
broader universe definition is supposed to preserve. Damboa's 25 wards are
IDENTICAL before/after the fix (checked ward-by-ward) - it isn't a border
LGA, so none of its "extra" wards were ever actually spurious, only
undrawn - explains why its % figure barely moved.

**R access resolved mid-investigation**: `scripts/run_accessibility_
refresh.py` already had the correct full Rscript path hardcoded
(`C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\Rscript.exe`)
from earlier project history - this fix was implemented and run as proper
R, not direct-patched like the Solidarités fix earlier the same day.

**Scripts touched**: `analysis_accessible_area_layer.R` (the core fix),
`analysis_remaining_eligible_pool.R` (same per-pop_type coverage fix),
`05_build_accessibility_impact_workbook.py` (`load_lga_area_pop_fractions()`
pop_type-aware; LGA Summary sheet's area columns split), `analysis_
sanity_check_accessibility_workflow.py` (added the missing reverse-
direction check - the OLD section 2 only ever verified "every master ward
has a GIS polygon," never "every GIS polygon is a real ward," which is
exactly how the 49%-spurious bug passed 15/0/3 clean for a full day;
also fixed a check that asserted Non-IDP/IDP area must be IDENTICAL per
LGA - true only under the old blended design, would have produced a wall
of false FAILs against the new, deliberately-different-per-pop_type
figures), `2_monitoring/dashboard_app/global.R` (added the `pop_type =
pop_typ` rename for the now-larger shapefile schema - checked the actual
map-rendering code first; harmless, since the popup content doesn't
reference pop_type and a dual-eligible ward's two stacked identical-
geometry features render as one visually indistinguishable shape).

**2_monitoring's own copy refreshed** via its existing `cleaning/prep/
prep_accessibility_layer.R` (also just needed the same full Rscript path -
no content changes needed, it's a plain file-copy script). Found but not
fixed (pre-existing, not caused by this session): a stale, unrefreshed
duplicate copy at `2_monitoring/dashboard_app/input_data/accessibility/`
alongside the real one at `2_monitoring/input_data/accessibility/` -
harmless (`global.R`'s `INPUT_DIR` resolution prefers the correct one) but
worth cleaning up if ever touching this area again.

Full backup of `resampling/output/` and the five scripts touched was taken
to the session scratchpad before any of this started, given `resampling/`
(scripts and output alike) is almost entirely outside git (`output/` is
gitignored at every depth; the two R scripts specifically were never
`git add`ed either) - no version-control safety net for any of this.

**Dashboard deployed live 2026-08-28** with the fix above (`2_monitoring/
deploy_dashboard.R` - also caught and fixed a separate, pre-existing stale
sampling-frame copy in `2_monitoring/input_data/sampling_frame/`, unrelated
to this fix, dating back to yesterday's Solidarités patch never having been
re-copied there).

**A second, independent Solidarités staleness gap found and fixed the same
night**, this time entirely inside `2_monitoring/dashboard_app/global.R`:
`ACCESSIBILITY_PARTNER_TO_ORG` (a hardcoded partner-name-to-org_id lookup
table, unrelated to anything touched during yesterday's propagation sweep
since that sweep never had reason to look inside 2_monitoring) still had
`"Solidarité"` as a dropdown key. Confirmed via live data this was
silently producing the literal string "NA" in the Coverage Map's
Accessibility-layer hover popup for Solidarités' ward, and miscounting
their entry in the "X of 19 partners reported" total (masked today only
by a 1-for-1 coincidence - one phantom NA swapping for one real entry).
Fixed, re-verified against live data, redeployed. **Lesson for next time
a partner name changes**: search `2_monitoring/` too, not just
`1_sampling/` - the two projects duplicate partner-name handling in
several independent places with no shared source of truth between them.

## Update 2026-08-28 — "Reported by" / "Last reported date" at every grain

Added throughout the accessibility workflow (ward grain computed directly
in `04_build_master_accessibility_status.py`; cluster/strata/LGA grain
aggregated in `05_build_accessibility_impact_workbook.py` from the wards
each one covers) - three categories (`Partner` / `Needs review` / `Not yet
reported`), semicolon-joined when a cluster/stratum/LGA's covered wards
mix categories (the normal case above ward grain, not an error). Dates
parsed from whatever format a partner used; anything parsing to AFTER
today is treated as unparseable, not real - excludes ~450 FACT rows with
the known Excel-autofill-drag date corruption (drifting as far as 2261)
from ever winning a "most recent" comparison. Full explanation lives in
the impact workbook's own README sheet and `resampling/README.md` - not
repeated here. Added a sanity-check pass verifying every "Reported by"
value is built only from the three known categories.

## Revision 2026-09-03 — Mobbar ward-level border-buffer override (Damasak + Zanna Umarti), first use of a targeted "carve a hole in the buffer for specific wards" mechanism

**Decision.** FHI 360 (assigned partner for Mobbar LGA, Borno) confirmed
on-ground access to Damasak and Zanna Umarti wards - two of the ~10 wards
excluded from the whole design since Stage 1 by the blanket 20km Niger
border buffer (a security-planning rule FACT itself originally recommended,
not a judgement on these specific places - see "Revision 2026-08-06").
Jack's call: since a willing, on-ground-confirmed partner now exists for
these two specific wards, they should be added to the sampling universe -
this is the first time this project has reopened part of a border-buffer
exclusion for a *specific ward* (as opposed to 2026-08-06's *region-wide
distance* relaxation). Corroborating evidence checked directly before
proceeding: FACT's own ward-level accessibility file
(`NGA_Sampling_accessibility_FACT_admin3_NE.csv`) independently rates
Damasak, Zulum Umarti (OCHA/COD's spelling of Zanna Umarti - not a boundary
error, just naming variation across GRID3/OCHA/DTM, same recurring pattern
as Funtua's Maska/Nasarawa) and the specific communities inside them
"Fully Accessible" - confirming the buffer, not an accessibility judgement,
was the only thing keeping these wards out.

**Scale, found before committing to a build.** Raw DTM data (previously
never processed for these wards, since they were never inside `accessible_
hex`) showed substantially more population than a routine "add two wards"
framing suggested: Non-IDP (WorldPop) 65,516 individuals / 10,919 households
across 16 eligible hexes; IDP (DTM, 10 real distinct sites, all >386m
apart) 89,388 individuals / **15,913 households**, dominated by one massive
camp (Gsss Camp Damasak, 69,794 individuals / 12,243 households). Mobbar
had **zero IDP stratum at all** before today - fully border-buffer-excluded
at Stage 1, on top of its existing Non-IDP stratum (which itself has been
separately `coverage_status = excluded` /
`accessibility_loss_below_population_threshold` since 2026-08-31, for an
unrelated reason - the other 8 wards' real insecurity, not the buffer).
Flagged to Jack before building anything; confirmed to proceed with full
build for both Non-IDP and IDP.

**Target-sample sizing - a genuine, useful finding, not just a formality.**
Independently recomputed via `build_sampling_plan()`'s exact formula
(Z=qnorm(0.95), p=0.5, e=0.10, m=6, ICC=0.06, buffer=0.10) both with
Mobbar Non-IDP's old-only N_hh (24,508.81) and the combined old+new total
(35,428.15) - **identical result, 17 clusters/102 households either way**.
At this population scale the FPC-adjusted formula has already saturated;
adding 10,919 more households doesn't move the target. This meant the
existing stratum's `target_sample` (102) didn't need recalculating at
all - the shortfall to close is simply the stratum's full existing target,
since 0 of it is currently achievable in WORKING (all 17 existing clusters
are `ward_accessible_status = Inaccessible` for the unrelated 2026-08-31
reason). The brand-new IDP stratum was sized fresh off its own real
15,913-household population - also 17 clusters/102 households (same
saturation).

**Mechanism - reused existing infrastructure, did not build parallel code.**
- **IDP**: extended the canonical site-level PSU candidate frame
  (`input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds`,
  the "Option B" mechanism from "Revision"/project-memory "IDP site-level
  PSU redesign") with these 10 real sites
  (`scripts/one_off_analyses/extend_idp_site_level_psu_mobbar_2026-09-03.R`),
  backed up first, then ran `draw_supplementary_idp_sites_batch.R`
  **completely unmodified** - exactly matching Jack's explicit instruction
  to "use the updated IDP cluster drawing mechanism." All 10 real sites got
  real coverage (target scaled per site's own PPS weight - Gsss Camp alone
  absorbed target_households=12 via selection_count=2, the smallest sites
  got the floor of 6).
- **Non-IDP**: adapted `draw_supplementary_clusters_batch.R` (kept as the
  proven, unmodified mechanism for every other partner's supplementary
  Non-IDP draws this round) with one necessary addition - since Damasak/
  Zanna Umarti were never in `hex_access` at all (zero intersection,
  confirmed directly), they don't exist in `non_idp_sampling$sampling_
  frame` for `add_supplementary_clusters()` to draw from. A new "Stage A0"
  (`resampling/scripts/draw_mobbar_expansion_non_idp_2026-09-03.R`) builds
  the 16 newly-eligible hexes (same `st_make_grid(cellsize=5000)` + WorldPop
  extraction method as Stage 1) and injects them into the sampling_frame
  object in memory, restricted to ONLY these 16 hexes for Mobbar by
  explicitly zeroing MOS on every other Mobbar hex (an allow-list, not the
  ward-accessibility-shapefile join other supplementary scripts use - safer
  near a small border-buffer LGA boundary, and the other 8 wards are
  excluded for an unrelated reason anyway). Real Google Open Buildings
  footprint draw, same Tier 1/Tier 2 mechanism as every other partner this
  round. Result: 15 clusters (one of the 16 hexes never got drawn - normal
  PPS variance, still available for a future draw), 106 real achieved
  households (nominal target summed to 114 - the two-uncoordinated-tiers
  overshoot this mechanism has always been prone to, same as documented in
  `draw_supplementary_clusters_batch.R`'s own header).
- **Merge**: `merge_partner_resample_batch.R`, unmodified, run once for
  both batches together (it already supports Non-IDP + hex-IDP + site-IDP
  in one call). A **pre-merge strata patch**
  (`scripts/one_off_analyses/patch_mobbar_strata_pre_merge_2026-09-03.R`)
  was needed first, since that script only *recomputes* achieved figures
  for strata that already have a row - it doesn't create new rows or touch
  `coverage_status`/N_hh: flipped `non_idp_NG008023` from `excluded`/
  `accessibility_loss_below_population_threshold` back to `covered`/`none`
  (real, substantial accessible population now exists), updated its N_hh/
  n_hex to the true combined total, and inserted a brand-new `idp_NG008023`
  strata row into both FULL and WORKING (didn't exist before today).
  `output/data/data_collection/` backed up first to
  `_archive/2026-09-03_pre_mobbar_fhi360_expansion/`, per this project's
  standing convention. Final verified result: non_idp_NG008023
  achieved_clusters=15/achieved_sample=106/realized_moe=9.09%;
  idp_NG008023 achieved_clusters=10/achieved_sample=102/realized_moe=9.26%
  - both within the 10% target. The pre-existing 17 inaccessible Mobbar
  Non-IDP clusters confirmed still absent from WORKING (unaffected).

**Bug found and fixed during the build (data-quality, not logic)**: the raw
DTM source file's own `lga_pcode` column uses a 9-character "NGA..."
convention (`NGA008023`) - this project's frame uses 8-character "NG..."
(`NG008023`) throughout, normally reconciled by the national site-level
builder's spatial join against `hex_access` (which silently overwrites the
raw DTM pcode). Since these 10 Mobbar sites skip that join entirely (never
intersected `hex_access`, being border-buffer-excluded), the mismatch had
to be corrected explicitly. First draw attempt silently produced "0 fresh
candidate sites" - not a real accessibility/distance problem (checked
directly: genuine ~75km separation from the nearest live IDP cluster) but
the shortfalls CSV's `adm2_pcode` join failing on the pcode-format
mismatch. Fixed in `extend_idp_site_level_psu_mobbar_2026-09-03.R`
(`sub("^NGA", "NG", ...)`) before redrawing.

**Partner-package cleanup, found while regenerating FHI 360's package**:
`build_cluster_factsheets.py` writes/copies a docx per cluster but never
deletes one for a cluster that's since left WORKING - FHI 360's Mobbar
`Cluster_guide/` folder still had all 17 of the original (dated 13 Aug,
pre-dating even the 2026-08-31 exclusion) now-inaccessible clusters'
factsheets sitting alongside today's 15 new valid ones. Manually removed
the 17 stale files (`non_idp_NG008023_{1-17}_factsheet.docx`, the plain-
numbered original IDs - today's new ones are all `_supp*`) before telling
FHI 360 they can proceed, so the delivered package can't be misread as
including wards that are still off-limits. **This is a pre-existing gap in
`build_cluster_factsheets.py`, not something this build introduced** - any
other partner whose assignment has shrunk since original delivery likely
has the same stale-file problem in their package folder; not checked/fixed
project-wide today, flagged for a future pass if worth doing systematically.

**Update, same evening**: initially left un-renamed ("v4" hardcoded across
too many scripts to touch unprompted, see below) - Jack then explicitly
asked for the v4->v5 cutover before handing off to Arnold. Done properly:
current (post-Mobbar) v4-named files copied to new v5-named files; v4
files then restored to their pre-Mobbar-build state (from the backup this
build already took) and left frozen as the historical baseline, matching
the 2026-08-31 v2->v3 precedent exactly. All ~23 *durable, reusable*
scripts referencing `_v4_` (every `field_guide_production/*` script, the
`resampling/scripts/` mechanism scripts - `draw_supplementary_*`,
`merge_partner_resample_batch.R`, `analysis_*`, the accessibility-workflow
`0N_*.py` scripts - `stamp_frame_version.R`, `build_partner_coverage_
workbook.py`) repointed to `_v5_` via a scripted sed pass, verified zero
`_v4_` references remain in any of them. **Dated one-off/patch scripts were
deliberately left referencing `_v4_`** (they already ran, already produced
delivered output, and are historically accurate as written - e.g.
`build_v4_frame_2026-08-31.R`, every `patch_*_2026-09-0N.R`, the FACT/DRC
report-builder scripts) - matches this project's own long-standing
convention of not retroactively rewriting completed one-off scripts.
`scripts/stamp_frame_version.R`'s own pre-existing (2026-09-01) archiving
logic then automatically moved the now-superseded v4 CSVs + build log into
`output/data/data_collection/_archive_superseded_versions/` on its next
run - exactly its documented job, not something new added tonight.

**Found and fixed while rebuilding the combined workbook for v5**:
`NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx`'s Strata-Level Summary
sheet was silently reading from `_pipeline_state.pkl`, dated **2026-08-19**
- predating this entire resampling round (FACT/DRC/CARE reviews, the
2026-08-31 accessibility-loss exclusion mechanism, tonight's Mobbar
addition). Its Mobbar row still showed the original pre-exclusion design
figures (coverage_status=covered, achieved_sample=102) as if none of the
last two weeks had happened. Fixed the same way the household-level sheet
was already fixed once before (2026-08-01/02, for the site_radius_m/
tier2_fallback_used patch): read live from the current strata-level FULL
CSV on disk instead of the stale pickle. Coverage Summary sheet
deliberately left sourced from the pickle - its own scope (the one-time
partner-LGA name-matching decision, `match_method` column) genuinely
hasn't changed since 2026-07-30/08-06, unlike Strata-Level Summary which
explicitly claims to be "a rollup of the household-level sheet" and needs
to actually be one. New workbook: `NGA_MSNA_2026_sampling_frame_workbook_
v5.xlsx`; the old `_v2.xlsx` is left in place as the frozen historical
copy, same convention as the CSVs. Full verification (zero content
differences on any row/column common to both v4 and v5, across household
and strata level alike, beyond the intended Mobbar rows) and the partner-
impact breakdown: `resampling/output/resample_runs/FHI360_Mobbar/
2026-09-03/v4_vs_v5_change_summary_2026-09-03.md`.

**Precedent this sets, worth remembering if a similar ask comes up again**:
a ward-level (not LGA-level, not a distance-threshold change) border-buffer
override is now a proven, repeatable pattern - build the specific ward's
hex/site candidates by hand (matching Stage 1's own construction method
exactly), inject them into the relevant `*_sampling`/candidate-frame object
in memory (Non-IDP) or the canonical on-disk frame (IDP site-level), then
run the existing supplementary-draw and merge scripts completely
unmodified. Does not require touching `01_sampling_pipeline_main.R` itself
or rerunning anything nationally.

## Update 2026-09-04 — FACT site-level IDP geometry backfill + Musawa exclusion check (both flagged by 2_monitoring)

Two items 2_monitoring's cleaning-log digest surfaced, worked through the
same day.

**1. FACT site-level IDP geometry gap — same root cause as Mobbar's,
backfilled the same way.** FACT's two site-level IDP batches
(`resampling/output/resample_runs/FACT/2026-09-02_sitelevel/` and
`.../2026-09-03/`) both predate the 2026-09-03 fix to
`draw_supplementary_idp_sites_batch.R` (the one that now writes
`new_clusters_idp.gpkg` automatically — see "Revision 2026-09-03" above),
so neither had ever written geometry: 29 of their 30 drawn clusters were
covered but invisible on the Coverage Map (the 30th, `idp_NG021001_supp1`,
already had geometry from elsewhere — checked directly before backfilling,
not assumed). Fixed via `scripts/one_off_analyses/backfill_fact_sitelevel_
idp_geometry_2026-09-04.R` (same no-redraw, build-from-already-drawn-CSV
pattern as `write_mobbar_idp_geometry_gpkg_2026-09-03.R`) — reran
2_monitoring's `prep_psu_geometries.R` afterward and confirmed 100% (3724
of 3724) of covered cluster_ids now resolve to geometry, up from ~99%.

**Caveat, not yet true "end-to-end" verified**: the 2026-09-03 fix to
`draw_supplementary_idp_sites_batch.R` itself has still never been
exercised by an actual live draw — every site-level IDP batch that has run
(Mobbar, and both FACT batches above) predates it. The fix's code is
verified correct by structural comparison (it's the identical `st_write()`
block, proven twice now via manual backfill), but confirm it produces a
`.gpkg` automatically the next time a real site-level IDP batch is drawn,
rather than assuming it's covered.

**Added, per 2_monitoring's request**: a per-batch completeness check in
`2_monitoring/cleaning/prep/prep_psu_geometries.R` (2026-09-04 block) —
scans every `resample_runs/*/*/` directory directly for a `new_clusters`/
`new_households` CSV with no matching `new_clusters*.gpkg`, and writes a
named, per-directory warning to `SANITY_WARNINGS.txt` if found. This is a
stricter, earlier signal than the pre-existing aggregate overlap-rate
check (which only fires once enough clusters are missing frame-wide) —
verified it correctly reports clean against all 14 real batch directories
after the backfill above, with no false positives against COOPI/INTERSOS/
ZOA/DRC/IMC's differently-named batches.

**2. Musawa LGA (Katsina, `idp_NG021029`) exclusion — checked and
confirmed still accurate, not stale.** 2_monitoring flagged that FACT has
47 real, completed, matched interviews against `idp_NG021029_2` (Sabuwar
Unguwa site, Musawa ward) despite the LGA being `coverage_status =
excluded` / `accessibility_loss_below_population_threshold` since
2026-08-31 (see "Revision" — this mechanism, `build_v3_frame_2026-08-31.R`)
— asked whether the exclusion is stale or FACT needs to be told to stop.
Checked both directly:
- **Not stale**: FACT's own 2026-09-03 accessibility follow-up
  (`resampling/output/resample_runs/FACT/2026-09-03/fact_followup_ward_
  reconciled.csv`) reaffirms all 16 of Musawa's insecure wards as
  `Accessible = No`, reason "Banditry and kidnappings," same 2026-08-24
  report date as the original — unchanged, not a new/updated report. The
  master log (`master_accessibility_status_ward_level.csv`) matches
  exactly, `status_source = confirmed_by_partner_report`. This was a
  direct, partner-confirmed security assessment at exclusion time
  (idp_NG021029 showed **0.0% population remaining** — full exclusion, not
  a marginal call) — not a default-unreported artifact like Damasak was.
- **FACT is not "still actively fielding" there**: checked submission
  dates directly, not assumed. Every real submission across every Musawa
  cluster (`idp_NG021029_2`, `_10`, `_14`, `non_idp_NG021029_5`, `_6`,
  `_12` — 83 rows total) falls between **2026-08-27 and 2026-08-30**,
  entirely before the 2026-08-31 exclusion took effect. Zero submissions
  in Musawa on or after 2026-08-31. The 47 (48 raw, 1 quality-excluded)
  interviews correctly count toward Collected but not Achieved — that's
  the intended behaviour for real pre-exclusion fieldwork under a design
  that later closed the LGA, not a bug or an ongoing violation. No frame
  change made; none needed.
- **Worth relaying to FACT, not acted on unilaterally**: their field team
  kept collecting in Musawa through 2026-08-30 — six days after their own
  2026-08-24 security report. Possibly an internal comms lag between
  FACT's access/security reporting and their field operations team, or an
  already-in-progress round finishing out before the report was acted on
  — worth FACT knowing this gap exists, not something this project can
  explain from the data alone.

## Revision 2026-09-05 — daily partner sampling-points workflow, and a real national achieved-tracking bug found and fixed along the way

**Context.** Jack asked for a new, repeatable (daily/every-other-day) refresh of each partner's `<Partner>_sampling_points_summary.xlsx` (lives in `3. External coordination\NGA MSNA 2026 Package\<Partner>\`), so partners can tell what they've already collected vs. what's still needed without relying on the dashboard/KML alone (direct trigger: a FACT phone call). Built and prototyped on FACT first, per Jack's explicit rollout choice, before this expanded into something much bigger (see below) — the other 18 partners have **not** been regenerated with the new mechanism yet, pending that review.

**New/changed mechanism, part 1 — the workbook itself**
(`scripts/field_guide_production/build_partner_dc_packages.py`):
- **"Sampling Points" sheet** now sourced from FULL (not WORKING, which the KML files still correctly use) with three new columns: `Achieved`, `Date Collected`, `Collection Status`. Non-IDP rows use an exact `survey_id` join against `real_submissions.csv` (a specific pre-assigned building was or wasn't visited — a real per-point fact). IDP rows are cluster-grain (no fixed physical building per slot — see the IDP field-methodology sections above): `Achieved` is a count ("8 of 12"), not Yes/No.
- **New "Needs Collecting" sheet** — same rows, filtered to `Collection Status` not in (Complete, Inaccessible — see below).
- **New "Cluster Summary" sheet** — one row per cluster (Non-IDP + IDP unified): Target/Reserve/Collected/Achieved/Still Needed/% Achieved/Collection Status/Last Collection Date, with conditional-formatting traffic lights.
- **README** gained a "Last refreshed" timestamp and a partner-level headline block (target/achieved/still-needed/% complete/inaccessible-cluster count) at the top, before the existing per-LGA target table.
- Achieved/is_achieved logic is mirrored (duplicated, not imported — this project's standalone-script convention) from `2_monitoring/dashboard_app/global.R`'s canonical `is_achieved()`/`is_collected()`, so this workbook and the live dashboard are never computing "achieved" two different ways.

**New/changed mechanism, part 2 — daily WORKING refresh**
(`scripts/field_guide_production/refresh_working_frame_daily.R`, new): generalises the one-off achieved-row-drop from `build_v3_frame_2026-08-31.R` into a repeatable step, run before the workbook script. Rebuilds household-level WORKING **fresh from FULL every run** (never chains off yesterday's WORKING — idempotent by construction; if a submission is later invalidated, its point correctly reappears next run rather than staying dropped forever). Non-IDP: exact `survey_id` drop. IDP: count-based per (cluster, primary/reserve), same logic as the Aug-31 script's IDP branch. No version bump — FULL is untouched, only WORKING is overwritten in place. **Also now keeps strata-level WORKING's `achieved_clusters`/`achieved_sample`/`realized_moe_pct` fresh every run** (see the bug below for why this was added) — computed from a *different* intermediate than the household-level output (see terminology note below), not just left to whichever merge script last touched a given stratum.

**The bug this surfaced, and why it matters far beyond one workbook.** While building the above, Jack noticed this workbook's FACT "achieved" total (7,118) didn't match the live dashboard's (6,946) — flagged with "this is exactly the sort of issue I'm persistently seeing across this current workflow" and asked for a full trace before any fix. Traced precisely:

1. **Root bug**: `resampling/scripts/merge_partner_resample_batch.R`'s `recompute_strata()` computed a stratum's `achieved_clusters`/`achieved_sample` by counting every `status=="primary"` row for that `strata_id` in the household-level frame — **with no `ward_accessible_status` filter at all**. A *separate* line in the same script (the `working_new_rows` filter, ~line 196) *does* correctly exclude a row from WORKING if it's already `ward_accessible_status == "Inaccessible"` **at the moment it's first merged in** — but nothing ever rechecked *existing* WORKING rows when their cluster's ward was marked inaccessible *later*, independent of any merge (a ward-level accessibility update, not a resample). Once a row like that was in, it stayed counted in `achieved_sample` forever after, even though its own row correctly carried `ward_accessible_status = "Inaccessible"`.
2. **Scale, verified nationally, not assumed**: `achieved_sample` exceeding `target_sample` is structurally impossible under a correctly-capped supplementary-draw mechanism (supplementary clusters exist to approach a fixed target, never exceed it) — yet 75 of 314 covered strata showed exactly that, some by ~2x (e.g. one FACT IDP stratum: target 96, stated achieved_sample 204). Total overstatement: 2,897 households, across 12 partners (FACT hardest hit, 52 strata). Confirmed via a `2026-09-03` diagnostic snapshot (`patch_fix_working_achieved_sample_staleness_2026-09-03.R`, a *different*, already-partially-applied fix for a related-but-distinct mechanical staleness — WORKING's row **count** not matching its own stated achieved figures — that patch deliberately left `target_sample` untouched, citing "Jack has a separate, already-planned single deliberate target/achieved recalibration pass for after this round" — a plan referenced twice in the codebase and, until today, never executed) that the gap already existed then (74 strata / 2,791 households) — this predates 2026-09-05, it wasn't introduced this session.
3. **Ruled out before fixing**: recomputed `target_sample` fresh via `build_sampling_plan()`'s exact MoE formula (Z=qnorm(0.95), p=0.5, e=0.10, m=6, ICC=0.06, buffer=0.10) against each affected stratum's *current* `N_hh` — **identical to the stated value for all 75 strata, zero exceptions**. So this was never a Mobbar-style "the accessible population genuinely grew, target_sample needs recalibrating" situation — `N_hh` hasn't materially moved for any of them. The apparent "achieved" overshoot was pure miscounting, not real extra fieldwork nor a stale target.
4. **Fix applied**: `recompute_strata()` now takes a `filter_ward_accessible` argument — `TRUE` for the WORKING call (adds `is.na(ward_accessible_status) | ward_accessible_status != "Inaccessible"`, same condition as the existing new-row filter, applied to *every* eligible row on every run, not just newly-merged ones), `FALSE` for the FULL call. `refresh_working_frame_daily.R` mirrors this: strata-level `achieved_clusters`/`achieved_sample` recomputed from `covered_accessible` (covered, not excluded, ward-accessible — **before** the field-achieved-row drop), every covered stratum, every run.
5. **Verified nationally after the fix**: 63 of the 75 affected strata resolved completely; national overstatement 2,897 → 51 households across a small residual of 12 strata. Recomputed `target_sample` for those 12 too — again identical to stated in every case; the residual is normal supplementary-cluster-granularity noise (1–18 households over a clean multiple-of-6 target), not a data problem. **No `target_sample` value was changed anywhere, for any stratum, nationally** — the fix was entirely to the (mis-tracked) achieved side.
6. **FULL deliberately left unfiltered** — checked directly first (0 mismatches nationally between FULL's stated and actual primary-row counts, both before and unaffected by this fix). FULL's `achieved_clusters`/`achieved_sample` is, and should stay, "every row ever drawn for this stratum, regardless of current accessibility" — the complete historical record. Only WORKING's copy of these columns is meant to mean "currently fieldable right now," which is what needed the filter.

**IMPORTANT TERMINOLOGY, worth restating precisely if this area is touched again** — strata-level `achieved_clusters`/`achieved_sample` has *never* meant "how many real interviews have been completed." It's a **design metric**: how many primary slots has the sampling design successfully assigned (compared against `target_sample`, the MoE-driven need). This is completely different from the **field-completion** "achieved" concept (`is_achieved()` against `real_submissions.csv`) that decides which household-level rows to drop from WORKING and what the workbook's `Achieved`/`Collection Status` columns show. `refresh_working_frame_daily.R` computes both, from two different intermediates, on purpose — using the field-achieved-row-dropped household output to recompute strata-level `achieved_sample` would silently invert its meaning into "how many are still outstanding."

**A related design decision, made deliberately, not a bug**: should a cluster's real, already-completed interviews stop counting toward `Achieved` once its ward becomes inaccessible? Checked directly before deciding — 417 real completed interviews nationally (159 Non-IDP + 258 IDP) sit in clusters currently marked inaccessible. **No** — `Achieved`/`Collected` (workbook and Cluster Summary) keep full credit for real completed work regardless of current accessibility; only `Still Needed` floors to 0 and `Needs Collecting` excludes such clusters. This needed a 4th `Collection Status` value, `Inaccessible`, alongside the existing Complete/Partial/Not started — distinct from Complete (so a partner doesn't mistake "we don't need more here because it's unsafe" for "we don't need more here because it's done") and distinct from Not started (so nobody is told to go somewhere currently unreachable). The README headline block splits accordingly: "Total target"/"Still needed" exclude inaccessible clusters (your active, currently-askable workload); "Achieved so far" doesn't (real work isn't erased by an area becoming unreachable afterward); a transparency line discloses the inaccessible-cluster count and how much achieved credit sits inside it, so nothing is silently dropped either direction.

**A genuine (non-bug) wrinkle found and worth remembering**: a Non-IDP hexagon can straddle two wards with *different* current accessibility status — verified directly, 221 clusters do (e.g. `non_idp_NG008010_16`'s 12 household rows split 5 "Aduwa"/Inaccessible, 7 "Guzamala West"/Accessible). `ward_accessible_status` correctly varies **per row** (per building) in this case, not per cluster — always check the specific row/cluster in hand, never aggregate a cluster's status to one value (an early verification pass in this same session got this wrong and produced a false-positive "4,358 inaccessible rows still showing" alarm before this was understood).

**Downstream propagation**: `scripts/stamp_frame_version.R` rerun; corrected `NGA_MSNA_2026_stage2_sampling_frame_v5_WORKING.csv` and `NGA_MSNA_2026_strata_level_sampling_frame_v5_WORKING.csv` copied into `2_monitoring/input_data/sampling_frame/` (old copies archived to `_archive_2026-09-05_pre_ward_filter_fix/`, matching this project's established downstream-copy convention). **Checked, doesn't change what the dashboard displays**: `TOTAL_PLANNED_INTERVIEWS`/`partner_progress_by_lga`'s `target_sample` comes from `strata_frame`, which was never wrong (see point 3 above) — unaffected. The dashboard's own `achieved_n` was *always* computed independently, fresh from `real_submissions.csv` via `compute_progress_by_stratum()`/`cluster_targets` (from `psu_hexagons_sf`/`psu_sites_sf`, itself FULL-derived and unaffected by this fix) — never read the strata CSV's `achieved_sample` column at all, so it was never actually wrong on its own terms either. The propagation matters for anything that *does* read strata-level `achieved_sample`/`achieved_clusters` directly (the internal partner digest, any future report), and so the next partner merge starts from a correct baseline instead of an inflated one.

**Update, same evening — both remaining residuals chased down and resolved, per Jack's explicit follow-up ask ("likely happening across different partners as well").** Diffed the workbook against the dashboard at STRATUM grain (not just national totals) for FACT — found two separate, genuine causes, one a real bug and one a legitimate metric difference:

1. **The 172-household achieved gap was a real, distinct bug** — in `build_partner_dc_packages.py`'s `idp_cluster_summary_row()` (the Cluster Summary sheet only — `idp_primary_metadata_row()`, the Sampling Points sheet's IDP `Achieved` column, was already correct). It computed `Achieved` from `cluster_collected_n` (`is_collected()` — just `interview_outcome == "completed"`, no other check) instead of the stricter `cluster_achieved_n` (`is_achieved()` — also non-duplicate, matched, not quality-excluded), silently letting duplicate/unmatched/quality-excluded submissions inflate Achieved. Every single affected stratum in the diff was IDP; zero were Non-IDP (whose Achieved was always computed from the strict per-`survey_id` `achieved_date_by_survey_id`, never from either cluster counter). Fixed by using `cluster_achieved_n` for IDP's Achieved, same as the Sampling Points sheet already did — `Collected` correctly keeps `cluster_collected_n` (its own definition genuinely calls for the loose count). **Verified nationally, not just for FACT**: after the fix, FACT's workbook achieved total is 6,946 — an **exact** match to the dashboard, and the strata-level diff shows **zero** remaining achieved discrepancy anywhere, not just in aggregate. While in there, found and fixed the mirror-image mislabeling on the Non-IDP side: Cluster Summary's `Collected` column was reusing the strict achieved-only count too (didn't affect `Achieved`'s own correctness there, but meant `Collected` wasn't showing what its own definition promises) — now uses `cluster_collected_n` like IDP's.
2. **The target gap is not a bug** — confirmed by tracing the per-stratum diff precisely: before this fix, differences went both directions and partly canceled (net −10); a real remaining imprecision was found and fixed along the way (below), after which every single per-stratum difference is negative and the pattern is fully coherent with current ward-inaccessibility, not noise. Dashboard's `target_sample` is a fixed, MoE-driven design ceiling that has never accounted for ward-level accessibility at all (see point 3 above — recomputing it against current `N_hh` reproduces the exact same figure). This workbook's `Total target (your currently active clusters)` is deliberately a live, accessibility-aware "what are we currently actually asking you to do" figure — necessarily smaller wherever a stratum has substantial current inaccessibility (e.g. `non_idp_NG008001`/Abadam, Borno: only 53 of 161 primary rows nationally-ward-accessible, most of its original 17 Stage-1 clusters now inaccessible — target_sample stays frozen at 102 regardless). These are legitimate, different metrics answering different questions, not the same number computed two ways — forcing them to match would mean discarding real information one way or the other. The README's headline block already frames this explicitly (separate "Total target (active)" vs "Achieved so far (all real interviews, including any since become inaccessible)" lines, plus an inaccessible-cluster disclosure line) precisely so this isn't confusing to a partner reading it.
3. **Real imprecision found and fixed while chasing #2**: `non_idp_cluster_summary_rows()`'s `Target HHs (primary)` used to count a straddling cluster's FULL nominal row count (all 6, say), not just its currently-accessible portion — inflating "Total target (active)" for the ~221 clusters whose hexagon spans two wards with different status (see the straddling-ward note above). Fixed: `Target HHs (primary)` in Cluster Summary is now the accessible-primary-row count specifically; `Achieved` still caps against the NOMINAL (full-cluster) target so real credit already earned is never reduced just because the accessible-portion cap shrank; `Still Needed` is computed directly as "accessible primary rows not yet achieved" (not `target − achieved` arithmetic, which would have been ambiguous once `achieved` can legitimately exceed the now-smaller `target` for a partially-credited straddling cluster); `Collection Status` = Complete is now driven by `Still Needed == 0`, not by comparing achieved against a target that no longer means what it used to. This fix is why FACT's active target moved from 14,714 → 14,073 (more accurate, not a regression) while the gap against the dashboard's fixed 14,724 widened slightly — expected, since making the "active" figure more precise necessarily pulls it further from a metric that was never trying to measure the same thing.
4. **One benign non-finding, checked and ruled out**: exactly one IDP cluster nationally (`idp_NG021001_9`) has mixed per-row `ward_accessible_status` — but it's `Accessible` vs `NA` (a later-added supplementary batch whose accessibility hadn't been classified yet at the time), not a real ward split. `NA` already correctly defaults to accessible (the project's established "unclassified defaults to accessible" convention) — no fix needed, this doesn't behave like the Non-IDP straddling case at all.

## Update 2026-09-05b — same-day follow-through: the <4-accessible-household threshold, national representativity check, and the weekend supplementary-draw plan

Continuing straight on from "Revision 2026-09-05" above (the ward-
accessibility achieved-tracking bug and its fix) - same evening, working
through the consequences with Jack in real time rather than as a separate
session.

**Decision: straddling Non-IDP clusters with fewer than 4 accessible
primary households are treated as fully inaccessible, not just the
literal 0-accessible case.** Discussed at length before deciding (not
picked unilaterally): the alternative of resampling the missing 1-2
households from the SAME hex's accessible remainder was considered and
rejected - checked directly, 217 of 220 straddling Non-IDP clusters
nationally still have spare eligible-building pool for this to even be
possible, but Jack's own instinct (asked, not assumed) was that same-hex
replacements skew toward the inaccessible ward's boundary, i.e. exactly
the least reliable/highest-risk households to actually collect - the same
concern that already argued for stratum-level (not same-hex) supplementary
draws being the right compensation mechanism. A blanket "any straddling
cluster is inaccessible" rule was checked and rejected too - of 184
straddling Non-IDP clusters, 46 have 5 of 6 (or equivalent) STILL
accessible, clearly still worth collecting. The threshold (4) is Jack's
own explicit call after seeing the shape of the distribution (0-20%
accessible: 47 clusters; 80-100%: 46 clusters - not lopsided, a genuine
threshold decision, not derivable from the data alone).

**Implementation - same threshold, same counting basis, in all three
places that needed to agree** (the exact class of "different mechanisms
computing the same thing differently" problem this whole evening has been
about - deliberately not repeated here):
- `build_partner_dc_packages.py`: `NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH = 4`,
  `cluster_accessible_primary_n` (count of ward-accessible primary rows
  per Non-IDP cluster, computed once nationally), `_row_effectively_
  inaccessible(r)` (the shared check every call site now uses - a row is
  effectively inaccessible if its OWN ward is inaccessible, OR - Non-IDP
  only - its whole cluster has fallen below the threshold). IDP is
  deliberately unaffected: `_row_effectively_inaccessible()` only invokes
  the threshold for `pop_type == "non_idp"` - IDP sites are single-point
  (a DTM GPS location, not a hexagon), so there's no "proportion
  accessible" concept for them at all, just the same binary check that's
  always existed. Confirmed directly with Jack, who'd independently
  reasoned through the same distinction and wanted it verified in the code
  rather than just asserted.
  - Applied consistently to Sampling Points (`non_idp_metadata_row`,
    `idp_primary_metadata_row`), Cluster Summary (`non_idp_cluster_
    summary_rows`, `idp_cluster_summary_row`) - Target HHs and Still
    Needed both show 0 for a below-threshold or fully-inaccessible
    cluster (not the true small accessible count) so the row reads
    consistently; Achieved/Collected keep full real credit regardless
    (capped at the NOMINAL, not accessible-reduced, target - real work
    already done is never erased by a cluster later falling below
    threshold or losing accessibility entirely).
  - **Bug fixed in the same pass, predates today's threshold discussion**:
    `idp_cluster_summary_row()`'s "Target HHs (primary)" used to still
    show the full nominal target next to a "Complete"/"Inaccessible"
    status - inconsistent, since Still Needed already correctly zeroed.
    Found while checking IDP wasn't wrongly picking up the Non-IDP-only
    threshold logic. Now zeroes Target HHs too when inaccessible, matching
    the Non-IDP side.
- `refresh_working_frame_daily.R`: same threshold constant and counting
  basis, applied when building `covered_accessible` (drops the WHOLE
  cluster's rows, not just its individually-inaccessible ones, for any
  Non-IDP cluster below 4 accessible primary households) - both the
  household-level WORKING output and the strata-level achieved_sample
  recompute inherit this correctly since both are derived from
  `covered_accessible`. Rerun nationally: 145 clusters dropped entirely
  (480 rows), household-level WORKING 46,362 -> 45,924 rows. Verified: 0
  duplicate survey_ids, Musawa still correctly excluded.
- `merge_partner_resample_batch.R`: same threshold applied to
  `working_new_rows` (computed from `full_hh_new` - existing + this
  batch's rows together, so a repeat-site merge pushing an EXISTING
  cluster below threshold is caught, not just brand-new clusters). This
  is defense-in-depth, not the sole enforcement point - refresh_working_
  frame_daily.R rebuilds WORKING wholesale on its own cadence regardless
  and would catch this the next time it runs either way.

Propagated: `stamp_frame_version.R` rerun, corrected WORKING files (both
levels) copied to `2_monitoring/input_data/sampling_frame/` (previous
copies archived), FACT's workbook rebuilt and reverified clean (0 rows
inconsistent between Collection Status and Target/Still Needed, both pop
types).

**National representativity check, requested explicitly by Jack after
seeing the fix's effect** (314 covered strata):
- **Undersampling**: 89 strata (28%) currently short of `target_sample`,
  1,346 households total - concentrated overwhelmingly in FACT (66 strata,
  1,002 households, 74% of the national gap); the rest spread thinly
  across IMC, INTERSOS, Save the Children, FHI 360 (one stratum, Mafa,
  carrying 74hh alone), CARE, COOPI, ZOA, PLAN, Street Child, Solidarités.
- **Oversampling**: only 4 strata, trivially (4-18 households over a
  102/96-household target) - down from 12 before the threshold fix, reads
  as ordinary cluster-rounding, not a systemic problem.
- **Realized-MoE outlook** (if everything CURRENTLY accessible were fully
  collected): 285 of 314 strata (91%) would meet the 10% target; 29 (9%)
  would not, even at 100% success on what's currently accessible.
- **Of those 29, checked against `analysis_remaining_eligible_pool.R`'s
  live remaining-candidate-pool output** (the project's own existing
  mechanism for exactly this question, rerun fresh rather than assumed
  stale): only **3 are genuinely population-exhausted** - `idp_NG034010`
  (Kebbe), `idp_NG037010` (Maru), `idp_NG021025` (Malumfashi-IDP), all
  IDP, all with zero remaining accessible-and-unselected DTM sites. **23
  have a comfortable remaining pool** (a supplementary draw should close
  them). **3 are marginal** - some pool exists but even the full remaining
  pool's upper bound falls short of the gap (`non_idp_NG008001`/Abadam,
  `idp_NG037009`/Maradun, `idp_NG021003`/Batsari-IDP - would improve, likely
  still land above 10%). The 3 exhausted strata have no path forward
  through ordinary supplementary drawing - only a Mobbar-style targeted
  ward reopening (a partner confirming access to a currently-inaccessible
  ward there) could add new eligible population; otherwise this is a real,
  disclosed design limitation, not something fixable by drawing harder
  against the same known universe.

**Decision: hold off on running the supplementary draw tonight.** Jack has
multiple new partner accessibility reports and recovery-workbook
deletion decisions landing tomorrow (2026-09-06) - both would materially
change the exact inputs this whole analysis is built on (new reports
change `ward_accessible_status`, i.e. everything above; recovery-workbook
deletions directly reduce `achieved_sample` for whatever gets confirmed
invalid/duplicate). Running the supplementary draw tonight risked being
based on a picture that's superseded within a day, and - concretely -
FACT alone has already had four separate resample batches this week;
landing a fifth tonight and a sixth tomorrow was judged not worth it
against waiting one day for a single, comprehensive batch. **Plan, as
agreed: hold off, then run ONE comprehensive supplementary-draw batch over
the weekend of 2026-09-06/07, incorporating tomorrow's new accessibility
reports, the recovery-workbook deletions, and everything already fixed
tonight, sequenced FACT first (74% of the gap) then a combined batch for
the other partners.** Same reasoning extends to partner-facing rollout of
the new daily workbook mechanism itself: FACT's workbook is built,
verified, and ready, but reflects tonight's fixes only - holding off
sharing it (with FACT or rolling out the other 18) until after the weekend
batch too, so partners get one accurate update rather than two within
days of each other. **Nothing partner-facing has been sent as a result of
tonight's session** - all changes are local/internal (frame files, 2_
monitoring's copies, the not-yet-distributed FACT workbook prototype).

**For whoever picks this up next** (this session or a fresh one): before
running the weekend batch, re-run this same representativity check first
(strata-level WORKING's `achieved_sample` vs `target_sample`, plus
`analysis_remaining_eligible_pool.R`) against whatever tomorrow's
accessibility reports and recovery-workbook deletions actually change -
the 89/1,346/29/3 figures above are a 2026-09-05 snapshot, not guaranteed
current by the weekend. **Superseded already, same evening - see
"stranded-achieved" below, which changes these to 80/1,128/29/3 before
tomorrow's new information is even factored in.**

## Update 2026-09-05c — "stranded-achieved" credit: real collected data was being double-asked-for once its area became inaccessible

**Context.** Before agreeing to run the weekend supplementary-draw batch,
Jack raised a concern worth pausing on: for clusters that become fully
inaccessible, or straddling clusters dropped by the <4-accessible-household
threshold just added, what happens to real data ALREADY collected there?
Two cases asked about specifically: (1) a whole area with substantial
collected data later becomes inaccessible - are those samples just lost?
(2) a straddling cluster has 1-3 accessible households remaining and gets
dropped entirely by the threshold rule - if those 1-3 were already
collected, do they still get discarded even though the data itself is
fine?

**Finding: partner-facing reporting was already correct; the actual gap
was one level down, in the design metric that sizes the supplementary
draw.** Checked directly before concluding either way (this project's
standing "verify, don't defend" practice) - the workbook's Achieved/
Collected columns and the dashboard already preserve full credit for real
completed interviews regardless of current accessibility (the "Update, same
evening" achieved-credit-preservation decision earlier tonight covers
this). Nothing there needed fixing. But strata-level `achieved_sample` -
the DESIGN metric compared against `target_sample` to decide how many
households the supplementary draw should ask for - is a pure row-count of
*currently accessible* design slots, blind to whether an excluded row
already produced a real completed interview. Both of Jack's cases are the
same underlying mechanism at different scopes (Case 1: a row excluded
directly via `ward_accessible_status`; Case 2: a whole cluster's rows
excluded via the threshold rule) - a real completed interview sitting in
either kind of excluded row was being silently treated as still-
outstanding capacity, inflating the shortfall the weekend batch would size
its supplementary draws against. Not a data-loss bug - a double-ask risk:
asking partners for new households to replace work that's already done.

**Quantified nationally before implementing, not assumed:**
- 341 real completed interviews nationally are "stranded" this way - 147
  Non-IDP (exact `survey_id` match against currently-excluded rows), 194
  IDP (cluster/status count-based, capped at `min(excluded rows in that
  cluster, real achieved count)` so it can never over-credit past what's
  real).
- Of the 89 strata then on the shortfall list (1,346 households), 25 had
  overlap, totaling 254 stranded households.
- 9 strata needed **zero** supplementary draw at all once corrected - they
  were only on the list because of this undercounting (e.g. `idp_NG021003`:
  target 102, showed shortfall 30, but had 35 stranded-achieved sitting in
  excluded rows).

**Fix - Jack approved implementing immediately ("yes go ahead and make
this change now"), same evening, ahead of the weekend batch:**
- `refresh_working_frame_daily.R`: `strata_agg` (feeds strata-level
  WORKING's `achieved_clusters`/`achieved_sample`) now unions
  `covered_accessible`'s primary rows with a `stranded_rows` set - rows
  excluded from `covered_accessible` (ward-inaccessible directly, or
  below-threshold Non-IDP cluster) that ALREADY have a real completed
  interview. Non-IDP: exact `survey_id` join against
  `achieved_non_idp_survey_ids` (already computed for the household-level
  drop). IDP: count-based per cluster, capped the same way as the national
  quantification above, specific rows picked deterministically (lowest
  `interview_number` first, since IDP achieved is inherently count-based,
  not tied to one physical slot). Household-level WORKING (the to-do list)
  is deliberately untouched by this - a stranded-achieved row correctly
  stays OUT of the to-do list, nobody should be sent to an inaccessible
  building; this fix only restores its credit to the design-capacity
  count.
- `merge_partner_resample_batch.R`'s `recompute_strata()`: same principle,
  Non-IDP/IDP logic identical. **Also fixed a related, previously-
  unnoticed issue found while implementing this**: the function's WORKING
  call used to read from `working_hh_new`, but `working_hh` (loaded fresh
  from the on-disk WORKING CSV) already has field-achieved rows dropped by
  the last daily refresh - counting achieved_sample from it silently
  UNDER-counted current design capacity by however many rows that to-do-
  list drop had already removed, the opposite-direction sibling of the
  stranded-achieved bug this section fixes. In practice transient (the next
  daily refresh always overwrote it), but there's no reason to leave a
  merge's own immediate output wrong in the meantime. Fixed by having
  `recompute_strata()` read from `full_hh_new` (every row ever drawn,
  achieved or not, accessible or not) for BOTH calls, and do its own
  complete ward-accessible filtering plus stranded-achieved crediting
  internally - self-contained, matching `refresh_working_frame_daily.R`'s
  approach exactly. **Deliberately scoped to `ward_accessible_status` only,
  not the <4 threshold rule** - matches this script's existing, already-
  documented defense-in-depth split (the threshold rule's full enforcement
  lives in `refresh_working_frame_daily.R`'s repeatable cadence; this
  script only applies it to brand-new `working_new_rows` at merge time,
  same as before). Not exercised end-to-end yet (no real merge has run
  since) - verified only by a clean parse/syntax check (`Rscript` with no
  args reaches the expected usage-error `stop()`, confirming the whole file
  parses); the underlying algorithm is identical to
  `refresh_working_frame_daily.R`'s version, which IS fully verified below.

**Verified after running `refresh_working_frame_daily.R` with the fix:**
household-level WORKING unchanged (45,924 rows, byte-identical md5 to
before - confirms this fix is correctly scoped to the strata-level design
metric only, doesn't touch the to-do list). Strata-level WORKING: 27
strata changed `achieved_sample`. National shortfall recomputed fresh from
the corrected file: **80 strata short (was 89), 1,128 households total
(was 1,346) - exactly the predicted 218-household/16.2% reduction**, first
computed as a diagnostic, then reproduced exactly by the actual fix once
applied. 9 strata now show `achieved_sample` slightly over `target_sample`
(was 4) - expected and fine, not a new problem: this is real stranded
credit that turned out to already exceed target once properly counted, the
same "ordinary cluster-rounding" character as the pre-existing 4, not
systemic over-collection asked of anyone.

**Checked, doesn't affect the FACT workbook or the dashboard**:
`build_partner_dc_packages.py` never reads strata-level `achieved_sample`
for its Target/Achieved/Collected figures (its only strata-level CSV
reference, `STRATA_CSV`, is a frozen 2026-08-06 archive used purely for the
`adm2_pcode` → state/LGA name lookup) - both are computed fresh from
household-level FULL/WORKING + `real_submissions.csv` directly, same as
already established in "Revision 2026-09-05". So this fix changes the
supplementary-draw sizing only, not anything already shown to a partner or
on the dashboard.

**Propagated**: `stamp_frame_version.R` rerun; corrected strata-level
WORKING (household-level unchanged, re-copied anyway for consistency)
copied to `2_monitoring/input_data/sampling_frame/` (previous copies
archived to `_archive_2026-09-05_pre_stranded_achieved_fix/`).

**For whoever picks this up next**: the weekend batch's shortfall
generation should use the corrected 80-strata/1,128-household baseline (or
re-derive it fresh from strata-level WORKING, which now already has this
fix baked in) - not the 89/1,346 figures from earlier tonight. Top
remaining shortfalls after this fix: `non_idp_NG008019` (74hh),
`non_idp_NG008001`/Abadam (54hh), `idp_NG037010`/Maru (36hh - one of the 3
genuinely population-exhausted strata), `idp_NG034010`/Kebbe (30hh - also
exhausted), `non_idp_NG008026` (25hh), `idp_NG021025`/Malumfashi-IDP (24hh
- also exhausted), `idp_NG037009`/Maradun (24hh - one of the 3 marginal
strata). **Superseded already, next day - see 2026-09-06 below.**

## Update 2026-09-06 — quality_exclusion_reason precision fix, per Jack's confirmed-deletion policy decision

**Context.** Ahead of today's comprehensive resampling batch, this project
is now being coordinated across multiple Claude Code sessions (this one,
`2-monitoring-ba`, and a root-level orchestrator session Jack is using to
route decisions and reconcile cross-session state - see the multi-session
architecture audit exchange earlier today for the full picture of how that
works). Jack settled a policy question via the orchestrator: deletion
confirmation requires a genuine, deliberate decision (a partner's recovery-
workbook response, or a reviewed internal call) - never an automatic/
timeout default. As of today, the `recovery_issue_tracker.csv`-based
confirmed-deletion process (2_monitoring's side) has exactly 10 registered
`confirmed_deletion`-type issues, all still contested - so nothing there
currently counts as confirmed.

**Why this reached this project's own code.** The canonical `is_achieved()`
mirror in this repo (`refresh_working_frame_daily.R` and, since last night,
`merge_partner_resample_batch.R`) filters on `real_submissions.csv`'s own
`quality_exclusion_reason` column directly - never on
`CONFIRMED_QUALITY_EXCLUSIONS.csv` or `combined_deletion_log.rds` (grep-
confirmed: neither is referenced anywhere in `1_sampling`). Checked what's
actually in that column before assuming the policy applied or didn't: 578
rows, every single one either `duration_under_20` (547) or `fcs_zero` (31)
- clearly a blanket automated survey-quality screen (duration/FCS
thresholds), not the tracker's 10 hand-reviewed cases. Flagged this
mismatch back rather than guessing, since dropping the filter outright
would have flipped 514 otherwise-achieved-eligible households from
not-achieved to achieved nationally - too large a swing to act on without
confirming intent first.

**Jack's resolution**: `duration_under_20` and `fcs_zero` specifically
bypass the recovery-workbook appeal process entirely and go straight to
`confirmed_deleted` (`confirmed_by=internal_team`) - validated
methodological thresholds from piloting (under 20 minutes genuinely can't
cover the questionnaire; all-8-FCS-components-zero is implausible as a real
response), not ambiguous judgment calls needing field input. Every other
quality-exclusion category the pipeline can produce (GPS-duplicate-point,
`pct_missing_flagged`, `no_consent`, `listing_missing`) remains
**unconfirmed** - achieved-eligible for now, pending the tracker/recovery-
workbook process. `no_consent` specifically noted as a candidate for the
same auto-confirm treatment later (the data officer's own cleaning-log
design already categorizes it the same way as duration/fcs_zero - "admits
no remedy at the household's own level") but Jack hasn't ruled on it yet -
left unconfirmed until he does.

**Fix**: both files' `achieved <- subs %>% filter(...)` block changed from
`quality_exclusion_reason %in% c(NA, "", "NA")` (blank = OK, ANY non-blank
value excludes) to `!(quality_exclusion_reason %in%
CONFIRMED_QUALITY_EXCLUSION_REASONS)` where `CONFIRMED_QUALITY_EXCLUSION_REASONS
<- c("duration_under_20", "fcs_zero")` - an explicit inclusion-list of only
the two confirmed values, not an "anything non-blank" catch-all. This is a
precision fix, not a behavior change today: verified directly that these
two values are the ONLY ones currently populated, so old and new logic
produce identical results against today's data - but it protects against
the pipeline someday populating `no_consent`/`listing_missing`/etc. and
those rows being silently (and wrongly) excluded before Jack has actually
confirmed them. Explicitly a stopgap - 2_monitoring is building the real
mechanism (tracker wiring, a version-stamped overlay file that will
eventually replace both `CONFIRMED_QUALITY_EXCLUSIONS.csv` and
`combined_deletion_log.rds` as the actual "confirmed for resampling"
source) - switch over once that's ready and verified.

**Deliberately NOT mirrored into `build_partner_dc_packages.py` yet** - the
Python side has its own `_is_achieved()` mirror of the same canonical
formula, but Jack wants partner workbook updates held until after today's
resampling is fully done (there's a bigger workbook update coming anyway
and he doesn't want partners' workbooks rewritten twice in one day). Do
this same fix there before the next workbook rebuild, or the R and Python
sides will disagree on quality-exclusion handling - exactly the class of
drift bug this whole project has been chasing all week.

**Incidental finding while verifying**: `real_submissions.csv` had been
refreshed by 2_monitoring since last night's stranded-achieved fix (14,587
-> 15,426 rows, modified 2026-09-04 17:11 -> 2026-09-06 12:33) - the
604-row household-level WORKING change and 2 newly-fully-achieved clusters
seen when re-running `refresh_working_frame_daily.R` just now are almost
entirely this fresh submission data landing, NOT a consequence of the
quality_exclusion_reason fix itself (confirmed: that fix alone is a
verified no-op against both the old and new real_submissions.csv snapshot,
since only duration_under_20/fcs_zero exist in either). Re-running instead
of trusting last night's numbers is exactly the "re-hash/re-read at the
start of your stage" discipline agreed with the orchestrator earlier today
- it already caught real, fresh field data landing that would otherwise
have gone unnoticed.

**Propagated**: `stamp_frame_version.R` rerun, corrected WORKING files
(both levels) copied to `2_monitoring/input_data/sampling_frame/` (previous
copies archived to `_archive_2026-09-06_pre_quality_exclusion_precision_fix/`).

## Update 2026-09-06b — 05_build_accessibility_impact_workbook.py repointed to CONFIRMED_DELETIONS_OVERLAY.csv

**Context.** Same day, continuing the multi-session coordination ahead of
the comprehensive resampling run. `05_build_accessibility_impact_workbook.py`'s
`load_real_achieved()` (feeds the MoE/Feasibility/resampling-need columns
specifically - see that function's own docstring) was reading a deletion
log via `glob.glob()` on `revised_deletion_log_for_resampling_*.csv` in
`2_monitoring/cleaning/real/handoff_for_resampling/` - last fed
2026-08-30_v2, 8 days stale. 2_monitoring built a deliberate replacement,
`2_monitoring/data/CONFIRMED_DELETIONS_OVERLAY.csv`, sourced from the
tracker-based confirmed-deletion process (`recovery_issue_tracker.csv`).

**Not a straightforward repoint - two rounds of independent verification
caught real problems before this was trusted:**
1. **First version of the overlay (1,818 rows) was wrong**: 1,628 of its
   "confirmed" rows carried `reason="duration_under_30"` - a category never
   approved (Jack's decision was specifically `duration_under_20`/
   `fcs_zero` only) and absent from `real_submissions.csv`'s own
   `quality_exclusion_reason` entirely. A direct spot-check against
   `real_submissions.csv`'s `duration_min` for 3 of those uuids found 42.1,
   427.95, and 94.46 minutes - none under 30. Flagged, not implemented.
2. **Second version (637 rows, `duration_under_30` removed) still failed a
   spot-check**: 4 of 5 sampled `duration_under_20` uuids showed
   `duration_min` of 41.69, -49.90 (negative), 153.08, and 45.77 minutes in
   `real_submissions.csv` - only 1 of 5 genuinely under 20. Flagged again,
   still not implemented.
3. **Resolution, verified at the code level, not taken on the orchestrator's
   word**: `duration_min` in `real_submissions.csv`
   (`2_monitoring/cleaning/real/prep_real_submissions.R:358`) is raw
   wall-clock time (`difftime(end, start, units="mins")`). The
   `duration_under_20` rule itself
   (`2_monitoring/cleaning/MSNA_Data_Cleaning/R/deletion_log.R:109-121`)
   uses a completely different figure, `duration_audit_sum_all_minutes` -
   an audit-log-derived *active-editing-time* sum, built via
   `load_or_build_audit_durations()`/`add_audit_duration_from_cache()` in
   `audit_cache.R`. Confirmed this really is a distinct, real, established
   concept in this codebase (not invented after the fact to explain away the
   finding) - `build_workbook_fn.R` independently describes
   `duration_under_20` as "audit-based" in partner-facing copy. So
   comparing the classification against `duration_min` was never a valid
   check - wrong field, not a wrong classification. **One claim did NOT
   check out even after this**: the orchestrator said all 5 flagged uuids
   were checked against `CONFIRMED_QUALITY_EXCLUSIONS.csv`'s audit-based
   duration and found genuinely short - directly checked, and none of the 5
   uuids exist in that file at all (it's a 578-row file, exactly matching
   `real_submissions.csv`'s own current `quality_exclusion_reason` count -
   likely just an older/narrower export that predates the ~43-row tracker
   expansion these particular uuids came from). Proceeded anyway since the
   *mechanism* is independently confirmed sound at the code level even
   though that specific verification claim wasn't accurate - worth knowing
   for whoever next takes a report from that orchestrator chain at face
   value.

**Fix**: `DELETION_LOG_CSV`'s glob-discovery block replaced with a direct
path constant `CONFIRMED_DELETIONS_OVERLAY_CSV`, and `load_real_achieved()`'s
`deletion_uuids` now filters `status == "confirmed"` explicitly (the overlay
also carries `status == "contested"` rows - 10 as of this writing, none
finalized - which must NOT be treated as deleted, matching Jack's "no
automatic/timeout default" policy). Join key (`uuid` both sides) verified
compatible with the old mechanism, no code change needed there. Unused
`import glob` removed.

**Verified by actually running the script**, not just a syntax check: "627
deletion-log rows applied" - exactly matching the overlay's confirmed count
(625 `confirmed_by=internal_team` + 2 `confirmed_by=partner`), correctly
excluding all 10 contested rows. Workbook and
`..._WORKING_with_accessibility.csv` regenerated cleanly.

## Update 2026-09-06c — four new/updated partner accessibility files reviewed, three resolved and ingested, one held for the partner

Jack brought in four partners' worth of accessibility updates the same
evening (ACF, FACT, Malteser, PLAN) ahead of staging the comprehensive
resampling run, and asked for each to be reviewed for issues before
ingesting - then, given the recurring pattern of partners sending back
imperfect data, asked to resolve as much as possible tonight rather than
lose more days to round-trips. Outcome per partner:

**FACT - fixed, ingested clean.** Their returned workbook (both Ward and
Cluster Accessibility sheets) predates the `% of target achieved so far`
column existing on their specific template - would have hit a `KeyError`
in `02_ingest_accessibility_reports.py` as-is. Fixed with the same
defensive `if "..." in idx` guard already used for Cluster ID/Pop Type/the
provenance columns (line ~103) - missing column now means "unknown" (`""`),
not a crash. Verified by actually running the ingest: 4,235 reported rows,
4,158 new/changed. This was the largest of the four by far.

**Malteser - one real data-corruption bug found and fixed, everything else
was already fine.** Their email named 5 clusters
(`non_idp_NG007013_5`, `non_idp_NG021022_2/6/8/4`) where both primary and
reserve are inaccessible - all verified as real, currently-covered clusters
in the live frame. Checked the Cluster Accessibility sheet (not just Ward)
before assuming anything was missing: it already had clean, correctly
detailed per-cluster entries for every one of these (North Bank 1 portion
of `non_idp_NG007013_5`; all four Wurma A/B clusters) - the ambiguous-
looking Mbalagh ward row (Accessible=Yes despite an Insecurity/conflict
reason and a "only one point" note) turned out not to be a problem at all,
since the real single-point issue is captured correctly at cluster grain
and the ward genuinely is mostly fine. The actual bug was in the Ward
Accessibility sheet: "Wurma A" and "Wurma B" each appeared **twice** - one
row an untouched template default (cluster count 3, "Not Among the
assigned samples"), the other Malteser's real dated answer (Accessible=No,
09-02) but with the State field corrupted to the literal string `"h"`
instead of `"Katsina"` and implausible cluster counts (22/20 instead of 3).
Scanned the entire sheet for other corrupted State values first (found
none elsewhere) before fixing just this one cell. Original file preserved
as `Malteser_accessibility_report_ORIGINAL_AS_RECEIVED_2026-09-06.xlsx.bak`
before editing. Verified after the fix, both via a clean ingest run (50/50
rows new/changed, no errors) and by checking the rebuilt master log
directly: Wurma A/B both correctly show `State=Katsina,
Accessible=Inaccessible, Reporting partner=Malteser`; Mbalagh/North Bank 1
correctly split (Accessible/Inaccessible respectively).

**Master accessibility log rebuilt and propagated** after FACT + Malteser:
`02_ingest_accessibility_reports.py` then `04_build_master_accessibility_
status.py`, both run for real (not dry-run). Result: 2,165 ward-LGA
portions total, 1,740 now confirmed by a partner report, 648 flagged
Inaccessible, 425 still on the default-accessible/not-yet-reported status.
Copied to both `2_monitoring/dashboard_app/input_data/accessibility/` and
`2_monitoring/input_data/accessibility/` (previous copies archived to
`_archive_2026-09-06_pre_fact_malteser_ingest/` in each), and
`_accessibility_version.txt` refreshed by hand in both locations (no
script writes this file anywhere in the codebase - it's a manually
maintained manifest, apparently started by whichever session created it
originally) with an explicit note that PLAN and ACF are NOT included in
this build.

**PLAN - explicitly NOT ingested, sent back to the partner instead.** Their
returned workbook is unusable as filed: every row in both Ward and Cluster
Accessibility sheets has `Accessible (Y/N)`/`Reason category` blank - PLAN
wrote their actual determinations into the free-text "Note" column instead
(confirmed: ingest run correctly showed "0 reported rows" for PLAN, exactly
matching this). Jack's read, independent of the parsing problem: several of
the Note-column entries look like they may be marking a WHOLE ward
inaccessible for what's actually a specific point/cluster-level issue (e.g.
Abbaram's note is about "the coordinates" being at a military base, not
the ward generally) - a recurring risk this partner was already warned
about once (see the 2026-08-27 draft response in
`resampling/input/partner_raw_comms/PLAN/`, which explains the ward-vs-
cluster tab distinction). Decision: don't guess through the ambiguous rows.
Built `resampling/input/accessibility_reports_generated/PLAN_accessibility_
report_FOLLOWUP_2026-09-06.xlsx` - a copy of PLAN's own returned file with
only the 5 unambiguous rows (Shehuri, Kasugula, Kumshe, Soye - all "data
collection was conducted in the community" - and Rann - "accessible")
transcribed into the proper columns; everything else left for PLAN to
complete directly. Drafted
`resampling/input/partner_raw_comms/PLAN/draft_response_email_2026-09-06.txt`
for Jack to send, explaining the column issue, naming the specific
ambiguous wards (Abbaram; the four relocation cases - Bogomari, Gulumba,
Magarta, Yabiri; and 7 bare "in accessible" wards with no reason given),
asking whether Jarawa's traceable-within-Rann population is being
correctly re-pointed rather than silently dropped, and offering a call.
**Nothing from PLAN is in the master accessibility log as of this
update** - holding entirely until they respond, per Jack's explicit
instruction ("before anything else moves forward").

**ACF - held, not actioned, per Jack's own call.** No formal workbook was
returned - only an email table (reached/unreached locations by LGA:
Bodinga, Gwadabawa, Tambuwal). Parsed the table properly from the email's
raw HTML (not the flattened plain-text body, which loses the merged-cell/
rowspan structure) and cross-checked every location name against the real
ward list for those three LGAs - the reconstruction holds up well (e.g.
"Jabo-" + "Kagara" split across two HTML rows is genuinely one ward,
confirmed against the frame), with two residual loose ends ("Huchi" grouped
under the wrong LGA in ACF's table; one unresolved fragment, "Town").
Available if needed at `_scratch`-style analysis, not written anywhere
permanent since ACF's own email says they're waiting on their sub-partner
STCI's data before sending a "consolidated list" - Jack chose to wait for
that rather than act on an admittedly-provisional partial list, and is
emailing ACF to prompt them.

**Update, same evening - Jack changed course and asked for ACF's parsed
data to go into their actual template now**, rather than wait. Filled
`resampling/input/accessibility_reports_generated/ACF_accessibility_
report.xlsx` (ACF's own previously-shared template, not a fresh generic
one) directly - 23 ward rows across Bodinga/Gwadabawa/Tambuwal, matched by
exact ward name against the frame (compound names like "Takatuku Madorawa"
correctly assembled from the email's two separate fragments). Original
preserved as `ACF_accessibility_report_PRE_2026-09-06_update.xlsx.bak`.
**Caught and fixed a real ward-name-collision bug while filling it**: the
first pass matched "Sabon Birni" by ward name alone (not scoped by LGA) and
wrongly filled Tambuwal's Sabon Birni row too - Sabon Birni exists as a
ward name in BOTH Gwadabawa and Tambuwal, and only Gwadabawa's was ever
mentioned in ACF's email. Caught via a row-count mismatch (24 filled vs 23
intended) before it went out - exactly the class of bare-ward-name-lookup
risk this project has been warned about before (see
`02_ingest_accessibility_reports.py`'s own header note on why ward
expansion must always be scoped to a specific LGA). Two items from the
original email couldn't be placed at all and were left out rather than
guessed - "Gidan"/"dawaki." (Gwadabawa) and "Town" (Tambuwal) don't match
any ward in the frame. Two items flagged with an explicit note in the
workbook itself for ACF to confirm rather than silently corrected: "Huchi"
(email grouped it under Bodinga; it's actually a Gwadabawa ward) and
"Nabaguda" (matched to "Barkeji-Nabaguda", the closest real ward name).
Draft response saved to `resampling/input/partner_raw_comms/ACF/
draft_response_email_2026-09-06.txt`, per Jack's exact wording - thanks
them, asks that all further accessibility information go directly into
this workbook, and looks forward to the STCI-inclusive update. **Not
ingested into the master accessibility log** - this is what's going TO
ACF, not a return from them; nothing changes on the master-log side until
they send the workbook back.

## Update 2026-09-07 — comprehensive resampling run, part 1: main frames refreshed, FACT's supplementary draw merged, three real latent bugs found and fixed in the draw pipeline itself

**Context.** 2_monitoring finished their partner-response deletion review
(tracker: 639 confirmed / 10 contested) and confirmed `real_submissions.csv`
was freshly copied. Jack asked to proceed with the full comprehensive
resampling run - main sampling frames first, then KML files, then partner
workbooks - sequenced FACT first (agreed, ~70% of the national gap), with
the 3 genuinely-exhausted IDP strata (Maru/Kebbe/Malumfashi-IDP) to simply
be disclosed as a hard limit rather than chased further.

**Pre-run readiness check caught a real gap**: the tracker had grown past
`duration_under_20`/`fcs_zero` since the previous night (639 confirmed, up
from 627) via the genuine partner-confirmation channel - `no_consent`
(x10), `duplicate_point` (x2), `gps_no_match_partner_confirmed` (x2), all
`confirmed_by=partner`. The 2026-09-06 hardcoded-reason-list stopgap in
`refresh_working_frame_daily.R`/`merge_partner_resample_batch.R` would have
silently missed these. Fixed by repointing both scripts to read
`CONFIRMED_DELETIONS_OVERLAY.csv` directly (`status=="confirmed"` →
`submission_uuid` exclusion set) - the same mechanism
`05_build_accessibility_impact_workbook.py` already used since the previous
night. No more hardcoded list to remember to update as the tracker moves.
Verified `real_submissions.csv`'s own `quality_exclusion_reason` currently
matches the overlay exactly (2_monitoring keeps it synced deliberately),
but the overlay is read directly regardless, not inferred from that column,
given it went stale/corrupted once already this week.

**Main frame refresh**: ran clean. Household-level WORKING correctly grew
by 28 rows (newly-un-confirmed interviews reappearing on the to-do list);
strata-level achieved_sample unchanged (none of the 12 net-new confirmed
deletions happened to be stranded-achieved rows). Propagated to
2_monitoring.

**Fresh national picture before any drawing**: 80 strata short / 1,127
households (down slightly from two nights ago - accessibility gains and
new deletions roughly cancelled out nationally, though individual strata
moved). Re-ran `analysis_remaining_eligible_pool.R` (3 days stale) too: 24
strata (down from 29) would miss 10% MoE even at 100% success on the
currently-accessible population - 3 genuinely exhausted (unchanged: Maru,
Kebbe, Malumfashi-IDP, all IDP, zero remaining candidate sites), 2 marginal
(Abadam, Maradun), 19 comfortable-pool. By partner: FACT 57 strata/794hh
(70% of the gap), then IMC/FHI 360/INTERSOS/Save the Children and smaller
amounts elsewhere.

**Three real, previously-latent bugs found and fixed while running FACT's
draw** - all in the shared small-batch/edge-case path (a thin Tier 2
repeat-draw round), none previously exercised hard enough to surface them:

1. **`load_building_footprints()`'s own integrity check
   (`02_stage2_building_ingestion.R`) crashed on a legitimately-empty
   result.** A small candidate batch (Tier 2 fallback, just 4 hexes) found
   zero buildings across all 3 Google Open Buildings parts -
   `process_single_gdb()` already logs "0 chunk file(s)" as a normal
   completion for that case, but `unlist()`-ing three empty vectors gives
   `character(0)`, and the old `stopifnot(length(part_cache_files) > 0 ...)`
   treated that as "caching failed" and crashed the ENTIRE draw before
   anything was written to disk - including a fully successful 107-cluster
   Tier 1 round. Fixed: `length(part_cache_files) == 0 || all(file.exists(...))`
   - preserves the real integrity check (any file that IS returned must
   actually exist) while allowing the legitimate empty case through.
2. **Two `hex_building_counts` blocks in `04_stage2_cluster_reallocation.R`
   assumed `round_building_files` was never empty.** Once (1) was fixed,
   `round_building_files` could legitimately be `character(0)` - `bind_rows()`
   over zero files produces a columnless empty tibble, and the subsequent
   `count(uuid_hex_pop, ...)`/`distinct(uuid_hex_pop, .centroid_key)` calls
   errored with "column not found" rather than correctly meaning "zero
   eligible candidates this round." Fixed both call sites with an explicit
   `if (length(round_building_files) == 0)` short-circuit to a correctly-shaped
   empty tibble.
3. **A Tier 2 (repeat-draw) candidate could get a cluster-level metadata row
   with zero actual households.** When a repeat-draw candidate's hex turned
   out to have nothing genuinely unclaimed left (the same building pool
   already used by the existing cluster), the cluster row was still kept,
   producing a `new_clusters`/`new_households` cluster_id set mismatch much
   later with no indication why (`draw_supplementary_clusters_batch.R`).
   Fixed with two layers: (a) drop any cluster with zero households
   immediately after Stage E.1, before renumbering (caught 7 of 8 cases
   live); (b) a belt-and-suspenders final check right before the
   equality assertion that drops any orphan on either side and logs it
   loudly, since one case (a Tier 2 candidate, `..._supp26`) still slipped
   past (a), root cause not fully pinned down under time pressure - flagged
   in the code for whoever next touches this path, since it survived a
   filter that should have caught it and the exact mechanism (something
   about its `.source`/renumbering interaction) wasn't chased down further
   given the other 114+ clusters in the batch were genuinely fine.

**A genuine, deliberate "call a human" check did its job correctly, not a
bug**: after fixing the above, Abadam's (`non_idp_NG008001`) Tier 2 repeat
draw hit a REAL building_id overlap with the existing live frame (5 of 20
repeat-draw clusters would have duplicated already-assigned households).
This check (`draw_supplementary_clusters_batch.R`, "does NOT redraw or
touch the existing cluster - only fails loudly... a call for a human, not
this script") is explicitly designed not to auto-resolve this. Given
Abadam was already known "marginal" (thin remaining pool) from the
exhaustion analysis, excluded Abadam entirely from this batch rather than
force a fix - its shortfall stays open, consistent with what was already
expected and already agreed to be disclosed.

**FACT draw results**: Non-IDP - 114 new clusters, 1,308 households, 45
strata (from a nominal shortfall of 46 strata; Abadam excluded per above).
IDP site-level - 10 new clusters, 120 households, 7 of 11 strata fully
closed (the 4 unclosed: Kafur, Malumfashi-IDP, Kebbe, Maradun - all
candidate-pool-exhausted under current DTM data, 3 of which were already
in the known-exhausted/marginal set). Merged via `merge_partner_resample_
batch.R` (unmodified) after archiving `output/data/data_collection/` to
`_archive/2026-09-07_pre_fact_resample_merge/`: FULL 110,950 → 112,378 rows,
WORKING 45,348 → 46,767. All 52 affected strata now show `realized_moe_pct`
under 10% (8.51-9.46%) except the excluded/exhausted ones. Propagated to
2_monitoring.

**National picture after FACT**: shortfall dropped from 80 strata/1,127hh
to **31 strata/487hh**. FACT's own remaining shortfall: 8 strata/154hh -
Abadam (54hh, excluded from this batch), 3 small residuals (Dan Musa/
Matazu/Safana, 4/4/2hh - lost a handful of households to the empty-cluster
drop, genuinely no more buildings available there either) plus the 4
already-known-exhausted/marginal IDP strata. By partner, remaining: IMC
(78hh), FHI 360 (74hh, one stratum/Mafa), INTERSOS (72hh), Save the
Children (50hh), and smaller amounts for CARE, COOPI, Solidarités, PLAN,
ZOA, Street Child - this is the combined batch for the next stage.

**For whoever picks this up next**: KML files and partner workbooks have
NOT been touched yet - Jack's explicit priority order was main frames
first. `build_partner_dc_packages.py` (the partner workbook builder) still
needs the same `CONFIRMED_DELETIONS_OVERLAY.csv` repoint as the other two
scripts before it's rerun for anyone. The bug fixes in
`02_stage2_building_ingestion.R`/`04_stage2_cluster_reallocation.R`/
`draw_supplementary_clusters_batch.R` are in the SHARED pipeline - they'll
also apply automatically to the combined batch for the other 10 partners,
not something to redo.

## Update 2026-09-07b — comprehensive resampling run, part 2: combined batch for the other 10 partners turned out to be almost entirely closed already by FACT's merge

**Context.** Picking back up after a pause, Jack confirmed to proceed with
the combined supplementary draw for the 10 partners left over from part 1
(IMC, FHI 360, INTERSOS, Save the Children, CARE, COOPI, Solidarités, PLAN,
ZOA, Street Child), reported at the time as 31 strata/487hh nationally.

**That 31/487 figure was stale and materially overstated - caught before
drawing anything, not after.** `resampling/output/NGA_MSNA_2026_
accessibility_impact_workbook.xlsx` still had an mtime from 2026-09-06
20:29, i.e. from BEFORE FACT's merge (02:01 on 09-07) - the 31/487 number
in part 1's own writeup was never actually re-derived from a regenerated
workbook post-merge. Re-ran `05_build_accessibility_impact_workbook.py`
fresh, then cross-checked its "Additional clusters needed" column two
independent ways: (1) filtering the regenerated workbook's Strata Level
sheet by `Partners covering` for the 10-partner group, (2) filtering
`output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v5_
WORKING.csv` directly by `partners_covering` and `realized_moe_pct > 10`.
Both converged: only 2 strata in the whole 10-partner group still show any
shortfall at all - **not 31**. Root cause of the stale figure: FACT jointly
covers most of the same LGAs as these 10 partners, so FACT's own merge
(part 1) already closed nearly every shared-coverage gap; the 487hh number
was carried forward from before that merge's effect was reflected anywhere.

Of the 2 remaining strata:
- **idp_NG037010 (Maru, Zamfara, INTERSOS)** - `Remaining eligible pool: 0`.
  This is one of the 3 already-known genuinely-exhausted IDP strata (see
  part 1 and the exhaustion analysis) - Jack's own prior decision was to
  disclose this as a hard limit, not chase it. Excluded from the draw,
  consistent with that decision, not a new judgment call.
- **non_idp_NG008019 (Mafa, Borno, FHI 360)** - the one real, drawable
  shortfall. `Remaining eligible pool: 85`, target 10 additional clusters.
  (IMC's two Kankia strata that showed >10% in the raw strata CSV,
  `non_idp_NG021020`/`idp_NG021020`, are NOT a resampling gap - the
  workbook's own "at full completion of currently-assigned PRIMARY slots"
  projection is under 10% for both (9.87%); IMC simply hasn't finished
  fielding against clusters they already have. Confirmed this is a
  fielding-completion distinction, not a bug in the workbook's shortfall
  formula, by reading both metrics side by side for these two strata.)

**Draw + merge for Mafa** - same unmodified mechanism as every other
partner this round (`draw_supplementary_clusters_batch.R` →
`merge_partner_resample_batch.R`), archived `output/data/data_collection/`
first to `_archive/2026-09-07_pre_combined10partner_resample_merge/`.
Shortfalls CSV built by hand (single stratum, not worth invoking
`extract_partner_shortfalls.R` for one row). Tier 1 alone resolved the full
shortfall - no Tier 2 needed, no empty-cluster drops, no orphans, none of
the three part-1 bugs re-triggered. 15 new clusters/108 new household rows
drawn; 10 rows excluded from WORKING (inaccessible/below-threshold, kept in
FULL only). Merged cleanly: FULL 112,378 → 112,486, WORKING 46,767 →
46,865. `non_idp_NG008019`: achieved_clusters 3→18, achieved_sample 0→92,
realized_moe_pct 17.68%→9.74%. Propagated to `2_monitoring/input_data/
sampling_frame/` (archived the pre-propagation state there too, same
pattern as part 1). Did NOT touch `2_monitoring/dashboard_app/input_data/
sampling_frame/` - that mirror wasn't touched by part 1's propagation
either, so treating it as 2_monitoring's own deploy-staging copy, not
something this project pushes into directly.

Harmless pre-existing cosmetic warnings seen during this merge (`Unknown or
uninitialised column: cluster_id/survey_id`, x6): these come from
`merge_partner_resample_batch.R`'s own preflight `stopifnot` block doing
`$cluster_id`/`$survey_id` on a genuinely-empty (0-column) `tibble()` when
a partner has nothing staged for IDP-hex/IDP-site/existing-cluster-
expansion, which happened for all three here since this was a Non-IDP-only
batch. `NULL %in% x` still correctly evaluates to `logical(0)`/`any() ==
FALSE`, so the check itself is unaffected - didn't fix, since the script is
deliberately kept unmodified/proven across every partner this round and
the correctness isn't in question, just flagging so it isn't mistaken for
a new bug next time it's seen.

**Maradun (idp_NG037009, Zamfara, FACT) - attempted, and a real methodology
bug found in the process.** The workbook said `Remaining eligible pool: 2`,
`Feasibility: Closeable with a modest top-up`. Ran the real mechanism
anyway (`draw_supplementary_idp_sites_batch.R`) rather than trusting that
number - it found **0 fresh candidate sites**, same "candidate-pool-
exhausted under current DTM data" result FACT's own part-1 batch already
hit for this exact stratum. Chased why the workbook and the real draw
mechanism disagree: `analysis_remaining_eligible_pool.R` (which feeds the
workbook's IDP "Remaining eligible pool"/"Feasibility" columns) marks a DTM
candidate site as already-used via an **exact `site_id` string match**
against `working$iom_site_id` (line 212-215); `draw_supplementary_idp_
sites_batch.R`'s own Stage B instead matches already-fielded sites by
**30m GPS proximity** - the correct approach for this project (see project
memory "IDP site-level PSU redesign") specifically because pre-redesign
clusters don't reliably carry a real matching DTM `site_id`. Maradun's two
existing clusters both carry `iom_site_id = "New HC"` - a generic
placeholder, not a real DTM code - so the exact-match script can never
recognize them as "used," and over-counts the LGA's remaining pool.
**Scanned nationally for the same pattern**: 14 strata have at least one
IDP cluster with a generic placeholder `iom_site_id` ("New HC" x17, "New
Camp" x5, "New Integrated" x2 - 24 clusters total, out of 801 IDP clusters
nationally): Gombi/idp_NG002004, Makurdi/idp_NG007013, Konduga/
idp_NG008016, Bakori/idp_NG021001, Kankia/idp_NG021020, Safana/
idp_NG021032, Bokkos/idp_NG032003 (x2), Shagari/idp_NG034014 (x3),
Tambuwal/idp_NG034018 (x7), Tangaza/idp_NG034019, Nangere/idp_NG036012,
Bungudu/idp_NG037005, Maradun/idp_NG037009 (x2), Talata Mafara/
idp_NG037012. **Not fixed here** - `analysis_remaining_eligible_pool.R` is
a shared analysis script, changing its matching logic would shift the
reported "Feasibility" label for all 14 strata at once, which is a
communication point for Jack, not something to change mid-batch unasked.
Recommend swapping the exact match for the same 30m proximity match
already proven in `draw_supplementary_idp_sites_batch.R`, next time someone
is in this script - flagged, not fixed.

**National picture after both merges**: every stratum across all 19
partners is now within its 10% MoE target except 5 - all genuinely
exhausted, all disclosed rather than resampled further: the 3 already-known
IDP strata (Maru/idp_NG037010, Kebbe/idp_NG034010, Malumfashi-IDP/
idp_NG021025), **Maradun/idp_NG037009 (now confirmed a 4th, via the real
draw mechanism, not just the workbook's stale number)**, and Abadam
(non_idp_NG008001, excluded from FACT's batch per the real building_id
overlap check).

**For whoever picks this up next**: main sampling frames are now fully
done for this round - both parts of the comprehensive run are merged and
propagated. KML files and partner workbooks are still untouched.
`build_partner_dc_packages.py` still reads `quality_exclusion_reason`
directly (line ~374) rather than `CONFIRMED_DELETIONS_OVERLAY.csv` - same
gap already fixed in the other three consumer scripts this week - fix this
before running it for real, not after. Both `build_partner_dc_packages.py`
and `build_partner_lga_boundary_kml.R` write into `3. External
coordination/NGA MSNA 2026 Package/<partner>/` - **outside this git repo
entirely, un-versioned, and directly partner-facing** - worth a deliberate
go-ahead before regenerating across all ~19 partners, not something to run
casually the way the internal frame refresh can be.

## Update 2026-09-07c — `analysis_remaining_eligible_pool.R` IDP proximity-match fix, applied and verified

**What changed.** `analysis_remaining_eligible_pool.R`'s IDP "already used"
check (flagged in Update 2026-09-07b) switched from an exact `site_id %in%
iom_site_id` string match to the same 30m GPS-proximity match
`draw_supplementary_idp_sites_batch.R` already used - live IDP points read
fresh from the FULL frame (unfiltered by coverage_status/exclusion_reason,
for parity with that script), matched by physical location instead of a
label. Also fixed, found only while testing this: 2 raw DTM rows (`site_id`
"New HC" at lat 115264553, "KN_H043" at lat 1205077 - both clearly garbage,
not real coordinates) produced empty geometry after projection and NA
`st_distance` results; harmless before by accident (an empty geometry
already fails every `st_join`/`st_nearest_feature` match, so these 2 rows
always fell out of scope anyway) but not safe to leave implicit once a
direct distance computation depends on it. Added an explicit `abs(lat) <=
90, abs(lon) <= 180` filter at the same point raw rows are already
filtered for NA - correct-by-construction, not a Nigeria-specific
heuristic, and consistent with this file's own stated aversion (in its own
header) to silently treating "couldn't determine" as "fine."

**Verified the fix corrects the bug in BOTH directions, not just the one
that motivated it:**
- **Understatement (Maradun's own case, part 2b)**: an LGA whose *own*
  existing clusters carry a placeholder ID never gets recognized as
  "used," inflating that LGA's own pool.
- **Overstatement (newly found while verifying) - Kaura Namoda
  (`idp_NG037008`, Zamfara)**: had 4 real, still-open candidate sites
  wrongly marked "used" under the old logic, because they too happened to
  be raw-DTM-labeled `"New HC"` - a generic placeholder that recurs
  **248+ times across unrelated real sites nationally in the raw DTM data
  itself**, not just in the sampling frame. The old exact-match check
  compared against `iom_site_id %in% used_idp_sites` with no LGA scoping,
  so Kaura Namoda's own "New HC" candidates got wrongly matched against
  the 33 *other* LGAs' clusters that also carry that exact same
  placeholder string. Confirmed directly: none of those 33 owning clusters
  are anywhere near Kaura Namoda. `idp_NG037008` pool: 0 -> 4.
  Both directions share one root cause - `iom_site_id` is not a reliable
  unique key wherever a placeholder label is involved, in the raw DTM
  source data as well as the sampling frame; only physical location is.

**National result**: `remaining_eligible_pool_idp.csv` accessible-
unselected sites, 2,342 -> 2,254 (net -88), but not uniform - **72 LGAs
changed, most down, several up** (full list and per-LGA before/after in
this update's own working notes, not reproduced here). Old CSV kept as
`resampling/output/gis/remaining_eligible_pool_idp_PRE_PROXIMITY_FIX_2026-
09-07.csv.bak`. Accessibility impact workbook regenerated against the
corrected pool.

**Does this change anything about tonight's actual draws (Jack's direct
question)? No - and that's expected, not a gap.** Every real draw tonight
(Mafa, Maradun, all of FACT's part-1 batch) already used the correct
mechanism (`draw_supplementary_clusters_batch.R` / `draw_supplementary_
idp_sites_batch.R`), never this analysis script - this fix only corrects
what the *workbook reports*, not what was actually drawn. Checked every
IDP stratum with a live shortfall against the corrected numbers: Bakori
(already closed by FACT, unaffected), Kafur/Kebbe/Malumfashi (already
correctly pool=0 before and after, unaffected) - no change to any
conclusion already acted on.

**What it DOES change: a 6th genuinely-exhausted stratum was hiding behind
the bug.** **Dan Musa (`idp_NG021007`, Katsina, FACT)** - needs 1 more
cluster, realized MoE at full completion of assigned primary slots 10.16%.
Old logic showed pool=3 - enough to look potentially closeable; corrected
logic shows **pool=0, `Feasibility: Not closeable - no remaining pool
left`**. This wasn't touched by anyone's batch tonight - it surfaced only
because this fix was run. Worth adding to whatever list Jack presents
alongside Maru/Kebbe/Malumfashi-IDP/Maradun/Abadam - it's a 6th case, not
a duplicate of the Non-IDP `non_idp_NG021007` (also Dan Musa LGA, but a
different stratum/pop_type, already documented in part 1 as one of
FACT's 3 small residuals lost to the empty-cluster drop - coincidence of
LGA name only, not the same underlying issue).

**One residual discrepancy found and NOT resolved - flagged, not fixed.**
Re-checking Maradun specifically against the real draw's own ground truth
(0 fresh sites, confirmed in part 2b): the corrected analysis script still
shows pool=1, not 0. Chased it down: the 1 remaining "unselected" candidate
is `ZF_R021` (13hh, 7.3km from the nearest live cluster - genuinely not
already used). But `ZF_R021` does not exist anywhere in `input_data/
population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds` - the
actual curated candidate frame the real draw script draws from - not
filtered out by site_type or population category, just absent from that
snapshot entirely. Checked nationally: no `_R###`-prefixed site_id survives
into that RDS at all (site_frame's own prefixes are H/INT/REL/S/"New
X" only), while the raw DTM source data (`IMPACT_IOM_DTM_NCNW_R18.csv` /
`IMPACT_IOM_NGA_R51_NE.csv`, what `analysis_remaining_eligible_pool.R`
reads directly) does contain `_R`-prefixed sites (Maradun alone has 3:
ZF_R019/021/022). Don't know whether this is a deliberate exclusion
(these might be a site category - e.g. "Registration point" -
legitimately out of scope for household sampling) or the site-level frame
being incomplete/stale relative to the raw source it was built from on
2026-09-02 - haven't chased that further, since it's a materially bigger
question (does the real draw mechanism's candidate universe need
expanding, nationally, not just for Maradun) than the reporting bug this
update set out to fix. For practical purposes tonight this changes
nothing - Maradun is still correctly treated as exhausted, since the real
draw mechanism (the one that actually matters for a real draw) already
returned 0 regardless of what this analysis script says. Flagging as a
distinct open question for whoever next looks at the site-level PSU
frame's own completeness, not something to silently resolve either
direction without Jack's input.

**Resolved same night by msna-n-wec-2026-4c**: pulled ZF_R021's raw
`Population Category` directly - `"Returnees"`, a genuinely different
population category from IDPs, not a data gap. Checked nationally: the
`_R`-prefix corresponds to `"Returnees"` in 555/555 and 823/825 rows across
the two raw DTM files (the small remainder is mislabeling noise, not
counter-evidence); H/INT/REL/S prefixes correspond just as cleanly to their
own IDP sub-categories. `idp_site_level_psu_frame_2026-09-02.rds` correctly
excludes Returnee sites - not stale, not incomplete, no national
candidate-universe question for Jack after all. Root cause of the residual
pool=1-vs-0 was simpler: `analysis_remaining_eligible_pool.R` wasn't
filtering by population category at all before this, so it was counting
Returnee sites into the IDP pool. Fixed immediately (same session, low-risk
- confirmed with the peer session before proceeding, not needed for
something this contained): added `population_category` to both raw-file
`transmute()` calls and filtered `!= "Returnees"` right before the
proximity-match step. Re-ran: Maradun's own `remaining_eligible_pool_idp.csv`
row now reads `accessible_unselected_sites = 0` - exact match with the real
draw mechanism's ground truth. National IDP pool total revised again:
2,254 -> 1,467 accessible-unselected sites (1,420 Returnee-category rows
were being wrongly counted in nationally, not just at Maradun). Workbook
regenerated once more against this fully-corrected figure. No open
questions remain from this thread.

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
  Since 2026-08-22: run `scripts/stamp_frame_version.R` after any refresh
  of `output/data/data_collection/` (see `output/README.md`) — writes
  `_frame_version.txt`, which downstream sanity checks compare their own
  copied version against to catch a stale copy automatically, since the
  static-copy rule above otherwise gives them no way to tell.
- **`Rscript` is not on PATH in this session's shells (bash or PowerShell)
  - check for this specifically before concluding R is unavailable.** R
  IS installed: `C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\
  bin\x64\Rscript.exe`, confirmed 2026-08-27 with all packages this
  project's R scripts need (sf, terra, dplyr, exactextractr, readr)
  present and working. Call that full path directly instead of bare
  `Rscript`. Earlier the same day, before this was found, "R not
  available" led to direct-patching already-generated CSV/xlsx files
  instead of properly rerunning the R sequence (see Revision 2026-08-27's
  Solidarités fix) - those patches are correct and don't need redoing,
  but don't repeat that workaround now that the real path is known.
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

## Incident 2026-09-07 — tonight's resampling drew into wards already known Inaccessible; purged and redone

**What happened.** FACT's and Mafa/FHI 360's supplementary draws (this same
night, documented above) were merged into WORKING/FULL believing they
closed real coverage gaps. They didn't, for a majority of FACT's Non-IDP
batch. Found while chasing an unrelated workbook/merge-log disagreement:
`draw_supplementary_clusters_batch.R`'s ward-accessibility pre-filter reads
`resampling/output/gis/accessible_area_lga_ward_portions.shp` - a
standalone GIS layer, last rebuilt 2026-09-03, that nothing regenerates
automatically before a draw. `master_accessibility_status_ward_level.csv` -
the real, continuously-updated source of truth - had moved on 3 more days
by the time FACT's draw ran (2026-09-07 02:00), including new partner
reports marking several Nganzai/Gubio/Guzamala wards Inaccessible. The
draw filtered candidates against the stale picture and drew from them
anyway. Checked directly against every household row actually drawn:
**714 of 1,308 FACT Non-IDP rows (55%, 72 of 114 clusters)** landed in a
currently-Inaccessible ward; 12 of 120 FACT IDP site-level rows; 4 of 108
Mafa rows.

**A second, compounding bug, found while investigating the first.**
`idp_site_level_psu_frame_2026-09-02.rds` (the IDP draw's own candidate
frame) carries its own baked-in `accessible_status` column from its
2026-09-02 build - same staleness, frozen even longer. Refreshed by
rejoining it against the freshly-rebuilt ward layer (surgical - only the
`accessible_status` column touched, site identity/PPS weights/geometry
untouched); backup at `input_data/population/sampling_frame/idp_site_
level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-07.rds.bak`.

**Why the merge's own existing safety net didn't catch it either.**
`merge_partner_resample_batch.R` already excludes any new row whose
`ward_accessible_status == "Inaccessible"` from WORKING (keeping it in
FULL) - a real, working mechanism. But by the same script's own comment
(line ~190), a genuinely new cluster's `ward_accessible_status` is
deliberately left NA at merge time ("not computed until `04_build_master_
accessibility_status.py`'s next run... matching this project's established
'unclassified defaults to accessible' convention"). Traced where that
"next run" was actually supposed to populate it: nowhere. Neither
`04_build_master_accessibility_status.py` (builds the ward-level master
file only) nor `refresh_working_frame_daily.R` (filters on the column,
never computes it) ever performs the household-level join that would turn
NA into a real value for a brand-new row. The intended second safety net
doesn't exist as code - only as a comment describing an assumption. NA
defaulted to "accessible" and sailed through the same exclusion filter
that would have correctly caught these rows if they'd been labeled.

**Fix applied for tonight's redo, and now a permanent part of the
pipeline**: a new utility, `resampling/scripts/stamp_ward_accessible_
status.py`, populates `ward_accessible_status` on a staged
`new_households.csv` via the same precise (adm1_name, adm2_name,
adm3_name) -> master-CSV lookup `05_build_accessibility_impact_workbook.py`'s
`classify_households()` already uses (proven correct all night) - applied
to every staged batch before merging, so the merge's existing exclusion
logic finally has real data to act on. Not yet wired in as an automatic,
un-skippable step of the draw scripts themselves - see "still open" #1
below.

**Purge and redo, in order:**
1. Rebuilt `accessible_area_lga_ward_portions.shp`/`.csv` fresh from the
   current master status (`analysis_accessible_area_layer.R`, standalone
   recompute, safe to rerun).
2. Refreshed `idp_site_level_psu_frame_2026-09-02.rds`'s `accessible_status`
   column (above).
3. Restored `output/data/data_collection/`'s v6-named files to the exact
   pre-tonight state (from `_archive/2026-09-07_pre_fact_resample_merge/`) -
   undoing both the FACT and Mafa merges in one step. Tainted post-merge
   state preserved for the record at `_archive/2026-09-07_TAINTED_pre_
   stale_ward_purge/` (not for reuse).
4. Re-ran `analysis_remaining_eligible_pool.R` + `05_build_accessibility_
   impact_workbook.py` against the clean baseline + corrected ward layer -
   this is the first genuinely trustworthy shortfall picture of the night:
   **67 strata short nationally** (not the 31 or 8 reported earlier - those
   numbers were built on the tainted merge).
5. Redrew FACT (`extract_partner_shortfalls.R` fresh -> 50 Non-IDP strata/
   243 clusters, 12 IDP strata/15 site-level clusters; 11 Non-IDP + 5 IDP
   strata still genuinely exhausted after Tier 2 - real exhaustion this
   time, not a stale-filter artifact), stamped `ward_accessible_status` on
   the staged output, merged. **665 of 3,251 new rows excluded from
   WORKING** (inaccessible-ward and/or below-threshold - correctly, this
   time), included in FULL only.
6. Redrew Mafa/FHI 360 (10 clusters -> 14 drawn, then a 1-cluster top-up
   once the corrected numbers showed it 0.35pp short of target), same
   stamp-then-merge. Both fully closed: `non_idp_NG008019` realized_moe_pct
   9.85%.
7. **Independent, final sign-off check** (not just trusting the
   `ward_accessible_status` column - a fresh direct cross-check against
   `master_accessibility_status_ward_level.csv` by every new row's own
   adm1/adm2/adm3): **2,688 of 2,688 household rows from tonight's redo,
   verified, zero in a currently-Inaccessible ward.**
8. Propagated corrected v6 files to `2_monitoring/input_data/sampling_
   frame/` (prior, tainted mirror archived first, not discarded).

**Final verified state**: FULL 114,311 rows, WORKING 48,036 rows
(+2,688 net vs. the clean pre-tonight baseline - smaller than the original
tainted batch's headline numbers, because this one is real). 40 strata
still show a genuine shortfall nationally after this round (down from 67).

**Found, NOT fixed tonight - flagged, needs a deliberate decision, not a
rushed one under this morning's deadline**: the SAME independent cross-
check run against the ENTIRE WORKING frame (not just tonight's rows) found
**5,629 rows nationally sitting in a currently-Inaccessible ward** per the
master status, despite passing the `ward_accessible_status` column check.
This is the pre-existing, ORIGINAL-design population of the frame - not
something this incident or its fix touched - and reflects the normal,
expected lag between "a partner reports a ward inaccessible" and "every
household row's own `ward_accessible_status` column gets refreshed to
match" across the whole frame. Whatever mechanism is *supposed* to keep
this column current frame-wide (referenced only in comments tonight, never
actually located as working code - see above) may not exist, or may exist
somewhere not yet found. This is a materially bigger question than
tonight's incident - it touches every partner's original assignment, not
just two - and deliberately not acted on unilaterally.

**Still open, for whoever next touches this path**:
1. `resampling/scripts/stamp_ward_accessible_status.py` is a standalone
   script that has to be remembered and run by hand between draw and
   merge - wire it into `draw_supplementary_clusters_batch.R`/`draw_
   supplementary_idp_sites_batch.R`'s own output (or call it as a
   mandatory post-draw, pre-merge step) so this can't be skipped by a
   future session that doesn't know to run it.
2. `analysis_accessible_area_layer.R` should probably run automatically as
   step 0 of any supplementary draw, not be a manually-remembered
   standalone recompute - or at minimum, the draw scripts should refuse to
   run (or warn loudly) if the shapefile is more than N days older than
   `master_accessibility_status_ward_level.csv`.
3. The 5,629-row national gap above needs a real owner and a real
   mechanism, not a comment claiming one exists.

**RESOLVED 2026-09-08 - see the rebuild section below**: items 1 and 2 above
are exactly what `assert_fresh()` + the merge/draw-script gates now enforce.
Item 3 (the 5,629-row gap) is deliberately still open by Jack's own explicit
call, not an oversight - see "Known, deliberately-deferred gaps" below.

## Update 2026-09-08 — pipeline rebuild (root cause fix, not more patches)

Jack stopped all resampling activity the night of 2026-09-07 after this
file's own incident writeups (above) made clear the pattern repeating -
"too many stacked bugs, too much confusion about what the real state
actually is." Ordered a full audit (`PIPELINE_AUDIT_2026-09-07.md`,
workspace root) across submission/deletion/accessibility/resampling/
dashboard, then a from-scratch conceptual design session with the
coordinating orchestrator session before authorizing any rebuild work. This
section is the result, built and tested the same night/next day.

**The one root cause**, stated in the audit and confirmed repeatedly while
building the fix: critical "current status" data (ward accessibility,
deletion status, which sampling-frame version is current) was a snapshot,
frozen wherever a standalone script last left it, with nothing enforcing a
refresh before something safety-critical read it - plus, underneath that, a
specific default direction (unknown accessibility status → treat as
accessible) that ran the wrong way for something safety-critical. Both are
now closed generically, not patched instance-by-instance.

### `assert_fresh()` — `scripts/shared/assert_fresh.R` (+ `.py`, identical copy in 2_monitoring)

Checks an artifact's real, current mtime/hash against its source, live,
every time - never trusts a `_*_version.txt` stamp file as ground truth
(found one mid-build: `_accessibility_version.txt` still claimed the ward
shapefile was from 09-03, three days after it was actually rebuilt, because
writing the stamp was a separate step nobody remembered mid-incident - this
function now writes that stamp itself, as a side effect of checking, so it
can't drift from what it describes). Two modes:
- `mode="auto"` - safe, deterministic, no-judgment regeneration/copy. Runs
  automatically, prints what it did. Used for: the 3 accessibility-mirror
  copies (`sync_accessibility_mirrors.R`), the `real_submissions.csv`
  mirror, dashboard `data`/`input_data` bundling
  (`bundle_dashboard_mirrors.R`, 2_monitoring).
- `mode="stop"` - judgment-sensitive, heavy, or explicitly "don't rerun
  casually." Blocks with the exact fix command, never runs anything itself.
  Used for: the ward shapefile rebuild, the IDP site frame's accessible_
  status refresh, staged household files before a merge (the exact chain
  that caused the 2026-09-07 incident), anything writing into the deletion
  tracker.

Wired in as real gates, not just documentation:
- `merge_partner_resample_batch.R` - blocks unless staged `new_households*.
  csv` files were stamped after the master ward CSV's last update. Also:
  the debunked "computed on 04's next run" comment (root cause of the
  2026-09-07 incident) is corrected, and unmatched/unknown ward status now
  defaults to EXCLUDED + logged to `NEEDS_REVIEW_unmatched_ward_status.csv`
  in the staging dir, not silently included - applied consistently at all 3
  places this logic appeared in the file.
- `draw_supplementary_clusters_batch.R` - blocks unless the ward shapefile
  postdates the master ward CSV.
- `draw_supplementary_idp_sites_batch.R` - blocks unless the IDP site
  frame's `accessible_status` postdates the ward shapefile.
- `stamp_ward_accessible_status.py` - no longer defaults an unmatched ward
  to Accessible; leaves it blank and reports exactly which keys didn't
  match.
- `refresh_working_frame_daily.R` - same default-direction fix at its own 3
  occurrences of the identical (duplicated, per this project's standalone-
  script convention) logic, plus the long-flagged hardcoded stale-mirror
  path (`REAL_SUBMISSIONS_CSV` was reading `2_monitoring/dashboard_app/
  data/`, only refreshed by a full deploy - now reads canonical
  `2_monitoring/data/real_submissions.csv`).

**`refresh_idp_site_frame_accessibility.R`** (new) - refreshes ONLY the
frozen IDP site frame's `accessible_status` column, without touching the
rest of that "don't rerun casually" frame. First draft used a text-name
join (same approach as `stamp_ward_accessible_status.py`) and was WRONG -
tested before shipping it, caught 1,489 of 2,765 in-scope rows failing to
match, because this frame's `ward` field is raw, unreconciled DTM text
("Sabon-Birni" vs "Sabon Birni"), never run through GRID3 reconciliation the
way the household frame's `adm3_name` was. Rebuilt using the actual proven
method already used elsewhere for this exact frame/purpose - a spatial join
(`st_join`/`st_within`) against the ward shapefile, with the same
nearest-ward-gap fallback `analysis_remaining_eligible_pool.R` already uses,
capped at 5km. Re-tested: match rate went from 43% to correctly matching
everything resolvable via geometry; genuinely unresolvable sites are left
NA (excluded, not defaulted to Accessible - deliberately stricter than
`analysis_remaining_eligible_pool.R`'s own reporting-only fallback, because
this column directly gates a real draw).

### Accessibility ingestion rules (Layer A vs Layer B - don't conflate them)

Three rules, confirmed against actual code, not just agreed conceptually:
1. A ward never reported on by any partner → Accessible (the genuine
   universe default, `04_build_master_accessibility_status.py`'s own
   documented rule - most of the universe hasn't been reported on yet, that
   isn't evidence of inaccessibility). Unchanged, correct as-is.
2. A ward previously given a status, not repeated in a partner's newer
   report → status PERSISTS unchanged. Confirmed `latest_ward_reports()`
   already does exactly this (per-ward latest-wins across files; an
   unrepeated ward's entry is simply never touched) - initially
   misdiagnosed as a bug in this same rebuild conversation, corrected after
   Jack clarified the actual intended rule (omission is far more likely
   partner oversight than a deliberate "this is fine now" signal - reading
   it as information would fabricate a claim the partner never made).
   Also confirmed: a ward row present in a file but with a blank status
   cell is already treated identically to an absent row (filtered out by
   `02_ingest_accessibility_reports.py`'s own logging step before rule 2
   ever sees it) - not a separate case needing separate handling.
3. A household row that can't be matched to the master file/shapefile at
   all (a geography reconciliation failure, not a partner reporting
   anything) → excluded + flagged, per the asymmetric-risk reasoning above.
   This is the ONLY rule the default-direction flip actually applies to -
   never rules 1 or 2, which are about interpreting what a partner said,
   not about a data-matching gap.

### The review-queue engine (shared with 2_monitoring - see that repo's CLAUDE.md for the deletion side)

`resampling/scripts/generate_review_queue_accessibility.py` - same JSON
shape as 2_monitoring's `generate_review_queue.R`, built from
`analysis_review_returned_reports.py`'s existing QA findings (partial
answers, contradictions, missing/extra ward coverage), grouped by
(partner, finding_type) instead of printed to stdout. Tested against the
real returned-reports folder: 550 individual findings collapse to 25 groups
across 11 partners. No "apply" step on this side yet - a finding here means
"fix the partner's file and re-ingest," not "resolve a tracker row," so
there's nothing to write back automatically.

### Sampling-frame versioning & archiving (`scripts/stamp_frame_version.R`)

Formalized the version-bump vs. in-place-fix distinction that was already
implicit in practice: a version bump means the cluster/row ROSTER changed
(a new batch/round merged in); an in-place fix corrects values on the
existing roster (no new rows). Extended the script to:
- Sweep any stray `*_PRE_*_backup*` file left at top level into
  `_archive/<date>_<reason>/` (inferred from the filename) on every run -
  found and swept 10 such files immediately (19-23MB each, accumulated
  2026-09-04 through 2026-09-07, because the correct destination was used
  correctly twice on 09-03 and then not followed for every fix since).
  Confirmed the live folder is now down to just current-version files.
- Added `archive_before_fix(reason)` - what an in-place-fix script should
  call FIRST, going forward, instead of writing its own ad hoc backup
  filename. The sweep above is the safety net behind this habit, not a
  replacement for it.

### Dashboard "Complete" status - fixed in 2_monitoring, noted here for the frame-side context

The bug (target_sample frozen at design time, never grew with resampling,
so a stratum could read "Complete" against a stale, too-low bar - see
2-monitoring-ba's 2026-09-07 finding above) is fixed in 2_monitoring's
`global.R`. Decided with Jack: keep the original design-time `target_sample`
visible (frozen, never recomputed - a stable baseline for "Original
target"), add a live `target_sample_current` (summed from the real current
cluster roster, same source the achieved-count capping already uses) that
Complete/coloring/pace now actually key off. Grows the instant a
supplementary cluster merges into WORKING, not once it's distributed to a
partner - deliberate, matches this whole rebuild's "WORKING is the one
source of truth, don't let anything else lag behind it" principle. Expect a
visible dip in some strata's "% complete" right after a batch is drawn -
that's the number becoming honest, not a new bug.

### Known, deliberately-deferred gaps (not fixed in this rebuild, on purpose)

- **The ~5,494-row FACT legacy accessibility gap** (original design
  assignments, unrelated to any draw, sitting in wards now known
  inaccessible - see the 2026-09-07 incident report above for the full
  numbers). Root cause understood (accessibility reporting is an ongoing
  rolling process; nothing has ever re-validated ALREADY-assigned rows
  against the CURRENT picture, only new draws get filtered at draw time) -
  Jack's explicit call: address this using the new accessibility
  review-queue mechanism once things settle, not as a rushed one-off
  cleanup that risks adding more mess on top of what this rebuild just
  cleaned up.
- **The Malteser 3-stratum shortfall** that never got its follow-up round
  (wrong partner-scope earlier in the 09-06/09-07 session) - a good real
  first case for the deletion review-queue engine once it's actually run
  for real, not fixed ad hoc.
- Augie/FACT single-partner concentration - a partner-relationship
  conversation, not a code fix.

## Update 2026-09-08b — partner-package two-tier refresh, built and run

The last piece from the rebuild design conversation: partner packages
(`3. External coordination/NGA MSNA 2026 Package/<Partner>/`) carry two
different kinds of "live," on two different cadences, per Jack's explicit
design -

- **Daily/auto tier** - achieved status, still-needed counts, confirmed
  deletions, current accessibility - refreshed silently, no partner
  notification needed (nothing they're being asked to do has changed, just
  what's now known about progress against the same unchanged points).
- **Resampling-push tier** - the actual GPS point roster (KML files) -
  changes only when WORKING itself changes, and always followed by an
  announced email (Jack's call each time, never automatic).

**New script**: `scripts/field_guide_production/
refresh_partner_workbooks_daily.py` - refreshes ONLY each partner's
`<Partner>_sampling_points_summary.xlsx` workbook (Sampling
Points/Needs Collecting/Cluster Summary sheets), never touches KML files or
LGA summary maps. Deliberately a standalone duplicate of
`build_partner_dc_packages.py`'s FULL-sourced workbook logic, not a
refactor of that script in place - matches this project's established
standalone-script convention, and meant safely rebuilding a 1180-line,
already-live, partner-facing generator in place carried real risk of a
subtle break for no real time saved. `build_partner_dc_packages.py` itself
is otherwise **unchanged** and remains the resampling-push tier (run only
when WORKING changes, whole-script - KML + workbook together - followed by
Jack's announced email).

One deliberate behavioural difference, found and reasoned through during
testing, not a bug: the new script gates IDP Tier 2 backup metadata rows on
the cluster's presence in FULL, not WORKING (which it never loads). Checked
directly: 76 IDP clusters currently sit in FULL but not WORKING, all 76
because they're now ward-inaccessible (0 are achieved-complete-dropped or
anything else) - the daily script now shows their Tier 2 backup reference
point in the workbook (marked Inaccessible via the existing per-row status
logic), matching this same workbook's own established principle everywhere
else in the file ("real completed work isn't erased... kept in full even
for a cluster now marked Inaccessible"). The original script's WORKING-gated
inclusion for this one row type looks like an incidental coupling from when
the workbook was still entirely WORKING-sourced, not a deliberate choice -
left `build_partner_dc_packages.py` itself untouched either way, since
that's not this rebuild's problem to fix and the two scripts are allowed to
agree-by-design rather than byte-for-byte, per the standalone-script
convention.

**Also fixed in `build_partner_dc_packages.py` itself** (same bug class as
`refresh_working_frame_daily.R`'s 2026-09-08 fix, found while duplicating
this section into the new script): `REAL_SUBMISSIONS_CSV` was pointed at
`2_monitoring/dashboard_app/data/` (the bundled mirror, only refreshed as a
side effect of a full dashboard deploy) instead of the canonical
`2_monitoring/data/`. Currently byte-identical by chance (checked directly),
but would have silently drifted the next time canonical updated without an
intervening deploy - same latent-staleness shape this whole rebuild has
been about killing everywhere it appears. Fixed in both the original script
and from-scratch-correct in the new one.

**Tested and run for real**: scoped test against FACT alone first
(`BUILD_DC_ONLY_PARTNER=FACT`) - workbook structure, headline block, and row
counts all checked directly and confirmed sane (24,496 Sampling Points rows,
2,287 clusters, 48% active-target achieved). Confirmed KML files' mtimes
unchanged before/after (2026-09-04, untouched) - the daily tier genuinely
touches nothing but the workbook. Then run for all 19 partners for real: all
19 workbooks refreshed successfully, 0 locked-file skips. This has now
actually happened once, live, not just been built and left untested.

**Not built**: any automatic trigger/schedule for either tier - both are
run manually for now (same as `refresh_working_frame_daily.R` and the
dashboard's own refresh), consistent with how every other daily-cadence
piece in this rebuild works today. A resampling push already means running
`build_partner_dc_packages.py` (optionally `BUILD_DC_ONLY_PARTNER`-scoped)
then emailing affected partners - that part of the design was already true
before tonight and needed no new code, just the daily tier being genuinely
separable from it, which it now is.

## Update 2026-09-08c — accessibility review-queue's own stale-baseline bug

Found by Jack, not caught by the rebuild: `analysis_review_returned_reports.py`
(and `generate_review_queue_accessibility.py`, which imports it) compared each
partner's returned report against `build_partner_ward_universe()` - the
*current, live* WORKING frame's `partners_covering` - to compute EXTRA/MISSING
ward findings. That baseline moves every time a stratum is dropped or added,
which happens on a totally different clock than "when did we last send this
partner a report." Exact same staleness shape as the whole 2026-09-08 rebuild
above, just in a script that rebuild never touched.

Caught on FACT: the queue showed 294 "EXTRA" + 51 "MISSING" (of 364 total
findings) that looked like a partner-side mess. Jack's challenge: "I remember
there being definitely more than 1000 ward rows in the file we were
using/sending out... was 1144 wards an amount before a round of resampling and
so these wards were simply just dropped strata from a previous round?" Checked
directly, not defended: FACT's WORKING-based ward count across archived frame
versions - v2 1,160 -> v3 1,074 -> v4 867 -> v5 843 -> v6 (tonight's redraw)
901 - confirms several stratum-drop/add rounds happened between when FACT's
report was generated (Sep 2, ~1,067 wards) and tonight. Direct diff of FACT's
returned wards against the exact ward list in the report actually sent
(`accessibility_reports_generated/FACT_accessibility_report.xlsx`): 1,067/1,067
matched, zero missing. FACT reported on everything asked, plus 77 wards beyond
that (a real, much smaller number worth a look, not 294).

**Fix**: added `build_sent_ward_universe()` to `analysis_review_returned_
reports.py` - reads the canonical file per partner in `accessibility_reports_
generated/` (current file only, same dated/followup-suffix filter already used
for the returned dir) and uses *that* ward list as the completeness baseline.
`build_partner_ward_universe()` (WORKING-based) is left in place - a genuinely
different, still-useful concept (which wards a partner currently has clusters
in right now) - just no longer used for this specific returned-vs-expected
comparison. Both `analysis_review_returned_reports.py`'s `main()` and
`generate_review_queue_accessibility.py` switched over; finding-text wording
updated to match ("beyond what was sent" instead of "not in expected
universe").

**Re-run for real, all 11 partners with a returned report**: 550 -> 189 total
findings, 25 -> 11 groups, 11 -> 7 partners with anything left. FACT:
364 -> 96 (77 EXTRA - genuine, worth reviewing - + 19 CONTRADICTION, unaffected
by this bug either way). Most other partners' EXTRA/MISSING findings dropped to
zero outright (their `ward_rows_in_file` now equals `ward_rows_expected`
exactly) - COOPI, FHI 360, IMC, IRC, NRC, PLAN, Save the Children, Solidarités,
ZOA. Malteser and INTERSOS still show real remaining findings unrelated to this
bug (Malteser: 4 residual EXTRA + DUPLICATE/ORPHANED/CONTRADICTION; INTERSOS:
35 PARTIAL).

**Not done**: no attempt to reconcile *why* FACT's WORKING-based count moved
1,160 -> 843 across v2-v5 (which strata, which rounds) - that's the FACT
legacy-gap investigation's job, not this fix's. Also not built: any automatic
flag for "this partner's sent report is now N wards stale vs current WORKING,
consider regenerating" - a real, cheap follow-on given `build_partner_ward_
universe()` is still sitting right there unused for this purpose, but out of
scope for what was actually asked tonight.

**Addendum, same night**: chasing Jack's follow-up question on 3 wards that
looked like unexplained "EXTRA" loose ends surfaced two more real things.
First, a self-check error on my (the assistant's) part worth recording
honestly: I initially claimed most of FACT's 77 EXTRA wards were "dropped
during tonight's purge," checked only against archived v2-v5 - never actually
checked v6. Corrected on a direct look: 72 of the 77 are still live in v6
WORKING right now; of those, 69 sit in wards master status calls Inaccessible
- meaning these aren't resolved purge output, they're a *live, unresolved*
slice of the FACT legacy-gap problem, now with a partner-corroborated ward
list to work from. Only 5 of the 77 are genuinely gone from WORKING (an older
v4->v5 drop, unrelated to tonight). Lesson: "checked the archived versions"
isn't the same claim as "checked the current file" - say precisely which one
was actually checked.

Second, a real scanner gap: `ACCESS_DENIAL_PATTERNS` (the CONTRADICTION
keyword list) missed FACT's Kebbi/Arewa-Dandi cluster (Bachaka, Chibike,
Kangiwa, Kuka - all Accessible=Yes with an identical note: "...team had to be
evacuated this morning as gun men opened fire..."), because the notes text
itself never used any of the existing trigger words (the one arguable match,
"conflict", was in the Reason *category* dropdown, which this scan never
reads). Widened the pattern list (evacuat/gun-men/opened fire/gunfire/shoot/
ambush/abduct/raid/clash/armed group) and rescanned all partners: FACT's
CONTRADICTION count 19 -> 23 (the 4 Arewa-Dandi wards); no change for any
other partner, so this specific gap wasn't universal - but worth remembering
that a keyword-based scan will always have this failure mode, silently, until
someone happens to ask about the specific row it missed.

## Update 2026-09-08d — the FACT legacy-gap fix, actually run ("making the numbers honest")

Jack's call: fix this now rather than defer to the review-queue mechanism,
since it was directly distorting FACT's true remaining shortfall going into
the next redraw. Two-step mechanism, both new scripts:

**`resweep_full_ward_accessible_status_2026-09-07.py`** - the missing
retroactive half of `stamp_ward_accessible_status.py`. That script only ever
stamps freshly-staged new rows before a merge; nothing resweeps FULL's
`ward_accessible_status` on rows already sitting there from past
rounds/versions - confirmed directly on 3 known-Inaccessible FACT wards, all
still stored "Accessible" or blank in FULL. This script resweeps every FULL
row against the current master ward CSV.

**Caught and self-corrected before it ever reached WORKING**: first draft
copied `stamp_ward_accessible_status.py`'s unmatched-stays-blank rule.
Produced 43,204 unmatched rows (38% of FULL) - nowhere near
`classify_households()`'s own docstring claim of "vanishingly rare" for this
case, which is what caught it. Checked the actual distribution before trusting
either number: within the states this accessibility exercise actually covers
(Katsina/Borno/Sokoto/Adamawa/Zamfara/Yobe/Kebbi) unmatched is 0-4%, genuinely
rare as expected; the other ~22,000+ come from states outside the master
file's scope entirely (Kano/Niger/Kogi 100% unmatched, Kaduna/Benue/Plateau/
Nasarawa mostly so) - never-monitored territory, not "unknown, needs review."
Restored FULL from the archive taken before the bad run (checksum-verified),
fixed the default to match `classify_households()`'s own
`ward_status.get(key, "Accessible")` exactly, reran clean. Lesson, same shape
as the accessibility-review-queue bug above: `stamp_ward_accessible_status.
py`'s stricter rule is correct for ITS job (freshly staged rows, always
inside an actively-monitored state); applying the same rule somewhere with a
wider blast radius (all of FULL, spanning states never touched by this
exercise) was wrong by not re-checking the assumption held in the new
context.

**Result** (resweep, national): 6,314 rows newly flipped to Inaccessible (not
before), 1,546 flipped the other way (ward reported accessible again since
last stamped - the mechanism is symmetric, not one-directional). By partner:
FACT 6,121, Malteser 173, INTERSOS 12, ZOA 8.

**Then ran `refresh_working_frame_daily.R`** (existing, already-fixed script -
see Update 2026-09-08's assert_fresh section) to propagate: household-level
WORKING 48,036 -> 42,965 rows (3,352 -> 2,957 clusters, 442 removed entirely).
Strata-level: 314 strata refreshed, 102 changed achieved_sample, 614 real
completed interviews (394 Non-IDP + 220 IDP) correctly preserved via
stranded-achieved credit rather than double-counted as outstanding. Only 14
strata still show achieved > target after the fix - a small residual, not
systemic, matches the script's own expectation.

**FACT's honest picture**: 149 FACT-covered strata currently in WORKING; 84
now show a real shortfall (target > achieved) totaling **1,629 households**
- this is the number a supplementary draw would actually need to close, not
the smaller, artificially-suppressed figure the stale ward_accessible_status
was showing before tonight. 13 strata still show a small surplus (largest:
idp_NG021014 +108, idp_NG037002 +42) - the residual above, not urgent.

**Not done**: no new supplementary draw yet - this step only corrects the
current picture (per the plan Jack confirmed before authorizing it: "making
the numbers honest" is separate from "closing the gap"). Also not yet
propagated: 2_monitoring's mirror, partner packages/workbooks - both still
reflect the pre-fix numbers until explicitly refreshed. Malteser/INTERSOS/ZOA
saw smaller versions of the same correction (173/12/8 rows) - not
individually investigated with the same depth as FACT tonight; worth the same
scrutiny before assuming their own known shortfalls are still sized
correctly.

## Update 2026-09-08e — the v5 rollback actually executed, v6 -> v7

**A real process failure, not a data one**: earlier the same night, Jack
approved a plan - restore the pre-incident v5 baseline, discard the whole of
that night's tainted resampling, relabel the eventual clean redo v7 (v6
retired/archived, not reused). That approval was never acted on. The
conversation moved straight into the accessibility review-queue investigation
right after, and everything done since (the review-queue baseline fix, the
FULL ward-status resweep, FACT's first supplementary redraw) got built on the
existing v6 files instead - which still carried that night's pre-halt FACT+
Mafa content. Caught only when about to merge that redraw and stopping to
think about what version label it should get. Same root shape as the bug
pattern above: proceeding on inherited context (here, an approved plan)
without checking it was actually acted on before building further on top of
it. Jack's direction on being told: actually do the rollback now, and check
these things before making further structural changes.

**Verified before touching anything**: zero rows in `real_submissions.csv`
match any of the 273 clusters that would be removed by reverting to v5 - safe
to roll back without orphaning real field data (nothing was ever sent to
partners about that content, consistent with the whole night's halt).

**Mechanics**: archived current v6 (FULL/WORKING/strata, both) to
`_archive/2026-09-07_pre_v5_rollback_to_v7/` - preserves that work for the
record even though it's not the live basis going forward. Restored `_archive/
2026-09-07_pre_fact_resample_merge/`'s v5 FULL/WORKING/strata (the earliest
snapshot of the whole night, verified by checksum) as new v7-named live
files. Renamed every `sampling_frame_v6_` reference across the codebase to
`_v7_` - 27 files (comprehensive `grep`, not relying on memory of which
files mattered from the v5->v6 rename), verified zero remaining `v6`
references afterward. Then, in order: reran the ward-accessibility resweep
against the fresh v7 FULL (same result shape as before - FACT 6,121/Malteser
173/INTERSOS 12/ZOA 8 rows newly Inaccessible, confirms the fix is
deterministic and not baseline-dependent); ran `refresh_working_frame_daily.R`
to propagate into v7 WORKING/strata; recomputed FACT's shortfall against the
now-honest v7 baseline (**1,875 non-IDP + 532 IDP = 2,407 households** -
larger than the v6-based 1,629, since v7 doesn't have last night's redraw
already offsetting some of it); redrew (306 non-IDP clusters/3,684 hh, 27 IDP
site-level clusters/444 hh); archived pre-merge v7; merged via
`merge_partner_resample_batch.R`; ran `stamp_frame_version.R` (auto-archived
the superseded v6 files to `_archive_superseded_versions/` as part of its own
normal version-bump sweep).

**Result**: v7 WORKING 43,139 rows / 2,969 clusters. FACT's shortfall closed
from 2,407 -> 876 households across 42 strata (candidate pool genuinely
exhausted for the rest, both non-IDP hexes and IDP DTM sites - a real
capacity limit, not a bug, same as the v6-based draw showed). 648 new rows
excluded pending review (unmatched ward geography), 1,266 total excluded from
WORKING (Inaccessible/below-threshold, kept in FULL only). Zero duplicate
survey_ids, zero ID collisions with the live frame.

**Not done**: 2_monitoring's mirror and partner packages still reflect the
old v6 numbers - not propagated yet. FACT's 876-household residual gap is
still open (structurally, per the exhausted-candidate-pool warnings). Other
partners (Malteser/INTERSOS/ZOA's own accessibility-driven corrections,
whatever else was affected by the v5 restore removing last night's other
partners' work if any existed) not re-verified post-rollback with the same
individual depth as FACT.

## Update 2026-09-08f — the other 11 partners, drawn against v7, one at a time with Jack's review

Scope self-derived from the live v7 strata-level WORKING (target > achieved
per partner), not from any carried-over or hardcoded partner list - the exact
fix for the earlier "11 vs 16 partners" scope-mismatch incident. Found 12
partners with a real shortfall (FACT already handled above); Jack reviewed
each partner's own stratum-level breakdown before approving the draw, one at
a time (IMC/INTERSOS/FHI 360/Save the Children/Malteser individually; the
remaining 6 small ones - COOPI/CARE/ZOA/Solidarités/PLAN/Street Child of
Nigeria - approved together since their LGAs are fully disjoint).

**FHI 360 caught a real terminology risk before it became a mistake**: Jack
asked whether "achieved=28/102" for Mafa meant real interviews were at risk
of being redone. Checked directly rather than reassuring: zero real
completed interviews exist yet for that stratum
(real_submissions.csv, matched) - the achieved_sample number is a design-
capacity metric (currently-accessible assigned slots: 79 of 107 primary rows
sit in now-Inaccessible wards, only 28 accessible), not a field-progress
count. Worth remembering going forward: this distinction is exactly the one
refresh_working_frame_daily.R's own header warns is "easy to get backwards" -
it was, in how this was first explained, until asked about directly.

**Batched draw, mechanism note**: for the 6 small partners, ran ONE combined
draw_supplementary_clusters_batch.R call (safe since their LGAs are
disjoint - the draw script doesn't know or care about partner identity, only
adm2_pcode), then split the staged new_clusters/new_households by adm2_pcode
into per-partner folders before running merge_partner_resample_batch.R once
per partner (that script tags every row with ONE partner name, so merging
mixed-partner staged output through a single call would have mis-attributed
coverage). Archived before each individual merge, same as every other merge
tonight - no batching shortcut on that part.

**Results** (target/achieved gap, before -> after):
- IMC: 78 -> ~3 (closed)
- INTERSOS: 78 -> 36 (NG037010's IDP portion - genuine site-pool exhaustion)
- FHI 360: 74 -> 54 (Mafa reporting gap - 5 of 8 touched wards have no
  master ward CSV entry at all; needs partner reporting, not a redraw)
- Save the Children: 50 -> ~0 (one small IDP site-pool exhaustion residual)
- Malteser: 35 -> ~3 (closed; note - superseded the earlier rushed 09-06/07
  cluster-count estimate, which undercounted; this run's number, from the
  full honest pipeline, is authoritative)
- COOPI/CARE/ZOA/PLAN/Street Child of Nigeria: fully closed
- Solidarités: ~12 -> ~3 (small unmatched-ward residual)

National remaining gap after this round: 987 households, 876 of it FACT
(already reported above). The rest (111, across FHI 360/INTERSOS/Save the
Children/Malteser/IMC/Solidarités) are small, individually-explained
residuals - genuine candidate-pool exhaustion or unreported wards, not
something another redraw round would close.

v7 finalized: 43,702 WORKING rows, 3,018 clusters.

**Not done**: 2_monitoring/partner packages still not propagated (next step,
per Jack's explicit sequencing - all partners first, then push everywhere).
Mafa's reporting gap (FHI 360) not chased - would need the same kind of
partner follow-up as FACT's accessibility workbook tonight, not attempted
yet.

## Update 2026-09-08g — Dandume/Faskari reinstated; found a 4th instance of the same drift pattern

Data officer reported FACT's subcontractor (Conpad Initiatives) requesting
coverage of Dandume and Faskari (Katsina) - LGAs absent from the working
frame entirely. Traced to `coverage_status=excluded`/`exclusion_reason=
accessibility_loss_below_population_threshold`, a real mechanism (<10% of a
stratum's population accessible = drop it) but computed ONCE by `build_v3_
frame_2026-08-31.R` against Aug-31 accessibility data, never recomputed
since - see the coordinating-session flag above. 11 strata nationally carry
this exclusion (1,146 households of target_sample); this update covers only
the two Jack asked to act on now.

**Faskari's data-quality call - Jack's, not inferred**: its 5 currently-
Accessible wards carried an identical "Banditry and kidnappings" note against
their own Yes flag. Jack's read: the note was copied down across the LGA,
not five independent reports - trust the Accessible (Y/N) column. No data
changed for this; it was a decision about which existing signal to believe.

**Recomputed the real population-weighted fraction** (05_build_accessibility_
impact_workbook.py's own `load_lga_area_pop_fractions()` formula, from the
ward-level GIS layer - not a row-count approximation): idp_NG021008
(Dandume) 19.19%, non_idp_NG021008 22.08%, idp_NG021013 (Faskari) 100.00%,
non_idp_NG021013 56.52% - all four clear the 10% floor comfortably.

**Reinstatement mechanics** (`patch_dandume_faskari_reinstatement_2026-09-
08.R`, modelled on the Mobbar precedent but simpler - no new population to
add, these are pre-existing FULL rows just gated off): flipped `coverage_
status`/`exclusion_reason` on the 4 strata-level rows, added them to strata
WORKING (didn't exist there while excluded). **First pass was incomplete** -
only patched the strata-level summary, not the 768 household-level FULL
rows' own `coverage_status`/`exclusion_reason` columns, which is what
refresh_working_frame_daily.R actually filters on. Caught immediately
(household-level WORKING hadn't grown at all after the "fix," a dead
giveaway) and corrected before merging anything.

**Found while investigating - a real, 4th instance of the exact pattern
flagged three times already tonight**: re-running `refresh_working_frame_
daily.R` as part of this fix changed 61 OTHER, unrelated strata's
achieved_sample (all decreasing) even though household-level FULL, real_
submissions.csv, and the deletions overlay were all verified byte-identical
to the prior run. Root cause: `merge_partner_resample_batch.R`'s own
`recompute_strata()` correctly excludes below-4-accessible-primary-HH
cluster rows from household-level WORKING, but never applied that same
threshold when recomputing strata-level `achieved_sample` - so every one of
tonight's 13 merges left affected strata's achieved_sample counting clusters
that were correctly absent from the actual to-do list. Independently
verified one example from raw data before trusting either number
(non_idp_NG002001: true value 102, matching the fresh refresh; the
merge-time figure of 105 was the stale one). The actual WORKING content
(the to-do list partners work from) was correct throughout - only the
strata-level bookkeeping number was quietly wrong, now corrected by this
run. Flagged to the coordinating session as the 4th instance of the
"duplicated logic silently drifts out of sync" pattern.

**Result**: idp_NG021013 (Faskari IDP) fully closed (96/96). Remaining:
idp_NG021008 (Dandume IDP) 72hh - genuine DTM site-pool exhaustion, matches
its low 19% accessible reading; non_idp_NG021008 15hh and non_idp_NG021013
13hh - small residuals from unmatched-ward-geography and below-threshold
exclusions among the newly-drawn rows. v7 now: 44,247 WORKING rows, 3,052
clusters.

**Not done**: the other 7 strata nationally under this same frozen
mechanism (Matazu, Sabuwa, and others) - Jack's explicit call to defer to
tomorrow, alongside whatever else this may have touched.
