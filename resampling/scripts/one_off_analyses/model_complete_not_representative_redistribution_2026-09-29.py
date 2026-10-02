# ==============================================================================
# "Complete but not Representative" redistribution model (Jack via Coordinator,
# 2026-09-29) - READ-ONLY analysis, no live changes, no real draw, no merge.
#
# Question: for a stratum that's already achieved >= its own target_sample_
# representativity but still reads moe_real > 10% (driven by uneven cluster
# spread - Sandamu IDP, cv=0.68, was Jack's own worked example), could
# RECOLLECTING IN THE CURRENTLY-THIN CLUSTERS ALONE (no new draw, no adding to
# already-above-average clusters) bring it to <=10%? Models a greedy
# "fill the thin clusters first, up to real capacity" scenario and reuses this
# project's OWN existing formulas throughout - realized_moe_unequal()/
# realized_moe_certainty_aware() (05's own MoE engine) and topup_search()
# (build_representativity_review.py's own greedy top-up search, already the
# established R4 "top up existing clusters" analysis, run every night as
# S3_R4_topup_existing_clusters_EXPLORATORY.csv) - not reimplemented.
#
# "REAL REMAINING CAPACITY" - the one open call this task named explicitly.
# Uses ACTUAL RESERVE ROWS STILL SITTING IN THE WORKING FRAME per cluster
# (same "supply" R4 already uses, L["w_by_cluster"][cluster_id]["reserve"]),
# NOT households_in_cluster minus achieved (a much larger, purely theoretical
# ceiling - R4 already computes that too, separately, as "theoretical
# household headroom", never as the primary supply figure). Reserve rows are
# real, already-assigned households a field team can visit without a new
# draw; households_in_cluster is the whole physical building universe, most
# of which was never assigned to anyone. Matches the ONLY methodology this
# project has already used for "top up existing clusters" analysis (R4,
# computed routinely, unlike a real draw which needs Jack's own sign-off) -
# reused directly here, not a fresh invention for this task.
#
# Model B (design-weighted, Kish deff_w) is used throughout, matching R4's
# own primary model - NOT model A (ignore-weights, explicitly labelled "not
# recommended" everywhere else in this project). Read-only: modelling what
# COULD close a stratum via reserve capacity is analysis, exactly the same
# category as R4 itself (already computed nightly without a fresh ask each
# time) - actually DRAWING or merging anything still needs its own separate
# sign-off, same as every other real-draw decision tonight, and this script
# does neither.
# ==============================================================================
import csv
import importlib.util
import math

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = PROJECT_DIR + r"\1_sampling"
RS = S + r"\resampling"
OUT_DIR = RS + r"\output\complete_not_representative_2026-09-29"
TARGET_MOE = 10.0

import os
os.makedirs(OUT_DIR, exist_ok=True)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    m = load_module(RS + r"\scripts\05_build_accessibility_impact_workbook.py", "m05")
    rev = load_module(S + r"\resampling\output\representativity_review_2026-09-27\build_representativity_review.py", "rev")

    print("Loading state (05's own inputs, read-only)...")
    L = rev.load_state(m)
    status_csv = rev.rd(RS + r"\output\strata_representativity_status.csv")
    # Same filter the review script's own main() applies (2026-09-28 fix): 05's CSV now
    # also carries bucket-(d) excluded/not-covered rows, which build_strata() never
    # expects (it only ever builds from covered strata) - filtered out here too.
    status_csv = [r for r in status_csv if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
    strata, bad, extra = rev.build_strata(m, L, status_csv)
    print(f"reproduction check: {len(strata)} strata, {len(bad)} mismatches, {len(extra)} unexpected extras")
    if bad or extra:
        for b in bad[:10]:
            print("  MISMATCH", b)
        raise SystemExit("STOP: strata dict doesn't reproduce 05's own output - not safe to model on top of it")

    real_cluster = L["real_cluster"]  # canonical real_achieved_by_cluster, from m.load_real_achieved()

    candidates = []
    for sid, st in strata.items():
        clusters = st["clusters"]
        if st["target_repr"] is None or not clusters:
            continue
        # Real achieved, summed over EVERY cluster ever assigned to this stratum - matches
        # 05's own real_achieved_accessible fix (2026-09-28), NOT build_strata()'s own
        # real_achieved_acc (which still filters to any_accessible clusters, the same class
        # of stranded-achieved bug 05 itself was fixed for) - recomputed directly here to
        # avoid inheriting that.
        real_achieved = sum(real_cluster.get(c["cluster_id"], 0) for c in clusters)
        if real_achieved < st["target_repr"]:
            continue  # not "Complete" by this definition
        real_cl = [dict(c, n_primary_ceiling_contribution=real_cluster.get(c["cluster_id"], 0)) for c in clusters]
        real_ceiling = sum(c["n_primary_ceiling_contribution"] for c in real_cl)
        if real_ceiling <= 0 or st["N_acc"] <= 0:
            continue
        moe_cert = m.realized_moe_certainty_aware(real_cl, st["N_acc"], st["m_used"], st["pop_type"], ICC=0.06)
        moe_real = moe_cert if moe_cert is not None else m.realized_moe_unequal(
            real_ceiling, st["N_acc"], [c["n_primary_ceiling_contribution"] for c in real_cl], ICC=0.06
        )
        if moe_real is None or moe_real <= TARGET_MOE:
            continue  # already Representative on real interviews - not this population
        candidates.append((sid, st, real_achieved, moe_real, real_cluster))

    print(f"\n'Complete but not Representative' strata found: {len(candidates)}")

    rows = []
    for sid, st, real_achieved, moe_real, real_cluster in candidates:
        clusters = st["clusters"]
        acc = [c for c in clusters if c["n_primary_accessible"] > 0]
        # real achieved per cluster, used both as the "fill" baseline and (via topup_search's
        # own base list) the starting distribution - dict(c, n_primary_ceiling_contribution=achieved)
        # so topup_search's internal moe_of() adds reserve fills ON TOP OF real achieved, not on
        # top of the (possibly different) design ceiling.
        real_cl_acc = [dict(c, n_primary_ceiling_contribution=real_cluster.get(c["cluster_id"], 0)) for c in acc]
        supply = {c["cluster_id"]: L["w_by_cluster"].get(c["cluster_id"], {}).get("reserve", 0) for c in acc}
        total_reserve_supply = sum(supply.values())
        result = rev.topup_search(m, st, real_cl_acc, st["N_acc"], supply, "B")
        closes = bool(result.get("feasible")) and result.get("total") is not None
        touched_clusters = []
        if closes and result.get("alloc"):
            for c, a in zip(result["live"], result["alloc"]):
                if a > 0:
                    touched_clusters.append(f"{c['cluster_id']}:+{a}")
        group = "(a) closes via reserve-only redistribution" if closes else "(b) reserve capacity insufficient"
        rows.append({
            "strata_id": sid, "state": st["state"], "lga": st["lga"], "pop_type": st["pop_label"],
            "partner": st["partners_covering"], "real_achieved": real_achieved, "target_repr": st["target_repr"],
            "current_moe_real_pct": round(moe_real, 2), "group": group,
            "additional_interviews_needed": result.get("total") if closes else "N/A (insufficient)",
            "total_reserve_supply_in_stratum": total_reserve_supply,
            "clusters_touched": len(touched_clusters) if closes else "N/A",
            "target_clusters_and_amounts": "; ".join(touched_clusters) if closes else "",
            "projected_moe_pct_after": round(result["moe"], 2) if closes and result.get("moe") is not None else "N/A",
            "moe_if_reserve_fully_exhausted_pct": round(result["moe"], 2) if not closes and result.get("moe") is not None else "",
        })

    rows.sort(key=lambda r: (r["group"], r["state"], r["lga"]))
    out_csv = os.path.join(OUT_DIR, "complete_not_representative_redistribution_model.csv")
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    n_a = sum(1 for r in rows if r["group"].startswith("(a)"))
    n_b = len(rows) - n_a
    print(f"\n(a) closes via reserve-only redistribution: {n_a}")
    print(f"(b) reserve capacity insufficient (needs a real draw / structurally capped): {n_b}")
    print(f"\nWrote {out_csv}")


if __name__ == "__main__":
    main()
