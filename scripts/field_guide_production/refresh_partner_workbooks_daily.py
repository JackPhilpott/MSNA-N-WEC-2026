# ==============================================================================
# refresh_partner_workbooks_daily.py - the DAILY/auto-safe tier of the
# partner-package two-tier refresh (2026-09-08 rebuild, design agreed with
# Jack: "we could update this partner folder daily with refreshed achieved/
# still to collect sheets etc (including confirmed deletions), and then only
# inform them for the bigger resampling pushes... I would follow up with an
# email informing them of bigger changes").
#
# Refreshes ONLY each partner's <Partner>_sampling_points_summary.xlsx
# workbook (Sampling Points / Needs Collecting / Cluster Summary sheets) -
# achieved status, still-needed counts, confirmed deletions, current
# accessibility - against today's real submissions and the current FULL
# sampling frame. Never touches KML files, LGA summary maps, or any
# partner-facing GPS point roster - those stay the RESAMPLING-PUSH tier, run
# only via the full build_partner_dc_packages.py when the WORKING roster
# itself actually changes, followed by an announced email (Jack's call each
# time, never automatic). This is exactly why this script never loads
# WORKING (NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv) at all -
# there is nothing in its own output that WORKING could change.
#
# Deliberately a standalone duplicate of build_partner_dc_packages.py's
# FULL-sourced workbook logic (its sections 1-3d, 6, 7's meta/cluster-row
# building, 8) rather than an import - matches this project's established
# standalone-script convention (independent runnability; see that script's
# own header for the fuller rationale). Kept in sync BY HAND with that
# script's equivalent sections whenever either changes - if you touch
# achieved/status/threshold logic in one, check the other. One deliberate
# behavioural difference from the source script: IDP Tier 2 backup metadata
# rows here are gated on the cluster's presence in the FULL frame (not
# WORKING, which this script doesn't load) - more correct for a daily/
# achieved-status view anyway, consistent with every other row in this
# workbook already being FULL-sourced and independent of WORKING roster
# changes (see build_partner_dc_packages.py's own repeated comments on this
# point) - the source script's use of the WORKING-gated `wrote_d` flag for
# this one row type looks like an incidental coupling, not a deliberate
# design choice, since it directly contradicts that stated principle.
#
# Meant to be run daily/every-other-day, right after
# refresh_working_frame_daily.R (needs a fresh FULL frame + fresh
# real_submissions.csv - does NOT need WORKING to be fresh, since it never
# reads WORKING at all). Safe to run unconditionally (assert_fresh
# "auto"-safe): deterministic given its inputs, no judgment calls, no
# partner-facing roster change, nothing that needs an announcement email.
#
# Usage: python refresh_partner_workbooks_daily.py
#   Optional env var BUILD_DC_ONLY_PARTNER, same convention as
#   build_partner_dc_packages.py, scopes a run to one partner only - useful
#   for testing a change against a single partner's live file.
# ==============================================================================
import csv
import datetime
import difflib
import os
import re
import time
from collections import defaultdict, Counter

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STRATA_CSV = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample\strata_level_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
_LOCKED_FALLBACK_COPY = r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"
if os.path.exists(_LOCKED_FALLBACK_COPY):
    # Same staleness guard as build_partner_dc_packages.py - see that
    # script's header for the 2026-08-19 incident this hardened against.
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
STAGE2_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"
# Canonical (not the dashboard_app/ bundled mirror - see
# build_partner_dc_packages.py's 2026-09-08 fix note for the identical bug
# this avoids from the start).
REAL_SUBMISSIONS_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\2_monitoring\data\real_submissions.csv"
BACKUP_POINTS_CSV = PROJECT_DIR + r"\output\data\data_collection\idp_camp_backup_points.csv"
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
# 1. Master LGA list (adm2_pcode <-> state/lga names) - needed only to
# resolve which partner owns which pcode below; row-level state/LGA/ward
# values come straight from the FULL frame's own columns.
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

_only_partner = os.environ.get("BUILD_DC_ONLY_PARTNER")
if _only_partner:
    partners_by_pcode = {pcode: {p for p in partners if p == _only_partner} for pcode, partners in partners_by_pcode.items()}
    partners_by_pcode = {pcode: partners for pcode, partners in partners_by_pcode.items() if partners}
    print(f"BUILD_DC_ONLY_PARTNER set - scoped to '{_only_partner}' only ({len(partners_by_pcode)} LGA(s)).")

print(f"Partner coverage resolved for {len(partners_by_pcode)} LGAs.")

# ---------------------------------------------------------------------------
# 3. FULL household-level frame - drives every sheet in this workbook. Same
# in-scope universe as build_partner_dc_packages.py's frame_rows_full:
# covered, not excluded. ward_accessible_status deliberately NOT filtered
# out here either, same reasoning as that script - see its header note on
# frame_rows_full (417 real completed interviews nationally sit in clusters
# now ward-inaccessible; silently dropping those rows would erase real,
# already-completed field credit).
# ---------------------------------------------------------------------------
def _ward_accessible(r):
    return r.get("ward_accessible_status") in (None, "", "NA") or r["ward_accessible_status"] != "Inaccessible"


with open(STAGE2_FULL_CSV, encoding="utf-8") as f:
    frame_rows_full = [r for r in csv.DictReader(f) if r["coverage_status"] == "covered" and r["exclusion_reason"] == "none"]
print(f"Loaded {len(frame_rows_full)} household-level rows (FULL, covered & not excluded - drives every workbook sheet).")

rows_by_pcode_full = defaultdict(list)
for r in frame_rows_full:
    rows_by_pcode_full[r["adm2_pcode"]].append(r)

# Sub-4-accessible-household cluster threshold - same rule, same value, as
# build_partner_dc_packages.py's section 3d (Jack's 2026-09-05 decision).
# See that script's header note for the full reasoning.
NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH = 4

cluster_accessible_primary_n = Counter()
for r in frame_rows_full:
    if r["pop_type"] == "non_idp" and r["status"] == "primary" and _ward_accessible(r):
        cluster_accessible_primary_n[r["cluster_id"]] += 1


def _cluster_below_accessible_threshold(cluster_id):
    return cluster_accessible_primary_n.get(cluster_id, 0) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH


def _row_effectively_inaccessible(r):
    if not _ward_accessible(r):
        return True
    if r["pop_type"] == "non_idp":
        return _cluster_below_accessible_threshold(r["cluster_id"])
    return False

# ---------------------------------------------------------------------------
# 3c. Achieved status, computed fresh from 2_monitoring's canonical
# real_submissions.csv every run - identical logic to
# build_partner_dc_packages.py's section 3c (mirrors dashboard_app/
# global.R's is_achieved()/is_collected()).
# ---------------------------------------------------------------------------
with open(REAL_SUBMISSIONS_CSV, encoding="utf-8") as f:
    real_subs = list(csv.DictReader(f))
print(f"Loaded {len(real_subs)} real submission rows.")


def _is_achieved(r):
    return (
        r.get("interview_outcome") == "completed"
        and r.get("is_duplicate") != "TRUE"
        and r.get("matched_survey_id") not in (None, "", "NA")
        and r.get("quality_exclusion_reason") in (None, "", "NA")
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
# 4. IDP camp backup GPS points - static reference data (Tier 2 metadata
# rows only; no KML written here).
# ---------------------------------------------------------------------------
with open(BACKUP_POINTS_CSV, encoding="utf-8") as f:
    backup_rows = list(csv.DictReader(f))
backup_by_cluster = {
    r["site_id"]: r for r in backup_rows if r["backup_gps_lat"] not in (None, "", "NA")
}
print(f"{len(backup_by_cluster)} in-camp clusters with a Tier 2 backup GPS point.")

# ---------------------------------------------------------------------------
# 6. Metadata-row builders - identical to build_partner_dc_packages.py's
# section 6 (workbook portion only; no placemark/KML builders here).
# ---------------------------------------------------------------------------
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
        n_achieved_exact = len(achieved_dates)
        collected = max(cluster_collected_n.get(cluster_id, 0), n_achieved_exact)
        accessible_primary = [pr for pr in g["primary"] if _ward_accessible(pr)]
        cluster_inaccessible = len(accessible_primary) < NON_IDP_MIN_ACCESSIBLE_PRIMARY_HH
        target = 0 if cluster_inaccessible else len(accessible_primary)
        nominal_target = len(g["primary"])
        achieved = min(n_achieved_exact, nominal_target) if nominal_target else n_achieved_exact
        any_r = g["primary"][0] if g["primary"] else g["reserve"][0]
        still_needed = 0 if cluster_inaccessible else sum(
            1 for pr in accessible_primary if achieved_date_by_survey_id.get(pr["survey_id"]) is None
        )
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
    nominal_target = int(r["target_households"]) if r["target_households"] not in (None, "", "NA") else 0
    reserve_n = int(r["reserve_households"]) if r["reserve_households"] not in (None, "", "NA") else 0
    collected = cluster_collected_n.get(cluster_id, 0)
    n_achieved = cluster_achieved_n.get(cluster_id, 0)
    achieved = min(n_achieved, nominal_target) if nominal_target else n_achieved
    inaccessible = _row_effectively_inaccessible(r)
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

    # ---- Sheet 3: Needs Collecting ----
    # 2026-09-08: Non-IDP reserve households and IDP Tier 2 backup points
    # are excluded here (kept in "Sampling Points" only) - see
    # build_partner_dc_packages.py's equivalent block for the full
    # reasoning (this sheet is framed as a straight to-do list; reserves/
    # Tier 2 are conditional-only-if-primary-fails backups, not independent
    # targets, and including them risked reading as "collect these too").
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

    # ---- Sheet 4: Cluster Summary ----
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
# 7. Build per-partner meta/cluster rows - FULL-sourced only, no KML/map I/O
# at all (that's the whole point of this tier).
# ---------------------------------------------------------------------------
partner_folders = set()
partner_meta_rows = defaultdict(list)
partner_cluster_rows = defaultdict(list)

for pcode, partners in partners_by_pcode.items():
    rows_full = rows_by_pcode_full.get(pcode) or []
    if not rows_full:
        continue
    v = master_lgas[pcode]
    state_name, lga_name = v["adm1_name"], v["adm2_name"]

    non_idp_primary_rows_full = [r for r in rows_full if r["pop_type"] == "non_idp" and r["status"] == "primary"]
    non_idp_reserve_rows_full = [r for r in rows_full if r["pop_type"] == "non_idp" and r["status"] == "reserve"]
    idp_rows_by_cluster_full = {}
    for r in rows_full:
        if r["pop_type"] == "idp":
            idp_rows_by_cluster_full.setdefault(r["cluster_id"], r)

    for partner in partners:
        partner_dir = safe_folder_name(partner)
        partner_folders.add(partner_dir)

        meta = partner_meta_rows[(partner_dir, partner)]
        if non_idp_primary_rows_full:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_primary_rows_full)
        if non_idp_reserve_rows_full:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_reserve_rows_full)
        if idp_rows_by_cluster_full:
            meta.extend(idp_primary_metadata_row(partner, state_name, lga_name, cid, r) for cid, r in idp_rows_by_cluster_full.items())
            # Tier 2 backup rows: gated on FULL-frame cluster presence, not
            # WORKING (this script never loads WORKING) - see header note on
            # why that's the more-correct gate anyway.
            meta.extend(
                idp_tier2_metadata_row(partner, state_name, lga_name, cid, r, backup_by_cluster[cid])
                for cid, r in idp_rows_by_cluster_full.items() if cid in backup_by_cluster
            )

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
        failed_workbooks.append(partner_name)
        print(f"WARNING: could not write workbook for {partner_name} - file appears to be open/locked. Skipped.")

if failed_workbooks:
    print(f"\n{len(failed_workbooks)} workbook(s) skipped due to file locks - close the file(s) and rerun to update: {failed_workbooks}")

print(f"\nPartners: {len(partner_folders)}")
print(f"Per-partner summary workbooks refreshed: {len(partner_meta_rows)}")
print("\nDONE (workbook-only daily refresh - no KML/point-roster files touched)")
