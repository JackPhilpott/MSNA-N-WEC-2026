# ==============================================================================
# Read-only audit, 2026-09-14, per Jack's explicit ask ("yes this should be
# checked across everything") after confirming the Bug 1 fix
# (n_primary_ceiling_contribution now credits real achieved households for
# partially_completed_access_lost clusters, not just completed ones - see
# 05_build_accessibility_impact_workbook.py's own 2026-09-14b comment).
#
# Question: for every stratum that got a NEW supplementary draw in tonight's
# comprehensive accessibility-driven resampling round, would the CORRECTED
# (post-Bug-1-fix) ceiling have called for fewer clusters than were actually
# drawn? Bug 1 only ever ADDS credit to the ceiling (never removes it), so
# this is a one-directional question - "were we oversized," never "were we
# undersized."
#
# Method: reconstruct each affected stratum's PRE-DRAW achievable ceiling by
# removing tonight's newly-drawn clusters' own contribution from the CURRENT
# (post-fix, post-draw) ceiling, using the exact same n_primary_ceiling_
# contribution formula and realized_moe_unequal()/Task-3 negligible-gap logic
# 05_build_accessibility_impact_workbook.py itself uses - not a hand-rolled
# approximation. Compares the resulting "clusters actually needed, corrected,
# pre-draw" against "clusters actually drawn tonight."
#
# This is a REPORT ONLY - does not drop, archive, or modify any cluster,
# frame row, or partner-facing file. Matches the established Task-5 pattern
# (compute + verify + report, get Jack's explicit go-ahead before any live
# wiring) - this script is the "compute + verify + report" half.
# ==============================================================================
import csv
import math
import os
from collections import defaultdict

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_WORKING_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v8_WORKING.csv"
CLUSTER_STATUS_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_cluster_status_v8.csv"
WORKBOOK_PATH = PROJECT_DIR + r"\resampling\output\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
TONIGHT_FILES = [
    PROJECT_DIR + r"\resampling\output\resample_runs\_combined\2026-09-14\new_households.csv",
    PROJECT_DIR + r"\resampling\output\resample_runs\_combined\2026-09-14\new_households_idp_sitelevel.csv",
]
OUT_CSV = PROJECT_DIR + r"\resampling\output\audit_tonight_draws_vs_bug1_fix_2026-09-14.csv"
TARGET_MOE_PCT = 10.0
ICC = 0.06
Z = 1.6448536269514722
P = 0.5


def realized_moe_unequal(achieved_sample, N_hh, cluster_sizes, icc=ICC, z=Z, p=P):
    """Verbatim copy of 05_build_accessibility_impact_workbook.py's ported
    formula (itself a port of scripts/shared/frame_status.R's Task 4
    function) - kept identical on purpose so this audit's numbers are
    directly comparable to the production script's own."""
    sizes = [s for s in cluster_sizes if s is not None and s > 0]
    if not sizes:
        return None
    if achieved_sample <= 0 or N_hh <= achieved_sample:
        return None
    m_bar = sum(sizes) / len(sizes)
    if len(sizes) > 1 and m_bar > 0:
        variance = sum((s - m_bar) ** 2 for s in sizes) / (len(sizes) - 1)
        cv = math.sqrt(variance) / m_bar
    else:
        cv = 0.0
    deff = 1 + ((cv ** 2 + 1) * m_bar - 1) * icc
    ndeff = achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
    n0 = ndeff / deff
    if n0 <= 0:
        return None
    return math.sqrt(z ** 2 * p * (1 - p) / n0) * 100


def load_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


# ---------------------------------------------------------------------------
# 1. Tonight's draw: cluster_id -> strata_id
# ---------------------------------------------------------------------------
tonight_strata_by_cluster = {}
for fn in TONIGHT_FILES:
    for r in load_csv(fn):
        tonight_strata_by_cluster[r["cluster_id"]] = r["strata_id"]
tonight_cluster_ids = set(tonight_strata_by_cluster)
affected_strata = sorted(set(tonight_strata_by_cluster.values()))
print(f"Tonight's draw: {len(tonight_cluster_ids)} new clusters across {len(affected_strata)} strata.")

# ---------------------------------------------------------------------------
# 2. cluster_status_v8.csv - status/n_achieved/n_accessible_primary_post_
#    threshold per cluster_id, to compute the CORRECTED ceiling contribution
#    for every cluster (tonight's new ones and every pre-existing one alike).
# ---------------------------------------------------------------------------
cluster_status = {r["cluster_id"]: r for r in load_csv(CLUSTER_STATUS_CSV)}


def ceiling_contribution(cid):
    cs = cluster_status.get(cid)
    if cs is None:
        return 0
    n_acc = int(cs["n_accessible_primary_post_threshold"] or 0)
    n_ach = int(cs["n_achieved"] or 0)
    if cs["status"] in ("completed", "partially_completed_access_lost"):
        return max(n_acc, n_ach)
    return n_acc


# ---------------------------------------------------------------------------
# 3. Every CURRENT cluster_id per strata_id (WORKING, primary rows) - needed
#    to reconstruct the full pre-draw cluster_sizes distribution, not just
#    tonight's subset, for the unequal-cluster-size MoE formula.
# ---------------------------------------------------------------------------
clusters_by_strata = defaultdict(set)
for r in load_csv(STAGE2_WORKING_CSV):
    if r["status"] != "primary":
        continue
    if r.get("sampling_method") == "MSNA Light":
        continue
    clusters_by_strata[r["strata_id"]].add(r["cluster_id"])

# ---------------------------------------------------------------------------
# 4. Current (post-fix, post-draw) per-stratum figures from the freshly-
#    rebuilt workbook - target_repr, m_used, N_hh_accessible, current
#    ceiling/Feasibility, for cross-reference.
# ---------------------------------------------------------------------------
wb = openpyxl.load_workbook(WORKBOOK_PATH, data_only=True)
ws = wb["Strata Level"]
header = [c.value for c in ws[1]]
idx = {h: i for i, h in enumerate(header)}
strata_current = {}
for row in ws.iter_rows(min_row=2, values_only=True):
    sid = row[idx["Strata ID"]]
    strata_current[sid] = {
        "m_used": row[idx["[UPDATED AREA] Target clusters"]],  # placeholder, overwritten below if m_used col found
        "N_hh_accessible": row[idx["Updated population within accessible area"]],
        "target_repr": row[idx["Target sample (representativity, incl. 5% operational margin)"]],
        "ceiling_current": row[idx["[UPDATED AREA] Achievable ceiling (primary only, decision basis)"]],
        "feasibility_current": row[idx["Feasibility"]],
        "additional_needed_current": row[idx["Additional clusters needed for 10% MoE (at m=6)"]],
        "partners": row[idx["Partners covering"]],
        "state": row[idx["State"]],
        "lga": row[idx["LGA"]],
        "pop_type": row[idx["Pop type"]],
    }

# m_used isn't a direct workbook column by that name - pull it from the strata-level WORKING CSV instead (authoritative).
strata_csv_rows = load_csv(PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v8_WORKING.csv")
m_used_by_strata = {r["strata_id"]: int(float(r["m_used"])) for r in strata_csv_rows if r.get("m_used") not in (None, "", "NA")}

# ---------------------------------------------------------------------------
# 5. Per-stratum reconstruction and comparison.
# ---------------------------------------------------------------------------
results = []
for sid in affected_strata:
    cur = strata_current.get(sid)
    if cur is None:
        results.append({"strata_id": sid, "note": "NOT FOUND in current workbook Strata Level sheet - investigate separately", })
        continue
    m_used = m_used_by_strata.get(sid)
    if not m_used:
        results.append({"strata_id": sid, "note": "m_used not found in strata CSV - investigate separately"})
        continue

    all_ids = clusters_by_strata.get(sid, set())
    tonight_ids_here = {cid for cid, s in tonight_strata_by_cluster.items() if s == sid}
    pre_draw_ids = all_ids - tonight_ids_here
    not_merged = tonight_ids_here - all_ids  # drawn tonight but not currently in WORKING primary set - flag, don't silently ignore

    pre_draw_sizes = [ceiling_contribution(cid) for cid in pre_draw_ids]
    ceiling_pre_draw = sum(pre_draw_sizes)
    tonight_sizes = [ceiling_contribution(cid) for cid in tonight_ids_here]
    tonight_contribution = sum(tonight_sizes)

    N_hh_accessible = cur["N_hh_accessible"] or 0
    target_repr = cur["target_repr"]

    moe_pre_draw = (
        realized_moe_unequal(ceiling_pre_draw, N_hh_accessible, pre_draw_sizes)
        if N_hh_accessible > 0 else None
    )

    if moe_pre_draw is not None and moe_pre_draw <= TARGET_MOE_PCT:
        feasibility_pre_draw = "Already at/under target (pre-draw, corrected)"
        clusters_needed_corrected = 0
    elif target_repr is None:
        feasibility_pre_draw = "Not computable (accessible population too small)"
        clusters_needed_corrected = None
    else:
        half_cluster = m_used / 2
        hypothetical_ceiling = ceiling_pre_draw + half_cluster
        if hypothetical_ceiling >= N_hh_accessible:
            moe_half_more = 0.0
        else:
            moe_half_more = realized_moe_unequal(hypothetical_ceiling, N_hh_accessible, pre_draw_sizes + [half_cluster])
        if moe_half_more is not None and moe_half_more <= TARGET_MOE_PCT:
            feasibility_pre_draw = "Negligible gap (pre-draw, corrected)"
            clusters_needed_corrected = 0
        else:
            shortfall = max(0, target_repr - ceiling_pre_draw)
            clusters_needed_corrected = math.ceil(shortfall / m_used) if shortfall > 0 else 0
            feasibility_pre_draw = "Real shortfall (pre-draw, corrected)"

    clusters_drawn_tonight = len(tonight_ids_here)
    excess_clusters = max(0, clusters_drawn_tonight - (clusters_needed_corrected or 0))

    results.append({
        "strata_id": sid, "state": cur["state"], "lga": cur["lga"], "pop_type": cur["pop_type"],
        "partners": cur["partners"], "m_used": m_used,
        "clusters_drawn_tonight": clusters_drawn_tonight,
        "not_merged_into_working": len(not_merged),
        "N_hh_accessible": round(N_hh_accessible, 1), "target_repr": round(target_repr, 2) if target_repr else target_repr,
        "ceiling_pre_draw_corrected": ceiling_pre_draw,
        "moe_pre_draw_corrected_pct": round(moe_pre_draw, 2) if moe_pre_draw is not None else None,
        "feasibility_pre_draw_corrected": feasibility_pre_draw,
        "clusters_needed_corrected": clusters_needed_corrected,
        "excess_clusters_this_stratum": excess_clusters,
        "ceiling_current_post_draw": cur["ceiling_current"],
        "feasibility_current": cur["feasibility_current"],
        "note": "",
    })

# ---------------------------------------------------------------------------
# 6. Write + summarize.
# ---------------------------------------------------------------------------
fieldnames = ["strata_id", "state", "lga", "pop_type", "partners", "m_used",
              "clusters_drawn_tonight", "not_merged_into_working",
              "N_hh_accessible", "target_repr", "ceiling_pre_draw_corrected",
              "moe_pre_draw_corrected_pct", "feasibility_pre_draw_corrected",
              "clusters_needed_corrected", "excess_clusters_this_stratum",
              "ceiling_current_post_draw", "feasibility_current", "note"]
with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in results:
        w.writerow({k: r.get(k, "") for k in fieldnames})

valid = [r for r in results if "excess_clusters_this_stratum" in r]
total_excess = sum(r["excess_clusters_this_stratum"] for r in valid)
strata_with_excess = [r for r in valid if r["excess_clusters_this_stratum"] > 0]
total_drawn = sum(r["clusters_drawn_tonight"] for r in valid)
not_merged_total = sum(r["not_merged_into_working"] for r in valid)

print(f"\n{len(valid)} of {len(affected_strata)} strata computed cleanly ({len(results) - len(valid)} need manual investigation - see notes).")
print(f"Total clusters drawn tonight (in-scope strata): {total_drawn}")
print(f"Total clusters drawn but not currently in WORKING primary set (investigate): {not_merged_total}")
print(f"\nStrata with excess (drawn more than the corrected formula says was needed): {len(strata_with_excess)}")
print(f"Total excess clusters nationally: {total_excess}")
print(f"\nWritten: {OUT_CSV}")
if strata_with_excess:
    print("\nTop excess strata:")
    for r in sorted(strata_with_excess, key=lambda x: -x["excess_clusters_this_stratum"])[:15]:
        print(f"  {r['strata_id']} ({r['partners']}, {r['state']}/{r['lga']}): drawn={r['clusters_drawn_tonight']}, "
              f"needed_corrected={r['clusters_needed_corrected']}, excess={r['excess_clusters_this_stratum']}")
