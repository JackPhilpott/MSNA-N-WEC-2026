# ==============================================================================
# Resweeps ward_accessible_status on EVERY row of FULL against the current
# master_accessibility_status_ward_level.csv - not just staged new rows
# (that's stamp_ward_accessible_status.py's job, run before a merge).
#
# Gap found 2026-09-07/08 while making FACT's numbers honest (see CLAUDE.md
# "FACT legacy-gap" / Update 2026-09-08c addendum): rows merged into FULL
# long ago carry whatever ward_accessible_status they were stamped with AT
# THE TIME (often "Accessible", sometimes blank) - nothing has ever gone
# back and refreshed it since, so a ward that has since been reported
# Inaccessible doesn't retroactively exclude the rows already sitting in it.
# refresh_working_frame_daily.R filters WORKING using exactly this column,
# so it inherits the staleness rather than fixing it - confirmed directly on
# 3 known-Inaccessible FACT wards (Borno/Abadam/Gudumbali East+West,
# Borno/Gubio/Dabira): all still stored "Accessible" or blank in FULL.
#
# CORRECTED before ever reaching WORKING: a first draft of this script
# copied stamp_ward_accessible_status.py's unmatched-stays-blank rule
# (blank = excluded-pending-review). Wrong for a FULL-frame-wide resweep -
# that rule is right for stamp_ward_accessible_status.py's actual job
# (freshly staged supplementary rows, always within an actively-monitored
# state, where a match failure is a genuine anomaly), but FULL spans states
# this accessibility-reporting exercise has never covered at all (Kano,
# Niger, Kogi - 100% unmatched; Kaduna/Benue/Plateau/Nasarawa mostly so).
# Applying the strict rule there would have excluded ~22,000+ rows nationally
# that were never "unknown, needs review" - they're simply outside scope.
# Caught by checking the unmatched count (43,204 - nowhere near "vanishingly
# rare") against classify_households()'s own docstring
# (05_build_accessibility_impact_workbook.py, proven-correct all night)
# BEFORE running refresh_working_frame_daily.R on top of it - restored FULL
# from the archive below and rebuilt with the right default. Matches
# classify_households()'s own `ward_status.get(key, "Accessible")`: unmatched
# defaults Accessible, same as "never reported" (rule 1), not "match failure"
# (rule 3 - which is specifically about a HOUSEHOLD failing to geo-reconcile
# to any ward at all, not a ward being outside the master file's covered
# state list). Within the actual monitored states (Katsina/Borno/Sokoto/
# Adamawa/Zamfara/Yobe/Kebbi), unmatched is 0-4% - genuinely rare, as
# expected; not chased further here since the correct default (Accessible)
# is the same outcome either way (never-reported vs. a real reconciliation
# gap). Run this BEFORE refresh_working_frame_daily.R, then that script's own
# fresh-every-run WORKING rebuild does the rest (drops now-excluded rows
# from the to-do list, credits any real completed interviews among them via
# stranded-achieved).
#
# Scope note: this is necessarily a FULL-frame-wide fix, not a FACT-only
# one - the stale-status mechanism isn't specific to FACT, so this corrects
# every partner's legacy rows in the same pass. Reported per-partner below
# so the FACT-specific effect (what was actually asked for) is visible
# alongside the full national picture (what actually happened).
#
# archive_before_fix() equivalent inlined here (duplicated from
# scripts/stamp_frame_version.R's version, not imported) since this touches
# FULL, which that function's own default file list doesn't cover.
#
# Usage: python resweep_full_ward_accessible_status_2026-09-07.py
# ==============================================================================
import csv
import os
import shutil
from collections import Counter, defaultdict
from datetime import date

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
SF_DIR = os.path.join(PROJECT_DIR, "output", "data", "data_collection")
FULL_CSV = os.path.join(SF_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv")
MASTER_WARD_CSV = os.path.join(PROJECT_DIR, "resampling", "output", "master_accessibility_status_ward_level.csv")
ARCHIVE_DIR = os.path.join(SF_DIR, "_archive", f"{date.today().isoformat()}_pre_full_ward_accessible_resweep")


def archive_before_fix():
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    shutil.copy2(FULL_CSV, os.path.join(ARCHIVE_DIR, os.path.basename(FULL_CSV)))
    print(f"archive_before_fix(): snapshot saved to {ARCHIVE_DIR} before proceeding.")


def load_ward_status():
    status = {}
    with open(MASTER_WARD_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            key = (row["State"], row["LGA"], row["Ward (GRID3)"])
            status[key] = row["Accessible status"]
    return status


def main():
    archive_before_fix()
    ward_status = load_ward_status()

    with open(FULL_CSV, encoding="utf-8") as f:
        r = csv.DictReader(f)
        fieldnames = list(r.fieldnames)
        rows = list(r)

    if "ward_accessible_status" not in fieldnames:
        fieldnames.append("ward_accessible_status")

    transitions = Counter()
    partner_flips_to_inaccessible = defaultdict(int)
    unmatched_keys = set()
    n_unmatched = 0

    for row in rows:
        old = row.get("ward_accessible_status", "") or ""
        key = (row.get("adm1_name", ""), row.get("adm2_name", ""), row.get("adm3_name", ""))
        st = ward_status.get(key)
        if st is None:
            n_unmatched += 1
            unmatched_keys.add(key)
        # Matches classify_households()'s proven-correct default exactly:
        # unmatched -> Accessible (never reported / outside monitored scope
        # is not evidence of inaccessibility), not blank/excluded. See header
        # note - this differs deliberately from stamp_ward_accessible_
        # status.py's stricter rule, which is right for its own narrower job.
        new = st if st is not None else "Accessible"
        row["ward_accessible_status"] = new
        transitions[(old, new)] += 1
        if new == "Inaccessible" and old != "Inaccessible":
            partners = [p.strip() for p in row.get("partners_covering", "").split(",") if p.strip() and p.strip() != "NA"]
            for p in partners:
                partner_flips_to_inaccessible[p] += 1

    with open(FULL_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

    print(f"\n{FULL_CSV}: {len(rows)} rows resweeped.\n")
    print("Transitions (old ward_accessible_status -> new), top 15 by count:")
    for (old, new), n in transitions.most_common(15):
        print(f"  {old or '(blank)'!r:>16} -> {new or '(blank)'!r:<16} : {n}")

    n_newly_inaccessible = sum(n for (old, new), n in transitions.items() if new == "Inaccessible" and old != "Inaccessible")
    n_newly_accessible = sum(n for (old, new), n in transitions.items() if old == "Inaccessible" and new != "Inaccessible")
    print(f"\nRows newly flipped to Inaccessible (were not before): {n_newly_inaccessible}")
    print(f"Rows newly flipped OFF Inaccessible (were Inaccessible, now something else): {n_newly_accessible}")
    print(f"Rows with no master-ward match (defaulted to Accessible, per classify_households()'s rule): {n_unmatched} across {len(unmatched_keys)} distinct ward keys")

    print("\nRows newly flipped to Inaccessible, by partner (a row can count for >1 partner in shared LGAs):")
    for p, n in sorted(partner_flips_to_inaccessible.items(), key=lambda kv: -kv[1]):
        print(f"  {p}: {n}")


if __name__ == "__main__":
    main()
