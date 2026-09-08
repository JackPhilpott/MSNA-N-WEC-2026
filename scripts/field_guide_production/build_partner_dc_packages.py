# ==============================================================================
# Builds per-partner data-collection packages for the 2026-08-05 pilot
# handoff: partner_dc_files/<Partner>/<State>/<LGA>/ folders containing KML
# GPS-point files for field teams to load in Maps.me / Google Maps.
#
# Reads:
#   - input_data/boundaries/partner_coverage/Partnerscoverage.xlsx (which
#     partner(s) cover which LGA - wide format, one column per partner)
#   - output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv
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
import time
from collections import defaultdict, Counter
from xml.sax.saxutils import escape

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
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
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"
STAGE2_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"
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
with open(STAGE2_CSV, encoding="utf-8") as f:
    frame_rows = list(csv.DictReader(f))
print(f"Loaded {len(frame_rows)} household-level rows (WORKING - drives KML placemarks, unchanged).")

rows_by_pcode = defaultdict(list)
for r in frame_rows:
    rows_by_pcode[r["adm2_pcode"]].append(r)

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


with open(STAGE2_FULL_CSV, encoding="utf-8") as f:
    frame_rows_full = [r for r in csv.DictReader(f) if r["coverage_status"] == "covered" and r["exclusion_reason"] == "none"]
print(f"Loaded {len(frame_rows_full)} household-level rows (FULL, covered & not excluded - drives workbook sheets).")

rows_by_pcode_full = defaultdict(list)
for r in frame_rows_full:
    rows_by_pcode_full[r["adm2_pcode"]].append(r)

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
for r in frame_rows_full:
    if r["pop_type"] == "non_idp" and r["status"] == "primary" and _ward_accessible(r):
        cluster_accessible_primary_n[r["cluster_id"]] += 1


def _cluster_below_accessible_threshold(cluster_id):
    return cluster_accessible_primary_n.get(cluster_id, 0) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH


def _row_effectively_inaccessible(r):
    """True if this row's OWN ward is inaccessible, OR (Non-IDP only) its
    whole cluster has fallen below the accessible-household threshold."""
    if not _ward_accessible(r):
        return True
    if r["pop_type"] == "non_idp":
        return _cluster_below_accessible_threshold(r["cluster_id"])
    return False

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

with open(CONFIRMED_DELETIONS_OVERLAY_CSV, encoding="utf-8") as f:
    _confirmed_deleted_uuids = {r["uuid"] for r in csv.DictReader(f) if r["status"] == "confirmed"}
print(f"Confirmed-deletions overlay: {len(_confirmed_deleted_uuids)} confirmed uuid(s) excluded from Achieved.")


def _is_achieved(r):
    return (
        r.get("interview_outcome") == "completed"
        and r.get("is_duplicate") != "TRUE"
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
    n_achieved = min(cluster_achieved_n.get(cluster_id, 0), target) if target else cluster_achieved_n.get(cluster_id, 0)
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
        accessible_primary = [pr for pr in g["primary"] if _ward_accessible(pr)]
        cluster_inaccessible = len(accessible_primary) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH
        target = 0 if cluster_inaccessible else len(accessible_primary)
        nominal_target = len(g["primary"])
        # Achieved is capped at the NOMINAL (full-cluster) target, not the
        # accessible-only one - real credit already earned must never be
        # reduced just because the cap shrank (a fully-inaccessible
        # cluster with historical achieved interviews must still show that
        # credit, not 0 - see the header note above frame_rows_full on why
        # this matters, 417 real interviews nationally).
        achieved = min(n_achieved_exact, nominal_target) if nominal_target else n_achieved_exact
        any_r = g["primary"][0] if g["primary"] else g["reserve"][0]
        still_needed = 0 if cluster_inaccessible else sum(
            1 for pr in accessible_primary if achieved_date_by_survey_id.get(pr["survey_id"]) is None
        )
        # Status driven by still_needed (not achieved>=target) - achieved
        # is capped at nominal_target and can exceed the smaller
        # accessible-only target for a straddling cluster, so comparing
        # achieved against target directly would be ambiguous there.
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
    # Achieved is always capped at the NOMINAL target - real credit already
    # earned is never reduced just because the site later became
    # inaccessible (same principle as the Non-IDP side).
    achieved = min(n_achieved, nominal_target) if nominal_target else n_achieved
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
    ("Achieved", "Collected, capped at this cluster's own target - what actually counts toward finishing it. Matches the dashboard's own definition. Kept in full even for a cluster now marked Inaccessible - real completed work isn't erased by the area becoming unreachable afterward."),
    ("Still Needed", "Target minus Achieved, floored at 0 - EXCEPT for a cluster marked Inaccessible, where this is always 0 regardless of the gap: you are not being asked to go back there right now, however far from target it is."),
    ("Collection Status = Inaccessible", "This cluster's ward is currently flagged as not safely reachable. It's excluded from 'Total target'/'Still needed' in the README headline above and from the 'Needs Collecting' sheet, but its Achieved/Collected figures still count in full."),
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


def build_partner_summary_table(meta_rows):
    agg = defaultdict(lambda: {"non_idp_target": 0, "non_idp_reserve": 0, "idp_clusters": 0, "idp_target": 0, "idp_reserve": 0})
    for row in meta_rows:
        key = (row["State"], row["LGA"])
        a = agg[key]
        pt = row["Point Type"]
        if pt == "Non-IDP household (primary)":
            a["non_idp_target"] += 1
        elif pt == "Non-IDP household (reserve)":
            a["non_idp_reserve"] += 1
        elif pt == "IDP cluster (Tier 1 primary)":
            a["idp_clusters"] += 1
            a["idp_target"] += int(row.get("Target HHs (primary)") or 0)
            a["idp_reserve"] += int(row.get("Reserve HHs") or 0)
    out = []
    for (state, lga), a in sorted(agg.items()):
        out.append({
            "State": state, "LGA": lga,
            "Non-IDP target sample": a["non_idp_target"], "Non-IDP reserve": a["non_idp_reserve"],
            "IDP clusters": a["idp_clusters"], "IDP target sample": a["idp_target"], "IDP reserve": a["idp_reserve"],
            "Total target sample": a["non_idp_target"] + a["idp_target"],
        })
    return out


def write_partner_workbook(partner_dir_path, partner_name, meta_rows, cluster_rows=None):
    if not meta_rows:
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

    # ---- headline block (2026-09-05): this partner's own target/achieved/
    # remaining at a glance, before the detailed per-LGA table below.
    # "Total target"/"Still needed" deliberately EXCLUDE clusters currently
    # marked Inaccessible - that's not part of your active, currently-
    # askable workload. "Achieved so far" deliberately does NOT exclude
    # them - real completed interviews still count in full even if the
    # area has since become inaccessible; see the header note above
    # frame_rows_full for why (417 real interviews nationally would
    # otherwise silently lose credit). This means Target may not always
    # equal Achieved + Still needed exactly - the gap, if any, is credited
    # work sitting in areas no longer part of your active target, called
    # out separately below rather than folded silently into either figure.
    active_rows = [x for x in cluster_rows if x["Collection Status"] != "Inaccessible"]
    inaccessible_rows = [x for x in cluster_rows if x["Collection Status"] == "Inaccessible"]
    total_target = sum(x["Target HHs (primary)"] for x in active_rows)
    total_achieved = sum(x["Achieved"] for x in cluster_rows)
    total_remaining = sum(x["Still Needed"] for x in active_rows)
    achieved_in_inaccessible = sum(x["Achieved"] for x in inaccessible_rows)
    n_clusters_complete = sum(1 for x in cluster_rows if x["Collection Status"] == "Complete")
    n_clusters_not_started = sum(1 for x in active_rows if x["Collection Status"] == "Not started")
    pct_complete = (total_achieved / total_target) if total_target else 0
    ws_readme.cell(row=r, column=1, value="Where things stand right now").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    headline_start = r
    headline = [
        ("Total target (your currently active clusters)", total_target),
        ("Achieved so far (all real interviews, including any since become inaccessible)", total_achieved),
        ("Still needed (active clusters only)", total_remaining),
        ("% of active target achieved", f"{pct_complete:.0%}"),
        ("Clusters fully complete", f"{n_clusters_complete} of {len(cluster_rows)}"),
        ("Clusters not yet started (active)", n_clusters_not_started),
        ("Clusters currently inaccessible (excluded from your active target above)", len(inaccessible_rows)),
        ("...of which, real interviews already achieved there (counted above, not asking for more)", achieved_in_inaccessible),
    ]
    for label, val in headline:
        ws_readme.cell(row=r, column=1, value=label).font = openpyxl.styles.Font(bold=True)
        cell = ws_readme.cell(row=r, column=2, value=val)
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="D9E2F3")
        r += 1
    r += 1

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
    summary_rows = build_partner_summary_table(meta_rows)
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

    os.makedirs(partner_dir_path, exist_ok=True)
    wb_out.save(os.path.join(partner_dir_path, f"{safe_folder_name(partner_name)}_sampling_points_summary.xlsx"))


# ---------------------------------------------------------------------------
# 7. Build per-partner/state/lga packages
# ---------------------------------------------------------------------------
stats = Counter()
partner_folders = set()
partner_meta_rows = defaultdict(list)
partner_cluster_rows = defaultdict(list)

for pcode, partners in partners_by_pcode.items():
    rows = rows_by_pcode.get(pcode)
    rows_full = rows_by_pcode_full.get(pcode) or []
    if not rows and not rows_full:
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

        # Cluster_guide/ subfolders created up front (even though the docx
        # files themselves are copied in later by build_cluster_factsheets.py)
        # so the folder skeleton is complete/consistent even for an LGA
        # whose factsheet batch hasn't run yet.
        if wrote_a or wrote_b:
            os.makedirs(os.path.join(lga_dir, "Non_IDP", "Cluster_guide"), exist_ok=True)
        if wrote_c or wrote_d:
            os.makedirs(os.path.join(lga_dir, "IDP", "Cluster_guide"), exist_ok=True)

        if wrote_a or wrote_b or wrote_c or wrote_d:
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

# ---------------------------------------------------------------------------
# 8. One summary Excel workbook per partner, at the partner's root folder
# ---------------------------------------------------------------------------
failed_workbooks = []
for (partner_dir, partner_name), meta_rows in partner_meta_rows.items():
    meta_rows.sort(key=lambda r: (r["State"], r["LGA"], r["Point Type"], r.get("Cluster ID", ""), r.get("Survey ID", "")))
    cluster_rows = partner_cluster_rows.get((partner_dir, partner_name), [])
    cluster_rows.sort(key=lambda r: (r["State"], r["LGA"], r["Population Type"], r["Cluster ID"]))
    try:
        write_partner_workbook(os.path.join(OUT_ROOT, partner_dir), partner_name, meta_rows, cluster_rows)
    except PermissionError:
        # File open/locked (e.g. in Excel) at run time - don't let one locked
        # partner file block every other partner's workbook from writing.
        failed_workbooks.append(partner_name)
        print(f"WARNING: could not write workbook for {partner_name} - file appears to be open/locked. Skipped.")

if failed_workbooks:
    print(f"\n{len(failed_workbooks)} workbook(s) skipped due to file locks - close the file(s) and rerun to update: {failed_workbooks}")

print(f"\nPartners: {len(partner_folders)}")
print(f"Partner/State/LGA folders written: {stats['lga_folders']}")
print(f"Non-IDP primary points: {stats['non_idp_primary_pts']}")
print(f"Non-IDP reserve points: {stats['non_idp_reserve_pts']}")
print(f"IDP Tier 1 primary points: {stats['idp_primary_pts']}")
print(f"IDP Tier 2 backup points: {stats['idp_tier2_pts']}")
print(f"LGA summary maps copied: {stats['lga_maps_copied']} (missing: {stats['lga_maps_missing']})")
print(f"Per-partner summary workbooks written: {len(partner_meta_rows)}")
print("\nDONE")
