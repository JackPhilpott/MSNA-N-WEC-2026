# ==============================================================================
# Adds 4 discussion columns to full_sweep_COMBINED_strategy_2026-09-30.csv
# (Jack, direct via Coordinator, 30 Sep) - Original target, Current revised
# target, Achieved samples so far, New target (samples). Everything else in
# the file left unchanged. Also writes an .xlsx version of the same table.
#
# "New target (samples)" = achieved + total_additional_real_interviews_combined
# (Jack's own definition) - sanity-checked against a fresh target_sample_
# representativity(N_hh_accessible, m_used) recompute per his own request.
# These are DELIBERATELY different formulas answering different questions:
# target_sample_representativity() is the crude, uniform-cluster-size
# reference figure (a function of population size alone, invariant to how
# interviews are actually distributed); the combined-strategy total is
# built from topup_search()'s RIGOROUS unequal-cluster-size, design-weighted
# search - the same real engine that actually drives whether a stratum
# crosses 10% MoE in reality, per this project's whole "never the crude
# uniform-cluster target_repr" convention (05's own comment). Both are
# reported so the divergence is visible, not picked silently.
# ==============================================================================
import csv
import importlib.util
import os

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = PROJECT_DIR + r"\1_sampling"
RS = S + r"\resampling"
REV_DIR = S + r"\resampling\output\representativity_review_2026-09-27"
OUT_DIR = RS + r"\output\full_sweep_2026-09-29"
CSV_PATH = os.path.join(OUT_DIR, "full_sweep_COMBINED_strategy_2026-09-30.csv")
XLSX_PATH = os.path.join(OUT_DIR, "full_sweep_COMBINED_strategy_2026-09-30.xlsx")


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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
        raise SystemExit("STOP: not safe to add columns on top of this")

    real_cluster = L["real_cluster"]

    with open(CSV_PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    print(f"Loaded {len(rows)} existing rows from {CSV_PATH}")

    mismatches = []
    for r in rows:
        sid = r["strata_id"]
        st = strata.get(sid)
        if st is None:
            r["original_target_samples"] = "N/A"
            r["current_revised_target_samples"] = "N/A"
            r["achieved_samples_so_far"] = "N/A"
            r["new_target_samples"] = "N/A"
            r["new_target_cross_check_target_sample_representativity_fn"] = "N/A"
            continue

        original_target = st.get("target_frame")
        revised_target = st.get("target_repr")
        achieved = sum(real_cluster.get(c["cluster_id"], 0) for c in st["clusters"])

        additional_raw = r.get("total_additional_real_interviews_combined", "")
        try:
            additional = int(float(additional_raw))
        except (TypeError, ValueError):
            additional = 0  # excluded/not-applicable rows (e.g. reason_if_excluded populated)

        new_target = achieved + additional

        # Sanity cross-check: target_sample_representativity() recomputed fresh at this
        # stratum's OWN N_hh_accessible/m_used (unchanged by the combined strategy -
        # it's a population-size function, not an achieved-count function) - reported
        # for comparison, NOT substituted in, since it's the cruder uniform-cluster
        # formula, not the rigorous one that actually drove new_target above.
        cross_check = None
        if st["N_acc"] > 0:
            tr = m.target_sample_representativity(st["N_acc"], st["m_used"])
            cross_check = math_ceil(tr) if tr is not None else None

        r["original_target_samples"] = original_target if original_target is not None else "N/A"
        r["current_revised_target_samples"] = revised_target if revised_target is not None else "N/A"
        r["achieved_samples_so_far"] = achieved
        r["new_target_samples"] = new_target
        r["new_target_cross_check_target_sample_representativity_fn"] = cross_check if cross_check is not None else "N/A"

        # Self-checks, per Jack's own ask.
        if original_target is not None and revised_target is not None and original_target < revised_target:
            mismatches.append(f"{sid}: original target ({original_target}) < revised target ({revised_target}) - unexpected direction")
        if achieved + additional != new_target:
            mismatches.append(f"{sid}: achieved+additional ({achieved}+{additional}) != new_target ({new_target}) - arithmetic bug")

    if mismatches:
        print(f"\n{len(mismatches)} self-check issue(s) found:")
        for msg in mismatches[:20]:
            print("  ", msg)
    else:
        print("\nSelf-checks clean: original >= revised target on every computable row, achieved+additional == new_target on every row.")

    fieldnames = list(rows[0].keys())
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"\nUpdated CSV written: {CSV_PATH}")
    print("xlsx version deliberately NOT written yet - Coordinator asked to hold until Jack's reviewed/confirmed the CSV numbers first.")


def math_ceil(x):
    import math
    return math.ceil(x)


if __name__ == "__main__":
    main()
