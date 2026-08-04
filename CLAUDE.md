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
