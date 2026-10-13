"""Cell-by-cell compare of the Coordinator's Round 1 candidate (build_round1_candidate_v5_kebbi_dtm_2026-10-13.py) with
Resampling's independent derivation (dtm_share_fix_sandbox_2026-10-12/round1/R1k/, scripts/dtm_r1k_derivation.py).
Two implementations from the same frozen inputs; every number must agree. Read only; writes one report into the
candidate's verification/ folder. Exit 1 on any mismatch."""
import csv, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
MINE = os.path.join(WS, "1_sampling", "resampling", "output", "round1_candidate_v5_kebbi_dtm_2026-10-13")
THEIRS = os.path.join(WS, "1_sampling", "resampling", "output", "dtm_share_fix_sandbox_2026-10-12", "round1", "R1k")
lines, bad = [], []


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def num(x):
    return None if x is None or str(x).strip() in ("", "None") else float(x)


def close(a, b, tol):
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) <= tol * max(1.0, abs(a), abs(b))


def cmp(what, key, col, a, b, tol=1e-9):
    if isinstance(a, str) or isinstance(b, str):
        ok = str(a) == str(b)
    else:
        ok = close(a, b, tol)
    if not ok:
        bad.append("%s %s %s: mine %r vs theirs %r" % (what, key, col, a, b))
    return ok


for mode, mtag in (("wp", "tables_WP_kebbi"), ("dtm", "tables_DTM_kebbi")):
    # strata
    mfp = {r["strata_id"]: r for r in rd(os.path.join(MINE, mtag, "strata_full_precision.csv"))}
    mtab = {r["Stratum ID"]: r for r in rd(os.path.join(MINE, mtag, "strata.csv"))}
    th = {r["Stratum ID"]: r for r in rd(os.path.join(THEIRS, "R1k_%s_strata.csv" % mode))}
    if set(mfp) != set(th):
        bad.append("%s strata sets differ: only mine %s, only theirs %s" % (mode, sorted(set(mfp) - set(th)), sorted(set(th) - set(mfp))))
    n = 0
    for sid in sorted(set(mfp) & set(th)):
        m, t, mt = mfp[sid], th[sid], mtab[sid]
        cmp(mode + " stratum", sid, "Category", mt["Category"], t["Category"])
        cmp(mode + " stratum", sid, "Interviews", int(m["n"]), int(t["Interviews"]))
        cmp(mode + " stratum", sid, "N_hh", num(m["N_hh"]), num(t["Households (all)"]))
        cmp(mode + " stratum", sid, "N_acc", num(m["N_acc"]), num(t["Accessible households"]))
        if num(t["MoE % (full precision)"]) is not None:
            cmp(mode + " stratum", sid, "MoE full", num(m["moe"]), num(t["MoE % (full precision)"]))
        cmp(mode + " stratum", sid, "MoE display", num(mt["Margin of error (%)"]), num(t["MoE % (display)"]), 0)
        n += 1
    lines.append("%s strata: %d compared (category, interviews, N_hh, N_acc, MoE full + display)" % (mode, n))
    # LGA and State
    for lvl, mf, tf, keys in (("LGA", "lga.csv", "R1k_%s_lga.csv" % mode, ("State", "LGA")),
                              ("State", "state.csv", "R1k_%s_state.csv" % mode, ("State", "Population group"))):
        mrows = {tuple(r[k] for k in keys): r for r in rd(os.path.join(MINE, mtag, mf))}
        magg = {(r["State"], r["unit"]): r for r in rd(os.path.join(MINE, mtag, "aggregates_full_precision.csv")) if r["level"] == lvl}
        trows = {tuple(r[k] for k in keys): r for r in rd(os.path.join(THEIRS, tf))}
        if set(mrows) != set(trows):
            bad.append("%s %s sets differ: only mine %s, only theirs %s" % (mode, lvl, sorted(set(mrows) - set(trows)), sorted(set(trows) - set(mrows))))
        for k in sorted(set(mrows) & set(trows)):
            m, t, ma = mrows[k], trows[k], magg[k]
            cmp(mode + " " + lvl, k, "Category", m["Category"], t["Category"])
            cmp(mode + " " + lvl, k, "Interviews in the estimate", int(m["Interviews in the estimate"]), int(t["Interviews in the estimate"]))
            cmp(mode + " " + lvl, k, "MoE full", num(ma["moe"]), num(t["MoE % (full precision)"]))
            cmp(mode + " " + lvl, k, "MoE display", num(m["Margin of error (%)"]), num(t["MoE % (display)"]), 0)
            for c in ("Households (all)", "Households in accessible areas", "Households represented by the estimate"):
                cmp(mode + " " + lvl, k, c, num(m[c]), float(round(num(t[c]))), 0)
        lines.append("%s %s: %d rows compared (category, interviews, MoE full + display, 3 household totals)" % (mode, lvl, len(set(mrows) & set(trows))))

# population sheet (DTM version)
mp = {r["strata"]: r for r in rd(os.path.join(MINE, "analysis_population_sheet", "population_sheet_WP_check_and_DTM.csv"))}
tp = {r["strata"]: r for r in rd(os.path.join(THEIRS, "R1k_population_sheet_dtm.csv"))}
if set(mp) != set(tp):
    bad.append("population sheet keys differ")
for k in sorted(set(mp) & set(tp)):
    cmp("pop sheet", k, "population", num(mp[k]["population"]), num(tp[k]["population"]), 0)
    cmp("pop sheet", k, "WP sheet value", num(mp[k]["population_accessible_WP_sheet"]), num(tp[k]["population_accessible_worldpop_sheet"]), 0)
    cmp("pop sheet", k, "DTM full", num(mp[k]["population_accessible_DTM_full"]), num(tp[k]["population_accessible"]))
    cmp("pop sheet", k, "DTM 1dp", num(mp[k]["population_accessible_DTM"]), num(tp[k]["population_accessible_1dp"]), 0)
lines.append("population sheet: %d rows compared (population, WP value, DTM full precision, DTM 1 dp)" % len(set(mp) & set(tp)))
# rescale factors (weighted strata)
mf = {r["strata_id"]: r for r in rd(os.path.join(MINE, "weights", "rescale_factors_by_stratum.csv"))}
tf = {r["strata_id"]: r for r in rd(os.path.join(THEIRS, "R1k_idp_rescale.csv"))}
nf = 0
for sid, r in mf.items():
    if sid.startswith("idp_"):
        nf += 1
        t = tf.get(sid)
        if t is None:
            bad.append("rescale: %s missing from theirs" % sid); continue
        # the design weights are calibrated to the strata table's 1-dp N_acc, so the factor is the ratio of the 1-dp values;
        # rebuild that ratio from Resampling's full-precision N_acc columns
        cmp("rescale", sid, "factor (1-dp N_acc ratio)", num(r["factor"]),
            round(num(t["N_acc_dtm"]), 1) / round(num(t["N_acc_worldpop"]), 1))
        cmp("rescale", sid, "N_acc_DTM 1dp", num(r["N_acc_DTM"]), round(num(t["N_acc_dtm"]), 1), 0)
lines.append("IDP rescale factors: %d weighted strata compared (ratio of the 1-dp N_acc the design weights are calibrated to)" % nf)

os.makedirs(os.path.join(MINE, "verification"), exist_ok=True)
lines.append("MISMATCHES: %d" % len(bad))
lines += ["  " + b for b in bad[:200]]
with open(os.path.join(MINE, "verification", "compare_vs_resampling_R1k.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(1 if bad else 0)
