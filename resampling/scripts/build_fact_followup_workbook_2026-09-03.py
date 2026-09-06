# ==============================================================================
# Builds the FACT follow-up accessibility workbook, 2026-09-03. Sends back
# the FULL, current (post 2026-09-01 resampling) ward + cluster universe -
# not another bespoke subset - with everything already known/correct left
# untouched, and only the ~28 wards / 78 clusters that genuinely need
# Talatu's input highlighted in a single colour with a plain-English reason.
#
# Data prepared by build_fact_followup_report_2026-09-03.R (+ _step2.R) -
# see that script's header for the full reconciliation logic (master
# accessibility status as the base, generic contradiction fixes, the
# 2026-09-03 Kebbi security update, the Matazu subcontractor notes).
#
# Deliberately does NOT reuse Talatu's multi-colour legend (Green/Yellow/
# Red/Purple/Blue) - the review found it applied inconsistently and often
# contradicting the plain-text value. One highlight colour here: amber =
# "please look at this row." Everything else = "already correct, leave it."
# ==============================================================================
import csv

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
WARD_CSV = PROJECT_DIR + r"\resampling\output\resample_runs\FACT\2026-09-03\fact_followup_ward_reconciled.csv"
CLUSTER_CSV = PROJECT_DIR + r"\resampling\output\resample_runs\FACT\2026-09-03\fact_followup_cluster_reconciled.csv"
OUT_PATH = PROJECT_DIR + r"\resampling\output\resample_runs\FACT\2026-09-03\FACT_accessibility_followup_2026-09-03.xlsx"

HEADER_FILL_REF = PatternFill("solid", fgColor="1B2A4A")
HEADER_FILL_INPUT = PatternFill("solid", fgColor="2C5F8A")
NEEDS_INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
INPUT_COLUMNS = {"Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far",
                  "Date reported", "Confirmed / Corrected?"}
ACCESSIBLE_OPTIONS = ["Yes", "No"]
REASON_OPTIONS = [
    "N/A - fully accessible", "Insecurity / conflict", "Physical access (terrain, flooding, roads)",
    "Population absent / relocated", "Building-footprint issue (no eligible structures)",
    "Access denied by authorities / community", "Other",
]

WARD_COLUMNS = ["State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)", "Non-IDP clusters", "IDP clusters",
                "Total target HHs (primary)", "Accessible (Y/N)", "Reason category", "Reason notes",
                "Date reported", "Needs your input?", "Why flagged"]
CLUSTER_COLUMNS = ["State", "LGA", "Ward (GRID3)", "Pop Type", "Cluster ID", "IDP Category",
                    "Target HHs (primary)", "Reserve HHs", "Accessible (Y/N)", "Reason category",
                    "Reason notes", "Date reported", "Needs your input?", "Why flagged"]
SUBCONTRACTOR_COLUMNS = ["Subcontracted / government partner name", "State", "LGA(s) covered",
                          "Ward(s) covered (leave blank if the whole LGA)", "Contact person (if available)", "Notes"]


def read_rows(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_sheet(wb, sheet_name, columns, rows, row_map, needs_attention_field="needs_attention", why_field="flag_reason"):
    ws = wb.create_sheet(sheet_name)
    ws.append(columns)
    for c, col_name in enumerate(columns, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL_INPUT if col_name in INPUT_COLUMNS else HEADER_FILL_REF

    n_flagged = 0
    for row in rows:
        vals = row_map(row)
        ws.append(vals)
        r = ws.max_row
        flagged = str(row.get(needs_attention_field, "")).strip().upper() in ("TRUE", "1")
        if flagged:
            n_flagged += 1
            for c in range(1, len(columns) + 1):
                ws.cell(row=r, column=c).fill = NEEDS_INPUT_FILL

    n_rows = len(rows)
    if "Accessible (Y/N)" in columns:
        access_col = columns.index("Accessible (Y/N)") + 1
        reason_col = columns.index("Reason category") + 1
        dv_access = DataValidation(type="list", formula1=f'"{",".join(ACCESSIBLE_OPTIONS)}"', allow_blank=True)
        dv_reason = DataValidation(type="list", formula1=f'"{",".join(REASON_OPTIONS)}"', allow_blank=True)
        ws.add_data_validation(dv_access)
        ws.add_data_validation(dv_reason)
        dv_access.add(f"{get_column_letter(access_col)}2:{get_column_letter(access_col)}{n_rows + 1}")
        dv_reason.add(f"{get_column_letter(reason_col)}2:{get_column_letter(reason_col)}{n_rows + 1}")

    ws.freeze_panes = "A2"
    for i, col_name in enumerate(columns, start=1):
        width = 34 if col_name == "Why flagged" else (28 if col_name == "Reason notes" else max(13, min(26, len(col_name) + 4)))
        ws.column_dimensions[get_column_letter(i)].width = width
    if n_rows:
        tbl = Table(displayName=sheet_name.replace(" ", "").replace("(", "").replace(")", ""),
                    ref=f"A1:{get_column_letter(len(columns))}{n_rows + 1}")
        tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws.add_table(tbl)
    return n_flagged


def main():
    ward_rows = read_rows(WARD_CSV)
    cluster_rows = read_rows(CLUSTER_CSV)

    wb = openpyxl.Workbook()
    wb.remove(wb.active)

    readme = wb.create_sheet("README")
    readme.column_dimensions["A"].width = 108
    n_ward_flag = sum(1 for r in ward_rows if str(r.get("needs_attention", "")).strip().upper() in ("TRUE", "1"))
    n_cluster_flag = sum(1 for r in cluster_rows if str(r.get("needs_attention", "")).strip().upper() in ("TRUE", "1"))
    lines = [
        ("FACT - NGA MSNA 2026 - Accessibility follow-up (2026-09-03)", True, 14),
        ("", False, 11),
        ("WHAT THIS IS", True, 12),
        (f"This is your FULL current assignment - {len(ward_rows)} wards, {len(cluster_rows)} clusters - reflecting "
         "everything as it stands today, including this week's resampling update. Almost all of it already matches "
         "what your team has told us and needs no action. Only the rows shaded amber need your input - "
         f"{n_ward_flag} wards ({n_cluster_flag} clusters). Everything else can be left exactly as it is.", False, 11),
        ("", False, 11),
        ("WHY THIS REPLACES THE FILES YOU SENT ON 3 SEPTEMBER", True, 12),
        ("Both files you sent this week were built on an older version of your assignment (from before this week's "
         "resampling), so a few of the corrections your team already made in your original 24 August report had "
         "reverted. This file starts from the current, correct version instead, so nothing gets lost either way.",
         False, 11),
        ("", False, 11),
        ("WHAT WE ALREADY APPLIED FOR YOU", True, 12),
        ("Your 3 September update about Fakai, Ngaski, and Wasagu/Danko (banditry / Lakurawa activity) has been "
         "applied - 13 wards exactly as you marked them, plus 6 more wards (Atuwo, Fakku, Danko Maga in Fakai; "
         "Bena, Kyaram, Dankolo in Wasagu/Danko) that you named in your email but weren't actually changed in your "
         "file. We've matched these to your intended wards directly and applied the same reason - please just "
         "confirm these are correct rather than re-entering them from scratch.", False, 10.5),
        ("", False, 11),
        ("WHAT STILL NEEDS YOU", True, 12),
        ("1. The 19 Kebbi wards above (amber, 'please confirm this is correct').", False, 11),
        ("2. Matazu: you marked Matazu A and Matazu B as covered by a subcontracted partner - please tell us which "
         "partner (see the new sheet below). The other 6 Matazu wards you gave the same note to but didn't mark "
         "as accessible - please confirm whether they should be Yes as well.", False, 11),
        ("3. One ward (Guzamala/Badu, Borno) has never been reported at all - please add Accessible Y/N and a "
         "reason.", False, 11),
        ("", False, 11),
        ("YOUR SUBCONTRACTED / GOVERNMENT PARTNERS", True, 12),
        ("New sheet - please list every subcontracted or government partner covering part of your assignment, and "
         "which LGA(s)/ward(s) each one covers. We can only treat an area as 'covered by a partner' once we have "
         "this written down clearly, rather than inferring it row by row from notes - that's what caused some of "
         "the confusion in this week's files.", False, 11),
        ("", False, 11),
        ("SHEETS", True, 12),
        ("Ward Accessibility - your full ward-level assignment. Amber rows need input.", False, 11),
        ("Cluster Accessibility - the same, at cluster level.", False, 11),
        ("Your Subcontracted Partners - new, please fill in.", False, 11),
    ]
    for i, (text, bold, size) in enumerate(lines, start=1):
        cell = readme.cell(row=i, column=1, value=text)
        cell.font = Font(bold=bold, size=size)
        cell.alignment = Alignment(wrap_text=True, vertical="top")
        if len(text) > 90:
            readme.row_dimensions[i].height = 16 + 14 * (len(text) // 90)

    def ward_map(r):
        return [r["State"], r["LGA"], r["Ward (GRID3)"], r.get("Ward (OCHA/COD)") or "",
                int(float(r["Non-IDP clusters"])) if r.get("Non-IDP clusters") not in (None, "", "NA") else None,
                int(float(r["IDP clusters"])) if r.get("IDP clusters") not in (None, "", "NA") else None,
                int(float(r["Total target HHs (primary)"])) if r.get("Total target HHs (primary)") not in (None, "", "NA") else None,
                r.get("Accessible") or None, r.get("Reason") or None, r.get("Notes") or None,
                r.get("Last reported date") or None,
                "Yes" if str(r.get("needs_attention", "")).strip().upper() in ("TRUE", "1") else "",
                r.get("flag_reason") or ""]

    def cluster_map(r):
        return [r["State"], r["LGA"], r["Ward (GRID3)"], r["Pop Type"], r["Cluster ID"], r.get("IDP Category") or None,
                int(float(r["Target HHs (primary)"])) if r.get("Target HHs (primary)") not in (None, "", "NA") else None,
                int(float(r["Reserve HHs"])) if r.get("Reserve HHs") not in (None, "", "NA") else None,
                r.get("Accessible (Y/N)") or None, r.get("Reason category") or None, r.get("Reason notes") or None,
                r.get("Date reported") or None,
                "Yes" if str(r.get("needs_attention", "")).strip().upper() in ("TRUE", "1") else "",
                r.get("flag_reason") or ""]

    n1 = write_sheet(wb, "Ward Accessibility", WARD_COLUMNS, ward_rows, ward_map)
    n2 = write_sheet(wb, "Cluster Accessibility", CLUSTER_COLUMNS, cluster_rows, cluster_map)

    sub_ws = wb.create_sheet("Your Subcontracted Partners")
    sub_ws.append(SUBCONTRACTOR_COLUMNS)
    for c, col_name in enumerate(SUBCONTRACTOR_COLUMNS, start=1):
        cell = sub_ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL_INPUT
        sub_ws.column_dimensions[get_column_letter(c)].width = 26
    # Pre-fill 2 example rows for Matazu A/B so she has a concrete starting point
    sub_ws.append(["(e.g. Conpad Initiatives)", "Katsina", "Matazu", "Matazu A, Matazu B", "", ""])
    for c in range(1, len(SUBCONTRACTOR_COLUMNS) + 1):
        sub_ws.cell(row=2, column=c).font = Font(italic=True, color="888888")
    for _ in range(14):
        sub_ws.append([""] * len(SUBCONTRACTOR_COLUMNS))
    sub_ws.freeze_panes = "A2"
    tbl = Table(displayName="SubcontractedPartners", ref=f"A1:{get_column_letter(len(SUBCONTRACTOR_COLUMNS))}16")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    sub_ws.add_table(tbl)

    wb.move_sheet("README", offset=-len(wb.sheetnames))
    wb.save(OUT_PATH)
    print(f"Wrote {OUT_PATH}")
    print(f"Ward Accessibility: {len(ward_rows)} rows, {n1} flagged")
    print(f"Cluster Accessibility: {len(cluster_rows)} rows, {n2} flagged")


if __name__ == "__main__":
    main()
