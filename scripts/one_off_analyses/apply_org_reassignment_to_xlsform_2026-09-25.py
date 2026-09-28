# ==============================================================================
# Apply an LGA -> organisation reassignment to a KoBo XLSForm (main or HH Listing),
# following the DO's own changelog conventions (Deployment_15.0/04_REFERENCE/CHANGELOG_v15.md):
#   - the tool routes by organisation: choices sheet, list l_admin2 has one `cover_org` per LGA and the
#     form filters LGAs by cover_org=${org_id}; l_admin1 has one (state, org) row per org state.
#   - an edited row is filled yellow with bold red font; a retired row is filled red with bold white font and its
#     cover_org gets `_REMOVED` appended (no org carries that, so the filter can never match it).
# What it does, given --move PCODE:from_org:to_org (repeatable):
#   1. l_admin2: cover_org from -> to for that LGA (must currently be `from`), highlighted.
#   2. l_admin1: retires every (state, org) row that a move left with no LGA (pre-existing empty rows are only reported); ADDS a
#      (state, to_org) row (copied from any row of that state, highlighted) if the gaining org has none.
#   3. settings.version -> --version.
# Then it reports: the full cell diff against the source (empty string vs blank ignored), and a mechanical cascade check
# (any real org+state with an empty LGA list; any real org left with NO state at all - the DO's README says an empty list
# "should be unreachable"). It does NOT touch the l_org_id list or the enumerator media; it reports what still needs a decision.
# --dry-run computes and reports everything in memory and writes nothing.
#
# Usage: python apply_org_reassignment_to_xlsform_2026-09-25.py --source FORM.xlsx --dest NEW.xlsx --version 25092026
#            --move NG008006:imc:fact --move NG008007:imc:fact [--dry-run]
# ==============================================================================
import argparse
import collections
import copy
import hashlib
import os
import sys

import openpyxl
from openpyxl.styles import Font, PatternFill

YEL = PatternFill("solid", fgColor="FFFFFF00")
RED = PatternFill("solid", fgColor="FFC00000")
F_EDIT = Font(bold=True, color="FFC00000")
F_RETIRE = Font(bold=True, color="FFFFFFFF")


def real(org):
    return bool(org) and not str(org).endswith("_REMOVED")


def tables(ws, hdr):
    ci, pi = hdr.index("cover_org") + 1, hdr.index("parent_admin1") + 1
    l1, l2 = [], []
    for r in range(2, ws.max_row + 1):
        ln, nm, co = ws.cell(r, 1).value, ws.cell(r, 2).value, ws.cell(r, ci).value
        if ln == "l_admin1":
            l1.append((r, nm, co))
        elif ln == "l_admin2":
            l2.append((r, nm, ws.cell(r, pi).value, co))
    return ci, pi, l1, l2


def cascade(ws, hdr, label):
    _, _, l1, l2 = tables(ws, hdr)
    lgas = collections.defaultdict(set)
    for _, nm, st, co in l2:
        if real(co):
            lgas[(co, st)].add(nm)
    states = collections.defaultdict(set)
    empties = []
    for _, st, co in l1:
        if real(co):
            states[co].add(st)
            if not lgas.get((co, st)):
                empties.append((co, st))
    orgs_with_lga = {co for _, _, _, co in l2 if real(co)}
    no_state = sorted(o for o in orgs_with_lga if not states.get(o))
    return {"empty_lga_lists": empties, "orgs_with_lgas_but_no_state_row": no_state, "n_orgs_in_l_admin1": len(states)}


def norm(v):
    return None if v == "" else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--move", action="append", required=True, help="PCODE:from_org:to_org")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    moves = [m.split(":") for m in a.move]
    assert all(len(m) == 3 for m in moves), "--move needs PCODE:from:to"

    wb = openpyxl.load_workbook(a.source)
    src = openpyxl.load_workbook(a.source)
    ws = wb["choices"]
    hdr = [c.value for c in ws[1]]
    ci, pi, l1, l2 = tables(ws, hdr)
    before = cascade(ws, hdr, "before")
    print(f"source: {a.source}")
    print(f"before: l_admin1 rows {len(l1)}, l_admin2 rows {len(l2)}, cascade {before}")
    changes = []
    states_before = collections.defaultdict(set)
    for _, nm, st, co in l2:
        if real(co):
            states_before[co].add(st)

    # 1. moves
    for pcode, frm, to in moves:
        rows = [r for r, nm, st, co in l2 if nm == pcode and co == frm]
        if not rows:
            sys.exit(f"STOP: no l_admin2 row for {pcode} with cover_org={frm} in this form (check the form version / pcode)")
        for r in rows:
            ws.cell(r, ci).value = to
            for c in (1, 2, ci):
                ws.cell(r, c).fill = copy.copy(YEL)
                ws.cell(r, c).font = copy.copy(F_EDIT)
            changes.append(f"l_admin2 {pcode} (row {r}): cover_org {frm} -> {to}")

    # 2. retire / add l_admin1 rows
    ci, pi, l1, l2 = tables(ws, hdr)
    lga_states = collections.defaultdict(set)
    for _, nm, st, co in l2:
        if real(co):
            lga_states[co].add(st)
    for r, st, co in l1:
        if real(co) and st in states_before.get(co, set()) and st not in lga_states.get(co, set()):  # only rows a move emptied
            ws.cell(r, ci).value = f"{co}_REMOVED"
            for c in (1, 2, ci):
                ws.cell(r, c).fill = copy.copy(RED)
                ws.cell(r, c).font = copy.copy(F_RETIRE)
            changes.append(f"l_admin1 {st} (row {r}): org {co} covers no LGA there any more -> {co}_REMOVED (retired)")
    ci, pi, l1, l2 = tables(ws, hdr)
    have = {(co, st) for _, st, co in l1 if real(co)}
    for org, states in sorted(lga_states.items()):
        for st in sorted(states):
            if (org, st) not in have:
                donor = next(r for r, s, co in l1 if s == st)
                last = max(r for r, _, _ in l1)
                ws.insert_rows(last + 1)
                for c in range(1, ws.max_column + 1):
                    src_cell = ws.cell(donor, c)
                    ws.cell(last + 1, c).value = src_cell.value
                    ws.cell(last + 1, c)._style = copy.copy(src_cell._style)
                ws.cell(last + 1, ci).value = org
                for c in (1, 2, ci):
                    ws.cell(last + 1, c).fill = copy.copy(YEL)
                    ws.cell(last + 1, c).font = copy.copy(F_EDIT)
                changes.append(f"l_admin1 {st}: ADDED row for gaining org {org} (row {last + 1}, copied from the {st} row of another org)")
                ci, pi, l1, l2 = tables(ws, hdr)

    # 3. version
    st = wb["settings"]
    vi = [c.value for c in st[1]].index("version") + 1
    changes.append(f"settings.version {st.cell(2, vi).value} -> {a.version}")
    st.cell(2, vi).value = a.version

    print("\nchanges:")
    for c in changes:
        print("  -", c)
    after = cascade(ws, hdr, "after")
    print(f"\nafter: cascade {after}")
    if after["empty_lga_lists"] or after["orgs_with_lgas_but_no_state_row"]:
        print("  WARNING: a real org can reach an empty list, or has LGAs but no state row: see above")
    orgs_before = {co for _, _, _, co in tables(src["choices"], hdr)[3] if real(co)}
    orgs_after = {co for _, _, _, co in l2 if real(co)}
    for o in sorted(orgs_before - orgs_after):
        print(f"  NOTE: org '{o}' now covers NO LGA in this form. It is retired from l_admin1, but is still in the l_org_id list (and the enumerator media),"
              " so it can still be picked as an organisation and would see an empty state list. Needs a DO decision.")

    # cell diff against source
    diffs = []
    for sn in src.sheetnames:
        A, B = src[sn], wb[sn]
        for r in range(1, max(A.max_row, B.max_row) + 1):
            for c in range(1, max(A.max_column, B.max_column) + 1):
                va, vb = norm(A.cell(r, c).value), norm(B.cell(r, c).value)
                if va != vb:
                    diffs.append((sn, B.cell(r, c).coordinate, va, vb))
    print(f"\ncell diff vs source (empty-string vs blank ignored): {len(diffs)} cell(s)")
    for d in diffs[:40]:
        print("   ", d)
    if a.dry_run:
        print("\n(dry-run) nothing written")
        return
    os.makedirs(os.path.dirname(a.dest) or ".", exist_ok=True)
    wb.save(a.dest)
    chk = openpyxl.load_workbook(a.dest)
    bad = 0
    for sn in src.sheetnames:
        A, B = src[sn], chk[sn]
        for r in range(1, max(A.max_row, B.max_row) + 1):
            for c in range(1, max(A.max_column, B.max_column) + 1):
                if norm(A.cell(r, c).value) != norm(B.cell(r, c).value) and (sn, B.cell(r, c).coordinate) not in {(d[0], d[1]) for d in diffs}:
                    bad += 1
    print(f"\nwritten {a.dest} ({os.path.getsize(a.dest)} bytes, md5 {hashlib.md5(open(a.dest, 'rb').read()).hexdigest()}); reload check: {bad} unexpected differences")


if __name__ == "__main__":
    main()
