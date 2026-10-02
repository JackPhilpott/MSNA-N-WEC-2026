# ==============================================================================
# Full national sweep (Jack, direct, 2026-09-29 night - "take your time, review
# in the morning"): for every currently non-Representative stratum with real
# accessible population, what NEW target (raising existing clusters' targets
# up to their TRUE physical households_in_cluster ceiling) would be needed to
# reach <=10% MoE - same method as the Gwadabawa IDP deep-dive tonight, reused
# directly (topup_search(), model B, design-weighted - build_representativity_
# review.py's own greedy engine, NOT reimplemented).
#
# THIS SCRIPT is the FAST, in-memory half of the sweep (no real draws) - answers
# "if we raised targets at EXISTING clusters to their true physical ceiling,
# what would it take". The SEPARATE, slower half (real Tier1+Tier2 draw
# dry-runs, to check whether NEW clusters could also help / confirm genuine
# pool exhaustion) is full_sweep_real_draw_check_2026-09-29.py - run
# independently, checkpointed separately, per Jack's own methodology
# distinction (a real weighted draw vs. manually raising an existing
# cluster's target are different, both legitimate, but different questions).
#
# READ-ONLY. Writes only to its own output folder. No real draw, no merge,
# no live frame change - explicitly the "take your time" analysis Jack asked
# for, not execution.
# ==============================================================================
import csv
import importlib.util
import os

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = PROJECT_DIR + r"\1_sampling"
RS = S + r"\resampling"
OUT_DIR = RS + r"\output\full_sweep_2026-09-29"
os.makedirs(OUT_DIR, exist_ok=True)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    m = load_module(RS + r"\scripts\05_build_accessibility_impact_workbook.py", "m05")
    rev = load_module(S + r"\resampling\output\representativity_review_2026-09-27\build_representativity_review.py", "rev")

    print("Loading state (read-only)...")
    L = rev.load_state(m)
    status_csv = rev.rd(RS + r"\output\strata_representativity_status.csv")
    status_csv = [r for r in status_csv if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
    strata, bad, extra = rev.build_strata(m, L, status_csv)
    print(f"reproduction check: {len(strata)} strata, {len(bad)} mismatches, {len(extra)} extras")
    if bad or extra:
        for b in bad[:10]:
            print("  MISMATCH", b)
        raise SystemExit("STOP: not safe to sweep on top of this")

    real_cluster = L["real_cluster"]

    # True households_in_cluster per cluster, direct from FULL (build_cluster_level()'s
    # own dict doesn't carry it - same gap found tonight on Gwadabawa).
    print("Loading true households_in_cluster from FULL...")
    hh_in_cluster = {}
    target_hh_design = {}
    with open(S + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            cid = r["cluster_id"]
            if cid not in hh_in_cluster:
                hh_in_cluster[cid] = int(r["households_in_cluster"]) if r["households_in_cluster"] not in (None, "", "NA") else 0
                target_hh_design[cid] = int(r["target_households"]) if r["target_households"] not in (None, "", "NA") else 0

    targets = []
    for sid, st in strata.items():
        v = rev.short_verdict(st["verdict"])
        if v == "Representative" or v == "Not computable" or st["N_acc"] <= 0:
            continue
        clusters = st["clusters"]
        acc = [c for c in clusters if c["n_primary_accessible"] > 0]
        if not acc:
            continue
        real_cl_acc = [dict(c, n_primary_ceiling_contribution=real_cluster.get(c["cluster_id"], 0)) for c in acc]
        supply_full = {c["cluster_id"]: max(0, hh_in_cluster.get(c["cluster_id"], 0) - real_cluster.get(c["cluster_id"], 0)) for c in acc}
        total_supply = sum(supply_full.values())
        design_target_open = sum(target_hh_design.get(c["cluster_id"], 0) for c in acc)
        current_achieved_open = sum(real_cluster.get(c["cluster_id"], 0) for c in acc)

        result = None
        try:
            result = rev.topup_search(m, st, real_cl_acc, st["N_acc"], supply_full, "B")
        except Exception as e:
            targets.append({
                "strata_id": sid, "state": st["state"], "lga": st["lga"], "pop_type": st["pop_label"],
                "partner": st["partners_covering"], "verdict": v, "current_moe_real_pct": "ERROR",
                "error": str(e),
            })
            continue

        closes = bool(result.get("feasible"))
        new_target_open = design_target_open + sum(a for a in (result.get("alloc") or []))
        touched = []
        if result.get("alloc"):
            for c, a in zip(result["live"], result["alloc"]):
                if a > 0:
                    old_t = target_hh_design.get(c["cluster_id"], 0)
                    touched.append(f"{c['cluster_id']}:{old_t}->{old_t + a} (true cap {hh_in_cluster.get(c['cluster_id'], 0)})")

        targets.append({
            "strata_id": sid, "state": st["state"], "lga": st["lga"], "pop_type": st["pop_label"],
            "partner": st["partners_covering"], "verdict": v,
            "current_moe_real_pct": round(st.get("moe_cert") or 0, 2),
            "target_sample_representativity": st["target_repr"],
            "real_achieved_stratum_total": sum(real_cluster.get(c["cluster_id"], 0) for c in clusters),
            "design_target_open_clusters": design_target_open,
            "achieved_open_clusters": current_achieved_open,
            "true_physical_headroom_open_clusters": total_supply,
            "closes_via_raised_targets": "Yes" if closes else "No - insufficient even at full physical capacity",
            "additional_real_interviews_needed": result.get("total") if closes else "N/A",
            "projected_moe_after_pct": round(result["moe"], 2) if result.get("moe") is not None else "N/A",
            "new_design_target_open_clusters": new_target_open if closes else "N/A",
            "clusters_and_new_targets": "; ".join(touched) if touched else "",
            "n_open_clusters": len(acc),
        })
        print(f"  {sid} ({st['lga']} {st['pop_label']}): closes={closes}, +{result.get('total')} needed, moe->{result.get('moe')}")

    targets.sort(key=lambda r: (r.get("closes_via_raised_targets", ""), r["state"], r["lga"]))
    out_csv = os.path.join(OUT_DIR, "full_sweep_target_increase_model.csv")
    fieldnames = list(targets[0].keys()) if targets else []
    # union of all keys in case of error rows with a different shape
    all_keys = []
    for r in targets:
        for k in r.keys():
            if k not in all_keys:
                all_keys.append(k)
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=all_keys)
        w.writeheader()
        w.writerows(targets)

    n_closes = sum(1 for r in targets if r.get("closes_via_raised_targets") == "Yes")
    print(f"\nTotal non-Representative strata with real accessible population swept: {len(targets)}")
    print(f"Closeable by raising targets at existing clusters to true physical capacity: {n_closes}")
    print(f"Not closeable even at full physical capacity: {len(targets) - n_closes}")
    print(f"\nWrote {out_csv}")


if __name__ == "__main__":
    main()
