# ==============================================================================
# Task 3 of Jack's five (2026-09-21): classify every covered stratum that is
# NOT representative (10% MoE on the verdict basis), for the donor note.
# Jack's scope: all non-representative strata - those that can't be fixed
# AND those still fixable by a draw, clearly marked - as a review table
# first; donor wording is a later step once he has checked the calls.
#
# Two questions per stratum, deliberately kept apart (a single "primary
# mechanism" would blur them):
#   WHY IT'S SHORT (every stratum). The excess over 10% on the rigorous Kish
#   formula splits additively into
#     unevenness part = rigorous MoE - MoE of the same interviews in the same
#                       number of EQUAL-sized clusters (cv = 0)
#     sample part     = equal-cluster MoE - 10
#   and the label follows the unevenness share of the excess:
#     mainly_uneven_cluster_sizes  share >= UNEVEN_HI (60%)
#     mainly_too_few_interviews    share <= UNEVEN_LO (40%)
#     both                         in between
#   Special cases, tested first:
#     no_full_design_sample   - Full Design achievable ceiling is 0 (MSNA Light
#                               never counts - 2026-09-11 rule).
#     sample_exceeds_population_estimate - achievable ceiling >= accessible
#                               N_hh, so no MoE formula applies.
#     certainty strata        - the verdict uses the certainty-PSU formula,
#                               which already credits site-size structure, so
#                               the rigorous split doesn't describe the
#                               verdict. Label from that formula's own
#                               variance: dominant_site_under_sampled if one
#                               certainty site carries >= 50% of the variance,
#                               else mainly_too_few_interviews. Flagged.
#   WHY IT CAN'T BE FIXED (verdict not recoverable / not computable), first
#   matching rule in this order; every other rule that also matches is listed
#   in also_matches:
#     no_full_design_sample, sample_exceeds_population_estimate - as above.
#     access_loss        - under ACCESS_LOSS_SHARE (50%) of the design
#                          population is still accessible.
#     no_remaining_pool  - no eligible, unselected candidate left.
#     pool_too_small     - some pool, fewer than the clusters needed.
#   Borderline calls (within 5 pts of a cut point) are flagged, not resolved.
#   Jack kept both cut points (50% access, 40/60 unevenness) on review,
#   2026-09-21.
#
# EXTRA INTERVIEWS AT A CERTAINTY SITE (route accepted by Jack on review,
# 2026-09-21, and built into 05 the same night): a certainty site is its
# own stratum under the verdict formula, so more interviews there cut
# variance directly with no cluster penalty. The route and its interview
# count are read from 05's own Feasibility label, never recomputed here, so
# the record and this table can't disagree; the highest-variance-site
# figure below is evidence only.
#
# Before classifying, both MoEs are re-derived here from cluster sizes and
# must reproduce the record (N +/- 0.5 for the record's rounding); a row
# that doesn't is flagged, since its split would then be unreliable.
#
# Everything is computed from the current record and frame, never recalled:
# resampling/output/strata_representativity_status.csv (verdicts), the
# impact workbook's Strata Level sheet (populations, pool, clusters needed),
# and the v11 cluster status + FULL frame (per-cluster sizes, with 05's own
# "ceiling contribution" rule and certainty flag).
#
# Output: resampling/output/non_representative_strata_2026-09-21.csv
# Usage:  python classify_non_representative_strata_2026-09-21.py
# ==============================================================================
import csv
import math
import re
from collections import Counter, defaultdict

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
DC = PROJECT_DIR + r"\output\data\data_collection"
REPR_CSV = PROJECT_DIR + r"\resampling\output\strata_representativity_status.csv"
IMPACT_XLSX = PROJECT_DIR + r"\resampling\output\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
CLUSTER_STATUS_CSV = DC + r"\NGA_MSNA_2026_cluster_status_v11.csv"
FULL_CSV = DC + r"\NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv"
OUT_CSV = PROJECT_DIR + r"\resampling\output\non_representative_strata_2026-09-21.csv"

TARGET_MOE_PCT = 10.0
ACCESS_LOSS_SHARE = 50.0   # % of design population still accessible; an explicit, re-cuttable parameter
UNEVEN_LO, UNEVEN_HI = 40.0, 60.0
BORDER_PTS = 5.0
REPRO_TOL = 0.02
CERTAINTY_MIN_COVERAGE, CERTAINTY_MIN_N_I = 0.90, 3

# HAND-MARKED NOT RECOVERABLE (Jack, 2026-09-21: "just mark by hand for now",
# instead of building-validating analysis_remaining_eligible_pool.R yet).
# 05 labels these "RECOVERABLE via supplementary draw" because its pool is a
# hex count with no building check; the building-validated draw (Stage B2,
# commit 4f36532) shows no draw can close them. Evidence from its dry run
# (resampling/output/draw_fix_dryrun_2026-09-21/new/pool_validation_by_hex.csv)
# and that run's projection. Applied ONLY while the record still calls the
# stratum draw-recoverable, and shown in its own column - never silent.
MANUAL_NOT_RECOVERABLE = {
    "non_idp_NG008015": "Kala/Balge: 0 of 3 candidate hexes have 6+ accessible, unclaimed buildings - nothing can be drawn",
    "non_idp_NG008025": "Ngala: 1 of 4 candidate hexes drawable; drawing it reaches only 11.92%",
    "non_idp_NG008026": "Nganzai: 1 of 5 candidate hexes drawable; drawing it reaches only 11.38%",
}
ICC, Z, P = 0.06, 1.6448536269514722, 0.5


def load(p):
    with open(p, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def moe_unequal(sizes, N):
    """05's realized_moe_unequal() (Kish unequal-cluster DEFF, FPC), in %."""
    s = [x for x in sizes if x and x > 0]
    n = sum(s)
    if not s or N is None or N <= n:
        return None
    m = n / len(s)
    cv = (math.sqrt(sum((x - m) ** 2 for x in s) / (len(s) - 1)) / m) if len(s) > 1 else 0.0
    deff = 1 + ((cv ** 2 + 1) * m - 1) * ICC
    return 100 * Z * math.sqrt(P * (1 - P) / ((n * (N - 1) / (N - n)) / deff))


def moe_equal(sizes, N):
    """Same interviews, same number of clusters, equal sizes (cv = 0)."""
    s = [x for x in sizes if x and x > 0]
    if not s:
        return None
    n = sum(s)
    return moe_unequal([n / len(s)] * len(s), N)


def certainty_terms(clusters, N_hh):
    """05's realized_moe_certainty_aware(), returning (moe %, per-site variance
    terms, pooled term) or None where 05 would fall back to rigorous."""
    live = [c for c in clusters if c["n"] > 0]
    if not live:
        return None
    cert_all = [c for c in live if c["cert"] and c["N_i"]]
    cert = [c for c in cert_all if c["n"] >= CERTAINTY_MIN_N_I]
    demoted = [c for c in cert_all if c["n"] < CERTAINTY_MIN_N_I]
    samp = [c for c in live if c not in cert_all] + demoted
    N_cert = sum(c["N_i"] for c in cert)
    N_total = max(float(N_hh or 0), N_cert)
    if N_total <= 0 or not cert or N_cert / N_total < CERTAINTY_MIN_COVERAGE or (N_cert < N_total and not samp):
        return None
    terms = {c["id"]: (c["N_i"] / N_total) ** 2 * P * (1 - P) / c["n"] * max(0.0, 1 - c["n"] / c["N_i"]) for c in cert}
    pooled = 0.0
    if samp:
        N_s = max(N_total - N_cert, 0.0)
        sizes = [c["n"] for c in samp]
        n_s = sum(sizes)
        if N_s > n_s:
            m = n_s / len(sizes)
            cv = (math.sqrt(sum((x - m) ** 2 for x in sizes) / (len(sizes) - 1)) / m) if len(sizes) > 1 else 0.0
            n0 = (n_s * (N_s - 1) / (N_s - n_s)) / (1 + ((cv ** 2 + 1) * m - 1) * ICC)
            if n0 > 0:
                pooled = (N_s / N_total) ** 2 * P * (1 - P) / n0
    return 100 * Z * math.sqrt(sum(terms.values()) + pooled), terms, pooled, N_total


def reproduces(fn, record_value, N):
    """True if fn(N') matches the record for some N' in N +/- 0.5 (the
    record stores round(N_hh_accessible))."""
    if N is None:
        return record_value is None
    if record_value is None:
        return any(fn(N + d) is None for d in (-0.5, 0, 0.5))
    vals = [fn(N + d) for d in (-0.5, -0.25, 0, 0.25, 0.5)]
    vals = [v for v in vals if v is not None]
    return bool(vals) and min(vals) - REPRO_TOL <= record_value <= max(vals) + REPRO_TOL


def verdict_class(v):
    if v.startswith("Representative"):
        return "Representative"
    if "certainty site" in v:
        return "Recoverable: extra interviews at a certainty site"
    if "NOT recoverable" in v:
        return "Not recoverable"
    if "RECOVERABLE" in v:
        return "Recoverable by a draw"
    if "negligible" in v:
        return "Negligible gap"
    if v.startswith("Not computable"):
        return "Not computable"
    return v


# ---- inputs -----------------------------------------------------------------
rep = load(REPR_CSV)
rc = list(rep[0].keys())
col = lambda frag: [k for k in rc if frag in k][0]
K_VERDICT, K_MOE, K_RIG = col("Representativity ("), col("DRIVES the verdict"), col("rigorous Kish")
K_CERT, K_NACC = col("treatment applied"), col("accessible N_hh")

wb = openpyxl.load_workbook(IMPACT_XLSX, read_only=True, data_only=True)
ws = wb["Strata Level"]
it = ws.iter_rows(values_only=True)
hdr = list(next(it))
sl = {r[hdr.index("Strata ID")]: dict(zip(hdr, r)) for r in it if r and r[hdr.index("Strata ID")]}
wb.close()
SL_POP, SL_POP_ACC = "Total population (design, n_pop)", "Updated population within accessible area"
SL_POOL = "Remaining eligible pool (accessible, unselected)"
SL_NEED = "Additional clusters needed for 10% MoE (at m=6)"

cs = {r["cluster_id"]: r for r in load(CLUSTER_STATUS_CSV)}
cl_meta = {}
for r in load(FULL_CSV):
    cl_meta.setdefault(r["cluster_id"], r)
by_stratum = defaultdict(list)
for cid, r in cl_meta.items():
    if r.get("sampling_method") == "MSNA Light" or cid not in cs:
        continue
    by_stratum[r["strata_id"]].append(cid)


def ceiling(cid):
    s = cs[cid]
    acc, ach = int(s["n_accessible_primary_post_threshold"]), int(s["n_achieved"])
    return max(acc, ach) if s["status"] in ("completed", "partially_completed_access_lost") else acc


def cluster_dicts(sid):
    return [{"id": c, "n": ceiling(c), "N_i": num(cl_meta[c].get("households_in_cluster")) or 0,
             "cert": (num(cl_meta[c].get("selection_count")) or 1) > 1,
             "site": cl_meta[c].get("iom_site_name") or c} for c in by_stratum.get(sid, [])]


# ---- classify ---------------------------------------------------------------
out = []
for r in rep:
    vc = verdict_class(r[K_VERDICT])
    if vc == "Representative":
        continue
    sid = r["Strata ID"]
    s = sl.get(sid, {})
    pop, pop_acc = num(s.get(SL_POP)), num(s.get(SL_POP_ACC))
    acc_share = round(100 * pop_acc / pop, 1) if pop and pop_acc is not None else None
    pool, need = num(s.get(SL_POOL)), num(s.get(SL_NEED))
    N = num(r[K_NACC])
    cds = cluster_dicts(sid)
    live = [c["n"] for c in cds if c["n"] > 0]
    ceiling_total = sum(live)
    m_rig, m_ver = num(r[K_RIG]), num(r[K_MOE])
    cert = (r[K_CERT] or "").startswith("Yes")
    m_eq = moe_equal(live, N)
    flags = []

    # reproduction check - the split below is only as good as this
    ok_rig = reproduces(lambda n_: moe_unequal(live, n_), m_rig, N)
    ok_ver = reproduces(lambda n_: (certainty_terms(cds, n_) or (None,))[0], m_ver, N) if cert else ok_rig
    if not (ok_rig and ok_ver):
        flags.append("MoE NOT reproduced from cluster sizes - split unreliable")
    # plausibility: an IDP site can't yield more interviews than it has
    # households (Non-IDP households_in_cluster is a building count - skip)
    if r["Pop type"] == "IDP":
        for c in cds:
            ach = int(cs[c["id"]]["n_achieved"])
            if c["N_i"] and ach > c["N_i"]:
                flags.append(f'{c["site"]}: {ach} interviews vs {int(c["N_i"])} DTM households - check')

    # why it's short
    uneven_share = None
    dominant = ""
    site_topup_k = None
    if ceiling_total == 0:
        why_short = "no_full_design_sample"
    elif N is not None and ceiling_total >= N:
        why_short = "sample_exceeds_population_estimate"
    elif cert:
        _, terms, pooled, N_total = certainty_terms(cds, N)
        total_var = sum(terms.values()) + pooled
        top_id, top_var = max(terms.items(), key=lambda kv: kv[1])
        top = next(c for c in cds if c["id"] == top_id)
        dominant = (f'{top["site"]}: {round(100 * top["N_i"] / N_total)}% of households, '
                    f'{top["n"]} interviews, {round(100 * top_var / total_var)}% of the variance')
        # under-sampled = carries most of the variance AND more of it than its
        # household share (a proportionally allocated certainty site's
        # variance share equals its household share)
        under = top_var / total_var >= 0.5 and top_var / total_var > top["N_i"] / N_total
        why_short = "dominant_site_under_sampled" if under else "mainly_too_few_interviews"
        # evidence only (no draw decided): extra interviews at that one site,
        # everything else held, to bring the certainty-formula MoE to <= 10%.
        # 05's own "clusters needed" projects NEW pool clusters on the
        # rigorous formula, which can't move a certainty verdict.
        site_topup = "not reachable at this site alone"
        if int(cs[top_id]["n_accessible_primary_post_threshold"]) == 0:
            site_topup = f"site no longer accessible ({cs[top_id]['status']})"
        for k in range(1, int(top["N_i"] - top["n"]) + 1 if site_topup.startswith("not reachable") else 0):
            trial = [dict(c, n=c["n"] + k) if c["id"] == top_id else c for c in cds]
            if certainty_terms(trial, N)[0] <= TARGET_MOE_PCT:
                site_topup = f"+{k} interviews at {top['site']} (cluster {top_id}, status {cs[top_id]['status']})"
                site_topup_k, site_topup_where = k, f"{top['site']} ({top_id}, {cs[top_id]['status'].replace('_', ' ')})"
                break
        dominant += f"; to reach 10%: {site_topup}"
        flags.append("certainty formula drives the verdict - rigorous split shown for reference only")
    else:
        excess = m_rig - TARGET_MOE_PCT
        uneven_share = min(100.0, max(0.0, 100 * (m_rig - m_eq) / excess)) if excess > 0 else None
        if uneven_share is None:
            why_short = "mainly_too_few_interviews"
        elif uneven_share >= UNEVEN_HI:
            why_short = "mainly_uneven_cluster_sizes"
        elif uneven_share <= UNEVEN_LO:
            why_short = "mainly_too_few_interviews"
        else:
            why_short = "both"
        if uneven_share is not None and (abs(uneven_share - UNEVEN_HI) < BORDER_PTS or abs(uneven_share - UNEVEN_LO) < BORDER_PTS):
            flags.append(f"borderline why-short split ({uneven_share:.0f}% uneven vs {UNEVEN_LO:.0f}/{UNEVEN_HI:.0f} cuts)")

    # why it can't be fixed
    certsite = vc == "Recoverable: extra interviews at a certainty site"
    unfixable = vc in ("Not recoverable", "Not computable")
    manual = MANUAL_NOT_RECOVERABLE.get(sid, "") if vc == "Recoverable by a draw" else ""
    if manual:
        unfixable = True
    matches = ["no_buildable_pool"] if manual else []
    if ceiling_total == 0:
        matches.append("no_full_design_sample")
    if ceiling_total and N is not None and ceiling_total >= N:
        matches.append("sample_exceeds_population_estimate")
    if acc_share is not None and acc_share < ACCESS_LOSS_SHARE:
        matches.append("access_loss")
    if not pool:
        matches.append("no_remaining_pool")
    elif need is not None and need > pool:
        matches.append("pool_too_small")
    why_unfixable = matches[0] if unfixable and matches else ""
    also = matches[1:] if unfixable else []
    if unfixable and acc_share is not None and abs(acc_share - ACCESS_LOSS_SHARE) < BORDER_PTS:
        flags.append(f"borderline access share ({acc_share}% vs {ACCESS_LOSS_SHARE:.0f}% cut)")

    # fix route for the rest
    draw_clusters = None
    if certsite:
        m05 = re.search(r"\(\+(\d+) at (.*)\)$", s.get("Feasibility", ""))
        site_topup_k = int(m05.group(1))
        fix_route = f"+{site_topup_k} interviews at certainty site {m05.group(2)}"
        group = vc
    elif vc == "Recoverable by a draw":
        draw_clusters = int(need)
        fix_route = f"draw {draw_clusters} cluster(s) from a pool of {int(pool)}"
    elif vc == "Negligible gap":
        if pool:
            draw_clusters = 1
            fix_route = f"within half a cluster; a 1-cluster draw is possible (pool {int(pool)}) - 05 advises no draw"
        else:
            fix_route = "within half a cluster; no pool left to draw from"
    else:
        fix_route = "not fixable by a draw"
    if manual:
        draw_clusters = None
        fix_route = "not fixable by a draw (hand-marked: building-validated pool can't close it)"
        flags.append(f"HAND-MARKED not recoverable (Jack, 2026-09-21) - 05 still says recoverable: {manual}")
    if not certsite:
        group = ("Cannot be fixed" if unfixable else
                 "Recoverable by a draw" if vc == "Recoverable by a draw" else "Negligible gap")
    if sid == "idp_NG034001":
        # Monitoring's trace, 2026-09-21 (handed over on Jack's instruction):
        # of the 121 matched interviews at Makarantar Boko, 84 are
        # matched_gps_outlier (median 468 m from the point), 39 already
        # is_duplicate, spread over 7 enumerators and 6 days; no sibling
        # cluster's work leaked in. Under the achieved policy only confirmed
        # deletions exclude, so all 121 count until cleanup resolves.
        flags.append("HOLD for donor note: verdict depends on duplicate cleanup - Monitoring trace 2026-09-21: "
                     "84 of 121 are GPS outliers, 39 already flagged duplicates, no sibling leakage. "
                     "Site at >=106 interviews: not computable; 90: 9.1%; 82 (all 39 duplicates removed): 11.2%. "
                     "Also: accessible N_hh 112 is below the DTM count of its own accessible sites (97 + 52 = 149)")

    out.append({
        "state": r["State"], "lga": r["LGA"], "pop_type": r["Pop type"], "strata_id": sid,
        "partners": r["Partners covering"], "verdict": vc, "group": group, "fixable": "no" if unfixable else "yes",
        "moe_verdict_pct": r[K_MOE], "moe_rigorous_pct": r[K_RIG],
        "moe_if_equal_clusters_pct": round(m_eq, 2) if m_eq is not None else "N/A",
        "uneven_share_of_gap_pct": round(uneven_share) if uneven_share is not None else "",
        "certainty_treatment": "yes" if cert else "no",
        "dominant_certainty_site": dominant,
        "why_short": why_short, "why_cannot_be_fixed": why_unfixable, "also_matches": "; ".join(also),
        "fix_route": fix_route,
        "manual_override": manual,
        "accessible_population_share_pct": acc_share if acc_share is not None else "N/A",
        "design_population": round(pop) if pop else "N/A", "accessible_households": r[K_NACC],
        "clusters_with_sample": len(live), "achievable_ceiling_interviews": ceiling_total,
        "remaining_pool": int(pool) if pool is not None else "N/A",
        "clusters_needed_05": int(need) if need is not None else "N/A",
        "draw_clusters_to_fix": draw_clusters if draw_clusters is not None else "",
        "certainty_site_extra_interviews": site_topup_k if certsite else "",
        "feasibility_05": s.get("Feasibility", ""),
        "flags": " | ".join(flags),
    })

order = {"Cannot be fixed": 0, "Recoverable: extra interviews at a certainty site": 1, "Recoverable by a draw": 2, "Negligible gap": 3}
out.sort(key=lambda x: (order.get(x["group"], 9), x["verdict"] != "Not computable", x["why_cannot_be_fixed"], x["why_short"], x["state"], x["lga"]))
with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
    w.writeheader()
    w.writerows(out)

print(f"{len(out)} non-representative strata -> {OUT_CSV}")
print("by 05 verdict:", dict(Counter(x["verdict"] for x in out)))
print("by group:", dict(Counter(x["group"] for x in out)))
print("why short:", dict(Counter(x["why_short"] for x in out)))
print("why it can't be fixed (unfixable only):", dict(Counter(x["why_cannot_be_fixed"] for x in out if x["fixable"] == "no")))
fx = [x for x in out if x["fixable"] == "yes"]
print(f"still fixable: {len(fx)}; clusters a full top-up would take: {sum(int(x['draw_clusters_to_fix'] or 0) for x in fx)}; "
      f"negligible with no pool: {sum(1 for x in fx if 'no pool' in x['fix_route'])}")
print("flagged rows:")
for x in out:
    if x["flags"]:
        print(f"  {x['lga']} {x['pop_type']}: {x['flags']}  [{x['why_short']} / {x['why_cannot_be_fixed']}] {x['dominant_certainty_site']}")
