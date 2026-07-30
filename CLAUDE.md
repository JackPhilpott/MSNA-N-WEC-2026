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
- The two outdated IDP example maps (`methodology_map_idp_site.png`/
  `_closeup.png`, still 150m-radius) have not been regenerated. The ToR
  itself flags this (`[INSERT NEW MAP HERE — replacing Figure 5]`) and
  references a suggested Claude Code prompt left as a Word comment in the
  ToR — that comment text wasn't available from the PDF version supplied
  2026-07-28, so the new map has not been attempted; get the actual comment
  text (or fresh instructions) before building it.
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
declined + all 44 Kano). 3 LGAs are excluded for both coverage and the
small-population reason at once: Niger/Katcha, Niger/Lapai,
Kaduna/Markafi. Full detail, per-LGA: `output/analysis_partner_coverage/`
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
