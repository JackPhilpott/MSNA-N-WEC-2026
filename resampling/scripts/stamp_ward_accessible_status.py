"""
Populates ward_accessible_status on a staged new_households.csv, using the
exact same (adm1_name, adm2_name, adm3_name) -> (State, LGA, Ward (GRID3))
lookup against master_accessibility_status_ward_level.csv that
05_build_accessibility_impact_workbook.py's classify_households() already
uses (proven correct all night, 2026-09-07). Fixes a real gap found that
night: new supplementary rows never got this column populated at all, so
merge_partner_resample_batch.R's own is.na()-passes-through exclusion logic
had nothing to act on and let inaccessible-ward rows straight into WORKING
(714 of 1,308 FACT Non-IDP rows, that incident - see CLAUDE.md's Incident
2026-09-07 for the full writeup). Overwrites the file in place, matching
the column's real schema (FULL carries every row regardless of status;
WORKING's own merge-time filter is what actually excludes based on this
column).

Run this on every staged new_households*.csv BEFORE merge_partner_resample_
batch.R, for every future supplementary draw - not optional, not a one-off.
As of 2026-09-08, merge_partner_resample_batch.R also enforces this via
assert_fresh() (mode="stop") rather than relying on that sentence alone -
it will refuse to proceed if this wasn't run since the master ward CSV was
last updated.

CORRECTED 2026-09-08: previously, a row with no match in the master ward
lookup silently got ward_accessible_status="Accessible" (tallied as
"no_entry_defaults_accessible" - the same "unknown defaults to accessible"
convention responsible for the 2026-09-07 incident, just relocated to this
script's own matching failure instead of the field it was built to fix).
Now leaves it genuinely blank and reports the count/keys so it's visible,
not silently defaulted - merge_partner_resample_batch.R treats a blank
ward_accessible_status as excluded-pending-review, not accessible.

Usage: python stamp_ward_accessible_status.py <new_households.csv>
"""
import csv
import sys

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
MASTER_WARD_CSV = PROJECT_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"

def load_ward_status():
    status = {}
    with open(MASTER_WARD_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            key = (row["State"], row["LGA"], row["Ward (GRID3)"])
            status[key] = row["Accessible status"]
    return status

def main(path):
    ward_status = load_ward_status()
    with open(path, encoding="utf-8") as f:
        r = csv.DictReader(f)
        fieldnames = list(r.fieldnames)
        rows = list(r)

    if "ward_accessible_status" not in fieldnames:
        fieldnames.append("ward_accessible_status")

    tally = {"Accessible": 0, "Inaccessible": 0, "unmatched_left_blank": 0}
    unmatched_keys = set()
    for row in rows:
        key = (row.get("adm1_name", ""), row.get("adm2_name", ""), row.get("adm3_name", ""))
        st = ward_status.get(key)
        if st is None:
            row["ward_accessible_status"] = ""
            tally["unmatched_left_blank"] += 1
            unmatched_keys.add(key)
        else:
            row["ward_accessible_status"] = st
            tally[st] = tally.get(st, 0) + 1

    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

    if tally["unmatched_left_blank"] > 0:
        print(f"WARNING: {tally['unmatched_left_blank']} row(s) across {len(unmatched_keys)} "
              f"distinct (State, LGA, Ward) key(s) had no match in the master ward lookup - "
              f"left blank, NOT defaulted to Accessible. These will be excluded from WORKING "
              f"pending review when merge_partner_resample_batch.R runs. Unmatched keys:")
        for key in sorted(unmatched_keys):
            print(f"    {key}")

    print(f"{path}: {len(rows)} rows stamped. {tally}")

if __name__ == "__main__":
    main(sys.argv[1])
