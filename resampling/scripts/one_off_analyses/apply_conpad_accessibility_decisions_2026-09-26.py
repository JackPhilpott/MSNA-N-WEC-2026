# ==============================================================================
# 2026-09-26: apply Conpad Initiatives' (FACT subcontractor) accessibility report
# v1_conpad_2609 + Jack Philpott's decisions (register block U) to FACT's returned
# accessibility report. EXACTLY the changes Jack decided, nothing else from
# Conpad's file (their other differences vs the main file are listed, not applied).
#
#   Ward Accessibility, Accessible = No (Date reported 2026-09-26 on every changed row):
#     Matazu/Dissi, Faskari/Yankara, Funtua/Goya, Funtua/Maigamji, Funtua/Makera,
#     Dandume/Mahuta C  (reason set by Jack: Insecurity / conflict; Conpad's own
#       reason was the contradictory "N/A - fully accessible")
#     Border wards, blank in Conpad's file, Jack: 'all no, inaccessible due to
#       insecurity': Dandume/Damari, Dandume/Gamji, Dandume/Makera, Faskari/Yankuzo A
#     Malumfashi/Rugoji, blank on file, Jack: 'set it to no for insecurity'
#     Malumfashi/Malumfashi B: NOT changed (Jack: 'leave as yes, the ward is
#       accessible but just some points within it weren't')
#   Cluster Accessibility: Dandume / Mahuta C / non_idp_NG021008_8 -> No
#   Your Subcontracted Partners: add Funtua to Conpad Initiatives (Katsina)
#
# Method: same merge-preserve pattern as the 09-16 / 09-20 merge scripts, but
# with the change set spelled out explicitly (no bulk merge from Conpad's file).
# The result is written to a temp file next to the main file, diffed cell by
# cell against the backup, and only moved into place if the diff is EXACTLY the
# expected set. Dry run by default; --execute needs the backup to exist.
# ==============================================================================
import argparse
import copy
import os
import shutil
import sys
from datetime import datetime

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling"
MAIN = PROJECT_DIR + r"\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"
BACKUP = PROJECT_DIR + r"\input\accessibility_reports_returned\_archive\FACT_accessibility_report_pre_conpad_2026-09-26.xlsx"
CONPAD = PROJECT_DIR + r"\input\partner_raw_comms\FACT\FACT_accessibility_report_v1_conpad_2609.xlsx"
TMP = MAIN.replace(".xlsx", "_tmp_conpad.xlsx")

SRC = "Conpad Initiatives (FACT subcontractor) report v1_conpad_2609 + Jack Philpott decisions 2026-09-26"
NEW_DATE = datetime(2026, 9, 26)
INSEC = "Insecurity / conflict"
BORDER_NOTE = ("Ward blank in Conpad's file; set to No (inaccessible due to insecurity) by Jack Philpott decision 2026-09-26")

# (LGA, ward) -> (reason category, detail: None = keep existing notes if real, else a text)
# detail is prepended to the source note; "KEEP" keeps whatever real note is already there.
WARD_CHANGES = {
    ("Matazu", "Dissi"): (INSEC, "KEEP"),
    ("Dandume", "Mahuta C"): (INSEC, "Reason set by Jack Philpott (Conpad's file gave No with a contradictory 'fully accessible' reason)"),
    ("Faskari", "Yankara"): (INSEC, "KEEP"),
    ("Funtua", "Goya"): ("Population absent / relocated", None),
    ("Funtua", "Maigamji"): (INSEC, "Banditry and kidnappings"),
    ("Funtua", "Makera"): ("Other", "Northwest part of the ward not access - Banditry and kidnapping"),
    ("Dandume", "Damari"): (INSEC, BORDER_NOTE),
    ("Dandume", "Gamji"): (INSEC, BORDER_NOTE),
    ("Dandume", "Makera"): (INSEC, BORDER_NOTE),
    ("Faskari", "Yankuzo A"): (INSEC, BORDER_NOTE),
    ("Malumfashi", "Rugoji"): (INSEC, "Malumfashi portion of Rugoji, blank on file; set to No (inaccessible due to insecurity) by Jack Philpott decision 2026-09-26"),
}
# cluster row: (LGA, ward, cluster_id)
CLUSTER_CHANGES = {
    ("Dandume", "Mahuta C", "non_idp_NG021008_8"): (INSEC, "KEEP"),
}
STATE = "Katsina"


def is_real_note(v):
    return v is not None and str(v).strip() not in ("", "NA", "N/A", "nan")


def hidx(ws):
    return {c.value: i for i, c in enumerate(ws[1]) if c.value}


def build_note(existing, detail):
    parts = []
    if detail == "KEEP":
        if is_real_note(existing):
            parts.append(str(existing).strip().rstrip("."))
    elif detail:
        parts.append(detail)
    parts.append("Source: " + SRC)
    return " | ".join(parts)


def apply_changes(wb):
    log = []
    ws = wb["Ward Accessibility"]
    ix = hidx(ws)
    found = {}
    for r in range(2, ws.max_row + 1):
        if ws.cell(r, ix["State"] + 1).value != STATE:
            continue
        key = (ws.cell(r, ix["LGA"] + 1).value, ws.cell(r, ix["Ward (GRID3)"] + 1).value)
        if key in WARD_CHANGES:
            found.setdefault(key, []).append(r)
    for key in WARD_CHANGES:
        rows = found.get(key, [])
        if len(rows) != 1:
            raise SystemExit(f"Ward row for {key} matched {len(rows)} rows: {rows}")
    for key, (reason, detail) in WARD_CHANGES.items():
        r = found[key][0]
        old = {c: ws.cell(r, ix[c] + 1).value for c in ("Accessible (Y/N)", "Reason category", "Reason notes", "Date reported")}
        ws.cell(r, ix["Accessible (Y/N)"] + 1).value = "No"
        ws.cell(r, ix["Reason category"] + 1).value = reason
        ws.cell(r, ix["Reason notes"] + 1).value = build_note(old["Reason notes"], detail)
        ws.cell(r, ix["Date reported"] + 1).value = NEW_DATE
        log.append(("Ward Accessibility", r, key, old))

    ws = wb["Cluster Accessibility"]
    ix = hidx(ws)
    found = {}
    for r in range(2, ws.max_row + 1):
        if ws.cell(r, ix["State"] + 1).value != STATE:
            continue
        key = (ws.cell(r, ix["LGA"] + 1).value, ws.cell(r, ix["Ward (GRID3)"] + 1).value, ws.cell(r, ix["Cluster ID"] + 1).value)
        if key in CLUSTER_CHANGES:
            found.setdefault(key, []).append(r)
    for key in CLUSTER_CHANGES:
        rows = found.get(key, [])
        if len(rows) != 1:
            raise SystemExit(f"Cluster row for {key} matched {len(rows)} rows: {rows}")
    for key, (reason, detail) in CLUSTER_CHANGES.items():
        r = found[key][0]
        old = {c: ws.cell(r, ix[c] + 1).value for c in ("Accessible (Y/N)", "Reason category", "Reason notes", "Date reported")}
        ws.cell(r, ix["Accessible (Y/N)"] + 1).value = "No"
        ws.cell(r, ix["Reason category"] + 1).value = reason
        ws.cell(r, ix["Reason notes"] + 1).value = build_note(old["Reason notes"], detail)
        ws.cell(r, ix["Date reported"] + 1).value = NEW_DATE
        log.append(("Cluster Accessibility", r, key, old))

    # Your Subcontracted Partners: add Funtua under Conpad Initiatives (rows 2-4 = Matazu, Dandume, Faskari)
    ws = wb["Your Subcontracted Partners"]
    assert ws.cell(2, 1).value == "Conpad Initiatives" and str(ws.cell(4, 3).value).strip() == "Faskari", "unexpected subcontractor sheet layout"
    assert all(ws.cell(10, c).value is None for c in range(1, 7)), "row 10 of the subcontractor sheet is not empty"
    for r in range(9, 4, -1):  # shift rows 5..9 down one (row 10 was empty)
        for c in range(1, 7):
            src, dst = ws.cell(r, c), ws.cell(r + 1, c)
            dst.value = src.value
            dst._style = copy.copy(src._style)
    for c in range(1, 7):
        ws.cell(5, c)._style = copy.copy(ws.cell(4, c)._style)
        ws.cell(5, c).value = None
    ws.cell(5, 3).value = "Funtua"
    ws.cell(5, 4).value = "Whole LGA (added 2026-09-26 by Jack Philpott decision; Conpad's Funtua feedback of 25 Sep)"
    log.append(("Your Subcontracted Partners", 5, ("Conpad Initiatives", "Katsina", "Funtua"), None))
    return log


def sheet_values(ws):
    return {(c.row, c.column): c.value for row in ws.iter_rows() for c in row if c.value is not None}


def diff_workbooks(path_a, path_b):
    """Cell-level value diff, a=before b=after. Returns {sheet: {(r,c): (a,b)}}."""
    wa = openpyxl.load_workbook(path_a)
    wb_ = openpyxl.load_workbook(path_b)
    out = {}
    assert wa.sheetnames == wb_.sheetnames, (wa.sheetnames, wb_.sheetnames)
    for n in wa.sheetnames:
        va, vb = sheet_values(wa[n]), sheet_values(wb_[n])
        d = {k: (va.get(k), vb.get(k)) for k in set(va) | set(vb) if va.get(k) != vb.get(k)}
        if d:
            out[n] = d
        # structural properties must survive the re-save
        for attr in ("freeze_panes",):
            assert getattr(wa[n], attr) == getattr(wb_[n], attr), (n, attr)
        assert wa[n].auto_filter.ref == wb_[n].auto_filter.ref, (n, "auto_filter")
        assert wa[n].dimensions == wb_[n].dimensions or n == "Your Subcontracted Partners", (n, wa[n].dimensions, wb_[n].dimensions)
        dva = sorted((str(dv.sqref), dv.type, dv.formula1) for dv in wa[n].data_validations.dataValidation)
        dvb = sorted((str(dv.sqref), dv.type, dv.formula1) for dv in wb_[n].data_validations.dataValidation)
        assert dva == dvb, (n, "data validations differ")
    return out


def conpad_other_differences():
    """Cells where Conpad's file differs from the main file (values, UPDATE_COLS + anything) - reported only, never applied."""
    wm = openpyxl.load_workbook(BACKUP)
    wc = openpyxl.load_workbook(CONPAD, data_only=True)
    res = {}
    for n in ("Ward Accessibility", "Cluster Accessibility", "Your Subcontracted Partners"):
        vm, vc = sheet_values(wm[n]), sheet_values(wc[n])
        res[n] = sorted(((k, vm.get(k), vc.get(k)) for k in set(vm) | set(vc) if vm.get(k) != vc.get(k)))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--execute", action="store_true")
    a = ap.parse_args()
    if not os.path.exists(BACKUP):
        raise SystemExit("backup missing: " + BACKUP)
    if os.path.exists(TMP):
        os.remove(TMP)
    wb = openpyxl.load_workbook(BACKUP)          # always start from the backup (= the pre-change file)
    log = apply_changes(wb)
    wb.save(TMP)
    d = diff_workbooks(BACKUP, TMP)

    exp_ward = len(WARD_CHANGES)
    got_ward_rows = sorted({k[0] for k in d.get("Ward Accessibility", {})})
    got_cl_rows = sorted({k[0] for k in d.get("Cluster Accessibility", {})})
    print(f"changed Ward rows: {len(got_ward_rows)} (expected {exp_ward}); cluster rows: {len(got_cl_rows)} (expected {len(CLUSTER_CHANGES)}); "
          f"subcontractor-sheet cells changed: {len(d.get('Your Subcontracted Partners', {}))}")
    for sheet, r, key, old in log:
        print(f"  {sheet} row {r}: {key}   before: {old}")
    ok = (len(got_ward_rows) == exp_ward and len(got_cl_rows) == len(CLUSTER_CHANGES)
          and set(d) <= {"Ward Accessibility", "Cluster Accessibility", "Your Subcontracted Partners"})
    # every changed Ward/Cluster cell must sit in the four editable columns
    for sheet in ("Ward Accessibility", "Cluster Accessibility"):
        wsb = openpyxl.load_workbook(TMP)[sheet]
        ix = hidx(wsb)
        allowed = {ix[c] + 1 for c in ("Accessible (Y/N)", "Reason category", "Reason notes", "Date reported")}
        bad = [k for k in d.get(sheet, {}) if k[1] not in allowed]
        if bad:
            ok = False
            print("UNEXPECTED column touched:", sheet, bad)
    print("DIFF VS BACKUP == EXPECTED SET:", ok)

    other = conpad_other_differences()
    for n, rows in other.items():
        print(f"Conpad file vs pre-change main, {n}: {len(rows)} differing cells (reported, not applied)")
    if not ok:
        os.remove(TMP)
        raise SystemExit("STOP: diff is not the expected set; nothing written")
    if not a.execute:
        os.remove(TMP)
        print("dry run: nothing written")
        return
    os.replace(TMP, MAIN)
    print("written ->", MAIN)


if __name__ == "__main__":
    main()
