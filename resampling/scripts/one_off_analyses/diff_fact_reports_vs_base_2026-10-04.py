# ==============================================================================
# 2026-10-04 READ-ONLY: which cells did FACT actually fill in each accessibility
# report it sent on 4 Oct? (Coordinator found that the "(1)" files are not newer
# versions of the same report but a second FACT person filling the same blank
# template for other LGAs - so "non-blank" is not "FACT's answer".)
#
# For each report FACT sent, compare against every candidate base it could have
# started from - the copy in the outgoing partner's package folder, the generated
# template, our returned copy of that partner's report and (CARE) CARE's own
# returned 28 Sep file - and keep the base with the same row set and the fewest
# differing cells. A row counts as FACT's answer only if FACT changed its
# Accessible / Reason category / Reason notes / Date reported vs that base.
# Writes resampling/output/staged_fact_accessibility_2026-10-04/edit_classification.csv
# ==============================================================================
import csv
import glob
import os
import sys
from collections import Counter

import openpyxl

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WS = os.path.dirname(os.path.dirname(RS))
IN_DIR = os.path.join(RS, "input", "partner_raw_comms", "04102026_bigresampling")
PKG = os.path.join(os.path.dirname(os.path.dirname(WS)), "3. External coordination", "NGA MSNA 2026 Package")
OUT = os.path.join(RS, "output", "staged_fact_accessibility_2026-10-04")
FIELDS = ("Accessible (Y/N)", "Reason category", "Reason notes", "Date reported")


def norm(v):
    if v is None:
        return ""
    s = str(v).strip()
    return "" if s.lower() in ("", "none", "nan") else s


def read(path):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    out = {}
    for sheet, key in (("Ward Accessibility", ("State", "LGA", "Ward (GRID3)")), ("Cluster Accessibility", ("Cluster ID",))):
        rows = list(wb[sheet].iter_rows(values_only=True))
        h = [str(c).strip() if c is not None else f"col{i}" for i, c in enumerate(rows[0])]
        for r in rows[1:]:
            d = dict(zip(h, r))
            if not any(v not in (None, "") for v in r):
                continue
            k = (sheet,) + tuple(norm(d.get(x)) for x in key)
            out[k] = d
    wb.close()
    return out


def org_of(fn):
    base = os.path.basename(fn).replace(" (1)", "")
    return base.split("_accessibility_report")[0]


def candidates(org):
    c = [os.path.join(PKG, org, f"{org}_accessibility_report.xlsx"),
         os.path.join(RS, "input", "accessibility_reports_generated", f"{org}_accessibility_report.xlsx"),
         os.path.join(RS, "input", "accessibility_reports_returned", f"{org}_accessibility_report.xlsx")]
    c += sorted(glob.glob(os.path.join(RS, "input", "partner_raw_comms", org, "*accessibility_report*.xlsx")))
    c += sorted(glob.glob(os.path.join(RS, "input", "accessibility_reports_returned", "_archive", f"{org}_accessibility_report*.xlsx")))
    return [p for p in c if os.path.isfile(p)]


def main():
    os.makedirs(OUT, exist_ok=True)
    out_rows = []
    for f in sorted(glob.glob(os.path.join(IN_DIR, "*.xlsx"))):
        fact = read(f)
        org = org_of(f)
        scored = []
        for b in candidates(org):
            try:
                base = read(b)
            except Exception as e:
                print(f"   (could not read {b}: {e})")
                continue
            same_rows = set(base) == set(fact)
            ndiff = sum(1 for k in fact if k in base for x in FIELDS if norm(fact[k].get(x)) != norm(base[k].get(x)))
            scored.append((not same_rows, ndiff, b, base, len(set(fact) ^ set(base))))
        scored.sort(key=lambda t: (t[0], t[1]))
        print(f"\n## {os.path.basename(f)}  (org {org}, {len(fact)} rows)")
        for miss, nd, b, _, nx in scored:
            print(f"   {'SAME ROWS' if not miss else f'rows differ by {nx}':18s} {nd:4d} differing cells  {os.path.relpath(b, os.path.dirname(WS))}")
        if not scored:
            continue
        miss, nd, bpath, base, _ = scored[0]
        edited = Counter()
        for k, d in fact.items():
            b = base.get(k)
            changed = [x for x in FIELDS if b is None or norm(d.get(x)) != norm(b.get(x))]
            lga = norm(d.get("LGA"))
            out_rows.append({"file": os.path.basename(f), "base": os.path.basename(bpath), "sheet": k[0], "key": " | ".join(k[1:]),
                             "lga": lga, "edited_by_fact": "yes" if changed else "no", "fields_changed": ";".join(changed),
                             "fact_accessible": norm(d.get("Accessible (Y/N)")), "base_accessible": norm(b.get("Accessible (Y/N)")) if b else "(no row)"})
            edited[(lga, k[0][:4], "edited" if changed else "untouched")] += 1
        print(f"   -> base used: {os.path.basename(bpath)}; per LGA (ward/clus): " +
              "; ".join(f"{l} {s}:{e}={n}" for (l, s, e), n in sorted(edited.items())))
    with open(os.path.join(OUT, "edit_classification.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        w.writerows(out_rows)
    print("\nwrote", os.path.join(OUT, "edit_classification.csv"))


if __name__ == "__main__":
    main()
