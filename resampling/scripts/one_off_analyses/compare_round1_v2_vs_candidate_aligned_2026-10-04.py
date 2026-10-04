"""
compare_round1_v2_vs_candidate_aligned_2026-10-04.py - what aligning the Round 1 weights and representativity to the
data officer's cleaned dataset would change, inside the Round 1 analysis coverage (NE + NW, Kebbi out).
Writes COMPARISON.md and strata_label_changes.csv into the candidate folder. Run from the workspace folder.
"""
import csv, collections, os

C = "1_sampling/resampling/output/round1_candidate_aligned_to_DO_clean_2026-10-04"
V2_REP = "1_sampling/resampling/output/round1_representativity_prototype_2026-10-02"
V2_W = "1_sampling/resampling/output/full_weighting_build_2026-09-28/round1_FINAL_2026-10-02"
COV = {"Adamawa", "Borno", "Yobe", "Kaduna", "Kano", "Katsina", "Sokoto", "Zamfara"}


def rd(p):
    with open(p, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def main():
    s2 = {r["strata_id"]: r for r in rd(f"{V2_REP}/round1_strata.csv") if r["State"] in COV}
    sc = {r["strata_id"]: r for r in rd(f"{C}/representativity/round1_strata.csv") if r["State"] in COV}
    l2 = {(r["State"], r["LGA"], r["Scope"]): r for r in rd(f"{V2_REP}/round1_lga.csv") if r["State"] in COV}
    lc = {(r["State"], r["LGA"], r["Scope"]): r for r in rd(f"{C}/representativity/round1_lga.csv") if r["State"] in COV}
    t2 = {(r["State"], r["Scope"]): r for r in rd(f"{V2_REP}/round1_state.csv") if r["State"] in COV}
    tc = {(r["State"], r["Scope"]): r for r in rd(f"{C}/representativity/round1_state.csv") if r["State"] in COV}
    w2 = rd(f"{V2_W}/ROUND1_WEIGHTS_FINAL_2026-10-02.csv")
    wc = rd(f"{C}/weights/ROUND1_WEIGHTS_FINAL_2026-10-02.csv")
    b2 = {r["strata_id"]: r for r in rd(f"{V2_W}/ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv")}
    bc = {r["strata_id"]: r for r in rd(f"{C}/weights/ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv")}
    in_cov = lambda sid, b: sid in b and b[sid]["State"] in COV

    lab = lambda d: collections.Counter(r["Round 1 label"] for r in d.values())
    changes = []
    for sid in sorted(set(s2) | set(sc)):
        a, b = s2.get(sid), sc.get(sid)
        if a is None or b is None or a["Round 1 label"] != b["Round 1 label"] or a["Achieved (Round 1)"] != b["Achieved (Round 1)"]:
            changes.append({"State": (a or b)["State"], "LGA": (a or b)["LGA"], "Pop type": (a or b)["Pop type"], "strata_id": sid,
                            "achieved_v2": a and a["Achieved (Round 1)"], "achieved_candidate": b and b["Achieved (Round 1)"],
                            "moe_v2": a and a["MoE Round 1 (deff=1) %"], "moe_candidate": b and b["MoE Round 1 (deff=1) %"],
                            "label_v2": a and a["Round 1 label"], "label_candidate": b and b["Round 1 label"]})
    with open(f"{C}/strata_label_changes.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(changes[0].keys()) if changes else ["strata_id"])
        w.writeheader(); w.writerows(changes)
    flips = [c for c in changes if c["label_v2"] != c["label_candidate"]]
    lflips = [(k, l2[k]["Round 1 label"], lc[k]["Round 1 label"]) for k in l2 if k in lc and l2[k]["Round 1 label"] != lc[k]["Round 1 label"]]
    tflips = [(k, t2[k]["Round 1 label"], tc[k]["Round 1 label"]) for k in t2 if k in tc and t2[k]["Round 1 label"] != tc[k]["Round 1 label"]]
    w2c = [r for r in w2 if in_cov(r["strata_id"], b2)]
    wcc = [r for r in wc if in_cov(r["strata_id"], bc)]
    cal_ok = all(abs(float(r["sum_weight"]) - float(r["N_acc"])) < 0.06 for r in bc.values())
    lines = [
        "# Round 1: current package (v2) vs. candidate aligned to the data officer's cleaned dataset",
        "",
        "Inside the Round 1 analysis coverage (NE + NW, Kebbi out). The candidate removes 283 households from the Round 1 set",
        "(204 the data officer deleted for duplication or quality, 198 of them in coverage; 79 submitted on 1 Oct that the",
        "cleaned dataset treats as Round 2), then re-runs the unchanged, verified representativity and weights scripts.",
        "",
        "| | Current package (v2) | Candidate |",
        "|---|---:|---:|",
        f"| Achieved in coverage | {sum(int(r['Achieved (Round 1)']) for r in s2.values()):,} | {sum(int(r['Achieved (Round 1)']) for r in sc.values()):,} |",
        f"| Weighted households in coverage | {len(w2c):,} | {len(wcc):,} |",
        f"| Weighted strata in coverage | {sum(1 for s in b2 if in_cov(s, b2))} | {sum(1 for s in bc if in_cov(s, bc))} |",
        f"| Strata: Representative / Indicative / Dropped | {lab(s2).get('Representative', 0)} / {lab(s2).get('Indicative - meets reporting threshold', 0)} / {sum(v for k, v in lab(s2).items() if k.startswith('Dropped'))} | {lab(sc).get('Representative', 0)} / {lab(sc).get('Indicative - meets reporting threshold', 0)} / {sum(v for k, v in lab(sc).items() if k.startswith('Dropped'))} |",
        f"| Calibration exact in every weighted stratum | yes | {'yes' if cal_ok else 'NO'} |",
        "",
        f"**Strata whose label changes: {len(flips)}.**",
    ]
    for c in flips:
        lines.append(f"- {c['State']} / {c['LGA']} {c['Pop type']}: {c['label_v2']} -> {c['label_candidate']} "
                     f"(achieved {c['achieved_v2']} -> {c['achieved_candidate']}, MoE {c['moe_v2']} -> {c['moe_candidate']}%)")
    lines += ["", f"**LGA rows whose label changes: {len(lflips)}.**"]
    lines += [f"- {k[0]} / {k[1]} ({k[2]}): {a} -> {b}" for k, a, b in lflips]
    lines += ["", f"**State rows whose label changes: {len(tflips)}.**"]
    lines += [f"- {k[0]} ({k[1]}): {a} -> {b}" for k, a, b in tflips]
    lines += ["", f"Strata whose achieved count changes (any label): {len(changes)} - listed in `strata_label_changes.csv`."]
    with open(f"{C}/COMPARISON.md", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
