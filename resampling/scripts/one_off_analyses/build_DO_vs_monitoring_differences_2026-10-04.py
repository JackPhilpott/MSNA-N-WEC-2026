"""
build_DO_vs_monitoring_differences_2026-10-04.py - read-only

Lists every household on which the data officer's cleaned Round 1 dataset and the monitoring pipeline's frozen
Round 1 set (snapshot v2, the basis of the shared weights) disagree, so the data officer can check them.
  DO data:  2_monitoring/cleaning/NGA2605_MSNA_UNHCR_Combined_Cleaning/output/final/
            IMPACT_NGA_Dataset_MSNA-UNHCR-2026-Round1_October-2026.xlsx (hh_raw_data, hh_clean_data, hh_deletion_log)
  Ours:     snapshot v2 + the Round 1 deletion & correction log given to the DO on 2 Oct.
Writes one CSV beside that deletion log. Run from the workspace folder ("MSNA N-WEC 2026"):
  python 1_sampling/resampling/scripts/one_off_analyses/build_DO_vs_monitoring_differences_2026-10-04.py
"""
import collections, csv, importlib.util, os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("cand", os.path.join(HERE, "build_round1_candidate_aligned_to_DO_clean_2026-10-04.py"))
cand = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cand)

SNAP = "1_sampling/resampling/output/round1_final_snapshot_v2_2026-10-02"
KEY = "2_monitoring/reports/round1_weighting_package_2026-10-02/01_weights/R1_household_status_all_28046.csv"
STRATA = "1_sampling/output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"
CLOSEOUT = "2_monitoring/reports/partner_data_recovery/outputs/_round1_closeout"
OUR_LOG = os.path.join(CLOSEOUT, "MSNA_N-WEC_2026_Round1_deletion_log_2026-10-02.csv")
OUT = os.path.join(CLOSEOUT, "MSNA_N-WEC_2026_Round1_DO_vs_monitoring_differences_2026-10-04.csv")

CATS = [
    ("A", "Removed in your cleaning, kept as achieved by us"),
    ("B", "Achieved for us, not in your raw data: submitted on 1 Oct (after your 30 Sep Round 1 cut-off)"),
    ("C", "Achieved for us, not in your raw data: submitted by 30 Sep"),
    ("D", "Removed by us, not in your raw data"),
    ("F", "In your raw data, absent from your clean data, but not in your deletion log"),
    ("G", "Removed by us, in your raw data, but not in your deletion log"),
    ("E", "In your household deletion log, not in our Round 1 set (and not a UNHCR record)"),
]


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    do = cand.read_sheets(cand.DO_FILE, {"hh_raw_data": {"uuid", "assessment"}, "hh_clean_data": {"uuid", "assessment"},
                                         "hh_deletion_log": set()})
    raw = {r["uuid"]: r.get("assessment", "") for r in do["hh_raw_data"]}
    raw_msna = {u for u, a in raw.items() if a == "MSNA_R1"}
    clean = {r["uuid"] for r in do["hh_clean_data"] if r.get("assessment") == "MSNA_R1"}
    dlog = {r["uuid"]: r for r in do["hh_deletion_log"]}

    rs = {r["submission_uuid"]: r for r in rd(os.path.join(SNAP, "real_submissions.csv"))}
    key = {r["uuid"]: r for r in rd(KEY)}
    lga = {r["strata_id"]: r["adm2_name"] for r in rd(STRATA)}
    ours = collections.defaultdict(list)
    for r in rd(OUR_LOG):
        if r["change_type"] == "remove_survey":
            ours[r["uuid"]].append("removed: " + (r.get("issue") or r.get("check_id") or "").strip())
        else:
            ours[r["uuid"]].append(r["change_type"] + ": " + (r.get("decision_basis") or r.get("issue") or "").strip()[:90])

    achieved = {u for u, k in key.items() if k["r1_status"] == "achieved"}
    removed = {u for u, k in key.items() if k["r1_status"].startswith("removed")}
    assert clean <= achieved, "a household in the DO's clean data is not achieved in our set - investigate before sharing"

    cat = {}
    for u in achieved - clean:
        if u in dlog: cat[u] = "A"
        elif u in raw_msna: cat[u] = "F"
        else: cat[u] = "B" if rs[u]["submission_date"] > "2026-09-30" else "C"
    for u in removed:
        if u not in raw_msna: cat[u] = "D"
        elif u not in dlog: cat[u] = "G"
    unhcr = 0
    for u in dlog:
        if u not in rs:
            if raw.get(u) == "UNHCR": unhcr += 1
            else: cat[u] = "E"

    def issue_type(d):
        return next((v for k, v in d.items() if k.startswith("Type of Issue")), "")

    rows = []
    for u, c in cat.items():
        r, k, d = rs.get(u, {}), key.get(u, {}), dlog.get(u, {})
        sid = k.get("r1_strata_id") or ""
        rows.append({
            "uuid": u, "difference_code": c, "difference": dict(CATS)[c],
            "state": k.get("r1_state") or r.get("admin1", ""), "lga": lga.get(sid, r.get("admin2_submitted", "")),
            "population_group": {"idp": "IDP", "non_idp": "Non-IDP"}.get(k.get("r1_pop_type") or "", ""),
            "partner": r.get("org_id", ""), "strata_id": sid, "cluster_id": k.get("r1_cluster_id") or "",
            "submission_date": r.get("submission_date", ""),
            "our_status": k.get("r1_status") or "not in our Round 1 set",
            "our_deletion_log": " | ".join(dict.fromkeys(ours.get(u, [])))[:300],
            "your_status": "deleted in your cleaning" if u in dlog else ("in your clean data" if u in clean else
                           ("in your raw data only" if u in raw_msna else "not in your raw data")),
            "your_deletion_reason": (d.get("reason_deletion") or "")[:300], "your_issue_type": issue_type(d),
        })
    order = {c: i for i, (c, _) in enumerate(CATS)}
    rows.sort(key=lambda x: (order[x["difference_code"]], x["state"], x["lga"], x["submission_date"], x["uuid"]))
    with open(OUT, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    n = collections.Counter(x["difference_code"] for x in rows)
    for c, label in CATS:
        print(f"  {c}  {n.get(c, 0):5d}  {label}")
    print(f"  (UNHCR records in your deletion log, left out: {unhcr})")
    if n.get("A"):
        a = [x for x in rows if x["difference_code"] == "A"]
        print("  A by your issue type:", dict(collections.Counter(x["your_issue_type"] for x in a)))
        print("  A by partner:", dict(collections.Counter(x["partner"] for x in a).most_common()))
        print("  A by state:", dict(collections.Counter(x["state"] for x in a).most_common()))
        print("  A: our deletion log has an entry for", sum(1 for x in a if x["our_deletion_log"]), "of them")
    print(f"wrote {len(rows):,} rows to {OUT}")


if __name__ == "__main__":
    main()
