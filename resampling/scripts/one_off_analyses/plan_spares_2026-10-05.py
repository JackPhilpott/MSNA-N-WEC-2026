# ==============================================================================
# 2026-10-05 READ-ONLY: scope and per-partner draw requests for the overnight spare clusters (Jack, 4-5 Oct, in
# Resampling's window: "2 yes" / "ok yes, we'll do the spares overnight once all is confirmed with coordinator").
# Rules agreed with Jack:
#   - every stratum STILL COLLECTING gets 2 spares: covered, not excluded, Full Design (MSNA Light strata take no Full
#     Design draws, rule R6), and with at least one primary household still on WORKING;
#   - Non-IDP spares from fresh areas only (the draw runs with DRAW_TIER1_ONLY=1: a repeat draw sits in the hex of an
#     existing cluster and would fail for the same reason the cluster it should replace failed);
#   - IDP spares from unfielded accessible sites (the site-level draw only ever draws unfielded sites).
# Writes resampling/output/spares_2026-10-05/: scope_by_stratum.csv and shortfalls_<pop>_<Partner>.csv
# (draw_supplementary_*_batch.R format). The batch folder is the stratum's first partner (a shared stratum such as
# "PLAN, FACT" is drawn in PLAN's batch; the merge stamps the stratum's own partners_covering on every row).
# ==============================================================================
import csv
import os
from collections import Counter, defaultdict

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DC = os.path.join(os.path.dirname(RS), "output", "data", "data_collection")
OUT = os.path.join(RS, "output", "spares_2026-10-05")
PER_STRATUM = 2


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"), encoding="utf-8-sig", newline="") as f:
        strata = list(csv.DictReader(f))
    todo, light = Counter(), set()
    with open(os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv"), encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if r["status"] == "primary":
                todo[r["strata_id"]] += 1
            if r.get("sampling_method") == "MSNA Light":
                light.add(r["strata_id"])
    scope, req = [], defaultdict(list)
    for s in strata:
        sid = s["strata_id"]
        covered = s["coverage_status"] == "covered" and s["exclusion_reason"] in ("none", "")
        is_light = s.get("sampling_method") == "MSNA Light" or sid in light
        why = ("not covered / excluded" if not covered else "MSNA Light (no Full Design draws)" if is_light
               else "no primary household left on WORKING" if todo[sid] == 0 else "")
        scope.append({"strata_id": sid, "state": s["adm1_name"], "lga": s["adm2_name"], "pop_type": s["pop_type"],
                      "partners_covering": s["partners_covering"], "primary_todo_rows": todo[sid],
                      "spares_requested": 0 if why else PER_STRATUM, "not_requested_because": why})
        if not why:
            folder = s["partners_covering"].split(",")[0].strip()
            req[(s["pop_type"], folder)].append({"strata_id": sid, "adm2_pcode": s["adm2_pcode"], "pop_type": s["pop_type"],
                                                 "additional_clusters_needed": PER_STRATUM, "state": s["adm1_name"],
                                                 "lga": s["adm2_name"], "partners": s["partners_covering"]})
    with open(os.path.join(OUT, "scope_by_stratum.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(scope[0].keys()))
        w.writeheader()
        w.writerows(scope)
    for (pop, folder), rows in sorted(req.items()):
        name = f"shortfalls_{pop}_{folder.replace(' ', '_')}.csv"
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    c = Counter((r["pop_type"], r["not_requested_because"] or "REQUESTED") for r in scope)
    for k, n in sorted(c.items()):
        print(f"{n:4d}  {k}")
    print(f"batches: {sorted(req)}")
    print(f"requested: {sum(len(v) for v in req.values())} strata x {PER_STRATUM} = {PER_STRATUM * sum(len(v) for v in req.values())} spares; files in {OUT}")


if __name__ == "__main__":
    main()
