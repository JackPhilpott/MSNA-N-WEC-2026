# ==============================================================================
# COMBINED strategy sweep (Jack, direct via Coordinator, 2026-09-30 - correcting
# last night's two-separate-scenarios presentation). One row per stratum, ONE
# real, traceable, fully-computed answer: what does it actually take, using
# EVERY real lever together (genuinely deliverable new clusters from a real
# dry-run, PLUS depth top-up into existing clusters' true physical household
# capacity), to reach <=10% MoE - and if even that combined effort can't get
# there, the actual best-achievable MoE and the actual interviews that takes,
# never "N/A" (nothing here is genuinely unknown to this project's own data).
#
# Sequencing (Jack's own words: "(a) whatever new clusters are genuinely
# deliverable, PLUS (b) whatever additional depth top-up... is needed ON TOP"):
# 1. Start from real achieved.
# 2. Add every cluster build_representativity_review.py's OWN real Tier1+Tier2
#    dry-run (last night, 2026-09-29 t2 run) actually delivered - real,
#    building-validated sizes, not a raw pool count. These are treated as
#    FIXED (no further depth top-up on them individually - the dry-run's
#    delivered size already IS that hex's building-validated max, there's
#    nothing more to add there without a fresh draw attempt).
# 3. On top of that, greedy depth top-up ONLY the EXISTING (already-fielded)
#    clusters, up to their TRUE households_in_cluster ceiling - same
#    topup_search() (model B, design-weighted) reused from Phase 1/Gwadabawa,
#    not reimplemented.
# 4. Whatever MoE/interview-count that combined process lands on IS the
#    answer, feasible or not - topup_search() already returns the real
#    stopping point (every bit of true capacity exhausted) even when it
#    doesn't cross 10%, so "best achievable" is a real, computed number here,
#    never invented or left blank.
#
# READ-ONLY. No real draw, no merge, no live change.
# ==============================================================================
import csv
import importlib.util
import os

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = PROJECT_DIR + r"\1_sampling"
RS = S + r"\resampling"
REV_DIR = S + r"\resampling\output\representativity_review_2026-09-27"
OUT_DIR = RS + r"\output\full_sweep_2026-09-29"
os.makedirs(OUT_DIR, exist_ok=True)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_sizes(raw):
    """S3_R2's 'deliverable cluster sizes (primary hh)' column - '/'-joined ints, '' if none."""
    raw = (raw or "").strip()
    if not raw:
        return []
    return [int(float(x)) for x in raw.split("/") if x.strip()]


def main():
    m = load_module(RS + r"\scripts\05_build_accessibility_impact_workbook.py", "m05")
    rev = load_module(REV_DIR + r"\build_representativity_review.py", "rev")

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

    print("Loading true households_in_cluster from FULL...")
    hh_in_cluster = {}
    target_hh_design = {}
    with open(S + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            cid = r["cluster_id"]
            if cid not in hh_in_cluster:
                hh_in_cluster[cid] = int(r["households_in_cluster"]) if r["households_in_cluster"] not in (None, "", "NA") else 0
                target_hh_design[cid] = int(r["target_households"]) if r["target_households"] not in (None, "", "NA") else 0

    print("Loading last night's real Tier1+Tier2 dry-run results (S3_R2)...")
    with open(REV_DIR + r"\S3_R2_supplementary_draw_dryrun.csv", encoding="utf-8-sig") as f:
        r2_rows = {r["strata_id"]: r for r in csv.DictReader(f)}

    # union of every non-Representative stratum with real population: Phase 1's set
    # (build_strata's own non-Representative, non-Not-Computable, has-open-clusters
    # population) UNIONED with S3_R2's own coverage (covers a couple extra edge rows,
    # e.g. the MSNA-Light-excluded Ngala row) - "all ~39, every cell populated".
    target_sids = set(r2_rows.keys())
    for sid, st in strata.items():
        v = rev.short_verdict(st["verdict"])
        if v not in ("Representative", "Not computable") and st["N_acc"] > 0:
            acc = [c for c in st["clusters"] if c["n_primary_accessible"] > 0]
            if acc:
                target_sids.add(sid)

    rows_out = []
    for sid in sorted(target_sids):
        st = strata.get(sid)
        if st is None:
            # in S3_R2 but not in build_strata's own non-Representative set (e.g. MSNA
            # Light strata, which the R2 dry-run still lists with source "n/a") -
            # real, traceable reason, not silently dropped.
            r2 = r2_rows.get(sid, {})
            rows_out.append({
                "strata_id": sid, "state": r2.get("state", ""), "lga": r2.get("lga", ""),
                "pop_type": r2.get("pop_type", ""), "partner": r2.get("partner", ""),
                "current_moe_real_pct": "N/A - excluded from Full Design routes (see reason)",
                "real_new_clusters_deliverable": 0, "real_new_cluster_sizes": "",
                "moe_after_real_draw_only_pct": "N/A", "existing_clusters_depth_additional_needed": "N/A",
                "existing_clusters_depth_detail": r2.get("source", ""),
                "total_additional_real_interviews_combined": "N/A", "projected_moe_final_pct": "N/A",
                "reaches_10pct": "N/A", "reason_if_excluded": r2.get("source", "not in Full Design non-Representative population"),
            })
            continue

        clusters = st["clusters"]
        acc = [c for c in clusters if c["n_primary_accessible"] > 0]
        # FIX (caught before reporting): baseline must be st["clusters"] UNMODIFIED -
        # its own n_primary_ceiling_contribution already IS max(n_primary_accessible,
        # real_achieved) (05's own ceiling-source fix from tonight, already applied via
        # build_cluster_level()) - the SAME basis "at full completion of assigned
        # accessible points" / S3_R2's own r2_moe_after uses. Overriding ceiling to
        # real-achieved-only (moe_real's own definition, used elsewhere for a
        # DIFFERENT question - "current progress today") would silently switch the
        # baseline mid-analysis and make an already-verified result (Sokoto North NI,
        # confirmed 9.81% last night) look wrong. current_moe here intentionally
        # matches st["moe_cert"] (the standing verdict basis), not moe_real.
        current_moe = st.get("moe_cert")

        # Step 2: real, dry-run-delivered new clusters (fixed-size, no further top-up).
        r2 = r2_rows.get(sid, {})
        delivered_sizes = parse_sizes(r2.get("deliverable cluster sizes (primary hh)", ""))
        new_clusters = [rev.hyp_cluster(sz) for sz in delivered_sizes]
        for i, nc in enumerate(new_clusters):
            nc["cluster_id"] = f"NEW_real_draw_{i+1}_of_size_{delivered_sizes[i]}"

        combined_baseline = clusters + new_clusters
        moe_after_draw, _ = rev.moe_basis(m, st, combined_baseline, st["N_acc"]) if st["N_acc"] > 0 else (None, False)
        draw_closes = moe_after_draw is not None and moe_after_draw <= rev.TARGET_MOE

        # Step 3: depth top-up on EXISTING clusters only, beyond what's already assumed
        # complete (households_in_cluster minus the CEILING, not minus real achieved -
        # closing the gap to ceiling is normal business-as-usual completion, not a new
        # ask; only true capacity BEYOND that ceiling counts as "additional"). New
        # clusters already maxed by the dry-run's own building validation - supply 0.
        supply = {c["cluster_id"]: max(0, hh_in_cluster.get(c["cluster_id"], 0) - c["n_primary_ceiling_contribution"]) for c in acc}
        for nc in new_clusters:
            supply[nc["cluster_id"]] = 0

        if draw_closes:
            depth_needed, depth_detail, final_total, final_moe, reaches = 0, "not needed - real draw alone closes it", sum(delivered_sizes), moe_after_draw, "Yes"
        else:
            result = rev.topup_search(m, st, combined_baseline, st["N_acc"], supply, "B")
            depth_needed = result.get("total") or 0
            # "additional real interviews needed" = genuinely NEW asks only (the real
            # draw + true depth beyond the ceiling) - NOT the gap to ceiling itself,
            # which is normal completion of what's already assigned, already counted
            # everywhere else in this project as "Remaining needed", not a fresh ask.
            final_total = sum(delivered_sizes) + depth_needed
            final_moe = result.get("moe")
            reaches = "Yes" if result.get("feasible") else "No - this is the real best-achievable ceiling, every true lever exhausted"
            touched = []
            if result.get("alloc"):
                for c, a in zip(result["live"], result["alloc"]):
                    if a > 0 and not str(c["cluster_id"]).startswith("NEW_"):
                        old_t = target_hh_design.get(c["cluster_id"], 0)
                        touched.append(f"{c['cluster_id']}:{old_t}->{old_t + a}(true cap {hh_in_cluster.get(c['cluster_id'], 0)})")
            depth_detail = "; ".join(touched) if touched else "no existing-cluster depth capacity available"

        rows_out.append({
            "strata_id": sid, "state": st["state"], "lga": st["lga"], "pop_type": st["pop_label"], "partner": st["partners_covering"],
            "current_moe_real_pct": round(current_moe, 2) if current_moe is not None else "N/A - not yet computable",
            "real_new_clusters_deliverable": len(delivered_sizes),
            "real_new_cluster_sizes": "/".join(str(x) for x in delivered_sizes),
            "moe_after_real_draw_only_pct": round(moe_after_draw, 2) if moe_after_draw is not None else "N/A - not yet computable",
            "existing_clusters_depth_additional_needed": depth_needed,
            "existing_clusters_depth_detail": depth_detail,
            "total_additional_real_interviews_combined": final_total,
            "projected_moe_final_pct": round(final_moe, 2) if final_moe is not None else "N/A - not yet computable",
            "reaches_10pct": reaches,
            "reason_if_excluded": "",
        })
        print(f"  {sid} ({st['lga']} {st['pop_label']}): draw {len(delivered_sizes)} clusters -> {moe_after_draw}, +depth {depth_needed} -> final {final_moe} ({reaches[:3]})")

    out_csv = os.path.join(OUT_DIR, "full_sweep_COMBINED_strategy_2026-09-30.csv")
    fieldnames = list(rows_out[0].keys())
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows_out)

    n_reaches = sum(1 for r in rows_out if r["reaches_10pct"] == "Yes")
    print(f"\nTotal strata: {len(rows_out)}")
    print(f"Reaches <=10% via combined real draw + depth top-up: {n_reaches}")
    print(f"Best-achievable-but-still-above-10% (real, computed ceiling, not N/A): {len(rows_out) - n_reaches}")
    print(f"\nWrote {out_csv}")


if __name__ == "__main__":
    main()
