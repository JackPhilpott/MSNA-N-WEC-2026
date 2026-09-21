# ==============================================================================
# One-off, 2026-09-21. Same bug shape as append_gis_eligible_wards_to_
# returned_2026-09-20.py (see that script's own header) - Jack caught it
# recurring: today's accessibility-report merge-preserve fix
# (01_generate_accessibility_reports.py, Task 4) corrects any FUTURE
# generated report, but accessibility_reports_returned/<Partner>_
# accessibility_report.xlsx - the file Jack treats as the current master
# record per partner - was never touched by that fix either, since it only
# writes to accessibility_reports_generated/. Every cluster added by this
# week's resampling rounds is missing from partners' own returned-folder
# master files, even though it now correctly appears in their generated
# report. Scope confirmed directly before writing this: 715 clusters
# missing for FACT alone, 900+ nationally across all 19 partners.
#
# Appends the current, active cluster set (same source
# 01_generate_accessibility_reports.py's load_cluster_rows_by_partner()
# already produces - correctly ward-attributed via today's dominant_ward.py
# fix) as brand-new rows at the end of each partner's OWN returned-folder
# Cluster Accessibility sheet only - never Ward Accessibility, since this
# week's gap is cluster-level, not ward-level (that gap was 09-20's, already
# closed). Strictly additive, same rule as the precedent: existing rows
# (including anything a partner has already filled in) are never read for
# content, never modified, never reordered - only appended after. Each
# partner's file backed up first to _archive/, per this project's standing
# convention.
#
# Newly-added rows are left with Accessible/Reason/etc. BLANK - these are
# genuinely never-before-reported clusters, so a blank row is the correct
# "not yet answered" state, matching how any new cluster has always looked
# on first appearance. Where a partner's own file schema provides a real
# flag column for this (FACT's "Needs your input?" / "Why flagged" -
# confirmed from FACT's own live convention on already-flagged rows, e.g.
# "This specific cluster has no accessibility status recorded - please
# confirm."), it's set the same way. No standard-template partner's Cluster
# Accessibility sheet has an equivalent note column (checked directly -
# unlike the Ward Accessibility sheet, which does) - left unset there,
# nothing to write.
# ==============================================================================
import csv
import glob
import importlib.util
import os
import shutil
import sys
from datetime import date

import openpyxl
from openpyxl.utils import get_column_letter, range_boundaries
from openpyxl.worksheet.datavalidation import DataValidation

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
RETURNED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned"
ARCHIVE_DIR = RETURNED_DIR + r"\_archive"
TODAY = str(date.today())

NEW_CLUSTER_NEEDS_INPUT_NOTE = (
    "This specific cluster is newly added to your assignment (resampling round, "
    f"found missing from your returned master file {TODAY} - see the accompanying "
    "note). No accessibility status recorded yet - please confirm."
)

CLUSTER_REF_COLUMNS = [
    "State", "LGA", "Ward (GRID3)", "Pop Type", "Cluster ID", "IDP Category",
    "Target HHs (primary)", "Reserve HHs",
]


def header_idx(ws):
    header = [c.value for c in ws[1]]
    return {h: i for i, h in enumerate(header) if h}


def resize_table_and_validations(ws, table_name, new_last_row):
    """Same logic as the 2026-09-20 precedent - see that script's own
    docstring for why a missing Table object (FACT) is handled separately."""
    min_row = 1
    if table_name is not None:
        t = ws.tables[table_name]
        min_col, min_row, max_col, _ = range_boundaries(t.ref)
        new_ref = f"{get_column_letter(min_col)}{min_row}:{get_column_letter(max_col)}{new_last_row}"
        t.ref = new_ref
        if t.autoFilter is not None:
            t.autoFilter.ref = new_ref

    dvs = list(ws.data_validations.dataValidation)
    by_formula_col = {}
    for dv in dvs:
        for rng in str(dv.sqref).split():
            c0, r0, c1, r1 = range_boundaries(rng)
            key = (c0, dv.formula1, dv.type)
            if key not in by_formula_col:
                by_formula_col[key] = dv
    ws.data_validations.dataValidation = []
    for (col, formula1, dv_type), dv in by_formula_col.items():
        new_dv = DataValidation(type=dv_type, formula1=formula1, allow_blank=True)
        colletter = get_column_letter(col)
        new_dv.add(f"{colletter}{min_row + 1}:{colletter}{new_last_row}")
        ws.add_data_validation(new_dv)


def append_for_partner(path, partner, current_records):
    wb = openpyxl.load_workbook(path)
    if "Cluster Accessibility" not in wb.sheetnames:
        print(f"  {partner}: no Cluster Accessibility sheet - skipped")
        wb.close()
        return 0
    ws = wb["Cluster Accessibility"]
    idx = header_idx(ws)

    existing_ids = set()
    for row_cells in ws.iter_rows(min_row=2):
        vals = [c.value for c in row_cells]
        if not any(v is not None for v in vals):
            continue
        cid = vals[idx["Cluster ID"]]
        if cid:
            existing_ids.add(cid)

    to_add = [r for r in current_records if r["Cluster ID"] not in existing_ids]
    if not to_add:
        print(f"  {partner}: 0 new cluster row(s) - already complete")
        wb.close()
        return 0

    needs_input_col = "Needs your input?" if "Needs your input?" in idx else None
    why_flagged_col = "Why flagged" if "Why flagged" in idx else None

    if ws.tables:
        table_name = list(ws.tables.keys())[0]
        _, _, _, cur_last_row = range_boundaries(ws.tables[table_name].ref)
    else:
        table_name = None
        cur_last_row = ws.max_row
        while cur_last_row > 1 and all(c.value is None for c in ws[cur_last_row]):
            cur_last_row -= 1

    for i, rec in enumerate(to_add):
        r = cur_last_row + 1 + i
        values = {c: rec.get(c, "") for c in CLUSTER_REF_COLUMNS}
        if needs_input_col:
            values[needs_input_col] = "Yes"
        if why_flagged_col:
            values[why_flagged_col] = NEW_CLUSTER_NEEDS_INPUT_NOTE
        for col_name, col_i in idx.items():
            if col_name in values:
                ws.cell(row=r, column=col_i + 1, value=values[col_name])

    new_last_row = cur_last_row + len(to_add)
    resize_table_and_validations(ws, table_name, new_last_row)

    wb.save(path)
    wb.close()
    print(f"  {partner}: {len(to_add)} new cluster row(s) added"
          + (f" (flagged via '{why_flagged_col}')" if why_flagged_col else ""))
    return len(to_add)


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + r"\..")
    spec = importlib.util.spec_from_file_location(
        "gen_acc", os.path.dirname(os.path.abspath(__file__)) + r"\..\01_generate_accessibility_reports.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _, cluster_repr_by_partner, _, _ = mod.load_cluster_rows_by_partner()

    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    total = 0
    for path in sorted(glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx"))):
        partner = os.path.basename(path)[: -len("_accessibility_report.xlsx")]
        current_records = [r for r in cluster_repr_by_partner.get(partner, []) if r.get("Status", "Active") == "Active"]
        if not current_records:
            print(f"  {partner}: no current cluster records from the frame - skipped")
            continue
        bak = os.path.join(ARCHIVE_DIR, f"{partner}_accessibility_report_pre_new_cluster_append_{TODAY}.xlsx")
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        try:
            n = append_for_partner(path, partner, current_records)
        except PermissionError as e:
            print(f"  {partner}: LOCKED, skipped - {e}")
            continue
        total += n

    print(f"\n{total} new cluster row(s) added in total across all partner returned files.")


if __name__ == "__main__":
    main()
