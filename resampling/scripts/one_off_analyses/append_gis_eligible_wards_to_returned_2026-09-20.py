# ==============================================================================
# One-off, 2026-09-20. Follow-up to today's ward-universe-gap fix (see
# 1_sampling/CLAUDE.md and 04_build_master_accessibility_status.py /
# 01_generate_accessibility_reports.py's load_gis_ward_universe()): those two
# fixes corrected the INTERNAL master status and any FUTURE generated report,
# but accessibility_reports_returned/<Partner>_accessibility_report.xlsx -
# the file Jack treats as the current master record per partner (FACT's own
# file literally says "this is your FULL current assignment") - was never
# touched by either fix, since neither one writes to that folder.
#
# This appends the same Stage-1-eligible-but-never-drawn ward rows (zero
# clusters, zero target HH) directly into each partner's OWN returned-folder
# file, as brand-new rows at the end of their Ward Accessibility sheet only -
# never the Cluster Accessibility sheet, since no real cluster exists for
# these wards. Strictly additive: existing rows (including anything a partner
# has already filled in) are never read for content, never modified, never
# reordered - only appended after. Each partner's file backed up first to
# _archive/, per this project's standing convention.
#
# Per Jack's explicit instruction: every newly-added row gets a note flagging
# it as new, in whichever "informational, not partner-input" column that
# partner's own file schema provides - "Note" for the standard template (17 of
# 18 live returned files), "Why flagged" for FACT's own differently-shaped
# master reconciliation file (no "Note" column at all - see its header).
#
# Partner-coverage source: resampling/output/gis/accessible_area_lga_ward_
# portions.csv's own covering_partners column - the same file both fixed
# scripts already read from, so this stays consistent with them by
# construction rather than re-deriving coverage a third, possibly-divergent
# way.
# ==============================================================================
import csv
import glob
import os
import shutil
from collections import defaultdict
from datetime import date

import openpyxl
from openpyxl.utils import get_column_letter, range_boundaries
from openpyxl.worksheet.datavalidation import DataValidation

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
RETURNED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned"
ARCHIVE_DIR = RETURNED_DIR + r"\_archive"
GIS_WARD_UNIVERSE_CSV = PROJECT_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
TODAY = "2026-09-20"

NEW_WARD_NOTE = (
    "Newly added 2026-09-20 - this ward is Stage-1-eligible for your coverage but had never had a cluster "
    "drawn in it by chance, so it was missing from your assignment list until now (a gap found and fixed "
    "today, see the accompanying email). Please review and report on it like any other row."
)


def load_gis_ward_universe():
    with open(GIS_WARD_UNIVERSE_CSV, encoding="utf-8") as f:
        gis_rows = list(csv.DictReader(f))
    out = []
    for r in gis_rows:
        partners = {p.strip() for p in r["covering_partners"].split(";") if p.strip()}
        if not partners:
            continue
        out.append({"state": r["adm1_name"], "lga": r["adm2_name"], "ward": r["wardname"], "partners": partners})
    return out


def build_ward_to_lgas(gis_rows):
    m = defaultdict(set)
    for g in gis_rows:
        m[(g["state"], g["ward"])].add(g["lga"])
    return {k: sorted(v) for k, v in m.items()}


def header_idx(ws):
    header = [c.value for c in ws[1]]
    return {h: i for i, h in enumerate(header) if h}


def resize_table_and_validations(ws, table_name, new_last_row):
    """table_name=None means the sheet has no Excel Table object at all
    (found 2026-09-20: FACT's Ward Accessibility sheet has none, unlike
    every other partner's standard-template sheet - a different, custom-
    built file, not a bug in this script). In that case the header row is
    always row 1 (consistent throughout this project's generated sheets),
    so data validations are simply extended from row 2 without any Table
    ref to resize."""
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


def append_for_partner(path, partner, gis_rows, ward_to_lgas):
    wb = openpyxl.load_workbook(path)
    if "Ward Accessibility" not in wb.sheetnames:
        print(f"  {partner}: no Ward Accessibility sheet - skipped")
        wb.close()
        return 0
    ws = wb["Ward Accessibility"]
    idx = header_idx(ws)

    existing_keys = set()
    for row_cells in ws.iter_rows(min_row=2):
        vals = [c.value for c in row_cells]
        if not any(v is not None for v in vals):
            continue
        key = (vals[idx["State"]], vals[idx["LGA"]], vals[idx["Ward (GRID3)"]])
        existing_keys.add(key)

    to_add = []
    for g in gis_rows:
        if partner not in g["partners"]:
            continue
        key = (g["state"], g["lga"], g["ward"])
        if key in existing_keys:
            continue
        to_add.append(g)
        existing_keys.add(key)  # avoid double-adding if the GIS layer ever repeats a (state,lga,ward)

    if not to_add:
        print(f"  {partner}: 0 new ward row(s) - already complete")
        wb.close()
        return 0

    note_col_name = "Note" if "Note" in idx else ("Why flagged" if "Why flagged" in idx else None)

    if ws.tables:
        table_name = list(ws.tables.keys())[0]
        _, _, _, cur_last_row = range_boundaries(ws.tables[table_name].ref)
    else:
        # No Excel Table object on this sheet (FACT's own file - see
        # resize_table_and_validations()'s docstring). Fall back to the
        # sheet's real last non-empty row.
        table_name = None
        cur_last_row = ws.max_row
        while cur_last_row > 1 and all(c.value is None for c in ws[cur_last_row]):
            cur_last_row -= 1

    for i, g in enumerate(to_add):
        r = cur_last_row + 1 + i
        other_lgas = [l for l in ward_to_lgas.get((g["state"], g["ward"]), [g["lga"]]) if l != g["lga"]]
        values = {
            "State": g["state"], "LGA": g["lga"], "Ward (GRID3)": g["ward"],
            "Non-IDP clusters": 0, "IDP clusters": 0, "Total target HHs (primary)": 0,
        }
        if "Ward spans multiple LGAs (Y/N)" in idx:
            values["Ward spans multiple LGAs (Y/N)"] = "Yes" if other_lgas else "No"
        if "Other LGA(s) sharing this ward" in idx:
            values["Other LGA(s) sharing this ward"] = "; ".join(other_lgas)
        if note_col_name:
            values[note_col_name] = NEW_WARD_NOTE
        for col_name, col_i in idx.items():
            if col_name in values:
                ws.cell(row=r, column=col_i + 1, value=values[col_name])

    new_last_row = cur_last_row + len(to_add)
    resize_table_and_validations(ws, table_name, new_last_row)

    wb.save(path)
    wb.close()
    print(f"  {partner}: {len(to_add)} new ward row(s) added (flagged via '{note_col_name}')")
    return len(to_add)


def main():
    gis_rows = load_gis_ward_universe()
    ward_to_lgas = build_ward_to_lgas(gis_rows)

    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    total = 0
    for path in sorted(glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx"))):
        partner = os.path.basename(path)[: -len("_accessibility_report.xlsx")]
        bak = os.path.join(ARCHIVE_DIR, f"{partner}_accessibility_report_pre_gis_eligible_ward_append_{TODAY}.xlsx")
        if not os.path.exists(bak):
            # Guard against a rerun (e.g. resuming after an earlier partial
            # failure) clobbering the TRUE pre-edit backup with an
            # already-edited copy - a backup only ever gets taken once.
            shutil.copy2(path, bak)
        n = append_for_partner(path, partner, gis_rows, ward_to_lgas)
        total += n

    print(f"\n{total} new ward row(s) added in total across all partner returned files.")


if __name__ == "__main__":
    main()
