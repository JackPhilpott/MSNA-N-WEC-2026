# ==============================================================================
# 2026-10-04 READ-ONLY, for Jack's decision list (Coordinator asks (a), (b)):
# (a) DIKWA: FACT dated all Dikwa rows in the Street Child file it sent on 4 Oct.
#     Dikwa has been FACT's since 19 Sep but is not one of tonight's 14 moved LGAs,
#     so Jack's rule ("only the LGAs FACT has now been given") excludes it. What would
#     FACT's edited answers change vs the current master / cluster overlay?
# (b) CHIBOK / DAMBOA (IMC -> FACT on 25 Sep): wards Inaccessible ONLY because IMC's
#     stale latest row says No while FACT's latest says Yes (04's any-No rule), and
#     clusters excluded only because IMC's row is the latest for that (cluster, ward).
# Writes nothing except a CSV per question in staged_fact_accessibility_2026-10-04/.
# ==============================================================================
import csv
import os
from collections import defaultdict

import openpyxl

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WS = os.path.dirname(os.path.dirname(RS))
PKG = os.path.join(os.path.dirname(os.path.dirname(WS)), "3. External coordination", "NGA MSNA 2026 Package")
LOG = os.path.join(RS, "output", "resampling_requests_log.csv")
MASTER = os.path.join(RS, "output", "master_accessibility_status_ward_level.csv")
OVERLAY = os.path.join(RS, "output", "cluster_accessibility_overlay.csv")
FACT_FILE = os.path.join(RS, "input", "partner_raw_comms", "04102026_bigresampling", "Street Child of Nigeria_accessibility_report.xlsx")
BASE_FILE = os.path.join(PKG, "Street Child of Nigeria", "Street Child of Nigeria_accessibility_report.xlsx")
OUT = os.path.join(RS, "output", "staged_fact_accessibility_2026-10-04")
FIELDS = ("Accessible (Y/N)", "Reason category", "Reason notes", "Date reported")
W = os.path.join(WS, "1_sampling", "output", "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv")
F = os.path.join(WS, "1_sampling", "output", "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv")


def norm(v):
    return "" if v is None or str(v).strip().lower() in ("", "none", "nan") else str(v).strip()


def yn(v):
    return {"yes": "Yes", "y": "Yes", "no": "No", "n": "No"}.get(norm(v).lower())


def read_sheet(p, sheet):
    wb = openpyxl.load_workbook(p, read_only=True, data_only=True)
    rows = list(wb[sheet].iter_rows(values_only=True))
    wb.close()
    h = [str(c).strip() if c is not None else f"c{i}" for i, c in enumerate(rows[0])]
    return [dict(zip(h, r)) for r in rows[1:] if any(v not in (None, "") for v in r)]


def main():
    log = list(csv.DictReader(open(LOG, encoding="utf-8-sig")))
    master = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r for r in csv.DictReader(open(MASTER, encoding="utf-8-sig"))}
    overlay = {r["cluster_id"] for r in csv.DictReader(open(OVERLAY, encoding="utf-8-sig"))}
    work_rows = defaultdict(int)
    for r in csv.DictReader(open(W, encoding="utf-8-sig")):
        work_rows[r["cluster_id"]] += 1
    full_info = {}
    for r in csv.DictReader(open(F, encoding="utf-8-sig")):
        full_info.setdefault(r["cluster_id"], (r["adm2_name"], r["adm3_name"], r["ward_accessible_status"]))

    # ---------------- (a) Dikwa ----------------
    base_w = {(r["LGA"], r["Ward (GRID3)"]): r for r in read_sheet(BASE_FILE, "Ward Accessibility")}
    base_c = {r["Cluster ID"]: r for r in read_sheet(BASE_FILE, "Cluster Accessibility") if r.get("Cluster ID")}
    out_a = []
    print("== (a) DIKWA: FACT's edited answers in the Street Child file vs current master / overlay")
    for r in read_sheet(FACT_FILE, "Ward Accessibility"):
        if r["LGA"] != "Dikwa":
            continue
        b = base_w.get((r["LGA"], r["Ward (GRID3)"]))
        ed = b is None or any(norm(r.get(x)) != norm(b.get(x)) for x in FIELDS)
        now = master.get((r["State"], r["LGA"], r["Ward (GRID3)"]), {}).get("Accessible status", "NOT IN MASTER")
        ans = yn(r.get("Accessible (Y/N)"))
        after = {"Yes": "Accessible", "No": "Inaccessible"}.get(ans, now)
        out_a.append({"level": "ward", "key": r["Ward (GRID3)"], "fact_edited": ed, "fact_answer": ans or "", "master_now": now,
                      "would_change": ed and after != now, "reason": norm(r.get("Reason category")), "date": norm(r.get("Date reported"))})
    for r in read_sheet(FACT_FILE, "Cluster Accessibility"):
        if r["LGA"] != "Dikwa" or not r.get("Cluster ID"):
            continue
        cid = r["Cluster ID"]
        b = base_c.get(cid)
        ed = b is None or any(norm(r.get(x)) != norm(b.get(x)) for x in FIELDS)
        ans = yn(r.get("Accessible (Y/N)"))
        now = "excluded" if cid in overlay else "not excluded"
        after = "excluded" if ans == "No" else ("not excluded" if ans == "Yes" else now)
        out_a.append({"level": "cluster", "key": cid, "fact_edited": ed, "fact_answer": ans or "", "master_now": now,
                      "would_change": ed and after != now, "reason": norm(r.get("Reason category")),
                      "date": norm(r.get("Date reported")) + f" | WORKING rows now {work_rows.get(cid, 0)}"})
    for o in out_a:
        flag = "  <- WOULD CHANGE" if o["would_change"] else ""
        print(f"   {o['level']:7s} {o['key']:22s} edited={str(o['fact_edited']):5s} FACT={o['fact_answer']:3s} now={o['master_now']:13s} {o['reason'][:26]:26s}{flag}")
    print(f"   -> {sum(o['would_change'] for o in out_a if o['level'] == 'ward')} ward(s), "
          f"{sum(o['would_change'] for o in out_a if o['level'] == 'cluster')} cluster(s) would change")

    # ---------------- (b) Chibok / Damboa stale IMC ----------------
    print("\n== (b) CHIBOK / DAMBOA: Inaccessible only because of a stale IMC row")
    latest = {}
    for r in log:
        if r["report_level"] == "ward" and r["lga"] in ("Chibok", "Damboa"):
            k = (r["partner"], r["lga"], r["ward_name"])
            if k not in latest or int(r["request_id"]) > int(latest[k]["request_id"]):
                latest[k] = r
    by_ward = defaultdict(dict)
    for (p, lga, ward), r in latest.items():
        by_ward[(lga, ward)][p] = r
    out_b = []
    for (lga, ward), reps in sorted(by_ward.items()):
        imc, fact = reps.get("IMC"), reps.get("FACT")
        others_no = [p for p, r in reps.items() if p not in ("IMC",) and r["accessible"].strip().lower() == "no"]
        if imc and imc["accessible"].strip().lower() == "no" and not others_no:
            st = master.get(("Borno", lga, ward), {}).get("Accessible status", "?")
            out_b.append({"level": "ward", "lga": lga, "key": ward, "imc_latest": f"No (#{imc['request_id']} {imc['date_added']})",
                          "fact_latest": (f"{fact['accessible']} (#{fact['request_id']} {fact['date_added']})" if fact else "no FACT row"),
                          "master_now": st})
    lc = {}
    for r in log:
        if r["report_level"] == "cluster" and r["cluster_id"] and r["lga"] in ("Chibok", "Damboa"):
            k = (r["cluster_id"], r["ward_name"])
            if k not in lc or int(r["request_id"]) > int(lc[k]["request_id"]):
                lc[k] = r
    for (cid, ward), r in sorted(lc.items()):
        if r["partner"] == "IMC" and r["accessible"].strip().lower() == "no":
            out_b.append({"level": "cluster", "lga": r["lga"], "key": cid, "imc_latest": f"No (#{r['request_id']} {r['date_added']})",
                          "fact_latest": "none later for this (cluster, ward)",
                          "master_now": ("excluded" if cid in overlay else "not excluded") + f"; ward status in FULL: {full_info.get(cid, ('', '', '?'))[2]}"})
    for o in out_b:
        print(f"   {o['level']:7s} {o['lga']:7s} {o['key']:22s} IMC latest {o['imc_latest']:24s} | FACT latest {o['fact_latest']:28s} | now {o['master_now']}")
    wards = [o for o in out_b if o["level"] == "ward"]
    print(f"   -> wards Inaccessible only via IMC's stale No: {len(wards)} "
          f"(with a FACT Yes on file: {sum(1 for o in wards if o['fact_latest'].startswith('Yes'))}; "
          f"with no FACT row at all: {sum(1 for o in wards if o['fact_latest'] == 'no FACT row')}) | "
          f"clusters excluded via an IMC row that is still the latest: {sum(1 for o in out_b if o['level'] == 'cluster')}")
    for name, rows in (("dikwa_fact_answers_vs_master.csv", out_a), ("chibok_damboa_stale_imc.csv", out_b)):
        if rows:
            with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="") as fh:
                w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
                w.writeheader()
                w.writerows(rows)


if __name__ == "__main__":
    main()
