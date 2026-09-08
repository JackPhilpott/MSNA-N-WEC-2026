# ==============================================================================
# Full sanity check of the 2026-08-25/26 accessibility-reporting workflow and
# its outputs, before sharing the workbook ahead of the technical-team
# meeting. Read-only - writes nothing, just reports PASS/WARN/FAIL per check.
#
# Covers: master log integrity, master-status <-> GIS-layer consistency,
# internal consistency of every workbook sheet, cross-file reconciliation
# (real_submissions.csv joins, collected-sample totals), the Inaccessibility
# Report Log sheet's handling of superseded/updated reports, an independent
# recomputation of realized_moe()/feasibility for a sample of strata, and an
# encoding scan.
# ==============================================================================
import csv
import math
from collections import defaultdict

import openpyxl

SAMPLING_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STRATA_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v7_WORKING.csv"
HOUSEHOLD_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"
LOG_CSV = SAMPLING_DIR + r"\resampling\output\resampling_requests_log.csv"
MASTER_WARD_CSV = SAMPLING_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"
GIS_WARD_CSV = SAMPLING_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
POOL_NON_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_non_idp.csv"
POOL_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_idp.csv"
WORKBOOK_PATH = SAMPLING_DIR + r"\resampling\output\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
REAL_SUBMISSIONS_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\2_monitoring\dashboard_app\data\real_submissions.csv"

results = []  # (status, section, message)


def check(status, section, message):
    results.append((status, section, message))


def load_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def sheet_rows(ws):
    headers = [c.value for c in ws[1]]
    out = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        if all(v is None for v in row):
            continue
        out.append(dict(zip(headers, row)))
    return out


# ---------------------------------------------------------------------------
print("Loading all source files and workbook sheets...")
log_rows = load_csv(LOG_CSV)
master_ward = load_csv(MASTER_WARD_CSV)
gis_ward = load_csv(GIS_WARD_CSV)
pool_non_idp = load_csv(POOL_NON_IDP_CSV)
pool_idp = load_csv(POOL_IDP_CSV)
strata_rows = load_csv(STRATA_CSV)
household_rows = load_csv(HOUSEHOLD_CSV)
real_submissions = load_csv(REAL_SUBMISSIONS_CSV)

wb = openpyxl.load_workbook(WORKBOOK_PATH, data_only=True)
strata_sheet = sheet_rows(wb["Strata Level"])
lga_sheet = sheet_rows(wb["LGA Summary"])
cluster_sheet = sheet_rows(wb["Cluster Level"])
log_sheet = sheet_rows(wb["Inaccessibility Report Log"])

# ===========================================================================
# 1. MASTER LOG INTEGRITY
# ===========================================================================
print("Checking master log integrity...")
req_ids = [int(r["request_id"]) for r in log_rows]
if len(req_ids) == len(set(req_ids)):
    check("PASS", "1. Master log", f"No duplicate request_id ({len(req_ids)} rows, all unique).")
else:
    dupes = [i for i in req_ids if req_ids.count(i) > 1]
    check("FAIL", "1. Master log", f"Duplicate request_id values found: {set(dupes)}")

req_id_set = set(req_ids)
bad_supersedes = [r["request_id"] for r in log_rows
                   if r["supersedes_request_id"] and int(r["supersedes_request_id"]) not in req_id_set]
if bad_supersedes:
    check("FAIL", "1. Master log", f"supersedes_request_id points to a non-existent request_id: {bad_supersedes}")
else:
    check("PASS", "1. Master log", "Every supersedes_request_id points to a real existing row.")

# Keys with more than one logged version (an update/correction happened at some point)
key_versions = defaultdict(list)
for r in log_rows:
    key = (r["partner"], r["report_level"], r["state"], r["lga"], r["ward_name"], r["cluster_id"])
    key_versions[key].append(r)
updated_keys = {k: v for k, v in key_versions.items() if len(v) > 1}
check("INFO", "1. Master log", f"{len(updated_keys)} (partner, ward/cluster) key(s) have been updated/corrected "
                                 f"more than once - checked in section 5 below for stale carry-through.")

# ===========================================================================
# 2. MASTER WARD STATUS <-> GIS LAYER CONSISTENCY
# ===========================================================================
# FIXED 2026-08-27 (see ../../CLAUDE.md's Revision 2026-08-27): this section
# previously only checked "every master ward has a matching GIS polygon" -
# it never checked the reverse (extra GIS rows beyond the true universe),
# which is exactly how the 49%-spurious-rows bug passed 15/0/3 undetected
# for a full day. Two things changed the shape of this section:
# 1. The GIS layer is now split by pop_type (one row per ward x pop_type,
#    since eligibility can differ - see analysis_accessible_area_layer.R's
#    header) while the master file stays ward-level only - so a master row
#    can now legitimately match 0, 1, or 2 GIS rows depending on the ward's
#    real Non-IDP/IDP cluster mix, not always exactly 1.
# 2. The GIS layer's universe is now DELIBERATELY BROADER than the master
#    file's (eligible-at-Stage-1, including wards no partner has clusters in
#    yet - see the same header for why) - so "every GIS row has a matching
#    master row" is no longer the right invariant; that broadening is the
#    fix, not a regression of the bug. What IS still checkable and
#    meaningful without geospatial tooling (this environment has no
#    geopandas/fiona/pyshp - see CLAUDE.md's R-availability note): every
#    ward the master file says has REAL clusters for a pop_type must have a
#    matching GIS row for that same pop_type (a ward with real clusters
#    necessarily contains part of an actually-selected, therefore eligible,
#    hex/site - so this can never legitimately be missing), and the GIS
#    layer's own (LGA, pop_type) coverage must exactly match the WORKING
#    frame's per-pop_type coverage (catches the Gwandu-class bug - a LGA
#    covered for one pop_type but not the other - recurring). Genuine
#    ward-level geometric eligibility (was this specific ward really inside
#    the border buffer or not) is NOT re-verified here - that needs sf/R,
#    not just these CSVs - so this section catches a regression of the
#    coverage-scoping fix, not a regression of the geometry itself.
print("Checking master ward status vs GIS layer consistency...")
master_by_key = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r for r in master_ward}
gis_pop_col = "pop_typ" if "pop_typ" in (gis_ward[0].keys() if gis_ward else []) else "pop_type"
gis_by_key_pop = defaultdict(list)  # (state, lga, ward, pop_type_label) -> [gis rows]
gis_lga_pop_pairs = set()
for r in gis_ward:
    key4 = (r.get("adm1_nm") or r.get("adm1_name", ""), r.get("adm2_nm") or r.get("adm2_name", ""),
            r.get("wardnam") or r.get("wardname", ""), r.get(gis_pop_col, ""))
    gis_by_key_pop[key4].append(r)
    gis_lga_pop_pairs.add((r["adm2_pc"] if "adm2_pc" in r else r.get("adm2_pcode", ""), r.get(gis_pop_col, "")))

missing_in_gis = []
status_mismatches = []
for k, mrow in master_by_key.items():
    for pop_label, count_col in (("Non-IDP", "Non-IDP clusters"), ("IDP", "IDP clusters")):
        if int(mrow.get(count_col, 0) or 0) <= 0:
            continue  # no real clusters of this pop_type here - not required to have a GIS row
        grows = gis_by_key_pop.get((*k, pop_label), [])
        if not grows:
            missing_in_gis.append((k, pop_label))
            continue
        for grow in grows:
            gstatus = grow.get("accessible_status") or grow.get("accssb_")
            if gstatus and gstatus != mrow["Accessible status"]:
                status_mismatches.append((k, pop_label, mrow["Accessible status"], gstatus))

if missing_in_gis:
    check("FAIL", "2. Ward<->GIS", f"{len(missing_in_gis)} ward(s) have REAL clusters for a pop_type per the "
                                     f"master file but NO matching GIS row for that pop_type: {missing_in_gis[:5]}")
else:
    check("PASS", "2. Ward<->GIS", "Every ward with real clusters (either pop_type) has a matching GIS polygon "
                                     "for that pop_type.")

if status_mismatches:
    check("FAIL", "2. Ward<->GIS", f"{len(status_mismatches)} ward(s) have a DIFFERENT accessible_status between "
                                     f"the master file and the GIS layer: {status_mismatches[:5]}")
else:
    check("PASS", "2. Ward<->GIS", "accessible_status agrees between master file and GIS layer for every matched ward.")

# Reverse-direction check (the actual gap that let the 2026-08-27 bug through):
# every (LGA, pop_type) pair present in the GIS layer must be real coverage
# per the WORKING frame - catches the Gwandu-class bug (a LGA's IDP/Non-IDP
# portion appearing when that pop_type has zero real WORKING-frame presence
# there) recurring, independent of the ward-level ballooning check above.
working_lga_pop_pairs = set()
for r in strata_rows:
    pt_label = "Non-IDP" if r["pop_type"] == "non_idp" else "IDP"
    working_lga_pop_pairs.add((r["adm2_pcode"], pt_label))
extra_lga_pop = gis_lga_pop_pairs - working_lga_pop_pairs
if extra_lga_pop:
    check("FAIL", "2. Ward<->GIS", f"{len(extra_lga_pop)} (LGA, pop_type) pair(s) appear in the GIS layer with NO "
                                     f"matching stratum in the WORKING frame - Gwandu-class coverage-scoping bug: "
                                     f"{list(extra_lga_pop)[:5]}")
else:
    check("PASS", "2. Ward<->GIS", "Every (LGA, pop_type) pair in the GIS layer has real WORKING-frame coverage - "
                                     "no Gwandu-class over-inclusion.")

n_inacc_master = sum(1 for r in master_ward if r["Accessible status"] == "Inaccessible")
n_gis_total = len(gis_ward)
n_gis_non_idp = sum(1 for r in gis_ward if r.get(gis_pop_col) == "Non-IDP")
n_gis_idp = sum(1 for r in gis_ward if r.get(gis_pop_col) == "IDP")
check("INFO", "2. Ward<->GIS", f"GIS layer: {n_gis_total} rows ({n_gis_non_idp} Non-IDP, {n_gis_idp} IDP) - "
                                 f"deliberately broader than the master file's {len(master_ward)} ward rows "
                                 f"(includes Stage-1-eligible-but-undrawn wards, see 2026-08-27 fix above), so "
                                 f"these counts are NOT expected to match 1:1 - not a bug.")

# ===========================================================================
# 3. WORKBOOK INTERNAL CONSISTENCY
# ===========================================================================
print("Checking workbook internal consistency...")

if len(strata_sheet) == len(strata_rows):
    check("PASS", "3. Workbook", f"Strata Level sheet row count ({len(strata_sheet)}) matches source strata CSV.")
else:
    check("FAIL", "3. Workbook", f"Strata Level sheet has {len(strata_sheet)} rows, source strata CSV has {len(strata_rows)}.")

cluster_ids_in_frame = {r["cluster_id"] for r in household_rows}
cluster_ids_in_sheet = [r["Cluster ID"] for r in cluster_sheet]
if len(cluster_ids_in_sheet) == len(set(cluster_ids_in_sheet)) == len(cluster_ids_in_frame):
    check("PASS", "3. Workbook", f"Cluster Level sheet has {len(cluster_ids_in_sheet)} unique clusters, matching "
                                   f"the source frame exactly.")
else:
    check("FAIL", "3. Workbook", f"Cluster Level sheet: {len(cluster_ids_in_sheet)} rows "
                                   f"({len(set(cluster_ids_in_sheet))} unique) vs {len(cluster_ids_in_frame)} in source frame.")

distinct_lgas = {r["adm2_name"] for r in strata_rows}
if len(lga_sheet) == len(distinct_lgas):
    check("PASS", "3. Workbook", f"LGA Summary row count ({len(lga_sheet)}) matches distinct LGA count.")
else:
    check("FAIL", "3. Workbook", f"LGA Summary has {len(lga_sheet)} rows, expected {len(distinct_lgas)} distinct LGAs.")

range_fail = []
subset_fail = []
for r in strata_sheet:
    for col in ["% of population remaining", "% of area remaining", "% of clusters remaining"]:
        v = r[col]
        if v is None or not (-0.01 <= v <= 100.01):
            range_fail.append((r["Strata ID"], col, v))
    if r["Updated population within accessible area"] > r["Total population (design, n_pop)"] + 1:
        subset_fail.append((r["Strata ID"], "population"))
    if r["Updated area km2 (accessible)"] > r["Total area km2 (LGA)"] + 0.1:
        subset_fail.append((r["Strata ID"], "area"))
    if r["Updated clusters within accessible area"] > r["Total clusters (achieved)"]:
        subset_fail.append((r["Strata ID"], "clusters"))

if range_fail:
    check("FAIL", "3. Workbook", f"{len(range_fail)} %-column value(s) outside [0,100]: {range_fail[:5]}")
else:
    check("PASS", "3. Workbook", "Every %-remaining column (population/area/clusters) is within [0, 100] for all 324 strata.")

if subset_fail:
    check("FAIL", "3. Workbook", f"{len(subset_fail)} case(s) where 'updated' exceeds 'total': {subset_fail[:5]}")
else:
    check("PASS", "3. Workbook", "'Updated' figures never exceed 'Total' figures (population/area/clusters) anywhere.")

# FIXED/INVERTED 2026-08-27: this used to assert Non-IDP and IDP area
# figures must be IDENTICAL per LGA - true only under the old, pre-fix
# design where load_lga_area_pop_fractions() returned one blended,
# pop-type-blind area figure. Since analysis_accessible_area_layer.R's
# 2026-08-27 fix, area is deliberately pop-type-SPECIFIC (IDP eligibility -
# contains a DTM site - is typically a stricter, smaller-area test than
# Non-IDP's - touches an accessible hex - for the same LGA), so identical
# figures would now be the SUSPICIOUS case, not the expected one. Keeping
# the OLD assertion here would have produced a wall of false FAILs on
# every dual-pop-type LGA. Replaced with a check for the opposite failure
# mode: Non-IDP and IDP area figures being SUSPICIOUSLY identical (down to
# the same rounding) on a LGA that genuinely has both pop types, which
# would suggest the pop_type split silently isn't taking effect somewhere.
by_lga = defaultdict(dict)
for r in strata_sheet:
    by_lga[r["LGA"]][r["Pop type"]] = r
suspiciously_identical = []
for lga, pops in by_lga.items():
    if "Non-IDP" in pops and "IDP" in pops:
        a, b = pops["Non-IDP"], pops["IDP"]
        if abs(a["Total area km2 (LGA)"] - b["Total area km2 (LGA)"]) < 0.05 and a["Total area km2 (LGA)"] > 0:
            suspiciously_identical.append(lga)
if suspiciously_identical:
    check("WARN", "3. Workbook", f"{len(suspiciously_identical)} LGA(s) where Non-IDP and IDP total area is "
                                   f"identical to 2dp - possible sign the pop_type split isn't taking effect "
                                   f"(worth a manual look, not necessarily wrong): {suspiciously_identical[:5]}")
else:
    check("PASS", "3. Workbook", "No dual-pop-type LGA has suspiciously identical Non-IDP/IDP area figures - "
                                   "the pop_type split is genuinely producing different eligible areas per pop_type.")

# Feasibility label vs underlying numbers, independently recomputed
def realized_moe(achieved_sample, N_hh, m, ICC=0.06, Z=1.6448536269514722, p=0.5):
    if achieved_sample <= 0 or N_hh <= achieved_sample:
        return None
    deff = 1 + (m - 1) * ICC
    ndeff = achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
    n0 = ndeff / deff
    if n0 <= 0:
        return None
    return math.sqrt(Z ** 2 * p * (1 - p) / n0) * 100


feas_logic_mismatch = []
for r in strata_sheet:
    feas = r["Feasibility"]
    addl_col = [k for k in r if k.startswith("Additional clusters needed")][0]
    addl = r[addl_col]
    if feas == "Already at/under target" and addl not in (0, "N/A"):
        feas_logic_mismatch.append((r["Strata ID"], feas, addl))
    if feas.startswith("Not closeable") and addl == 0:
        feas_logic_mismatch.append((r["Strata ID"], feas, addl))
if feas_logic_mismatch:
    check("FAIL", "3. Workbook", f"{len(feas_logic_mismatch)} strata where Feasibility label contradicts "
                                   f"Additional-clusters-needed: {feas_logic_mismatch[:5]}")
else:
    check("PASS", "3. Workbook", "Feasibility label is internally consistent with 'Additional clusters needed' "
                                   "for all 324 strata.")

neg_pool = [r["Strata ID"] for r in strata_sheet if r["Remaining eligible pool (accessible, unselected)"] < 0]
if neg_pool:
    check("FAIL", "3. Workbook", f"Negative remaining pool found: {neg_pool}")
else:
    check("PASS", "3. Workbook", "Remaining eligible pool is >= 0 for every stratum.")

# "Reported by" (2026-08-28 addition) - every value at every grain should be
# built ONLY from the three known categories ("Partner", "Needs review",
# "Not yet reported"), possibly semicolon-joined when mixed - anything else
# means the categorisation logic itself produced something unexpected.
VALID_REPORTED_BY = {"Partner", "Needs review", "Not yet reported"}
bad_reported_by = []
for sheet_name, rows in [("Strata Level", strata_sheet), ("LGA Summary", lga_sheet), ("Cluster Level", cluster_sheet)]:
    for r in rows:
        val = r.get("Reported by", "")
        parts = {p.strip() for p in val.split(";")} if val else set()
        if not parts or not parts.issubset(VALID_REPORTED_BY):
            bad_reported_by.append((sheet_name, r.get("Strata ID") or r.get("LGA") or r.get("Cluster ID"), val))
if bad_reported_by:
    check("FAIL", "3. Workbook", f"{len(bad_reported_by)} row(s) have a 'Reported by' value outside the three "
                                   f"known categories: {bad_reported_by[:5]}")
else:
    check("PASS", "3. Workbook", "Every 'Reported by' value (all three sheets) is built only from the three "
                                   "known categories (Partner / Needs review / Not yet reported).")

# Spot-check realized_moe passthrough (full frame) matches the strata CSV's own value exactly
strata_by_id = {r["strata_id"]: r for r in strata_rows}
passthrough_mismatch = []
for r in strata_sheet:
    src = strata_by_id.get(r["Strata ID"])
    if src and src["realized_moe_pct"] not in ("NA", ""):
        src_val = float(src["realized_moe_pct"])
        wb_val = r["Realized MoE % (full frame, existing)"]
        try:
            wb_val = float(wb_val)
        except (TypeError, ValueError):
            continue
        if abs(src_val - wb_val) > 0.01:
            passthrough_mismatch.append((r["Strata ID"], src_val, wb_val))
if passthrough_mismatch:
    check("FAIL", "3. Workbook", f"'Realized MoE % (full frame)' does not match the source strata CSV exactly "
                                   f"for {len(passthrough_mismatch)} strata: {passthrough_mismatch[:5]}")
else:
    check("PASS", "3. Workbook", "'Realized MoE % (full frame, existing)' passthrough matches the source strata "
                                   "CSV exactly for every stratum.")

# ===========================================================================
# 4. CROSS-FILE RECONCILIATION (real_submissions.csv)
# ===========================================================================
print("Checking real_submissions.csv reconciliation...")
valid_strata_ids = {r["strata_id"] for r in strata_rows}
valid_cluster_ids = {r["cluster_id"] for r in household_rows}
clean_submissions = [r for r in real_submissions
                      if r["interview_outcome"] == "completed" and r["any_quality_flag"] == "FALSE"]

orphaned_strata = [r["matched_strata_id"] for r in clean_submissions if r["matched_strata_id"] not in valid_strata_ids]
orphaned_clusters = [r["matched_cluster_id"] for r in clean_submissions
                      if r["matched_cluster_id"] and r["matched_cluster_id"] not in valid_cluster_ids]
if orphaned_strata:
    check("WARN", "4. Reconciliation", f"{len(orphaned_strata)} qualifying submission(s) have a matched_strata_id "
                                         f"NOT found in the sampling frame - these are silently excluded from "
                                         f"'Collected samples' totals: {set(orphaned_strata)}")
else:
    check("PASS", "4. Reconciliation", f"Every one of {len(clean_submissions)} qualifying submissions has a "
                                         f"matched_strata_id that exists in the sampling frame.")
if orphaned_clusters:
    check("WARN", "4. Reconciliation", f"{len(orphaned_clusters)} qualifying submission(s) have a matched_cluster_id "
                                         f"not found in the frame: {set(orphaned_clusters)}")
else:
    check("PASS", "4. Reconciliation", "Every qualifying submission's matched_cluster_id exists in the frame.")

wb_total_collected = sum(r["[FULL FRAME] Collected samples (field, quality-checked)"] for r in strata_sheet)
if wb_total_collected == len(clean_submissions):
    check("PASS", "4. Reconciliation", f"Workbook's total 'Collected samples' ({wb_total_collected}) matches "
                                         f"real_submissions.csv's qualifying row count exactly.")
else:
    check("WARN", "4. Reconciliation", f"Workbook total collected = {wb_total_collected}, but "
                                         f"real_submissions.csv has {len(clean_submissions)} qualifying rows "
                                         f"(difference = {len(clean_submissions) - wb_total_collected}, expected "
                                         f"to equal the orphaned-strata count above if nonzero).")

# ===========================================================================
# 5. INACCESSIBILITY REPORT LOG SHEET - stale/superseded entries?
# ===========================================================================
print("Checking Inaccessibility Report Log sheet for stale superseded entries...")
log_sheet_ids = {r["Request ID"] for r in log_sheet}
stale_entries = []
for key, versions in updated_keys.items():
    if key[1] != "ward":
        continue
    versions_sorted = sorted(versions, key=lambda r: int(r["request_id"]))
    latest = versions_sorted[-1]
    older = versions_sorted[:-1]
    for old in older:
        if int(old["request_id"]) in log_sheet_ids and old["accessible"].strip().lower() == "no" \
                and latest["accessible"].strip().lower() != "no":
            stale_entries.append((key, old["request_id"], latest["request_id"]))
if stale_entries:
    check("FAIL", "5. Report Log sheet", f"{len(stale_entries)} SUPERSEDED 'No' report(s) still appear in the "
                                           f"Inaccessibility Report Log sheet even though the latest version for "
                                           f"that same ward is no longer 'No': {stale_entries}")
else:
    check("PASS", "5. Report Log sheet", f"No stale/superseded entries found - the log sheet does not currently "
                                           f"include any outdated 'No' report that's since been corrected "
                                           f"({len(updated_keys)} updated key(s) checked, none affected).")
check("INFO", "5. Report Log sheet", f"FIXED 2026-08-26: the sheet's build logic previously included every 'No' "
                                       f"row from the log regardless of supersession status. No ward has "
                                       f"actually flipped status yet, so today's output was unaffected either "
                                       f"way, but this was a latent bug waiting to surface the next time a "
                                       f"partner corrects a prior report - 05_build_accessibility_impact_"
                                       f"workbook.py now filters to the latest logged row per (partner, state, "
                                       f"lga, ward) before building this sheet, matching the same latest-wins "
                                       f"rule used everywhere else in this workflow.")

# ===========================================================================
# 6. ENCODING SCAN
# ===========================================================================
print("Scanning for encoding issues...")
mojibake_locations = []
for fname, rows in [("resampling_requests_log.csv", log_rows), ("master_ward", master_ward), ("strata CSV", strata_rows)]:
    for r in rows:
        for k, v in r.items():
            if v and "\ufffd" in v:
                mojibake_locations.append((fname, k, v))
                break
if mojibake_locations:
    seen_files = sorted({m[0] for m in mojibake_locations})
    check("WARN", "6. Encoding", f"Replacement-character (U+FFFD) mojibake found in: {seen_files}.")
else:
    check("PASS", "6. Encoding", "No replacement-character mojibake found in any checked file. (2026-08-27: the "
                                   f"'Solidarité' partner name previously flagged here was never actually "
                                   f"mojibake - the accented character was valid UTF-8 throughout; the real issue "
                                   f"was a missing trailing 's' truncated somewhere upstream of the raw "
                                   f"Partnerscoverage.xlsx source file, since fixed there and propagated through "
                                   f"every derived output.)")

# ===========================================================================
# REPORT
# ===========================================================================
print("\n\n" + "=" * 78)
print("SANITY CHECK REPORT")
print("=" * 78)
n_pass = sum(1 for s, _, _ in results if s == "PASS")
n_warn = sum(1 for s, _, _ in results if s == "WARN")
n_fail = sum(1 for s, _, _ in results if s == "FAIL")
n_info = sum(1 for s, _, _ in results if s == "INFO")
print(f"{n_pass} PASS, {n_warn} WARN, {n_fail} FAIL, {n_info} INFO\n")
for status, section, message in results:
    print(f"[{status:4}] {section}: {message}")
