# ==============================================================================
# Builds NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx from the state stashed
# by analysis_partner_coverage.py - the FULL sampling frame (Sampling Frame +
# Strata-Level Summary, unchanged plus coverage_status/exclusion_reason),
# a Coverage Summary sheet, and a README with before/after figures.
#
# Mirrors 07_build_workbook.py's style (colors, table styling) but is its own
# script since this is a new coverage-layer deliverable, not a change to the
# frozen pipeline's own workbook builder.
# ==============================================================================
import csv
import pickle

import openpyxl
from openpyxl.worksheet.table import Table, TableStyleInfo
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
OUT_DIR = PROJECT_DIR + r"\output\analysis_partner_coverage"
OUT_PATH = OUT_DIR + r"\NGA_MSNA_2026_sampling_frame_workbook_v2.xlsx"

with open(OUT_DIR + r"\_pipeline_state.pkl", "rb") as f:
    state = pickle.load(f)

NAVY, BLUE, GREEN, WHITE = "1B2A4A", "2C5F8A", "1F7A5C", "FFFFFF"
AMBER, RED, MINT = "FFF2CC", "F4CCCC", "D5F0E3"

wb = openpyxl.Workbook()
wb.remove(wb.active)


# ---------------------------------------------------------------------------
# Helper: write a list-of-dicts sheet as a styled table
# ---------------------------------------------------------------------------
def write_sheet(name, rows, fieldnames, header_color, note, bool_cols=(), highlight=None):
    ws = wb.create_sheet(name)
    ws["A1"] = f"{name} — see README tab for column definitions"
    ws["A1"].font = Font(bold=True, italic=True, size=10, color="595959")
    ws["A2"] = note
    ws["A2"].font = Font(italic=True, size=9, color="7F7F7F")
    start_row = 4
    for i, h in enumerate(fieldnames, start=1):
        ws.cell(row=start_row, column=i, value=h)
    for i, r in enumerate(rows, start=start_row + 1):
        for j, h in enumerate(fieldnames, start=1):
            v = r.get(h, "")
            if h in bool_cols:
                v = True if v == "TRUE" else (False if v == "FALSE" else v)
            ws.cell(row=i, column=j, value=v)
    last_row = start_row + len(rows)
    last_col = get_column_letter(len(fieldnames))
    tbl = Table(displayName=name.replace(" ", "").replace("-", "")[:30], ref=f"A{start_row}:{last_col}{last_row}")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)
    for i in range(1, len(fieldnames) + 1):
        ws.column_dimensions[get_column_letter(i)].width = 16
    if highlight:
        col_idx = fieldnames.index(highlight[0]) + 1
        col_letter = get_column_letter(col_idx)
        rule = FormulaRule(formula=[f'${col_letter}{start_row + 1}="{highlight[1]}"'], fill=PatternFill("solid", fgColor=highlight[2]))
        ws.conditional_formatting.add(f"A{start_row + 1}:{last_col}{last_row}", rule)
    print(f"Wrote sheet '{name}': {len(rows)} rows")
    return ws


write_sheet(
    "Strata-Level Summary (FULL)", state["full_strata"], state["strata_fieldnames"],
    NAVY, "Strata-Level Summary, unchanged from the live frame, plus coverage_status/exclusion_reason. One row per (pop_type x LGA) stratum. The household-level Sampling Frame (86,394 rows, FULL and WORKING) is delivered as separate CSVs alongside this workbook, not embedded here, for file-size/performance reasons - see NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv / _WORKING.csv.",
    bool_cols={"certainty_stratum", "excluded_infeasible"},
    highlight=("coverage_status", "not_covered", RED),
)

coverage_fieldnames = ["region", "state", "lga", "adm2_pcode", "coverage_status", "match_method", "exclusion_reason"]
ws_cov = write_sheet(
    "Coverage Summary", state["coverage_summary_rows"], coverage_fieldnames,
    GREEN, "One row per LGA (323 total) - for ToR narrative use. match_method: 'exact' = matched cleanly by name; 'proposed' = a name-variant reconciliation, confirmed by user 2026-07-30; 'no_data_treated_as_not_covered' = LGA absent from the coverage file entirely (Kano only), confirmed treated as not_covered by user 2026-07-30 (highlighted amber below for audit visibility, even though it now carries the same coverage_status as an ordinary declined LGA).",
    highlight=("coverage_status", "not_covered", RED),
)
# Second highlight: Kano's state-wide-gap rows, distinct from an ordinary
# in-file "not covered" row, for audit traceability - write_sheet() only
# wires up one rule, so this is added directly on the returned worksheet.
_last_row = 4 + len(state["coverage_summary_rows"])
_last_col = get_column_letter(len(coverage_fieldnames))
_method_col = get_column_letter(coverage_fieldnames.index("match_method") + 1)
ws_cov.conditional_formatting.add(
    f"A5:{_last_col}{_last_row}",
    FormulaRule(formula=[f'${_method_col}5="no_data_treated_as_not_covered"'], fill=PatternFill("solid", fgColor=AMBER)),
)


# ---------------------------------------------------------------------------
# README
# ---------------------------------------------------------------------------
def write_readme():
    ws = wb.create_sheet("README", 0)
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 16
    ws.column_dimensions["C"].width = 16
    ws.column_dimensions["D"].width = 16
    ws.column_dimensions["E"].width = 16
    ws.column_dimensions["F"].width = 16
    row = 1

    def title(text, size=16):
        nonlocal row
        c = ws.cell(row=row, column=1, value=text)
        c.font = Font(bold=True, size=size, color=NAVY)
        row += 2

    def subhead(text, color=BLUE):
        nonlocal row
        c = ws.cell(row=row, column=1, value=text)
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
        c.font = Font(bold=True, size=12, color=WHITE)
        c.fill = PatternFill("solid", fgColor=color)
        for col in range(2, 7):
            ws.cell(row=row, column=col).fill = PatternFill("solid", fgColor=color)
        row += 1

    def para(text, height=45):
        nonlocal row
        c = ws.cell(row=row, column=1, value=text)
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
        c.alignment = Alignment(wrap_text=True, vertical="top")
        ws.row_dimensions[row].height = height
        c.font = Font(size=11)
        row += 2

    def table_header(cols):
        nonlocal row
        for i, h in enumerate(cols, start=1):
            c = ws.cell(row=row, column=i, value=h)
            c.font = Font(bold=True, size=10, color=WHITE)
            c.fill = PatternFill("solid", fgColor=NAVY)
        row += 1

    def table_row(vals, bold_last=False):
        nonlocal row
        for i, v in enumerate(vals, start=1):
            c = ws.cell(row=row, column=i, value=v)
            if bold_last and i == len(vals):
                c.font = Font(bold=True)
        row += 1

    title("NGA MSNA 2026 — Sampling Frame + Partner Coverage Layer (v2)")
    para(
        "This workbook adds a partner-coverage layer on top of the live, HQ-approved sampling "
        "frame (verified current as of this build - Non-IDP/IDP terminology, 28-strata minimal-"
        "supplementary-cluster correction at m=6 throughout, 18 certainty strata excluded under "
        "the projected-MoE rule). It does NOT change the underlying design - it adds two columns "
        "(coverage_status, exclusion_reason) so the frame can be filtered to what partners have "
        "actually confirmed they can cover, while keeping the full original frame intact and "
        "re-derivable from if coverage changes again.",
        height=75,
    )
    para(
        "FULL vs WORKING: this workbook's 'Strata-Level Summary (FULL)' sheet is the complete, "
        "unchanged original strata frame plus the two new columns - the reusable master. The "
        "household-level Sampling Frame (86,394 rows) is too large to embed usefully here and is "
        "delivered as separate FULL/WORKING CSVs alongside this workbook. WORKING (both levels) is "
        "the subset where coverage_status = 'covered' AND exclusion_reason = 'none' - i.e. what can "
        "actually be fielded today. Re-deriving WORKING from FULL is always a filter, not a rebuild.",
        height=60,
    )

    subhead("KEY FINDING: national sample drops ~40% after the coverage cut")
    row += 1
    para(
        "Applying confirmed partner coverage removes more than a third of the previously-planned "
        "sample nationally - largely driven by North-Central, where only 18 of 99 LGAs are "
        "currently covered by a confirmed partner. See the before/after table below.",
        height=30,
    )

    subhead("Region-level summary: BEFORE vs AFTER coverage cut")
    row += 1
    table_header(["Region", "LGAs", "Clusters", "Sample: Non-IDP", "Sample: IDP", "Total Sample"])
    for r in ["NC", "NE", "NW"]:
        b = state["before_rows_by_region"][r]
        table_row(["  " + b["region"] + " (before)", b["lgas"], b["clusters"], b["sample_non_idp"], b["sample_idp"], b["sample_non_idp"] + b["sample_idp"]])
        a = state["after_rows_by_region"][r]
        table_row(["  " + a["region"] + " (after)", a["lgas"], a["clusters"], a["sample_non_idp"], a["sample_idp"], a["sample_non_idp"] + a["sample_idp"]], bold_last=True)
    nb, na = state["nat_before"], state["nat_after"]
    table_row(["National Total (before)", nb["lgas"], nb["clusters"], nb["sample_non_idp"], nb["sample_idp"], nb["sample_non_idp"] + nb["sample_idp"]])
    r_ = ws.cell(row=row, column=1, value="National Total (after)")
    r_.font = Font(bold=True)
    table_row(["National Total (after)", na["lgas"], na["clusters"], na["sample_non_idp"], na["sample_idp"], na["sample_non_idp"] + na["sample_idp"]], bold_last=True)
    row += 1

    subhead("Per-region LGA counts (not mutually exclusive)")
    row += 1
    para(
        "An LGA can appear in more than one count below (e.g. not covered by a partner AND "
        "has a certainty-excluded IDP stratum) - these are separate tallies, not a partition.",
        height=30,
    )
    table_header(["Region", "Total LGAs", "Covered", "Excluded: coverage", "Excluded: certainty stratum", "State-wide gap (folded into 'coverage')"])
    for r in ["NC", "NE", "NW"]:
        c = state["region_lga_counts"][r]
        table_row([state["before_rows_by_region"][r]["region"], c["total_lgas"], c["covered"], c["excluded_for_coverage"], c["excluded_for_certainty"], c["unresolved_no_coverage_data"]])
    row += 1

    subhead("Overlap: LGAs excluded for BOTH coverage and certainty-stratum reasons", AMBER)
    row += 1
    para(
        "3 LGAs nationally have their IDP stratum already excluded under the certainty-stratum "
        "projected-MoE rule (Section A1.5) AND no partner covering the LGA at all: Niger/Katcha, "
        "Niger/Lapai (North-Central), and Kaduna/Markafi (North-West). See each row's "
        "exclusion_reason in the Strata-Level Summary sheet for the exact combination.",
        height=30,
    )

    subhead("Kano State (44 LGAs): confirmed not_covered, not a data gap", RED)
    row += 1
    para(
        "Kano State is entirely absent from the partner coverage file's North-West sheet (which "
        "covers Sokoto/Zamfara/Katsina/Kaduna/Kebbi but not Kano) - not a naming mismatch. Per "
        "explicit user confirmation (2026-07-30): \"Kano is a completely excluded state, no partner "
        "is wanting to cover it, and therefore should be treated same as others not included.\" All "
        "44 Kano LGAs are therefore coverage_status = 'not_covered', exclusion_reason = "
        "'partner_coverage_declined' - the same as any other explicitly-declined LGA, distinguished "
        "only by match_method = 'no_data_treated_as_not_covered' in the Coverage Summary sheet for "
        "audit purposes. Kano also already has 14 IDP LGAs excluded for the separate, unrelated "
        "certainty-stratum reason.",
        height=75,
    )

    subhead("Name-variant reconciliations (10) - confirmed by user 2026-07-30", MINT)
    row += 1
    table_header(["Coverage-file text", "State", "Matched to (sampling frame)", "Count value"])
    for r in state["proposed_applied"]:
        table_row([r["lga"], r["state"], r["proposed_master_name"], str(r["count_raw"])])
    row += 1

    subhead("Column definitions (new columns only)")
    row += 1
    table_header(["Column", "Definition"])
    table_row(["coverage_status", "'covered' / 'not_covered' (from the partner coverage file's COUNT column, or the LGA is absent from the coverage file entirely - state-wide gaps are folded into 'not_covered' per explicit user confirmation, see Kano note above)."])
    table_row(["exclusion_reason", "'none', or any of: partner_coverage_declined, certainty_stratum_below_moe_threshold - joined with '; ' if both apply. A stratum is in the WORKING frame only if exclusion_reason = 'none' AND coverage_status = 'covered'."])
    table_row(["match_method (Coverage Summary sheet only)", "'exact' = matched by normalized name directly; 'proposed' = matched via a manually-reviewed name-variant reconciliation, confirmed by the user (see above); 'no_data_treated_as_not_covered' = LGA absent from the coverage file entirely (Kano only), confirmed treated as not_covered."])

    ws.freeze_panes = "A1"


write_readme()
wb.active = 0
wb.save(OUT_PATH)
print(f"\nSaved: {OUT_PATH}")
