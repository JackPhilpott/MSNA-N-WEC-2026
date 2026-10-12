# ==============================================================================
# 2026-10-12: verifies the Maru accessibility change + today's top-up merges against the pre-Maru archive.
# Exit 1 on any failure.
#   FULL vs the archive:
#     added rows   == every staged household row (new clusters + depth additions, all partners, this label)
#     removed rows == 0
#     changed rows: only (a) ward_accessible_status -> Inaccessible on Maru LGA rows in wards the master now marks
#                   Inaccessible, and (b) the depth columns of clusters in an existing_cluster_target_increases file
#   WORKING vs the snapshot taken right before the merges (after the accessibility chain's routine refresh):
#     added rows <= staged rows; removed 0; changed rows only the depth columns of depth clusters
#   new rows: partners_covering == their stratum's; ward_accessible_status Accessible
# Usage (from 1_sampling): py resampling/scripts/one_off_analyses/verify_maru_topups_merge_2026-10-12.py <label[,label2]> <archive dir> <WORKING snapshot>
# ==============================================================================
import csv
import glob
import os
import sys
from collections import Counter

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
sys.path.insert(0, os.path.join(S1, "scripts", "shared"))
import msna_paths  # noqa: E402

DEPTH_COLS = {"target_households", "reserve_households", "selection_count"}


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    label, fa, snap = sys.argv[1], os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])
    staged, depth = set(), set()
    dirs = [d for lb in label.split(",") for d in glob.glob(os.path.join(RS, "output", "resample_runs", "*", lb))]  # several labels: a,b
    for d in dirs:
        for fn in ("new_households.csv", "new_households_idp_sitelevel.csv",
                   "existing_cluster_household_additions_non_idp.csv", "existing_cluster_household_additions_idp.csv"):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and os.path.getsize(p) > 2:
                staged |= {r["survey_id"] for r in rd(p)}
        for fn in ("existing_cluster_target_increases_non_idp.csv", "existing_cluster_target_increases_idp.csv"):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and os.path.getsize(p) > 2:
                depth |= {r["cluster_id"] for r in rd(p)}
    master = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"]
              for r in rd(os.path.join(RS, "output", "master_accessibility_status_ward_level.csv"))}
    ok, lines = True, [f"label {label}: {len(staged)} staged household rows, {len(depth)} depth cluster(s)"]
    for kind, base in (("stage2_FULL", os.path.join(fa, os.path.basename(msna_paths.frame_file("stage2_FULL")))), ("stage2_WORKING", snap)):
        old = {r["survey_id"]: r for r in rd(base)}
        new = {r["survey_id"]: r for r in rd(msna_paths.frame_file(kind))}
        added, removed = set(new) - set(old), set(old) - set(new)
        why = Counter()
        bad = []
        for k in set(old) & set(new):
            cols = {c for c in old[k] if old[k][c] != new[k].get(c)}
            if not cols:
                continue
            x = new[k]
            maru_flip = "ward_accessible_status" in cols and kind == "stage2_FULL" and x["adm1_name"] == "Zamfara" and x["adm2_name"] == "Maru" \
                and x["ward_accessible_status"] == "Inaccessible" and master.get(("Zamfara", "Maru", x["adm3_name"])) == "Inaccessible"
            rest = cols - {"ward_accessible_status"} if maru_flip else cols
            if maru_flip and not rest:
                why["Maru ward now Inaccessible"] += 1
            elif x["cluster_id"] in depth and rest <= DEPTH_COLS:  # a depth cluster's row may also sit in a ward that just closed
                why[("Maru ward now Inaccessible + " if maru_flip else "") + "depth cluster: " + "+".join(sorted(rest))] += 1
            else:
                bad.append((k, sorted(cols)))
        exact = kind == "stage2_FULL"
        good = not removed and not bad and (added == staged if exact else added <= staged)
        ok &= good
        lines.append(f"- {kind}: {len(old):,} -> {len(new):,} rows; +{len(added)} (staged {len(staged)}), -{len(removed)}; "
                     f"changed rows {dict(why)}; unexpected {len(bad)} {bad[:3]} -> {'PASS' if good else 'FAIL'}")
    full = {r["survey_id"]: r for r in rd(msna_paths.frame_file("stage2_FULL"))}
    strata = {r["strata_id"]: r["partners_covering"] for r in rd(msna_paths.frame_file("strata_FULL"))}
    new_rows = [full[s] for s in staged if s in full]
    bad_partner = sum(1 for r in new_rows if r["partners_covering"] != strata.get(r["strata_id"]))
    not_acc = sum(1 for r in new_rows if r["ward_accessible_status"] != "Accessible")
    good = bad_partner == 0 and not_acc == 0 and len(new_rows) == len(staged)
    ok &= good
    lines.append(f"- staged rows in FULL {len(new_rows)}/{len(staged)}; partner differs from stratum {bad_partner}; "
                 f"ward not Accessible {not_acc} -> {'PASS' if good else 'FAIL'}")
    print("\n".join(lines))
    print("VERIFY: ALL PASS" if ok else "VERIFY: FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
