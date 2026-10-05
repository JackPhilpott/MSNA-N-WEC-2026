# ==============================================================================
# 2026-10-04 DRY RUN / READ-ONLY. Jack's rule (4 Oct, relayed by the Coordinator): "if any of the LGAs
# absorbed by FACT tonight doesn't have an accessibility report and is Borno, default back to Isa's full
# Borno report from last week." Of tonight's Borno LGAs, Mafa / Mobbar / Monguno have FACT reports; Bama and
# Kala/Balge (now shared "PLAN, FACT") do not, so FACT's position there = Isa's review.
#
# What it does (writes ONLY to resampling/output/staged_isa_borno_default_2026-10-04/):
#   (a) Bama + Kala/Balge: one FACT ward row per Isa answer (Accessible -> Yes, Inaccessible -> No; blank or
#       "Not yet assessed" -> no row). PLAN's rows are KEPT (PLAN still covers both LGAs), so 04's any-No
#       rule applies: Isa's No closes a ward PLAN reports open; Isa's Yes cannot reopen a ward PLAN reports
#       closed. Predicted ward flips + the WORKING to-do rows / clusters / target in the flipping wards.
#   (b) Dikwa, row by row: Isa's answer vs FACT's 4 Oct answer (Street Child file) vs the master.
#   (c) Chibok / Damboa: Isa's answer for each ward that is Inaccessible only on IMC's word.
#   Provenance check: Isa's answers must reproduce the 26 Sep log rows sourced from her review.
#
# Source file: the 25 Sep copy (partner_raw_comms/FACT/..._Isa_2509.xlsx) is cloud-only while OneDrive is
# not serving files; --isa-file takes another copy (tonight: Isa's file from the Outlook attachment cache,
# last modified by Isa 2026-09-21 14:33; same column O/P counts as the 26 Sep read of _2509). The md5 and
# path of the file used are written into every output. Re-run on _2509 itself before anything is applied.
#
# Usage: python stage_isa_borno_default_2026-10-04.py [--isa-file PATH]
# ==============================================================================
import argparse
import csv
import hashlib
import os
from collections import defaultdict

import openpyxl

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DC = os.path.join(os.path.dirname(RS), "output", "data", "data_collection")
ISA_DEFAULT = os.path.join(RS, "input", "partner_raw_comms", "FACT", "FACT_Borno_Accessibility_Review_2026-09-17_FACT_Isa_2509.xlsx")
FACT_0410 = os.path.join(RS, "input", "partner_raw_comms", "04102026_bigresampling", "Street Child of Nigeria_accessibility_report.xlsx")
LOG = os.path.join(RS, "output", "resampling_requests_log.csv")
MASTER = os.path.join(RS, "output", "master_accessibility_status_ward_level.csv")
WORKING = os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv")
OUT = os.path.join(RS, "output", "staged_isa_borno_default_2026-10-04")
DEFAULT_LGAS = ("Bama", "Kala/Balge")


def norm(v):
    return "" if v is None or str(v).strip().lower() in ("", "none", "nan") else str(v).strip()


def isa_answer(v):
    return {"accessible": "Yes", "inaccessible": "No"}.get(norm(v).lower())


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def write(name, rows):
    if not rows:
        return
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--isa-file", default=ISA_DEFAULT)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    src = f"{os.path.basename(args.isa_file)} md5 {md5(args.isa_file)[:8]}"
    print("Isa file:", args.isa_file, "|", src)

    wb = openpyxl.load_workbook(args.isa_file, read_only=True, data_only=True)
    raw = list(wb["Borno Ward Review"].iter_rows(values_only=True))
    wb.close()
    hi = next(i for i, r in enumerate(raw) if sum(c not in (None, "") for c in r) >= 5)
    h = [norm(c) for c in raw[hi]]
    isa = {}
    for r in raw[hi + 1:]:
        d = dict(zip(h, r))
        if norm(d.get("LGA")):
            k = (norm(d["LGA"]), norm(d["Ward (GRID3)"]))
            if k in isa:
                raise SystemExit(f"STOP: Isa's sheet has {k} twice")
            isa[k] = d
    print(f"Isa's sheet: {len(isa)} wards; column O answered on {sum(1 for d in isa.values() if norm(d.get(h[14])))}")
    col_o, col_p, col_q = h[14], h[15], h[16]

    with open(LOG, encoding="utf-8-sig", newline="") as f:
        log = list(csv.DictReader(f))
    with open(MASTER, encoding="utf-8-sig", newline="") as f:
        master = {(r["LGA"], r["Ward (GRID3)"]): r for r in csv.DictReader(f) if r["State"] == "Borno"}

    # ---- provenance: Isa's answers reproduce the 26/27 Sep rows sourced from her review ----
    from_isa = [r for r in log if "Isa Jugudum" in r["reason_notes"] and r["report_level"] == "ward"]
    mism = [(r["lga"], r["ward_name"], r["accessible"], norm(isa.get((r["lga"], r["ward_name"]), {}).get(col_o)))
            for r in from_isa if isa_answer(isa.get((r["lga"], r["ward_name"]), {}).get(col_o)) != r["accessible"]]
    print(f"provenance: {len(from_isa)} logged rows cite Isa's review; answers that differ in this file: {len(mism)} {mism[:5]}")

    # ---- latest ward row per partner (04's rule) ----
    latest = {}
    for r in log:
        if r["report_level"] == "ward" and r["state"] == "Borno":
            k = (r["partner"], r["lga"], r["ward_name"])
            if k not in latest or int(r["request_id"]) > int(latest[k]["request_id"]):
                latest[k] = r
    by_ward = defaultdict(dict)
    for (p, lga, ward), r in latest.items():
        by_ward[(lga, ward)][p] = r

    # WORKING to-do rows per ward (what a flip would take off PLAN's / FACT's lists)
    todo = defaultdict(lambda: defaultdict(set))
    rows_n = defaultdict(lambda: defaultdict(int))
    with open(WORKING, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if r["adm1_name"] == "Borno" and r["adm2_name"] in DEFAULT_LGAS + ("Dikwa", "Chibok", "Damboa"):
                todo[(r["adm2_name"], r["adm3_name"])][r["pop_type"]].add(r["cluster_id"])
                rows_n[(r["adm2_name"], r["adm3_name"])][r["pop_type"]] += 1

    # ---- (a) Bama + Kala/Balge ----
    out_a = []
    for (lga, ward), d in sorted(isa.items()):
        if lga not in DEFAULT_LGAS:
            continue
        ans = isa_answer(d.get(col_o))
        reps = dict(by_ward.get((lga, ward), {}))
        now = master.get((lga, ward), {}).get("Accessible status", "NOT IN MASTER")
        if ans:
            reps["FACT"] = {"accessible": ans}
        after = ("Inaccessible" if any(x["accessible"].strip().lower() == "no" for x in reps.values()) else "Accessible") if reps else now
        plan = by_ward.get((lga, ward), {}).get("PLAN")
        out_a.append({
            "lga": lga, "ward": ward, "isa_answer": norm(d.get(col_o)) or "<blank>", "isa_decision": norm(d.get(col_p)),
            "isa_notes": norm(d.get(col_q)), "master_now": now,
            "plan_latest": f"{plan['accessible']} (#{plan['request_id']} {plan['date_added']}; {norm(plan['reason_category'])})" if plan else "no PLAN row",
            "other_partners_latest": "; ".join(f"{p}={x['accessible']}" for p, x in sorted(by_ward.get((lga, ward), {}).items()) if p != "PLAN"),
            "fact_row_to_append": ans or "none", "after": after, "flips": after != now,
            "working_rows_nonidp": rows_n[(lga, ward)].get("non_idp", 0), "working_rows_idp": rows_n[(lga, ward)].get("idp", 0),
            "working_clusters": len(todo[(lga, ward)].get("non_idp", set()) | todo[(lga, ward)].get("idp", set())),
            "isa_source": src})
    missing = [k for k in master if k[0] in DEFAULT_LGAS and k not in isa]
    print(f"\n(a) Bama + Kala/Balge: {len(out_a)} wards in Isa's sheet; master wards not in her sheet: {missing}")
    for o in out_a:
        print(f"   {o['lga']:10s} {o['ward']:16s} Isa={o['isa_answer']:13s} now={o['master_now']:12s} PLAN={o['plan_latest'][:44]:44s} "
              f"-> {o['after']:12s}{'  FLIP' if o['flips'] else ''}  WORKING NI {o['working_rows_nonidp']} / IDP {o['working_rows_idp']}")
    fl = [o for o in out_a if o["flips"]]
    print(f"   -> FACT rows to append: {sum(1 for o in out_a if o['fact_row_to_append'] != 'none')}; ward flips: {len(fl)} "
          f"(to Inaccessible {sum(1 for o in fl if o['after'] == 'Inaccessible')}, to Accessible {sum(1 for o in fl if o['after'] == 'Accessible')}); "
          f"WORKING rows in flipping wards: NI {sum(o['working_rows_nonidp'] for o in fl)}, IDP {sum(o['working_rows_idp'] for o in fl)}, "
          f"clusters {sum(o['working_clusters'] for o in fl)}")

    # ---- (b) Dikwa row by row ----
    wbf = openpyxl.load_workbook(FACT_0410, read_only=True, data_only=True)
    fr = list(wbf["Ward Accessibility"].iter_rows(values_only=True))
    wbf.close()
    fh = [norm(c) for c in fr[0]]
    fact_dikwa = {norm(dict(zip(fh, r)).get("Ward (GRID3)")): dict(zip(fh, r)) for r in fr[1:] if norm(dict(zip(fh, r)).get("LGA")) == "Dikwa"}
    out_b = []
    for ward in sorted(set(w for (l, w) in isa if l == "Dikwa") | set(fact_dikwa) | set(w for (l, w) in master if l == "Dikwa")):
        d = isa.get(("Dikwa", ward), {})
        f4 = fact_dikwa.get(ward, {})
        out_b.append({"ward": ward, "isa_21sep": norm(d.get(col_o)) or "<blank>", "isa_notes": norm(d.get(col_q)),
                      "fact_4oct": norm(f4.get("Accessible (Y/N)")) or "<blank>", "fact_4oct_reason": norm(f4.get("Reason category")),
                      "master_now": master.get(("Dikwa", ward), {}).get("Accessible status", "NOT IN MASTER"),
                      "isa_vs_fact_4oct": ("agree" if isa_answer(d.get(col_o)) and {"y": "Yes", "yes": "Yes", "n": "No", "no": "No"}.get(norm(f4.get("Accessible (Y/N)")).lower()) == isa_answer(d.get(col_o))
                                           else "differ/blank"), "isa_source": src})
    print("\n(b) Dikwa, row by row:")
    for o in out_b:
        print(f"   {o['ward']:18s} Isa 21 Sep={o['isa_21sep']:13s} FACT 4 Oct={o['fact_4oct']:8s} master={o['master_now']:12s} {o['isa_vs_fact_4oct']}")

    # ---- (c) Chibok / Damboa wards Inaccessible only on IMC's word ----
    out_c = []
    for (lga, ward), reps in sorted(by_ward.items()):
        if lga not in ("Chibok", "Damboa"):
            continue
        imc = reps.get("IMC")
        if imc and imc["accessible"].strip().lower() == "no" and not any(p != "IMC" and x["accessible"].strip().lower() == "no" for p, x in reps.items()):
            d = isa.get((lga, ward), {})
            fact = reps.get("FACT")
            out_c.append({"lga": lga, "ward": ward, "imc_latest": f"No (#{imc['request_id']} {imc['date_added']})",
                          "fact_latest_logged": f"{fact['accessible']} (#{fact['request_id']} {fact['date_added']})" if fact else "no FACT row",
                          "isa_21sep": norm(d.get(col_o)) or ("<blank>" if d else "<not in Isa's sheet>"), "isa_notes": norm(d.get(col_q)),
                          "master_now": master.get((lga, ward), {}).get("Accessible status", "?"),
                          "working_rows": sum(rows_n[(lga, ward)].values()), "isa_source": src})
    print("\n(c) Chibok / Damboa wards Inaccessible only on IMC's word:")
    for o in out_c:
        print(f"   {o['lga']:7s} {o['ward']:18s} IMC {o['imc_latest']:24s} FACT logged {o['fact_latest_logged']:28s} Isa 21 Sep={o['isa_21sep']:13s} {o['isa_notes'][:45]}")
    from collections import Counter
    print("   -> Isa's answers on these:", dict(Counter(o["isa_21sep"] for o in out_c)))

    write("bama_kalabalge_isa_default_predicted.csv", out_a)
    write("dikwa_isa_vs_fact_4oct.csv", out_b)
    write("chibok_damboa_imc_only_wards_isa_answers.csv", out_c)
    print(f"\n(dry run) nothing live written; CSVs in {OUT}")


if __name__ == "__main__":
    main()
