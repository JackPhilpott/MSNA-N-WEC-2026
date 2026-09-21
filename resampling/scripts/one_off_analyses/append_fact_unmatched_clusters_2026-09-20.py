# ==============================================================================
# One-off, 2026-09-20. Follow-up to merge_accessibility_report_updates_2026-
# 09-20.py: FACT's 18-Sept accessibility-book merge (Cluster Accessibility
# sheet only) matched and updated 3 of its 17 rows against FACT's master
# returned file, but 12 cluster_ids had no matching row there at all -
# confirmed against the live FULL frame (all 12 real, currently FACT-
# assigned Dandume/Zurmi/Shinkafi clusters, mostly "_suppN" supplementary
# clusters drawn after this master file was last rebuilt - see 1_sampling/
# CLAUDE.md for the file's own rebuild history). Unlike the earlier GIS-
# eligible-ward append (blank placeholder rows), FACT already gave us real
# answers for these 12 - append them WITH those answers already filled in,
# not as blank rows to be re-reported later.
#
# Runs against FACT's file as it stands AFTER the 0920 merge (backed up
# separately here under its own reason tag, so the true pre-merge backup
# from the main merge script is untouched).
# ==============================================================================
import csv
import shutil
from datetime import date

import openpyxl
from openpyxl.utils import get_column_letter, range_boundaries
from openpyxl.worksheet.datavalidation import DataValidation

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
MAIN_PATH = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"
ARCHIVE_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned\_archive"
RAW_PATH = PROJECT_DIR + r"\resampling\input\partner_raw_comms\FACT\FACT_accessibility_report_update_18_Sept_2026_2009.xlsx"
FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v10_FULL.csv"
TODAY = "2026-09-20"

NEW_CLUSTER_NOTE = (
    "Newly added 2026-09-20 - FACT reported on this cluster in their 18 Sept accessibility update, but it "
    "didn't exist yet as a row in this file (a supplementary cluster drawn after this file was last rebuilt). "
    "Their answer is already filled in below, straight from that update."
)

UNMATCHED_CLUSTER_IDS = [
    "idp_NG021008_supp1", "non_idp_NG021008_supp1", "non_idp_NG021008_supp11", "non_idp_NG021008_supp13",
    "non_idp_NG021008_supp2", "non_idp_NG021008_supp3", "non_idp_NG021008_supp6", "non_idp_NG021008_supp7",
    "non_idp_NG037014_supp9", "non_idp_NG037014_supp5", "non_idp_NG037014_supp7", "non_idp_NG037011_supp4",
]


def header_idx(ws):
    header = [c.value for c in ws[1]]
    return {h: i for i, h in enumerate(header) if h}


def load_frame_metadata():
    """Real target/reserve HH + idp_population_category per cluster_id,
    straight from FULL - verified all 12 exist there and are FACT-assigned
    before this script was ever written, not assumed here."""
    out = {}
    with open(FULL_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            cid = r["cluster_id"]
            if cid in UNMATCHED_CLUSTER_IDS and cid not in out:
                cat = r["idp_population_category"]
                cat = "" if cat in ("NA", "", None) else ("In-camp" if cat == "idps in camp" else "In-host")
                out[cid] = {
                    "state": r["adm1_name"], "lga": r["adm2_name"], "ward": r["adm3_name"],
                    "pop_type": "Non-IDP" if r["pop_type"] == "non_idp" else "IDP",
                    "idp_category": cat,
                    "target_hh": r["target_households"], "reserve_hh": r["reserve_households"],
                }
    missing = set(UNMATCHED_CLUSTER_IDS) - set(out)
    if missing:
        raise RuntimeError(f"Cluster(s) not found in FULL frame - aborting, don't guess: {missing}")
    return out


def load_raw_answers():
    wb = openpyxl.load_workbook(RAW_PATH, data_only=True)
    ws = wb["Cluster Accessibility"]
    idx = header_idx(ws)
    out = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        if row is None or row[idx["Cluster ID"]] is None:
            continue
        cid = row[idx["Cluster ID"]]
        if cid in UNMATCHED_CLUSTER_IDS:
            out[cid] = {
                "accessible": row[idx["Accessible (Y/N)"]],
                "reason_category": row[idx["Reason category"]],
                "reason_notes": row[idx["Reason notes"]],
                "date_reported": row[idx["Date reported"]],
            }
    wb.close()
    missing = set(UNMATCHED_CLUSTER_IDS) - set(out)
    if missing:
        raise RuntimeError(f"Cluster(s) not found in FACT's raw update file - aborting: {missing}")
    return out


def main():
    frame_meta = load_frame_metadata()
    raw_answers = load_raw_answers()

    bak = f"{ARCHIVE_DIR}\\FACT_accessibility_report_pre_0920_new_cluster_append_{TODAY}.xlsx"
    shutil.copy2(MAIN_PATH, bak)
    print(f"backed up -> {bak}")

    wb = openpyxl.load_workbook(MAIN_PATH)
    ws = wb["Cluster Accessibility"]
    idx = header_idx(ws)

    # Sanity check: none of these 12 should already be present (re-verify
    # directly against the live file, not just trust the earlier merge run's
    # printed list, in case anything changed in between).
    existing_ids = set()
    for row_cells in ws.iter_rows(min_row=2):
        vals = [c.value for c in row_cells]
        if vals[idx["Cluster ID"]] is not None:
            existing_ids.add(vals[idx["Cluster ID"]])
    already_present = existing_ids & set(UNMATCHED_CLUSTER_IDS)
    if already_present:
        raise RuntimeError(f"These are already present - would duplicate, aborting: {already_present}")

    cur_last_row = ws.max_row
    while cur_last_row > 1 and all(c.value is None for c in ws[cur_last_row]):
        cur_last_row -= 1

    for i, cid in enumerate(UNMATCHED_CLUSTER_IDS):
        meta = frame_meta[cid]
        ans = raw_answers[cid]
        r = cur_last_row + 1 + i
        values = {
            "State": meta["state"], "LGA": meta["lga"], "Ward (GRID3)": meta["ward"],
            "Pop Type": meta["pop_type"], "Cluster ID": cid, "IDP Category": meta["idp_category"],
            "Target HHs (primary)": meta["target_hh"], "Reserve HHs": meta["reserve_hh"],
            "Accessible (Y/N)": ans["accessible"], "Reason category": ans["reason_category"],
            "Reason notes": ans["reason_notes"], "Date reported": ans["date_reported"],
        }
        if "Why flagged" in idx:
            values["Why flagged"] = NEW_CLUSTER_NOTE
        for col_name, col_i in idx.items():
            if col_name in values:
                ws.cell(row=r, column=col_i + 1, value=values[col_name])

    new_last_row = cur_last_row + len(UNMATCHED_CLUSTER_IDS)

    # No Table object on this sheet (checked directly), but it DOES have 2
    # data validations (Accessible/Reason dropdowns) - extend their ranges
    # to cover the new rows too, same rebuild-by-formula approach used
    # elsewhere in this batch.
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
        new_dv.add(f"{get_column_letter(col)}2:{get_column_letter(col)}{new_last_row}")
        ws.add_data_validation(new_dv)

    wb.save(MAIN_PATH)
    print(f"{len(UNMATCHED_CLUSTER_IDS)} new cluster row(s) appended (rows {cur_last_row + 1}-{new_last_row}), "
          f"each with FACT's real answer already filled in.")
    print(f"saved -> {MAIN_PATH}")


if __name__ == "__main__":
    main()
