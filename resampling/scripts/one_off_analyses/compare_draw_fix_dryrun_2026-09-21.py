# ==============================================================================
# Dry-run check for the 2026-09-21 draw fix (Stage B2 building-validated pool
# + Stage F accessible-only redraw in draw_supplementary_clusters_batch.R;
# Jack: "build now, dry-run only", 6-building floor). Compares the new script
# against the committed (HEAD) version on identical shortfalls and seed, both
# stamped by stamp_ward_accessible_status.py - the same stamp the merge
# enforces - so "accessible" here is exactly what the merge and 05 will see.
# Nothing is merged; the dry-run folder sits outside resample_runs/ so the
# dashboard's coverage map can't pick it up.
# Usage: python compare_draw_fix_dryrun_2026-09-21.py
# ==============================================================================
import csv
import os
from collections import Counter, defaultdict

D = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\output\draw_fix_dryrun_2026-09-21"


def load(p):
    if not os.path.exists(p) or os.path.getsize(p) < 5:
        return []
    with open(p, encoding="utf-8") as f:
        return list(csv.DictReader(f))


need = {r["strata_id"]: (r["lga"], int(float(r["additional_clusters_needed"]))) for r in load(os.path.join(D, "new", "dryrun_shortfalls.csv"))}
res = {}
for v in ("old", "new"):
    hh = load(os.path.join(D, v, "new_households.csv"))
    per = defaultdict(lambda: {"prim_acc": 0, "prim_bad": 0})
    sid_of = {}
    for r in hh:
        if r["status"] != "primary":
            continue
        c = per[r["cluster_id"]]
        sid_of[r["cluster_id"]] = r["strata_id"]
        if r.get("ward_accessible_status") == "Accessible":
            c["prim_acc"] += 1
        else:
            c["prim_bad"] += 1
    by = defaultdict(Counter)
    for cid, c in per.items():
        s = by[sid_of[cid]]
        s["clusters"] += 1
        s["usable_hh"] += c["prim_acc"] if c["prim_acc"] >= 4 else 0
        s["ge6"] += c["prim_acc"] >= 6
        s["4to5"] += 4 <= c["prim_acc"] < 6
        s["lt4"] += c["prim_acc"] < 4
        s["bad_primary_rows"] += c["prim_bad"]
    res[v] = by

print(f"{'stratum':22} {'need':>4} | {'OLD drawn':>9} {'>=6':>4} {'4-5':>4} {'<4':>4} {'inacc':>5} {'usable':>6} | {'NEW drawn':>9} {'>=6':>4} {'4-5':>4} {'<4':>4} {'inacc':>5} {'usable':>6}")
tot = {v: Counter() for v in res}
for sid, (lga, n) in need.items():
    o, w = res["old"][sid], res["new"][sid]
    for v, s in (("old", o), ("new", w)):
        tot[v].update(s)
    print(f"{lga[:22]:22} {n:>4} | {o['clusters']:>9} {o['ge6']:>4} {o['4to5']:>4} {o['lt4']:>4} {o['bad_primary_rows']:>5} {o['usable_hh']:>6} | "
          f"{w['clusters']:>9} {w['ge6']:>4} {w['4to5']:>4} {w['lt4']:>4} {w['bad_primary_rows']:>5} {w['usable_hh']:>6}")
for v in ("old", "new"):
    t = tot[v]
    print(f"TOTAL {v.upper()}: {t['clusters']} clusters | >=6 usable {t['ge6']} | 4-5 {t['4to5']} | <4 (duds) {t['lt4']} | "
          f"primary rows in inaccessible/unmatched wards {t['bad_primary_rows']} | usable households {t['usable_hh']}")
