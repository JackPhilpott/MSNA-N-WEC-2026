# ==============================================================================
# Applies FACT's 10-LGA blanket closure (Emmanuel Atam email, 2026-09-28
# 10:03 UTC, read directly from resampling/input/partner_raw_comms/FACT/
# "Re Follow up Request for Overall Cluster Verification_dropLGAs_2809.msg" -
# verified against the email body before writing this, not just the relayed
# summary) into FACT_accessibility_report.xlsx's "Ward Accessibility" sheet,
# the same file every other partner accessibility update goes through
# (02_ingest_accessibility_reports.py / 04_build_master_accessibility_
# status.py's own input - see 04's build_reports_present_lookup() docstring).
#
# FACT's email is unambiguous that each LGA is closed WHOLESALE for the rest
# of this MSNA round - not a partial ward list - so every row for these 10
# LGAs where Accessible currently reads "Yes" or is blank (blank defaults to
# Accessible per 04's own stated default rule) gets flipped to "No". Rows
# already "No" for a prior, more specific reason are left untouched - this is
# a correction of what's wrong (shows Accessible, shouldn't), not a blanket
# overwrite of what's already right.
#
# Reason category mapped to this file's own existing vocabulary (checked
# directly: "Insecurity / conflict", "Physical access (terrain, flooding,
# roads)", "Access denied by authorities / community", "Other" are the
# categories already in use) - one category per LGA, based on FACT's own
# stated reason; Reason notes carries FACT's EXACT wording, not a paraphrase,
# so nothing is lost or invented.
# ==============================================================================
import shutil
from datetime import date

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
REPORT_PATH = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"

TODAY = date(2026, 9, 28)

# (LGA name as it appears in this file's own LGA column, reason category, exact reason text from the email)
CLOSURES = {
    "Guyuk": ("Physical access (terrain, flooding, roads)",
              "No Access Due to very bad terrain. We have over 5 injured enumerators from this LGA. We cannot go back until the rainy season is over"),
    "Mayo-Belwa": ("Access denied by authorities / community",
                   "Several security incidents. We previously accessed the location and then further access was denied by community/local vigilante groups"),
    "Sabuwa": ("Access denied by authorities / community",
               "Community leaders informed us that the communities are unsafe. They rejected our attempts and told us not to come back"),
    "Dan Musa": ("Access denied by authorities / community",
                 "Community leaders informed us that the communities are unsafe. They rejected our attempts and told us not to come back"),
    "Safana": ("Insecurity / conflict",
               "This LGA is completely inaccessible"),
    "Dandi": ("Insecurity / conflict",
              "We collected data for some weeks. Serious security attack. AOG continues to attack, so we cannot go back"),
    "Gudu": ("Insecurity / conflict",
             "Bandits are more in control of the LGA now. We cannot go back, especially not right now"),
    "Tureta": ("Insecurity / conflict",
               "Bandits are more in control of the LGA now. We cannot go back, especially not right now"),
    "Geidam": ("Insecurity / conflict",
               "Massive attacks in the whole of Geidam, the area is displaced, so it cannot be completed"),
    "Tarmua": ("Insecurity / conflict",
               "AOGs attacked our enumerators in the LGA, and security information confirms the AOGs are still there. We were told by a community leader not to come back for now"),
}
REASON_NOTE_SUFFIX = " [FACT, Emmanuel Atam email 2026-09-28 10:03 UTC - LGA closed for the rest of this MSNA round, blanket closure]"

BACKUP_PATH = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned\_archive\FACT_accessibility_report_pre_10LGA_closure_2026-09-28.xlsx"


def main():
    shutil.copy2(REPORT_PATH, BACKUP_PATH)
    print(f"Backed up to {BACKUP_PATH}")

    wb = openpyxl.load_workbook(REPORT_PATH)
    ws = wb["Ward Accessibility"]
    headers = [c.value for c in ws[1]]
    idx = {h: i + 1 for i, h in enumerate(headers)}  # 1-based column numbers for cell writes

    changed = 0
    already_no = 0
    unmatched_lgas = set(CLOSURES.keys())
    for row_cells in ws.iter_rows(min_row=2):
        lga = row_cells[idx["LGA"] - 1].value
        if lga not in CLOSURES:
            continue
        unmatched_lgas.discard(lga)
        acc_cell = row_cells[idx["Accessible (Y/N)"] - 1]
        current = acc_cell.value
        if current == "No":
            already_no += 1
            continue
        category, reason = CLOSURES[lga]
        acc_cell.value = "No"
        row_cells[idx["Reason category"] - 1].value = category
        row_cells[idx["Reason notes"] - 1].value = reason + REASON_NOTE_SUFFIX
        row_cells[idx["Date reported"] - 1].value = TODAY
        changed += 1

    wb.save(REPORT_PATH)
    print(f"Flipped {changed} ward row(s) Accessible -> No across {len(CLOSURES)} LGAs.")
    print(f"{already_no} row(s) already read 'No' - left untouched (kept their existing reason).")
    if unmatched_lgas:
        print(f"WARNING: {len(unmatched_lgas)} LGA(s) named in the closure list had NO rows at all in this sheet: {sorted(unmatched_lgas)}")
    else:
        print("All 10 closure LGAs matched rows in the sheet.")


if __name__ == "__main__":
    main()
