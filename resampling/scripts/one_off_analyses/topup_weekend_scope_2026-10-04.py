# ==============================================================================
# 2026-10-04 READ-ONLY scope for the weekend top-up draw (Jack: "we will do a
# big resampling/top-up draw this weekend"). NO draw, NO merge, NO live change.
# Jack has not given the go in Resampling's window; this prepares his decision.
#
# For every stratum that is not Representative under the strict formula (05's
# certainty-PSU-aware verdict), plus, optionally, every Representative stratum
# above Jack's 9.5% margin, it says which lever exists and how far it gets:
#   - IDP: depth top-up into EXISTING sites (the D3 mechanism, used for real on
#     27/30 Sep). Greedy design-weighted search (model B) to Jack's margin target
#     of 9.25% (the middle of his 9-9.5% band), on a LOCAL copy of
#     topup_search(), never by patching the shared TARGET_MOE (that broke the
#     reproduction check on 30 Sep).
#   - Non-IDP: new clusters only. The Non-IDP depth mechanism is unbuilt (needs a
#     real building-footprint draw). 05's "Additional clusters needed" and
#     "Remaining eligible pool" are listed, but the pool is an unvalidated hex
#     count, so these need a fresh real Tier1+Tier2 dry-run before they count.
# Coverage scenarios: A = every covered stratum; B = NE+NW without Kebbi (the
# Round 1 analysis coverage - Round 2 fieldwork coverage is Jack's call).
# Writes resampling/output/weekend_topup_scope_2026-10-04/.
# ==============================================================================
import csv
import importlib.util
import math
import os
import sys

TARGET = 9.25
MARGIN_TOP = 9.5
NE_NW = {"Adamawa", "Borno", "Yobe", "Katsina", "Sokoto", "Zamfara", "Kaduna", "Kano"}
RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S = os.path.dirname(RS)
REV_DIR = os.path.join(RS, "output", "representativity_review_2026-09-27")
OUT_DIR = os.path.join(RS, "output", "weekend_topup_scope_2026-10-04")
os.makedirs(OUT_DIR, exist_ok=True)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def topup_to(rev, m, st, clusters, N_acc, supply, target):
    """rev.topup_search() with the stopping MoE as a parameter (same greedy model-B step)."""
    live = [c for c in clusters if c["n_primary_ceiling_contribution"] > 0]
    base = [c["n_primary_ceiling_contribution"] for c in live]
    sup = [supply.get(c["cluster_id"], 0) if c["n_primary_accessible"] > 0 else 0 for c in live]
    alloc = [0] * len(live)

    def moe_of(al):
        cl = [dict(c, n_primary_ceiling_contribution=c["n_primary_ceiling_contribution"] + a) for c, a in zip(live, al)]
        v, _ = rev.moe_basis(m, st, cl, N_acc)
        if v is None:
            return None
        return v * math.sqrt(rev.deff_w_factor(base, [b + a for b, a in zip(base, al)]))

    cur = moe_of(alloc)
    if cur is None:
        return {"feasible": False, "total": None, "moe": None, "touched": 0, "to_10": None}
    steps, total_cap = 0, sum(sup)
    to_10 = 0 if cur <= 10.0 else None  # interviews at which the same greedy path first reaches <= 10%
    while cur > target and steps < min(total_cap, 3000) and (sum(base) + steps) < N_acc:
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
        cur, steps = best_v, steps + 1
        if to_10 is None and cur <= 10.0:
            to_10 = steps
    return {"feasible": cur <= target, "total": sum(alloc), "moe": cur, "touched": sum(1 for a in alloc if a),
            "supply_total": total_cap, "to_10": to_10}


def main():
    include_margin = "--with-margin" in sys.argv
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
    hh = {}
    with open(os.path.join(S, "output", "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["cluster_id"] not in hh:
                hh[r["cluster_id"]] = int(r["households_in_cluster"]) if r["households_in_cluster"] not in ("", "NA") else 0
    rows = []
    for sid, st in sorted(strata.items()):
        v = rev.short_verdict(st["verdict"])
        moe = st.get("moe_cert")
        thin = v == "Representative" and moe is not None and moe > MARGIN_TOP
        if v in ("Not computable",) or st["N_acc"] <= 0 or (v == "Representative" and not (include_margin and thin)):
            continue
        r05 = st05.get(sid, {})
        acc = [c for c in st["clusters"] if c["n_primary_accessible"] > 0]
        is_idp = st["pop_label"] == "IDP"
        depth = {"total": "", "moe": "", "feasible": "", "touched": "", "to_10": ""}
        if is_idp and acc:
            supply = {c["cluster_id"]: max(0, hh.get(c["cluster_id"], 0) - c["n_primary_ceiling_contribution"]) for c in acc}
            depth = topup_to(rev, m, st, st["clusters"], st["N_acc"], supply, TARGET)
        rows.append({
            "strata_id": sid, "state": st["state"], "lga": st["lga"], "pop_type": st["pop_label"], "partner": st["partners_covering"],
            "scenario_B_NE_NW_no_Kebbi": "yes" if st["state"] in NE_NW else "no",
            "why_listed": "thin margin (Representative, MoE > 9.5%)" if thin else v,
            "verdict_05": r05.get("Representativity (10% MoE threshold)", "")[:90],
            "moe_now_pct": round(moe, 2) if moe is not None else "",
            "lever": ("IDP depth top-up at existing sites (D3)" if is_idp else
                      "Non-IDP new clusters only (depth mechanism unbuilt)"),
            "idp_depth_extra_interviews_to_10": ("" if not is_idp else (depth["to_10"] if depth["to_10"] is not None else "not reachable")),
            "idp_depth_extra_interviews_to_9_25": depth["total"] if is_idp else "",
            "idp_depth_moe_reached_pct": round(depth["moe"], 2) if is_idp and isinstance(depth["moe"], float) else "",
            "idp_depth_reaches_9_25": ("yes" if depth["feasible"] else "no (physical ceiling)") if is_idp and depth["moe"] not in ("", None) else "",
            "idp_sites_touched": depth["touched"] if is_idp else "",
            "nonidp_additional_clusters_needed_05": "" if is_idp else r05.get("Additional clusters needed", ""),
            "nonidp_remaining_pool_05_unvalidated": "" if is_idp else r05.get("Remaining eligible pool", ""),
        })
        print(f"  {sid:20s} {st['lga'][:14]:14s} {st['pop_label']:7s} {rows[-1]['moe_now_pct']}% -> "
              + (f"depth +{depth['total']} -> {rows[-1]['idp_depth_moe_reached_pct']}% ({rows[-1]['idp_depth_reaches_9_25']})" if is_idp
                 else f"NI: +{rows[-1]['nonidp_additional_clusters_needed_05']} clusters, pool {rows[-1]['nonidp_remaining_pool_05_unvalidated']}"))
    out = os.path.join(OUT_DIR, "weekend_topup_scope" + ("_with_margin" if include_margin else "") + "_2026-10-04.csv")
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    for scen, keep in (("A all covered", lambda r: True), ("B NE+NW no Kebbi", lambda r: r["scenario_B_NE_NW_no_Kebbi"] == "yes")):
        sel = [r for r in rows if keep(r)]
        idp = [r for r in sel if r["pop_type"] == "IDP"]
        idp_yes = [r for r in idp if r["idp_depth_reaches_9_25"] == "yes"]
        print(f"\n{scen}: {len(sel)} strata | IDP {len(idp)} (depth reaches 9.25%: {len(idp_yes)}, extra interviews "
              f"{sum(int(r['idp_depth_extra_interviews_to_9_25'] or 0) for r in idp_yes)}) | Non-IDP {len(sel) - len(idp)}")
    print("wrote", out)


if __name__ == "__main__":
    main()
