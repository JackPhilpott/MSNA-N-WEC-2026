# ==============================================================================
# Builds per-partner data-collection packages for the 2026-08-05 pilot
# handoff: partner_dc_files/<Partner>/<State>/<LGA>/ folders containing KML
# GPS-point files for field teams to load in Maps.me / Google Maps.
#
# Reads:
#   - input_data/boundaries/partner_coverage/Partnerscoverage.xlsx (which
#     partner(s) cover which LGA - wide format, one column per partner)
#   - output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv
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
# ==============================================================================
import csv
import difflib
import os
import re
import shutil
from collections import defaultdict, Counter
from xml.sax.saxutils import escape

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
# LGA-level summary maps (build_lga_summary_maps.R), copied into each
# covering partner's LGA folder below - 2026-08-07.
LGA_MAPS_DIR = PROJECT_DIR + r"\output\maps\lga_summary"
STRATA_CSV = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample\strata_level_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
if os.path.exists(r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"):
    # Source file was open/locked in Excel at run time - use the just-taken copy instead (2026-08-06).
    COVERAGE_XLSX = r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"
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

print(f"Partner coverage resolved for {len(partners_by_pcode)} LGAs.")

# ---------------------------------------------------------------------------
# 3. Household-level sampling frame (already covered-only)
# ---------------------------------------------------------------------------
with open(STAGE2_CSV, encoding="utf-8") as f:
    frame_rows = list(csv.DictReader(f))
print(f"Loaded {len(frame_rows)} household-level rows.")

rows_by_pcode = defaultdict(list)
for r in frame_rows:
    rows_by_pcode[r["adm2_pcode"]].append(r)

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
# ---------------------------------------------------------------------------
def write_kml(path, folder_name, placemarks):
    if not placemarks:
        return False
    parts = [
        '<?xml version="1.0" encoding="utf-8" ?>',
        '<kml xmlns="http://www.opengis.net/kml/2.2">',
        '<Document id="root_doc">',
        f"<Folder><name>{escape(folder_name)}</name>",
    ]
    for i, pm in enumerate(placemarks, start=1):
        desc = escape(pm["description"]).replace("\n", "&#10;")
        parts.append(
            f'  <Placemark id="{escape(folder_name)}.{i}">\n'
            f'\t<name>{escape(pm["name"])}</name>\n'
            f"\t<description>{desc}</description>\n"
            f'      <Point><coordinates>{pm["lon"]},{pm["lat"]}</coordinates></Point>\n'
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
METADATA_COLUMNS = [
    "Partner", "Point Type", "State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)", "Cluster ID", "Survey ID",
    "Status", "Sequence", "Latitude", "Longitude",
    "Building ID", "Building Confidence",
    "IDP Category", "IOM Site Name", "IOM Site Type", "Site Radius (m)",
    "Target HHs (primary)", "Reserve HHs", "Notes",
]


def cod_ward_value(r):
    cod_name = r.get("admin3_cod_name")
    return cod_name if cod_name and cod_name != "NA" else ""


def non_idp_metadata_row(partner, state_name, lga_name, r):
    label = "Primary" if r["status"] == "primary" else "Reserve"
    seq = r["interview_number"] if r["status"] == "primary" else r["replacement_rank"]
    return {
        "Partner": partner, "Point Type": f"Non-IDP household ({label.lower()})",
        "State": state_name, "LGA": lga_name, "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Cluster ID": r["cluster_id"], "Survey ID": r["survey_id"],
        "Status": label, "Sequence": seq,
        "Latitude": r["latitude"], "Longitude": r["longitude"],
        "Building ID": r["building_id"], "Building Confidence": r["confidence"],
    }


def idp_primary_metadata_row(partner, state_name, lga_name, cluster_id, r):
    cat = "In-camp" if r["idp_population_category"] == "idps in camp" else "In-host"
    return {
        "Partner": partner, "Point Type": "IDP cluster (Tier 1 primary)",
        "State": state_name, "LGA": lga_name, "Ward (GRID3)": r["adm3_name"], "Ward (OCHA/COD)": cod_ward_value(r),
        "Cluster ID": cluster_id, "Status": "Primary",
        "Latitude": r["latitude"], "Longitude": r["longitude"],
        "IDP Category": cat, "IOM Site Name": r["iom_site_name"], "IOM Site Type": r["iom_site_type"],
        "Site Radius (m)": r["site_radius_m"],
        "Target HHs (primary)": r["target_households"], "Reserve HHs": r["reserve_households"],
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


def write_partner_workbook(partner_dir_path, partner_name, meta_rows):
    if not meta_rows:
        return
    from openpyxl.worksheet.table import Table, TableStyleInfo

    wb_out = openpyxl.Workbook()

    # ---- Sheet 1: README (definitions + per-state/LGA summary) ----
    ws_readme = wb_out.active
    ws_readme.title = "README"
    ws_readme.column_dimensions["A"].width = 30
    ws_readme.column_dimensions["B"].width = 95
    r = 1
    ws_readme.cell(row=r, column=1, value=f"{partner_name} - NGA MSNA 2026 sampling points summary").font = openpyxl.styles.Font(bold=True, size=14, color="1B2A4A")
    r += 2
    ws_readme.cell(row=r, column=1, value="Every GPS sampling point assigned to this partner, across all covered LGAs. See the 'Sampling Points' sheet for the full row-level table; this sheet gives definitions and a per-LGA target-sample summary.").font = openpyxl.styles.Font(italic=True)
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

    ws_readme.cell(row=r, column=1, value="Other column notes").font = openpyxl.styles.Font(bold=True, size=12)
    r += 1
    for term, definition in README_FIELD_NOTES:
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

    os.makedirs(partner_dir_path, exist_ok=True)
    wb_out.save(os.path.join(partner_dir_path, f"{safe_folder_name(partner_name)}_sampling_points_summary.xlsx"))


# ---------------------------------------------------------------------------
# 7. Build per-partner/state/lga packages
# ---------------------------------------------------------------------------
stats = Counter()
partner_folders = set()
partner_meta_rows = defaultdict(list)

for pcode, partners in partners_by_pcode.items():
    rows = rows_by_pcode.get(pcode)
    if not rows:
        continue
    v = master_lgas[pcode]
    state_name, lga_name = v["adm1_name"], v["adm2_name"]

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

        wrote_a = write_kml(os.path.join(non_idp_kml_dir, "non_idp_households_primary.kml"), "Non-IDP households (primary)", non_idp_primary)
        wrote_b = write_kml(os.path.join(non_idp_kml_dir, "non_idp_households_reserve.kml"), "Non-IDP households (reserve)", non_idp_reserve)
        wrote_c = write_kml(os.path.join(idp_kml_dir, "idp_clusters_primary.kml"), "IDP clusters (Tier 1 primary)", idp_primary)
        wrote_d = write_kml(os.path.join(idp_kml_dir, "idp_clusters_tier2_backup.kml"), "IDP clusters (Tier 2 backup points)", idp_tier2_backup)

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

        meta = partner_meta_rows[(partner_dir, partner)]
        if wrote_a:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_primary_rows)
        if wrote_b:
            meta.extend(non_idp_metadata_row(partner, state_name, lga_name, r) for r in non_idp_reserve_rows)
        if wrote_c:
            meta.extend(idp_primary_metadata_row(partner, state_name, lga_name, cid, r) for cid, r in idp_rows_by_cluster.items())
        if wrote_d:
            meta.extend(
                idp_tier2_metadata_row(partner, state_name, lga_name, cid, r, backup_by_cluster[cid])
                for cid, r in idp_rows_by_cluster.items() if cid in backup_by_cluster
            )

# ---------------------------------------------------------------------------
# 8. One summary Excel workbook per partner, at the partner's root folder
# ---------------------------------------------------------------------------
failed_workbooks = []
for (partner_dir, partner_name), meta_rows in partner_meta_rows.items():
    meta_rows.sort(key=lambda r: (r["State"], r["LGA"], r["Point Type"], r.get("Cluster ID", ""), r.get("Survey ID", "")))
    try:
        write_partner_workbook(os.path.join(OUT_ROOT, partner_dir), partner_name, meta_rows)
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
