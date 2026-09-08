# ==============================================================================
# Standing recurring recheck for the accessibility_loss_below_population_
# threshold exclusion mechanism (build_v3_frame_2026-08-31.R) - Jack's
# explicit go-ahead 2026-09-08, closing the concrete fix named repeatedly in
# project memory/this pipeline audit: that exclusion is computed ONCE against
# whatever accessibility snapshot existed on 2026-08-31, then every later
# frame version inherits it unchanged (a simple `filter(exclusion_reason ==
# "none")`) - nothing has ever rechecked it against CURRENT ward-accessibility
# data. Real, confirmed-both-directions consequence found this week: some
# frozen-excluded strata (Dandume, Faskari - already manually reinstated
# 2026-09-08, see CLAUDE.md Update 2026-09-08g) should be reinstated; other
# currently-COVERED strata have silently fallen below the floor while
# partners actively work toward now-largely-unreachable targets.
#
# What this script does: recomputes the real, current population-weighted %
# accessible for every in-scope stratum (same authoritative formula
# 05_build_accessibility_impact_workbook.py's load_lga_area_pop_fractions()
# uses - the ward-clipped GIS layer, NOT a row-count approximation - proven
# correct for exactly this purpose during the Dandume/Faskari reinstatement),
# compares the mechanical verdict against the stratum's ACTUAL current
# coverage_status/exclusion_reason, and flags every mismatch in BOTH
# directions. Purely mechanical - the recompute itself is deterministic, no
# judgment involved, per this project's "run a mechanical test uniformly and
# report the number" principle.
#
# What this script deliberately does NOT do: change coverage_status,
# exclusion_reason, target_sample, or anything else in FULL/WORKING. Whether/
# how to actually act on a flagged stratum (reinstate it, recompute its
# target_sample, reassign a partner, or decide a marginal case needs a second
# look) is Jack's call, same bar as any coverage decision - this script's
# entire job is producing the reviewable list, not applying it. Read-only,
# same convention as analysis_remaining_eligible_pool.R/
# analysis_partner_overview.py.
#
# Scope: only strata where population-threshold is the relevant axis -
# currently-excluded-for-THIS-reason strata (reinstatement candidates) and
# fully-covered strata with no exclusion at all (new-exclusion candidates).
# A stratum excluded for a DIFFERENT reason (partner_coverage_declined,
# certainty_stratum_below_moe_threshold) is out of scope - this mechanism
# doesn't touch those, reinstating/excluding them isn't a population-
# threshold question.
#
# Usage: python recheck_population_threshold_exclusions.py
# Writes resampling/output/population_threshold_recheck_<date>.csv (every
# in-scope stratum, flagged or not, for a full audit trail) and prints a
# short summary of just the flagged ones.
# ==============================================================================
import csv
import sys
from collections import defaultdict
from datetime import date

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
sys.path.insert(0, PROJECT_DIR + r"\scripts\shared")
from assert_fresh import assert_fresh  # noqa: E402

STRATA_FULL_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"
GIS_WARD_CSV = PROJECT_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
MASTER_WARD_CSV = PROJECT_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"
OUT_CSV = PROJECT_DIR + rf"\resampling\output\population_threshold_recheck_{date.today().isoformat()}.csv"

POP_FLOOR_PCT = 10.0  # matches build_v3_frame_2026-08-31.R's POP_FLOOR_PCT exactly
EXCLUSION_REASON = "accessibility_loss_below_population_threshold"

# GIS layer must postdate the master ward status it's derived from - a stale
# GIS layer would make this recheck's whole output meaningless. mode="stop":
# this is judgment-relevant, heavy-recompute-adjacent territory, never
# auto-regenerate.
assert_fresh(
    artifact_path=GIS_WARD_CSV,
    source_paths=[MASTER_WARD_CSV],
    mode="stop",
    fix_hint='Rscript "resampling/scripts/analysis_accessible_area_layer.R"',
    label="accessible_area_lga_ward_portions.csv",
)


def load_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def pop_type_label(pop_type_lower):
    return "Non-IDP" if pop_type_lower == "non_idp" else "IDP"


# ---- Recompute the real, current population-weighted % accessible per (adm2_pcode, pop_type) ----
gis_rows = load_csv(GIS_WARD_CSV)
agg = defaultdict(lambda: {"total_pop": 0.0, "acc_pop": 0.0})
for r in gis_rows:
    key = (r["adm2_pcode"], r["pop_type"])
    pop = float(r["pop_total"])
    agg[key]["total_pop"] += pop
    if r["accessible_status"] == "Accessible":
        agg[key]["acc_pop"] += pop

pct_accessible = {}
for key, a in agg.items():
    pct_accessible[key] = 100 * a["acc_pop"] / a["total_pop"] if a["total_pop"] else None

print(f"Recomputed population-weighted %% accessible for {len(pct_accessible)} (LGA, pop_type) combination(s) from {GIS_WARD_CSV}.")

# ---- Evaluate every in-scope stratum ----
strata = load_csv(STRATA_FULL_CSV)
results = []
for s in strata:
    coverage_status = s.get("coverage_status", "")
    exclusion_reason = s.get("exclusion_reason", "") or "none"
    is_excluded_this_reason = (coverage_status == "excluded" and exclusion_reason == EXCLUSION_REASON)
    is_fully_covered = (coverage_status == "covered" and exclusion_reason in ("none", ""))
    if not (is_excluded_this_reason or is_fully_covered):
        continue  # out of scope - excluded for an unrelated reason

    key = (s["adm2_pcode"], pop_type_label(s["pop_type"]))
    pct = pct_accessible.get(key)

    if pct is None:
        verdict = "COULD_NOT_RECOMPUTE"
        flag = "NO_GIS_MATCH_NEEDS_REVIEW"
    else:
        verdict = "below_floor" if pct < POP_FLOOR_PCT else "at_or_above_floor"
        if is_excluded_this_reason and verdict == "at_or_above_floor":
            flag = "REINSTATEMENT_CANDIDATE"
        elif is_fully_covered and verdict == "below_floor":
            flag = "NEW_EXCLUSION_CANDIDATE"
        else:
            flag = "consistent_no_action"

    results.append({
        "strata_id": s["strata_id"],
        "pop_type": s["pop_type"],
        "adm2_pcode": s["adm2_pcode"],
        "adm2_name": s.get("adm2_name", ""),
        "current_coverage_status": coverage_status,
        "current_exclusion_reason": exclusion_reason,
        "recomputed_pct_pop_accessible": f"{pct:.2f}" if pct is not None else "NA",
        "pop_floor_pct": POP_FLOOR_PCT,
        "mechanical_verdict": verdict,
        "flag": flag,
        "N_hh": s.get("N_hh", ""),
        "target_sample": s.get("target_sample", ""),
        "achieved_sample": s.get("achieved_sample", ""),
        "partners_covering": s.get("partners_covering", ""),
    })

with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    w.writeheader()
    w.writerows(results)

flagged = [r for r in results if r["flag"] != "consistent_no_action"]
reinstate = [r for r in results if r["flag"] == "REINSTATEMENT_CANDIDATE"]
new_excl = [r for r in results if r["flag"] == "NEW_EXCLUSION_CANDIDATE"]
no_match = [r for r in results if r["flag"] == "NO_GIS_MATCH_NEEDS_REVIEW"]

print(f"\n{len(results)} in-scope strata checked ({sum(1 for r in results if r['current_exclusion_reason']==EXCLUSION_REASON)} currently excluded for this reason, {sum(1 for r in results if r['current_coverage_status']=='covered')} currently covered).")
print(f"Wrote full audit trail (every in-scope stratum, flagged or not) to {OUT_CSV}\n")

print(f"=== REINSTATEMENT CANDIDATES ({len(reinstate)}) - currently excluded, now recompute at/above the {POP_FLOOR_PCT}% floor ===")
for r in reinstate:
    print(f"  {r['strata_id']} ({r['adm2_name']}): {r['recomputed_pct_pop_accessible']}% accessible, N_hh={r['N_hh']}, target={r['target_sample']}, partners={r['partners_covering']}")

print(f"\n=== NEW-EXCLUSION CANDIDATES ({len(new_excl)}) - currently covered, now recompute BELOW the {POP_FLOOR_PCT}% floor ===")
for r in new_excl:
    print(f"  {r['strata_id']} ({r['adm2_name']}): {r['recomputed_pct_pop_accessible']}% accessible, N_hh={r['N_hh']}, target={r['target_sample']}, achieved={r['achieved_sample']}, partners={r['partners_covering']}")

if no_match:
    print(f"\n=== COULD NOT RECOMPUTE ({len(no_match)}) - no GIS match for this (LGA, pop_type) - needs manual review, not defaulted either direction ===")
    for r in no_match:
        print(f"  {r['strata_id']} ({r['adm2_name']})")

print(f"\n{len(results) - len(flagged)} stratum/strata consistent (mechanical verdict matches current status) - no action needed.")
print("\nNothing in FULL/WORKING was changed by this script - it is read-only. Every flagged stratum above needs Jack's decision (reinstate/exclude, target_sample, partner reassignment), not an automatic apply.")
