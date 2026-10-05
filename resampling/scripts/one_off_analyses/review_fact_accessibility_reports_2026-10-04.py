# ==============================================================================
# 2026-10-04 READ-ONLY review of the accessibility reports in
# resampling/input/partner_raw_comms/04102026_bigresampling/ (Jack: the reports
# for the LGAs FACT takes over tonight; apply ONLY after the reallocation and ONLY
# to those LGAs; document that any update comes from this change). Writes a
# ward-level comparison CSV to resampling/output/fact_accessibility_review_2026-10-04/
# and changes nothing else.
#
# For each report file, for the reallocated LGAs only: each ward's answer vs the
# current master_accessibility_status_ward_level.csv, and where a file has a "(1)"
# twin, every ward/cluster answer that differs between the two versions.
# ==============================================================================
import csv
import glob
import os
from collections import Counter, defaultdict

import openpyxl

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IN_DIR = os.path.join(RS, "input", "partner_raw_comms", "04102026_bigresampling")
OUT_DIR = os.path.join(RS, "output", "fact_accessibility_review_2026-10-04")
MASTER = os.path.join(RS, "output", "master_accessibility_status_ward_level.csv")
REALLOC = {"Tangaza": "ZOA", "Madagali": "FACT", "Mafa": "FACT", "Mobbar": "FACT", "Monguno": "FACT", "Mashi": "FACT",
           "Batagarawa": "FACT", "Jibia": "FACT", "Zuru": "FACT", "Gwandu": "FACT", "Birnin Kebbi": "FACT", "Suru": "FACT",
           "Argungu": "FACT", "Tsafe": "FACT", "Anka": "FACT"}


def ans(v):
    s = str(v).strip().lower() if v not in (None, "") else ""
    return {"yes": "Accessible", "y": "Accessible", "no": "Inaccessible", "n": "Inaccessible"}.get(s, "(blank)" if not s else f"?{v}")


def read(path, sheet):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    rows = list(wb[sheet].iter_rows(values_only=True))
    wb.close()
    h = [str(c).strip() if c is not None else f"col{i}" for i, c in enumerate(rows[0])]
    return [dict(zip(h, r)) for r in rows[1:] if any(v not in (None, "") for v in r)]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(MASTER, encoding="utf-8-sig", newline="") as f:
        master = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r for r in csv.DictReader(f)}
    out = []
    files = sorted(glob.glob(os.path.join(IN_DIR, "*.xlsx")))
    for path in files:
        fn = os.path.basename(path)
        props = openpyxl.load_workbook(path, read_only=True).properties
        for r in read(path, "Ward Accessibility"):
            if r["LGA"] not in REALLOC:
                continue
            m = master.get((r["State"], r["LGA"], r["Ward (GRID3)"]), {})
            out.append({"file": fn, "saved_by": props.lastModifiedBy, "saved_at": str(props.modified),
                        "state": r["State"], "lga": r["LGA"], "ward": r["Ward (GRID3)"], "new_partner": REALLOC[r["LGA"]],
                        "report_answer": ans(r.get("Accessible (Y/N)")), "reason": r.get("Reason category") or "",
                        "notes": r.get("Reason notes") or "", "date_reported": r.get("Date reported") or "",
                        "master_now": m.get("Accessible status", "NOT IN MASTER"), "master_source": m.get("Status source", ""),
                        "master_reported_by": m.get("Reporting partner(s)", "")})
    with open(os.path.join(OUT_DIR, "ward_answers_vs_master.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    print("== per file, reallocated LGAs only: report answer vs master now (wards)")
    for fn in sorted({o["file"] for o in out}):
        rows = [o for o in out if o["file"] == fn]
        print(f"\n{fn}  (saved by {rows[0]['saved_by']}, {rows[0]['saved_at'][:16]})")
        for lga in sorted({o["lga"] for o in rows}):
            rl = [o for o in rows if o["lga"] == lga]
            flips = Counter((o["master_now"], o["report_answer"]) for o in rl if o["master_now"] != o["report_answer"])
            print(f"   {lga:13s} wards {len(rl):2d} | answers {dict(Counter(o['report_answer'] for o in rl))} | "
                  f"master now {dict(Counter(o['master_now'] for o in rl))} | would change: {dict(flips) or 'none'}")

    print("\n== '(1)' versions vs originals (every differing ward and cluster answer)")
    for p1 in [p for p in files if "(1)" in os.path.basename(p)]:
        p0 = p1.replace(" (1)", "")
        for sheet, key in (("Ward Accessibility", ("LGA", "Ward (GRID3)")), ("Cluster Accessibility", ("Cluster ID",))):
            a = {tuple(r[k] for k in key): r for r in read(p0, sheet)}
            b = {tuple(r[k] for k in key): r for r in read(p1, sheet)}
            diffs = []
            for k in sorted(set(a) | set(b), key=str):
                ra, rb = a.get(k, {}), b.get(k, {})
                cols = [c for c in ("Accessible (Y/N)", "Reason category", "Reason notes") if str(ra.get(c) or "").strip() != str(rb.get(c) or "").strip()]
                if cols:
                    diffs.append((k, {c: (ra.get(c), rb.get(c)) for c in cols}))
            print(f"\n{os.path.basename(p1)} vs original, {sheet}: {len(diffs)} differing rows")
            for k, d in diffs[:40]:
                print("   ", k, d)


if __name__ == "__main__":
    main()
