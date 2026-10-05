# ==============================================================================
# 2026-10-05 READ-ONLY: per-stratum result of the overnight spares (Coordinator, relaying Jack: "per stratum, report:
# requested 2, drawn N, and the reason for any shortfall"). Reads plan_spares' scope_by_stratum.csv, the spare register
# and the runner's stratum_failures.csv; writes resampling/output/spares_2026-10-05/spares_by_stratum.csv and prints a
# markdown summary for the morning report.
# Reasons: a recorded failure (draw / merge) wins; then a PPS double selection (one large site/area drawn twice:
# selection_count 2, i.e. one location carrying two clusters' households - seen on CARE's IDP draw, 01:25); otherwise a
# short draw means the candidate pool ran out (Non-IDP: Tier 1 only, i.e. fresh areas with enough accessible unclaimed
# buildings; IDP: unfielded accessible sites).
# ==============================================================================
import csv
import glob
import os
from collections import Counter

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DC = os.path.join(os.path.dirname(RS), "output", "data", "data_collection")
SP = os.path.join(RS, "output", "spares_2026-10-05")
EXHAUSTED = {"non_idp": "pool exhausted: fewer fresh areas with enough accessible, unclaimed buildings than requested "
                        "(Tier 1 only: repeat draws in fielded areas excluded)",
             "idp": "pool exhausted: fewer unfielded accessible IDP sites than requested"}


def rd(p):
    if not os.path.isfile(p) or os.path.getsize(p) == 0:
        return []
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    scope = [r for r in rd(os.path.join(SP, "scope_by_stratum.csv")) if int(r["spares_requested"] or 0) > 0]
    reg = rd(os.path.join(DC, "buffer_cluster_register.csv"))
    drawn = Counter(r["strata_id"] for r in reg)
    sel = {}  # cluster_id -> selection_count, from the staged cluster files (the register does not carry it)
    for p in glob.glob(os.path.join(RS, "output", "resample_runs", "*", "2026-10-05_spares*", "new_clusters*.csv")):
        for r in rd(p):
            try:
                sel[r["cluster_id"]] = max(1, int(float(r.get("selection_count") or 1)))
            except ValueError:
                sel[r["cluster_id"]] = 1
    equiv = Counter()
    for r in reg:
        equiv[r["strata_id"]] += sel.get(r["cluster_id"], 1)
    failed = {}
    for r in rd(os.path.join(SP, "stratum_failures.csv")):
        failed.setdefault(r["strata_id"], r["reason"])
    out = []
    for s in scope:
        sid = s["strata_id"]
        n, e, req = drawn.get(sid, 0), equiv.get(sid, 0), int(s["spares_requested"])
        if n >= req:
            why = ""
        elif sid in failed:
            why = failed[sid]
        elif e >= req:
            why = (f"PPS double selection: {n} location(s) drawn, carrying {e} clusters' worth of households "
                   "(a large site/area selected twice)")
        else:
            why = EXHAUSTED.get(s["pop_type"], "pool exhausted")
        out.append({"strata_id": sid, "state": s["state"], "lga": s["lga"], "pop_type": s["pop_type"],
                    "partners_covering": s["partners_covering"], "requested": req, "drawn": n,
                    "cluster_equivalents": e, "shortfall_reason": why})
    with open(os.path.join(SP, "spares_by_stratum.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["strata_id", "state", "lga", "pop_type", "partners_covering", "requested",
                                          "drawn", "cluster_equivalents", "shortfall_reason"])
        w.writeheader()
        w.writerows(out)
    by_n = Counter(min(r["drawn"], 2) for r in out)
    print(f"### Spares by stratum ({len(out)} strata requested, {sum(r['drawn'] for r in out)} spares drawn)")
    print(f"- 2 spares: {by_n.get(2, 0)} strata | 1 spare: {by_n.get(1, 0)} | 0 spares: {by_n.get(0, 0)}")
    for pop in ("non_idp", "idp"):
        rows = [r for r in out if r["pop_type"] == pop]
        print(f"- {'Non-IDP' if pop == 'non_idp' else 'IDP'}: {len(rows)} strata, {sum(r['drawn'] for r in rows)} spares")
    short = [r for r in out if r["drawn"] < r["requested"]]
    if short:
        print("\n| stratum | state | LGA | population | partner(s) | drawn / requested | reason |\n|---|---|---|---|---|---|---|")
        for r in sorted(short, key=lambda x: (x["drawn"], x["state"], x["lga"], x["pop_type"])):
            print(f"| {r['strata_id']} | {r['state']} | {r['lga']} | {'Non-IDP' if r['pop_type'] == 'non_idp' else 'IDP'} | "
                  f"{r['partners_covering']} | {r['drawn']} / {r['requested']} | {r['shortfall_reason']} |")
    double = [r for r in out if r["cluster_equivalents"] > r["drawn"]]
    if double:
        print(f"\nPPS double selections (one location, two clusters' households): "
              + ", ".join(f"{r['strata_id']} ({r['drawn']} location(s) = {r['cluster_equivalents']} cluster-equivalents)" for r in double))
    print(f"\nfull table: {os.path.join(SP, 'spares_by_stratum.csv')}")


if __name__ == "__main__":
    main()
