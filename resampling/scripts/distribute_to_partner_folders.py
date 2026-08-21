# ==============================================================================
# Copies each partner's staged accessibility report
# (resampling/input/accessibility_reports_generated/<Partner>_accessibility_
# report.xlsx) into that partner's existing package folder root in
# "3. External coordination\NGA MSNA 2026 Package\<Partner>\" - the same
# folder build_partner_dc_packages.py already writes
# "<Partner>_sampling_points_summary.xlsx" into.
#
# HARD CONSTRAINT (see ../../CLAUDE.md): that package tree is synced to
# SharePoint and individually shared with all 19 partners already.
# SharePoint permissions are tied to folder item IDs, not path/name - a
# partner's TOP-LEVEL folder must NEVER be deleted or recreated (even
# implicitly, e.g. by a naive "wipe and rebuild" pattern), or their sharing
# breaks silently. This script only ever does a plain single-file copy into
# an ALREADY-EXISTING partner folder - it never creates, deletes, or
# renames a partner's top-level folder, and if that folder doesn't already
# exist for some partner, it skips them and warns rather than creating one
# (a folder created fresh here wouldn't carry the partner's existing
# SharePoint sharing anyway, so silently creating it would look like
# success while actually producing a folder the partner can't see).
#
# Deliberately NOT robocopy /MIR: /MIR deletes anything at the destination
# not present in the source, which would be actively dangerous here - each
# partner's folder already holds KMLs, cluster-guide docx files, the sampling
# points workbook, SOP/How-To-Use PDFs, etc. that must not be touched. This
# script places exactly one new file among many existing ones, so a plain
# single-file copy is both simpler and safer than a mirror operation.
#
# Safety-by-default: run with no arguments for a DRY RUN (prints what would
# happen, writes nothing). Pass --execute to actually copy files. Plain
# --execute never overwrites an existing destination file (it may already
# carry partner-filled-in accessibility data) - it only fills in partners
# who don't have a file there yet.
#
# --replace-existing (added 2026-08-21, only meaningful together with
# --execute) additionally updates partners who DO already have a destination
# file - e.g. after a fix to 01_generate_accessibility_reports.py's ward
# logic that every partner's file needs picking up. Before overwriting, it
# reads the CURRENT destination file for any of the 5 partner-input columns
# already filled in (Accessible (Y/N), Reason category, Reason notes, % of
# target achieved so far, Date reported) on either sheet - keyed by
# (State, LGA, Ward (GRID3)) for Ward Accessibility, Cluster ID for Cluster
# Accessibility, both stable keys that survive the ward-count fix. Any
# filled answers found are re-applied onto the matching row(s) of the fresh
# source workbook before it's written to the destination, so a partner's
# real reported answers are never lost just because the underlying template
# was regenerated. A destination with nothing filled in is simply replaced
# outright. Checked 2026-08-21 against all 19 live destination files before
# this flag was used for real: INTERSOS (34 Ward Accessibility rows) and
# COOPI (2 Cluster Accessibility rows) had genuine partner input; the other
# 17 were still blank.
#
# Every successful copy/replace is logged to
# resampling/output/distribution_log.csv (append-only, mirrors the master
# request log's append-only convention) - this is the workflow's record of
# which partners have actually received their report and when.
# ==============================================================================
import csv
import glob
import os
import re
import shutil
import sys
from datetime import datetime

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
SRC_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_generated"
# Same partner package root as build_partner_dc_packages.py.
OUT_ROOT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
LOG_CSV = PROJECT_DIR + r"\resampling\output\distribution_log.csv"

LOG_FIELDS = ["timestamp", "partner", "dest_path", "action"]

INPUT_COLUMNS = ["Accessible (Y/N)", "Reason category", "Reason notes", "% of target achieved so far", "Date reported"]
WARD_KEY_COLUMNS = ["State", "LGA", "Ward (GRID3)"]


def extract_filled_input(path):
    """Reads an existing destination workbook and returns
    {"Ward Accessibility": {key: {col: value}}, "Cluster Accessibility": {key: {col: value}}}
    for every row that has ANY of the 5 input columns filled in. Returns None
    sheet-by-sheet if that sheet/columns aren't present (e.g. an unexpected
    file). Read-only - never modifies the file passed in.
    """
    wb = openpyxl.load_workbook(path, data_only=True)
    result = {}

    if "Ward Accessibility" in wb.sheetnames:
        ws = wb["Ward Accessibility"]
        headers = [c.value for c in ws[1]]
        if all(c in headers for c in WARD_KEY_COLUMNS) and any(c in headers for c in INPUT_COLUMNS):
            idx = {h: i for i, h in enumerate(headers)}
            by_key = {}
            for row in ws.iter_rows(min_row=2, values_only=True):
                filled = {c: row[idx[c]] for c in INPUT_COLUMNS if c in idx and row[idx[c]] not in (None, "")}
                if filled:
                    key = tuple(row[idx[c]] for c in WARD_KEY_COLUMNS)
                    by_key[key] = filled
            result["Ward Accessibility"] = by_key

    if "Cluster Accessibility" in wb.sheetnames:
        ws = wb["Cluster Accessibility"]
        headers = [c.value for c in ws[1]]
        if "Cluster ID" in headers and any(c in headers for c in INPUT_COLUMNS):
            idx = {h: i for i, h in enumerate(headers)}
            by_key = {}
            for row in ws.iter_rows(min_row=2, values_only=True):
                filled = {c: row[idx[c]] for c in INPUT_COLUMNS if c in idx and row[idx[c]] not in (None, "")}
                if filled:
                    by_key[row[idx["Cluster ID"]]] = filled
            result["Cluster Accessibility"] = by_key

    return result


def apply_filled_input(src_path, dest_path, filled_by_sheet):
    """Loads the freshly-generated src workbook, writes any previously-
    filled answers (from extract_filled_input) onto the matching rows, and
    saves the RESULT to dest_path - never back to src_path. This keeps
    resampling/input/accessibility_reports_generated/ always a pristine,
    blank-template copy safe to regenerate wholesale (per 01's own rerun-
    safety rule) - merged partner answers only ever live at the destination
    (and, if a copy is pulled back for re-ingestion, in returned/), never in
    the local staging copy itself. Returns the count of rows actually
    matched and updated, per sheet, so the caller can report/log it. Rows
    in the fresh sheet with no matching key (e.g. a ward that no longer
    exists for this partner) are left as-is and not counted - flagged to
    the caller via unmatched count."""
    wb = openpyxl.load_workbook(src_path)
    counts = {}
    unmatched = {}

    if "Ward Accessibility" in filled_by_sheet and "Ward Accessibility" in wb.sheetnames:
        ws = wb["Ward Accessibility"]
        headers = [c.value for c in ws[1]]
        idx = {h: i for i, h in enumerate(headers)}
        key_idx = [idx[c] for c in WARD_KEY_COLUMNS]
        by_key = dict(filled_by_sheet["Ward Accessibility"])
        n = 0
        for row in ws.iter_rows(min_row=2):
            key = tuple(row[i].value for i in key_idx)
            if key in by_key:
                for col, val in by_key.pop(key).items():
                    row[idx[col]].value = val
                n += 1
        counts["Ward Accessibility"] = n
        unmatched["Ward Accessibility"] = list(by_key.keys())

    if "Cluster Accessibility" in filled_by_sheet and "Cluster Accessibility" in wb.sheetnames:
        ws = wb["Cluster Accessibility"]
        headers = [c.value for c in ws[1]]
        idx = {h: i for i, h in enumerate(headers)}
        by_key = dict(filled_by_sheet["Cluster Accessibility"])
        n = 0
        for row in ws.iter_rows(min_row=2):
            key = row[idx["Cluster ID"]].value
            if key in by_key:
                for col, val in by_key.pop(key).items():
                    row[idx[col]].value = val
                n += 1
        counts["Cluster Accessibility"] = n
        unmatched["Cluster Accessibility"] = list(by_key.keys())

    wb.save(dest_path)
    return counts, unmatched


def safe_folder_name(s):
    # Must match build_partner_dc_packages.py's safe_folder_name() exactly,
    # so files land in the same folder that script already created.
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


def partner_name_from_path(path):
    base = os.path.basename(path)
    return base[: -len("_accessibility_report.xlsx")]


def log_action(rows):
    if not rows:
        return
    write_header = not os.path.exists(LOG_CSV) or os.path.getsize(LOG_CSV) == 0
    os.makedirs(os.path.dirname(LOG_CSV), exist_ok=True)
    with open(LOG_CSV, "a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=LOG_FIELDS)
        if write_header:
            writer.writeheader()
        for r in rows:
            writer.writerow(r)


def run(execute, replace_existing):
    staged_files = sorted(glob.glob(os.path.join(SRC_DIR, "*_accessibility_report.xlsx")))
    if not staged_files:
        print(f"No staged reports found in {SRC_DIR}.")
        return

    mode = "EXECUTE" if execute else "DRY RUN (pass --execute to actually copy)"
    if replace_existing:
        mode += " + REPLACE-EXISTING (merge-preserving partner-filled answers)"
    print(f"Mode: {mode}\n")

    copied, replaced, merged, skipped_exists, skipped_missing_folder, failed = [], [], [], [], [], []
    log_rows = []

    for src_path in staged_files:
        partner = partner_name_from_path(src_path)
        dest_root = os.path.join(OUT_ROOT, safe_folder_name(partner))
        dest_path = os.path.join(dest_root, os.path.basename(src_path))

        if not os.path.isdir(dest_root):
            print(f"  SKIP (no existing partner folder): {partner} -> {dest_root}")
            skipped_missing_folder.append(partner)
            continue

        dest_exists = os.path.exists(dest_path)

        if dest_exists and not replace_existing:
            print(f"  SKIP (already exists at destination, may carry partner input): {partner}")
            skipped_exists.append(partner)
            continue

        if dest_exists and replace_existing:
            try:
                filled_by_sheet = extract_filled_input(dest_path)
            except Exception as e:
                print(f"  WARNING: could not read existing destination for {partner}, skipping to be safe: {e}")
                failed.append(partner)
                continue
            has_filled = any(filled_by_sheet.get(s) for s in ("Ward Accessibility", "Cluster Accessibility"))

            if not execute:
                action = "WOULD MERGE+REPLACE" if has_filled else "WOULD REPLACE (no existing input found)"
                print(f"  {action}: {partner} -> {dest_path}")
                (merged if has_filled else replaced).append(partner)
                continue

            try:
                if has_filled:
                    counts, unmatched = apply_filled_input(src_path, dest_path, filled_by_sheet)
                    n_total = sum(counts.values())
                    n_unmatched = sum(len(v) for v in unmatched.values())
                    print(f"  MERGED+REPLACED: {partner} -> {dest_path} ({n_total} answered row(s) carried over"
                          + (f", {n_unmatched} could not be matched to a current row - check manually" if n_unmatched else "") + ")")
                    merged.append(partner)
                    if n_unmatched:
                        for sheet, keys in unmatched.items():
                            for k in keys:
                                print(f"    UNMATCHED in {sheet}: {k}")
                    log_rows.append({
                        "timestamp": datetime.now().isoformat(timespec="seconds"),
                        "partner": partner, "dest_path": dest_path,
                        "action": f"merged_and_replaced ({n_total} rows carried over, {n_unmatched} unmatched)",
                    })
                else:
                    shutil.copy2(src_path, dest_path)
                    print(f"  REPLACED (no existing input found): {partner} -> {dest_path}")
                    replaced.append(partner)
                    log_rows.append({
                        "timestamp": datetime.now().isoformat(timespec="seconds"),
                        "partner": partner, "dest_path": dest_path, "action": "replaced_no_existing_data",
                    })
            except PermissionError as e:
                print(f"  WARNING: could not replace {partner} - destination appears locked/syncing: {e}")
                failed.append(partner)
            continue

        if not execute:
            print(f"  WOULD COPY: {partner} -> {dest_path}")
            copied.append(partner)
            continue

        try:
            shutil.copy2(src_path, dest_path)
            print(f"  COPIED: {partner} -> {dest_path}")
            copied.append(partner)
            log_rows.append({
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "partner": partner, "dest_path": dest_path, "action": "copied",
            })
        except PermissionError as e:
            print(f"  WARNING: could not copy {partner} - destination appears locked/syncing: {e}")
            failed.append(partner)

    log_action(log_rows)

    print(f"\n{'Would copy' if not execute else 'Copied'} (new): {len(copied)}")
    if replace_existing:
        print(f"{'Would merge+replace' if not execute else 'Merged+replaced'}: {len(merged)} {merged if merged else ''}")
        print(f"{'Would replace' if not execute else 'Replaced'} (no existing input): {len(replaced)}")
    else:
        print(f"Skipped (already at destination): {len(skipped_exists)}")
    print(f"Skipped (no existing partner folder - check name/spelling): {len(skipped_missing_folder)} {skipped_missing_folder if skipped_missing_folder else ''}")
    if failed:
        print(f"Failed (locked/syncing - rerun later): {len(failed)} {failed}")


if __name__ == "__main__":
    run(execute="--execute" in sys.argv, replace_existing="--replace-existing" in sys.argv)
