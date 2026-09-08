# ==============================================================================
# Builds the workbook to send back to FACT alongside the reply email
# (2026-08-26, post-meeting, v2 - fixed two real bugs the user caught in v1):
#
# 1. v1 copied cell VALUES only (ws.iter_rows -> cell.value), which silently
#    drops DataValidation (the Accessible Y/N and Reason category dropdowns)
#    - the sheet looked identical but had lost the guided-input formatting
#    entirely. Fixed by rebuilding the dropdowns fresh on the output sheet,
#    same technique 01_generate_accessibility_reports.py uses, rather than
#    trying to copy validation objects across workbooks.
# 2. v1's Ward Accessibility sheet only contained the 878 wards FACT actually
#    submitted - the 189 wards missing from their return were listed on the
#    Issues to Review tab but never actually present as rows to fill in.
#    Fixed by rebuilding the FULL 1,067-ward universe (same logic as
#    generate_fact_gap_fill_report.py's build_fact_ward_rows()) and merging
#    FACT's own (corrected) submitted values onto it - the 878 already-
#    answered rows keep their answers, the 189 missing ones are present as
#    blank, fillable rows. One complete document, not two separate files.
#
# Purpose (per the user, 2026-08-26): this workbook is BOTH a highlight of
# the issues AND a clean, complete, correctly-formatted template FACT can
# fill in directly and send back for us to implement - not a read-only
# report.
# ==============================================================================
import csv
from collections import defaultdict

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

SAMPLING_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v4_WORKING.csv"
FACT_RETURNED = SAMPLING_DIR + r"\resampling\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"
LGA_SUMMARY_SOURCE = SAMPLING_DIR + r"\resampling\output\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
OUT_PATH = SAMPLING_DIR + r"\resampling\output\FACT_cleaned_listing_and_issues_2026-08-26.xlsx"
PARTNER = "FACT"

ACCESSIBLE_OPTIONS = ["Yes", "No"]
REASON_OPTIONS = [
    "N/A - fully accessible", "Insecurity / conflict", "Physical access (terrain, flooding, roads)",
    "Population absent / relocated", "Building-footprint issue (no eligible structures)",
    "Access denied by authorities / community", "Other",
]
WARD_COLUMNS = [
    "State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)",
    "Ward spans multiple LGAs (Y/N)", "Other LGA(s) sharing this ward", "Note",
    "Non-IDP clusters", "IDP clusters", "Total target HHs (primary)",
    "Accessible (Y/N)", "Reason category", "Reason notes",
    "% of target achieved so far", "Date reported",
]
CLUSTER_COLUMNS = [
    "State", "LGA", "Ward (GRID3)", "Pop Type", "Cluster ID", "IDP Category",
    "Target HHs (primary)", "Reserve HHs",
    "Accessible (Y/N)", "Reason category", "Reason notes",
    "% of target achieved so far", "Date reported",
]
INPUT_COLUMNS = {"Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported"}
MULTI_LGA_WARD_NOTE = (
    "This ward's GRID3 polygon spans more than one LGA - you only need to report on the part of the ward that "
    "falls within your own LGA coverage. See the 'Other LGA(s) sharing this ward' column for where the rest "
    "of it sits."
)

HEADER_FILL = PatternFill("solid", fgColor="1B2A4A")
HEADER_FILL_INPUT = PatternFill("solid", fgColor="2C5F8A")
ISSUE_FILL = PatternFill("solid", fgColor="8B4A4A")
WARN_FILL = PatternFill("solid", fgColor="C9A227")
LIGHT_ISSUE = PatternFill("solid", fgColor="F3E5E3")
LIGHT_WARN = PatternFill("solid", fgColor="FCF1CE")
NEEDS_INPUT_FILL = PatternFill("solid", fgColor="FFF6DD")  # highlights blank/new rows FACT still needs to fill

CONTRADICTION_KEYS = {
    ("Kebbi", "Augie", "Tiggi"), ("Sokoto", "Gada", "Gilbadi"), ("Sokoto", "Gudu", "Bachaka"),
    ("Sokoto", "Silame", "Jekanadu"), ("Sokoto", "Silame", "Kwaido"),
}
PARTIAL_KEYS = {
    ("Sokoto", "Gudu", "Chilas"), ("Sokoto", "Gudu", "Marake"), ("Sokoto", "Gudu", "Tullun Doya"),
    ("Sokoto", "Kebbe", "Bardoki"), ("Sokoto", "Silame", "Bakale"), ("Sokoto", "Tureta", "Kwarare"),
}
SEVERE_LGA_THRESHOLD = 30.0  # % population remaining - matches today's meeting discussion


def norm_pop_type(pt):
    return "Non-IDP" if pt == "non_idp" else "IDP"


def build_fact_full_universe():
    """Every (State, LGA, Ward) FACT has clusters in - the full 1,067-ward
    universe, same logic as generate_fact_gap_fill_report.py."""
    with open(STAGE2_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    ward_to_lgas = defaultdict(set)
    for r in rows:
        ward_to_lgas[(r["adm1_name"], r["adm3_name"])].add(r["adm2_name"])
    ward_to_lgas = {k: sorted(v) for k, v in ward_to_lgas.items()}

    cluster_rows = defaultdict(list)
    for r in rows:
        cluster_rows[r["cluster_id"]].append(r)

    ward_records = []
    for cid, crows in cluster_rows.items():
        any_row = crows[0]
        partners = [p.strip() for p in any_row["partners_covering"].split(",") if p.strip() and p.strip() != "NA"]
        if PARTNER not in partners:
            continue
        pop_type_norm = norm_pop_type(any_row["pop_type"])
        by_ward = defaultdict(lambda: {"primary": 0, "ward_cod": ""})
        for r in crows:
            key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
            w = by_ward[key]
            if r["status"] == "primary":
                w["primary"] += 1
            ward_cod = r.get("admin3_cod_name")
            if ward_cod and ward_cod != "NA":
                w["ward_cod"] = ward_cod
        for (state, lga, ward), w in by_ward.items():
            ward_records.append({
                "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": w["ward_cod"],
                "Pop Type": pop_type_norm, "Target HHs (primary)": w["primary"],
            })

    agg = defaultdict(lambda: {"non_idp": 0, "idp": 0, "target_hh": 0, "ward_cod": ""})
    for r in ward_records:
        key = (r["State"], r["LGA"], r["Ward (GRID3)"])
        a = agg[key]
        if r["Pop Type"] == "Non-IDP":
            a["non_idp"] += 1
        else:
            a["idp"] += 1
        a["target_hh"] += r["Target HHs (primary)"]
        a["ward_cod"] = r["Ward (OCHA/COD)"]

    out = {}
    for (state, lga, ward), a in agg.items():
        other_lgas = [l for l in ward_to_lgas.get((state, ward), [lga]) if l != lga]
        out[(state, lga, ward)] = {
            "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": a["ward_cod"],
            "Ward spans multiple LGAs (Y/N)": "Yes" if other_lgas else "No",
            "Other LGA(s) sharing this ward": "; ".join(other_lgas),
            "Note": MULTI_LGA_WARD_NOTE if other_lgas else "",
            "Non-IDP clusters": a["non_idp"], "IDP clusters": a["idp"], "Total target HHs (primary)": a["target_hh"],
        }
    return out


def write_input_sheet(wb, sheet_name, columns, rows, filled_flags):
    """Same technique as 01_generate_accessibility_reports.py's
    add_input_sheet() - rebuilds real DataValidation + Table + styling on
    THIS workbook, rather than attempting to copy validation objects across
    workbooks (which openpyxl doesn't do via plain cell iteration - the
    actual root cause of v1's missing-dropdown bug)."""
    ws = wb.create_sheet(sheet_name)
    ws.append(columns)
    for c, col_name in enumerate(columns, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL_INPUT if col_name in INPUT_COLUMNS else HEADER_FILL

    for row in rows:
        ws.append([row.get(c, "") for c in columns])

    n_rows = len(rows)
    accessible_col = columns.index("Accessible (Y/N)") + 1
    reason_col = columns.index("Reason category") + 1
    dv_access = DataValidation(type="list", formula1=f'"{",".join(ACCESSIBLE_OPTIONS)}"', allow_blank=True)
    dv_reason = DataValidation(type="list", formula1=f'"{",".join(REASON_OPTIONS)}"', allow_blank=True)
    ws.add_data_validation(dv_access)
    ws.add_data_validation(dv_reason)
    dv_access.add(f"{get_column_letter(accessible_col)}2:{get_column_letter(accessible_col)}{n_rows + 1}")
    dv_reason.add(f"{get_column_letter(reason_col)}2:{get_column_letter(reason_col)}{n_rows + 1}")

    # Highlight rows FACT hasn't answered yet (the 189 previously-missing
    # wards) so they're immediately visible as "still needs input", not just
    # blank cells easy to miss.
    for i, filled in enumerate(filled_flags, start=2):
        if not filled:
            for c in range(1, len(columns) + 1):
                ws.cell(row=i, column=c).fill = NEEDS_INPUT_FILL

    ws.freeze_panes = "A2"
    for i, col_name in enumerate(columns, start=1):
        ws.column_dimensions[get_column_letter(i)].width = max(14, min(30, len(col_name) + 4))
    if n_rows:
        tbl = Table(displayName=sheet_name.replace(" ", ""), ref=f"A1:{get_column_letter(len(columns))}{n_rows + 1}")
        tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws.add_table(tbl)
    return ws


def main():
    src_wb = openpyxl.load_workbook(FACT_RETURNED, data_only=True)

    # ---- Merge full universe with FACT's own (corrected) submitted answers ----
    universe = build_fact_full_universe()
    ward_headers = [c.value for c in src_wb["Ward Accessibility"][1]]
    ward_idx = {h: i for i, h in enumerate(ward_headers)}
    submitted_rows = list(src_wb["Ward Accessibility"].iter_rows(min_row=2, values_only=True))

    # "Answered" = Accessible OR Reason category actually filled in - same
    # rule 02_ingest_accessibility_reports.py uses to decide whether a row is
    # a real report vs an untouched template row. NOT the same as "a row for
    # this ward exists in the sheet": the template pre-fills State/LGA/Ward/
    # target-HH for every assigned ward before it's ever sent out, so a row
    # can be present with those reference columns populated while FACT never
    # actually answered it. v1 of this script conflated the two (used mere
    # row-presence as "answered"), which wrongly marked 110 genuinely-
    # unanswered wards as done and skipped shading them - caught by the
    # 2026-08-26 sanity check, fixed here.
    merged_ward_rows = []
    filled_flags = []
    submitted_keys = set()
    for row in submitted_rows:
        key = (row[ward_idx["State"]], row[ward_idx["LGA"]], row[ward_idx["Ward (GRID3)"]])
        if not any(key):
            continue
        submitted_keys.add(key)
        base = universe.get(key, {c: row[ward_idx[c]] if c in ward_idx else "" for c in WARD_COLUMNS[:10]})
        merged = dict(base)
        for col in ["Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported"]:
            merged[col] = row[ward_idx[col]] if col in ward_idx else ""
        merged_ward_rows.append(merged)
        answered = bool(merged["Accessible (Y/N)"]) or bool(merged["Reason category"])
        filled_flags.append(answered)

    absent_keys = sorted(set(universe.keys()) - submitted_keys)
    for key in absent_keys:
        merged = dict(universe[key])
        for col in ["Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported"]:
            merged[col] = ""
        merged_ward_rows.append(merged)
        filled_flags.append(False)

    # Sort: already-answered rows first (grouped by State/LGA as before), then
    # the still-needs-input rows at the end, grouped the same way - keeps the
    # "needs attention" rows together and easy to filter/scroll to, rather
    # than scattered alphabetically among 878 already-done rows.
    combined = sorted(zip(merged_ward_rows, filled_flags), key=lambda pair: (
        not pair[1], pair[0]["State"], pair[0]["LGA"], -pair[0]["Total target HHs (primary)"], pair[0]["Ward (GRID3)"]
    ))
    merged_ward_rows = [c[0] for c in combined]
    filled_flags = [c[1] for c in combined]
    absent_key_set = set(absent_keys)
    needs_input = [
        (row["State"], row["LGA"], row["Ward (GRID3)"],
         "Not in your original submission" if (row["State"], row["LGA"], row["Ward (GRID3)"]) in absent_key_set
         else "In your submission, but Accessible/Reason left blank")
        for row, filled in zip(merged_ward_rows, filled_flags) if not filled
    ]

    # ---- Cluster Accessibility: same submitted data, dropdowns rebuilt ----
    cluster_headers = [c.value for c in src_wb["Cluster Accessibility"][1]]
    cluster_idx = {h: i for i, h in enumerate(cluster_headers)}
    cluster_rows_out = []
    for row in src_wb["Cluster Accessibility"].iter_rows(min_row=2, values_only=True):
        if not any(row):
            continue
        cluster_rows_out.append({c: row[cluster_idx[c]] if c in cluster_idx else "" for c in CLUSTER_COLUMNS})

    out_wb = openpyxl.Workbook()
    out_wb.remove(out_wb.active)

    n_answered = sum(filled_flags)
    n_needs_input = len(filled_flags) - n_answered
    n_absent = len(absent_keys)
    n_blank_in_file = n_needs_input - n_absent

    readme = out_wb.create_sheet("README")
    readme.column_dimensions["A"].width = 105
    lines = [
        ("FACT - NGA MSNA 2026 accessibility submission, cleaned + complete + issues to review", True),
        ("", False),
        (f"Ward Accessibility now contains your FULL assigned universe ({len(merged_ward_rows)} wards) - "
         f"{n_answered} you already answered (with the corrections described in our email applied), plus "
         f"{n_needs_input} still needing input: {n_absent} weren't in your original submission at all, and "
         f"{n_blank_in_file} were present in your file but Accessible/Reason were left blank. All "
         f"{n_needs_input} are shaded and sorted to the bottom of the sheet so they're easy to find.", False),
        ("Please fill in the highlighted rows and send the whole file back - same format, same dropdowns, "
         "as your original template.", False),
        ("", False),
        ("SHEETS", True),
        (f"Ward Accessibility - your main sheet. {n_answered} rows already answered (corrections applied, see", False),
        (f"the Issues to Review tab), {n_needs_input} rows still blank and shaded - please complete these.", False),
        ("Cluster Accessibility - your original cluster-level submission, unchanged, same dropdowns restored.", False),
        ("Issues to Review - four sections: corrected contradictions, corrected blank-Accessible rows, the", False),
        (f"{n_needs_input} wards needing input (also visible directly on the Ward Accessibility sheet, shaded,", False),
        ("split into never-submitted vs submitted-but-blank), and the LGAs discussed on today's call where", False),
        ("reported accessibility is close to zero.", False),
    ]
    for i, (line, bold) in enumerate(lines, start=1):
        cell = readme.cell(row=i, column=1, value=line)
        if bold:
            cell.font = Font(bold=True, size=13 if i == 1 else 11)

    write_input_sheet(out_wb, "Ward Accessibility", WARD_COLUMNS, merged_ward_rows, filled_flags)
    write_input_sheet(out_wb, "Cluster Accessibility", CLUSTER_COLUMNS, cluster_rows_out, [True] * len(cluster_rows_out))

    # ---- Issues to Review ----
    issues_ws = out_wb.create_sheet("Issues to Review")
    r = 1

    def banner(text, fill=ISSUE_FILL):
        nonlocal r
        cell = issues_ws.cell(row=r, column=1, value=text)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = fill
        issues_ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=6)
        r += 1

    def table_header(cols):
        nonlocal r
        for c, col in enumerate(cols, start=1):
            cell = issues_ws.cell(row=r, column=c, value=col)
            cell.font = Font(bold=True)
            cell.fill = PatternFill("solid", fgColor="E7EAE8")
        r += 1

    banner("1. Corrected: marked Accessible=Yes but notes described insecurity (flipped to No)")
    table_header(["State", "LGA", "Ward (GRID3)", "Original notes (preserved)"])
    for row in submitted_rows:
        key = (row[ward_idx["State"]], row[ward_idx["LGA"]], row[ward_idx["Ward (GRID3)"]])
        if key in CONTRADICTION_KEYS:
            issues_ws.cell(row=r, column=1, value=key[0])
            issues_ws.cell(row=r, column=2, value=key[1])
            issues_ws.cell(row=r, column=3, value=key[2])
            issues_ws.cell(row=r, column=4, value=row[ward_idx["Reason notes"]])
            for c in range(1, 5):
                issues_ws.cell(row=r, column=c).fill = LIGHT_ISSUE
            r += 1
    r += 1

    banner("2. Corrected: a reason was given but Accessible was left blank (set to No)")
    table_header(["State", "LGA", "Ward (GRID3)", "Reason category", "Reason notes"])
    for row in submitted_rows:
        key = (row[ward_idx["State"]], row[ward_idx["LGA"]], row[ward_idx["Ward (GRID3)"]])
        if key in PARTIAL_KEYS:
            issues_ws.cell(row=r, column=1, value=key[0])
            issues_ws.cell(row=r, column=2, value=key[1])
            issues_ws.cell(row=r, column=3, value=key[2])
            issues_ws.cell(row=r, column=4, value=row[ward_idx["Reason category"]])
            issues_ws.cell(row=r, column=5, value=row[ward_idx["Reason notes"]])
            for c in range(1, 6):
                issues_ws.cell(row=r, column=c).fill = LIGHT_ISSUE
            r += 1
    r += 1

    banner(f"3. Wards needing input on the Ward Accessibility sheet ({len(needs_input)} total - shaded there too)")
    table_header(["State", "LGA", "Ward (GRID3)", "Why it needs input"])
    for state, lga, ward, why in needs_input:
        issues_ws.cell(row=r, column=1, value=state)
        issues_ws.cell(row=r, column=2, value=lga)
        issues_ws.cell(row=r, column=3, value=ward)
        issues_ws.cell(row=r, column=4, value=why)
        for c in range(1, 5):
            issues_ws.cell(row=r, column=c).fill = LIGHT_WARN
        r += 1
    r += 1

    banner("4. Agreed in today's call: please re-verify these LGAs (population accessible is close to zero)", WARN_FILL)
    table_header(["State", "LGA", "% of population still accessible", "% of area still accessible",
                  "Total clusters", "Clusters still accessible"])
    lga_wb = openpyxl.load_workbook(LGA_SUMMARY_SOURCE, data_only=True)
    lga_ws = lga_wb["LGA Summary"]
    lga_headers = [c.value for c in lga_ws[1]]
    lga_idx = {h: i for i, h in enumerate(lga_headers)}
    severe = []
    for row in lga_ws.iter_rows(min_row=2, values_only=True):
        covering = row[lga_idx["Partners covering"]] or ""
        if "FACT" in covering and row[lga_idx["% population remaining"]] < SEVERE_LGA_THRESHOLD:
            severe.append(row)
    severe.sort(key=lambda row: row[lga_idx["% population remaining"]])
    for row in severe:
        issues_ws.cell(row=r, column=1, value=row[lga_idx["State"]])
        issues_ws.cell(row=r, column=2, value=row[lga_idx["LGA"]])
        issues_ws.cell(row=r, column=3, value=round(row[lga_idx["% population remaining"]], 1))
        issues_ws.cell(row=r, column=4, value=round(row[lga_idx["% area remaining"]], 1))
        issues_ws.cell(row=r, column=5, value=row[lga_idx["Total clusters"]])
        issues_ws.cell(row=r, column=6, value=row[lga_idx["Updated clusters (accessible)"]])
        for c in range(1, 7):
            issues_ws.cell(row=r, column=c).fill = LIGHT_WARN
        r += 1

    for c in range(1, 7):
        issues_ws.column_dimensions[get_column_letter(c)].width = 20
    issues_ws.column_dimensions["D"].width = 34

    out_wb.save(OUT_PATH)
    print(f"Ward Accessibility: {len(merged_ward_rows)} rows total ({n_answered} already answered, "
          f"{n_needs_input} still need input = {n_absent} never submitted + {n_blank_in_file} submitted-but-blank)")
    print(f"Cluster Accessibility: {len(cluster_rows_out)} rows")
    print(f"Corrected contradictions: {len(CONTRADICTION_KEYS)}")
    print(f"Corrected blank-Accessible rows: {len(PARTIAL_KEYS)}")
    print(f"Severe LGAs flagged (<{SEVERE_LGA_THRESHOLD}% pop remaining): {len(severe)}")
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
