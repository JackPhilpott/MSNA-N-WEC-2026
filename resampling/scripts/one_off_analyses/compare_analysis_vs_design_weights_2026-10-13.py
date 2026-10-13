"""#13 context for Jack (13 Oct 2026, Coordinator): the analysis team's Step 1 weights (analysistools::add_weights =
stratum accessible households / stratum interviews, i.e. self-weighting within each stratum) versus the Round 1 DESIGN
weights (1 / (first-stage x second-stage probability), capped at 4x the stratum median, calibrated to the same stratum
accessible households). Same households, same strata totals; only the within-stratum weighting differs.
Both on the WorldPop accessible households (the #44 choice moves both the same way). Read only; writes one aggregated
CSV (no household rows) into the candidate's impact/ folder. Needs the local extract made by
extract_v5_keys_and_fsl_2026-10-13.py (%TEMP%\\r1dtm\\v5_keys_fsl.csv)."""
import collections, csv, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
OUTD = os.path.join(WS, "1_sampling", "resampling", "output")
SHEET = os.path.join(OUTD, "round1_candidate_v5_kebbi_dtm_2026-10-13", "analysis_population_sheet", "population_sheet_WP_check_and_DTM.csv")
DESIGN = os.path.join(OUTD, "round1_candidate_aligned_to_DO_clean_2026-10-04", "weights", "ROUND1_WEIGHTS_FINAL_2026-10-02.csv")
EXTRACT = os.path.join(os.environ["TEMP"], "r1dtm", "v5_keys_fsl.csv")
OUT = os.path.join(OUTD, "round1_candidate_v5_kebbi_dtm_2026-10-13", "impact", "analysis_weights_vs_design_weights_WP.csv")


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


sheet = {r["strata"]: float(r["population_accessible_WP_sheet"]) for r in rd(SHEET)}
dw = {r["submission_uuid"]: (float(r["weight"]), r["strata_id"]) for r in rd(DESIGN)}
hh = rd(EXTRACT)


def key(r):
    p = {"non_idp": "Non IDP", "idp": "IDP"}.get(r["pop_group"])
    return None if p is None else "%s-%s - %s" % (p, r["admin2"], r["admin2_name"])


inw = [r for r in hh if key(r) in sheet]
n_h = collections.Counter(key(r) for r in inw)
if any(r["uuid"] not in dw or dw[r["uuid"]][1] != r["strata_id"] for r in inw):
    sys.exit("STOPPED: a weighted household has no design weight, or a different stratum")
IND = {
    "FCS poor or borderline (%)": lambda r: None if r["fsl_fcs_cat"] == "" else float(r["fsl_fcs_cat"] in ("Poor", "Borderline")),
    "FC phase 3+ (%)": lambda r: None if r["fsl_fc_phase"] == "" else float(r["fsl_fc_phase"] in ("Phase 3 FC", "Phase 4 FC", "Phase 5 FC")),
    "HHS moderate or severe (%)": lambda r: None if r["fsl_hhs_cat_ipc"] == "" else float(r["fsl_hhs_cat_ipc"] in ("Moderate", "Severe", "Very Severe")),
    "LCSI crisis or emergency (%)": lambda r: None if r["fsl_lcsi_cat"] == "" else float(r["fsl_lcsi_cat"] in ("Crisis", "Emergency")),
    "rCSI high (%)": lambda r: None if r["fsl_rcsi_cat"] == "" else float(r["fsl_rcsi_cat"] == "High"),
}


def est(rows, f, wf):
    num = den = 0.0
    for r in rows:
        v = f(r)
        if v is not None:
            w = wf(r)
            num += w * v
            den += w
    return 100 * num / den if den else None


aw = lambda r: sheet[key(r)] / n_h[key(r)]
dwf = lambda r: dw[r["uuid"]][0]
dom = collections.defaultdict(list)
for r in inw:
    g = {"idp": "IDP", "non_idp": "Non-IDP"}[r["pop_group"]]
    dom[(r["admin1_name"], "IDP + Non-IDP")].append(r)
    dom[(r["admin1_name"], g)].append(r)
rows, worst = [], collections.defaultdict(lambda: (0.0, ""))
for (st, g), rs in sorted(dom.items()):
    rec = {"State": st, "Population group": g, "Households": len(rs)}
    for n, f in IND.items():
        a, d = est(rs, f, aw), est(rs, f, dwf)
        rec[n + " analysis weights"], rec[n + " design weights"], rec[n + " difference"] = round(a, 2), round(d, 2), round(d - a, 2)
        if abs(d - a) > worst[g][0]:
            worst[g] = (abs(d - a), "%s %s: %.1f vs %.1f" % (st, n, a, d))
    rows.append(rec)
with open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\r\n")
    w.writeheader()
    w.writerows(rows)
print("households %d (all with a design weight in the same stratum)" % len(inw))
for g, (v, where) in sorted(worst.items()):
    print("largest difference, %-13s %.2f pts (%s)" % (g, v, where))
print("written", OUT)
