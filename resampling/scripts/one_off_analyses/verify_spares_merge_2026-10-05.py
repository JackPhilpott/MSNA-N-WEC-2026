# ==============================================================================
# 2026-10-05: verifies tonight's spare merges against the pre-spares archive and writes the v16 hand-off's
# "what changed" text. Exit 1 on any failure (the overnight runner then restores the v15 frame).
#   FULL:    added rows == every staged spare household row; nothing removed; no existing row changed
#   WORKING: against the routine-refreshed pre-spares snapshot (runner step 1b): added rows are staged spare rows;
#            nothing removed; no existing row changed
#   register: every spare cluster is in FULL; every spare row's partners_covering == its stratum's
# Usage: python verify_spares_merge_2026-10-05.py <label> <pre-spares archive dir> [<WORKING baseline csv>]
#   (the WORKING baseline defaults to the archive's WORKING, i.e. no routine refresh before the spares)
# ==============================================================================
import csv
import glob
import os
import sys
from collections import Counter

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
DC = os.path.join(S1, "output", "data", "data_collection")
SP = os.path.join(RS, "output", "spares_2026-10-05")


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    label, fa = sys.argv[1], sys.argv[2]
    fa = fa if os.path.isabs(fa) else os.path.join(S1, fa)
    wb = sys.argv[3] if len(sys.argv) > 3 else os.path.join(fa, "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv")
    wb = wb if os.path.isabs(wb) else os.path.join(S1, wb)
    staged = set()
    for d in glob.glob(os.path.join(RS, "output", "resample_runs", "*", label)):
        for fn in ("new_households.csv", "new_households_idp_sitelevel.csv"):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and os.path.getsize(p) > 2:
                staged |= {r["survey_id"] for r in rd(p)}
    ok, lines = True, []
    for name, base, exact in (("NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", None, True),
                              ("NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", wb, False)):
        old = {r["survey_id"]: r for r in rd(base or os.path.join(fa, name))}
        new = {r["survey_id"]: r for r in rd(os.path.join(DC, name))}
        added, removed = set(new) - set(old), set(old) - set(new)
        changed = sum(1 for k in set(old) & set(new) if old[k] != new[k])
        good = not removed and changed == 0 and (added == staged if exact else added <= staged)
        ok &= good
        lines.append(f"- {name}: {len(old):,} -> {len(new):,} rows; +{len(added)} (staged {len(staged)}), -{len(removed)}, "
                     f"existing rows changed {changed} -> {'PASS' if good else 'FAIL'}")
    reg = rd(os.path.join(DC, "buffer_cluster_register.csv"))
    full = rd(os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"))
    strata = {r["strata_id"]: r["partners_covering"] for r in rd(os.path.join(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"))}
    in_full = {r["cluster_id"] for r in full}
    spare_ids = {r["cluster_id"] for r in reg}
    missing = sorted(spare_ids - in_full)
    bad_partner = sum(1 for r in full if r["cluster_id"] in spare_ids and r["partners_covering"] != strata.get(r["strata_id"]))
    good = not missing and bad_partner == 0
    ok &= good
    lines.append(f"- register: {len(reg)} spares; missing from FULL {len(missing)} {missing[:3]}; rows with a partner "
                 f"different from their stratum {bad_partner} -> {'PASS' if good else 'FAIL'}")
    v15 = {r["survey_id"] for r in rd(os.path.join(fa, "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv"))}
    pre = {r["survey_id"] for r in rd(wb)}
    left, back = len(v15 - pre), len(pre - v15)
    lines.append(f"- routine refresh before the spares (v15 WORKING -> pre-spares snapshot): {left} completed household(s) "
                 f"left, {back} returned")
    routine = ("Nothing else changed." if not (left or back) else
               f"Besides the spares, only the routine daily refresh changed WORKING: {left:,} household(s) completed since "
               f"v15 left it" + (f" and {back:,} returned (deleted submissions)" if back else "") + ".")
    by = Counter((r["partner"], r["pop_type"]) for r in reg)
    strata_n = len({r["strata_id"] for r in reg})
    with open(os.path.join(SP, "do_handoff_changes_v16.md"), "w", encoding="utf-8") as f:
        f.write(f"This version adds the **spare clusters** to frame v15. {routine}\n\n"
                f"- **{len(reg)} spare clusters in {strata_n} strata**, up to 2 per stratum still collecting. Non-IDP spares "
                "come from fresh areas only; IDP spares from unfielded accessible sites.\n"
                "- Every spare is listed in `buffer_cluster_register.csv` beside the frame. A spare is an ordinary "
                "cluster in the frame, so a submission at it matches normally.\n"
                "- **Use:** only when a primary cluster in the same stratum is confirmed impossible to complete. "
                "Report each use to the DO the same day.\n"
                "- An unused spare counts nowhere (targets, progress, weights). Partners see spares separately: "
                "`spare_clusters.kml` (names start \"SPARE - \") and a \"Spare Clusters\" sheet.\n\n"
                "| partner | population | spares |\n|---|---|---|\n"
                + "".join(f"| {p} | {'IDP' if t == 'idp' else 'Non-IDP'} | {n} |\n" for (p, t), n in sorted(by.items())))
    print("\n".join(lines))
    print(f"v16 changes text written to {os.path.join(SP, 'do_handoff_changes_v16.md')}")
    print("VERIFY: ALL PASS" if ok else "VERIFY: FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
