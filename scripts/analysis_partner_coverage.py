# ==============================================================================
# Partner coverage layer - join partner_coverage/Partnerscoverage.xlsx onto the
# live sampling frame (output/strata_level_sampling_frame.csv +
# output/stage2_sampling_frame.csv), add coverage_status/exclusion_reason,
# produce FULL + WORKING frames, before/after summaries, and a standalone
# coverage-summary CSV for the ToR narrative.
#
# Standalone analysis script (not part of the numbered 00-08 pipeline, does
# not modify the frozen sampling frame's own outputs - reads them, writes new
# versioned files alongside).
# ==============================================================================
import csv
import difflib
import re
from collections import defaultdict, Counter

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STRATA_CSV = PROJECT_DIR + r"\output\strata_level_sampling_frame.csv"
STAGE2_CSV = PROJECT_DIR + r"\output\stage2_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
OUT_DIR = PROJECT_DIR + r"\output\analysis_partner_coverage"

import os
os.makedirs(OUT_DIR, exist_ok=True)

# In-scope states for this assessment (from the pipeline's own admin1 focus
# lists, 01_sampling_pipeline_main.R) - anything outside this set in the
# coverage file (e.g. Kwara) is out of scope for this MSNA, not a real
# match failure.
IN_SCOPE_STATES = {
    "Adamawa", "Borno", "Yobe",  # NE
    "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto", "Zamfara",  # NW
    "Benue", "Kogi", "Nasarawa", "Niger", "Plateau",  # NC
}


def norm(s):
    if s is None:
        return ""
    s = str(s).strip().lower()
    s = s.replace("/", " ").replace("-", " ")
    # strip every apostrophe-like character (straight, curly, or a mangled
    # replacement character from a source-file encoding issue), not just the
    # ASCII one - "Mai'adua" vs "Mai’adua" vs a corrupted byte should all
    # normalize identically rather than needing a guessed-character mapping.
    s = re.sub(r"[\'‘’ʼ�]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


# ---------------------------------------------------------------------------
# 1. Load master LGA list from the live, verified-current sampling frame
# ---------------------------------------------------------------------------
with open(STRATA_CSV, encoding="utf-8") as f:
    strata_rows = list(csv.DictReader(f))

master_lgas = {}
for r in strata_rows:
    master_lgas[r["adm2_pcode"]] = {
        "region": r["region"], "adm1_pcode": r["adm1_pcode"], "adm1_name": r["adm1_name"],
        "adm2_pcode": r["adm2_pcode"], "adm2_name": r["adm2_name"],
    }
print(f"Master LGA list: {len(master_lgas)} distinct LGAs from strata_level_sampling_frame.csv")

# lookup index: (norm(state), norm(lga)) -> adm2_pcode
lga_index = {}
dupe_keys = defaultdict(list)
for pcode, v in master_lgas.items():
    key = (norm(v["adm1_name"]), norm(v["adm2_name"]))
    if key in lga_index:
        dupe_keys[key].append(pcode)
    lga_index[key] = pcode
if dupe_keys:
    print("WARNING - duplicate normalized (state, LGA) keys in master list:", dupe_keys)

# for fuzzy suggestions: LGA names by state
master_by_state = defaultdict(list)
for v in master_lgas.values():
    master_by_state[v["adm1_name"]].append(v["adm2_name"])

# ---------------------------------------------------------------------------
# 2. Load coverage workbook, all 3 sheets, filter blank/footer rows
# ---------------------------------------------------------------------------
wb = openpyxl.load_workbook(COVERAGE_XLSX, data_only=True)
coverage_rows = []
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    rows = list(ws.iter_rows(values_only=True))
    header = rows[0]
    count_idx = header.index("COUNT")
    for r in rows[1:]:
        if r[2] is None:  # LGA column blank -> footer/summary row
            continue
        state = str(r[1]).strip() if r[1] else None
        lga = str(r[2]).strip() if r[2] else None
        count_val = r[count_idx]
        coverage_rows.append({
            "sheet": sheet_name, "region_raw": r[0], "state": state, "lga": lga,
            "count_raw": count_val,
        })

print(f"\nCoverage file: {len(coverage_rows)} LGA rows across {len(wb.sheetnames)} sheets (after dropping blank/footer rows)")

# out-of-scope rows (state not in this assessment, e.g. Kwara in the NC sheet)
out_of_scope = [r for r in coverage_rows if r["state"] not in IN_SCOPE_STATES]
in_scope_coverage = [r for r in coverage_rows if r["state"] in IN_SCOPE_STATES]
if out_of_scope:
    oos_states = Counter(r["state"] for r in out_of_scope)
    print(f"Out-of-scope rows (state not part of this assessment - ignored, not a match failure): {len(out_of_scope)}")
    print("  states:", dict(oos_states))

# ---------------------------------------------------------------------------
# 3. Match coverage rows to master LGA list
# ---------------------------------------------------------------------------
matched = {}       # adm2_pcode -> coverage row
unmatched_coverage = []  # coverage rows with no master-list match at all

for r in in_scope_coverage:
    key = (norm(r["state"]), norm(r["lga"]))
    pcode = lga_index.get(key)
    if pcode:
        if pcode in matched:
            print(f"WARNING - {r['state']}/{r['lga']} matches an adm2_pcode already matched by another coverage row")
        matched[pcode] = r
    else:
        # fuzzy suggestion within the same state, for manual review only
        candidates = master_by_state.get(r["state"], [])
        suggestion = difflib.get_close_matches(r["lga"], candidates, n=1, cutoff=0.6)
        r["fuzzy_suggestion"] = suggestion[0] if suggestion else None
        unmatched_coverage.append(r)

matched_pcodes = set(matched.keys())
master_pcodes = set(master_lgas.keys())
unmatched_master = master_pcodes - matched_pcodes  # sampling-frame LGAs with NO coverage row at all

print(f"\nMatched: {len(matched)} of {len(master_lgas)} master LGAs")
print(f"Sampling-frame LGAs with NO coverage-file match at all: {len(unmatched_master)}")
unmatched_master_by_state = Counter(master_lgas[p]["adm1_name"] for p in unmatched_master)
print("  by state:", dict(unmatched_master_by_state))

print(f"\nCoverage-file rows (in-scope) that didn't match any sampling-frame LGA: {len(unmatched_coverage)}")
for r in unmatched_coverage:
    print(f"  {r['state']} / {r['lga']!r}  (count={r['count_raw']!r})  fuzzy suggestion: {r.get('fuzzy_suggestion')}")

print(f"\nSampling-frame LGAs with no coverage match, by state+name:")
for p in sorted(unmatched_master, key=lambda p: (master_lgas[p]["adm1_name"], master_lgas[p]["adm2_name"])):
    v = master_lgas[p]
    print(f"  {v['adm1_name']} / {v['adm2_name']} ({p})")

# ---------------------------------------------------------------------------
# 3b. Proposed reconciliation for the 12 high-confidence name-variant
# mismatches (typos / alternate spellings / hyphenation - NOT the Kano gap,
# which is a genuine data gap, not a naming issue and is NOT auto-resolved
# here). Applied as "proposed" matches, clearly flagged, not silently final.
# ---------------------------------------------------------------------------
PROPOSED_RECONCILIATION = {
    # (coverage state, coverage LGA text) -> master adm2_pcode
    ("Zamfara", "Birnin Magaji/Kiyaw"): "NG037003",   # Birnin Magaji
    ("Zamfara", "Kauran Namoda"): "NG037008",          # Kaura Namoda
    # Mai'adua/Jema'a not listed here - now resolved automatically by norm()
    # stripping apostrophe variants, confirmed by rerun below.
    ("Kaduna", "Makarfi"): "NG019018",                 # Markafi (note: distinct spelling, not "Markurdi")
    ("Kaduna", "Zangon-Kataf"): "NG019022",            # Zango-Kataf
    ("Kebbi", "Wasagu"): "NG022019",                   # Wasagu/Danko
    ("Benue", "Otukpo"): "NG007019",                   # Oturkpo
    ("Kogi", "Olamaboro"): "NG023018",                 # Olamabolo
    ("Nasarawa", "Eggon"): "NG026010",                 # Nasarawa-Eggon
    ("Niger", "Munya"): "NG027018",                    # Muya
    ("Plateau", "Barkin Ladi"): "NG032001",            # Barikin Ladi
}

proposed_applied = []
still_unmatched_coverage = []
for r in unmatched_coverage:
    pcode = PROPOSED_RECONCILIATION.get((r["state"], r["lga"]))
    if pcode:
        r["proposed_pcode"] = pcode
        r["proposed_master_name"] = master_lgas[pcode]["adm2_name"]
        matched[pcode] = r
        proposed_applied.append(r)
    else:
        still_unmatched_coverage.append(r)

print(f"\nApplied {len(proposed_applied)} proposed name-variant reconciliations (flagged as 'proposed' in output, not silently final):")
for r in proposed_applied:
    print(f"  {r['state']} / {r['lga']!r}  ->  {r['proposed_master_name']} ({r['proposed_pcode']})  count={r['count_raw']!r}")

if still_unmatched_coverage:
    print(f"\nStill-unmatched coverage rows after proposed reconciliation: {len(still_unmatched_coverage)}")
    for r in still_unmatched_coverage:
        print(f"  {r['state']} / {r['lga']!r}  count={r['count_raw']!r}")

# recompute unmatched_master after proposed reconciliation
matched_pcodes = set(matched.keys())
unmatched_master = master_pcodes - matched_pcodes
print(f"\nAfter proposed reconciliation: {len(unmatched_master)} sampling-frame LGAs still with NO coverage data at all")
unmatched_master_by_state = Counter(master_lgas[p]["adm1_name"] for p in unmatched_master)
print("  by state:", dict(unmatched_master_by_state))

# ---------------------------------------------------------------------------
# 4. Derive coverage_status per LGA
#    covered      : COUNT is a positive integer (>=1)
#    not_covered  : COUNT is False, 0, or blank/None on a matched row - per
#                    the task's own stated logic ("FALSE or blank means no
#                    partner covers it") - OR the LGA is entirely absent
#                    from the coverage file (Kano, currently the only case).
#                    Per explicit user confirmation (2026-07-30): "Kano is a
#                    completely excluded state, no partner is wanting to
#                    cover it, and therefore should be treated same as
#                    others not included." This is a confirmed decision
#                    based on ground knowledge of the partner landscape, NOT
#                    an assumption - the earlier "unresolved_no_data" bucket
#                    (which correctly withheld judgement pending that
#                    confirmation) is retained below only as match_method,
#                    so this is still auditable/distinguishable from an
#                    ordinary FALSE-in-file row if that distinction matters
#                    later.
# ---------------------------------------------------------------------------
coverage_by_pcode = {}

for pcode, v in master_lgas.items():
    if pcode in matched:
        r = matched[pcode]
        count_val = r["count_raw"]
        is_covered = isinstance(count_val, (int, float)) and not isinstance(count_val, bool) and count_val >= 1
        status = "covered" if is_covered else "not_covered"
        method = "proposed" if "proposed_pcode" in r else "exact"
        coverage_by_pcode[pcode] = {
            "coverage_status": status,
            "match_method": method,
            "count_raw": count_val,
            "coverage_note": (
                f"Matched to coverage file as '{r['lga']}' ({r['state']}) - {method} match"
                + (", PROPOSED reconciliation not yet confirmed" if method == "proposed" else "")
            ),
        }
    else:
        coverage_by_pcode[pcode] = {
            "coverage_status": "not_covered",
            "match_method": "no_data_treated_as_not_covered",
            "count_raw": None,
            "coverage_note": "LGA absent from the coverage file entirely (state-wide gap, e.g. Kano). Treated as not_covered per explicit user confirmation 2026-07-30, not a default assumption.",
        }

status_counts = Counter(v["coverage_status"] for v in coverage_by_pcode.values())
print(f"\nFinal LGA coverage_status tally: {dict(status_counts)}")

# ---------------------------------------------------------------------------
# 5. Apply to strata-level frame -> FULL strata frame; derive exclusion_reason
# ---------------------------------------------------------------------------
def exclusion_reason_for(pcode, certainty_excluded):
    reasons = []
    cs = coverage_by_pcode[pcode]["coverage_status"]
    if cs == "not_covered":
        reasons.append("partner_coverage_declined")
    elif cs is None:
        reasons.append("coverage_data_unavailable")
    if certainty_excluded:
        reasons.append("certainty_stratum_below_moe_threshold")
    return "; ".join(reasons) if reasons else "none"


full_strata = []
for r in strata_rows:
    row = dict(r)
    pcode = r["adm2_pcode"]
    cov = coverage_by_pcode[pcode]
    certainty_excluded = r["excluded_infeasible"] == "TRUE"
    row["coverage_status"] = cov["coverage_status"] if cov["coverage_status"] is not None else "unresolved_no_data"
    row["exclusion_reason"] = exclusion_reason_for(pcode, certainty_excluded)
    full_strata.append(row)

strata_fieldnames = list(strata_rows[0].keys()) + ["coverage_status", "exclusion_reason"]

with open(OUT_DIR + r"\NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=strata_fieldnames)
    w.writeheader()
    w.writerows(full_strata)

working_strata = [r for r in full_strata if r["coverage_status"] == "covered" and r["exclusion_reason"] == "none"]
with open(OUT_DIR + r"\NGA_MSNA_2026_strata_level_sampling_frame_v2_WORKING.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=strata_fieldnames)
    w.writeheader()
    w.writerows(working_strata)

print(f"\nFULL strata frame: {len(full_strata)} rows. WORKING strata frame: {len(working_strata)} rows.")

# ---------------------------------------------------------------------------
# 6. Apply to stage2 (household-level) frame -> FULL + WORKING
# ---------------------------------------------------------------------------
with open(STAGE2_CSV, encoding="utf-8") as f:
    stage2_rows = list(csv.DictReader(f))

# per-pcode certainty exclusion lookup (only meaningful for the idp stratum
# at that pcode, since certainty strata are IDP-only - but stage2 rows are
# per-record and already only exist for achieved strata, so no stage2 row
# will ever belong to an excluded_infeasible stratum in the first place;
# kept here for completeness/robustness rather than assumed)
certainty_excluded_by_stratum = {
    (r["pop_type"], r["adm2_pcode"]): (r["excluded_infeasible"] == "TRUE") for r in strata_rows
}

stage2_fieldnames = list(stage2_rows[0].keys()) + ["coverage_status", "exclusion_reason"] if stage2_rows else []
full_stage2 = []
for r in stage2_rows:
    row = dict(r)
    pcode = r["adm2_pcode"]
    cov = coverage_by_pcode.get(pcode)
    if cov is None:
        # Shouldn't happen - every stage2 row's LGA must be in the master
        # list it was derived from - but don't silently assume if it does.
        row["coverage_status"] = "UNKNOWN_LGA_NOT_IN_MASTER_LIST"
        row["exclusion_reason"] = "UNKNOWN"
    else:
        certainty_excluded = certainty_excluded_by_stratum.get((r["pop_type"], pcode), False)
        row["coverage_status"] = cov["coverage_status"] if cov["coverage_status"] is not None else "unresolved_no_data"
        row["exclusion_reason"] = exclusion_reason_for(pcode, certainty_excluded)
    full_stage2.append(row)

with open(OUT_DIR + r"\NGA_MSNA_2026_stage2_sampling_frame_v2_FULL.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=stage2_fieldnames)
    w.writeheader()
    w.writerows(full_stage2)

working_stage2 = [r for r in full_stage2 if r["coverage_status"] == "covered" and r["exclusion_reason"] == "none"]
with open(OUT_DIR + r"\NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=stage2_fieldnames)
    w.writeheader()
    w.writerows(working_stage2)

print(f"FULL stage2 frame: {len(full_stage2)} rows. WORKING stage2 frame: {len(working_stage2)} rows.")
unknown_lga = [r for r in full_stage2 if r["coverage_status"] == "UNKNOWN_LGA_NOT_IN_MASTER_LIST"]
if unknown_lga:
    print(f"WARNING: {len(unknown_lga)} stage2 rows reference an adm2_pcode not in the master LGA list - investigate.")

# ---------------------------------------------------------------------------
# 7. Region-level before/after summary + national totals
# ---------------------------------------------------------------------------
REGIONS = ["NC", "NE", "NW"]
REGION_LABELS = {"NC": "North-Central", "NE": "North-East", "NW": "North-West"}


def region_summary(rows, region):
    rs = [r for r in rows if r["region"] == region]
    non_idp = [r for r in rs if r["pop_type"] == "non_idp"]
    idp = [r for r in rs if r["pop_type"] == "idp"]
    return {
        "region": REGION_LABELS[region],
        "lgas": len(set(r["adm2_pcode"] for r in non_idp)),
        "clusters": sum(int(r["achieved_clusters"]) for r in rs),
        "sample_non_idp": sum(int(r["achieved_sample"]) for r in non_idp),
        "sample_idp": sum(int(r["achieved_sample"]) for r in idp),
    }


def national_summary(rows):
    non_idp = [r for r in rows if r["pop_type"] == "non_idp"]
    idp = [r for r in rows if r["pop_type"] == "idp"]
    return {
        "region": "National Total",
        "lgas": len(set(r["adm2_pcode"] for r in non_idp)),
        "clusters": sum(int(r["achieved_clusters"]) for r in rows),
        "sample_non_idp": sum(int(r["achieved_sample"]) for r in non_idp),
        "sample_idp": sum(int(r["achieved_sample"]) for r in idp),
    }


print("\n" + "=" * 70)
print("REGION-LEVEL SUMMARY: BEFORE (original frame) vs AFTER (coverage cut)")
print("=" * 70)
before_rows_by_region = {}
after_rows_by_region = {}
for region in REGIONS:
    before = region_summary(full_strata, region)
    after = region_summary(working_strata, region)
    before_rows_by_region[region] = before
    after_rows_by_region[region] = after
    total_before = before["sample_non_idp"] + before["sample_idp"]
    total_after = after["sample_non_idp"] + after["sample_idp"]
    print(f"\n{before['region']}:")
    print(f"  BEFORE: LGAs={before['lgas']:>4}  Clusters={before['clusters']:>5}  Non-IDP={before['sample_non_idp']:>6}  IDP={before['sample_idp']:>6}  Total={total_before:>6}")
    print(f"  AFTER : LGAs={after['lgas']:>4}  Clusters={after['clusters']:>5}  Non-IDP={after['sample_non_idp']:>6}  IDP={after['sample_idp']:>6}  Total={total_after:>6}")

nat_before = national_summary(full_strata)
nat_after = national_summary(working_strata)
tb = nat_before["sample_non_idp"] + nat_before["sample_idp"]
ta = nat_after["sample_non_idp"] + nat_after["sample_idp"]
print(f"\nNATIONAL TOTAL:")
print(f"  BEFORE: LGAs={nat_before['lgas']:>4}  Clusters={nat_before['clusters']:>5}  Non-IDP={nat_before['sample_non_idp']:>6}  IDP={nat_before['sample_idp']:>6}  Total={tb:>6}")
print(f"  AFTER : LGAs={nat_after['lgas']:>4}  Clusters={nat_after['clusters']:>5}  Non-IDP={nat_after['sample_non_idp']:>6}  IDP={nat_after['sample_idp']:>6}  Total={ta:>6}")

# ---------------------------------------------------------------------------
# 8. Per-region LGA counts: covered / excluded-for-coverage /
#    excluded-for-certainty / unresolved-no-data - reported as separate,
#    NOT mutually-exclusive tallies (an LGA can be both not_covered and
#    have a certainty-excluded IDP stratum)
# ---------------------------------------------------------------------------
lga_region = {r["adm2_pcode"]: r["region"] for r in strata_rows if r["pop_type"] == "non_idp"}
lga_certainty_excluded = defaultdict(bool)
for r in strata_rows:
    if r["excluded_infeasible"] == "TRUE":
        lga_certainty_excluded[r["adm2_pcode"]] = True

print("\n" + "=" * 70)
print("PER-REGION LGA COUNTS (not mutually exclusive - an LGA can appear in multiple counts)")
print("=" * 70)
region_lga_counts = {}
for region in REGIONS:
    pcodes_in_region = [p for p, r in lga_region.items() if r == region]
    covered = sum(1 for p in pcodes_in_region if coverage_by_pcode[p]["coverage_status"] == "covered")
    excl_coverage = sum(1 for p in pcodes_in_region if coverage_by_pcode[p]["coverage_status"] == "not_covered")
    excl_certainty = sum(1 for p in pcodes_in_region if lga_certainty_excluded[p])
    unresolved = sum(1 for p in pcodes_in_region if coverage_by_pcode[p]["coverage_status"] is None)
    region_lga_counts[region] = {
        "total_lgas": len(pcodes_in_region), "covered": covered, "excluded_for_coverage": excl_coverage,
        "excluded_for_certainty": excl_certainty, "unresolved_no_coverage_data": unresolved,
    }
    print(f"\n{REGION_LABELS[region]} ({len(pcodes_in_region)} LGAs total):")
    print(f"  covered:                  {covered}")
    print(f"  excluded_for_coverage:    {excl_coverage}")
    print(f"  excluded_for_certainty:   {excl_certainty}")
    print(f"  unresolved_no_coverage_data: {unresolved}")

# ---------------------------------------------------------------------------
# 9. Standalone coverage-summary CSV (one row per LGA) for the ToR narrative
# ---------------------------------------------------------------------------
coverage_summary_rows = []
for pcode in sorted(master_lgas, key=lambda p: (master_lgas[p]["region"], master_lgas[p]["adm1_name"], master_lgas[p]["adm2_name"])):
    v = master_lgas[pcode]
    cov = coverage_by_pcode[pcode]
    reasons = []
    if cov["coverage_status"] == "not_covered":
        reasons.append("partner_coverage_declined")
    elif cov["coverage_status"] is None:
        reasons.append("coverage_data_unavailable")
    if lga_certainty_excluded[pcode]:
        reasons.append("certainty_stratum_below_moe_threshold (IDP stratum only)")
    coverage_summary_rows.append({
        "region": REGION_LABELS[v["region"]],
        "state": v["adm1_name"],
        "lga": v["adm2_name"],
        "adm2_pcode": pcode,
        "coverage_status": cov["coverage_status"] if cov["coverage_status"] is not None else "unresolved_no_data",
        "match_method": cov["match_method"],
        "exclusion_reason": "; ".join(reasons) if reasons else "none",
    })

with open(OUT_DIR + r"\NGA_MSNA_2026_coverage_summary_v2.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["region", "state", "lga", "adm2_pcode", "coverage_status", "match_method", "exclusion_reason"])
    w.writeheader()
    w.writerows(coverage_summary_rows)

print(f"\nWrote coverage-summary CSV: {len(coverage_summary_rows)} rows -> NGA_MSNA_2026_coverage_summary_v2.csv")

# stash everything needed for the workbook-building step
import pickle
with open(OUT_DIR + r"\_pipeline_state.pkl", "wb") as f:
    pickle.dump({
        "full_strata": full_strata, "working_strata": working_strata,
        "strata_fieldnames": strata_fieldnames,
        "coverage_summary_rows": coverage_summary_rows,
        "before_rows_by_region": before_rows_by_region, "after_rows_by_region": after_rows_by_region,
        "nat_before": nat_before, "nat_after": nat_after,
        "region_lga_counts": region_lga_counts,
        "unmatched_master": sorted(unmatched_master, key=lambda p: (master_lgas[p]["adm1_name"], master_lgas[p]["adm2_name"])),
        "master_lgas": master_lgas,
        "proposed_applied": proposed_applied,
        "still_unmatched_coverage": still_unmatched_coverage,
        "out_of_scope": out_of_scope,
    }, f)

print("\nDONE - pipeline state stashed for workbook-building step.")
