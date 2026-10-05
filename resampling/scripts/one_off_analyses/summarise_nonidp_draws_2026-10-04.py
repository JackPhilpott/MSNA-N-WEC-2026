# ==============================================================================
# 2026-10-04 READ-ONLY: what tonight's Non-IDP 150-rule draws actually DELIVERED vs what was requested, and the
# projected MoE with the delivered clusters (new clusters enter the MoE as in plan_nonidp_topups_150rule_2026-10-04.py:
# rev.hyp_cluster(size) with each delivered cluster's own target size). Strata that delivered 0 are listed - under the
# standing Tier 2 policy a fresh real Tier1+Tier2 draw is what settles "pool exhausted".
# Reads resample_runs/<Partner>/2026-10-04_nonidp_topup_150rule/{summary_by_stratum,new_clusters}.csv.
# Writes resampling/output/nonidp_topup_150rule_2026-10-04/delivered_vs_requested.csv.
# ==============================================================================
import csv
import glob
import importlib.util
import os
from collections import defaultdict

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REV_DIR = os.path.join(RS, "output", "representativity_review_2026-09-27")
PLAN_DIR = os.path.join(RS, "output", "nonidp_topup_150rule_2026-10-04")
LABEL = "2026-10-04_nonidp_topup_150rule"


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    m = load_module(os.path.join(RS, "scripts", "05_build_accessibility_impact_workbook.py"), "m05")
    rev = load_module(os.path.join(REV_DIR, "build_representativity_review.py"), "rev")
    L = rev.load_state(m)
    status = [r for r in rev.rd(os.path.join(RS, "output", "strata_representativity_status.csv"))
              if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
    strata, bad, extra = rev.build_strata(m, L, status)
    # Tonight's own draws change some "recoverable" LABELS (05 reads real draw results) until 05 is re-run; that is
    # expected. Only a MoE difference means the engine is out of step, so only that stops this report.
    import re
    moe_bad = [x for x in bad if (lambda g: g is None or round(float(g.group(1)), 2) != round(float(g.group(2)), 2))(
        re.search(r"moe ([0-9.]+) vs ([0-9.]+)", x[1]))]
    if moe_bad or extra:
        raise SystemExit(f"STOP: the review engine does not reproduce 05's MoE - not safe: {moe_bad[:3]} {extra[:3]}")
    if bad:
        print(f"note: {len(bad)} verdict-label-only difference(s) from tonight's draws (MoE identical): {[x[0] for x in bad]}")
    plan = {r["strata_id"]: r for r in rd(os.path.join(PLAN_DIR, "summary_by_stratum.csv"))}
    sizes, folder = defaultdict(list), {}
    for d in glob.glob(os.path.join(RS, "output", "resample_runs", "*", LABEL)):
        p = os.path.join(d, "new_clusters.csv")
        if os.path.isfile(p):
            for r in rd(p):
                sizes[r["strata_id"] if "strata_id" in r else r["uuid_hex_pop"].rsplit("_hex", 1)[0]].append(int(float(r["target_households"])))
        for r in rd(os.path.join(d, "shortfalls_nonidp.csv")):
            folder[r["strata_id"]] = os.path.basename(os.path.dirname(d))
    out = []
    for sid, pr in sorted(plan.items()):
        if not pr["decision"].startswith("DRAW"):
            continue
        st = strata[sid]
        got = sizes.get(sid, [])
        moe_now, _ = rev.moe_basis(m, st, st["clusters"], st["N_acc"])
        moe_after, _ = rev.moe_basis(m, st, st["clusters"] + [rev.hyp_cluster(s) for s in got], st["N_acc"]) if got else (moe_now, False)
        out.append({"strata_id": sid, "lga": st["lga"], "partner": st["partners_covering"], "batch": folder.get(sid, ""),
                    "requested_clusters": int(pr["clusters_requested"]), "delivered_clusters": len(got),
                    "delivered_interviews": sum(got), "moe_now_pct": round(moe_now, 2),
                    "moe_projected_pct": round(moe_after, 2), "reaches_10": "yes" if moe_after <= 10.0 else "no",
                    "reaches_9_25": "yes" if moe_after <= 9.25 else "no", "delivered_zero": "YES" if not got else ""})
    with open(os.path.join(PLAN_DIR, "delivered_vs_requested.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    for o in out:
        print(f"  {o['lga'][:14]:14s} {o['partner'][:12]:12s} req {o['requested_clusters']:>2} got {o['delivered_clusters']:>2} "
              f"({o['delivered_interviews']:>3} int.) MoE {o['moe_now_pct']}% -> {o['moe_projected_pct']}% "
              f"{'<=9.25' if o['reaches_9_25'] == 'yes' else ('<=10' if o['reaches_10'] == 'yes' else '>10')} {o['delivered_zero'] and 'DELIVERED 0'}")
    print(f"total: requested {sum(o['requested_clusters'] for o in out)}, delivered {sum(o['delivered_clusters'] for o in out)} clusters "
          f"({sum(o['delivered_interviews'] for o in out)} interviews); reaching <=10%: {sum(o['reaches_10'] == 'yes' for o in out)} of {len(out)}")


if __name__ == "__main__":
    main()
