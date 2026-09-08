# ==============================================================================
# Builds FACT's follow-up accessibility workbook, 2026-09-07 - same shape as
# build_fact_followup_workbook_2026-09-03.py (send back the FULL current
# assignment, everything already correct left untouched, only genuinely
# uncertain rows shaded amber with a plain-English reason). Rebuilt from
# scratch for this round rather than reusing the Sep-3 script directly, since
# this project's convention is standalone dated scripts, and the source data
# this time comes straight from 01_generate_accessibility_reports.py's own
# current-frame logic + analysis_review_returned_reports.py's QA findings,
# not a bespoke R reconciliation pass.
#
# What's flagged this round, and why (see CLAUDE.md "Update 2026-09-08c" /
# its addendum for the full investigation):
#   - 23 CONTRADICTION rows - Accessible=Yes with a note that reads like an
#     active access problem (or Accessible=No with an empty-sounding reason).
#     Two whole-LGA clusters (Faskari x5, Arewa-Dandi x4) share one identical
#     note across every ward in the LGA - almost certainly the same
#     underlying report copy-pasted per ward, genuinely worth FACT rechecking
#     rather than us guessing which field (Yes/No, or the note) is stale.
#   - 51 rows never reported at all - wards now in FACT's current assignment
#     (this week's resampling added ~58 net new wards) that their last
#     return simply doesn't cover yet.
# Everything else (827 of 901 current wards) is carried forward exactly as
# FACT last told us - no flag, no action needed, explicitly says so.
#
# Deliberately NOT included here: the 74 wards that were EXTRA in FACT's
# return relative to what we'd sent them (69 currently-Inaccessible legacy
# rows + 5 older drops) - those aren't a question for FACT, they're the
# FACT legacy-gap fix's own input, handled separately.
# ==============================================================================
import csv
import os
import sys
from collections import defaultdict
from datetime import date, datetime
from importlib import import_module

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
gen = import_module("01_generate_accessibility_reports")
rev = import_module("analysis_review_returned_reports")

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
OUT_DIR = PROJECT_DIR + r"\resampling\output\resample_runs\FACT\2026-09-07"
OUT_PATH = OUT_DIR + r"\FACT_accessibility_followup_2026-09-07.xlsx"

HEADER_FILL_REF = PatternFill("solid", fgColor="1B2A4A")
HEADER_FILL_INPUT = PatternFill("solid", fgColor="2C5F8A")
NEEDS_INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
ACCESSIBLE_OPTIONS = ["Yes", "No"]
REASON_OPTIONS = [
    "N/A - fully accessible", "Insecurity / conflict", "Physical access (terrain, flooding, roads)",
    "Population absent / relocated", "Building-footprint issue (no eligible structures)",
    "Access denied by authorities / community", "Other",
]
DATE_REPORTED_MIN = date(2026, 7, 1)

WARD_COLUMNS = ["State", "LGA", "Ward (GRID3)", "Ward (OCHA/COD)", "Non-IDP clusters", "IDP clusters",
                "Total target HHs (primary)", "Accessible (Y/N)", "Reason category", "Reason notes",
                "Date reported", "Needs your input?", "Why flagged"]
INPUT_COLUMNS = {"Accessible (Y/N)", "Reason category", "Reason notes", "Date reported"}
SUBCONTRACTOR_COLUMNS = ["Subcontracted / government partner name", "State", "LGA(s) covered",
                          "Ward(s) covered (leave blank if the whole LGA)", "Contact person (if available)", "Notes"]

# Human-readable "why flagged" text per finding, keyed the same way the
# CONTRADICTION cluster groups naturally fall out of analysis_review_
# returned_reports.py's findings - written once per cluster rather than
# per-row so five near-identical Faskari rows don't read as five different
# complaints.
WHY_FLAGGED_CONTRADICTION_ACCESS_NO_REASON = (
    "You marked this ward Accessible=No, but the Reason category is "
    "'N/A - fully accessible', which doesn't fit a No answer. Please pick "
    "the actual reason from the dropdown (or change Accessible to Yes if "
    "No was the mistake)."
)
WHY_FLAGGED_CONTRADICTION_ACCESS_YES_NOTE = (
    "You marked this ward Accessible=Yes, but your own notes describe what "
    "reads like an active access problem (quoted below). Please confirm "
    "Yes is correct, or change it to No if the notes are the current, "
    "accurate picture."
)
WHY_FLAGGED_PARTIAL = (
    "Your notes describe partial access (some parts of the ward accessible, "
    "some not) - our sheet only has a single Yes/No per ward. Please tell "
    "us which answer better reflects where most of your target sample "
    "actually is, and we'll note the partial-access detail alongside it."
)
WHY_FLAGGED_NEVER_REPORTED = (
    "New to your assignment since this week's resampling update - this "
    "ward wasn't in your last report at all. Please add Accessible (Y/N) "
    "and a reason."
)


def build_contradiction_flags(findings):
    """{(state,lga,ward): why_flagged_text} for every CONTRADICTION/PARTIAL-
    access finding relevant to this follow-up. Parses the same finding
    strings review_partner() already produces rather than re-deriving the
    logic - see that function for the actual detection rules."""
    flags = {}
    for f in findings:
        if not f.startswith("CONTRADICTION"):
            continue
        # "CONTRADICTION: State/LGA/Ward - marked ..."
        body = f[len("CONTRADICTION: "):]
        loc, _, rest = body.partition(" - ")
        state, lga, ward = loc.split("/", 2)
        key = (state, lga, ward)
        if "Reason category is 'N/A - fully accessible'" in rest:
            flags[key] = WHY_FLAGGED_CONTRADICTION_ACCESS_NO_REASON
        elif "some part" in rest.lower() or "inacceesible" in rest.lower() and "some" in rest.lower():
            flags[key] = WHY_FLAGGED_PARTIAL
        else:
            flags[key] = WHY_FLAGGED_CONTRADICTION_ACCESS_YES_NOTE
    # The one genuinely partial-access row (Bayamari) reads like a plain
    # access-problem note under the generic parse above (it does say
    # "inacceesible"), which is fine content-wise but the more specific
    # partial-access framing is more useful to FACT than the generic one -
    # override it explicitly rather than lean on brittle keyword sniffing.
    flags[("Yobe", "Bursari", "Bayamari")] = WHY_FLAGGED_PARTIAL
    return flags


def read_returned_ward_answers(path):
    """{(state,lga,ward): {Accessible, Reason category, Reason notes, Date
    reported}} - FACT's own last-reported values, carried forward as-is for
    every row that isn't flagged."""
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb["Ward Accessibility"]
    headers = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
    idx = {h: i for i, h in enumerate(headers) if h}
    out = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        if all(v is None for v in row):
            continue
        state, lga, ward = row[idx["State"]], row[idx["LGA"]], row[idx["Ward (GRID3)"]]
        if not (state and lga and ward):
            continue
        out[(state, lga, ward)] = {
            "Accessible (Y/N)": row[idx.get("Accessible (Y/N)")] if "Accessible (Y/N)" in idx else None,
            "Reason category": row[idx.get("Reason category")] if "Reason category" in idx else None,
            "Reason notes": row[idx.get("Reason notes")] if "Reason notes" in idx else None,
            "Date reported": row[idx.get("Date reported")] if "Date reported" in idx else None,
        }
    wb.close()
    return out


def write_ward_sheet(wb, ward_rows, answers, flags):
    ws = wb.create_sheet("Ward Accessibility")
    ws.append(WARD_COLUMNS)
    for c, col_name in enumerate(WARD_COLUMNS, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL_INPUT if col_name in INPUT_COLUMNS else HEADER_FILL_REF

    n_flagged = 0
    for r in ward_rows:
        key = (r["State"], r["LGA"], r["Ward (GRID3)"])
        ans = answers.get(key, {})
        why = flags.get(key, "")
        date_reported = ans.get("Date reported")
        if isinstance(date_reported, datetime):
            date_reported = date_reported.date()
        vals = [
            r["State"], r["LGA"], r["Ward (GRID3)"], r.get("Ward (OCHA/COD)") or "",
            r["Non-IDP clusters"], r["IDP clusters"], r["Total target HHs (primary)"],
            ans.get("Accessible (Y/N)"), ans.get("Reason category"), ans.get("Reason notes"),
            date_reported, "Yes" if why else "", why,
        ]
        ws.append(vals)
        row_idx = ws.max_row
        if why:
            n_flagged += 1
            for c in range(1, len(WARD_COLUMNS) + 1):
                ws.cell(row=row_idx, column=c).fill = NEEDS_INPUT_FILL
            ws.cell(row=row_idx, column=WARD_COLUMNS.index("Reason notes") + 1).alignment = Alignment(wrap_text=True, vertical="top")
            ws.cell(row=row_idx, column=WARD_COLUMNS.index("Why flagged") + 1).alignment = Alignment(wrap_text=True, vertical="top")

    n_rows = len(ward_rows)
    access_col = WARD_COLUMNS.index("Accessible (Y/N)") + 1
    reason_col = WARD_COLUMNS.index("Reason category") + 1
    date_col = WARD_COLUMNS.index("Date reported") + 1
    dv_access = DataValidation(type="list", formula1=f'"{",".join(ACCESSIBLE_OPTIONS)}"', allow_blank=True)
    dv_reason = DataValidation(type="list", formula1=f'"{",".join(REASON_OPTIONS)}"', allow_blank=True)
    dv_date = DataValidation(type="date", operator="between", formula1=DATE_REPORTED_MIN, formula2=date.today(),
                              allow_blank=True, showErrorMessage=True, errorTitle="Invalid date",
                              error=f"Enter a real date between {DATE_REPORTED_MIN:%d %b %Y} and today.")
    ws.add_data_validation(dv_access)
    ws.add_data_validation(dv_reason)
    ws.add_data_validation(dv_date)
    dv_access.add(f"{get_column_letter(access_col)}2:{get_column_letter(access_col)}{n_rows + 1}")
    dv_reason.add(f"{get_column_letter(reason_col)}2:{get_column_letter(reason_col)}{n_rows + 1}")
    dv_date.add(f"{get_column_letter(date_col)}2:{get_column_letter(date_col)}{n_rows + 1}")
    for row_idx in range(2, n_rows + 2):
        ws.cell(row=row_idx, column=date_col).number_format = "dd-mmm-yyyy"

    ws.freeze_panes = "A2"
    widths = {"Reason notes": 40, "Why flagged": 44, "Ward (GRID3)": 20, "Ward (OCHA/COD)": 20}
    for i, col_name in enumerate(WARD_COLUMNS, start=1):
        ws.column_dimensions[get_column_letter(i)].width = widths.get(col_name, max(13, min(26, len(col_name) + 4)))
    tbl = Table(displayName="WardAccessibility", ref=f"A1:{get_column_letter(len(WARD_COLUMNS))}{n_rows + 1}")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)
    return n_flagged


def write_subcontractor_sheet(wb):
    ws = wb.create_sheet("Your Subcontracted Partners")
    ws.append(SUBCONTRACTOR_COLUMNS)
    for c, col_name in enumerate(SUBCONTRACTOR_COLUMNS, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL_INPUT
        ws.column_dimensions[get_column_letter(c)].width = 30
    # Carried forward from what FACT told us in their last return - please
    # confirm/correct rather than re-entering from scratch.
    known = [
        ("Conpad Initiatives", "Katsina", "Matazu", "Only two wards appear on the tool", "Rashidi Idi, +234 803 704 1482 / conpadinitiatives@gmail.com", ""),
        ("Conpad Initiatives", "Katsina", "Dandume", "Not on the tool", "", ""),
        ("Conpad Initiatives", "Katsina", "Faskari", "Not on the tool", "", "PLEASE CONFIRM: is Faskari's status Yes or No? Your Ward Accessibility rows for all 5 Faskari wards say Yes, but each has a 'Banditry and kidnappings' note - please clarify with Conpad which is current."),
        ("Linkgate", "Kebbi", "Fakai", "Mahuta 8 samples, Fakai kuka 3 samples", "linkgateforhumanity@gmail.com / +234 703 490 1610", ""),
        ("Linkgate", "Kebbi", "Ngaski", "Wara, Gain Baka, Utuwo", "", "PLEASE CONFIRM: is 'Utuwo' the same ward as 'Utono' in your Ward Accessibility sheet (Kebbi/Ngaski)? Spelling differs between the two sheets - want to make sure we're not treating one real ward as two."),
        ("Linkgate", "Kebbi", "Wasagu Danko", "Ribah/Machika 6 samples, Kyabu Kandu 2 samples", "", ""),
        ("Aim", "Zamfara", "Bukkuyum", "Bukkuyum 18, Kyaram 12, Nasarawa 12, Gurusu 6, Masama 18 samples collected", "Mustapha Ngamdu, mustaphalawanngamdu@gmail.com / +234 703 719 9578", ""),
        ("Aim", "Zamfara", "Gummi", "", "", ""),
    ]
    for row in known:
        ws.append(row)
    ws.freeze_panes = "A2"
    tbl = Table(displayName="SubcontractedPartners", ref=f"A1:{get_column_letter(len(SUBCONTRACTOR_COLUMNS))}{len(known)+1}")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)


def write_readme(wb, n_wards, n_flagged, n_contradiction, n_never_reported):
    ws = wb.create_sheet("README")
    ws.column_dimensions["A"].width = 108
    lines = [
        ("FACT - NGA MSNA 2026 - Accessibility follow-up (2026-09-07)", True, 14),
        ("", False, 11),
        ("WHAT THIS IS", True, 12),
        (f"This is your FULL current assignment - {n_wards} wards - reflecting everything as it stands today, "
         f"including this week's resampling update. {n_wards - n_flagged} of these already match what your team "
         f"told us and need no action. Only the {n_flagged} rows shaded amber need your input. Everything else can "
         "be left exactly as it is.", False, 11),
        ("", False, 11),
        ("WHY WE'RE ASKING AGAIN", True, 12),
        (f"Two things came up going through your last report in detail: ({n_contradiction}) a small number of wards "
         "where the Accessible answer and your own notes for that ward seem to disagree with each other, most often "
         "because the same note was entered for every ward in an LGA and the Yes/No wasn't updated to match it; and "
         f"({n_never_reported}) wards that are new to your assignment since this week's resampling and haven't been "
         "reported on yet. Neither is a criticism of your reporting - the first is an easy thing to miss across a "
         "large sheet, and the second simply didn't exist when you last reported.", False, 11),
        ("", False, 11),
        ("WHAT STILL NEEDS YOU", True, 12),
        ("1. Katsina/Faskari (5 wards) - all marked Yes with an identical 'Banditry and kidnappings' note. Faskari "
         "is also one of Conpad Initiatives' subcontracted areas per your own sheet - please confirm with them "
         "which answer is current.", False, 11),
        ("2. Kebbi/Arewa-Dandi (4 wards: Bachaka, Chibike, Kangiwa, Kuka) - all marked Yes with an identical note "
         "about a team evacuation after gunfire. Please confirm whether Yes is still correct.", False, 11),
        ("3. Kebbi/Fakai/Danko Maga (1 ward) - marked Yes, note describes ongoing banditry/Lakurawa activity "
         "(from your subcontracted partner's report).", False, 11),
        ("4. 5 wards marked No with Reason category 'N/A - fully accessible' (Borno/Guzamala/Monguno, Kebbi/"
         "Maiyama/Andarai, and 3 in Sokoto/Binji) - please pick the actual reason, or correct Accessible to Yes "
         "if No was the mistake.", False, 11),
        ("5. Yobe/Bursari/Bayamari (1 ward) - your notes describe partial access within the ward. Please tell us "
         "which answer better reflects most of your target sample there.", False, 11),
        ("6. Yobe/Geidam (7 wards) - all marked Yes with an identical note that they're 'currently inaccessible "
         "due to active presence of AOGs'. Please confirm whether Yes is still correct.", False, 11),
        (f"7. {n_never_reported} wards new to your assignment this week - never reported on yet, need Accessible "
         "(Y/N) and a reason. See the amber rows on the Ward Accessibility sheet.", False, 11),
        ("", False, 11),
        ("YOUR SUBCONTRACTED PARTNERS", True, 12),
        ("We've carried forward what you told us last time (Conpad Initiatives, Linkgate, Aim) - please just check "
         "it's still accurate and answer the two specific questions flagged in that sheet (Faskari's real status, "
         "and whether 'Utuwo' and 'Utono' are the same ward).", False, 11),
        ("", False, 11),
        ("SHEETS", True, 12),
        ("Ward Accessibility - your full current ward-level assignment. Amber rows need input.", False, 11),
        ("Your Subcontracted Partners - please review and confirm/complete.", False, 11),
    ]
    for i, (text, bold, size) in enumerate(lines, start=1):
        cell = ws.cell(row=i, column=1, value=text)
        cell.font = Font(bold=bold, size=size)
        cell.alignment = Alignment(wrap_text=True, vertical="top")
        if len(text) > 90:
            ws.row_dimensions[i].height = 16 + 14 * (len(text) // 90)


def main():
    ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas = gen.load_cluster_rows_by_partner()
    ward_rows = gen.build_ward_rows(ward_split_by_partner["FACT"], ward_to_lgas)

    returned_path = os.path.join(rev.RETURNED_DIR, "FACT_accessibility_report.xlsx")
    partner, findings, reported_wards, seen_wards = rev.review_partner(returned_path)
    answers = read_returned_ward_answers(returned_path)
    flags = build_contradiction_flags(findings)

    current_keys = {(r["State"], r["LGA"], r["Ward (GRID3)"]) for r in ward_rows}
    never_reported = current_keys - seen_wards
    for key in never_reported:
        flags.setdefault(key, WHY_FLAGGED_NEVER_REPORTED)

    n_contradiction = sum(1 for f in findings if f.startswith("CONTRADICTION"))
    n_never_reported = len(never_reported)

    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    n_flagged = write_ward_sheet(wb, ward_rows, answers, flags)
    write_subcontractor_sheet(wb)
    write_readme(wb, len(ward_rows), n_flagged, n_contradiction, n_never_reported)
    wb.move_sheet("README", offset=-len(wb.sheetnames))

    os.makedirs(OUT_DIR, exist_ok=True)
    wb.save(OUT_PATH)
    print(f"Wrote {OUT_PATH}")
    print(f"Ward Accessibility: {len(ward_rows)} rows, {n_flagged} flagged "
          f"({n_contradiction} contradiction, {n_never_reported} never-reported)")


if __name__ == "__main__":
    main()
