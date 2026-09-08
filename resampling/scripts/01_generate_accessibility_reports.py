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
# Reads: output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv
# - the same per-household delivered frame build_partner_dc_packages.py reads,
# which already carries a resolved `partners_covering` column (comma-separated
# for multi-partner LGAs, e.g. "DRC, IRC, LHI") and per-row ward attribution
# (`adm3_name` GRID3, `admin3_cod_name` OCHA/COD in the 3 NE states only) - no
# need to re-derive any matching/join logic done elsewhere.
#
# Rerun safety: this OVERWRITES each partner's staged .xlsx in
# accessibility_reports_generated/ every run - safe only because that's a
# staging copy nothing has been filled into yet. Once a copy has been pushed
# to a partner's SharePoint folder and may have partner input in it, do NOT
# rerun this script to "refresh" that copy - it would silently wipe their
# filled-in Accessible/Reason columns (same class of bug as
# write_partner_workbook() in build_partner_dc_packages.py, which rebuilds
# from scratch every run). If the cluster list changes (e.g. after a
# resample), any refresh of an already-distributed report must merge-preserve
# existing partner input, not regenerate blind - not implemented here since
# it hasn't been needed yet.
# ==============================================================================
import csv
import os
import re
from collections import defaultdict
from datetime import date

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
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"
OUT_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_generated"

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
    "State", "LGA", "Ward (GRID3)", "Pop Type", "Cluster ID", "IDP Category",
    "Target HHs (primary)", "Reserve HHs",
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


def safe_folder_name(s):
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


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

    ward_to_lgas = defaultdict(set)
    for r in rows:
        ward_to_lgas[(r["adm1_name"], r["adm3_name"])].add(r["adm2_name"])
    ward_to_lgas = {k: sorted(v) for k, v in ward_to_lgas.items()}

    cluster_rows = defaultdict(list)
    for r in rows:
        cluster_rows[r["cluster_id"]].append(r)

    ward_split_by_partner = defaultdict(list)
    cluster_repr_by_partner = defaultdict(list)

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
            record = {
                "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": w["ward_cod"],
                "Pop Type": pop_type_norm, "Cluster ID": cid, "IDP Category": cat,
                "Target HHs (primary)": w["primary"], "Reserve HHs": w["reserve"],
            }
            for p in partners:
                ward_split_by_partner[p].append(record)

        dominant_key = max(by_ward, key=lambda k: (by_ward[k]["primary"], k))
        state, lga, ward = dominant_key
        ward_cod = by_ward[dominant_key]["ward_cod"]
        cluster_record = {
            "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": ward_cod,
            "Pop Type": pop_type_norm, "Cluster ID": cid, "IDP Category": cat,
            "Target HHs (primary)": any_row["target_households"], "Reserve HHs": any_row["reserve_households"],
        }
        for p in partners:
            cluster_repr_by_partner[p].append(cluster_record)

    return ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas


def build_ward_rows(cluster_records, ward_to_lgas):
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


def write_partner_report(partner, ward_split_records, cluster_records, ward_to_lgas):
    ward_split_records.sort(key=lambda r: (r["State"], r["LGA"], r["Pop Type"], r["Cluster ID"]))
    cluster_records.sort(key=lambda r: (r["State"], r["LGA"], r["Pop Type"], r["Cluster ID"]))
    ward_rows = build_ward_rows(ward_split_records, ward_to_lgas)

    wb = openpyxl.Workbook()
    write_readme_sheet(wb, partner, len(ward_rows), len(cluster_records))

    add_input_sheet(wb, "Ward Accessibility", "WardAccessibility", WARD_COLUMNS, ward_rows)
    add_input_sheet(wb, "Cluster Accessibility", "ClusterAccessibility", CLUSTER_COLUMNS, cluster_records)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{safe_folder_name(partner)}_accessibility_report.xlsx")
    wb.save(out_path)
    return out_path, len(ward_rows)


if __name__ == "__main__":
    ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas = load_cluster_rows_by_partner()
    print(f"{len(cluster_repr_by_partner)} partners.")
    failed = []
    for partner in sorted(cluster_repr_by_partner):
        records = cluster_repr_by_partner[partner]
        ward_split_records = ward_split_by_partner[partner]
        try:
            path, n_wards = write_partner_report(partner, ward_split_records, records, ward_to_lgas)
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
