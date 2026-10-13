"""#44: how much do Round 1 ESTIMATES move if the IDP accessible population comes from IOM DTM households instead of
WorldPop? (Coordinator, 13 Oct 2026). Read only; writes into the candidate's impact/ folder.

It reproduces the analysis team's own weighting (msna_analysis_main, Step 1 l.1096-1118):
  - analysistools::add_weights on the "population" sheet;
  - strata key = "IDP-"/"Non IDP-" + admin2 + " - " + admin2_name;
  - records whose stratum has no population row are left out.
So a household's weight is proportional to N_acc_h / n_h, and every domain estimate is
sum_h N_acc_h * mean_h / sum_h N_acc_h (NAs dropped per indicator, as srvyr does).

Run twice: the sheet as the analysis has it (WorldPop) and the candidate's DTM sheet. The only input that differs is
population_accessible on the IDP rows.

Also reports, per domain, the worst case for ANY yes/no indicator: the total-variation distance between the two sets of
stratum weights. No proportion in that domain can move by more than this, whatever the indicator.
"""
import collections, csv, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
CAND = os.path.join(WS, "1_sampling", "resampling", "output", "round1_candidate_v5_kebbi_dtm_2026-10-13")
SHEET = os.path.join(CAND, "analysis_population_sheet", "population_sheet_WP_check_and_DTM.csv")
EXTRACT = os.path.join(os.environ["TEMP"], "r1dtm", "v5_keys_fsl.csv")
OUT = os.path.join(CAND, "impact")


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


sheet = {r["strata"]: r for r in rd(SHEET)}
hh = rd(EXTRACT)
print("v5 households: %d | assessment: %s | pop_group: %s" % (len(hh), dict(collections.Counter(r["assessment"] for r in hh)),
                                                              dict(collections.Counter(r["pop_group"] for r in hh))))
for c in ("fsl_fcs_cat", "fsl_rcsi_cat", "fsl_hhs_cat_ipc", "fsl_hhs_cat", "fsl_lcsi_cat", "fsl_fc_phase"):
    print("  %s: %s" % (c, dict(sorted(collections.Counter(r[c] for r in hh).items()))))


def key(r):
    p = {"non_idp": "Non IDP", "idp": "IDP"}.get(r["pop_group"])
    return None if p is None else "%s-%s - %s" % (p, r["admin2"], r["admin2_name"])


rows = [dict(r, _k=key(r)) for r in hh]
inw = [r for r in rows if r["_k"] in sheet]
print("in the weighted analysis (stratum in the population sheet): %d | not: %d (by pop_group %s)"
      % (len(inw), len(rows) - len(inw), dict(collections.Counter(r["pop_group"] for r in rows if r["_k"] not in sheet))))
n_h = collections.Counter(r["_k"] for r in inw)
missing_keys = sorted(set(sheet) - set(n_h))
print("sheet strata with no household in v5:", missing_keys or "none")
IND = {
    "FCS poor (%)": lambda r: None if r["fsl_fcs_cat"] in ("", "NA") else float(r["fsl_fcs_cat"] == "Poor"),
    "FCS poor or borderline (%)": lambda r: None if r["fsl_fcs_cat"] in ("", "NA") else float(r["fsl_fcs_cat"] in ("Poor", "Borderline")),
    "rCSI high (%)": lambda r: None if r["fsl_rcsi_cat"] in ("", "NA") else float(r["fsl_rcsi_cat"] == "High"),
    "HHS moderate or severe (%)": lambda r: None if r["fsl_hhs_cat_ipc"] in ("", "NA") else float(r["fsl_hhs_cat_ipc"] in ("Moderate", "Severe", "Very Severe")),
    "LCSI crisis or emergency (%)": lambda r: None if r["fsl_lcsi_cat"] in ("", "NA") else float(r["fsl_lcsi_cat"] in ("Crisis", "Emergency")),
    "FC phase 3+ (%)": lambda r: None if r["fsl_fc_phase"] in ("", "NA") else float(r["fsl_fc_phase"] in ("Phase 3 FC", "Phase 4 FC", "Phase 5 FC")),
    "FCS score (mean)": lambda r: None if r["fsl_fcs_score"] in ("", "NA") else float(r["fsl_fcs_score"]),
    "rCSI score (mean)": lambda r: None if r["fsl_rcsi_score"] in ("", "NA") else float(r["fsl_rcsi_score"]),
}
for name, f in IND.items():
    vals = [f(r) for r in inw]
    print("  %-30s non-missing %d" % (name, sum(v is not None for v in vals)))
    if name.endswith("(%)") and sum(v for v in vals if v is not None) == 0:
        sys.exit("STOPPED: indicator %s is never true - check the category codes above" % name)


def est(domain_rows, col):
    num = den = 0.0
    for r in domain_rows:
        v = IND_VALS[id(r)][IND_NAMES.index(col)]
        if v is None:
            continue
        w = float(sheet[r["_k"]][col_pop]) / n_h[r["_k"]]
        num += w * v
        den += w
    return None if den == 0 else num / den


IND_NAMES = list(IND)
IND_VALS = {id(r): [IND[n](r) for n in IND_NAMES] for r in inw}
domains = collections.defaultdict(list)
for r in inw:
    domains[("MSNA-wide", "All Round 1", "IDP + Non-IDP")].append(r)
    domains[("State", r["admin1_name"], "IDP + Non-IDP")].append(r)
    domains[("State", r["admin1_name"], "IDP" if r["pop_group"] == "idp" else "Non-IDP")].append(r)
    domains[("LGA", "%s / %s" % (r["admin1_name"], r["admin2_name"]), "IDP + Non-IDP")].append(r)
    domains[("LGA", "%s / %s" % (r["admin1_name"], r["admin2_name"]), "IDP" if r["pop_group"] == "idp" else "Non-IDP")].append(r)


def tvd(domain_rows):
    ks = sorted({r["_k"] for r in domain_rows})
    a = {k: float(sheet[k]["population_accessible_WP_sheet"]) for k in ks}
    b = {k: float(sheet[k]["population_accessible_DTM"]) for k in ks}
    sa, sb = sum(a.values()), sum(b.values())
    return 0.5 * sum(abs(a[k] / sa - b[k] / sb) for k in ks) if sa and sb else 0.0


out = []
for dk, drows in sorted(domains.items()):
    level, unit, group = dk
    rec = {"Level": level, "Unit": unit, "Population group": group, "Households": len(drows),
           "Strata": len({r["_k"] for r in drows}),
           "Worst case for any yes/no indicator (pts)": round(100 * tvd(drows), 2)}
    for name in IND_NAMES:
        col_pop = "population_accessible_WP_sheet"
        globals()["col_pop"] = col_pop
        a = est(drows, name)
        globals()["col_pop"] = "population_accessible_DTM"
        b = est(drows, name)
        scale = 100 if name.endswith("(%)") else 1
        rec[name + " WP"] = None if a is None else round(scale * a, 2)
        rec[name + " DTM"] = None if b is None else round(scale * b, 2)
        rec[name + " change"] = None if (a is None or b is None) else round(scale * (b - a), 2)
    out.append(rec)

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "estimates_WP_vs_DTM_by_domain.csv"), "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys()), lineterminator="\r\n")
    w.writeheader()
    w.writerows(out)

summ = []
for level, group in [("MSNA-wide", "IDP + Non-IDP"), ("State", "IDP + Non-IDP"), ("State", "IDP"), ("State", "Non-IDP"),
                     ("LGA", "IDP + Non-IDP"), ("LGA", "IDP"), ("LGA", "Non-IDP")]:
    rs = [r for r in out if r["Level"] == level and r["Population group"] == group]
    line = {"Level": level, "Population group": group, "Domains": len(rs),
            "Worst case any yes/no indicator, max over domains (pts)": max(r["Worst case for any yes/no indicator (pts)"] for r in rs)}
    for name in IND_NAMES:
        ch = [abs(r[name + " change"]) for r in rs if r[name + " change"] is not None]
        line["max |change| " + name] = round(max(ch), 2) if ch else None
    summ.append(line)
with open(os.path.join(OUT, "estimates_change_summary.csv"), "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(summ[0].keys()), lineterminator="\r\n")
    w.writeheader()
    w.writerows(summ)
for s in summ:
    print(s)
print("\nState rows:")
for r in out:
    if r["Level"] == "State":
        print("  %-8s %-14s worst %5.2f | %s" % (r["Unit"], r["Population group"], r["Worst case for any yes/no indicator (pts)"],
              " | ".join("%s %s->%s" % (n.split(" (")[0], r[n + " WP"], r[n + " DTM"]) for n in IND_NAMES[:6])))
