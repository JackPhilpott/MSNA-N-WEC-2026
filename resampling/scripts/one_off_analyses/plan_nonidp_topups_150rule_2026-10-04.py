# ==============================================================================
# 2026-10-04 READ-ONLY: Jack's 150 rule for Non-IDP strata (new clusters; the Non-IDP depth mechanism is unbuilt).
# For every non-Representative (strict) Non-IDP stratum: the smallest number k of new clusters of the stratum's own
# cluster size (m_used) that brings the verdict-basis MoE to 9.25%, else to 10%, with k x m_used <= 150 extra
# interviews; otherwise skip. New clusters enter the MoE exactly as in full_sweep_combined_strategy_2026-09-30.py
# (rev.hyp_cluster(size) added to the stratum's clusters, rev.moe_basis). This is the REQUEST; what a real
# Tier1+Tier2 draw actually delivers after building validation is only known from the draw (27 Sep: Damboa asked 13,
# got 3; Kala/Balge asked 7, got 0).
# Writes resampling/output/nonidp_topup_150rule_2026-10-04/: summary_by_stratum.csv and one
# shortfalls_<Partner>.csv per partner in draw_supplementary_clusters_batch.R's format.
# ==============================================================================
import csv
import importlib.util
import os
from collections import defaultdict

RULE_MAX = 150
TARGETS = (9.25, 10.0)
RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REV_DIR = os.path.join(RS, "output", "representativity_review_2026-09-27")
OUT_DIR = os.path.join(RS, "output", "nonidp_topup_150rule_2026-10-04")


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
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
    st05 = {r["Strata ID"]: r for r in status}
    summary, shortfalls = [], defaultdict(list)
    for sid, st in sorted(strata.items()):
        v = rev.short_verdict(st["verdict"])
        if st["pop_label"] == "IDP" or v in ("Representative", "Not computable") or st["N_acc"] <= 0:
            continue
        msize = int(round(float(st["m_used"])))
        kmax = RULE_MAX // max(1, msize)
        base, _ = rev.moe_basis(m, st, st["clusters"], st["N_acc"])
        need = {}
        for t in TARGETS:
            need[t] = None
            for k in range(1, kmax + 1):
                moe, _ = rev.moe_basis(m, st, st["clusters"] + [rev.hyp_cluster(msize) for _ in range(k)], st["N_acc"])
                if moe is not None and moe <= t:
                    need[t] = (k, moe)
                    break
        choice = next((t for t in TARGETS if need[t]), None)
        k, moe_after = need[choice] if choice else (0, None)
        r05 = st05.get(sid, {})
        partner = st["partners_covering"]
        summary.append({"strata_id": sid, "state": st["state"], "lga": st["lga"], "partner": partner, "verdict_05": v,
                        "m_used": msize, "moe_now_pct": round(base, 2) if base is not None else "",
                        "clusters_to_9_25": need[9.25][0] if need[9.25] else f"> {kmax}",
                        "clusters_to_10": need[10.0][0] if need[10.0] else f"> {kmax}",
                        "decision": f"DRAW {k} to {choice}%" if choice else "skip",
                        "clusters_requested": k, "extra_interviews": k * msize,
                        "moe_after_if_all_delivered_pct": round(moe_after, 2) if moe_after else "",
                        "pool_05_unvalidated": r05.get("Remaining eligible pool", "")})
        if choice:
            shortfalls[partner].append({"strata_id": sid, "adm2_pcode": sid.split("_")[-1], "pop_type": "non_idp",
                                        "additional_clusters_needed": k, "state": st["state"], "lga": st["lga"], "partners": partner})
        s = summary[-1]
        print(f"  {sid:18s} {st['lga'][:14]:14s} {partner[:12]:12s} {s['moe_now_pct']}% -> {s['decision']:16s} "
              f"(to9.25 {s['clusters_to_9_25']}, to10 {s['clusters_to_10']}, pool {s['pool_05_unvalidated']})")
    with open(os.path.join(OUT_DIR, "summary_by_stratum.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(summary[0].keys()))
        w.writeheader()
        w.writerows(summary)
    for partner, rows in shortfalls.items():
        name = partner.replace(", ", "_").replace(" ", "_")
        with open(os.path.join(OUT_DIR, f"shortfalls_{name}.csv"), "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    sel = [s for s in summary if s["decision"] != "skip"]
    print(f"\n{len(summary)} non-Representative Non-IDP strata; {len(sel)} to draw: {sum(s['clusters_requested'] for s in sel)} clusters, "
          f"{sum(s['extra_interviews'] for s in sel)} interviews, partners {sorted(shortfalls)}; files in {OUT_DIR}")


if __name__ == "__main__":
    main()
