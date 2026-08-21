# Resampling workflow

Handles field-reported accessibility/collection problems in specific
clusters/LGAs, separately from the main numbered pipeline (`../scripts/`)
and the field-guide production layer (`../scripts/field_guide_production/`).
Scaffolded 2026-08-20; first real partner data (Save the Children)
processed 2026-08-21.

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
    copy) before running script 02.
- `output/`
  - `resampling_requests_log.csv` - the master, append-only request log,
    and the first true output of this workflow. Never hand-edit; only
    `02_ingest_accessibility_reports.py` writes to it.
  - `distribution_log.csv` - append-only record of every report actually
    copied to a partner folder (timestamp, partner, destination path).
    Written only by `distribute_to_partner_folders.py --execute`.
  - Future outputs (routing/resolution results, revised frame archives)
    land here too, once `03` is built.

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

Every reported issue gets resampled (donor/management decision, 2026-08-20
- see below); the framework routes to *which* mechanism, and separately
determines the representative/indicative flag:

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

## Known bug (found 2026-08-21, not yet fixed) - clusters spanning >1 ward silently drop the extra ward(s)

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

**Not fixed yet** - the generated reports have already been distributed
(some may already carry partner-filled input), so per the "don't rerun
script 01 casually" rule above, this needs a merge-preserving patch (add
only the missing ward rows to each partner's *existing* distributed copy)
rather than a full regenerate, and needs the user's sign-off on approach
before either script or distributed files are touched.

## Not yet done

- `03_route_and_flag.py`, including the representative/indicative
  self-deriving threshold (metric decided, exact formula not yet specified)
- The ward-scoped draw-pool rejection filter in
  `04_stage2_cluster_reallocation.R` (design decided above, not built - no
  real request has needed it yet)
- A generalized, parameterized version of the 2026-08-06 targeted-resample
  scripts (currently written for that specific 24-LGA run)
- Scoped map/factsheet/KML regeneration + robocopy-mirror redistribution for
  only the clusters a resolved request actually changed
- `source_channel` in the master log is hardcoded to `"partner_excel_return"`
  by `02_ingest_accessibility_reports.py` for every row, regardless of
  whether the returned file was actually filled in by the partner
  themselves or hand-transcribed by a coordinator from raw
  `partner_raw_comms/` material (email/WhatsApp/call) via an
  `accessibility_reports_drafts/` copy. Flagged 2026-08-21, not fixed -
  would need either a real provenance column in the template itself
  (touches the 19 already-distributed files) or some other per-file
  convention; needs a user decision before changing, not a call to make
  solo.
