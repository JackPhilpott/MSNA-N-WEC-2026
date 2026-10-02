# ==============================================================================
# Adds "Available population (N_hh_accessible)" to full_sweep_COMBINED_
# strategy_2026-09-30.csv and checks Jack's hypothesis: for every "No - real
# ceiling" row, does new_target_samples actually exceed N_hh_accessible (the
# signature of a stratum genuinely capped by population size, not just
# clustering inefficiency)? CSV only, per Coordinator's hold on the xlsx.
# ==============================================================================
import csv
import importlib.util
import os

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = PROJECT_DIR + r"\1_sampling"
RS = S + r"\resampling"
REV_DIR = S + r"\resampling\output\representativity_review_2026-09-27"
CSV_PATH = RS + r"\output\full_sweep_2026-09-29\full_sweep_COMBINED_strategy_2026-09-30.csv"


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    m = load_module(RS + r"\scripts\05_build_accessibility_impact_workbook.py", "m05")
    rev = load_module(REV_DIR + r"\build_representativity_review.py", "rev")

    L = rev.load_state(m)
    status_csv = rev.rd(RS + r"\output\strata_representativity_status.csv")
    status_csv = [r for r in status_csv if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
    strata, bad, extra = rev.build_strata(m, L, status_csv)
    print(f"reproduction check: {len(strata)} strata, {len(bad)} mismatches, {len(extra)} extras")
    if bad or extra:
        raise SystemExit("STOP: not safe")

    with open(CSV_PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    holds, violates = [], []
    for r in rows:
        sid = r["strata_id"]
        st = strata.get(sid)
        n_acc = round(st["N_acc"]) if st is not None else "N/A"
        r["available_population_N_hh_accessible"] = n_acc

        if r["reaches_10pct"].startswith("No") and st is not None:
            try:
                new_t = int(float(r["new_target_samples"]))
            except (ValueError, TypeError):
                new_t = None
            if new_t is not None:
                if new_t > st["N_acc"]:
                    holds.append((r["lga"], r["pop_type"], new_t, round(st["N_acc"])))
                else:
                    violates.append((r["lga"], r["pop_type"], new_t, round(st["N_acc"])))

    print(f"\nHypothesis (new_target > N_hh_accessible) holds for {len(holds)} of {len(holds)+len(violates)} 'No' rows.")
    if violates:
        print("Does NOT hold for these - something ELSE is capping them, not population size:")
        for v in violates:
            print("  ", v)
    else:
        print("Holds for every single 'No' row - every non-closeable stratum is genuinely population-capped, confirmed.")

    fieldnames = list(rows[0].keys())
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"\nUpdated CSV written: {CSV_PATH}")


if __name__ == "__main__":
    main()
