"""
Merge the 2026-09-14 (_1409) partner returns for INTERSOS and Solidarites
into their master accessibility_reports_returned files, per Jack's
established 2026-09-13 policy (see memory:
project_accessibility_report_cleanup_1309_2026-09-13):

1. Blank in the new return where the master already has an answer ->
   preserve the master's existing answer (a blank means "not re-answered
   this round", not "cleared").
2. Newly answered (blank in master, answered in the new return) -> take
   the new value.
3. A real status flip (both sides answered, value differs) -> take the
   new (raw) value; this is the partner reporting a change.
4. Yes + blank Reason category -> auto-fill "N/A - fully accessible".
5. No + blank Reason category -> "Other" + a placeholder follow-up note.
6. Reason-only enrichment (status unchanged, raw supplies a reason where
   master had none) -> take the raw reason.

Backs up both master files to accessibility_reports_returned/_archive/
before writing.
"""
import shutil
from pathlib import Path
import openpyxl

RESAMPLING_DIR = Path(__file__).resolve().parents[2]
RETURNED_DIR = RESAMPLING_DIR / "input" / "accessibility_reports_returned"
ARCHIVE_DIR = RETURNED_DIR / "_archive"
RAW_COMMS_DIR = RESAMPLING_DIR / "input" / "partner_raw_comms"

PARTNERS = [
    ("INTERSOS", RAW_COMMS_DIR / "INTERSOS" / "INTERSOS_accessibility_report-INTERSOS_1409.xlsx",
     RETURNED_DIR / "INTERSOS_accessibility_report.xlsx"),
    ("Solidarités", RAW_COMMS_DIR / "Solidarités" / "Solidarités_accessibility_report_1409.xlsx",
     RETURNED_DIR / "Solidarités_accessibility_report.xlsx"),
]

SHEETS = [
    # sheet, key_fn (indices), acc_idx, reason_idx, reason_notes_idx, pct_idx, date_idx, reportedby_idx, source_idx
    ("Ward Accessibility", lambda r: (r[0], r[1], r[2]), 10, 11, 12, 13, 14, 15, 16),
    ("Cluster Accessibility", lambda r: (r[0], r[1], r[2], r[4]), 8, 9, 10, 11, 12, 13, 14),
]

FOLLOWUP_NOTE = "partner marked inaccessible but did not provide a reason category on return - follow up needed"


def load_rows(path, sheet):
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb[sheet]
    rows = list(ws.iter_rows(values_only=True))
    return rows[0], rows[1:]


summary_lines = []

for partner, raw_path, master_path in PARTNERS:
    summary_lines.append(f"\n=== {partner} ===")

    ARCHIVE_DIR.mkdir(exist_ok=True)
    backup_path = ARCHIVE_DIR / f"{master_path.stem}_pre_1409_merge_2026-09-14.xlsx"
    shutil.copy2(master_path, backup_path)
    summary_lines.append(f"  backed up master to {backup_path.name}")

    wb_master = openpyxl.load_workbook(master_path)  # keep formatting/data-validation, write in place

    for sheet_name, keyfn, acc_idx, reason_idx, reason_notes_idx, pct_idx, date_idx, reportedby_idx, source_idx in SHEETS:
        _, raw_rows = load_rows(raw_path, sheet_name)
        raw_by_key = {keyfn(r): r for r in raw_rows}

        ws = wb_master[sheet_name]
        header = [c.value for c in ws[1]]
        n_status_flip = n_new_answer = n_reason_fill_yes = n_reason_fill_no = n_reason_enrich = n_preserved_blank = 0

        for row_idx in range(2, ws.max_row + 1):
            row_vals = [ws.cell(row=row_idx, column=c + 1).value for c in range(len(header))]
            k = keyfn(row_vals)
            if k not in raw_by_key:
                continue
            rraw = raw_by_key[k]
            macc = row_vals[acc_idx]
            racc = rraw[acc_idx]
            mreason = row_vals[reason_idx]
            rreason = rraw[reason_idx]

            if racc is None:
                # Raw didn't re-answer this row this round; never blank an
                # existing master answer.
                if macc is not None:
                    n_preserved_blank += 1
                continue

            if macc != racc:
                n_status_flip += 1 if macc is not None else 0
                n_new_answer += 1 if macc is None else 0
                # Take the raw status + whatever raw provided for the
                # provenance/reason columns.
                ws.cell(row=row_idx, column=acc_idx + 1).value = racc
                if racc == "Yes" and not rreason:
                    new_reason = "N/A - fully accessible"
                    new_reason_notes = rraw[reason_notes_idx]
                    n_reason_fill_yes += 1
                elif racc == "No" and not rreason:
                    new_reason = "Other"
                    new_reason_notes = FOLLOWUP_NOTE
                    n_reason_fill_no += 1
                else:
                    new_reason = rreason
                    new_reason_notes = rraw[reason_notes_idx]
                ws.cell(row=row_idx, column=reason_idx + 1).value = new_reason
                ws.cell(row=row_idx, column=reason_notes_idx + 1).value = new_reason_notes
                for src_idx in (pct_idx, date_idx, reportedby_idx, source_idx):
                    if src_idx < len(rraw):
                        ws.cell(row=row_idx, column=src_idx + 1).value = rraw[src_idx]
            elif mreason != rreason and rreason:
                # Status unchanged, raw enriches a previously-blank reason.
                ws.cell(row=row_idx, column=reason_idx + 1).value = rreason
                if rraw[reason_notes_idx] is not None:
                    ws.cell(row=row_idx, column=reason_notes_idx + 1).value = rraw[reason_notes_idx]
                for src_idx in (pct_idx, date_idx, reportedby_idx, source_idx):
                    if src_idx < len(rraw) and rraw[src_idx] is not None:
                        ws.cell(row=row_idx, column=src_idx + 1).value = rraw[src_idx]
                n_reason_enrich += 1

        summary_lines.append(
            f"  {sheet_name}: {n_status_flip} status flips, {n_new_answer} newly answered, "
            f"{n_reason_fill_yes} Yes/blank-reason auto-filled, {n_reason_fill_no} No/blank-reason "
            f"-> Other+followup, {n_reason_enrich} reason-only enrichments, "
            f"{n_preserved_blank} existing answers preserved (raw left blank)"
        )

    wb_master.save(master_path)
    summary_lines.append(f"  wrote {master_path.name}")

print("\n".join(summary_lines))
