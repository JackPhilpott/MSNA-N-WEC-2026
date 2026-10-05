# ==============================================================================
# 2026-10-05: writes output/data/data_collection/buffer_cluster_register.csv (register option A, Jack) from the
# clusters tonight's spare draws staged under resample_runs/<Partner>/<label>/ - BEFORE the merge, so the frame never
# holds a spare that the register does not know about. Refuses if a register already exists. Validated with
# scripts/shared/spare_clusters.load_register (stops on missing columns or duplicates).
# Usage: python write_spare_register_2026-10-05.py <label>
# ==============================================================================
import csv
import datetime
import glob
import os
import sys
from collections import defaultdict

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
sys.path.insert(0, os.path.join(S1, "scripts", "shared"))
import spare_clusters  # noqa: E402

DC = os.path.join(S1, "output", "data", "data_collection")
REG = os.path.join(DC, spare_clusters.REGISTER_NAME)
NOTE = ("Spare cluster (Jack, 4-5 Oct 2026): use only if a primary cluster in this stratum is confirmed impossible to "
        "complete, and report it to the DO the same day. Unused, it counts nowhere (targets, progress, weights).")


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    label = sys.argv[1]
    if os.path.exists(REG):
        raise SystemExit(f"STOP: {REG} already exists")
    strata = {r["strata_id"]: r for r in rd(os.path.join(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"))}
    live = {r["cluster_id"] for r in rd(os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"))}
    drawn = defaultdict(list)
    for d in sorted(glob.glob(os.path.join(RS, "output", "resample_runs", "*", label))):
        for fn, pop in (("new_clusters.csv", "non_idp"), ("new_clusters_idp_sitelevel.csv", "idp")):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and os.path.getsize(p) > 2:
                for r in rd(p):
                    drawn[r["strata_id"]].append((r["cluster_id"], pop))
    now = datetime.datetime.now().isoformat(timespec="seconds")
    rows = []
    for sid, cl in sorted(drawn.items()):
        if sid not in strata:
            raise SystemExit(f"STOP: drawn stratum {sid} is not in the strata frame")
        for rank, (cid, pop) in enumerate(sorted(set(cl)), start=1):
            if cid in live:
                raise SystemExit(f"STOP: {cid} is already in the live frame - a spare must be a NEW cluster")
            rows.append({"cluster_id": cid, "strata_id": sid, "pop_type": pop, "partner": strata[sid]["partners_covering"],
                         "buffer_rank": rank, "drawn_batch": label, "drawn_at": now, "source_note": NOTE})
    with open(REG, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=spare_clusters.REGISTER_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    reg = spare_clusters.load_register(REG)  # stops on missing columns / duplicates
    print(f"register: {len(rows)} spare cluster(s) in {len(drawn)} strata "
          f"(Non-IDP {sum(r['pop_type'] == 'non_idp' for r in rows)}, IDP {sum(r['pop_type'] == 'idp' for r in rows)}); "
          f"validated by load_register ({len(reg) if hasattr(reg, '__len__') else 'ok'}) -> {REG}")


if __name__ == "__main__":
    main()
