"""Round 1 CANDIDATE on the final-dataset basis, with Kebbi reinstated and the #44 fix - 13 Oct 2026 (Coordinator).

STAGED for Jack's decision. Writes ONLY to resampling/output/round1_candidate_v5_kebbi_dtm_2026-10-13/.
Nothing live, partner-facing or analysis-facing is touched; the analysis team's workbook is only read.

Why:
  1. Kebbi is back in Round 1 (Jack, 12 Oct). The final cleaned dataset (..._08102026_v5) has 23,206 MSNA households:
     the 4 Oct DO-aligned candidate's 21,428 in coverage plus Kebbi's 1,778.
  2. #44: an IDP stratum's accessible share came from WorldPop people, not IOM DTM households
     (analysis_accessible_area_layer.R l.200). Resampling's round1/R1_idp_share_worldpop_vs_dtm_by_lga.csv gives each
     Round 1 IDP stratum's share under both, by the Round 1 rule:
       - current basis = the 2 Oct layer;
       - strata that lost access after collection = the larger of the 8 Sep / 26 Sep layers;
       - never accessible = 100%.
     Its WorldPop column reproduces Round 1 for 131/131 strata.

Three modes, one code path (the 5 Oct IPC/CH builder's own formulas, copied unchanged):
  V2    WorldPop, Kebbi out. Must reproduce the shared IPC/CH tables (_csv_for_verification) BYTE FOR BYTE.
  WPK   WorldPop, Kebbi in. Every non-Kebbi row must equal V2; Kebbi's strata must reproduce the 4 Oct all-states table.
  DTMK  DTM, Kebbi in. The candidate: only IDP accessible households, and what follows from them, may change.

Also built:
  - the analysis team's "population" sheet (their weights input): a WorldPop check and a DTM version;
  - the design weights, rescaled per IDP stratum. The calibration (cap at 4x median, then sum to N_acc) is
    scale-invariant, so a new N_acc rescales a stratum's weights exactly.
"""
import collections
import csv
import datetime
import hashlib
import io
import math
import os
import sys

import openpyxl
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
S1 = os.path.join(WS, "1_sampling")
CAND = os.path.join(S1, "resampling", "output", "round1_candidate_aligned_to_DO_clean_2026-10-04")
ALL_STRATA = os.path.join(CAND, "representativity", "round1_strata.csv")
ALL_LGA = os.path.join(CAND, "representativity", "round1_lga.csv")
ALL_STATE = os.path.join(CAND, "representativity", "round1_state.csv")
NENW_STRATA = os.path.join(CAND, "package_staging", "03_representativity", "R1_representativity_strata_NE_NW.csv")
W_FINAL = os.path.join(CAND, "weights", "ROUND1_WEIGHTS_FINAL_2026-10-02.csv")
W_BYS = os.path.join(CAND, "weights", "ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv")
IPC = os.path.join(WS, "2_monitoring", "reports", "round1_ipc_ch_representativity_2026-10-04")
FP_CSV = os.path.join(IPC, "_build_intermediate", "full_precision_strata.csv")
V1_VERIFY_DIR = os.path.join(IPC, "_csv_for_verification")
FRAME_CSV = os.path.join(S1, "output", "data", "data_collection", "_archive", "2026-10-04_daily_update_2026-10-04_222328",
                         "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv")
DTM_CSV = os.path.join(S1, "resampling", "output", "dtm_share_fix_sandbox_2026-10-12", "round1", "R1_idp_share_worldpop_vs_dtm_by_lga.csv")
POP_SHEET_XLSX = os.path.normpath(os.path.join(WS, "..", "..", "6. Outputs", "analysis", "msna_analysis_main", "resources",
                                               "R1_cluster_table_NE_NW.xlsx"))
OUT = os.environ.get("R1K_OUT") or os.path.join(S1, "resampling", "output", "round1_candidate_v5_kebbi_dtm_2026-10-13")
EXPECT_MD5 = {ALL_STRATA: "0c06fcde", ALL_LGA: "44ed2b67", ALL_STATE: "64deccdd", FP_CSV: "cf6956f6", DTM_CSV: "44717a65",
              FRAME_CSV: "1212854d", POP_SHEET_XLSX: "bd5770bb"}

V2_STATES = {"Adamawa", "Borno", "Yobe", "Kaduna", "Katsina", "Sokoto", "Zamfara"}
K_STATES = V2_STATES | {"Kebbi"}
V2_HH, KEBBI_HH = 21428, 1778

# ---- constants and helpers copied unchanged from build_round1_ipc_ch_workbook_v2_2026-10-05.py ----
Z = 1.6448536269514722
REPR, INDIC = "Representative", "Indicative - meets reporting threshold"
MSNA_LIGHT = "not_assessed"
EXCL_TEXT = {
    "accessibility_loss_below_population_threshold": "Excluded from the design: accessible share of the population below the design threshold",
    "insecurity_related_inaccessibility": "Excluded from the design: inaccessible because of insecurity",
    "idp_population_no_longer_present_partner_reported": "Excluded from the design: IDP population no longer present (partner report)",
    # new with Kebbi (Gwandu IDP, 21 households; excluded on Jack's word 23 Sep): not needed by the NE+NW tables
    "certainty_stratum_below_moe_threshold": "Excluded from the design: too few households for a sample that meets the precision threshold",
}
log_lines = []


def log(msg):
    print(msg)
    log_lines.append(msg)


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def var_h(n, N):
    if N <= n:
        return 0.0
    return 0.5 * (1 - 0.5) / (n * (N - 1) / (N - n))


def moe_stratum(n, N):
    if n <= 0 or N <= 0:
        return None
    return 100 * Z * math.sqrt(var_h(n, N))


def aggregate(strata, included):
    inc = [s for s in strata if included(s)]
    hh_all = sum(s["N"] for s in strata)
    acc_all = sum(s["Nacc"] for s in strata)
    rep = sum(s["Nacc"] for s in inc)
    moe = None
    if inc:
        moe = 100 * Z * math.sqrt(sum((s["Nacc"] / rep) ** 2 * var_h(s["n"], s["Nacc"]) for s in inc))
    return {"inc": inc, "n_inc": sum(s["n"] for s in inc), "hh_all": hh_all, "acc_all": acc_all, "rep": rep, "moe": moe}


def fnum(x):
    return float(x) if str(x).strip() != "" else None


def moe_display(m):
    if m is None:
        return None
    d = 2
    while m > 10 and round(m, d) <= 10 and d < 8:
        d += 1
    return round(m, d)


def edge_note(m):
    return ("Margin of error %s%% before rounding: just above the 10%% threshold, so (b)" % ("%.4f" % m)) if (m is not None and m > 10 and round(m, 2) <= 10) else ""


def csv_text(rows_):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=list(rows_[0].keys()), lineterminator="\r\n")
    w.writeheader()
    w.writerows(rows_)
    return buf.getvalue()
# ---- end of copied helpers ----


def stop(msg):
    log("STOPPED: " + msg)
    sys.exit(1)


# =====================================================================================================================
# 1. Inputs
log("Round 1 candidate (v5 basis, Kebbi in, #44 DTM fix) - %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
for p, exp in EXPECT_MD5.items():
    h = md5(p)
    log("input %s md5 %s" % (os.path.relpath(p, os.path.dirname(os.path.dirname(WS))), h))
    if not h.startswith(exp):
        stop("%s md5 %s, expected %s" % (p, h, exp))
for p in (NENW_STRATA, W_FINAL, W_BYS):
    log("input %s md5 %s" % (os.path.relpath(p, WS), md5(p)))

raw_all = rd(ALL_STRATA)
fp = {r["strata_id"]: r for r in rd(FP_CSV)}
assert all(float(r["Z"]) == Z for r in fp.values()), "captured Z differs"


def make_stratum(r):
    s = {"row": r, "state": r["State"], "lga": r["LGA"], "pcode": r["adm2_pcode"], "pop": r["Pop type"], "sid": r["strata_id"],
         "method": r["Sampling method"], "covered": r["Covered in design"], "basis": r["Accessible-population basis"],
         "N": float(r["Households (N_hh)"]), "pct_acc": fnum(r["% population accessible"]), "Nacc": float(r["Accessible households"]),
         "n": int(float(r["Achieved (Round 1)"])), "moe_csv": fnum(r["MoE Round 1 (deff=1) %"]),
         "label": r["Round 1 label"], "reason": r["Round 1 reason"]}
    f = fp[s["sid"]]
    N_full, Nacc_full = float(f["_N_hh"]), float(f["_N_acc"])
    assert round(N_full) == round(s["N"]) and round(Nacc_full, 1) == s["Nacc"], (s["sid"], N_full, s["N"], Nacc_full, s["Nacc"])
    assert int(f["Achieved (Round 1)"]) == s["n"] and f["Round 1 label"] == s["label"], s["sid"]
    s["N"], s["Nacc"] = N_full, Nacc_full
    s["var_captured"] = None if f["_var"] in ("", "None") else float(f["_var"])
    return s


# Coverage: V2 = the shared NE + NW (Kebbi out) table, in its own row order; K = V2 + Kebbi.
nenw = rd(NENW_STRATA)
by_sid_all = {r["strata_id"]: r for r in raw_all}
for r in nenw:   # the package's NE+NW table must be the all-states table's rows, unchanged
    a = by_sid_all[r["strata_id"]]
    if {k: a[k] for k in r} != r:
        stop("NE+NW package row differs from the all-states table: %s" % r["strata_id"])
if {r["State"] for r in nenw} != V2_STATES or {r["strata_id"] for r in nenw} != {r["strata_id"] for r in raw_all if r["State"] in V2_STATES}:
    stop("NE+NW package coverage is not exactly the 7 V2 states of the all-states table")
kebbi_rows = [r for r in raw_all if r["State"] == "Kebbi"]
log("coverage: V2 %d strata (NE+NW, Kebbi out) | Kebbi %d strata | K %d strata" % (len(nenw), len(kebbi_rows), len(nenw) + len(kebbi_rows)))

# DTM shares (Resampling, A)
dtm_rows = rd(DTM_CSV)
dtm = {r["r1_strata_id"]: r for r in dtm_rows if r["r1_strata_id"]}
log("DTM share rows: %d LGAs, %d with a Round 1 IDP stratum; worldpop-reproduces flags: %s"
    % (len(dtm_rows), len(dtm), dict(collections.Counter(r["r1_check_worldpop_reproduces"] for r in dtm.values()))))

frame = rd(FRAME_CSV)
REGION = {"NE": "North-East", "NW": "North-West", "NC": "North-Central"}
state_region = {f["adm1_name"]: REGION.get(f["region"], f["region"]) for f in frame}


# =====================================================================================================================
# 2. One code path for every mode
def stratum_category(s):
    if s["label"] == REPR or s["label"] == INDIC:
        if s["method"] == "MSNA Light" and MSNA_LIGHT == "not_assessed":
            return "d", "MSNA Light: collected in the accessible area only; not part of the weighted Round 1 analysis"
        note = "" if s["method"] != "MSNA Light" else " (MSNA Light: not part of the weighted Round 1 analysis)"
        return ("a", "Margin of error 10% or less" + note) if s["label"] == REPR else ("b", "Margin of error above 10%, at least 20 interviews" + note)
    if s["reason"] == "Dropped - <20 samples achieved":
        return "c", "Fewer than 20 interviews (%d)" % s["n"]
    if s["reason"] == "Dropped - no accessible population":
        return "d", "No accessible population at the end of Round 1"
    if s["reason"].startswith("Dropped - LGA/strata excluded"):
        code = s["reason"].split("(", 1)[1].rstrip(")")
        return "d", EXCL_TEXT[code]
    raise ValueError("unmapped stratum %s: %s / %s" % (s["sid"], s["label"], s["reason"]))


def build(mode):
    rows = nenw if mode == "V2" else nenw + kebbi_rows
    strata = [make_stratum(r) for r in rows]
    fails, relabels, dtm_applied = [], [], []
    if mode == "DTMK":
        for s in strata:
            if s["pop"] != "IDP":
                continue
            d = dtm.get(s["sid"])
            if d is None:
                if s["Nacc"] > 0 or s["n"] > 0:
                    fails.append("IDP stratum with accessible households or interviews but no DTM share: %s" % s["sid"])
                continue
            wp = float(d["r1_share_as_used_worldpop_pct"])
            if abs(s["N"] * wp / 100 - s["Nacc"]) > 1e-6 * max(1.0, s["Nacc"]):
                fails.append("WorldPop share does not reproduce N_acc: %s %r vs %r" % (s["sid"], s["N"] * wp / 100, s["Nacc"]))
            share = float(d["r1_share_as_used_dtm_pct"])
            s["Nacc_wp"], s["pct_wp"] = s["Nacc"], s["pct_acc"]
            s["Nacc"], s["pct_acc"] = s["N"] * share / 100, round(share, 1)
            s["share_dtm_full"] = share
            s["basis"] = s["basis"] + " (IDP: IOM DTM households)"
            dtm_applied.append(s["sid"])
    for s in strata:
        excluded = s["reason"].startswith("Dropped - LGA/strata excluded")
        m = None if excluded else moe_stratum(s["n"], s["Nacc"])
        s["moe"] = m
        if mode != "DTMK" and s["var_captured"] is not None and (s["n"] <= 0 or var_h(s["n"], s["Nacc"]) != s["var_captured"]):
            fails.append("stratum variance %s" % s["sid"])
        if excluded:
            lab, why = "Dropped", s["reason"]
        elif s["Nacc"] <= 0:
            lab, why = "Dropped", "Dropped - no accessible population"
        elif m is not None and m <= 10:
            lab, why = REPR, "Representative (MoE <= 10%)"
        elif s["n"] >= 20:
            lab, why = INDIC, "Indicative - meets reporting threshold (>=20 samples achieved)"
        else:
            lab, why = "Dropped", "Dropped - <20 samples achieved"
        if (lab, why) != (s["label"], s["reason"]):
            if mode == "DTMK":
                relabels.append((s["sid"], s["state"], s["lga"], s["pop"], s["label"], lab))
                s["label_wp"], s["label"], s["reason"] = s["label"], lab, why
            else:
                fails.append("stratum label %s: recomputed %s / %s vs %s / %s" % (s["sid"], lab, why, s["label"], s["reason"]))
        if mode != "DTMK" and ((s["moe_csv"] is None) != (m is None) or (m is not None and round(m, 2) != s["moe_csv"])):
            fails.append("stratum MoE %s: recomputed %s vs %s" % (s["sid"], m, s["moe_csv"]))
    if fails:
        for f in fails[:60]:
            log("[%s] SELF-CHECK FAIL: %s" % (mode, f))
        stop("%s: %d self-check failures" % (mode, len(fails)))

    by_lga = collections.defaultdict(list)
    for s in strata:
        by_lga[(s["state"], s["lga"])].append(s)
    scope_pop = {"IDP + Non-IDP": None, "IDP only": "IDP", "Non-IDP only": "Non-IDP"}
    by_state = collections.defaultdict(list)
    for s in strata:
        for sc, pop in scope_pop.items():
            if pop is None or s["pop"] == pop:
                by_state[(s["state"], sc)].append(s)

    msna_states = sorted({f["adm1_name"] for f in frame if f["coverage_status"] == "covered"})
    r1_states = sorted({s["state"] for s in strata})
    outside_states = [st for st in msna_states if st not in r1_states]
    frame_only_states = sorted({f["adm1_name"] for f in frame} - set(msna_states))
    kad = [f for f in frame if f["adm1_name"] == "Kaduna"]
    kad_cov = sorted({f["adm2_name"] for f in kad if f["coverage_status"] == "covered"})

    for s in strata:
        s["cat"], s["why"] = stratum_category(s)
    inc_ipc = lambda s: s["cat"] in ("a", "b")
    pop_label = lambda ss: " + ".join(sorted({x["pop"] for x in ss}, key=lambda p: 0 if p == "IDP" else 1)) or "none"

    def unit_category(a, ss):
        if a["moe"] is not None:
            return "a" if a["moe"] <= 10 else "b"
        return "c" if any(x["cat"] == "c" for x in ss) else "d"

    def not_included(ss):
        return "; ".join("%s: %s" % (x["pop"], x["why"]) for x in ss if not inc_ipc(x))

    lga_out = []
    for (st, lg), ss in sorted(by_lga.items()):
        a = aggregate(ss, inc_ipc)
        lga_out.append({"State": st, "LGA": lg, "LGA pcode": ss[0]["pcode"], "Category": unit_category(a, ss),
                        "Population groups in the estimate": pop_label(a["inc"]) if a["inc"] else "none",
                        "Interviews in the estimate": a["n_inc"], "Margin of error (%)": moe_display(a["moe"]),
                        "Households (all)": round(a["hh_all"]), "Households in accessible areas": round(a["acc_all"]),
                        "Households represented by the estimate": round(a["rep"]),
                        "% of households represented": round(100 * a["rep"] / a["hh_all"], 1) if a["hh_all"] else None,
                        "Not included in the estimate": not_included(ss),
                        "Note": "; ".join(x for x in ["Only Jema'a and Zaria are in the MSNA design in Kaduna; no Kaduna state figure" if st == "Kaduna" else "", edge_note(a["moe"])] if x),
                        "_moe": a["moe"]})
    state_out = []
    for st in r1_states:
        if st == "Kaduna":
            continue
        n_lgas = len({s["lga"] for s in strata if s["state"] == st})
        for sc in scope_pop:
            ss = by_state[(st, sc)]
            a = aggregate(ss, inc_ipc)
            state_out.append({"State": st, "Population group": sc.replace(" only", ""), "Category": unit_category(a, ss),
                              "LGAs": n_lgas, "Strata": len(ss), "Strata in the estimate": len(a["inc"]),
                              "Interviews in the estimate": a["n_inc"], "Margin of error (%)": moe_display(a["moe"]),
                              "Households (all)": round(a["hh_all"]), "Households in accessible areas": round(a["acc_all"]),
                              "Households represented by the estimate": round(a["rep"]),
                              "% of households represented": round(100 * a["rep"] / a["hh_all"], 1) if a["hh_all"] else None,
                              "Not included in the estimate": "; ".join("%s %s: %s" % (x["lga"], x["pop"], x["why"]) for x in ss if not inc_ipc(x)),
                              "_moe": a["moe"]})
    strata_out = [{"State": s["state"], "LGA": s["lga"], "LGA pcode": s["pcode"], "Population group": s["pop"], "Category": s["cat"],
                   "Interviews": s["n"], "Margin of error (%)": moe_display(s["moe"]) if inc_ipc(s) else None,
                   "Households (all)": round(s["N"]), "% of households in accessible areas": s["pct_acc"],
                   "Households in accessible areas": round(s["Nacc"], 1), "Accessible-population basis": s["basis"],
                   "Reason": "; ".join(x for x in [s["why"], edge_note(s["moe"]) if inc_ipc(s) else ""] if x), "Stratum ID": s["sid"],
                   "_moe": s["moe"]}
                  for s in sorted(strata, key=lambda s: (s["state"], s["lga"], s["pop"]))]
    na = collections.OrderedDict()
    for f in sorted(frame, key=lambda f: (f["adm1_name"], f["adm2_name"])):
        st, lg = f["adm1_name"], f["adm2_name"]
        if st in outside_states or st in frame_only_states or (st == "Kaduna" and lg not in kad_cov):
            d = na.setdefault((st, lg), {"State": st, "LGA": lg, "LGA pcode": f["adm2_pcode"], "Region": f["region"], "statuses": set(), "pops": set(), "hh": 0.0})
            d["statuses"].add(f["coverage_status"]); d["pops"].add("IDP" if f["pop_type"] == "idp" else "Non-IDP"); d["hh"] += float(f["N_hh"])
    na_out = []
    for (st, lg), d in na.items():
        in_design = bool(d["statuses"] & {"covered", "excluded"})
        if st == "Kaduna":
            why = "Not in the MSNA sampling design (Kaduna: only Jema'a and Zaria are in the design)"
        elif not in_design:
            why = "Not in the MSNA sampling design"
        else:
            why = "In the MSNA design; %s (%s) is not part of the Round 1 analysis coverage" % (st, state_region[st])
        na_out.append({"State": st, "LGA": lg, "LGA pcode": d["LGA pcode"], "Category": "d", "Population groups in the frame": " + ".join(sorted(d["pops"])),
                       "Households (design frame)": round(d["hh"]), "Reason": why})
    odd = [r for r in lga_out + state_out + strata_out if r["Margin of error (%)"] is not None and (r["Margin of error (%)"] <= 10) != (r["Category"] == "a")]
    assert not odd, "a displayed MoE disagrees with its category"
    for r in strata_out:
        if r["Category"] in ("a", "b"):
            assert r["Interviews"] >= 20
    n_all = sum(s["n"] for s in strata)
    expect_n = V2_HH if mode == "V2" else V2_HH + KEBBI_HH
    if n_all != expect_n:
        stop("%s: interviews in coverage %d != %d" % (mode, n_all, expect_n))
    log("[%s] %d strata, %d LGAs, %d State rows | interviews %d, in estimates %d | strata %s | LGAs %s"
        % (mode, len(strata), len(lga_out), len(state_out), n_all, sum(s["n"] for s in strata if inc_ipc(s)),
           dict(sorted(collections.Counter(s["cat"] for s in strata).items())), dict(sorted(collections.Counter(r["Category"] for r in lga_out).items()))))
    return {"strata": strata, "strata_out": strata_out, "lga_out": lga_out, "state_out": state_out, "na_out": na_out,
            "relabels": relabels, "dtm_applied": dtm_applied}


def public(rows_):
    return [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows_]


# =====================================================================================================================
# 3. V2 must reproduce the shared IPC/CH tables byte for byte
V2 = build("V2")
for fname, rows_ in [("strata.csv", V2["strata_out"]), ("lga.csv", V2["lga_out"]), ("state.csv", V2["state_out"]), ("not_assessed.csv", V2["na_out"])]:
    with open(os.path.join(V1_VERIFY_DIR, fname), encoding="utf-8", newline="") as f:
        if csv_text(public(rows_)) != f.read():
            stop("V2 %s differs from the shared IPC/CH table" % fname)
log("SELF-CHECK PASS [V2]: the shared IPC/CH strata, LGA, State and Not assessed tables reproduced byte for byte.")

# =====================================================================================================================
# 4. WPK: Kebbi only adds rows
WPK = build("WPK")
def keyed(rows_, keys):
    return {tuple(r[k] for k in keys): r for r in public(rows_)}
for name, keys in [("strata_out", ("Stratum ID",)), ("lga_out", ("State", "LGA")), ("state_out", ("State", "Population group"))]:
    a, b = keyed(V2[name], keys), keyed(WPK[name], keys)
    for k, r in a.items():
        if b.get(k) != r:
            stop("WPK changes a non-Kebbi %s row: %s" % (name, k))
    extra = [k for k in b if k not in a]
    if any((b[k]["State"] != "Kebbi") for k in extra):
        stop("WPK adds a non-Kebbi %s row" % name)
na_v2, na_k = public(V2["na_out"]), public(WPK["na_out"])
if [r for r in na_v2 if r["State"] != "Kebbi"] != na_k or not any(r["State"] == "Kebbi" for r in na_v2):
    stop("WPK Not assessed table is not V2 minus Kebbi")
log("SELF-CHECK PASS [WPK]: every non-Kebbi row equals V2; Kebbi adds %d strata, %d LGA rows, %d State rows; Kebbi leaves Not assessed (%d rows)."
    % (sum(1 for r in WPK["strata_out"] if r["State"] == "Kebbi"), sum(1 for r in WPK["lga_out"] if r["State"] == "Kebbi"),
       sum(1 for r in WPK["state_out"] if r["State"] == "Kebbi"), sum(1 for r in na_v2 if r["State"] == "Kebbi")))
# Kebbi's aggregates vs the 4 Oct all-states tables (those keep MSNA Light in; the IPC/CH rule leaves it out)
all_state = {(r["State"], r["Scope"].replace(" only", "")): r for r in rd(ALL_STATE)}
all_lga = {(r["State"], r["LGA"]): r for r in rd(ALL_LGA) if r.get("Scope", "IDP + Non-IDP") in ("IDP + Non-IDP", "")}
light_kebbi = [s["sid"] for s in WPK["strata"] if s["state"] == "Kebbi" and s["method"] == "MSNA Light"]
for r in WPK["state_out"]:
    if r["State"] == "Kebbi":
        ref = all_state[(r["State"], r["Population group"])]
        log("   Kebbi State %-13s IPC/CH: cat %s MoE %s n %s | 4 Oct all-states table: %s MoE %s n %s"
            % (r["Population group"], r["Category"], r["Margin of error (%)"], r["Interviews in the estimate"], ref["Round 1 label"],
               ref["MoE Round 1 (deff=1) %"], ref["Achieved (included strata)"]))
log("   Kebbi MSNA Light strata (left out of IPC/CH aggregates): %s" % (light_kebbi or "none"))
kebbi_lga_diff = []
for r in WPK["lga_out"]:
    if r["State"] == "Kebbi":
        ref = all_lga.get((r["State"], r["LGA"]))
        if ref is not None and fnum(ref["MoE Round 1 (deff=1) %"]) != (None if r["_moe"] is None else round(r["_moe"], 2)):
            kebbi_lga_diff.append((r["LGA"], ref["MoE Round 1 (deff=1) %"], r["Margin of error (%)"]))
log("   Kebbi LGA rows differing from the 4 Oct all-states LGA table: %s" % (kebbi_lga_diff or "none"))

# =====================================================================================================================
# 5. DTMK: the candidate
DTMK = build("DTMK")
log("[DTMK] DTM share applied to %d IDP strata; Round 1 label changes: %d" % (len(DTMK["dtm_applied"]), len(DTMK["relabels"])))
for r in DTMK["relabels"]:
    log("   relabel %s (%s / %s %s): %s -> %s" % r)


def diff_rows(a_rows, b_rows, keys, cols):
    a, b = keyed(a_rows, keys), keyed(b_rows, keys)
    a_m = {tuple(r[k] for k in keys): r.get("_moe") for r in a_rows}
    b_m = {tuple(r[k] for k in keys): r.get("_moe") for r in b_rows}
    out = []
    for k in a:
        ra, rb = a[k], b[k]
        ch = [c for c in cols if ra[c] != rb[c]]
        if ch:
            d = {kk: ra[kk] for kk in keys}
            d.update({"State": ra["State"]} if "State" not in d else {})
            for c in cols:
                d["WP " + c], d["DTM " + c] = ra[c], rb[c]
            ma, mb = a_m[k], b_m[k]
            d["MoE change (points, unrounded)"] = None if (ma is None or mb is None) else round(mb - ma, 4)
            d["Category changes"] = "Yes" if ra["Category"] != rb["Category"] else ""
            d["Changed columns"] = "; ".join(ch)
            out.append(d)
    assert set(a) == set(b)
    return out


cols_s = ["Category", "Margin of error (%)", "% of households in accessible areas", "Households in accessible areas"]
cols_u = ["Category", "Margin of error (%)", "Households in accessible areas", "Households represented by the estimate", "% of households represented"]
d_strata = diff_rows(WPK["strata_out"], DTMK["strata_out"], ("Stratum ID",), cols_s)
d_lga = diff_rows(WPK["lga_out"], DTMK["lga_out"], ("State", "LGA"), cols_u)
d_state = diff_rows(WPK["state_out"], DTMK["state_out"], ("State", "Population group"), cols_u)
if any(r["Stratum ID"].startswith("non_idp") for r in d_strata):
    stop("a Non-IDP stratum changed under DTM")
log("[DTMK vs WPK] strata rows changed %d (category %d) | LGA rows %d (category %d, max |dMoE| %.2f) | State rows %d (category %d, max |dMoE| %.2f)"
    % (len(d_strata), sum(1 for r in d_strata if r["Category changes"]), len(d_lga), sum(1 for r in d_lga if r["Category changes"]),
       max([abs(r["MoE change (points, unrounded)"] or 0) for r in d_lga] or [0]), len(d_state), sum(1 for r in d_state if r["Category changes"]),
       max([abs(r["MoE change (points, unrounded)"] or 0) for r in d_state] or [0])))
for r in d_lga + d_state:
    if r["Category changes"]:
        log("   category change: %s" % {k: r[k] for k in r if k in ("State", "LGA", "Population group", "WP Category", "DTM Category", "WP Margin of error (%)", "DTM Margin of error (%)")})
acc_idp = lambda B: sum(s["Nacc"] for s in B["strata"] if s["pop"] == "IDP" and s["cat"] in ("a", "b"))
log("IDP households in accessible areas, strata in the estimates: WP %s -> DTM %s (%+.1f%%)"
    % (f"{acc_idp(WPK):,.0f}", f"{acc_idp(DTMK):,.0f}", 100 * (acc_idp(DTMK) / acc_idp(WPK) - 1)))

# =====================================================================================================================
# 6. The analysis team's "population" sheet (their weights input; read only)
wb = openpyxl.load_workbook(POP_SHEET_XLSX, read_only=True, data_only=True)
ws = wb["population"]
ws.reset_dimensions()
prow = list(ws.iter_rows(values_only=True))
phdr = list(prow[0])
assert phdr == ["strata", "population", "population_accessible"], phdr
psheet = [dict(zip(phdr, r)) for r in prow[1:] if r and r[0] is not None]


def key2sid(k):
    left = str(k).split(" - ")[0]
    pop, code = left.rsplit("-", 1)
    return {"IDP": "idp_", "Non IDP": "non_idp_"}[pop.strip()] + code.strip()


sK = {s["sid"]: s for s in WPK["strata"]}
sD = {s["sid"]: s for s in DTMK["strata"]}
pop_rows, pop_issues = [], []
for r in psheet:
    sid = key2sid(r["strata"])
    s, sd = sK.get(sid), sD.get(sid)
    if s is None:
        pop_issues.append("not a Round 1 (K) stratum: %s" % r["strata"]); continue
    if abs(float(r["population"]) - s["N"]) >= 1:
        pop_issues.append("population %s: sheet %s vs N_hh %.3f" % (r["strata"], r["population"], s["N"]))
    if abs(float(r["population_accessible"]) - s["Nacc"]) > 0.051:
        pop_issues.append("population_accessible %s: sheet %s vs N_acc %.3f" % (r["strata"], r["population_accessible"], s["Nacc"]))
    if s["cat"] not in ("a", "b"):
        pop_issues.append("sheet row for a stratum outside the IPC/CH estimates: %s (%s)" % (r["strata"], s["cat"]))
    pop_rows.append({"strata": r["strata"], "strata_id": sid, "population": r["population"],
                     "population_accessible_WP_sheet": r["population_accessible"],
                     "population_accessible_DTM": round(sd["Nacc"], 1), "population_accessible_DTM_full": sd["Nacc"],
                     "factor_DTM_over_WP": (sd["Nacc"] / s["Nacc"]) if s["Nacc"] else None,
                     "changed": "Yes" if round(sd["Nacc"], 1) != round(s["Nacc"], 1) else ""})
in_est = {s["sid"] for s in WPK["strata"] if s["cat"] in ("a", "b")}
missing_from_sheet = sorted(in_est - {p["strata_id"] for p in pop_rows})
log("analysis population sheet: %d rows | issues %d | IPC/CH-estimate strata missing from the sheet: %s"
    % (len(psheet), len(pop_issues), missing_from_sheet or "none"))
for x in pop_issues[:40]:
    log("   POP SHEET: " + x)
log("analysis population sheet, DTM version: %d IDP rows change" % sum(1 for p in pop_rows if p["changed"]))

# =====================================================================================================================
# 7. Design weights, rescaled per IDP stratum (calibrated to the 1-dp N_acc of the strata table, as the R script does)
wf, bys = rd(W_FINAL), rd(W_BYS)
bys_k = {r["strata_id"]: r for r in bys if r["strata_id"] in sK}
fac, wchk = {}, []
for sid, r in bys_k.items():
    s, sd = sK[sid], sD[sid]
    if abs(float(r["N_acc"]) - round(s["Nacc"], 1)) > 1e-6 or abs(float(r["sum_weight"]) - float(r["N_acc"])) > 1e-6 * float(r["N_acc"]):
        wchk.append("by_stratum %s: N_acc %s / sum %s vs table %.1f" % (sid, r["N_acc"], r["sum_weight"], s["Nacc"]))
    fac[sid] = round(sd["Nacc"], 1) / float(r["N_acc"])
if wchk:
    for x in wchk[:20]:
        log("   WEIGHTS CHECK: " + x)
    stop("the 4 Oct weights do not match the WorldPop strata table")
w_out, tot = [], collections.defaultdict(lambda: [0.0, 0.0])
for r in wf:
    if r["strata_id"] not in fac:
        continue
    f = fac[r["strata_id"]]
    o = dict(r)
    o["weight_uncapped"] = float(r["weight_uncapped"]) * f
    o["weight"] = float(r["weight"]) * f
    o["weight_WP"] = float(r["weight"])
    o["rescale_factor_DTM"] = f
    w_out.append(o)
    k = (sK[r["strata_id"]]["state"], r["pop_type"])
    tot[k][0] += float(r["weight"]); tot[k][1] += o["weight"]
sums = collections.defaultdict(float)
for o in w_out:
    sums[o["strata_id"]] += o["weight"]
bad = [sid for sid, v in sums.items() if abs(v - round(sD[sid]["Nacc"], 1)) > 1e-6 * max(1.0, v)]
if bad:
    stop("rescaled weights do not sum to the DTM N_acc: %s" % bad[:10])
log("design weights: %d households in %d weighted K strata rescaled; calibration exact to the DTM N_acc in every stratum"
    % (len(w_out), len(fac)))
fs = sorted(f for sid, f in fac.items() if sid.startswith("idp_"))
log("   IDP rescale factors: n %d, min %.3f, median %.3f, max %.3f; >10%% change in %d strata"
    % (len(fs), fs[0], fs[len(fs) // 2], fs[-1], sum(1 for f in fs if abs(f - 1) > 0.10)))
for (st, pt), (a, b) in sorted(tot.items()):
    if pt == "idp":
        nonidp = tot.get((st, "non_idp"), [0, 0])
        log("   %-8s IDP weight total %s -> %s (%+.1f%%); IDP share of the state's weighted households %.1f%% -> %.1f%%"
            % (st, f"{a:,.0f}", f"{b:,.0f}", 100 * (b / a - 1) if a else 0, 100 * a / (a + nonidp[0]), 100 * b / (b + nonidp[1])))

# =====================================================================================================================
# 8. Write
os.makedirs(OUT, exist_ok=True)
for sub in ("tables_WP_kebbi", "tables_DTM_kebbi", "diff_DTM_vs_WP", "analysis_population_sheet", "weights"):
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)


def wcsv(path, rows_):
    with open(path, "w", encoding="utf-8", newline="") as f:
        if not rows_:
            f.write("")
            return
        w = csv.DictWriter(f, fieldnames=list(rows_[0].keys()), lineterminator="\r\n")
        w.writeheader()
        w.writerows(rows_)


for tag, B in (("tables_WP_kebbi", WPK), ("tables_DTM_kebbi", DTMK)):
    for fname, rows_ in [("strata.csv", B["strata_out"]), ("lga.csv", B["lga_out"]), ("state.csv", B["state_out"]), ("not_assessed.csv", B["na_out"])]:
        wcsv(os.path.join(OUT, tag, fname), public(rows_))
    # full-precision values for independent verification
    wcsv(os.path.join(OUT, tag, "strata_full_precision.csv"),
         [{"strata_id": s["sid"], "State": s["state"], "LGA": s["lga"], "Pop type": s["pop"], "n": s["n"], "N_hh": repr(s["N"]),
           "N_acc": repr(s["Nacc"]), "moe": "" if s["moe"] is None else repr(s["moe"]), "label": s["label"], "category": s["cat"]} for s in B["strata"]])
    wcsv(os.path.join(OUT, tag, "aggregates_full_precision.csv"),
         [{"level": "LGA", "State": r["State"], "unit": r["LGA"], "Category": r["Category"], "moe": "" if r["_moe"] is None else repr(r["_moe"])} for r in B["lga_out"]] +
         [{"level": "State", "State": r["State"], "unit": r["Population group"], "Category": r["Category"], "moe": "" if r["_moe"] is None else repr(r["_moe"])} for r in B["state_out"]])
wcsv(os.path.join(OUT, "diff_DTM_vs_WP", "strata_changes.csv"), d_strata)
wcsv(os.path.join(OUT, "diff_DTM_vs_WP", "lga_changes.csv"), d_lga)
wcsv(os.path.join(OUT, "diff_DTM_vs_WP", "state_changes.csv"), d_state)
wcsv(os.path.join(OUT, "analysis_population_sheet", "population_sheet_WP_check_and_DTM.csv"), pop_rows)
# drop-in "population" sheet, same 3 columns, same row order as the analysis team's sheet
pwb = openpyxl.Workbook()
pws = pwb.active
pws.title = "population"
pws.append(["strata", "population", "population_accessible"])
for p in pop_rows:
    pws.append([p["strata"], p["population"], p["population_accessible_DTM"]])
for c in range(1, 4):
    pws.cell(row=1, column=c).font = Font(bold=True)
pws.column_dimensions["A"].width = 44
pws.column_dimensions["B"].width = 14
pws.column_dimensions["C"].width = 22
pwb.save(os.path.join(OUT, "analysis_population_sheet", "population_sheet_DTM_DRAFT.xlsx"))
w_cols = list(wf[0].keys()) + ["weight_WP", "rescale_factor_DTM"]
wcsv(os.path.join(OUT, "weights", "ROUND1_WEIGHTS_R1_kebbi_DTM_DRAFT.csv"), [{c: o[c] for c in w_cols} for o in w_out])
wcsv(os.path.join(OUT, "weights", "rescale_factors_by_stratum.csv"),
     [{"strata_id": sid, "State": sK[sid]["state"], "LGA": sK[sid]["lga"], "Pop type": sK[sid]["pop"], "N_acc_WP": round(sK[sid]["Nacc"], 1),
       "N_acc_DTM": round(sD[sid]["Nacc"], 1), "factor": f} for sid, f in sorted(fac.items())])
with open(os.path.join(OUT, "BUILD_LOG.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(log_lines) + "\n")
print("written to", OUT)
