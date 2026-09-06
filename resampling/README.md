# Resampling workflow

Handles field-reported accessibility/collection problems in specific
clusters/LGAs, separately from the main numbered pipeline (`../scripts/`)
and the field-guide production layer (`../scripts/field_guide_production/`).
Scaffolded 2026-08-20; first real partner data (Save the Children)
processed 2026-08-21.

**Deciding what happens to each stratum during the 2026-08-29 resampling
push** (drop vs. attempt, representativity-vs-target logic, partner
rollout order) is documented separately in
[`RESAMPLING_DECISION_RULES.md`](RESAMPLING_DECISION_RULES.md) — this
README covers how the scripts work, that file covers the policy calls.

## Canonical live data sources (always these paths/filenames)

Two files outside this folder are the source of truth for this workflow
and get referenced repeatedly when triaging a partner report - always at
the same path with the same filename even as their content is regenerated,
so they can be pointed to directly rather than re-derived each session:

- **Sampling frame**: `1_sampling/output/data/data_collection/` (the
  WORKING/FULL household- and strata-level CSVs - see that folder's own
  README for which is current). Used to verify a partner's ward/cluster
  claims directly against real cluster_id/adm2/adm3/lat-lon data rather
  than trusting a self-reported spreadsheet at face value.
- **Real submissions so far**: `2_monitoring/dashboard_app/data/
  real_submissions.csv`. Per-interview record with `matched_cluster_id`,
  `admin2_submitted`/`admin3_submitted` (what the enumerator actually
  recorded in the field, not the frame's assignment), `dist_to_matched_point_m`,
  and quality flags (`flag_gps_outlier`, `flag_lga_mismatch`, etc.) - lets
  a partner's claimed achievement/% figures be checked against actual
  completed interviews instead of taken as given.

## Why this is separate

Three problems, distinct from anything the main pipeline or field-guide
scripts handle:
- **Intake is unstandardized.** Partner reports arrive as emails, broken
  Excels, and WhatsApp messages, and the same partner/LGA can get updated
  more than once as new information comes in.
- **Partners report accessibility at ward level, not cluster level** - see
  "The accessibility report" below. A pure per-cluster checklist (this
  workflow's original v1) caused real confusion, since that's not how
  partners actually describe the problem to us ("these wards are insecure
  in this LGA").
- **Not every reason calls for the same mechanism.** See "Decision
  framework" below - some reasons call for the pipeline's existing
  reallocation machinery, some call for a targeted resample (the
  2026-08-06 border-buffer pattern, see `../CLAUDE.md`). **Per
  donor/management decision 2026-08-20: every reported issue gets
  resampled, full stop** - even where the resulting cluster set can no
  longer be called representative of the original design and must be
  reported as indicative instead. The framework's job is no longer
  deciding whether to resample; it's routing to the right mechanism and
  making sure the representative/indicative call is computed and flagged
  clearly, not lost.

## Folder structure

Split `input/` vs `output/` (added 2026-08-20, matching the main project's
own `input_data/` vs `output/` convention): both accessibility-report
folders are raw material the workflow consumes, not a decision or result -
whether generated-by-us or returned-by-partners, neither is itself an
output of the resampling process. The log (and, once built, whatever `03`
produces) is the first genuine output.

- `scripts/`
  - `01_generate_accessibility_reports.py` - builds one
    `<Partner>_accessibility_report.xlsx` per partner from the live WORKING
    frame (README sheet, then Ward Accessibility - one row per ward - then
    a Cluster Accessibility detail sheet), staged (not yet distributed)
    into `input/accessibility_reports_generated/`.
  - `02_ingest_accessibility_reports.py` - reads filled-in copies from
    `input/accessibility_reports_returned/` and appends new/changed rows
    into `output/resampling_requests_log.csv`.
  - `03_route_and_flag.py` - **not built yet**, needs real reported data
    first. Will apply the decision framework below per logged request.
  - `distribute_to_partner_folders.py` - copies each staged report from
    `input/accessibility_reports_generated/` into that partner's existing
    package folder root in `3. External coordination\NGA MSNA 2026
    Package\<Partner>\`. Dry-run by default (prints what it would do,
    writes nothing); pass `--execute` to actually copy. Never creates or
    deletes a partner's top-level folder (skips + warns if one doesn't
    already exist) and never overwrites a destination file that's already
    there (it may carry partner-filled-in data). Logs every real copy to
    `output/distribution_log.csv`. **Run 2026-08-20: all 19 partners'
    reports distributed successfully**, confirmed via a direct read of the
    destination content, not just the script's own success message.
    **HARD CONSTRAINT (see this script's own header comment): a partner's
    top-level package folder must NEVER be deleted or recreated, only
    renamed/written into in place — SharePoint sharing is tied to the
    folder's item ID, not its path/name.** A 2026-08-27 fix nearly violated
    this by creating a new correctly-named folder instead of renaming the
    existing shared one; caught and corrected before anything was shared
    externally (see `../CLAUDE.md`'s Revision 2026-08-27). Read that
    comment in full before writing anything that touches a partner's
    top-level folder path.
- `input/`
  - `accessibility_reports_generated/` - script 01's output, but
    functionally an input to the rest of the workflow (the blank template
    sent out). Once a copy has been distributed and may carry partner
    input, don't rerun script 01 to "refresh" it - see below.
  - `partner_raw_comms/<Partner>/` - added 2026-08-21, one folder per
    partner (mirrors the same 19 partner names as
    `accessibility_reports_generated/`, no separate hardcoded list). Drop
    raw, unstandardized material here as it arrives - email text/
    screenshots, WhatsApp exports, call notes - before it's been turned
    into anything structured. Never read directly by any script; purely a
    human/Claude staging area for the next step.
  - `accessibility_reports_drafts/` - added 2026-08-21. Coordinator-
    prefilled copies of a partner's template, built from
    `partner_raw_comms/` content, **before partner verification**. Kept
    physically separate from `accessibility_reports_returned/` on purpose:
    `02_ingest_accessibility_reports.py` only ever reads `returned/`, so a
    half-verified, coordinator-guessed draft can never be accidentally
    logged as if the partner had confirmed it. Move (don't copy-and-leave)
    a draft into `returned/` only once the partner has confirmed/completed
    it.
  - `accessibility_reports_returned/` - drop filled-in partner copies here
    (pulled from their SharePoint folder, saved from an email attachment,
    hand-transcribed from a WhatsApp/verbal report into a copy of the
    template, or promoted from a verified `accessibility_reports_drafts/`
    copy) before running script 02. A draft is "verified" for this purpose
    once every row traces back to either the partner's own submitted
    material or an explicit partner confirmation (email/verbal relayed by
    the user) - a coordinator's own inference of what's *probably* fine
    (e.g. defaulting an unreported ward to accessible given a partner's
    otherwise-comprehensive review) is a real, useful answer but is not
    itself "verified" in this sense, since it isn't traceable to the
    partner - it can still be promoted, just knowingly, not by the same
    rule as a directly-confirmed row.
    **Convention (2026-08-23): keep the canonical `<Partner>_accessibility_
    report.xlsx` (needed as-is - `02`'s glob matches only that exact
    suffix, so a date inside this filename would silently stop it being
    picked up) alongside a dated snapshot copy,
    `<Partner>_accessibility_report_YYYY-MM-DD.xlsx`, for the audit trail**
    - the snapshot is never read by `02` (it doesn't match the glob), it's
    purely a historical record of what was returned and when, since a
    later re-return for the same partner overwrites the canonical copy
    with no trail otherwise.
- `output/`
  - `resampling_requests_log.csv` - the master, append-only request log,
    and the first true output of this workflow. Never hand-edit; only
    `02_ingest_accessibility_reports.py` writes to it.
  - `distribution_log.csv` - append-only record of every report actually
    copied to a partner folder (timestamp, partner, destination path).
    Written only by `distribute_to_partner_folders.py --execute`.
  - Future outputs (routing/resolution results, revised frame archives)
    land here too, once `03` is built.

**Housekeeping convention (2026-08-27)**: once a partner's draft in
`accessibility_reports_drafts/` is confirmed identical to (or superseded
by) their real file in `accessibility_reports_returned/`, or a generated
file in `accessibility_reports_generated/` is superseded by a later
approach, move it into a `_superseded_YYYY-MM-DD/` subfolder within that
same directory rather than deleting it or leaving it sitting alongside
active files. First done 2026-08-27 clearing out FHI 360/IMC/Save the
Children's now-redundant drafts (verified byte-identical to their real
returns before moving, not assumed), PLAN's abandoned draft, and a stray
superseded FACT gap-fill file. If either `accessibility_reports_drafts/`
or the `_superseded_*` convention itself looks emptier/different than
expected, check here before assuming something's missing.

## The accessibility report (per partner, two sheets)

**`Ward Accessibility` (primary sheet)** - one row per (State, LGA, Ward)
this partner has clusters in, since that's the granularity partners
actually report at. Reference columns (Non-IDP/IDP cluster counts, total
target HHs) are pre-filled from the live frame; input columns are blank for
the partner (or a coordinator, if the report arrived by WhatsApp/email) to
fill: `Accessible (Y/N)`, `Reason category` (dropdown), `Reason notes`
(free text), `% of target achieved so far`, `Date reported`.

**`Cluster Accessibility` (secondary sheet)** - the original per-cluster
checklist, kept only for the rarer case where a problem is specific to one
site/HH within an otherwise-fine ward, and only once that cluster's
reserve/replacement households have already been used and weren't enough -
not a first resort before working through reserves, and not a second way
to report the same ward-wide issue already on the first sheet.

**Why every ward row is scoped to a specific LGA, never a bare ward name**:
ward polygons don't cleanly nest inside LGA polygons in this project's own
boundary data - GRID3 ward boundaries occasionally disagree with the
OCHA/COD LGA line by tens of metres at borders (documented already in
`build_partner_dc_packages.py`'s `LGA_WARD_SOURCE_NOTE`), and a
partner-recognised ward can genuinely span what this project's admin-2
layer treats as two different LGAs. If ward accessibility were tracked by
ward name alone, one partner's "inaccessible" call on a border ward could
wrongly get applied to a neighbouring LGA/partner's portion of the
same-named ward - this happens often enough per the user (2026-08-20) to
matter. The fix costs nothing extra to build: a ward row only exists in a
partner's report if that partner actually has clusters in that specific
(LGA, Ward) pair (built from `adm2_name`+`adm3_name` on their own cluster
set), so there is no free-floating ward-name join anywhere that could
cross-contaminate another partner's area - no polygon-clipping needed, the
existing per-cluster admin attribution already does this correctly.

**Not yet pushed to partner SharePoint folders** - that copy-out is a
separate, deliberate step (see `../CLAUDE.md`'s partner-folder constraint:
never delete/recreate a partner's top-level folder, only mirror files into
it in place). Review the generated format first.

**Once a copy has been distributed and may carry partner input, do not
rerun script 01 to "refresh" it** - it rebuilds from scratch and would
silently wipe anything already filled in. If the cluster list for a
partner changes (e.g. after a resample), refreshing their report requires
merge-preserving existing input, not regenerating blind - not implemented,
since it hasn't been needed yet.

## The master log

`resampling_requests_log.csv` is append-only: every ingested report becomes
a new row, never an edit to an existing one. Each row carries `report_level`
(`ward` or `cluster`) - ward-level rows have `cluster_id`/`pop_type` blank
and `ward_name` populated; cluster-level rows are the reverse. When a
partner updates a prior report for the same key (partner + level + state +
lga + ward_name/cluster_id), the new row's `supersedes_request_id` points
at the row it replaces - the full history stays in the file. `status` /
`resolution_*` columns are filled in by hand (or a future script) once a
request has been triaged and acted on.

## Decision framework (for `03_route_and_flag.py`, once built)

**Geospatial/map-identification claims are triaged BEFORE the table below,
not routed to resampling at all (policy, 2026-08-21).** A ward-level claim
whose stated reason is that a point/ward "isn't on the map," doesn't match
the partner's own KML/maps.me rendering, or that a ward belongs to a
different LGA/name than what's assigned - as opposed to insecurity,
population absence, or actual denied access - is a recurring pattern across
partner reports (not specific to one partner) that has, every time it's
been checked so far, turned out to be the partner's own map/GPS-tool usage
rather than a genuine sampling-frame or accessibility problem. Per user
decision 2026-08-21: **do not mark such a ward Accessible=No or log it as a
resampling request** - leave it as a normal (blank/available) row, and
address it operationally by continuing to coach partners toward using the
GPS point itself rather than ward names to locate their sample (per-cluster
detail, not a ward-wide read). This is a triage rule based on the STATED
REASON, not the partner or the ward - the same partner's genuine insecurity
or access-denial claim (e.g. Save the Children's Bingi South/Gada Karakai/
Samawa/Tofa, all confirmed independently via zero real Kobo submissions,
2026-08-21) is still logged and resampled normally. If real submission data
(`2_monitoring/dashboard_app/data/real_submissions.csv`) or other evidence
later shows a genuine map/frame defect behind a specific claim like this,
revisit that specific case - this is a default triage rule, not a blanket
dismissal of every geospatial complaint forever.

Every other reported issue gets resampled (donor/management decision,
2026-08-20 - see below); the framework routes to *which* mechanism, and
separately determines the representative/indicative flag:

| Reason category | Mechanism |
|---|---|
| Building-footprint issue / population absent-relocated | `reallocate_zero_building_clusters()` (same stratum, no design change) |
| Stratum short after the above | `add_supplementary_clusters()` |
| Accessible-area boundary itself changed (e.g. a defined security cordon) | Targeted resample, generalized 2026-08-06 pattern (isolated copy, own seed, spliced back in) |
| Insecurity / access denied by authorities or community | Same reallocation/supplementary-cluster machinery as above - draw a replacement from the stratum's remaining unselected pool. **Always executed now, regardless of how large the reported-inaccessible share of the stratum/LGA is.** |

**Draw-pool protocol (decided 2026-08-20, given ward-level reporting) - a
per-LGA rejection filter, NOT a global carve-out of the ward's polygon.**
This distinction matters and is worth stating precisely, because "exclude
this ward from the available area" is exactly the phrase this project
already uses for the international border buffer (`accessible_area`),
which genuinely *is* a global exclusion applied before the hex grid is
even split by LGA - and a global carve-out of a ward polygon absolutely
would leak across LGA boundaries wherever that ward's own polygon spans
into a neighbouring LGA, which is precisely the risk flagged 2026-08-20.
**That is not what this mechanism does.** Verified directly against
`01_sampling_pipeline_main.R` lines 417-459 (`bound_hex_clip`): the hex
grid is not one national grid later attributed to an LGA - it is built
**LGA by LGA from the start** (`split_admins <- split(nga_admin2,
adm2_pcode)`, then `st_make_grid()`/`st_intersection()` *per LGA polygon*,
with `adm2_name` baked into every hexagon's `uuid_hex` at creation). So a
hexagon belongs to exactly one LGA's candidate pool from the moment it
exists - there is no shared national hex pool for a ward polygon to leak
across in the first place.

Given that, the actual mechanism:
- Every finalized household/site already gets its ward via a point-in-polygon
  join against the GRID3 `wards` layer (`finalize_households()` in
  `03_stage2_household_selection.R`, `st_join(..., wards_proj, join =
  st_within)`) - the same `wards` sf object already loaded wherever this
  pipeline runs. This layer is used only as a per-point "which ward is this
  in" test - never to define or clip the hex grid's own extent.
- When redrawing a replacement for **LGA-A's** stratum specifically
  (candidate pool already 100% confined to LGA-A's own hexagons, per the
  above), draw a candidate, run its point through the same `st_within` join,
  and reject/redraw if it lands in a ward LGA-A's own reporting partner(s)
  named as inaccessible. Because the candidate was never eligible to be
  anything but an LGA-A hexagon, a "yes, in Ward W" result here can only
  ever mean "in LGA-A's portion of Ward W" - no clipped/intersected
  "LGA+Ward" polygon object needs to be constructed for this to be true.
- **LGA-B's own redraw never sees this exclusion at all.** It's a separate
  function call against LGA-B's own hexagons, looking up exclusions from
  the master log filtered to `lga == LGA-B` - a request Partner X logged
  against LGA-A is filtered out before LGA-B's redraw ever runs, regardless
  of whether Ward W's real-world polygon happens to physically touch LGA-B
  too. This is also why one master log file (not per-LGA files) is fine:
  `lga` is already part of every row and every lookup key (see "The master
  log" above) - the partition you'd get from separate files already exists
  inside the one file.
- Cluster-level requests (site-specific, not ward-wide) don't need this -
  the existing unfiltered redraw is correct for those, since nothing about
  the surrounding area is actually inaccessible.

Not yet implemented in `04_stage2_cluster_reallocation.R` itself - this is
the design, to be built alongside `03_route_and_flag.py` once there's a
real request to process. Until then, a ward-level request would still use
the existing unfiltered functions, which for a small/scattered
inaccessible area is fine in practice but for a large, concentrated one
could require several report -> resample -> report-again cycles before a
usable cluster emerges.

## Representative vs. indicative classification

Every resampled cluster/stratum needs to carry, into the delivered frame
and the partner packages, whether it's still representative of the
original design or has become indicative-only because of how much of the
stratum had to be substituted. Planned columns (added when `03` is built,
threaded through the same way `coverage_status`/`exclusion_reason` already
are): `resampled_due_to_access_issue` (bool), `access_issue_reason_category`,
`representativeness_status` (`representative` / `indicative`).

**Decided (2026-08-20): a computed, self-deriving threshold**, not a
per-case human call - same style as the existing certainty-stratum MoE
check, so the cutoff is derived per stratum rather than a fixed number
picked in the abstract. Not yet specified precisely (needs building
alongside `03`), but the natural candidate metric, now that reporting is
ward-aware: the fraction of a stratum's achieved sample drawn from
access-issue replacement clusters (or the ward-level equivalent - fraction
of a stratum's wards carrying an active `accessible = No` report), feeding
into a `realized_moe()`-style recomputation the same way the certainty-
stratum check already reuses that function for a different purpose. The
number(s) behind it must be real, current figures at the point of
reporting (revised MoE, % of stratum resampled) - same standard the rest
of this project holds itself to, not an assertion.

## Known bug (found 2026-08-21) - clusters spanning >1 ward silently drop the extra ward(s)

**FIXED 2026-08-21**, same day it was found - this section's heading
previously said "not yet fixed" but that went stale; left the rest of the
write-up below as-is since it's still the accurate root-cause record.
`load_cluster_rows_by_partner()` was rewritten to key by `(cluster_id,
ward)` pairs instead of collapsing to one row per cluster - see that
function's own current docstring in `01_generate_accessibility_reports.py`
for the fix detail.

`load_cluster_rows_by_partner()` in `01_generate_accessibility_reports.py`
(lines 139-143) picks one "representative" row per `cluster_id` to
determine that cluster's (State, LGA, Ward) for the generated Ward
Accessibility sheet:

```python
cluster_repr = {}
for r in rows:
    cid = r["cluster_id"]
    if cid not in cluster_repr or r["status"] == "primary":
        cluster_repr.setdefault(cid, r)
```

`dict.setdefault(cid, r)` only inserts the first time `cid` is seen -
once the key exists, later calls are no-ops regardless of the `or
r["status"] == "primary"` condition in front of them, which is dead code.
The actual behavior is "whichever row is first for this cluster_id in the
CSV's file order wins," silently discarding every other row for that
cluster - including ones whose household falls in a genuinely different
ward (a hexagon can span more than one ward's polygon; each household is
joined to its own ward individually, per "Draw-pool protocol" above, so
this is expected in the underlying data, just not handled when collapsing
to one row per cluster for the ward-level report).

**Found via real partner reports**, both traced to this same root cause:
Save the Children flagged Tofa ward (Bungudu LGA) as "not on the list" -
`non_idp_NG037005_4` has 11 of 12 household rows in Samawa, 1 in Tofa,
and Tofa lost the race. Save the Children also flagged "Mbakyaha ward is
actually in Vandeikya, not Kwande" - `non_idp_NG007011_14` has households
split across Mbaketsa/Mbakyaha/Tondov Ll, same mechanism.

**Scope, checked directly against the WORKING frame, not assumed**: 1,214
of 3,428 clusters nationally (35%) have households spanning more than one
ward, leaving **1,210 distinct (partner, State, LGA, Ward) combinations
missing** from the generated Ward Accessibility sheets - **all 19
partners affected**, not a Save the Children-specific issue.

**FIXED and redistributed same day (2026-08-21)** - this paragraph
previously said "not fixed yet," which went stale. Confirmed directly
against `output/distribution_log.csv`: all 19 partners were redistributed
at 2026-08-21T12:56 via `distribute_to_partner_folders.py --execute
--replace-existing`, with COOPI (2 rows) and INTERSOS (34 rows) going
through the merge-preserving path described in that script's own header
comment - genuine partner-filled answers were carried over, not
overwritten blind.

## "Reported by" and "Last reported date" (added 2026-08-28)

Every level of the accessibility workflow now carries who reported (three
categories: `Partner`, `Needs review` - an unclassified log row, see the
provenance-columns work above - or `Not yet reported`) and when, most
recently. Ward grain (`04_build_master_accessibility_status.py`'s output)
computes these directly; cluster/strata/LGA grain (the impact workbook)
aggregates them from the wards each one actually covers - a cluster
spanning >1 ward, or any stratum/LGA, commonly shows a semicolon-joined
mix (e.g. "Not yet reported; Partner") - this is the expected, normal case
above ward level, not an inconsistency. Dates are parsed from whatever
format a partner actually used (checked directly: 1,749 DD/MM/YYYY, 239
YYYY-MM-DD, 31 with a time component) and a parsed date after today is
treated as unparseable rather than real - this excludes ~450 FACT rows
with a known Excel-autofill-drag corruption (dates drifting as far as the
year 2261) from ever being reported as a "most recent" date. See the
impact workbook's own README sheet for the full explanation shown to
anyone opening the file.

## Bug found and fixed 2026-08-27 - "confirmed by blank row" was applying per-PARTNER, not per-ward

`04_build_master_accessibility_status.py`'s "confirmed_by_partner_report
(blank row - not flagged)" status previously fired for a ward the moment
*any* partner covering it had returned *any* report at all, regardless of
whether that specific ward was ever actually a row in what they returned.
Wrong whenever a partner's current assignment has grown since their last
return (frame changes, or - the confirmed real case - a genuinely
incomplete first submission): FACT's 189 wards missing from their returned
file (see "Issues to Review" on the FACT cleaned-listing workbook) were
showing as reviewed-and-clear, when FACT had never seen those rows at all.
Fixed: `wards_present_in_returned_files()` now reads each partner's actual
returned `.xlsx` directly and checks per-(partner, ward), not per-partner -
confirmed-by-blank-row dropped 1,423 -> 1,234 (the exact 189-row FACT gap,
verified directly against 3 sample wards before and after). The other 8
returned files were already 100% row-complete against their current
assignment, so this was a no-op for them - checked directly, not assumed.
**Rerun `04` and `05` after any refresh of `accessibility_reports_returned/`
or the WORKING frame** - this check reads the returned files live each run.

## Not yet done

- `03_route_and_flag.py`, including the representative/indicative
  self-deriving threshold (metric decided, exact formula not yet specified)
- The ward-scoped draw-pool rejection filter in
  `04_stage2_cluster_reallocation.R` (design decided above, not built - no
  real request has needed it yet)
- A generalized, parameterized version of the 2026-08-06 targeted-resample
  scripts (currently written for that specific 24-LGA run)
- Scoped map/factsheet/KML regeneration + robocopy-mirror redistribution for
  only the clusters a resolved request actually changed - though
  `BUILD_DC_ONLY_PARTNER` (added 2026-08-27, see below) now gets most of
  the way there for a single-partner scope.
- **DONE 2026-08-27** (previously listed here as not fixed): `source_channel`
  being hardcoded regardless of who actually typed a given answer. Two
  real provenance columns (`Reported by (Partner / IMPACT-default)`,
  `Source channel`) now exist on both sheets of every generated report,
  and `02_ingest_accessibility_reports.py` reads them instead of
  hardcoding. See `../CLAUDE.md`'s Revision 2026-08-27 for full detail,
  including the master-log backfill and the 186 rows still marked "needs
  review" rather than guessed.

## Ad-hoc reports (added 2026-08-27)

`input/ad_hoc_reports/` - for a one-off, non-recurring supplement outside
the normal 19-partner cycle (e.g. `FHI 360_Mobbar_ADHOC_accessibility_
report_2026-08-27.xlsx` - asking FHI 360 specifically about 7 Mobbar wards
excluded by the international border buffer, not the normal per-partner
template). Deliberately NOT in `accessibility_reports_generated/` or
`_returned/` - those folders and their naming convention belong to `01`/
`02`'s standard `*_accessibility_report.xlsx` glob; dropping a differently-
scoped file in there risks it being silently mismatched to the wrong
partner key on ingest. When an ad-hoc report like this comes back filled
in, it needs a small dedicated one-off ingestion step (not `02_ingest`
directly), since its rows describe wards outside the partner's normal
WORKING-frame assignment.

## Partner-matching constants consistency check (added 2026-08-28)

`IN_SCOPE_STATES`, `PROPOSED_RECONCILIATION`, and `COMBINED_PARTNER_SPLITS`
are hand-copied into 5 separate scripts (4 Python, 1 R - see the header of
`../scripts/partner_coverage/analysis_sanity_check_partner_matching_
constants.py` for the full list and reasoning) rather than imported from one
shared module, per this project's deliberate standalone-script convention.
Flagged by the comprehensive sweep as a drift risk (currently all 5 copies
ARE in sync, verified) - decided 2026-08-28 to keep the duplication as-is
for now (given the same-day resampling push) but add a script that actually
checks the 5 stay identical, rather than relying on someone remembering to
update all 5 by hand. Run `analysis_sanity_check_partner_matching_
constants.py` any time one of the 5 is touched, or periodically. Revisit
consolidating to a single shared data file after the resampling push, per
Jack's own call.

## Pending ad-hoc proposal override (added 2026-08-28)

`ad_hoc_reports/pending_adhoc_proposals.csv` is a small, hand-maintained
registry for one specific case: a ward that's genuinely eligible and
unreported (so it would normally get the universal default-Accessible
status - see the ward-universe fix above) but where we've made a live,
specific, still-unanswered ask to a partner about it (i.e. via an
`ad_hoc_reports/*.xlsx` proposal). Showing that ward as "Accessible" while
the ask is still outstanding overstates what's actually confirmed.
`analysis_accessible_area_layer.R` reads this file after computing the
normal default and overrides just the listed (state, LGA, ward) rows from
Accessible/default_unreported to Inaccessible/pending_adhoc_proposal_
response - a narrow, explicit exception, NOT a change to the general
default rule, which is untouched everywhere else. First used 2026-08-28 for
Mobbar/Bogum and Mobbar/Gudumbali West (the FHI 360 Mobbar supplement, see
`ad_hoc_reports/FHI 360_accessibility_report_MOBBAR_SUPPLEMENT_2026-08-27.
xlsx`) - Jack's own call, confirmed a genuine definitional decision rather
than a bug. Once a proposal is resolved (accepted or declined), remove its
row(s) from this CSV and rerun `run_accessibility_refresh.py` - an accepted
ward then flows through the normal reporting path once a report exists for
it; a declined one goes back to whatever its normal default would be.

## Single-partner scoping (added 2026-08-27, extended 2026-08-28)

`BUILD_DC_ONLY_PARTNER` (env var, unset by default = normal full-19-partner
behaviour) is read by `../scripts/field_guide_production/
build_partner_dc_packages.py`, `build_cluster_factsheets.py`, and (as of
2026-08-28 - flagged as a gap by the comprehensive sweep, since it's the
one sibling script that touches a partner's live SharePoint folder without
this hook) `build_partner_lga_boundary_kml.R`. Set it to one partner's
exact name to regenerate/redistribute only that partner's own
KML/maps/summary-workbook/cluster-factsheet/LGA-boundary-KML files, without
touching the other 18 partners' already-delivered material. Added for the
Solidarités partner-name fix (`../CLAUDE.md`'s Revision 2026-08-27) but is a
permanent, reusable hook - reach for it whenever a fix is genuinely scoped
to one partner, rather than rerunning any of these scripts for all 19.
