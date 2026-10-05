# ==============================================================================
# 2026-10-04 READ-ONLY plan for tonight's IDP depth top-ups under Jack's 150 rule (relayed 4 Oct, decision in his
# own window still needed before anything is merged): "top up every non-Representative (strict) stratum whose EXTRA
# interviews needed are <=150. Aim for 9.25% if the extra is <=150, else 10% if <=150, else skip." Tonight's fast
# path (Jack): IDP top-ups only; Non-IDP new clusters go into tomorrow's second tool version with the spares.
#
# Same engine as every real top-up since 27 Sep: the review engine's MoE (05's certainty-aware strict verdict,
# reproduction-checked) and the greedy design-weighted (model B) step that always adds the next interview where it
# lowers the MoE most (topup_weekend_scope_2026-10-04.py's topup_to, here keeping the per-cluster allocation).
# Supply per site = households_in_cluster minus the interviews already counted there; a site with selection_count 1
# that is not already a certainty site is capped at +5 per batch (the merge script's increase/6 rule would otherwise
# flip its certainty status - the 27 Sep Obi/Bassa finding, used for every batch since 30 Sep).
# Optional --max-share S: a site's new target may not exceed S x its households (a field-feasibility cap).
# Writes resampling/output/idp_topup_150rule_2026-10-04/: summary_by_stratum[_maxshareNN].csv + plan_by_cluster[...].csv.
# ==============================================================================
import argparse
import csv
import importlib.util
import math
import os

RULE_MAX = 150
TARGETS = (9.25, 10.0)
CAP_SINGLE = 5
RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S = os.path.dirname(RS)
REV_DIR = os.path.join(RS, "output", "representativity_review_2026-09-27")
OUT_DIR = os.path.join(RS, "output", "idp_topup_150rule_2026-10-04")


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def search(rev, m, st, supply, target):
    """Greedy model-B allocation until MoE <= target (or supply runs out). Returns allocation by cluster_id."""
    live = [c for c in st["clusters"] if c["n_primary_ceiling_contribution"] > 0]
    base = [c["n_primary_ceiling_contribution"] for c in live]
    sup = [supply.get(c["cluster_id"], 0) if c["n_primary_accessible"] > 0 else 0 for c in live]
    alloc = [0] * len(live)

    def moe_of(al):
        cl = [dict(c, n_primary_ceiling_contribution=c["n_primary_ceiling_contribution"] + a) for c, a in zip(live, al)]
        v, _ = rev.moe_basis(m, st, cl, st["N_acc"])
        return None if v is None else v * math.sqrt(rev.deff_w_factor(base, [b + a for b, a in zip(base, al)]))

    cur = moe_of(alloc)
    if cur is None:
        return None
    start = cur
    while cur > target and sum(alloc) < min(sum(sup), 3000) and (sum(base) + sum(alloc)) < st["N_acc"]:
        best_i, best_v = None, cur
        for i in range(len(live)):
            if alloc[i] >= sup[i]:
                continue
            alloc[i] += 1
            v = moe_of(alloc)
            alloc[i] -= 1
            if v is not None and v < best_v - 1e-12:
                best_i, best_v = i, v
        if best_i is None:
            break
        alloc[best_i] += 1
        cur = best_v
    return {"start": start, "moe": cur, "total": sum(alloc), "reached": cur <= target,
            "alloc": {c["cluster_id"]: a for c, a in zip(live, alloc) if a}, "clusters": {c["cluster_id"]: c for c in live}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-share", type=float, default=None,
                    help="optional: a site's new target may not exceed this share of its households (e.g. 0.5)")
    args = ap.parse_args()
    suffix = f"_maxshare{int(round(args.max_share * 100))}" if args.max_share else ""
    os.makedirs(OUT_DIR, exist_ok=True)
    m = load_module(os.path.join(RS, "scripts", "05_build_accessibility_impact_workbook.py"), "m05")
    rev = load_module(os.path.join(REV_DIR, "build_representativity_review.py"), "rev")
    L = rev.load_state(m)
    status = [r for r in rev.rd(os.path.join(RS, "output", "strata_representativity_status.csv"))
              if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
    strata, bad, extra = rev.build_strata(m, L, status)
    print(f"reproduction check: {len(strata)} strata, {len(bad)} mismatches, {len(extra)} extras")
    if bad or extra:
        raise SystemExit("STOP: the review engine does not reproduce 05's verdicts - not safe")
    hh = {}
    with open(os.path.join(S, "output", "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"),
              encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if r["cluster_id"] not in hh:
                hh[r["cluster_id"]] = (int(r["households_in_cluster"]) if r["households_in_cluster"] not in ("", "NA") else 0,
                                       int(float(r["selection_count"])) if r["selection_count"] not in ("", "NA") else 1,
                                       r["certainty_stratum"], r["partners_covering"],
                                       int(float(r["target_households"])) if r["target_households"] not in ("", "NA") else 0)
    summary, plan = [], []
    for sid, st in sorted(strata.items()):
        v = rev.short_verdict(st["verdict"])
        if st["pop_label"] != "IDP" or v in ("Representative", "Not computable") or st["N_acc"] <= 0:
            continue
        acc = [c for c in st["clusters"] if c["n_primary_accessible"] > 0]
        supply, capped = {}, []
        for c in acc:
            h, sel, cert, _, tgt = hh.get(c["cluster_id"], (0, 1, "", "", 0))
            room = max(0, h - c["n_primary_ceiling_contribution"])
            is_cert = bool(c.get("is_certainty")) or sel > 1
            supply[c["cluster_id"]] = room if is_cert else min(room, CAP_SINGLE)
            if args.max_share:
                supply[c["cluster_id"]] = max(0, min(supply[c["cluster_id"]], int(args.max_share * h) - tgt))
            if not is_cert and room > CAP_SINGLE:
                capped.append(c["cluster_id"])
        partner = st["partners_covering"]
        res = {t: search(rev, m, st, supply, t) for t in TARGETS} if acc else {}
        choice, reason = None, ""
        for t in TARGETS:
            r = res.get(t)
            if r and r["reached"] and r["total"] <= RULE_MAX:
                choice = t
                break
        if choice is None:
            r925, r10 = res.get(9.25), res.get(10.0)
            if not acc:
                reason = "no accessible site with interviews to top up"
            elif r10 and r10["reached"]:
                reason = f"needs {r10['total']} extra to reach 10% (> {RULE_MAX})"
            else:
                reason = (f"10% not reachable with the sites' headroom (best {r10['moe']:.2f}% with +{r10['total']})" if r10
                          else "MoE not computable")
        r = res.get(choice) if choice else None
        summary.append({"strata_id": sid, "state": st["state"], "lga": st["lga"], "partner": partner, "verdict_05": v,
                        "moe_now_pct": round(res[9.25]["start"], 2) if res.get(9.25) else "",
                        "extra_to_9_25": res[9.25]["total"] if res.get(9.25) and res[9.25]["reached"] else "not reachable",
                        "extra_to_10": res[10.0]["total"] if res.get(10.0) and res[10.0]["reached"] else "not reachable",
                        "decision": f"TOP UP to {choice}%" if choice else "skip",
                        "extra_interviews": r["total"] if r else 0, "moe_after_pct": round(r["moe"], 2) if r else "",
                        "sites_touched": len(r["alloc"]) if r else 0, "sites_capped_at_5": len(capped), "reason": reason})
        if r:
            for cid, a in sorted(r["alloc"].items()):
                h, sel, cert, pc, tgt = hh.get(cid, (0, 1, "", "", 0))
                plan.append({"partner": partner, "strata_id": sid, "lga": st["lga"], "cluster_id": cid, "increase": a,
                             "households_in_cluster": h, "selection_count": sel, "target_used_pct": choice})
        s = summary[-1]
        print(f"  {sid:14s} {st['lga'][:16]:16s} {partner[:14]:14s} {s['moe_now_pct']}% -> {s['decision']:15s} "
              f"+{s['extra_interviews']:>3} -> {s['moe_after_pct']}% | to9.25 {s['extra_to_9_25']} to10 {s['extra_to_10']} {reason}")
    for name, rows in ((f"summary_by_stratum{suffix}.csv", summary), (f"plan_by_cluster{suffix}.csv", plan)):
        with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8", newline="") as f:
            if rows:
                w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
                w.writeheader()
                w.writerows(rows)
    tops = [s for s in summary if s["decision"] != "skip"]
    print(f"\n{len(summary)} non-Representative IDP strata; {len(tops)} to top up, {sum(s['extra_interviews'] for s in tops)} extra "
          f"interviews at {sum(s['sites_touched'] for s in tops)} sites; files in {OUT_DIR}")


if __name__ == "__main__":
    main()
