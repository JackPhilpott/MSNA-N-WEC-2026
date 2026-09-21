# ==============================================================================
# Tonight's (2026-09-16) partner accessibility-report prep batch: FACT, PLAN,
# COOPI, ACF, Street Child of Nigeria all sent updated reports (raw comms,
# _1609 suffix). Merges each into its partner's own master file in
# accessibility_reports_returned/ - MERGE, never overwrite: a partner's
# raw_1609 file is very often a PARTIAL/scoped re-submission (confirmed
# directly for ACF tonight - only Goronyo/Rabah had fresh data, the other 66
# clusters were blank not because they're "no longer accessible" but because
# they weren't part of this round's review), so blank cells in the raw file
# never overwrite an existing non-blank value in the main file. A non-blank
# raw value DOES overwrite an existing value (a partner's newer report always
# wins when they actually said something - covers COOPI's legitimate No->Yes
# status updates too, not just fresh info on previously-blank rows).
#
# Special cases, all per Jack's direct decisions this session:
#   - ACF: non_idp_NG034006_11 forced to Accessible=Yes (Godwin's email
#     explicitly says accessible via Kagara IDP Camp; the raw file's own
#     cell said No with no reason - Jack's call was to trust the email).
#   - Street Child: Dikwa LGA removed entirely (reassigned to FACT - see
#     patch_dikwa_reassignment_to_fact_2026-09-16.py, run first). Monguno's
#     Kekeno ward forced to Accessible=Yes - the raw file's own yellow
#     highlight (matching Monguno ward's own highlight, both meant to mark
#     "these are the 2 real accessible wards") disagreed with its own
#     Accessible(Y/N) text cell, which still said No - a data-entry slip in
#     the returned file itself, not a partner intent question.
#   - FACT: gains Dikwa's 10 wards / 17 clusters as fresh not-yet-assessed
#     rows (blank Accessible), mirroring the same
#     expand_partner_accessibility_reports_full_ward_lists_2026-09-16.py
#     append pattern already used tonight for the national ward-completeness
#     fix.
#
# Backs up each partner's main file first, to accessibility_reports_returned/
# _archive/, per this project's standing convention.
# ==============================================================================
import shutil
from datetime import date

import openpyxl
from openpyxl.utils import get_column_letter, range_boundaries
from openpyxl.worksheet.datavalidation import DataValidation

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling"
RETURNED_DIR = PROJECT_DIR + r"\input\accessibility_reports_returned"
ARCHIVE_DIR = RETURNED_DIR + r"\_archive"
RAW_DIR = PROJECT_DIR + r"\input\partner_raw_comms"
TODAY = "2026-09-16"

UPDATE_COLS = ["Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported"]


def backup(main_path, partner, reason):
    bak = f"{ARCHIVE_DIR}\\{partner}_accessibility_report_pre_{reason}_{TODAY}.xlsx"
    shutil.copy2(main_path, bak)
    print(f"  backed up -> {bak}")


def header_idx(ws):
    header = [c.value for c in ws[1]]
    return {h: i for i, h in enumerate(header) if h}


def merge_sheet(ws_main, idx_main, ws_raw, idx_raw, key_cols):
    """Layer raw's non-blank UPDATE_COLS values onto ws_main's matching rows
    (matched by key_cols, e.g. Cluster ID, or (State, LGA, Ward (GRID3))).
    Never blanks out an existing value; a non-blank raw value always wins."""
    raw_rows = {}
    for r in ws_raw.iter_rows(min_row=2, values_only=True):
        if not any(v is not None for v in r):
            continue
        key = tuple(r[idx_raw[c]] for c in key_cols)
        raw_rows[key] = r

    n_updated = 0
    for row_cells in ws_main.iter_rows(min_row=2):
        vals = [c.value for c in row_cells]
        if not any(v is not None for v in vals):
            continue
        key = tuple(vals[idx_main[c]] for c in key_cols)
        rr = raw_rows.get(key)
        if rr is None:
            continue
        changed = False
        for col in UPDATE_COLS:
            if col not in idx_raw or col not in idx_main:
                continue
            new_val = rr[idx_raw[col]]
            if new_val is None or new_val == "":
                continue
            cell = row_cells[idx_main[col]]
            if cell.value != new_val:
                cell.value = new_val
                changed = True
        if changed:
            n_updated += 1
    return n_updated


def merge_partner(partner, raw_filename, raw_sheet_map=None):
    """raw_sheet_map: optional {main_sheet_name: raw_sheet_name} if they differ."""
    main_path = f"{RETURNED_DIR}\\{partner}_accessibility_report.xlsx"
    raw_path = f"{RAW_DIR}\\{partner}\\{raw_filename}"
    print(f"\n=== {partner} ===")
    backup(main_path, partner, "1609_merge")

    wb_main = openpyxl.load_workbook(main_path)
    wb_raw = openpyxl.load_workbook(raw_path, data_only=True)

    sheet_map = raw_sheet_map or {"Ward Accessibility": "Ward Accessibility", "Cluster Accessibility": "Cluster Accessibility"}
    for main_sheet, raw_sheet in sheet_map.items():
        ws_main = wb_main[main_sheet]
        ws_raw = wb_raw[raw_sheet]
        idx_main = header_idx(ws_main)
        idx_raw = header_idx(ws_raw)
        key_cols = ["Cluster ID"] if "Cluster ID" in idx_main else ["State", "LGA", "Ward (GRID3)"]
        n = merge_sheet(ws_main, idx_main, ws_raw, idx_raw, key_cols)
        print(f"  {main_sheet}: {n} row(s) updated")

    wb_main.save(main_path)
    print(f"  saved -> {main_path}")
    return main_path


def apply_acf_correction():
    main_path = f"{RETURNED_DIR}\\ACF_accessibility_report.xlsx"
    wb = openpyxl.load_workbook(main_path)
    ws = wb["Cluster Accessibility"]
    idx = header_idx(ws)
    note = ("Marked accessible per Godwin (STCI) email 2026-09-16: respondents displaced by "
            "banditry, currently reside in Kagara IDP Camp (Goronyo LGA) and are reachable there. "
            "Overrides the returned workbook's own cell, which said No with no reason given.")
    n = 0
    for row_cells in ws.iter_rows(min_row=2):
        if row_cells[idx["Cluster ID"]].value == "non_idp_NG034006_11":
            row_cells[idx["Accessible (Y/N)"]].value = "Yes"
            row_cells[idx["Reason category"]].value = "N/A - fully accessible"
            row_cells[idx["Reason notes"]].value = note
            row_cells[idx["Date reported"]].value = "2026-09-16"
            n += 1
    wb.save(main_path)
    print(f"\n=== ACF correction ===\n  non_idp_NG034006_11 forced to Yes ({n} row matched)")


def resize_table_and_validations(ws, table_name, new_last_row):
    t = ws.tables[table_name]
    min_col, min_row, max_col, _ = range_boundaries(t.ref)
    new_ref = f"{get_column_letter(min_col)}{min_row}:{get_column_letter(max_col)}{new_last_row}"
    t.ref = new_ref
    if t.autoFilter is not None:
        t.autoFilter.ref = new_ref

    # Rebuild every DataValidation on this sheet as one clean range per formula,
    # rather than trying to patch fragmented sqref chunks left by row add/remove.
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


def add_fact_dikwa_wards():
    main_path = f"{RETURNED_DIR}\\FACT_accessibility_report.xlsx"
    sci_raw_path = f"{RETURNED_DIR}\\_archive\\Street Child of Nigeria_accessibility_report_pre_1609_merge_{TODAY}.xlsx"
    print("\n=== FACT gains Dikwa (from Street Child's pre-merge backup) ===")
    backup(main_path, "FACT", "dikwa_addition")

    wb_main = openpyxl.load_workbook(main_path)
    wb_sci = openpyxl.load_workbook(sci_raw_path, data_only=True)

    # --- Ward Accessibility ---
    ws_main = wb_main["Ward Accessibility"]
    ws_sci = wb_sci["Ward Accessibility"]
    idx_main = header_idx(ws_main)
    idx_sci = header_idx(ws_sci)
    t = ws_main.tables["WardAccessibility"] if "WardAccessibility" in ws_main.tables else list(ws_main.tables.values())[0]
    table_name = list(ws_main.tables.keys())[0]
    _, _, _, cur_last_row = range_boundaries(t.ref)
    n_added = 0
    for r in ws_sci.iter_rows(min_row=2, values_only=True):
        if not any(v is not None for v in r):
            continue
        if r[idx_sci["LGA"]] != "Dikwa":
            continue
        new_row = cur_last_row + 1 + n_added
        for col_name in idx_main:
            if col_name in idx_sci:
                ws_main.cell(row=new_row, column=idx_main[col_name] + 1, value=r[idx_sci[col_name]])
        note_col = idx_main.get("Note")
        if note_col is not None:
            ws_main.cell(row=new_row, column=note_col + 1,
                         value="Newly added 2026-09-16 - Dikwa reassigned from Street Child of Nigeria to FACT; not yet assessed by FACT.")
        n_added += 1
    resize_table_and_validations(ws_main, table_name, cur_last_row + n_added)
    print(f"  Ward Accessibility: {n_added} row(s) added")

    # --- Cluster Accessibility ---
    ws_main = wb_main["Cluster Accessibility"]
    ws_sci = wb_sci["Cluster Accessibility"]
    idx_main = header_idx(ws_main)
    idx_sci = header_idx(ws_sci)
    table_name = list(ws_main.tables.keys())[0]
    t = ws_main.tables[table_name]
    _, _, _, cur_last_row = range_boundaries(t.ref)
    n_added = 0
    for r in ws_sci.iter_rows(min_row=2, values_only=True):
        if not any(v is not None for v in r):
            continue
        if r[idx_sci["LGA"]] != "Dikwa":
            continue
        new_row = cur_last_row + 1 + n_added
        for col_name in idx_main:
            if col_name in idx_sci:
                ws_main.cell(row=new_row, column=idx_main[col_name] + 1, value=r[idx_sci[col_name]])
        # Dikwa clusters carried no accessibility data from Street Child - leave blank (not yet assessed by FACT)
        n_added += 1
    resize_table_and_validations(ws_main, table_name, cur_last_row + n_added)
    print(f"  Cluster Accessibility: {n_added} row(s) added")

    wb_main.save(main_path)
    print(f"  saved -> {main_path}")


def apply_street_child_fixes():
    main_path = f"{RETURNED_DIR}\\Street Child of Nigeria_accessibility_report.xlsx"
    print("\n=== Street Child: Kekeno fix + Dikwa removal ===")
    backup(main_path, "Street Child of Nigeria", "kekeno_fix_and_dikwa_removal")
    wb = openpyxl.load_workbook(main_path)

    # --- Kekeno fix (Ward Accessibility) ---
    ws = wb["Ward Accessibility"]
    idx = header_idx(ws)
    n_fixed = 0
    for row_cells in ws.iter_rows(min_row=2):
        if row_cells[idx["LGA"]].value == "Monguno" and row_cells[idx["Ward (GRID3)"]].value == "Kekeno":
            row_cells[idx["Accessible (Y/N)"]].value = "Yes"
            row_cells[idx["Reason category"]].value = "N/A - fully accessible"
            row_cells[idx["Reason notes"]].value = ("Corrected 2026-09-16: cell said No but the ward name was "
                                                       "highlighted yellow in the returned file, matching Monguno "
                                                       "ward's own highlight - both meant to mark the 2 real "
                                                       "accessible Monguno wards. Data-entry slip, not new information.")
            n_fixed += 1
    print(f"  Ward Accessibility: Kekeno corrected to Yes ({n_fixed} row matched)")

    # --- Kekeno fix (Cluster Accessibility, any clusters in that ward) ---
    ws2 = wb["Cluster Accessibility"]
    idx2 = header_idx(ws2)
    n_fixed_clusters = 0
    for row_cells in ws2.iter_rows(min_row=2):
        if row_cells[idx2["LGA"]].value == "Monguno" and row_cells[idx2["Ward (GRID3)"]].value == "Kekeno":
            row_cells[idx2["Accessible (Y/N)"]].value = "Yes"
            row_cells[idx2["Reason category"]].value = "N/A - fully accessible"
            n_fixed_clusters += 1
    print(f"  Cluster Accessibility: {n_fixed_clusters} Kekeno cluster row(s) corrected to Yes")

    # --- Dikwa removal (both sheets) ---
    for sheet_name in ["Ward Accessibility", "Cluster Accessibility"]:
        ws = wb[sheet_name]
        idx = header_idx(ws)
        table_name = list(ws.tables.keys())[0]
        t = ws.tables[table_name]
        _, min_row, _, cur_last_row = range_boundaries(t.ref)
        rows_to_delete = []
        for row_cells in ws.iter_rows(min_row=2):
            if row_cells[idx["LGA"]].value == "Dikwa":
                rows_to_delete.append(row_cells[0].row)
        for r in sorted(rows_to_delete, reverse=True):
            ws.delete_rows(r, 1)
        new_last_row = cur_last_row - len(rows_to_delete)
        resize_table_and_validations(ws, table_name, new_last_row)
        print(f"  {sheet_name}: {len(rows_to_delete)} Dikwa row(s) removed")

    wb.save(main_path)
    print(f"  saved -> {main_path}")


if __name__ == "__main__":
    # Order matters: Street Child must be merged (creating the pre-merge
    # backup FACT's Dikwa addition reads from) BEFORE its own Dikwa rows are
    # stripped out, and before FACT gains them.
    # FACT's raw file only has a Cluster Accessibility sheet (Dandume correction)
    # plus a separately-handled "Missing Clusters on Kobo" sheet (not an
    # accessibility-status merge - flagged to Jack as an operational tool-config
    # item, not written into this file).
    merge_partner("FACT", "FACT_accessibility_report_update_15_Sept_2026_1609.xlsx",
                  raw_sheet_map={"Cluster Accessibility": "Cluster Accessibility"})
    merge_partner("PLAN", "PLAN_accessibility_report_1609.xlsx")
    merge_partner("COOPI", "COOPI_accessibility_report_1609.xlsx")
    merge_partner("ACF", "ACF_accessibility_report_1609.xlsx")
    apply_acf_correction()
    merge_partner("Street Child of Nigeria", "Street Child of Nigeria_accessibility_report_1609.xlsx")

    add_fact_dikwa_wards()
    apply_street_child_fixes()

    print("\nAll merges done.")
