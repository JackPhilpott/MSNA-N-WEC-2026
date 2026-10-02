# ==============================================================================
# 3 housekeeping updates to full_sweep_COMBINED_strategy_2026-09-30.csv, all
# from Jack's 30 Sep decisions (relayed via Coordinator + confirmed directly):
#
# 1. Binji IDP (idp_NG034001) reverts to normal - Jack's explicit instruction,
#    not excluded/anomalous. Recomputed for real (not forced) via the
#    realized_moe_unequal() FPC-floor-at-0 fix already applied to 05 tonight
#    (see 05_build_accessibility_impact_workbook.py and the memory note) -
#    this row is refreshed from the LIVE strata_representativity_status.csv,
#    same as every other row, not hand-typed.
# 2. The 12 accessibility-capped strata get a clearer reaches_10pct label -
#    "No available population" language, distinguishing them from a genuine
#    population-size cap (there isn't one among these 12, confirmed 30 Sep).
# 3. The 4 IDP strata Jack approved AND that were actually executed tonight
#    (Charanchi IDP, Obi IDP, Wamako IDP, Shinkafi IDP - real D3 depth top-up,
#    merged into the live v14 frame, verified Representative) get a new
#    execution_status column so the table doesn't show them as still-pending
#    asks for Jack's morning review.
# ==============================================================================
import csv
import importlib.util

RS = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling"
OUT_DIR = RS + r"\output\full_sweep_2026-09-29"
CSV_PATH = OUT_DIR + r"\full_sweep_COMBINED_strategy_2026-09-30.csv"
STATUS_CSV = RS + r"\output\strata_representativity_status.csv"


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ACCESSIBILITY_CAPPED = {
    "idp_NG019007", "idp_NG021027", "idp_NG037012", "non_idp_NG002010", "non_idp_NG008007",
    "non_idp_NG008008", "non_idp_NG008015", "non_idp_NG008020", "non_idp_NG021008",
    "non_idp_NG021014", "non_idp_NG021025", "non_idp_NG022020",
}  # the 12 - Binji (idp_NG034001) deliberately excluded, see #1 above

EXECUTED_TONIGHT = {
    "idp_NG021006": "EXECUTED 2026-09-30: real D3 depth top-up merged (+15 interviews, 6 clusters, CARE), verified Representative (moe_cert 9.43%)",
    "idp_NG026011": "EXECUTED 2026-09-30: real D3 depth top-up merged (+66 interviews to Jack's override target of 66, 3 clusters, CARE - Odobu excluded, selection_count collision risk, redistributed), verified Representative (moe_cert 7.48%)",
    "idp_NG034021": "EXECUTED 2026-09-30: real D3 depth top-up merged (+81 interviews, 4 clusters, CRS), verified Representative (moe_cert 9.27%)",
    "idp_NG037011": "EXECUTED 2026-09-30: real D3 depth top-up merged (+21 interviews, 7 clusters, FACT), verified Representative (moe_cert 9.47%)",
}

NONIDP_BLOCKED = {
    "non_idp_NG008011": "Gwoza", "non_idp_NG008025": "Ngala", "non_idp_NG008027": "Shani",
    "non_idp_NG021006": "Charanchi", "non_idp_NG022007": "Bunza", "non_idp_NG022011": "Jega",
    "non_idp_NG022012": "Kalgo",
}
for sid, lga in NONIDP_BLOCKED.items():
    EXECUTED_TONIGHT[sid] = (
        f"APPROVED by Jack, BLOCKED 2026-09-30: no tested existing-cluster depth top-up mechanism exists on the "
        f"Non-IDP side (merge_partner_resample_batch.R's target_increases/additions path is IDP-only, checked "
        f"directly - confirmed no non_idp equivalent anywhere in 1_sampling). Needs either a new, tested Non-IDP "
        f"mechanism (real build+test work, not done tonight) or a different route. Reported to Coordinator."
    )


def main():
    with open(STATUS_CSV, encoding="utf-8-sig") as f:
        status_rows = {r["Strata ID"]: r for r in csv.DictReader(f)}

    with open(CSV_PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    fieldnames = list(rows[0].keys())
    if "execution_status" not in fieldnames:
        fieldnames.append("execution_status")

    for r in rows:
        sid = r["strata_id"]
        r.setdefault("execution_status", "")
        if sid in EXECUTED_TONIGHT:
            r["execution_status"] = EXECUTED_TONIGHT[sid]
        if sid in ACCESSIBILITY_CAPPED:
            r["reaches_10pct"] = "No available population (accessibility-capped, NOT a genuine population-size cap - confirmed 2026-09-30)"
        if sid == "idp_NG034001":
            sr = status_rows.get(sid)
            if sr is not None:
                verdict = sr["Representativity (10% MoE threshold)"]
                moe = sr["Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)"]
                r["reaches_10pct"] = "Yes" if verdict.startswith("Representative") else verdict
                r["projected_moe_final_pct"] = moe
                r["reason_if_excluded"] = ""
                r["execution_status"] = (
                    "REVERTED TO NORMAL 2026-09-30 (Jack's explicit instruction): the 39 pending duplicate-flag "
                    "interviews at Makarantar Boko count as achieved until confirmed, same as every other pending "
                    "flag (standard policy). Underlying formula fixed same night (realized_moe_unequal() now floors "
                    "the FPC term at 0 when achieved >= N_hh_accessible, mirroring realized_moe_certainty_aware()'s "
                    "own existing per-site convention, instead of returning None) - was the real cause of the "
                    "'Not computable' reading, not a data problem. Recomputed live via strata_representativity_status.csv, not hand-set."
                )
                print(f"Binji reverted: verdict={verdict}, moe={moe}")

    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"Updated: {CSV_PATH}")


if __name__ == "__main__":
    main()
