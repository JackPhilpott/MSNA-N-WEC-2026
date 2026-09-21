# ==============================================================================
# Builds per-partner data-collection packages for the 2026-08-05 pilot
# handoff: partner_dc_files/<Partner>/<State>/<LGA>/ folders containing KML
# GPS-point files for field teams to load in Maps.me / Google Maps.
#
# Reads:
#   - input_data/boundaries/partner_coverage/Partnerscoverage.xlsx (which
#     partner(s) cover which LGA - wide format, one column per partner)
#   - output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v11_WORKING.csv
#     (household-level sampling frame, already restricted to covered LGAs)
#   - output/data/data_collection/idp_camp_backup_points.csv (re-delineated
#     backup GPS point for the 15 flagged large in-camp sites)
#
# LGA name matching (coverage file text -> adm2_pcode) mirrors
# analysis_partner_coverage.py's norm()/PROPOSED_RECONCILIATION exactly, so
# the same LGAs resolve the same way - duplicated rather than imported per
# this project's standalone-script convention.
#
# Per user decisions (2026-08-05):
#   - Non-IDP: one point per household survey, primary and reserve in
#     SEPARATE kml files.
#   - IDP: one point per cluster (primary interviews' site point; reserve
#     interviews share the identical coordinate, so no separate IDP reserve
#     file is produced). Every in-camp cluster additionally gets a second
#     placemark for its Tier 2 (random-walk fallback) starting point - see
#     idp_camp_backup_points.csv, extended 2026-08-05 (Part 3) from the
#     original 15-largest-camps-only subset to all 81 in-camp clusters,
#     per partner feedback at the ToT that Tier 1 listing feasibility is a
#     broader concern than originally anticipated. Tier 2 backup points were
#     originally folded into idp_clusters_primary.kml as extra placemarks;
#     since 2026-08-06 they get their own idp_clusters_tier2_backup.kml per
#     LGA folder instead (user flagged them as hard to find buried inside
#     the primary file - the points were always present, just not
#     separately named/discoverable).
#   - An LGA covered by >1 partner gets identical folders duplicated into
#     each partner's tree (only 1 such LGA currently: Sokoto/Isa).
#   - Since 2026-08-06: one summary Excel workbook per partner, written at
#     that partner's root folder (not per LGA), listing every GPS point
#     across all their LGAs/point-types with the same metadata as the KML
#     descriptions, for teams who prefer a table over opening every KML.
#   - Since 2026-08-13: LGA folders split by population group
#     (Non_IDP/ vs IDP/), each with its own KML/ and Cluster_guide/
#     subfolders - <Partner>/<State>/<LGA>/<Non_IDP|IDP>/<KML|Cluster_guide>/
#     - per user request, now that the LGA folder holds both KML points AND
#     per-cluster field-guide docx files (build_cluster_factsheets.py) and a
#     flat folder got too cluttered. The LGA-level summary map PNG stays at
#     the plain <LGA>/ level (it isn't population-group-specific). Rebuilt
#     from scratch into this structure, not reorganized in place.
#
# 2026-09-05: partner summary workbook extended with live achieved status,
# per Jack + a direct FACT request (they couldn't tell from the dashboard/
# KML alone which points were already done). Meant to be rerun daily/every-
# other-day alongside refresh_working_frame_daily.R (run that FIRST - this
# script's KML output already benefits from a fresh WORKING with no extra
# changes needed here, since KML placemarks were already WORKING-sourced).
# The workbook additions below are new:
#   - "Sampling Points" sheet now sourced from FULL (not WORKING), so
#     already-achieved points stay visible with real status - previously
#     this sheet just silently lost a row the moment it was achieved
#     (inherited from KML's WORKING source, which is correct for KML but
#     was never right for a status-tracking sheet).
#   - New "Needs Collecting" sheet - the FULL-sourced rows filtered to
#     Status != Complete. Functionally close to what the old WORKING-
#     sourced Sampling Points sheet used to show, but now genuinely fresh
#     each run rather than however-stale WORKING happened to be.
#   - New "Cluster Summary" sheet - one row per cluster (Non-IDP + IDP
#     unified), Target/Reserve/Collected/Achieved/Still Needed/Status/Last
#     Collection Date - the "am I basically done with this LGA" view.
# Achieved status computed directly from 2_monitoring's real_submissions.csv
# each run (not from WORKING's row-presence, which can lag) - mirrors
# dashboard_app/global.R's is_achieved()/is_collected() exactly (duplicated,
# not imported, per this project's standalone-script convention), so this
# workbook and the live dashboard never disagree on what counts as done.
# Non-IDP: exact survey_id join (a specific pre-assigned building really
# was or wasn't visited). IDP: count-based per cluster (on-site listing
# numbers don't map to the frame's pre-assigned slot labels - see
# refresh_working_frame_daily.R's header for the full reasoning) - an IDP
# row represents a whole cluster already, so its "Achieved" is a count
# ("8 of 12"), never a per-point yes/no.
# ==============================================================================
import csv
import datetime
import difflib
import os
import re
import shutil
import sys
import time
from collections import defaultdict, Counter
from xml.sax.saxutils import escape

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
sys.path.insert(0, PROJECT_DIR + r"\scripts\shared")
from assert_plausible import assert_plausible  # noqa: E402
# LGA-level summary maps (build_lga_summary_maps.R), copied into each
# covering partner's LGA folder below - 2026-08-07.
LGA_MAPS_DIR = PROJECT_DIR + r"\output\maps\lga_summary"
STRATA_CSV = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample\strata_level_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
_LOCKED_FALLBACK_COPY = r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"
if os.path.exists(_LOCKED_FALLBACK_COPY):
    # Source file was open/locked in Excel at run time - fall back to a
    # just-taken copy instead (2026-08-06). Hardened 2026-08-19: this
    # fallback previously had no staleness check, and a copy left over from
    # 2026-08-06 silently got reused 13 days later during the Dange-Shuni
    # partner reallocation, overriding a just-made edit with no warning.
    # Now: refuse to use the copy at all if it's more than an hour old (too
    # old to plausibly be "just taken" by this run's own lock event), and
    # loudly warn even when it's fresh, so this is never silent again.
    _copy_age_s = time.time() - os.path.getmtime(_LOCKED_FALLBACK_COPY)
    if _copy_age_s > 3600:
        raise SystemExit(
            f"ERROR: {_LOCKED_FALLBACK_COPY} exists but is "
            f"{_copy_age_s / 3600:.1f} hour(s) old - too stale to trust as "
            f"a fresh locked-file fallback. Close Partnerscoverage.xlsx if "
            f"it's open in Excel, delete this stale copy, and rerun."
        )
    print(
        f"WARNING: Partnerscoverage.xlsx appears locked - using a "
        f"{_copy_age_s / 60:.0f}-minute-old fallback copy instead: {_LOCKED_FALLBACK_COPY}"
    )
    COVERAGE_XLSX = _LOCKED_FALLBACK_COPY
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v11_WORKING.csv"
STAGE2_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv"
# 2026-09-08 fix: was pointed at dashboard_app/data/ - the BUNDLED MIRROR
# that only updates as a side effect of a full dashboard deploy, not the
# canonical daily-refreshed source. Same bug class already found and fixed
# in refresh_working_frame_daily.R the same day (see 1_sampling/CLAUDE.md's
# rebuild section) - currently byte-identical by chance, but would silently
# drift the next time canonical updates without an intervening deploy.
REAL_SUBMISSIONS_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\2_monitoring\data\real_submissions.csv"
# Confirmed-only deletion basis (2026-09-08 audit fix) - this script was the
# last of 4 consumers still reading quality_exclusion_reason directly
# (blank=OK, ANY non-blank excludes), which wrongly drops a still-pending/
# contested tracker row from Achieved before Jack has actually confirmed it.
# The other 3 (refresh_working_frame_daily.R, merge_partner_resample_batch.R,
# 05_build_accessibility_impact_workbook.py) were repointed to this overlay
# 2026-09-06/07 - see 1_sampling/CLAUDE.md. Verified against current data
# before fixing: 0 rows currently affected (every non-blank
# quality_exclusion_reason row today happens to already be confirmed), so
# this closes a live gap rather than changing any number right now.
CONFIRMED_DELETIONS_OVERLAY_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\2_monitoring\data\CONFIRMED_DELETIONS_OVERLAY.csv"
BACKUP_POINTS_CSV = PROJECT_DIR + r"\output\data\data_collection\idp_camp_backup_points.csv"

# 2026-09-19 fix - two overlay-exclusion files WORKING/KML already apply
# (via scripts/shared/frame_status.R's compute_cluster_accessibility(), wired
# into refresh_working_frame_daily.R) but this script's FULL-sourced workbook
# sheets (Sampling Points / Needs Collecting / Cluster Summary) never read at
# all - confirmed via grep, zero references to either file anywhere in this
# script before this fix. KML output was NEVER affected (it's WORKING-sourced,
# see frame_rows_all below - a cluster excluded by either overlay simply never
# reaches WORKING to begin with), but a cluster excluded this way still showed
# up in the FULL-sourced sheets as "Not started"/needing collection, directly
# contradicting what the same partner's own KML/WORKING already reflects.
#   - cluster_accessibility_overlay.csv (2026-09-13c): a partner-reported
#     CLUSTER-level "No" (e.g. ACF's Tambuwal IDP relocations) - additive only,
#     already latest-wins/pre-filtered to excluded cluster_ids by
#     resampling/scripts/build_cluster_accessibility_overlay.py.
#   - target_correction_dropped_clusters.csv (2026-09-14, Task 5): excess
#     not-yet-started capacity dropped because the stratum's TRUE requirement
#     (target_sample_representativity) needs fewer clusters than currently
#     assigned - cumulative/append-only, per compute_target_correction_drops.R.
# Same "missing file = no exclusions, not an error" convention as the R-side
# loaders (frame_status.R's load_cluster_accessibility_overlay()/
# load_target_correction_drops()) - both files are optional/additive.
CLUSTER_ACCESSIBILITY_OVERLAY_CSV = PROJECT_DIR + r"\resampling\output\cluster_accessibility_overlay.csv"
TARGET_CORRECTION_DROPPED_CLUSTERS_CSV = PROJECT_DIR + r"\resampling\output\target_correction_dropped_clusters.csv"


def _load_cluster_id_set(path):
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        return {r["cluster_id"] for r in csv.DictReader(f)}


CLUSTER_ACCESSIBILITY_OVERLAY_EXCLUDED = _load_cluster_id_set(CLUSTER_ACCESSIBILITY_OVERLAY_CSV)
TARGET_CORRECTION_DROPPED_CLUSTERS = _load_cluster_id_set(TARGET_CORRECTION_DROPPED_CLUSTERS_CSV)
print(f"Loaded {len(CLUSTER_ACCESSIBILITY_OVERLAY_EXCLUDED)} cluster-accessibility-overlay exclusion(s), "
      f"{len(TARGET_CORRECTION_DROPPED_CLUSTERS)} target-correction drop(s).")


def _cluster_overlay_excluded(cluster_id):
    return cluster_id in CLUSTER_ACCESSIBILITY_OVERLAY_EXCLUDED or cluster_id in TARGET_CORRECTION_DROPPED_CLUSTERS
# Moved 2026-08-06 by the user from "6. Outputs\partner_dc_files" - same
# per-partner folder structure, new parent location.
OUT_ROOT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"

IN_SCOPE_STATES = {
    "Adamawa", "Borno", "Yobe",
    "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto", "Zamfara",
    "Benue", "Kogi", "Nasarawa", "Niger", "Plateau",
}


def norm(s):
    if s is None:
        return ""
    s = str(s).strip().lower()
    s = s.replace("/", " ").replace("-", " ")
    s = re.sub(r"[\'\u2018\u2019\u02bc\ufffd]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def safe_folder_name(s):
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


def lga_map_filename(pcode, lga_name):
    # Must match build_lga_summary_maps.R's safe_name() exactly:
    # gsub("[^A-Za-z0-9]+", "_", s)
    return f"{pcode}_{re.sub(r'[^A-Za-z0-9]+', '_', lga_name)}.png"


# "IRC/LHI" is a single column in the source coverage sheet, but IRC and LHI
# are two separate organisations (confirmed with the user 2026-08-07) - the
# coverage sheet's author used the slash to mean "IRC and/or LHI", not a
# joint entity name. There's a separate standalone "IRC" column elsewhere in
# the same sheet with its own distinct LGAs, but LHI never appears on its
# own anywhere - every trace of it is inside this one combined column.
# Expanding it here means every LGA under "IRC/LHI" gets duplicated into
# BOTH an "IRC" folder (merging with IRC's own separately-assigned LGAs) and
# a new "LHI" folder, so both organisations definitely receive the package
# regardless of who ends up fielding it - same reasoning already applied to
# genuinely multi-partner LGAs like Sokoto/Isa (DRC + IRC/LHI).
COMBINED_PARTNER_SPLITS = {
    "IRC/LHI": ["IRC", "LHI"],
}

PROPOSED_RECONCILIATION = {
    ("Zamfara", "Birnin Magaji/Kiyaw"): "NG037003",
    ("Zamfara", "Kauran Namoda"): "NG037008",
    ("Kaduna", "Makarfi"): "NG019018",
    ("Kaduna", "Zangon-Kataf"): "NG019022",
    ("Kebbi", "Wasagu"): "NG022019",
    ("Benue", "Otukpo"): "NG007019",
    ("Kogi", "Olamaboro"): "NG023018",
    ("Nasarawa", "Eggon"): "NG026010",
    ("Niger", "Munya"): "NG027018",
    ("Plateau", "Barkin Ladi"): "NG032001",
}

# ---------------------------------------------------------------------------
# 1. Master LGA list (adm2_pcode <-> state/lga names) from the live frame
# ---------------------------------------------------------------------------
with open(STRATA_CSV, encoding="utf-8") as f:
    strata_rows = list(csv.DictReader(f))

master_lgas = {}
for r in strata_rows:
    master_lgas[r["adm2_pcode"]] = {
        "adm1_name": r["adm1_name"], "adm2_name": r["adm2_name"],
    }

lga_index = {}
master_by_state = defaultdict(list)
for pcode, v in master_lgas.items():
    lga_index[(norm(v["adm1_name"]), norm(v["adm2_name"]))] = pcode
    master_by_state[v["adm1_name"]].append(v["adm2_name"])

# ---------------------------------------------------------------------------
# 2. Partner coverage: adm2_pcode -> set of partner names
# ---------------------------------------------------------------------------
wb = openpyxl.load_workbook(COVERAGE_XLSX, data_only=True)
partners_by_pcode = defaultdict(set)
unmatched_coverage_rows = []

for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    rows = list(ws.iter_rows(values_only=True))
    header = rows[0]
    count_idx = header.index("COUNT")
    partner_col_idx = list(range(3, count_idx))
    for r in rows[1:]:
        if r[2] is None:
            continue
        state = str(r[1]).strip() if r[1] else None
        lga = str(r[2]).strip() if r[2] else None
        if state not in IN_SCOPE_STATES:
            continue
        partners_here = [str(header[i]).strip() for i in partner_col_idx if r[i]]
        if not partners_here:
            continue

        key = (norm(state), norm(lga))
        pcode = lga_index.get(key)
        if pcode is None:
            pcode = PROPOSED_RECONCILIATION.get((state, lga))
        if pcode is None:
            candidates = master_by_state.get(state, [])
            suggestion = difflib.get_close_matches(lga, candidates, n=1, cutoff=0.6)
            unmatched_coverage_rows.append((state, lga, suggestion[0] if suggestion else None))
            continue

        for p in partners_here:
            for expanded in COMBINED_PARTNER_SPLITS.get(p, [p]):
                partners_by_pcode[pcode].add(expanded)

if unmatched_coverage_rows:
    print(f"WARNING: {len(unmatched_coverage_rows)} partner-coverage rows with a partner assigned did not match any master LGA:")
    for state, lga, sugg in unmatched_coverage_rows:
        print(f"  {state} / {lga!r}  fuzzy suggestion: {sugg}")

# Opt-in single-partner scoping (env var, unset by default) - lets a targeted
# fix (e.g. a corrected partner name) regenerate just that partner's live
# SharePoint folder without touching the other 18 partners' already-delivered
# files. Normal/default behaviour (env var unset) is unchanged: every partner.
_only_partner = os.environ.get("BUILD_DC_ONLY_PARTNER")
if _only_partner:
    partners_by_pcode = {pcode: {p for p in partners if p == _only_partner} for pcode, partners in partners_by_pcode.items()}
    partners_by_pcode = {pcode: partners for pcode, partners in partners_by_pcode.items() if partners}
    print(f"BUILD_DC_ONLY_PARTNER set - scoped to '{_only_partner}' only ({len(partners_by_pcode)} LGA(s)).")

print(f"Partner coverage resolved for {len(partners_by_pcode)} LGAs.")

# ---------------------------------------------------------------------------
# 3. Household-level sampling frame (already covered-only)
# ---------------------------------------------------------------------------
# 2026-09-13 fix: sampling_method == "MSNA Light" rows (government-
# negotiated, unverifiable collection - Abadam/Nganzai/Guzamala) were
# silently flowing into the same KML/workbook structures as every normal
# partner point, with no separation at all - checked directly, this script
# had zero sampling_method awareness before this fix. FACT is the assigned
# partner for all 3 MSNA Light LGAs, so their next package regen would have
# mixed these 564 rows into FACT's normal deliverable, undifferentiated -
# exactly what Jack's "must be visibly different, never mixed in"
# requirement (2026-09-11) exists to prevent. Split at load time into the
# normal MSNA Full Design stream (rows_by_pcode/_full, unchanged variable
# names and downstream behaviour) and a separate MSNA Light stream
# (rows_by_pcode_msna_light/_full) - the main Sampling Points/Needs
# Collecting/Cluster Summary sheets and README headline never see MSNA
# Light rows at all; a distinctly-labelled extra sheet and a separate KML
# subfolder do (see write_partner_workbook() and the main loop below).
MSNA_LIGHT_SAMPLING_METHOD = "MSNA Light"


def _is_msna_light(r):
    return r.get("sampling_method") == MSNA_LIGHT_SAMPLING_METHOD


with open(STAGE2_CSV, encoding="utf-8") as f:
    frame_rows_all = list(csv.DictReader(f))
frame_rows = [r for r in frame_rows_all if not _is_msna_light(r)]
frame_rows_msna_light = [r for r in frame_rows_all if _is_msna_light(r)]
print(f"Loaded {len(frame_rows_all)} household-level rows (WORKING - drives KML placemarks): "
      f"{len(frame_rows)} MSNA Full Design, {len(frame_rows_msna_light)} MSNA Light (kept separate).")

rows_by_pcode = defaultdict(list)
for r in frame_rows:
    rows_by_pcode[r["adm2_pcode"]].append(r)

rows_by_pcode_msna_light = defaultdict(list)
for r in frame_rows_msna_light:
    rows_by_pcode_msna_light[r["adm2_pcode"]].append(r)

# ---------------------------------------------------------------------------
# 3b. FULL household-level frame (2026-09-05) - drives the workbook's
# "Sampling Points"/"Needs Collecting"/"Cluster Summary" sheets, so already-
# achieved rows stay visible with real status instead of just disappearing
# the way they correctly do from WORKING/KML. Same in-scope universe as
# WORKING: covered, not excluded, AND currently ward-accessible.
#
# ward_accessible_status handling, added 2026-09-05 (same bug found and
# fixed the same day in merge_partner_resample_batch.R and refresh_working_
# frame_daily.R - see 1_sampling/CLAUDE.md's "Revision 2026-09-05"):
# deliberately NOT filtered out of frame_rows_full itself - checked
# directly first (2026-09-05): 417 real, completed interviews nationally
# (159 Non-IDP + 258 IDP) sit in clusters that are NOW ward-inaccessible.
# Silently excluding those rows from this workbook would erase real,
# already-completed field credit just because the area became inaccessible
# LATER - the opposite of what Jack asked this workbook to get right
# ("whether we have achieved our targets... or still requiring further
# collection"). Instead, ward_accessible_status feeds a 4th Collection
# Status value ("Inaccessible") applied per-row (Non-IDP: that survey_id's
# own building; IDP: the cluster's own site - see _ward_accessible() and
# its call sites below) - Needs Collecting excludes it same as Complete,
# and Cluster Summary's Still Needed floors to 0 for it, but Achieved/
# Collected keep full credit for real work already done. A cluster's
# ward_accessible_status can genuinely differ row-by-row for Non-IDP (a
# hexagon can straddle two wards with different status - verified directly,
# 221 clusters do; NOT a data bug) - always check the specific row/cluster
# in hand, never aggregate to a single per-cluster value.
# ---------------------------------------------------------------------------
# 2026-09-08, Jack's decision (option a): a whole-stratum
# accessibility_loss_below_population_threshold exclusion (build_v3_frame_
# 2026-08-31.R) used to erase real achieved credit entirely from this
# workbook, because frame_rows_full's own base filter (below) dropped such
# rows before ANY per-row nuance (Achieved/Collected preservation) could
# apply - unlike a ward-level exclusion within an otherwise-covered stratum,
# which already preserves credit correctly. Found while building the new
# recheck_population_threshold_exclusions.py tool and applying its first
# real exclusions. Fix: admit these rows into the base pool too (so their
# real Achieved/Collected still show), then treat every one of them as
# effectively inaccessible unconditionally (see _row_effectively_
# inaccessible below) regardless of their OWN row's ward_accessible_status -
# the exclusion decision was made at the whole-stratum level, a broader
# judgment than any single row's own ward.
POPULATION_THRESHOLD_EXCLUSION_REASON = "accessibility_loss_below_population_threshold"


def _population_threshold_excluded_stratum_row(r):
    return r.get("coverage_status") == "excluded" and r.get("exclusion_reason") == POPULATION_THRESHOLD_EXCLUSION_REASON


def _ward_accessible(r):
    # 2026-09-08 audit fix: was `in (None,"","NA") or != "Inaccessible"` -
    # since a blank/NA value is ALWAYS also != "Inaccessible", the first
    # clause was dead and the whole expression collapsed to just
    # `!= "Inaccessible"`, which evaluates True (accessible) for blank/NA
    # too. That's the exact wrong default direction the 2026-09-08 rebuild
    # was built to eliminate - stamp_ward_accessible_status.py's own header
    # states the correct rule explicitly: "a blank ward_accessible_status
    # [is] excluded-pending-review, not accessible" (a genuine ward-geography
    # match failure, not evidence of safety). Verified against current FULL:
    # 452 primary rows nationally (366 FACT) had blank ward_accessible_status
    # and were wrongly showing as Needs-Collecting-eligible under the old
    # logic. Does not affect KML - those are sourced from WORKING, which the
    # R-side merge/refresh scripts already filter correctly.
    status = r.get("ward_accessible_status")
    return status not in (None, "", "NA") and status != "Inaccessible"


def _in_scope_row(r):
    if r["coverage_status"] == "covered" and r["exclusion_reason"] == "none":
        return True
    # 2026-09-08: also admit population-threshold-excluded rows, so their
    # real Achieved/Collected credit still shows (see the constant/helper
    # above) - every such row is then forced effectively-inaccessible
    # unconditionally by _row_effectively_inaccessible below, so it still
    # correctly disappears from Needs Collecting / Still Needed.
    if _population_threshold_excluded_stratum_row(r):
        return True
    return False


with open(STAGE2_FULL_CSV, encoding="utf-8") as f:
    frame_rows_full_all = [r for r in csv.DictReader(f) if _in_scope_row(r)]
frame_rows_full = [r for r in frame_rows_full_all if not _is_msna_light(r)]
frame_rows_full_msna_light = [r for r in frame_rows_full_all if _is_msna_light(r)]
print(f"Loaded {len(frame_rows_full_all)} household-level rows (FULL, covered-or-population-threshold-excluded - drives workbook sheets): "
      f"{len(frame_rows_full)} MSNA Full Design, {len(frame_rows_full_msna_light)} MSNA Light (kept separate).")

rows_by_pcode_full = defaultdict(list)
for r in frame_rows_full:
    rows_by_pcode_full[r["adm2_pcode"]].append(r)

rows_by_pcode_full_msna_light = defaultdict(list)
for r in frame_rows_full_msna_light:
    rows_by_pcode_full_msna_light[r["adm2_pcode"]].append(r)

# ---------------------------------------------------------------------------
# 3d. Sub-4-accessible-household cluster threshold (2026-09-05, Jack's
# decision after discussing the straddling-hexagon findings above). A
# Non-IDP hexagon that straddles two wards can end up with only 1-3 of its
# original primary households still ward-accessible once the other ward is
# marked inaccessible. Decided NOT to keep collecting those few remaining
# households: (a) they're geometrically the closest to the inaccessible
# ward's boundary, so the least reliable to safely/actually complete in
# practice - the same "sends a team toward the edge of a risk zone"
# concern that argued for a stratum-level (not same-hex) supplementary
# redraw in the first place; (b) a dedicated field visit for 1-3
# households is operationally inefficient; (c) the stratum-level
# supplementary draw closes the resulting gap anyway. Checked directly
# before deciding: NOT a blanket "any straddling cluster" rule - of 184
# straddling Non-IDP clusters nationally, 46 have 5 of 6 (or equivalent)
# STILL accessible, which is very much worth keeping (dropping those would
# waste real, low-risk, already-accessible population for no reason and
# unnecessarily inflate the stratum-level shortfall). Threshold: 4.
# Whole-cluster inaccessible clusters (0 accessible) already worked this
# way; this only extends the SAME treatment to the 1-3-accessible case.
# Applied consistently with refresh_working_frame_daily.R and
# merge_partner_resample_batch.R (same threshold, same "count of
# ward-accessible primary rows" basis) - see 1_sampling/CLAUDE.md's
# Revision 2026-09-05 for the full cross-file reasoning.
NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH = 4

cluster_accessible_primary_n = Counter()
# 2026-09-14 fix (found investigating a real Jack-reported issue - MSNA
# Light points showing wrong/missing status for his DO): this used to
# iterate frame_rows_full ONLY, which the 2026-09-13b split deliberately
# excludes MSNA Light rows from (to keep them out of normal Target/
# Achieved figures - correct for THAT purpose). But _row_effectively_
# inaccessible() below reuses this SAME counter for MSNA Light rows too
# (non_idp_metadata_row() is called on both streams) - so every MSNA
# Light cluster_id was permanently invisible to this counter, always
# read as 0 accessible, always failing the <4 threshold regardless of its
# real ward_accessible_status. Verified directly: Abadam/Nganzai's MSNA
# Light rows (genuinely Accessible-ward) were showing Collection
# Status="Inaccessible" in the live workbook before this fix - not a data
# problem, a pure code gap. Fixed by also counting frame_rows_full_msna_
# light's own accessible primary rows into the same counter - MSNA Light
# cluster_ids use a distinct "_lightN" suffix, so there's no collision
# risk with normal design cluster_ids sharing a count. Does NOT affect
# Target/Achieved anywhere - those stay correctly separate per the
# 2026-09-13b split (non_idp_cluster_summary_rows(), which feeds the MSNA
# Light headline block, already computed accessible_primary locally from
# whatever rows it's given and was never affected by this bug - confirmed
# by checking today's headline figures against ward_accessible_status by
# hand before writing this fix).
for r in frame_rows_full + frame_rows_full_msna_light:
    if r["pop_type"] == "non_idp" and r["status"] == "primary" and _ward_accessible(r):
        cluster_accessible_primary_n[r["cluster_id"]] += 1


def _cluster_below_accessible_threshold(cluster_id):
    return cluster_accessible_primary_n.get(cluster_id, 0) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH


def _row_effectively_inaccessible(r):
    """True if this row's whole STRATUM is population-threshold-excluded,
    OR this row's OWN ward is inaccessible, OR this row's cluster is excluded
    by the cluster-accessibility or target-correction overlay (2026-09-19 fix
    - see the loaders above), OR (Non-IDP only) its whole cluster has fallen
    below the accessible-household threshold."""
    if _population_threshold_excluded_stratum_row(r):
        return True
    if not _ward_accessible(r):
        return True
    if _cluster_overlay_excluded(r["cluster_id"]):
        return True
    if r["pop_type"] == "non_idp":
        return _cluster_below_accessible_threshold(r["cluster_id"])
    return False

# ---- Output-plausibility gate (2026-09-08 audit, pass 4) ----
# Direct regression guard for this same day's _ward_accessible() fix (see
# that function's own comment): a row with blank/NA ward_accessible_status
# (unmatched geography) must ALWAYS come back effectively-inaccessible, by
# construction - if this OR-bug ever regresses, a blank-ward row would be
# silently treated as accessible again and could reappear as a to-do item
# in "Needs Collecting". Checked once, nationally, before any per-partner
# workbook is built.
_n_unmatched_wrongly_accessible = sum(
    1 for r in frame_rows_full
    if r.get("ward_accessible_status") in (None, "", "NA") and not _row_effectively_inaccessible(r)
)
assert_plausible("unmatched-ward rows NOT flagged effectively-inaccessible", _n_unmatched_wrongly_accessible, (0, 0),
                  context="a blank/NA ward_accessible_status must always be treated as inaccessible - regression of the 2026-09-08 _ward_accessible() fix")

# ---------------------------------------------------------------------------
# 3e. target_sample / target_sample_representativity per stratum (2026-09-16,
# Decision A of the coordination-session target/achieved consistency review,
# confirmed directly by Jack: "target_sample (frozen) becomes canonical
# headline Target everywhere (dashboard, main frame, partner workbooks);
# target_sample_representativity shown alongside as reference, not
# replaced"). Dashboard/2_monitoring already implemented their own side
# (0 mismatches across 325 strata, per their report-back) - this is the
# matching change on the partner-workbook side, so all three surfaces show
# the same headline Target for the same stratum.
#
# Deliberately a SEPARATE figure from "Target HHs (primary)" on the Cluster
# Summary sheet (per-cluster, live/accessibility-aware, real field-level
# "collect N more households at this exact point" detail) - that column is
# UNCHANGED by this decision, same as target_households was never touched
# by the earlier per-row vs Cluster-Summary-rollup distinction. Only the
# PARTNER/STRATUM-level rollup figures (this README's headline block, and
# the Target Sample Summary table) move to target_sample - matching the
# same "per-row detail stays, only the competing headline rollup changes"
# shape as every other consistency fix in this project's history.
#
# strata-level FULL (not WORKING) is the correct source here, same
# "covered, exclusion_reason=none" scope as frame_rows_full's own
# _in_scope_row() - a population-threshold-excluded stratum's target_sample
# is deliberately excluded from a partner's headline Target (that stratum
# isn't part of their real current design assignment), matching this
# script's own pre-existing precedent of already zeroing "Target HHs
# (primary)" for a population-threshold-excluded cluster - not a new
# asymmetry introduced by this change.
STRATA_LEVEL_V9_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v11_FULL.csv"
TARGET_SAMPLE_REPRESENTATIVITY_CSV = PROJECT_DIR + r"\resampling\output\target_sample_representativity_last_run.csv"

with open(STRATA_LEVEL_V9_FULL_CSV, encoding="utf-8") as f:
    _strata_v11_rows = list(csv.DictReader(f))

strata_target_sample = {}
strata_partners_covering = {}
strata_lga_key = {}   # strata_id -> (adm1_name, adm2_name)
strata_pop_type = {}
for _r in _strata_v11_rows:
    sid = _r["strata_id"]
    if _r.get("coverage_status") == "covered" and _r.get("exclusion_reason") == "none":
        strata_target_sample[sid] = float(_r["target_sample"]) if _r.get("target_sample") not in (None, "", "NA") else 0.0
        strata_partners_covering[sid] = {p.strip() for p in (_r.get("partners_covering") or "").split(",") if p.strip()}
        strata_lga_key[sid] = (_r["adm1_name"], _r["adm2_name"])
        strata_pop_type[sid] = _r["pop_type"]
print(f"Loaded target_sample for {len(strata_target_sample)} covered strata (Decision A headline Target basis).")

strata_target_repr = {}
if os.path.exists(TARGET_SAMPLE_REPRESENTATIVITY_CSV):
    with open(TARGET_SAMPLE_REPRESENTATIVITY_CSV, encoding="utf-8") as f:
        for _r in csv.DictReader(f):
            strata_target_repr[_r["strata_id"]] = float(_r["target_sample_representativity"])
    _n_missing_repr = sum(1 for sid in strata_target_sample if sid not in strata_target_repr)
    print(f"Loaded target_sample_representativity for {len(strata_target_repr)} strata "
          f"({_n_missing_repr} covered strata have no representativity figure yet - shown as partial where relevant).")
else:
    print(f"WARNING: {TARGET_SAMPLE_REPRESENTATIVITY_CSV} not found - representativity reference line will be omitted from every workbook's headline.")


def partner_covered_strata_ids(partner_name):
    return [sid for sid, partners in strata_partners_covering.items() if partner_name in partners]


# ---------------------------------------------------------------------------
# 3c. Achieved status, computed fresh from 2_monitoring's real_submissions.csv
# every run - mirrors dashboard_app/global.R's is_achieved()/is_collected()
# exactly (see header note). Two lookups:
#   - achieved_date_by_survey_id: Non-IDP exact per-point join (a specific
#     pre-assigned building either has been visited or hasn't).
#   - per-cluster achieved/collected counts + most-recent date: used for
#     IDP rows (count-based - no per-point identity is meaningful there)
#     and for the Cluster Summary sheet, both population types.
# ---------------------------------------------------------------------------
with open(REAL_SUBMISSIONS_CSV, encoding="utf-8") as f:
    real_subs = list(csv.DictReader(f))
print(f"Loaded {len(real_subs)} real submission rows.")

# FIX 2026-09-11: was status=="confirmed" only, missing "contested" - a
# contested row that was reviewed and upheld (deletion stands) is equally
# settled/terminal as a plain "confirmed" one, per 2_monitoring's own
# TERMINAL_STATUSES = {"confirmed", "contested"} (issue_tracker.R). The old
# filter silently still counted an upheld-on-appeal deletion as Achieved.
_CONFIRMED_OVERLAY_TERMINAL_STATUSES = {"confirmed", "contested"}
with open(CONFIRMED_DELETIONS_OVERLAY_CSV, encoding="utf-8") as f:
    _confirmed_deleted_uuids = {r["uuid"] for r in csv.DictReader(f) if r["status"] in _CONFIRMED_OVERLAY_TERMINAL_STATUSES}
print(f"Confirmed-deletions overlay: {len(_confirmed_deleted_uuids)} confirmed/contested uuid(s) excluded from Achieved.")

# FIX 2026-09-14 (Coordinator cross-check, msna-n-wec-2026-91): dropped an
# independent is_duplicate=="TRUE" exclusion here - a raw/pending signal on
# real_submissions.csv, not a confirmed deletion decision, so it silently
# reimposed the pre-2026-09-11 pessimistic policy (Jack: "the team would
# rather risk asking a field team to go back for a specific interview later
# than have them oversample now against a pessimistic count") through a
# side door the 2026-09-08 quality_exclusion_reason audit never looked at,
# since it's a different column. 1,323 real completed interviews nationally
# were wrongly excluded this way (is_duplicate=="TRUE" but never actually
# confirmed/contested in the overlay) - ~7% of all completed interviews.
# Only the overlay's confirmed/contested status is authoritative for
# exclusion now, matching 2_monitoring's global.R is_achieved() exactly.


def _is_achieved(r):
    return (
        r.get("interview_outcome") == "completed"
        and r.get("matched_survey_id") not in (None, "", "NA")
        and r.get("submission_uuid") not in _confirmed_deleted_uuids
    )


def _is_collected(r):
    return r.get("interview_outcome") == "completed"


achieved_date_by_survey_id = {}
for r in real_subs:
    if r.get("pop_type") == "non_idp" and _is_achieved(r):
        sid = r["matched_survey_id"]
        d = r.get("submission_date") or ""
        if sid not in achieved_date_by_survey_id or d > achieved_date_by_survey_id[sid]:
            achieved_date_by_survey_id[sid] = d
print(f"Non-IDP achieved survey_ids (exact join): {len(achieved_date_by_survey_id)}")

cluster_achieved_n = Counter()
cluster_collected_n = Counter()
cluster_last_date = {}
for r in real_subs:
    cid = r.get("matched_cluster_id")
    if not cid or cid == "NA":
        continue
    if _is_collected(r):
        cluster_collected_n[cid] += 1
        d = r.get("submission_date") or ""
        if cid not in cluster_last_date or d > cluster_last_date[cid]:
            cluster_last_date[cid] = d
    if _is_achieved(r):
        cluster_achieved_n[cid] += 1
print(f"Clusters with at least one collected submission: {len(cluster_collected_n)}")

# ---------------------------------------------------------------------------
# 4. IDP camp backup GPS points - every in-camp cluster now has one (Part 3,
#    2026-08-05: extended from the original 15 flagged-camp-only subset to
#    all 81, per partner feedback at the ToT).
# ---------------------------------------------------------------------------
with open(BACKUP_POINTS_CSV, encoding="utf-8") as f:
    backup_rows = list(csv.DictReader(f))
backup_by_cluster = {
    r["site_id"]: r for r in backup_rows if r["backup_gps_lat"] not in (None, "", "NA")
}
print(f"{len(backup_by_cluster)} in-camp clusters with a Tier 2 backup GPS point.")

# ---------------------------------------------------------------------------
# 5. KML writer (plain Placemark/Point, no GDAL schema - simplest for Maps.me)
#
# Per-file colored icon styling added 2026-08-19, per user request, so field
# teams can visually tell primary/reserve and IDP/Non-IDP points apart at a
# glance once several KML files are loaded into Maps.me together (previously
# every point rendered as an identical default pin). Uses Google's standard
# KML "paddle" icon set (googleearth's classic colored-circle pins) - a
# widely-recognized KML convention that Maps.me's Bookmarks import maps onto
# its own bookmark colors. One color per point type, no shape variation
# (kept simple/robust): green=Non-IDP primary, yellow=Non-IDP reserve,
# blue=IDP Tier 1 primary, red=IDP Tier 2 backup. Note: the icon PNG itself
# loads from a Google-hosted URL, so a phone with zero connectivity the
# first time it opens the file may briefly show a generic pin until the
# icon loads once online - this is a Maps.me/KML-icon limitation, not
# something fixable from the file itself.
# ---------------------------------------------------------------------------
ICON_NON_IDP_PRIMARY = "http://maps.google.com/mapfiles/kml/paddle/grn-circle.png"
ICON_NON_IDP_RESERVE = "http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png"
ICON_IDP_PRIMARY = "http://maps.google.com/mapfiles/kml/paddle/blu-circle.png"
ICON_IDP_TIER2_BACKUP = "http://maps.google.com/mapfiles/kml/paddle/red-circle.png"


def write_kml(path, folder_name, placemarks, icon_href=None):
    if not placemarks:
        # 2026-09-19 fix: this used to leave a stale file from a previous run
        # untouched whenever the new placemark list is empty (e.g. every
        # point in this LGA/point-type has since become inaccessible/
        # overlay-excluded/below-threshold) - found via the standing UUID-
        # reconciliation check below turning up KML points that no longer
        # exist in WORKING at all, including a 15-day-stale
        # non_idp_households_primary.kml for Abadam (non_idp_NG008001,
        # Borno - one of the known largely-inaccessible strata) still
        # listing survey_ids from a supplementary cluster long since dropped.
        # A field team loading that file would be pointed at households no
        # longer part of the active design. Now actively clears the stale
        # file instead of silently leaving it for a future team to find.
        if os.path.exists(path):
            os.remove(path)
        return False
    parts = [
        '<?xml version="1.0" encoding="utf-8" ?>',
        '<kml xmlns="http://www.opengis.net/kml/2.2">',
        '<Document id="root_doc">',
    ]
    if icon_href:
        parts.append(
            '<Style id="ptStyle"><IconStyle><Icon><href>'
            f"{escape(icon_href)}</href></Icon></IconStyle></Style>"
        )
    parts.append(f"<Folder><name>{escape(folder_name)}</name>")
    style_ref = "\n      <styleUrl>#ptStyle</styleUrl>" if icon_href else ""
    for i, pm in enumerate(placemarks, start=1):
        desc = escape(pm["description"]).replace("\n", "&#10;")
        parts.append(
            f'  <Placemark id="{escape(folder_name)}.{i}">\n'
            f'\t<name>{escape(pm["name"])}</name>\n'
            f"\t<description>{desc}</description>\n"
            f'      <Point><coordinates>{pm["lon"]},{pm["lat"]}</coordinates></Point>{style_ref}\n'
            f"  </Placemark>"
        )
    parts.append("</Folder>")
    parts.append("</Document>")
    parts.append("</kml>")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    return True


# Ward is sourced from GRID3 (the only national-coverage admin-3 product);
# for the 3 NE states, OCHA/COD also publishes its own official admin-3
# product, stored separately as admin3_cod_name (blank/NA for NW/NC, where
# OCHA/COD has no ward product at all) - see 1_sampling/CLAUDE.md and
# 2_monitoring/field_verify/README.md's 2026-08-10 changelog entry for the
# full boundary-source investigation this is based on. Surfaced here (KML +
# workbook) per partner feedback tracing a "wrong LGA" report to exactly
# this GRID3/OCHA-COD ward disagreement - LGA itself is unaffected either
# way, since it always comes from OCHA/COD's own admin-2 layer, not either
# ward source.
def cod_ward_line(r):
    cod_name = r.get("admin3_cod_name")
    if not cod_name or cod_name == "NA":
        return ""
    return f"Ward (OCHA/COD): {cod_name}\n"


def non_idp_placemark(r):
    label = "Primary" if r["status"] == "primary" else "Reserve"
    seq = r["interview_number"] if r["status"] == "primary" else r["replacement_rank"]
    desc = (
        f"Status: {label} (#{seq})\n"
        f"Cluster: {r['cluster_id']}\n"
        f"Survey ID: {r['survey_id']}\n"
        f"State / LGA / Ward (GRID3): {r['adm1_name']} / {r['adm2_name']} / {r['adm3_name']}\n"
        f"{cod_ward_line(r)}"
        f"Building ID: {r['building_id']}\n"
        f"Building confidence: {r['confidence']}"
    )
    return {"name": r["survey_id"], "description": desc, "lat": r["latitude"], "lon": r["longitude"]}


def idp_primary_placemark(cluster_id, r):
    cat = "In-camp" if r["idp_population_category"] == "idps in camp" else "In-host"
    desc = (
        f"Cluster: {cluster_id}\n"
        f"Category: {cat}\n"
        f"IOM site: {r['iom_site_name']} ({r['iom_site_type']})\n"
        f"State / LGA / Ward (GRID3): {r['adm1_name']} / {r['adm2_name']} / {r['adm3_name']}\n"
        f"{cod_ward_line(r)}"
        f"Site radius (m): {r['site_radius_m']}\n"
        f"Target households (primary): {r['target_households']} | Reserve: {r['reserve_households']}\n"
        f"Use this point for Tier 1 (full household listing). If in-camp and Tier 1 isn't feasible on arrival, "
        f"see the separate Tier 2 backup point KML for this cluster (if in-host, there is no Tier 2 - use "
        f"chief/head-of-settlement listing instead)."
    )
    return {"name": cluster_id, "description": desc, "lat": r["latitude"], "lon": r["longitude"]}


def idp_tier2_backup_placemark(cluster_id, r, backup_row):
    desc = (
        f"Cluster: {cluster_id}\n"
        f"Tier 2 (random-walk) fallback starting point - use ONLY if Tier 1 full household listing is not "
        f"feasible on arrival at the primary point (see idp_clusters_primary.kml). Not a corrected or "
        f"alternate primary location.\n"
        f"IOM site: {r['iom_site_name']} ({r['iom_site_type']})\n"
        f"State / LGA / Ward (GRID3): {r['adm1_name']} / {r['adm2_name']} / {r['adm3_name']}\n"
        f"{cod_ward_line(r)}"
        f"Note: {backup_row['extent_source_note']}"
    )
    return {
        "name": f"{cluster_id} - Tier 2 backup point",
        "description": desc,
        "lat": backup_row["backup_gps_lat"], "lon": backup_row["backup_gps_lon"],
    }


# ---------------------------------------------------------------------------
# 6. Metadata-row builders, for the per-partner Excel summary (mirrors the
#    KML description fields, one row per point, unified schema across the
#    4 point types - blank cells where a field doesn't apply to that type)
# ---------------------------------------------------------------------------
# "Ward (GRID3)" (was plain "Ward") / "Ward (OCHA/COD)": see cod_ward_line()
# above for the source rationale. "Ward (OCHA/COD)" is blank outside the 3
# NE states, where OCHA/COD publishes no admin-3 product at all.
# "Status"/"Sequence" (primary vs reserve rank) predate 2026-09-05 and are
# unrelated to the new "Collection Status" - kept both names since renaming
# "Status" would break anyone already relying on this sheet's columns.
METADATA_COLUMNS = [
    "Partner", "Point Type", "State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)", "Cluster ID", "Survey ID",
    "Status", "Sequence", "Latitude", "Longitude",
    "Building ID", "Building Confidence",
    "IDP Category", "IOM Site Name", "IOM Site Type", "Site Radius (m)",
    "Target HHs (primary)", "Reserve HHs", "Notes",
    "Achieved", "Date Collected", "Collection Status",
]


def cod_ward_value(r):
    cod_name = r.get("admin3_cod_name")
    return cod_name if cod_name and cod_name != "NA" else ""


def non_idp_metadata_row(partner, state_name, lga_name, r):
    label = "Primary" if r["status"] == "primary" else "Reserve"
    seq = r["interview_number"] if r["status"] == "primary" else r["replacement_rank"]
    date = achieved_date_by_survey_id.get(r["survey_id"])
    if date is not None:
        collection_status = "Complete"
    elif _row_effectively_inaccessible(r):
        collection_status = "Inaccessible"
    else:
        collection_status = "Not started"
    return {
        "Partner": partner, "Point Type": f"Non-IDP household ({label.lower()})",
        "State": state_name, "LGA": lga_name, "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Cluster ID": r["cluster_id"], "Survey ID": r["survey_id"],
        "Status": label, "Sequence": seq,
        "Latitude": r["latitude"], "Longitude": r["longitude"],
        "Building ID": r["building_id"], "Building Confidence": r["confidence"],
        "Achieved": "Yes" if date is not None else "No",
        "Date Collected": date or "",
        "Collection Status": collection_status,
    }


def idp_primary_metadata_row(partner, state_name, lga_name, cluster_id, r):
    cat = "In-camp" if r["idp_population_category"] == "idps in camp" else "In-host"
    target = int(r["target_households"]) if r["target_households"] not in (None, "", "NA") else 0
    # 2026-09-21: was min(cluster_achieved_n, target) - the per-cluster
    # oversampling cap. Removed per Jack's 2026-09-20 decision ("include ALL
    # oversampled interviews in achieved counts, without inflating stratum
    # target"), which had landed in 2_monitoring's compute_progress_by_stratum()
    # but not in either of this project's two duplicated workbook generators -
    # so every partner workbook was under-reporting Achieved against the
    # dashboard and against frame_status.R's own achieved_sample. See the
    # matching fix in refresh_partner_workbooks_daily.py; both must stay in
    # step or the daily tier silently re-caps what this script just fixed.
    n_achieved = cluster_achieved_n.get(cluster_id, 0)
    if target > 0 and n_achieved >= target:
        status = "Complete"
    elif _row_effectively_inaccessible(r):
        status = "Inaccessible"
    elif n_achieved > 0:
        status = "Partial"
    else:
        status = "Not started"
    return {
        "Partner": partner, "Point Type": "IDP cluster (Tier 1 primary)",
        "State": state_name, "LGA": lga_name, "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Cluster ID": cluster_id, "Status": "Primary",
        "Latitude": r["latitude"], "Longitude": r["longitude"],
        "IDP Category": cat, "IOM Site Name": r["iom_site_name"], "IOM Site Type": r["iom_site_type"],
        "Site Radius (m)": r["site_radius_m"],
        "Target HHs (primary)": r["target_households"], "Reserve HHs": r["reserve_households"],
        "Achieved": f"{n_achieved} of {target}",
        "Date Collected": cluster_last_date.get(cluster_id, ""),
        "Collection Status": status,
    }


def idp_tier2_metadata_row(partner, state_name, lga_name, cluster_id, r, backup_row):
    return {
        "Partner": partner, "Point Type": "IDP Tier 2 backup point",
        "State": state_name, "LGA": lga_name, "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Cluster ID": cluster_id, "Status": "Tier 2 backup",
        "Latitude": backup_row["backup_gps_lat"], "Longitude": backup_row["backup_gps_lon"],
        "IOM Site Name": r["iom_site_name"], "IOM Site Type": r["iom_site_type"],
        "Notes": backup_row["extent_source_note"],
    }


CLUSTER_SUMMARY_COLUMNS = [
    "Cluster ID", "Population Type", "State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)",
    "Target HHs (primary)", "Reserve HHs", "Collected", "Achieved", "Still Needed",
    "% Achieved", "Collection Status", "Last Collection Date",
]


def non_idp_cluster_summary_rows(state_name, lga_name, primary_rows, reserve_rows):
    by_cluster = defaultdict(lambda: {"primary": [], "reserve": []})
    for r in primary_rows:
        by_cluster[r["cluster_id"]]["primary"].append(r)
    for r in reserve_rows:
        by_cluster[r["cluster_id"]]["reserve"].append(r)
    out = []
    for cluster_id, g in by_cluster.items():
        all_rows = g["primary"] + g["reserve"]
        achieved_dates = [achieved_date_by_survey_id[r["survey_id"]] for r in all_rows if achieved_date_by_survey_id.get(r["survey_id"])]
        # 2026-09-05 fix: "Collected" here used to reuse the same strict,
        # exact-survey_id-matched achieved count as "Achieved" - correct
        # for Achieved (Non-IDP's whole design is per-point exact
        # matching), but Collected's own definition (README: "every
        # completed interview, full stop, includes duplicates/surplus")
        # calls for the loose cluster-level count instead, same source
        # (cluster_collected_n) IDP's Collected already correctly used.
        # Didn't affect Achieved's own value (already correct) or explain
        # the 172-household achieved gap (that was 100% the IDP bug above)
        # - fixed for the same reason, for consistency and because a
        # partner reading "Collected" should get what the column promises.
        n_achieved_exact = len(achieved_dates)
        collected = max(cluster_collected_n.get(cluster_id, 0), n_achieved_exact)
        # Cluster-level accessibility (2026-09-05): a Non-IDP hexagon can
        # straddle two wards with different status (verified, 221 clusters
        # do) - individual rows already carry their own correct per-row
        # status via non_idp_metadata_row. "Target HHs (primary)" is
        # deliberately the ACCESSIBLE-only primary count, not the nominal
        # full-cluster count, so a partially-inaccessible cluster's target
        # doesn't silently count households you're not being asked to
        # visit right now.
        #
        # 2026-09-05, same day - Jack's threshold decision: a cluster with
        # FEWER than NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH (4) accessible
        # primary households is treated as fully inaccessible too, not
        # just the literal 0-accessible case - see the header note above
        # cluster_accessible_primary_n for the full reasoning (those few
        # remaining households sit closest to the inaccessible ward's
        # boundary, least reliable to safely collect; not worth a
        # dedicated visit; the stratum-level supplementary draw covers the
        # resulting gap instead). When this applies, Target HHs and Still
        # Needed both show 0 - NOT the true small accessible count - so the
        # row reads consistently (an "Inaccessible" cluster with a nonzero
        # Target would be confusing). Achieved/Collected are UNAFFECTED -
        # real credit already earned in that small accessible sliver is
        # never removed, same principle as the plain 0-accessible case.
        # 2026-09-08: also exclude population-threshold-excluded-stratum rows
        # here directly (can't just call _row_effectively_inaccessible - that
        # would be circular, since IT calls _cluster_below_accessible_
        # threshold, which is what this very computation feeds).
        # 2026-09-19: also apply the cluster-accessibility/target-correction
        # overlay exclusion here - this block is a SEPARATE, duplicate
        # computation from _row_effectively_inaccessible() (not a call to it,
        # for the circularity reason above), so it needed the same fix
        # independently, not just at the shared function.
        accessible_primary = [pr for pr in g["primary"] if _ward_accessible(pr) and not _population_threshold_excluded_stratum_row(pr)]
        cluster_inaccessible = len(accessible_primary) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH or _cluster_overlay_excluded(cluster_id)
        target = 0 if cluster_inaccessible else len(accessible_primary)
        nominal_target = len(g["primary"])
        # Achieved is UNCAPPED (2026-09-21, Jack's 2026-09-20 oversampling
        # decision - see idp_primary_metadata_row above). It was previously
        # capped at the NOMINAL (full-cluster) target; that cap existed to stop
        # a shrinking accessible-only target from erasing credit already
        # earned, which uncapping achieves just as well and more simply - a
        # fully-inaccessible cluster still shows its full historical credit
        # (417 real interviews nationally), and an over-collected cluster now
        # shows every interview actually done there.
        achieved = n_achieved_exact
        any_r = g["primary"][0] if g["primary"] else g["reserve"][0]
        # 2026-09-14 fix (found by Coordinator tracing a ZOA "target/
        # achieved/still needed don't add up" question, independently
        # re-verified here before applying): this used to count individual
        # accessible primary points with no achieved_date - a per-POINT
        # to-do count, not the household-count gap the "Still Needed"
        # column's own documented definition promises ("Target minus
        # Achieved, floored at 0" - see the column-definitions block below,
        # and the IDP side's matching max(nominal_target-achieved,0) at
        # idp_primary_metadata_row). Consequence: a cluster that already
        # hit its household target via reserve substitution (a different
        # survey_id than the original primary point) still showed a
        # nonzero Still Needed for whichever specific primary points
        # happened to remain individually unvisited - verified on ZOA's
        # live workbook, 4 clusters where the true gap was 41 but this
        # formula reported 52 (an 11-household phantom overstatement).
        # Fixed to match "Target minus Achieved" literally, using the SAME
        # accessible-only `target` already shown in this row's own "Target
        # HHs (primary)" column - not nominal_target - so the two columns
        # stay internally consistent (a nonzero Still Needed next to a
        # Target that already equals Achieved would be its own new,
        # different inconsistency). Naturally floors to 0 whenever achieved
        # already covers the accessible target - resolves the exact
        # "achieved can exceed target" case the 2026-09-05 per-point design
        # was originally trying to sidestep, just via max(..., 0) instead of
        # a parallel point-count mechanism. Since 2026-09-21 achieved is
        # uncapped, so it exceeds target more often (every over-collected
        # cluster) - the max(..., 0) floor is what keeps this correct, and is
        # now load-bearing rather than a rare-edge-case guard.
        still_needed = 0 if cluster_inaccessible else max(target - achieved, 0)
        # Status driven by still_needed (not achieved>=target) - achieved is
        # uncapped and can exceed this row's accessible-only target (a
        # straddling or over-collected cluster), so comparing achieved
        # against target directly would be ambiguous here.
        if cluster_inaccessible:
            status = "Inaccessible"
        elif still_needed == 0 and target > 0:
            status = "Complete"
        elif achieved > 0:
            status = "Partial"
        else:
            status = "Not started"
        out.append({
            "Cluster ID": cluster_id, "Population Type": "Non-IDP", "State": state_name, "LGA": lga_name,
            "Ward (GRID3)": any_r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(any_r),
            "Target HHs (primary)": target, "Reserve HHs": len(g["reserve"]),
            "Collected": collected, "Achieved": achieved, "Still Needed": still_needed,
            "% Achieved": (achieved / target) if target else None,
            "Collection Status": status,
            "Last Collection Date": max(achieved_dates) if achieved_dates else "",
        })
    return out


def idp_cluster_summary_row(state_name, lga_name, cluster_id, r):
    # 2026-09-05 bug fix: this used to compute achieved as min(collected,
    # target) using cluster_collected_n (is_collected only - "completed",
    # no other check) as the base - meaning duplicate/unmatched/quality-
    # excluded submissions were inflating "Achieved" here, even though
    # idp_primary_metadata_row (the Sampling Points sheet) already used the
    # correct, stricter cluster_achieved_n for the exact same figure. 100%
    # of a 172-household gap between this workbook's FACT total and the
    # live dashboard's traced to exactly this - every affected stratum was
    # IDP, none were Non-IDP (which never had this bug - its Achieved is
    # computed from the strict per-survey_id achieved_date_by_survey_id,
    # not from either cluster counter). Collected correctly stays on
    # cluster_collected_n - that column's own definition (README: "every
    # completed interview, full stop, includes duplicates") calls for the
    # loose count; only Achieved needed the strict one.
    nominal_target = int(r["target_households"]) if r["target_households"] not in (None, "", "NA") else 0
    reserve_n = int(r["reserve_households"]) if r["reserve_households"] not in (None, "", "NA") else 0
    collected = cluster_collected_n.get(cluster_id, 0)
    n_achieved = cluster_achieved_n.get(cluster_id, 0)
    # Achieved is UNCAPPED (2026-09-21, same change and same reasoning as the
    # Non-IDP side above and idp_primary_metadata_row) - real credit already
    # earned is never reduced, and an over-collected site now shows every
    # interview actually done there rather than stopping at its own target.
    achieved = n_achieved
    # IDP sites are single-point (a DTM GPS location, not a hexagon) - no
    # straddling-ward/partial-accessibility or accessible-household-COUNT
    # threshold concept applies here (that's Non-IDP-only, see
    # _row_effectively_inaccessible - for IDP it reduces to the plain
    # per-row ward_accessible_status check, nothing more). A site's ward is
    # either accessible or it isn't - no "proportion" in between.
    inaccessible = _row_effectively_inaccessible(r)
    # 2026-09-05 fix: Target HHs now shows 0 when Inaccessible, matching
    # the Non-IDP side's now-consistent behaviour (this bug predates
    # today's threshold discussion - found while checking IDP wasn't
    # wrongly picking up the Non-IDP-only threshold logic, and fixed
    # alongside it for consistency). Previously showed the full nominal
    # target next to "Inaccessible" status, which read as contradictory.
    target = 0 if inaccessible else nominal_target
    if not inaccessible and target > 0 and achieved >= target:
        status = "Complete"
    elif inaccessible:
        status = "Inaccessible"
    elif achieved > 0:
        status = "Partial"
    else:
        status = "Not started"
    return {
        "Cluster ID": cluster_id, "Population Type": "IDP", "State": state_name, "LGA": lga_name,
        "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Target HHs (primary)": target, "Reserve HHs": reserve_n,
        "Collected": collected, "Achieved": achieved, "Still Needed": 0 if inaccessible else max(nominal_target - achieved, 0),
        "% Achieved": (achieved / target) if target else None,
        "Collection Status": status,
        "Last Collection Date": cluster_last_date.get(cluster_id, ""),
    }


README_DEFINITIONS = [
    ("Non-IDP household (primary)", "One planned primary household interview, drawn from an eligible building footprint within a selected Non-IDP cluster. One row = one interview."),
    ("Non-IDP household (reserve)", "A ranked backup household for a Non-IDP cluster, used strictly in rank order (Sequence column) whenever a primary household can't be reached or declines. Reserve list size normally matches the primary target exactly for that cluster (including for combined-draw clusters with a larger-than-standard target) - except where the eligible building pool is smaller than the target, in which case reserve is capped by whatever's left in the pool, down to zero for the smallest clusters. A cluster with zero reserve households has no backup on the list - if its primary household is unreachable or declines, there is no replacement."),
    ("IDP cluster (Tier 1 primary)", "One row per IDP cluster (not per interview) - the site's primary GPS point, used for Tier 1 (full household listing on arrival). 'Target HHs (primary)' / 'Reserve HHs' give that cluster's planned interview and reserve counts."),
    ("IDP Tier 2 backup point", "In-camp clusters only - a second, pre-assigned GPS point for the Tier 2 random-walk fallback, used ONLY if Tier 1 full listing proves infeasible on arrival. Not a corrected or alternate primary location. Host-community IDP clusters have no Tier 2 (they use chief/head-of-settlement listing instead, with no walk fallback)."),
]

README_FIELD_NOTES = [
    ("LGA", "Sourced from OCHA/COD (nga_admin2), the officially-endorsed humanitarian administrative boundary dataset. This is the authoritative LGA source throughout this assessment - see 'A note on LGA vs Ward data sources' below."),
    ("Ward (GRID3)", "Sourced from GRID3, the only ward-level (admin-3) boundary product with national coverage. Used to supplement ward detail - never as a substitute for the LGA column's OCHA/COD source. See 'A note on LGA vs Ward data sources' below."),
    ("Ward (OCHA/COD)", "North-East states only (Borno/Adamawa/Yobe) - OCHA/COD's own official admin-3 product, shown alongside Ward (GRID3) for cross-reference. Blank for North-West/North-Central points, where OCHA/COD publishes no ward product at all."),
    ("Status / Sequence", "For Non-IDP rows: Primary/Reserve plus the household's rank (#1, #2, ... within that cluster's primary or reserve list). For IDP primary rows: always 'Primary' (the row represents the whole cluster). For Tier 2 rows: always 'Tier 2 backup'."),
    ("Building ID / Confidence", "Non-IDP only - the source Google Open Buildings footprint ID and its detection-confidence score (0-1) backing that household point."),
    ("IDP Category", "In-camp or In-host - which of the two IDP field methods applies (Section 3 of the methodology doc). In-host sites have no Site Radius or Tier 2 backup point."),
    ("Site Radius (m)", "In-camp only, and only for a subset of sites where a real camp extent was delineated or a fixed-radius fallback applied - NA where the concept doesn't apply (most in-camp sites use 'visible camp extent' with no fixed radius; host-community listing is never radius-bound)."),
    ("Target HHs (primary) / Reserve HHs", "IDP cluster rows only - the total number of primary interviews and reserve (backup) households planned for that specific cluster."),
    ("Achieved / Date Collected / Collection Status", "Live, computed fresh from submitted data each time this workbook is refreshed (see 'When was this last refreshed' above). For Non-IDP rows: Achieved is Yes/No for that SPECIFIC point (a pre-assigned building either has or hasn't been visited) and Date Collected is when. For IDP rows: Achieved is a count (e.g. '8 of 12') since IDP interviews aren't tied to individual pre-assigned points (see 'IDP cluster (Tier 1 primary)' above) - Date Collected is the most recent interview date at that cluster. Collection Status is Not started / Partial / Complete / Inaccessible - the 'Needs Collecting' sheet excludes both Complete AND Inaccessible. 'Inaccessible' means this specific point/cluster is currently in a ward flagged as not safely reachable - do NOT go there even if it also shows 'Not started'/Achieved 'No'; this is not the same as being done, it means it's off your active list until conditions change. Achieved credit already earned there before it became inaccessible is never removed."),
]

CLUSTER_SUMMARY_FIELD_NOTES = [
    ("Collected", "Every real interview matched to this cluster so far, uncapped - includes any surplus beyond target (see 'Still Needed' - if this is 0 while Collected keeps growing, that cluster is oversampled; further visits there don't help your remaining total)."),
    ("Achieved", "Every real interview here that counts toward the assessment - completed, matched to this cluster, not a duplicate and not confirmed for deletion. Uncapped: where a cluster was over-collected, all of those interviews are counted, so this can exceed the cluster's own target. Matches the monitoring dashboard's own definition. Kept in full even for a cluster now marked Inaccessible - real completed work isn't erased by the area becoming unreachable afterward."),
    ("Still Needed", "Target minus Achieved, floored at 0 - EXCEPT for a cluster marked Inaccessible, where this is always 0 regardless of the gap: you are not being asked to go back there right now, however far from target it is."),
    ("Collection Status = Inaccessible", "This cluster's ward is currently flagged as not safely reachable. It's excluded from the 'Needs Collecting' sheet, but its Achieved/Collected figures still count in full. Note: the README headline's 'Total target' is now the frozen, stratum-level target_sample figure (2026-09-16) - it does not vary with any individual cluster's accessibility, so an Inaccessible cluster here does not change the headline Target the way it used to; only Achieved/Still-needed at that headline level move."),
]

LGA_WARD_SOURCE_NOTE = (
    "LGA (State/LGA columns) is sourced from OCHA/COD, the officially-endorsed boundary dataset, and is "
    "authoritative throughout this assessment. Ward detail is sourced from GRID3 - the only admin-3 product with "
    "national coverage, used to supplement ward-level detail (for North-East clusters, OCHA/COD's own official "
    "ward product is also shown separately - see 'Ward (OCHA/COD)' column). GRID3's ward polygons carry their own "
    "embedded LGA label, and at a number of LGA borders that embedded label disagrees with the official OCHA/COD "
    "line - by as little as a few tens of metres. If you look up a point's ward within the GRID3 dataset yourself "
    "and find its implied LGA differs from the LGA column shown here, this is that same known discrepancy, not an "
    "error - OCHA/COD remains the LGA of record. If your team identifies more strongly with a different LGA in the "
    "field, please flag it to your FACT Foundation/IMPACT Initiatives focal point with the specific point(s); we "
    "track these case by case."
)

# 2026-09-16 (Decision C, coordination methodology review): documentation-only
# addition - shared-LGA attribution itself is unchanged, deliberately not
# redesigned. Some LGAs are assigned to more than one partner at once
# (Partnerscoverage.xlsx can mark >1 partner column for the same LGA row);
# this workbook does not split a shared LGA's points/clusters between its
# partners in any way - every partner covering that LGA sees the LGA's full
# point set and full target/achieved figures in their own package, not a
# geographic or household-level subset. Never changed unilaterally here - a
# partner-level split would need a real field-assignment decision (who
# physically covers which specific points) that this project doesn't
# currently make; this note exists so a partner comparing notes with a
# co-covering partner in a shared LGA isn't surprised to see the same
# figures in both packages.
TWO_TARGET_FIGURES_NOTE = (
    "This workbook shows target figures at two different levels, on purpose - they answer different questions and "
    "are not meant to match each other. The headline 'Total target' above (and the Target Sample Summary table "
    "below) is target_sample: a fixed number set at survey design time for your whole stratum (LGA x population "
    "group), the same number the dashboard and every other report use - this is what to compare against another "
    "report. The 'Target HHs (primary)' column on the Cluster Summary sheet is a different, live figure: exactly "
    "how many accessible households remain assigned at that ONE specific cluster right now, which shrinks if that "
    "cluster's area loses accessibility. Use the headline figure to check your overall progress against what's "
    "reported elsewhere; use the Cluster Summary column to see real, current, point-level fieldwork remaining."
)

SHARED_LGA_ATTRIBUTION_NOTE = (
    "A small number of LGAs in this assessment are assigned to more than one partner at once. Where that happens, "
    "this workbook does NOT split that LGA's points or target/achieved figures between the covering partners - "
    "every partner assigned to a shared LGA sees that LGA's FULL point set and FULL target/achieved numbers in "
    "their own package, the same as every other partner covering it. This is a deliberate simplification, not an "
    "error: this assessment does not currently divide a shared LGA's actual field assignment between partners at "
    "the point level, so this workbook doesn't either. If you're covering a shared LGA, coordinate directly with "
    "your IMPACT focal point and any co-covering partner on which specific points your team will physically visit, "
    "so the same points aren't double-collected."
)


def build_partner_summary_table(meta_rows, partner_name):
    # 2026-09-16 (Decision A): "Non-IDP target sample" / "IDP target sample" /
    # "Total target sample" below are a rollup HEADLINE figure (one number
    # per LGA/pop_type), same class of thing as the README's own top
    # headline - so, per Decision A, these three columns now come from
    # target_sample (frozen design figure), NOT a count/sum of meta_rows.
    # "Non-IDP reserve" / "IDP clusters" / "IDP reserve" stay meta_rows-
    # derived - real operational counts (how many reserve slots exist, how
    # many physical IDP cluster sites), never a competing "target" claim,
    # so Decision A doesn't touch them.
    target_sample_by_lga_poptype = {}
    for sid in partner_covered_strata_ids(partner_name):
        target_sample_by_lga_poptype[(strata_lga_key[sid][0], strata_lga_key[sid][1], strata_pop_type[sid])] = strata_target_sample[sid]

    agg = defaultdict(lambda: {"non_idp_reserve": 0, "idp_clusters": 0, "idp_reserve": 0})
    for row in meta_rows:
        key = (row["State"], row["LGA"])
        a = agg[key]
        pt = row["Point Type"]
        if pt == "Non-IDP household (reserve)":
            a["non_idp_reserve"] += 1
        elif pt == "IDP cluster (Tier 1 primary)":
            a["idp_clusters"] += 1
            a["idp_reserve"] += int(row.get("Reserve HHs") or 0)
    # Also seed a row for any (State, LGA) covered by a target_sample stratum
    # but with zero meta_rows currently (e.g. a stratum with real target but
    # no achieved/collected activity yet still deserves a summary row).
    for (state, lga, pop_type) in target_sample_by_lga_poptype:
        agg[(state, lga)]  # noqa: B018 - defaultdict touch, ensures the key exists
    out = []
    for (state, lga), a in sorted(agg.items()):
        non_idp_target = target_sample_by_lga_poptype.get((state, lga, "non_idp"), 0)
        idp_target = target_sample_by_lga_poptype.get((state, lga, "idp"), 0)
        out.append({
            "State": state, "LGA": lga,
            "Non-IDP target sample": non_idp_target, "Non-IDP reserve": a["non_idp_reserve"],
            "IDP clusters": a["idp_clusters"], "IDP target sample": idp_target, "IDP reserve": a["idp_reserve"],
            "Total target sample": non_idp_target + idp_target,
        })
    return out


def write_partner_workbook(partner_dir_path, partner_name, meta_rows, cluster_rows=None,
                            meta_rows_msna_light=None, cluster_rows_msna_light=None):
    meta_rows_msna_light = meta_rows_msna_light or []
    cluster_rows_msna_light = cluster_rows_msna_light or []
    if not meta_rows and not meta_rows_msna_light:
        return
    cluster_rows = cluster_rows or []
    from openpyxl.worksheet.table import Table, TableStyleInfo

    wb_out = openpyxl.Workbook()

    # ---- Sheet 1: README (definitions + per-state/LGA summary) ----
    ws_readme = wb_out.active
    ws_readme.title = "README"
    ws_readme.column_dimensions["A"].width = 30
    ws_readme.column_dimensions["B"].width = 95
    r = 1
    ws_readme.cell(row=r, column=1, value=f"{partner_name} - NGA MSNA 2026 sampling points summary").font = openpyxl.styles.Font(bold=True, size=14, color="1B2A4A")
    r += 1
    ws_readme.cell(row=r, column=1, value=f"Last refreshed: {datetime.datetime.now().strftime('%d %b %Y %H:%M')} - regenerated regularly against your team's actual submitted interviews. If this looks out of date, ask your IMPACT focal point for a fresh copy.").font = openpyxl.styles.Font(italic=True, color="808080")
    r += 2
    ws_readme.cell(row=r, column=1, value="Every GPS sampling point assigned to this partner, across all covered LGAs, with live achieved status. 'Sampling Points' = every point, done or not. 'Needs Collecting' = just what's still outstanding - start there if you want a straight to-do list. 'Cluster Summary' = one row per cluster (target/achieved/still needed) - start there if you want the big picture before the point-by-point detail. This sheet gives definitions and a per-LGA target-sample summary.").font = openpyxl.styles.Font(italic=True)
    r += 2

    # ---- headline block (2026-09-05, REVISED 2026-09-16 per Decision A):
    # this partner's own target/achieved/remaining at a glance, before the
    # detailed per-LGA table below.
    #
    # 2026-09-16 change: "Total target"/"Still needed" now use target_sample
    # (the frozen, stratum-level design figure) rather than a live sum of
    # per-cluster "Target HHs (primary)" - this is the canonical Target
    # figure everywhere now (dashboard, this workbook, and wherever else
    # reports it), so a partner comparing this workbook against the
    # dashboard sees the same number, not two different "targets" computed
    # two different ways. target_sample_representativity is shown as a
    # separate REFERENCE line right below it, not as a replacement - it's
    # useful context (a live, accessibility-adjusted view of the same
    # stratum) but is not itself the headline Target. "Achieved so far"
    # is unchanged - real completed interviews still count in full even if
    # the area has since become inaccessible (417+ real interviews
    # nationally would otherwise silently lose credit - see the header note
    # above frame_rows_full). "Still needed" = Target minus Achieved at this
    # SAME stratum-level basis (floored at 0), so Target - Achieved =
    # Still needed holds exactly within this headline block, the whole
    # point of Decision A (previously Target and Still Needed were both
    # live/cluster-based and self-consistent, but disagreed with the
    # dashboard's own frozen target_sample figure for the same stratum).
    active_rows = [x for x in cluster_rows if x["Collection Status"] != "Inaccessible"]
    inaccessible_rows = [x for x in cluster_rows if x["Collection Status"] == "Inaccessible"]
    partner_strata_ids = partner_covered_strata_ids(partner_name)
    total_target = round(sum(strata_target_sample[sid] for sid in partner_strata_ids))
    total_achieved = sum(x["Achieved"] for x in cluster_rows)
    total_remaining = max(0, total_target - total_achieved)
    _strata_with_repr = [sid for sid in partner_strata_ids if sid in strata_target_repr]
    total_target_repr = round(sum(strata_target_repr[sid] for sid in _strata_with_repr)) if _strata_with_repr else None
    _n_strata_missing_repr = len(partner_strata_ids) - len(_strata_with_repr)
    achieved_in_inaccessible = sum(x["Achieved"] for x in inaccessible_rows)
    n_clusters_complete = sum(1 for x in cluster_rows if x["Collection Status"] == "Complete")
    n_clusters_not_started = sum(1 for x in active_rows if x["Collection Status"] == "Not started")
    pct_complete = (total_achieved / total_target) if total_target else 0
    ws_readme.cell(row=r, column=1, value="Where things stand right now").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    headline_start = r
    headline = [
        ("Total target", total_target),
        ("Reference: target adjusted for current accessibility (not the headline Target - see note below)",
         total_target_repr if total_target_repr is not None else "n/a"),
        ("Achieved so far (all real interviews, including any since become inaccessible)", total_achieved),
        ("Still needed (Total target minus Achieved so far)", total_remaining),
        ("% of target achieved", f"{pct_complete:.0%}"),
        ("Clusters fully complete", f"{n_clusters_complete} of {len(cluster_rows)}"),
        ("Clusters not yet started (currently accessible)", n_clusters_not_started),
        ("Clusters currently inaccessible", len(inaccessible_rows)),
        ("...of which, real interviews already achieved there (counted in Achieved above, not asking for more)", achieved_in_inaccessible),
    ]
    if _n_strata_missing_repr:
        headline.append((f"({_n_strata_missing_repr} of your {len(partner_strata_ids)} strata have no representativity figure yet - reference line above is partial)", ""))
    for label, val in headline:
        ws_readme.cell(row=r, column=1, value=label).font = openpyxl.styles.Font(bold=True)
        cell = ws_readme.cell(row=r, column=2, value=val)
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="D9E2F3")
        r += 1
    r += 1

    ws_readme.cell(row=r, column=1, value="A note on the two different 'target' figures in this workbook").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    ws_readme.cell(row=r, column=1, value=TWO_TARGET_FIGURES_NOTE).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
    ws_readme.merge_cells(start_row=r, start_column=1, end_row=r, end_column=2)
    ws_readme.row_dimensions[r].height = 115
    r += 2

    ws_readme.cell(row=r, column=1, value="Point Type definitions").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for term, definition in README_DEFINITIONS:
        ws_readme.cell(row=r, column=1, value=term).font = openpyxl.styles.Font(bold=True)
        ws_readme.cell(row=r, column=2, value=definition).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        r += 1
    r += 1

    ws_readme.cell(row=r, column=1, value="A note on LGA vs Ward data sources").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    ws_readme.cell(row=r, column=1, value=LGA_WARD_SOURCE_NOTE).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
    ws_readme.merge_cells(start_row=r, start_column=1, end_row=r, end_column=2)
    ws_readme.row_dimensions[r].height = 130
    r += 2

    ws_readme.cell(row=r, column=1, value="A note on LGAs covered by more than one partner").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    ws_readme.cell(row=r, column=1, value=SHARED_LGA_ATTRIBUTION_NOTE).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
    ws_readme.merge_cells(start_row=r, start_column=1, end_row=r, end_column=2)
    ws_readme.row_dimensions[r].height = 100
    r += 2

    ws_readme.cell(row=r, column=1, value="Other column notes (Sampling Points / Needs Collecting sheets)").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for term, definition in README_FIELD_NOTES:
        ws_readme.cell(row=r, column=1, value=term).font = openpyxl.styles.Font(bold=True)
        ws_readme.cell(row=r, column=2, value=definition).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        r += 1
    r += 1

    ws_readme.cell(row=r, column=1, value="Column notes (Cluster Summary sheet)").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for term, definition in CLUSTER_SUMMARY_FIELD_NOTES:
        ws_readme.cell(row=r, column=1, value=term).font = openpyxl.styles.Font(bold=True)
        ws_readme.cell(row=r, column=2, value=definition).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        r += 1
    r += 2

    ws_readme.cell(row=r, column=1, value="Targeted sample per State / LGA").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    summary_start_row = r
    summary_headers = ["State", "LGA", "Non-IDP target sample", "Non-IDP reserve", "IDP clusters", "IDP target sample", "IDP reserve", "Total target sample"]
    for c, h in enumerate(summary_headers, start=1):
        cell = ws_readme.cell(row=r, column=c, value=h)
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="2C5F8A")
    r += 1
    summary_rows = build_partner_summary_table(meta_rows, partner_name)
    for row in summary_rows:
        for c, h in enumerate(summary_headers, start=1):
            ws_readme.cell(row=r, column=c, value=row[h])
        r += 1
    total_row = r
    ws_readme.cell(row=total_row, column=1, value="TOTAL").font = openpyxl.styles.Font(bold=True)
    for c, h in enumerate(summary_headers[2:], start=3):
        val = sum(row[h] for row in summary_rows)
        cell = ws_readme.cell(row=total_row, column=c, value=val)
        cell.font = openpyxl.styles.Font(bold=True)
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="FFF2CC")
    if summary_rows:
        tbl = Table(displayName="TargetSampleSummary", ref=f"A{summary_start_row}:H{total_row}")
        tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws_readme.add_table(tbl)
    for i in range(3, 9):
        ws_readme.column_dimensions[openpyxl.utils.get_column_letter(i)].width = 15

    # ---- Sheet 2: full Sampling Points table ----
    ws = wb_out.create_sheet("Sampling Points")
    ws.append(METADATA_COLUMNS)
    for cell in ws[1]:
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="1B2A4A")
    for row in meta_rows:
        ws.append([row.get(c, "") for c in METADATA_COLUMNS])
    ws.freeze_panes = "A2"
    for i, col in enumerate(METADATA_COLUMNS, start=1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(12, min(28, len(col) + 4))
    tbl = Table(displayName="SamplingPoints", ref=f"A1:{openpyxl.utils.get_column_letter(len(METADATA_COLUMNS))}{len(meta_rows)+1}")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)

    # ---- Sheet 3 (2026-09-05): Needs Collecting - Sampling Points filtered
    # to what isn't done yet. Same columns/order as Sheet 2, just a subset -
    # for a partner who only wants "what do I still need to go do," without
    # scrolling past everything already achieved. IDP primary rows appear
    # here as long as their cluster isn't fully done (Achieved column still
    # shows the "X of Y" count so it's clear how much of that cluster
    # remains). Excludes "Inaccessible" as well as "Complete" (2026-09-05) -
    # a currently-inaccessible point is not something to ask a partner to go
    # collect, same reasoning as WORKING/KML no longer including it.
    #
    # 2026-09-08 fix, per Jack: Non-IDP reserve households and IDP Tier 2
    # backup points are EXCLUDED here (previously both were included
    # whenever not Complete/Inaccessible - Tier 2 in particular has no
    # Collection Status at all, so it was unconditionally always included).
    # This sheet is explicitly framed elsewhere in this workbook as "a
    # straight to-do list" - reserves and Tier 2 points are conditional,
    # only-if-the-primary-fails backups, not independent targets, and rank
    # order (Sequence) can't be represented in a flat list anyway. Including
    # them here risked reading as "collect these too," i.e. exhaustive
    # sampling of primary + reserve together - exactly what the reserve
    # design (strict rank-order replacement only) is not. Both remain fully
    # visible, with all their own detail, in the "Sampling Points" sheet.
    NEEDS_COLLECTING_EXCLUDED_TYPES = {"Non-IDP household (reserve)", "IDP Tier 2 backup point"}
    needs_rows = [
        row for row in meta_rows
        if row.get("Collection Status", "") not in ("Complete", "Inaccessible")
        and row.get("Point Type") not in NEEDS_COLLECTING_EXCLUDED_TYPES
    ]
    ws_needs = wb_out.create_sheet("Needs Collecting")
    ws_needs.append(METADATA_COLUMNS)
    for cell in ws_needs[1]:
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="A5281B")
    for row in needs_rows:
        ws_needs.append([row.get(c, "") for c in METADATA_COLUMNS])
    ws_needs.freeze_panes = "A2"
    for i, col in enumerate(METADATA_COLUMNS, start=1):
        ws_needs.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(12, min(28, len(col) + 4))
    if needs_rows:
        tbl_needs = Table(displayName="NeedsCollecting", ref=f"A1:{openpyxl.utils.get_column_letter(len(METADATA_COLUMNS))}{len(needs_rows)+1}")
        tbl_needs.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws_needs.add_table(tbl_needs)

    # ---- Sheet 4 (2026-09-05): Cluster Summary - one row per cluster
    # (Non-IDP + IDP together), target/collected/achieved/still-needed - the
    # "am I basically done with this LGA" view. Conditional formatting on
    # Collection Status so it reads at a glance without opening every row. --
    ws_cs = wb_out.create_sheet("Cluster Summary")
    ws_cs.append(CLUSTER_SUMMARY_COLUMNS)
    for cell in ws_cs[1]:
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="1B2A4A")
    for row in cluster_rows:
        ws_cs.append([row.get(c, "") for c in CLUSTER_SUMMARY_COLUMNS])
    ws_cs.freeze_panes = "A2"
    for i, col in enumerate(CLUSTER_SUMMARY_COLUMNS, start=1):
        ws_cs.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(12, min(28, len(col) + 4))
    pct_col_idx = CLUSTER_SUMMARY_COLUMNS.index("% Achieved") + 1
    for row_i in range(2, len(cluster_rows) + 2):
        ws_cs.cell(row=row_i, column=pct_col_idx).number_format = "0%"
    if cluster_rows:
        tbl_cs = Table(displayName="ClusterSummary", ref=f"A1:{openpyxl.utils.get_column_letter(len(CLUSTER_SUMMARY_COLUMNS))}{len(cluster_rows)+1}")
        tbl_cs.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws_cs.add_table(tbl_cs)
        status_col_letter = openpyxl.utils.get_column_letter(CLUSTER_SUMMARY_COLUMNS.index("Collection Status") + 1)
        status_range = f"{status_col_letter}2:{status_col_letter}{len(cluster_rows)+1}"
        from openpyxl.formatting.rule import CellIsRule
        ws_cs.conditional_formatting.add(status_range, CellIsRule(operator="equal", formula=['"Complete"'], fill=openpyxl.styles.PatternFill("solid", fgColor="C6E0B4")))
        ws_cs.conditional_formatting.add(status_range, CellIsRule(operator="equal", formula=['"Partial"'], fill=openpyxl.styles.PatternFill("solid", fgColor="FFE699")))
        ws_cs.conditional_formatting.add(status_range, CellIsRule(operator="equal", formula=['"Not started"'], fill=openpyxl.styles.PatternFill("solid", fgColor="F8CBAD")))
        ws_cs.conditional_formatting.add(status_range, CellIsRule(operator="equal", formula=['"Inaccessible"'], fill=openpyxl.styles.PatternFill("solid", fgColor="D9D9D9")))

    # ---- Sheet 5 (2026-09-13): MSNA Light - a completely separate,
    # distinctly-coloured sheet for the government-negotiated, unverified
    # LGAs (Abadam/Nganzai/Guzamala as of this writing). Deliberately NOT
    # blended into the README headline, Target Sample Summary table, or any
    # of Sheets 2-4 above - those must keep reflecting only this partner's
    # normal "MSNA Full Design" workload, per Jack's explicit requirement
    # (2026-09-11) that this data must never be mixed in. Only rendered when
    # this partner actually has MSNA Light rows (checking here, not at the
    # call site, keeps this self-contained).
    if meta_rows_msna_light or cluster_rows_msna_light:
        ws_light = wb_out.create_sheet("MSNA Light")
        ws_light.column_dimensions["A"].width = 30
        ws_light.column_dimensions["B"].width = 95
        rl = 1
        ws_light.cell(row=rl, column=1, value=f"{partner_name} - MSNA Light (government-negotiated, unverified)").font = openpyxl.styles.Font(bold=True, size=14, color="A5281B")
        rl += 1
        ws_light.cell(
            row=rl, column=1,
            value=("These points are NOT part of your normal MSNA Full Design workload above - a separate, one-off "
                   "arrangement negotiated directly with the government for specific LGAs where full access was not "
                   "otherwise possible. Government enumerators only, no GPS-proximity verification of compliance is "
                   "possible for these points. This data will NEVER be counted in state/regional/national aggregation "
                   "or compared against any other LGA - it is reported as disclosed, LGA-level findings only. Kept "
                   "entirely separate from every figure above (Target Sample Summary, Sampling Points, Needs "
                   "Collecting, Cluster Summary) - those reflect your normal workload only.")
        ).alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        ws_light.merge_cells(start_row=rl, start_column=1, end_row=rl, end_column=2)
        ws_light.row_dimensions[rl].height = 90
        rl += 2

        light_target = sum(x["Target HHs (primary)"] for x in cluster_rows_msna_light)
        light_achieved = sum(x["Achieved"] for x in cluster_rows_msna_light)
        light_headline = [
            ("LGAs", ", ".join(sorted({x["LGA"] for x in cluster_rows_msna_light}))),
            ("Total clusters", len(cluster_rows_msna_light)),
            ("Total target (MSNA Light only)", light_target),
            ("Achieved so far (MSNA Light only)", light_achieved),
        ]
        for label, val in light_headline:
            ws_light.cell(row=rl, column=1, value=label).font = openpyxl.styles.Font(bold=True)
            cell = ws_light.cell(row=rl, column=2, value=val)
            cell.fill = openpyxl.styles.PatternFill("solid", fgColor="FBE5D6")
            rl += 1
        rl += 1

        ws_light.cell(row=rl, column=1, value="MSNA Light sampling points").font = openpyxl.styles.Font(bold=True, size=12)
        rl += 1
        pts_header_row = rl
        for c, h in enumerate(METADATA_COLUMNS, start=1):
            cell = ws_light.cell(row=rl, column=c, value=h)
            cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
            cell.fill = openpyxl.styles.PatternFill("solid", fgColor="A5281B")
        rl += 1
        for row in meta_rows_msna_light:
            for c, h in enumerate(METADATA_COLUMNS, start=1):
                ws_light.cell(row=rl, column=c, value=row.get(h, ""))
            rl += 1
        if meta_rows_msna_light:
            tbl_light = Table(displayName="MSNALightPoints", ref=f"A{pts_header_row}:{openpyxl.utils.get_column_letter(len(METADATA_COLUMNS))}{rl-1}")
            tbl_light.tableStyleInfo = TableStyleInfo(name="TableStyleMedium3", showRowStripes=True)
            ws_light.add_table(tbl_light)
        for i, col in enumerate(METADATA_COLUMNS, start=1):
            ws_light.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(12, min(28, len(col) + 4))

    os.makedirs(partner_dir_path, exist_ok=True)
    wb_out.save(os.path.join(partner_dir_path, f"{safe_folder_name(partner_name)}_sampling_points_summary.xlsx"))


# ---------------------------------------------------------------------------
# 7. Build per-partner/state/lga packages
# ---------------------------------------------------------------------------
stats = Counter()
partner_folders = set()
partner_meta_rows = defaultdict(list)
partner_cluster_rows = defaultdict(list)
# 2026-09-13: separate MSNA Light tracking - never merged into the dicts
# above. All 3 MSNA Light LGAs (Abadam/Nganzai/Guzamala) are Non-IDP only
# (checked directly - no idp_ MSNA Light strata exist), so this only needs
# the Non-IDP path, not IDP's.
partner_meta_rows_msna_light = defaultdict(list)
partner_cluster_rows_msna_light = defaultdict(list)

for pcode, partners in partners_by_pcode.items():
    rows = rows_by_pcode.get(pcode)
    rows_full = rows_by_pcode_full.get(pcode) or []
    rows_msna_light = rows_by_pcode_msna_light.get(pcode) or []
    rows_full_msna_light = rows_by_pcode_full_msna_light.get(pcode) or []
    if not rows and not rows_full and not rows_msna_light and not rows_full_msna_light:
        continue
    v = master_lgas[pcode]
    state_name, lga_name = v["adm1_name"], v["adm2_name"]

    rows = rows or []
    non_idp_primary_rows = [r for r in rows if r["pop_type"] == "non_idp" and r["status"] == "primary"]
    non_idp_reserve_rows = [r for r in rows if r["pop_type"] == "non_idp" and r["status"] == "reserve"]
    non_idp_primary = [non_idp_placemark(r) for r in non_idp_primary_rows]
    non_idp_reserve = [non_idp_placemark(r) for r in non_idp_reserve_rows]

    idp_rows_by_cluster = {}
    for r in rows:
        if r["pop_type"] == "idp":
            idp_rows_by_cluster.setdefault(r["cluster_id"], r)  # first row = same coords for all statuses
    # 2026-09-19 fix: IDP achieved-tracking is count-based (cluster_achieved_n),
    # never tied to one specific survey_id - so a cluster whose primary rows
    # are ALL already achieved (and therefore already dropped from WORKING)
    # can still have a RESERVE row survive here untouched, since reserve
    # slots aren't individually consumed the same way. That surviving row
    # used to still produce a KML placemark/Tier 2 backup point, telling a
    # field team to go collect a cluster that's already 100% done. Found via
    # the standing UUID-reconciliation check below (idp_NG002001_1: 6/6
    # primary achieved and gone from WORKING, 6 reserve rows still present).
    # Drop any cluster whose real achieved count already meets its nominal
    # target - matches idp_primary_metadata_row's own Complete-status logic
    # below exactly, just applied here so KML/Tier2 agree with it too.
    idp_rows_by_cluster = {
        cid: r for cid, r in idp_rows_by_cluster.items()
        if not (
            r["target_households"] not in (None, "", "NA")
            and cluster_achieved_n.get(cid, 0) >= int(r["target_households"])
        )
    }
    idp_primary = []
    idp_tier2_backup = []
    for cluster_id, r in idp_rows_by_cluster.items():
        idp_primary.append(idp_primary_placemark(cluster_id, r))
        backup_row = backup_by_cluster.get(cluster_id)
        if backup_row is not None:
            idp_tier2_backup.append(idp_tier2_backup_placemark(cluster_id, r, backup_row))

    # ---- FULL-sourced equivalents (2026-09-05) - feed the workbook's
    # Sampling Points/Needs Collecting/Cluster Summary sheets only, NOT the
    # KML files above (which stay WORKING-sourced, correctly outstanding-
    # only). Same LGA, so every row here shares the same state/LGA/ward as
    # the WORKING-sourced rows above - only which individual points/clusters
    # are included differs (FULL keeps already-achieved ones too). ----------
    non_idp_primary_rows_full = [r for r in rows_full if r["pop_type"] == "non_idp" and r["status"] == "primary"]
    non_idp_reserve_rows_full = [r for r in rows_full if r["pop_type"] == "non_idp" and r["status"] == "reserve"]
    idp_rows_by_cluster_full = {}
    for r in rows_full:
        if r["pop_type"] == "idp":
            idp_rows_by_cluster_full.setdefault(r["cluster_id"], r)

    # ---- MSNA Light equivalents (2026-09-13) - same construction as the
    # normal Non-IDP path above, kept completely separate. Non-IDP only,
    # see the note above partner_meta_rows_msna_light. ----------------------
    non_idp_primary_rows_msna_light = [r for r in rows_msna_light if r["pop_type"] == "non_idp" and r["status"] == "primary"]
    non_idp_reserve_rows_msna_light = [r for r in rows_msna_light if r["pop_type"] == "non_idp" and r["status"] == "reserve"]
    non_idp_primary_msna_light = [non_idp_placemark(r) for r in non_idp_primary_rows_msna_light]
    non_idp_reserve_msna_light = [non_idp_placemark(r) for r in non_idp_reserve_rows_msna_light]
    non_idp_primary_rows_full_msna_light = [r for r in rows_full_msna_light if r["pop_type"] == "non_idp" and r["status"] == "primary"]
    non_idp_reserve_rows_full_msna_light = [r for r in rows_full_msna_light if r["pop_type"] == "non_idp" and r["status"] == "reserve"]

    for partner in partners:
        partner_dir = safe_folder_name(partner)
        partner_root = os.path.join(OUT_ROOT, partner_dir)
        lga_dir = os.path.join(partner_root, safe_folder_name(state_name), safe_folder_name(lga_name))
        partner_folders.add(partner_dir)

        # LGA folder split by population group since 2026-08-13 - each
        # gets its own KML/ subfolder (Cluster_guide/ is populated
        # separately, by build_cluster_factsheets.py's
        # distribute_to_partner_folders()). The LGA summary map PNG below
        # stays at the plain lga_dir level - it isn't population-specific.
        non_idp_kml_dir = os.path.join(lga_dir, "Non_IDP", "KML")
        idp_kml_dir = os.path.join(lga_dir, "IDP", "KML")

        wrote_a = write_kml(os.path.join(non_idp_kml_dir, "non_idp_households_primary.kml"), "Non-IDP households (primary)", non_idp_primary, icon_href=ICON_NON_IDP_PRIMARY)
        wrote_b = write_kml(os.path.join(non_idp_kml_dir, "non_idp_households_reserve.kml"), "Non-IDP households (reserve)", non_idp_reserve, icon_href=ICON_NON_IDP_RESERVE)
        wrote_c = write_kml(os.path.join(idp_kml_dir, "idp_clusters_primary.kml"), "IDP clusters (Tier 1 primary)", idp_primary, icon_href=ICON_IDP_PRIMARY)
        wrote_d = write_kml(os.path.join(idp_kml_dir, "idp_clusters_tier2_backup.kml"), "IDP clusters (Tier 2 backup points)", idp_tier2_backup, icon_href=ICON_IDP_TIER2_BACKUP)

        # 2026-09-13: MSNA Light points go in a physically separate top-level
        # folder (MSNA_Light/KML/, a sibling of Non_IDP/ and IDP/, not nested
        # inside either) - never merged into FACT's normal Non_IDP/KML/ folder.
        # This is for the government-negotiated arrangement specifically, so
        # it stays visibly distinct in the delivered folder structure, not
        # just in the workbook.
        msna_light_kml_dir = os.path.join(lga_dir, "MSNA_Light", "KML")
        wrote_e = write_kml(os.path.join(msna_light_kml_dir, "msna_light_households_primary.kml"), "MSNA Light households (primary) - government-negotiated, unverified", non_idp_primary_msna_light, icon_href=ICON_NON_IDP_PRIMARY)
        wrote_f = write_kml(os.path.join(msna_light_kml_dir, "msna_light_households_reserve.kml"), "MSNA Light households (reserve) - government-negotiated, unverified", non_idp_reserve_msna_light, icon_href=ICON_NON_IDP_RESERVE)
        stats["msna_light_primary_pts"] += len(non_idp_primary_msna_light) if wrote_e else 0
        stats["msna_light_reserve_pts"] += len(non_idp_reserve_msna_light) if wrote_f else 0

        # Cluster_guide/ subfolders created up front (even though the docx
        # files themselves are copied in later by build_cluster_factsheets.py)
        # so the folder skeleton is complete/consistent even for an LGA
        # whose factsheet batch hasn't run yet.
        if wrote_a or wrote_b:
            os.makedirs(os.path.join(lga_dir, "Non_IDP", "Cluster_guide"), exist_ok=True)
        if wrote_c or wrote_d:
            os.makedirs(os.path.join(lga_dir, "IDP", "Cluster_guide"), exist_ok=True)

        if wrote_a or wrote_b or wrote_c or wrote_d or wrote_e or wrote_f:
            stats["lga_folders"] += 1
            map_src = os.path.join(LGA_MAPS_DIR, lga_map_filename(pcode, lga_name))
            if os.path.exists(map_src):
                os.makedirs(lga_dir, exist_ok=True)
                shutil.copy2(map_src, os.path.join(lga_dir, f"{safe_folder_name(lga_name)}_map.png"))
                stats["lga_maps_copied"] += 1
            else:
                stats["lga_maps_missing"] += 1
        stats["non_idp_primary_pts"] += len(non_idp_primary) if wrote_a else 0
        stats["non_idp_reserve_pts"] += len(non_idp_reserve) if wrote_b else 0
        stats["idp_primary_pts"] += len(idp_primary) if wrote_c else 0
        stats["idp_tier2_pts"] += len(idp_tier2_backup) if wrote_d else 0

        # Workbook meta rows are FULL-sourced (2026-09-05) - independent of
        # the wrote_a/b/c/d KML flags above, since an already-achieved point
        # can have an empty KML (correctly) while still needing to appear in
        # the workbook with its real status. Gated on FULL having any rows
        # for this LGA at all, not on WORKING/KML output.
        meta = partner_meta_rows[(partner_dir, partner)]
        if non_idp_primary_rows_full:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_primary_rows_full)
        if non_idp_reserve_rows_full:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_reserve_rows_full)
        if idp_rows_by_cluster_full:
            meta.extend(idp_primary_metadata_row(partner, state_name, lga_name, cid, r) for cid, r in idp_rows_by_cluster_full.items())
        if wrote_d:
            meta.extend(
                idp_tier2_metadata_row(partner, state_name, lga_name, cid, r, backup_by_cluster[cid])
                for cid, r in idp_rows_by_cluster.items() if cid in backup_by_cluster
            )

        # Cluster Summary rows - same FULL-sourced gating as the meta rows
        # above, independent grain (one row per cluster, not per household).
        cluster_rows = partner_cluster_rows[(partner_dir, partner)]
        if non_idp_primary_rows_full or non_idp_reserve_rows_full:
            cluster_rows.extend(non_idp_cluster_summary_rows(state_name, lga_name, non_idp_primary_rows_full, non_idp_reserve_rows_full))
        if idp_rows_by_cluster_full:
            cluster_rows.extend(idp_cluster_summary_row(state_name, lga_name, cid, r) for cid, r in idp_rows_by_cluster_full.items())

        # 2026-09-13: MSNA Light meta/cluster rows - completely separate
        # dicts, same FULL-sourced construction, Non-IDP only (see the note
        # where partner_meta_rows_msna_light is created). These never touch
        # `meta`/`cluster_rows` above, so FACT's normal Target/Achieved/
        # Collected figures are unaffected by them.
        meta_msna_light = partner_meta_rows_msna_light[(partner_dir, partner)]
        if non_idp_primary_rows_full_msna_light:
            meta_msna_light.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_primary_rows_full_msna_light)
        if non_idp_reserve_rows_full_msna_light:
            meta_msna_light.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_reserve_rows_full_msna_light)

        cluster_rows_msna_light = partner_cluster_rows_msna_light[(partner_dir, partner)]
        if non_idp_primary_rows_full_msna_light or non_idp_reserve_rows_full_msna_light:
            cluster_rows_msna_light.extend(non_idp_cluster_summary_rows(state_name, lga_name, non_idp_primary_rows_full_msna_light, non_idp_reserve_rows_full_msna_light))

# ---------------------------------------------------------------------------
# 8. One summary Excel workbook per partner, at the partner's root folder
# ---------------------------------------------------------------------------
failed_workbooks = []
failed_workbook_dirs = set()
# 2026-09-13: union with the MSNA Light keys too, in case a partner ever has
# MSNA Light rows with zero normal rows (doesn't happen for FACT today -
# checked directly - but this loop shouldn't silently skip that partner's
# workbook entirely if it ever does).
all_partner_keys = set(partner_meta_rows.keys()) | set(partner_meta_rows_msna_light.keys())
for partner_dir, partner_name in sorted(all_partner_keys):
    meta_rows = partner_meta_rows.get((partner_dir, partner_name), [])
    meta_rows.sort(key=lambda r: (r["State"], r["LGA"], r["Point Type"], r.get("Cluster ID", ""), r.get("Survey ID", "")))
    cluster_rows = partner_cluster_rows.get((partner_dir, partner_name), [])
    cluster_rows.sort(key=lambda r: (r["State"], r["LGA"], r["Population Type"], r["Cluster ID"]))
    meta_rows_msna_light = partner_meta_rows_msna_light.get((partner_dir, partner_name), [])
    meta_rows_msna_light.sort(key=lambda r: (r["State"], r["LGA"], r["Point Type"], r.get("Cluster ID", ""), r.get("Survey ID", "")))
    cluster_rows_msna_light = partner_cluster_rows_msna_light.get((partner_dir, partner_name), [])
    cluster_rows_msna_light.sort(key=lambda r: (r["State"], r["LGA"], r["Population Type"], r["Cluster ID"]))
    try:
        write_partner_workbook(os.path.join(OUT_ROOT, partner_dir), partner_name, meta_rows, cluster_rows,
                                meta_rows_msna_light=meta_rows_msna_light, cluster_rows_msna_light=cluster_rows_msna_light)
    except PermissionError:
        # File open/locked (e.g. in Excel) at run time - don't let one locked
        # partner file block every other partner's workbook from writing.
        failed_workbooks.append(partner_name)
        failed_workbook_dirs.add(partner_dir)
        print(f"WARNING: could not write workbook for {partner_name} - file appears to be open/locked. Skipped.")

if failed_workbooks:
    print(f"\n{len(failed_workbooks)} workbook(s) skipped due to file locks - close the file(s) and rerun to update: {failed_workbooks}")

print(f"\nPartners: {len(partner_folders)}")
print(f"Partner/State/LGA folders written: {stats['lga_folders']}")
print(f"Non-IDP primary points: {stats['non_idp_primary_pts']}")
print(f"Non-IDP reserve points: {stats['non_idp_reserve_pts']}")
print(f"IDP Tier 1 primary points: {stats['idp_primary_pts']}")
print(f"IDP Tier 2 backup points: {stats['idp_tier2_pts']}")
print(f"MSNA Light primary points: {stats['msna_light_primary_pts']}")
print(f"MSNA Light reserve points: {stats['msna_light_reserve_pts']}")
print(f"LGA summary maps copied: {stats['lga_maps_copied']} (missing: {stats['lga_maps_missing']})")
print(f"Per-partner summary workbooks written: {len(partner_meta_rows)}")

# ---------------------------------------------------------------------------
# 9. Standing UUID-reconciliation check (2026-09-19) - permanent, runs as
# part of this build itself (not a separately-remembered script) per Jack's
# explicit instruction, given directly after a real, confirmed bug (the
# overlay-exclusion gap fixed in Section 3d above) let the KML files and this
# workbook's own Sampling Points sheet silently disagree about which points
# are still outstanding for weeks. Re-parses the ACTUAL files just written to
# disk - not the in-memory objects that built them - so this also catches a
# future file-write failure (a locked-file skip, an encoding break, a partial
# write) or any other future drift between the two artifacts, not just a
# repeat of today's specific bug.
#
# Scope, deliberately: Non-IDP survey_id + IDP cluster_id, "Sampling Points"
# sheet vs the matching non_idp_households_{primary,reserve}.kml /
# idp_clusters_primary.kml files, restricted to rows/placemarks BOTH sides
# consider still-outstanding (workbook Collection Status Not started/Partial
# - KML is WORKING-sourced and therefore already only ever outstanding
# points). MSNA Light is deliberately excluded - its own separate, isolated
# KML/sheet pair, never subject to the overlay/threshold logic this check
# exists to verify (must never be touched by ordinary target/achieved logic
# per Jack's repeated instruction, 2026-09-11). IDP Tier 2 backup points are
# also excluded - a secondary, always-present-if-flagged layer with no
# independent achieved/still-needed lifecycle of its own, not part of the
# core "is this still outstanding" identity this check reconciles.
# ---------------------------------------------------------------------------
_PLACEMARK_NAME_RE = re.compile(r"<Placemark\b[^>]*>\s*<name>(.*?)</name>", re.DOTALL)


def _extract_kml_names(path):
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        content = f.read()
    from xml.sax.saxutils import unescape
    return {unescape(n) for n in _PLACEMARK_NAME_RE.findall(content)}


def _extract_workbook_active_ids(xlsx_path):
    """(non_idp_survey_ids, idp_cluster_ids) that the just-written 'Sampling
    Points' sheet currently marks Not started/Partial - i.e. still
    outstanding, the population that should exactly match the corresponding
    KML files."""
    if not os.path.exists(xlsx_path):
        return set(), set()
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    try:
        if "Sampling Points" not in wb.sheetnames:
            return set(), set()
        ws = wb["Sampling Points"]
        rows_iter = ws.iter_rows(values_only=True)
        header = next(rows_iter, None)
        if header is None:
            return set(), set()
        idx = {h: i for i, h in enumerate(header) if h is not None}
        needed = ("Point Type", "Cluster ID", "Survey ID", "Collection Status")
        if not all(h in idx for h in needed):
            return set(), set()
        non_idp_ids, idp_ids = set(), set()
        for row in rows_iter:
            if row[idx["Collection Status"]] not in ("Not started", "Partial"):
                continue
            point_type = row[idx["Point Type"]] or ""
            if point_type.startswith("Non-IDP household"):
                sid = row[idx["Survey ID"]]
                if sid:
                    non_idp_ids.add(sid)
            elif point_type.startswith("IDP cluster"):
                cid = row[idx["Cluster ID"]]
                if cid:
                    idp_ids.add(cid)
        return non_idp_ids, idp_ids
    finally:
        wb.close()


reconciliation_findings = []
_checked_partner_dirs = sorted(partner_folders - failed_workbook_dirs)
for _p_dir in _checked_partner_dirs:
    partner_root = os.path.join(OUT_ROOT, _p_dir)
    xlsx_path = os.path.join(partner_root, f"{_p_dir}_sampling_points_summary.xlsx")
    kml_non_idp_ids, kml_idp_ids = set(), set()
    for dirpath, _dirnames, files in os.walk(partner_root):
        norm_dirpath = dirpath.replace("\\", "/")
        if "/MSNA_Light" in norm_dirpath:
            continue
        # 2026-09-19: skip any in-place _archive/ subfolder (e.g. FACT's own
        # `_archive/2026-09-13_pre_msna_light_sampling_method_fix/`, found
        # while first running this check - a historical backup taken inside
        # the live delivered folder, not something a field team would ever
        # load; a false-positive source, not a real mismatch, if walked).
        if "/_archive" in norm_dirpath:
            continue
        for fn in files:
            if fn in ("non_idp_households_primary.kml", "non_idp_households_reserve.kml"):
                kml_non_idp_ids |= _extract_kml_names(os.path.join(dirpath, fn))
            elif fn == "idp_clusters_primary.kml":
                kml_idp_ids |= _extract_kml_names(os.path.join(dirpath, fn))

    wb_non_idp_ids, wb_idp_ids = _extract_workbook_active_ids(xlsx_path)

    only_in_kml_non_idp = kml_non_idp_ids - wb_non_idp_ids
    only_in_wb_non_idp = wb_non_idp_ids - kml_non_idp_ids
    only_in_kml_idp = kml_idp_ids - wb_idp_ids
    only_in_wb_idp = wb_idp_ids - kml_idp_ids

    if only_in_kml_non_idp or only_in_wb_non_idp or only_in_kml_idp or only_in_wb_idp:
        reconciliation_findings.append({
            "partner_dir": _p_dir,
            "n_kml_only_non_idp": len(only_in_kml_non_idp),
            "n_workbook_only_non_idp": len(only_in_wb_non_idp),
            "n_kml_only_idp": len(only_in_kml_idp),
            "n_workbook_only_idp": len(only_in_wb_idp),
            "kml_only_non_idp_survey_ids": sorted(only_in_kml_non_idp)[:20],
            "workbook_only_non_idp_survey_ids": sorted(only_in_wb_non_idp)[:20],
            "kml_only_idp_cluster_ids": sorted(only_in_kml_idp)[:20],
            "workbook_only_idp_cluster_ids": sorted(only_in_wb_idp)[:20],
        })

RECONCILIATION_REPORT_CSV = PROJECT_DIR + r"\resampling\output\dc_package_uuid_reconciliation_report.csv"
os.makedirs(os.path.dirname(RECONCILIATION_REPORT_CSV), exist_ok=True)
with open(RECONCILIATION_REPORT_CSV, "w", encoding="utf-8-sig", newline="") as f:
    fieldnames = [
        "partner_dir", "n_kml_only_non_idp", "n_workbook_only_non_idp",
        "n_kml_only_idp", "n_workbook_only_idp",
        "kml_only_non_idp_survey_ids", "workbook_only_non_idp_survey_ids",
        "kml_only_idp_cluster_ids", "workbook_only_idp_cluster_ids",
    ]
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for finding in reconciliation_findings:
        row = dict(finding)
        for k in ("kml_only_non_idp_survey_ids", "workbook_only_non_idp_survey_ids",
                   "kml_only_idp_cluster_ids", "workbook_only_idp_cluster_ids"):
            row[k] = "; ".join(row[k])
        w.writerow(row)

print(f"\n{'=' * 70}")
if reconciliation_findings:
    print(f"UUID RECONCILIATION: FAIL - {len(reconciliation_findings)} of {len(_checked_partner_dirs)} partner(s) "
          f"have a KML/workbook mismatch on which points are still outstanding. Full detail: {RECONCILIATION_REPORT_CSV}")
    for finding in reconciliation_findings:
        print(f"  {finding['partner_dir']}: non-IDP kml-only={finding['n_kml_only_non_idp']} "
              f"workbook-only={finding['n_workbook_only_non_idp']}, "
              f"IDP kml-only={finding['n_kml_only_idp']} workbook-only={finding['n_workbook_only_idp']}")
else:
    print(f"UUID RECONCILIATION: PASS - all {len(_checked_partner_dirs)} partner(s) checked, KML and workbook "
          f"Sampling Points agree exactly on which points are still outstanding.")
if failed_workbook_dirs:
    print(f"({len(failed_workbook_dirs)} partner(s) skipped from this check - their workbook write failed above: "
          f"{sorted(failed_workbook_dirs)})")
print(f"{'=' * 70}")

# ---------------------------------------------------------------------------
# 9b. Stale partner/LGA folder detector (2026-09-19) - read-only, reports
# only, never deletes. Found via a real case (Street Child of Nigeria kept a
# full, live Dikwa folder for days after Dikwa was reassigned to FACT in the
# frame's own partners_covering column) that nothing in this script's own
# per-LGA loop would ever catch - a partner/LGA combination that drops out of
# partners_by_pcode is simply never visited again, its existing folder left
# exactly as-is forever. Same "only ever adds, never subtracts" shape as the
# write_kml() stale-file bug fixed earlier tonight, one level up (a whole LGA
# folder, not one KML file) - auto-removing a partner's live folder is a much
# bigger, more consequential action than clearing one stale KML file though,
# so this only reports, it never deletes; a confirmed case (like Dikwa) still
# needs its own deliberate removal.
# Skipped when BUILD_DC_ONLY_PARTNER is set, since partners_by_pcode is then
# deliberately narrowed to one partner and every OTHER partner's real,
# current folders would falsely flag as 100% stale.
# ---------------------------------------------------------------------------
if not _only_partner:
    expected_partner_lgas = defaultdict(set)
    for _pcode, _partners in partners_by_pcode.items():
        _v = master_lgas.get(_pcode)
        if not _v:
            continue
        _key = (safe_folder_name(_v["adm1_name"]), safe_folder_name(_v["adm2_name"]))
        for _partner in _partners:
            expected_partner_lgas[safe_folder_name(_partner)].add(_key)

    stale_lga_folders = []
    for _partner_dir in sorted(os.listdir(OUT_ROOT)):
        _partner_path = os.path.join(OUT_ROOT, _partner_dir)
        if not os.path.isdir(_partner_path) or _partner_dir.startswith("_"):
            continue
        _expected = expected_partner_lgas.get(_partner_dir, set())
        for _state_dir in os.listdir(_partner_path):
            _state_path = os.path.join(_partner_path, _state_dir)
            if not os.path.isdir(_state_path) or _state_dir.startswith("_"):
                continue
            for _lga_dir in os.listdir(_state_path):
                _lga_path = os.path.join(_state_path, _lga_dir)
                if not os.path.isdir(_lga_path):
                    continue
                if (_state_dir, _lga_dir) not in _expected:
                    stale_lga_folders.append((_partner_dir, _state_dir, _lga_dir))

    print(f"\n{'=' * 70}")
    if stale_lga_folders:
        print(f"STALE PARTNER/LGA FOLDERS: {len(stale_lga_folders)} folder(s) exist on disk for a partner no "
              f"longer assigned that LGA in Partnerscoverage.xlsx - NOT auto-removed, needs a deliberate look:")
        for _partner_dir, _state_dir, _lga_dir in stale_lga_folders:
            print(f"  {_partner_dir}/{_state_dir}/{_lga_dir}")
    else:
        print("STALE PARTNER/LGA FOLDERS: none found.")
    print(f"{'=' * 70}")

print("\nDONE")
