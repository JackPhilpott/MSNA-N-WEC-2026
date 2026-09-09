# ==============================================================================
# Builds <Partner>'s follow-up accessibility workbook - the partner's FULL
# current ward assignment, with everything already correct carried forward
# untouched, and only genuinely uncertain rows shaded amber with a plain-
# English reason. Generalizes build_fact_followup_workbook_2026-09-07.py
# (which hardcoded FACT-specific subcontractor/README content) into a
# reusable, self-deriving mechanism - every flag on every row is computed
# from this partner's own current frame + their own last return, nothing
# about which rows get flagged is hardcoded per partner.
#
# What gets flagged, always derived, never hardcoded:
#   - CONTRADICTION rows - analysis_review_returned_reports.py's own
#     review_partner() findings (Accessible=Yes with a note that reads like
#     an active access problem, or Accessible=No with an empty-sounding
#     reason, or a note describing partial access).
#   - Never-reported rows - wards in this partner's CURRENT frame that their
#     last return doesn't cover at all (new since a resample, or never sent
#     in the first place - both read the same way to this partner: "you've
#     never told us about this one").
# Everything else is carried forward exactly as the partner last told us -
# no flag, no action needed.
#
# Optional pre-fill: a partner sometimes tells us an answer for a specific
# ward through a channel other than the report itself (an email, a call).
# Pass --prefill <csv> (columns: State,LGA,Ward (GRID3),Reason notes) to
# stamp that into a never-reported row's Reason notes before it's sent back
# - saves the partner re-typing what they already told us, while still
# leaving Accessible/Reason category for them to confirm (never guessed on
# their behalf - see this project's "no silent discretion" rule).
#
# Deliberately NOT generalized: the subcontractor sheet (FACT-specific,
# stays in build_fact_followup_workbook_2026-09-07.py) - most partners don't
# have known subcontractors on record, and inventing an empty sheet asking
# about subcontractors nobody mentioned would be a solution looking for a
# problem, not a real need.
#
# Reads FULL, not WORKING, for the partner's ward universe - deliberately
# different from 01_generate_accessibility_reports.py's initial-ask default.
# A follow-up's whole purpose is catching drift since the last report,
# including a ward that was excluded (and so invisible to WORKING) when
# last asked but has since been reinstated - the same class of gap this
# project spent 2026-09-08 finding for Dandume/Faskari/Matazu/Musawa/Sabuwa.
# Asking from WORKING alone would silently never re-ask about exactly the
# wards most likely to have changed. Pass --working to use WORKING instead
# (matches the initial-ask script's scope) if a partner's follow-up should
# be scoped to their currently-fieldable assignment only.
#
# Usage: python build_partner_followup_workbook.py <PartnerName> <out_dir> [--prefill <csv>] [--working]
# ==============================================================================
import argparse
import csv
import os
import sys
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
    "New to your current assignment - this ward wasn't in your last report "
    "at all. Please add Accessible (Y/N) and a reason."
)


def build_contradiction_flags(findings):
    """{(state,lga,ward): why_flagged_text} for every CONTRADICTION/PARTIAL-
    access finding - parses the same finding strings review_partner() already
    produces rather than re-deriving the logic."""
    flags = {}
    for f in findings:
        if not f.startswith("CONTRADICTION"):
            continue
        body = f[len("CONTRADICTION: "):]
        loc, _, rest = body.partition(" - ")
        state, lga, ward = loc.split("/", 2)
        key = (state, lga, ward)
        if "Reason category is 'N/A - fully accessible'" in rest:
            flags[key] = WHY_FLAGGED_CONTRADICTION_ACCESS_NO_REASON
        elif "some part" in rest.lower() or ("some" in rest.lower() and "inacc" in rest.lower()):
            flags[key] = WHY_FLAGGED_PARTIAL
        else:
            flags[key] = WHY_FLAGGED_CONTRADICTION_ACCESS_YES_NOTE
    return flags


def read_returned_ward_answers(path):
    """{(state,lga,ward): {Accessible, Reason category, Reason notes, Date
    reported}} - the partner's own last-reported values, carried forward
    as-is for every row that isn't flagged. Empty dict if the partner has
    never returned a report at all."""
    if not os.path.exists(path):
        return {}
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


def read_prefill(path):
    """{(state,lga,ward): reason_notes_text} from an optional --prefill CSV -
    a ward a partner already told us about through some other channel
    (email, call). Only ever stamps Reason notes, never Accessible/Reason
    category - those stay for the partner to confirm themselves, not
    guessed on their behalf."""
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        return {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Reason notes"] for r in csv.DictReader(f)}


def write_ward_sheet(wb, ward_rows, answers, flags, prefill):
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
        reason_notes = ans.get("Reason notes")
        if key in prefill and not reason_notes:
            reason_notes = prefill[key]
        vals = [
            r["State"], r["LGA"], r["Ward (GRID3)"], r.get("Ward (OCHA/COD)") or "",
            r["Non-IDP clusters"], r["IDP clusters"], r["Total target HHs (primary)"],
            ans.get("Accessible (Y/N)"), ans.get("Reason category"), reason_notes,
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


def write_readme(wb, partner, n_wards, n_flagged, n_contradiction, n_never_reported, run_date):
    ws = wb.create_sheet("README")
    ws.column_dimensions["A"].width = 108
    lines = [
        (f"{partner} - NGA MSNA 2026 - Accessibility follow-up ({run_date})", True, 14),
        ("", False, 11),
        ("WHAT THIS IS", True, 12),
        (f"This is your FULL current assignment - {n_wards} wards - reflecting everything as it stands today. "
         f"{n_wards - n_flagged} of these already match what your team told us and need no action. Only the "
         f"{n_flagged} rows shaded amber need your input. Everything else can be left exactly as it is.", False, 11),
        ("", False, 11),
        ("WHY WE'RE ASKING AGAIN", True, 12),
    ]
    why_bits = []
    if n_contradiction:
        why_bits.append(f"({n_contradiction}) a small number of wards where the Accessible answer and your own "
                         "notes for that ward seem to disagree with each other")
    if n_never_reported:
        why_bits.append(f"({n_never_reported}) wards that are new to your current assignment and haven't been "
                         "reported on yet")
    if why_bits:
        lines.append((" and ".join(why_bits) + ". Neither is a criticism of your reporting - see the 'Why flagged' "
                       "column on each amber row for the specific reason.", False, 11))
    lines += [
        ("", False, 11),
        ("SHEETS", True, 12),
        ("Ward Accessibility - your full current ward-level assignment. Amber rows need input.", False, 11),
    ]
    for i, (text, bold, size) in enumerate(lines, start=1):
        cell = ws.cell(row=i, column=1, value=text)
        cell.font = Font(bold=bold, size=size)
        cell.alignment = Alignment(wrap_text=True, vertical="top")
        if len(text) > 90:
            ws.row_dimensions[i].height = 16 + 14 * (len(text) // 90)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("partner")
    ap.add_argument("out_dir")
    ap.add_argument("--prefill", default=None)
    ap.add_argument("--working", action="store_true",
                     help="Scope to WORKING (currently-fieldable) instead of FULL (this partner's whole assignment, including currently-excluded wards).")
    args = ap.parse_args()

    if not args.working:
        gen.STAGE2_CSV = gen.STAGE2_CSV.replace("_WORKING.csv", "_FULL.csv")
    ward_split_by_partner, cluster_repr_by_partner, ward_to_lgas = gen.load_cluster_rows_by_partner()
    if args.partner not in ward_split_by_partner:
        sys.exit(f"'{args.partner}' not found in current frame's partners_covering. "
                  f"Known partners: {sorted(ward_split_by_partner.keys())}")
    ward_rows = gen.build_ward_rows(ward_split_by_partner[args.partner], ward_to_lgas)

    returned_path = os.path.join(rev.RETURNED_DIR, f"{args.partner}_accessibility_report.xlsx")
    if os.path.exists(returned_path):
        partner, findings, reported_wards, seen_wards = rev.review_partner(returned_path)
    else:
        findings, seen_wards = [], set()
    answers = read_returned_ward_answers(returned_path)
    flags = build_contradiction_flags(findings)
    prefill = read_prefill(args.prefill)

    current_keys = {(r["State"], r["LGA"], r["Ward (GRID3)"]) for r in ward_rows}
    never_reported = current_keys - seen_wards
    for key in never_reported:
        flags.setdefault(key, WHY_FLAGGED_NEVER_REPORTED)

    n_contradiction = sum(1 for f in findings if f.startswith("CONTRADICTION"))
    n_never_reported = len(never_reported)
    run_date = date.today().isoformat()

    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    n_flagged = write_ward_sheet(wb, ward_rows, answers, flags, prefill)
    write_readme(wb, args.partner, len(ward_rows), n_flagged, n_contradiction, n_never_reported, run_date)
    wb.move_sheet("README", offset=-len(wb.sheetnames))

    os.makedirs(args.out_dir, exist_ok=True)
    safe_name = args.partner.replace(" ", "_")
    out_path = os.path.join(args.out_dir, f"{safe_name}_accessibility_followup_{run_date}.xlsx")
    wb.save(out_path)
    print(f"Wrote {out_path}")
    print(f"Ward Accessibility: {len(ward_rows)} rows, {n_flagged} flagged "
          f"({n_contradiction} contradiction, {n_never_reported} never-reported)")


if __name__ == "__main__":
    main()
