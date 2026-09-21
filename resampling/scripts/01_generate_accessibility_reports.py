# ==============================================================================
# Generates one "<Partner>_accessibility_report.xlsx" per partner, staged into
# resampling/input/accessibility_reports_generated/ (NOT yet pushed to the
# partner package folders in "3. External coordination\NGA MSNA 2026 Package"
# - that copy-out is a separate, deliberate step, since it touches SharePoint
# folders already shared with all 19 partners).
#
# Two sheets, 2026-08-20 (v2): partners overwhelmingly report inaccessibility
# at WARD level ("these wards are insecure in this LGA"), not cluster level -
# a pure per-cluster checklist (v1 of this script) was causing confusion
# between the cluster and ward concepts. "Ward Accessibility" is now the
# primary sheet, one row per (State, LGA, Ward) this partner has clusters in;
# "Cluster Accessibility" is kept as a secondary/detail sheet for the rarer
# case where the issue is genuinely specific to one site/building rather than
# the whole ward.
#
# Why ward rows are always paired with a specific LGA (never a bare ward
# name): ward polygons don't cleanly nest inside LGA polygons in this
# project's own boundary data (see ../CLAUDE.md and
# build_partner_dc_packages.py's LGA_WARD_SOURCE_NOTE - GRID3 ward polygons
# occasionally disagree with the OCHA/COD LGA line by tens of metres at
# borders, and in practice a partner-recognised ward can span what this
# project's admin-2 layer treats as two different LGAs). If ward
# accessibility were tracked by ward name alone, one partner's "inaccessible"
# call on a border ward could wrongly get applied to a neighbouring LGA/
# partner's portion of the same-named ward. Scoping every ward row to
# (this partner's own cluster set) x (LGA, Ward) avoids that by construction
# - a row only exists here if this partner actually has clusters in that
# specific LGA+Ward combination, so there's no free-floating ward-name join
# anywhere that could cross-contaminate another partner's area.
#
# Reads: output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v11_WORKING.csv
# - the same per-household delivered frame build_partner_dc_packages.py reads,
# which already carries a resolved `partners_covering` column (comma-separated
# for multi-partner LGAs, e.g. "DRC, IRC, LHI") and per-row ward attribution
# (`adm3_name` GRID3, `admin3_cod_name` OCHA/COD in the 3 NE states only) - no
# need to re-derive any matching/join logic done elsewhere.
#
# Rerun safety (FIXED 2026-09-21, see below - previously this section
# documented the gap as unfixed; kept the history since the reasoning still
# explains WHY the fix works the way it does): this OVERWRITES each
# partner's staged .xlsx in accessibility_reports_generated/ every run, but
# it no longer regenerates blind. Every Ward Accessibility / Cluster
# Accessibility row is now merge-preserved against
# resampling/output/resampling_requests_log.csv (the durable, append-only
# record 02_ingest_accessibility_reports.py builds from returned partner
# files) before being written: a currently-live row whose (partner, ward)
# or (partner, cluster_id) already has a logged answer gets that answer
# pre-filled (Accessible/Reason/notes/%/Date reported/provenance) instead of
# a blank template, and a cluster the log has an answer for but that's no
# longer in the current WORKING frame at all (dropped by a resample) still
# gets a row, sourced entirely from the log, marked Status = "No longer in
# frame" - see load_requests_log()/dominant match keys below. This was
# flagged 2026-09-20 as a known gap (Jack: "later, not now") and fixed
# 2026-09-21 once it became blocking - a straddling cluster's own ward flip-
# flopping between regenerations (see the dominant-ward fix the same day)
# made the lost-reporting problem visible sooner than expected. Only
# addresses drift since the LAST regeneration of this staged copy - it does
# NOT reach into a partner's live SharePoint copy that has unsaved,
# never-returned edits sitting in it; those still need to come back through
# accessibility_reports_returned/ and 02_ingest first, same as always.
# ==============================================================================
import csv
import os
import re
from collections import defaultdict
from datetime import date, datetime

import openpyxl
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

# "Date reported" used to be plain free text - no validation at all - which is
# how we ended up with 3 different date formats across returned files and
# ~450 FACT rows corrupted by an Excel autofill-drag up to the year 2261
# (04_build_master_accessibility_status.py's parse_date_flexible() handles
# that mess downstream, but this stops new instances of it at the source
# instead). DATE_REPORTED_MIN is the reporting cycle's start with a small
# margin; anything before it typed into the cell is almost certainly a typo,
# and Excel's native date validation now rejects it outright rather than us
# silently discovering it months later. Decided 2026-08-28 - see CLAUDE.md.
DATE_REPORTED_MIN = date(2026, 7, 1)
DATE_REPORTED_FORMAT = "dd-mmm-yyyy"  # unambiguous regardless of the partner's locale (e.g. "27-Aug-2026")

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v11_WORKING.csv"
STAGE2_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv"
GIS_WARD_UNIVERSE_CSV = PROJECT_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
OUT_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_generated"
REQUESTS_LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"

ACCESSIBLE_OPTIONS = ["Yes", "No"]
REASON_OPTIONS = [
    "N/A - fully accessible",
    "Insecurity / conflict",
    "Physical access (terrain, flooding, roads)",
    "Population absent / relocated",
    "Building-footprint issue (no eligible structures)",
    "Access denied by authorities / community",
    "Other",
]

PROVENANCE_COLUMNS = ["Reported by (Partner / IMPACT-default)", "Source channel"]
REPORTED_BY_COL, SOURCE_CHANNEL_COL = PROVENANCE_COLUMNS
REPORTED_BY_OPTIONS = ["Partner", "IMPACT (default - accessible until reported otherwise)"]
SOURCE_CHANNEL_OPTIONS = [
    "Partner's own template", "Email", "WhatsApp/verbal (coordinator-transcribed)",
    "Point-level file annotation", "N/A",
]

WARD_COLUMNS = [
    "State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)",
    "Ward spans multiple LGAs (Y/N)", "Other LGA(s) sharing this ward", "Note",
    "Non-IDP clusters", "IDP clusters", "Total target HHs (primary)",
    "Accessible (Y/N)", "Reason category", "Reason notes",
    "% of target achieved so far", "Date reported",
] + PROVENANCE_COLUMNS

MULTI_LGA_WARD_NOTE = (
    "This ward's GRID3 polygon spans more than one LGA - you only need to report on the part of the ward that "
    "falls within your own LGA coverage. See the 'Other LGA(s) sharing this ward' column for where the rest "
    "of it sits."
)
CLUSTER_COLUMNS = [
    "State", "LGA", "Ward (GRID3)", "Pop Type", "Cluster ID", "Status", "IDP Category",
    "Target HHs (primary)", "Reserve HHs",
    "Accessible (Y/N)", "Reason category", "Reason notes",
    "% of target achieved so far", "Date reported",
] + PROVENANCE_COLUMNS
# Columns pre-filled from resampling_requests_log.csv when a prior answer
# exists for this exact (partner, key) - see load_requests_log() below.
PREFILL_FROM_LOG_COLUMNS = [
    "Accessible (Y/N)", "Reason category", "Reason notes",
    "% of target achieved so far", "Date reported",
] + PROVENANCE_COLUMNS
INPUT_COLUMNS = {
    "Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported",
    REPORTED_BY_COL, SOURCE_CHANNEL_COL,
}

README_OVERVIEW = (
    "This file lists every ward (and, on the second sheet, every individual cluster) currently assigned to your "
    "organisation under the NGA MSNA 2026 sampling design, so you can tell us where your teams are having "
    "trouble collecting data and why. We use this to decide how to respond - drawing a replacement cluster "
    "where needed - and to correctly document, in our final reporting, which areas' we were able to collect "
    "from and which we weren't. Accurate, complete reporting from you feeds directly into that documentation."
)

README_STEPS = [
    "Open the 'Ward Accessibility' sheet first - this is your main report, one row per ward you have clusters "
    "in. It's pre-filled with every ward/LGA combination assigned to you; you don't need to add or remove rows. "
    "Rows are sorted within each LGA by Total target HHs, largest first, so your main wards come before any "
    "small border cases.",
    "If you've reported on a row before, your last answer is already shown here (Accessible/Reason/Date "
    "reported etc.) rather than a blank cell - please review it and only change it if something has actually "
    "changed since you last told us, don't assume a filled-in row is a mistake. On the 'Cluster Accessibility' "
    "sheet, a cluster you previously flagged that's since been removed from your assigned list entirely still "
    "appears, marked 'No longer in frame' in the Status column - kept so your earlier report isn't lost, but "
    "it's no longer something we need action on.",
    "A row with a very small Total target HHs figure (1-2) usually means a border case - GRID3 and OCHA/COD "
    "boundaries don't always agree exactly, so a small part of one of your clusters can fall just inside a "
    "ward you don't otherwise work in. This is expected, not an error - please still report on it like any "
    "other row if it's genuinely inaccessible. If a row also shows 'Yes' under 'Ward spans multiple LGAs', "
    "see that row's Note for what part of the ward is actually yours to report on.",
    "For each ward, set Accessible (Y/N). Leave a ward's row otherwise blank if there's no issue there.",
    "For any ward marked 'No', pick the closest-fitting Reason category from the dropdown (use 'Other' plus a "
    "note if none fit), and add specific Reason notes - e.g. 'active clashes reported near [location] in the "
    "past week' is far more useful to us than just 'insecure'.",
    "If you know it, fill in roughly what % of the target sample you were able to achieve in that ward before "
    "stopping - even a rough estimate helps, and please don't leave this blank if the true answer is 0%.",
    "The last two columns ('Reported by' and 'Source channel') are for our own internal record-keeping - please "
    "leave them blank unless we've asked you to fill in a specific row on our behalf (e.g. transcribing a "
    "WhatsApp/verbal report into this sheet).",
    "Only use the 'Cluster Accessibility' sheet (second tab) for a problem specific to ONE site/HH within an "
    "otherwise-fine ward - and only once you've already worked through that cluster's reserve/replacement "
    "households and they weren't enough to cover it. Don't use this sheet before exhausting your reserve list "
    "for that cluster, and don't use it as a second way to report the same ward-wide issue already captured on "
    "the first sheet.",
    "Date reported must be an actual date, not typed text - click the cell and use Excel's date picker, or "
    "type it as e.g. 27-Aug-2026. The cell will reject anything that isn't a real date, or a date before "
    f"{DATE_REPORTED_MIN:%d %b %Y}/after today.",
    "IMPORTANT: please review your ENTIRE coverage area in one pass before sending this back to us, rather "
    "than reporting a few wards now and more later - this significantly cuts down the back-and-forth rounds "
    "we need with you. If genuinely new information comes in afterwards, send an updated copy of the FULL "
    "sheet (not just the changed rows) with a new Date reported - we track changes over time by date, so we "
    "don't need you to tell us what changed, just the current full picture.",
]

SHEET_GUIDE = [
    ("Ward Accessibility", "Your main report. Use for any access problem affecting a ward generally - "
     "insecurity, flooding/terrain, population displacement, denied access, etc."),
    ("Cluster Accessibility", "Secondary/detail only. Use ONLY for a problem specific to one site/HH, not the "
     "surrounding ward, and only after that cluster's reserve/replacement households were already used and "
     "weren't enough."),
]


def norm_pop_type(pt):
    return "Non-IDP" if pt == "non_idp" else "IDP"


def load_gis_ward_universe():
    """Stage-1-eligible (State, LGA, Ward) portions with real partner
    coverage, from the GIS accessible-area layer. FIXED 2026-09-20 (same
    root cause and fix pattern as 04_build_master_accessibility_status.py's
    load_gis_ward_universe() - independent code path, duplicated per this
    project's standalone-script convention, so fixing one does NOT fix the
    other): this script used to seed a partner's ward list purely from
    clusters actually drawn in WORKING - a ward that's genuinely eligible
    but never happened to get a cluster by chance (PPS is random) was
    invisible to that partner's generated report entirely, so they could
    never be asked about it. Found by Coordinator via Save the Children/
    Bungudu; independently re-verified before fixing: 1,681 distinct
    (State, LGA, Ward) portions with real partner coverage exist in the GIS
    layer but not in WORKING's own ward set."""
    try:
        with open(GIS_WARD_UNIVERSE_CSV, encoding="utf-8") as f:
            gis_rows = list(csv.DictReader(f))
    except FileNotFoundError:
        return []
    out = []
    for r in gis_rows:
        partners = {p.strip() for p in r["covering_partners"].split(";") if p.strip()}
        if not partners:
            continue
        out.append({"state": r["adm1_name"], "lga": r["adm2_name"], "ward": r["wardname"], "partners": partners})
    return out


def safe_folder_name(s):
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


def _parse_log_date(s):
    # date_reported_by_partner is stored in the log as a plain DD/MM/YYYY
    # string (day-first, matching this project's own Excel convention - see
    # feedback_date_dayfirst_sanity_check memory). "Date reported" on the
    # generated sheet is a real Excel date cell (DataValidation type="date"
    # in add_input_sheet), so this must come back as a date object, not a
    # string, or it renders oddly under the cell's date number format and
    # can trip the sheet's own date validation if a partner re-edits it.
    if not s:
        return ""
    try:
        return datetime.strptime(s, "%d/%m/%Y").date()
    except ValueError:
        return ""  # unparseable/legacy format - leave blank rather than guess


def load_requests_log():
    """Latest logged answer per (partner, report_level, key), where key is
    cluster_id for report_level=="cluster" and (state, lga, ward_name) for
    report_level=="ward". Mirrors 02_ingest_accessibility_reports.py's own
    latest_by_key() (request_id-max-wins, no status filtering - every row in
    the log is currently status=="new" anyway, since the resolution-tracking
    half of this log was never built - see that script's ingest() docstring)
    - duplicated rather than imported, per this project's standalone-script
    convention, since 01_ and 02_'s filenames can't be imported as Python
    modules (leading digits) without importlib machinery that isn't worth it
    for ~15 lines of logic.

    Added 2026-09-21 (Task 4, Jack) - the merge-preserve fix for the "already
    reported, don't want to lose that reporting" gap. See this script's
    header comment for the full history.
    """
    if not os.path.exists(REQUESTS_LOG_CSV):
        return {}, {}
    with open(REQUESTS_LOG_CSV, encoding="utf-8") as f:
        log_rows = list(csv.DictReader(f))
    latest_cluster = {}
    latest_ward = {}
    for r in log_rows:
        # .strip() every key field - found 2026-09-21 via a sanity check on
        # the dropped-cluster count (see the merge-preserve block below):
        # one real log row (Malteser, request_id 6480) had a stray leading
        # newline baked into cluster_id ('\nnon_idp_NG021027_8', presumably
        # copy-paste residue from a transcribed report), which silently
        # created a phantom second key alongside the correct one (request_id
        # 6484) - the phantom then matched no real frame row and would have
        # shown as "dropped from frame" for a cluster that was never
        # actually dropped. Stripping here fixes this instance and any
        # future one with the same shape, rather than special-casing this
        # one row.
        partner = r["partner"].strip()
        if r["report_level"] == "cluster" and r.get("cluster_id", "").strip():
            key = (partner, r["cluster_id"].strip())
            if key not in latest_cluster or int(r["request_id"]) > int(latest_cluster[key]["request_id"]):
                latest_cluster[key] = r
        elif r["report_level"] == "ward":
            key = (partner, r["state"].strip(), r["lga"].strip(), r["ward_name"].strip())
            if key not in latest_ward or int(r["request_id"]) > int(latest_ward[key]["request_id"]):
                latest_ward[key] = r
    return latest_cluster, latest_ward


def _log_row_to_prefill(log_row):
    return {
        "Accessible (Y/N)": log_row["accessible"],
        "Reason category": log_row["reason_category"],
        "Reason notes": log_row["reason_notes"],
        "% of target achieved so far": log_row["pct_target_achieved"],
        "Date reported": _parse_log_date(log_row["date_reported_by_partner"]),
        REPORTED_BY_COL: log_row["reported_by"],
        SOURCE_CHANNEL_COL: log_row["source_channel"],
    }


def load_cluster_rows_by_partner():
    """Returns (ward_split_by_partner, cluster_repr_by_partner).

    Fixed 2026-08-21 (found via real Save the Children reports - Tofa,
    Sankalawa, Gwamba, Bumbum A, Mai'adua C, Maikoni B, and Gallu were all
    silently missing their own Ward Accessibility row). The old version
    picked one "representative" household row per cluster_id via
    `dict.setdefault` to decide that cluster's single (State, LGA, Ward) -
    but setdefault only ever inserts on the first row seen for a cluster_id,
    so the `or r["status"] == "primary"` condition in front of it was dead
    code, and the real behaviour was "whichever row is first in the CSV's
    file order wins," discarding every other ward a cluster's households
    actually touch. A hexagon can genuinely span more than one ward's
    polygon - each household is joined to its own ward individually (see
    "Draw-pool protocol" in resampling/README.md) - so collapsing a cluster
    to one ward was always wrong whenever that happened. Checked against the
    full WORKING frame: 1,214 of 3,428 clusters nationally (35%) span more
    than one ward, affecting all 19 partners, not just Save the Children.

    `ward_split_by_partner` now has one record per (cluster, ward) pair
    actually touched, with Target/Reserve HHs counted from ONLY that ward's
    own household rows - never the whole cluster's target_households, which
    would double-count a shared cluster into every ward it touches. This
    feeds `build_ward_rows()` or "Ward Accessibility".

    `cluster_repr_by_partner` is a separate, unaffected-in-spirit result for
    "Cluster Accessibility" (site-level, always meant to show one row per
    actual cluster with its FULL target/reserve) - it still needs *a*
    representative ward for display, so it deterministically picks the ward
    with the most primary households in that cluster (ties broken by ward
    name) rather than "first in file," which is at least reproducible and
    usually the true majority site.

    Also returns `ward_to_lgas`: {(State, Ward (GRID3)): sorted [LGAs]},
    built from EVERY household nationally (not just one partner's own rows)
    - a ward name can genuinely be split across more than one LGA by the
    same GRID3-vs-OCHA/COD disagreement documented in resampling/README.md
    (e.g. Gallu, recognised by GRID3 as Mashi but placed in Mai'adua by
    OCHA/COD - the exact example map already sent to Save the Children).
    Scoped to (State, Ward) rather than Ward alone because the same ward
    NAME can coincidentally recur in a totally unrelated state (e.g.
    "Gwamba" is both a real Katsina/Zango ward and an unrelated
    Adamawa/Demsa ward) - that's name reuse, not a boundary split, and
    must not be flagged as one. Added 2026-08-21 alongside the ward-split
    fix above, so partners can tell "this ward is unfamiliar because it's
    a genuine border sliver of your own LGA" (small target count, decided
    2026-08-21 to keep as a normal row) apart from "this ward is
    unfamiliar because most of it actually belongs to a neighbouring LGA"
    (this flag) - two different reasons a row might look surprising, per
    the user's explicit request for this distinction to be visible on the
    sheet itself, not just in this file's history.
    """
    with open(STAGE2_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    latest_cluster_log, latest_ward_log = load_requests_log()

    ward_to_lgas = defaultdict(set)
    for r in rows:
        ward_to_lgas[(r["adm1_name"], r["adm3_name"])].add(r["adm2_name"])

    cluster_rows = defaultdict(list)
    for r in rows:
        cluster_rows[r["cluster_id"]].append(r)

    ward_split_by_partner = defaultdict(list)
    cluster_repr_by_partner = defaultdict(list)
    live_cluster_ids_by_partner = defaultdict(set)

    for cid, crows in cluster_rows.items():
        any_row = crows[0]
        partners = [p.strip() for p in any_row["partners_covering"].split(",") if p.strip() and p.strip() != "NA"]
        cat = any_row["idp_population_category"]
        cat = "" if cat in ("NA", "", None) else ("In-camp" if cat == "idps in camp" else "In-host")
        pop_type_norm = norm_pop_type(any_row["pop_type"])

        by_ward = defaultdict(lambda: {"primary": 0, "reserve": 0, "ward_cod": ""})
        for r in crows:
            key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
            w = by_ward[key]
            w[r["status"]] += 1
            ward_cod = r.get("admin3_cod_name")
            if ward_cod and ward_cod != "NA":
                w["ward_cod"] = ward_cod

        for (state, lga, ward), w in by_ward.items():
            base_record = {
                "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": w["ward_cod"],
                "Pop Type": pop_type_norm, "Cluster ID": cid, "IDP Category": cat,
                "Target HHs (primary)": w["primary"], "Reserve HHs": w["reserve"],
            }
            for p in partners:
                # Per-partner copy, not a shared dict reference - a
                # shared-LGA ward can have more than one covering partner
                # (partners_covering can list >1), each with their OWN
                # logged answer for the same (state, lga, ward); mutating
                # one shared dict here would let the last partner's prefill
                # silently overwrite what gets shown to every other partner
                # covering the same ward.
                record = dict(base_record)
                log_row = latest_ward_log.get((p, state, lga, ward))
                if log_row:
                    record.update(_log_row_to_prefill(log_row))
                ward_split_by_partner[p].append(record)

        dominant_key = max(by_ward, key=lambda k: (by_ward[k]["primary"], k))
        state, lga, ward = dominant_key
        ward_cod = by_ward[dominant_key]["ward_cod"]
        cluster_base_record = {
            "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": ward_cod,
            "Pop Type": pop_type_norm, "Cluster ID": cid, "IDP Category": cat,
            "Target HHs (primary)": any_row["target_households"], "Reserve HHs": any_row["reserve_households"],
        }
        for p in partners:
            # Same per-partner-copy reasoning as the ward loop above.
            record = dict(cluster_base_record)
            log_row = latest_cluster_log.get((p, cid))
            if log_row:
                record.update(_log_row_to_prefill(log_row))
            record["Status"] = "Active"
            cluster_repr_by_partner[p].append(record)
            live_cluster_ids_by_partner[p].add(cid)

    # Union in Stage-1-eligible wards that never had a cluster drawn there by
    # chance (see load_gis_ward_universe()'s docstring) - tracked separately
    # per partner as zero-cluster (State, LGA, Ward) keys, since there's no
    # real cluster row to build a WARD_COLUMNS record from. build_ward_rows()
    # seeds these into its own aggregation so they still appear as a normal
    # (blank) row in the partner's Ward Accessibility sheet.
    existing_ward_keys_by_partner = defaultdict(set)
    for p, records in ward_split_by_partner.items():
        for r in records:
            existing_ward_keys_by_partner[p].add((r["State"], r["LGA"], r["Ward (GRID3)"]))

    extra_ward_keys_by_partner = defaultdict(set)
    for g in load_gis_ward_universe():
        key = (g["state"], g["lga"], g["ward"])
        ward_to_lgas[(g["state"], g["ward"])].add(g["lga"])
        for p in g["partners"]:
            if key not in existing_ward_keys_by_partner[p]:
                extra_ward_keys_by_partner[p].add(key)

    ward_to_lgas = {k: sorted(v) for k, v in ward_to_lgas.items()}

    # Preserve previously-reported clusters that have since dropped out of
    # the current frame entirely (Task 4, Jack, 2026-09-21: "we don't want
    # to lose that reporting"). A cluster the log has a logged answer for,
    # for this partner, that ISN'T among this partner's current live
    # cluster_ids, gets a row built entirely from the log (no frame row
    # exists any more to source Target/Reserve/IDP Category from - shown as
    # "N/A (dropped)" rather than guessed). Sorted in with the live rows
    # below by build_ward_rows()/write_partner_report()'s own existing
    # sort, not appended separately, so a partner sees them in the same
    # place they'd expect the cluster to be.
    #
    # IMPORTANT: "genuinely dropped" is checked against the FULL frame's
    # partners_covering, NOT against live_cluster_ids_by_partner (which is
    # built from THIS SCRIPT's own STAGE2_CSV = WORKING). Caught 2026-09-21
    # before shipping via a sanity check on the raw count (1,364 dropped
    # rows, 1,209 of them FACT alone, was implausibly high) - traced to
    # exactly this: WORKING is a deliberately shrinking CANDIDATE pool that
    # already excludes a cluster once it's Complete or ward-inaccessible
    # (see household_frame's own header note in 2_monitoring/global.R for
    # the same WORKING-vs-FULL distinction elsewhere in this project) - a
    # cluster missing from WORKING for either of those completely normal
    # reasons is NOT "removed by resampling", and re-checked directly
    # against the live data confirmed zero of FACT's 2,147 logged clusters
    # were actually absent from FULL or reassigned to a different partner.
    # Using FULL + this partner still being in partners_covering is the
    # correct test for "the cluster or this partner's claim to it is
    # genuinely gone", matching what "dropped by a resample" actually means.
    full_partners_by_cluster = {}
    with open(STAGE2_FULL_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            cid = r["cluster_id"]
            if cid not in full_partners_by_cluster:
                full_partners_by_cluster[cid] = {p.strip() for p in r["partners_covering"].split(",") if p.strip() and p.strip() != "NA"}

    for (log_partner, log_cid), log_row in latest_cluster_log.items():
        if log_cid in live_cluster_ids_by_partner[log_partner]:
            continue
        if log_partner in full_partners_by_cluster.get(log_cid, set()):
            continue  # still genuinely this partner's cluster - just Complete/inaccessible/excluded from WORKING right now, not dropped
        dropped_record = {
            # log_row["pop_type"] is already display-form ("Non-IDP"/"IDP"
            # - see read_sheet_rows() in 02_ingest_accessibility_reports.py,
            # which stores the sheet's own "Pop Type" column verbatim, and
            # that column is itself already norm_pop_type()'d output at
            # generation time). Caught before shipping: passing it back
            # through norm_pop_type() here would invert every row (that
            # function expects the internal "non_idp"/"idp" code, not the
            # display string - "Non-IDP" != "non_idp" so it would return
            # "IDP" for an actual Non-IDP cluster). Currently a latent-only
            # bug (0 dropped rows nationally as of this fix), but fixed now
            # rather than left for whenever a cluster is first genuinely
            # dropped.
            "State": log_row.get("state", ""), "LGA": log_row.get("lga", ""),
            "Ward (GRID3)": log_row.get("ward_name", ""), "Pop Type": log_row.get("pop_type", ""),
            "Cluster ID": log_cid, "Status": "No longer in frame (kept for historical reporting - not an active target)",
            "IDP Category": "", "Target HHs (primary)": "N/A (dropped)", "Reserve HHs": "N/A (dropped)",
        }
        dropped_record.update(_log_row_to_prefill(log_row))
        cluster_repr_by_partner[log_partner].append(dropped_record)

    return ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas, extra_ward_keys_by_partner


def build_ward_rows(cluster_records, ward_to_lgas, extra_ward_keys=None):
    agg = defaultdict(lambda: {"non_idp": 0, "idp": 0, "target_hh": 0, "ward_cod": ""})
    for r in cluster_records:
        key = (r["State"], r["LGA"], r["Ward (GRID3)"])
        a = agg[key]
        if r["Pop Type"] == "Non-IDP":
            a["non_idp"] += 1
        else:
            a["idp"] += 1
        a["target_hh"] += int(r["Target HHs (primary)"] or 0)
        a["ward_cod"] = r["Ward (OCHA/COD)"]
    for key in (extra_ward_keys or ()):
        agg[key]  # touch to create a zero-cluster entry (GIS-eligible, never drawn - see load_gis_ward_universe())
    out = []
    for (state, lga, ward), a in agg.items():
        other_lgas = [l for l in ward_to_lgas.get((state, ward), [lga]) if l != lga]
        out.append({
            "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": a["ward_cod"],
            "Ward spans multiple LGAs (Y/N)": "Yes" if other_lgas else "No",
            "Other LGA(s) sharing this ward": "; ".join(other_lgas),
            "Note": MULTI_LGA_WARD_NOTE if other_lgas else "",
            "Non-IDP clusters": a["non_idp"], "IDP clusters": a["idp"], "Total target HHs (primary)": a["target_hh"],
        })
    # Grouped by State/LGA (stable, matches how partners think about their coverage), then by
    # Total target HHs descending within each LGA - so a partner's substantial wards come first
    # and small border-slivers (see README step above) naturally sink to the bottom of each group,
    # rather than being alphabetically interleaved with the wards that actually matter.
    out.sort(key=lambda r: (r["State"], r["LGA"], -r["Total target HHs (primary)"], r["Ward (GRID3)"]))
    return out


def add_input_sheet(wb, sheet_name, table_name, columns, rows):
    ws = wb.create_sheet(sheet_name)
    ws.append(columns)
    header_fill_ref = openpyxl.styles.PatternFill("solid", fgColor="1B2A4A")
    header_fill_input = openpyxl.styles.PatternFill("solid", fgColor="2C5F8A")
    for c, col_name in enumerate(columns, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = header_fill_input if col_name in INPUT_COLUMNS else header_fill_ref

    for row in rows:
        ws.append([row.get(c, "") for c in columns])

    n_rows = len(rows)
    accessible_col = columns.index("Accessible (Y/N)") + 1
    reason_col = columns.index("Reason category") + 1

    dv_access = DataValidation(type="list", formula1=f'"{",".join(ACCESSIBLE_OPTIONS)}"', allow_blank=True)
    dv_reason = DataValidation(type="list", formula1=f'"{",".join(REASON_OPTIONS)}"', allow_blank=True)
    ws.add_data_validation(dv_access)
    ws.add_data_validation(dv_reason)
    dv_access.add(f"{openpyxl.utils.get_column_letter(accessible_col)}2:{openpyxl.utils.get_column_letter(accessible_col)}{n_rows + 1}")
    dv_reason.add(f"{openpyxl.utils.get_column_letter(reason_col)}2:{openpyxl.utils.get_column_letter(reason_col)}{n_rows + 1}")

    if REPORTED_BY_COL in columns:
        reported_by_col = columns.index(REPORTED_BY_COL) + 1
        source_channel_col = columns.index(SOURCE_CHANNEL_COL) + 1
        dv_reported_by = DataValidation(type="list", formula1=f'"{",".join(REPORTED_BY_OPTIONS)}"', allow_blank=True)
        dv_source_channel = DataValidation(type="list", formula1=f'"{",".join(SOURCE_CHANNEL_OPTIONS)}"', allow_blank=True)
        ws.add_data_validation(dv_reported_by)
        ws.add_data_validation(dv_source_channel)
        dv_reported_by.add(f"{openpyxl.utils.get_column_letter(reported_by_col)}2:{openpyxl.utils.get_column_letter(reported_by_col)}{n_rows + 1}")
        dv_source_channel.add(f"{openpyxl.utils.get_column_letter(source_channel_col)}2:{openpyxl.utils.get_column_letter(source_channel_col)}{n_rows + 1}")

    if "Date reported" in columns:
        date_col = columns.index("Date reported") + 1
        date_col_letter = openpyxl.utils.get_column_letter(date_col)
        dv_date = DataValidation(
            type="date", operator="between",
            formula1=DATE_REPORTED_MIN, formula2=date.today(),
            allow_blank=True, showErrorMessage=True,
            errorTitle="Invalid date",
            error=(f"Enter an actual date between {DATE_REPORTED_MIN:%d %b %Y} and today - click the cell and "
                   "use the date picker, or type e.g. 27-Aug-2026. Free text and out-of-range dates (including "
                   "future dates) are rejected here so they don't need to be caught and excluded later."),
        )
        ws.add_data_validation(dv_date)
        dv_date.add(f"{date_col_letter}2:{date_col_letter}{n_rows + 1}")
        for row_idx in range(2, n_rows + 2):
            ws.cell(row=row_idx, column=date_col).number_format = DATE_REPORTED_FORMAT

    ws.freeze_panes = "A2"
    for i, col_name in enumerate(columns, start=1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(14, min(30, len(col_name) + 4))

    if n_rows:
        tbl = Table(displayName=table_name, ref=f"A1:{openpyxl.utils.get_column_letter(len(columns))}{n_rows + 1}")
        tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws.add_table(tbl)
    return ws


def write_readme_sheet(wb, partner, n_wards, n_clusters):
    ws = wb.active
    ws.title = "README"
    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 95

    r = 1
    ws.cell(row=r, column=1, value=f"{partner} - NGA MSNA 2026 accessibility report").font = openpyxl.styles.Font(bold=True, size=14, color="1B2A4A")
    r += 2

    ws.cell(row=r, column=1, value="Overview").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    cell = ws.cell(row=r, column=1, value=README_OVERVIEW)
    cell.alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
    ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=2)
    ws.row_dimensions[r].height = 90
    r += 2

    ws.cell(row=r, column=1, value=f"Assigned to you: {n_wards} wards, {n_clusters} clusters").font = openpyxl.styles.Font(bold=True, italic=True)
    r += 2

    ws.cell(row=r, column=1, value="What to do").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for i, step in enumerate(README_STEPS, start=1):
        ws.cell(row=r, column=1, value=i).font = openpyxl.styles.Font(bold=True)
        ws.cell(row=r, column=1).alignment = openpyxl.styles.Alignment(vertical="top")
        cell = ws.cell(row=r, column=2, value=step)
        cell.alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        is_important = step.startswith("IMPORTANT")
        if is_important:
            cell.font = openpyxl.styles.Font(bold=True, color="8B4A4A")
            ws.cell(row=r, column=2).fill = openpyxl.styles.PatternFill("solid", fgColor="FFF2CC")
        ws.row_dimensions[r].height = 60 if not is_important else 90
        r += 1
    r += 1

    ws.cell(row=r, column=1, value="Which sheet do I use?").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for c, h in enumerate(["Sheet", "Use for"], start=1):
        cell = ws.cell(row=r, column=c, value=h)
        cell.font = openpyxl.styles.Font(bold=True, color="FFFFFF")
        cell.fill = openpyxl.styles.PatternFill("solid", fgColor="2C5F8A")
    r += 1
    for sheet_name, desc in SHEET_GUIDE:
        ws.cell(row=r, column=1, value=sheet_name).font = openpyxl.styles.Font(bold=True)
        cell = ws.cell(row=r, column=2, value=desc)
        cell.alignment = openpyxl.styles.Alignment(wrap_text=True, vertical="top")
        ws.row_dimensions[r].height = 45
        r += 1


def write_partner_report(partner, ward_split_records, cluster_records, ward_to_lgas, extra_ward_keys=None):
    ward_split_records.sort(key=lambda r: (r["State"], r["LGA"], r["Pop Type"], r["Cluster ID"]))
    cluster_records.sort(key=lambda r: (r["State"], r["LGA"], r["Pop Type"], r["Cluster ID"]))
    ward_rows = build_ward_rows(ward_split_records, ward_to_lgas, extra_ward_keys)

    wb = openpyxl.Workbook()
    # 2026-09-21: count only Status=="Active" clusters here - cluster_records
    # can now also hold "No longer in frame" historical rows (Task 4), which
    # aren't really "assigned to you" any more and would inflate this
    # headline count if included.
    n_active_clusters = sum(1 for r in cluster_records if r.get("Status", "Active") == "Active")
    write_readme_sheet(wb, partner, len(ward_rows), n_active_clusters)

    add_input_sheet(wb, "Ward Accessibility", "WardAccessibility", WARD_COLUMNS, ward_rows)
    add_input_sheet(wb, "Cluster Accessibility", "ClusterAccessibility", CLUSTER_COLUMNS, cluster_records)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{safe_folder_name(partner)}_accessibility_report.xlsx")
    wb.save(out_path)
    return out_path, len(ward_rows)


if __name__ == "__main__":
    ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas, extra_ward_keys_by_partner = load_cluster_rows_by_partner()
    print(f"{len(cluster_repr_by_partner)} partners.")
    n_extra_total = sum(len(v) for v in extra_ward_keys_by_partner.values())
    print(f"{n_extra_total} Stage-1-eligible-but-never-drawn ward row(s) added across all partners (2026-09-20 fix).")
    failed = []
    for partner in sorted(cluster_repr_by_partner):
        records = cluster_repr_by_partner[partner]
        ward_split_records = ward_split_by_partner[partner]
        try:
            path, n_wards = write_partner_report(partner, ward_split_records, records, ward_to_lgas,
                                                   extra_ward_keys_by_partner.get(partner))
            print(f"  {partner}: {len(records)} clusters, {n_wards} wards -> {path}")
        except PermissionError:
            # File open/locked (e.g. in Excel, or mid-OneDrive-sync) at run time
            # - don't let one locked partner file block the rest of the batch.
            # Same handling as build_partner_dc_packages.py's write_partner_workbook().
            failed.append(partner)
            print(f"  WARNING: {partner} - file appears to be open/locked. Skipped.")
    if failed:
        print(f"\n{len(failed)} report(s) skipped due to file locks - close the file(s) and rerun to update: {failed}")
    print("\nDONE - staged in resampling/input/accessibility_reports_generated/. Not yet pushed to partner SharePoint folders.")
