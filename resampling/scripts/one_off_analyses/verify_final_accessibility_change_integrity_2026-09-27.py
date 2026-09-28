# ==============================================================================
# 2026-09-27: my own integrity + tie-out checks after the FINAL accessibility change (FACT/Isa 38 removals, Street Child Kekeno,
# CRS 9 Shagari wards). READ-ONLY. Adapted from verify_conpad_change_integrity_2026-09-26.py (staged-package sections dropped: the
# staged set is superseded and nothing is staged tonight).
# Writes one results file: resampling/output/final_accessibility_change_result_2026-09-27/INTEGRITY_CHECKS.txt
# ==============================================================================
import csv
import collections
import hashlib
import os

B = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = B + r"\1_sampling"
DC = S + r"\output\data\data_collection"
SNAP = DC + r"\_archive\2026-09-26_pre_final_accessibility"
PRE = S + r"\resampling\output\_archive_accessibility_pre_final_2026-09-26"
OUT = S + r"\resampling\output\final_accessibility_change_result_2026-09-27\INTEGRITY_CHECKS.txt"
STG = S + r"\resampling\output\staged_packages_2026-09-26_conpad_accessibility"


def lp(p):
    p = os.path.abspath(p)
    return p if p.startswith("\\\\?\\") else "\\\\?\\" + p


def rd(p):
    with open(lp(p), encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def md5(p):
    h = hashlib.md5()
    with open(lp(p), "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


lines, ok_all = [], True


def check(name, ok, detail=""):
    global ok_all
    ok_all &= bool(ok)
    lines.append(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" | {detail}" if detail else ""))
    print(lines[-1])


V = "v13"
F = lambda kind, tier: f"{DC}\\NGA_MSNA_2026_{kind}_{V}_{tier}.csv"
full = rd(F("stage2_sampling_frame", "FULL")); work = rd(F("stage2_sampling_frame", "WORKING"))
swork = rd(F("strata_level_sampling_frame", "WORKING"))
full_by = {r["survey_id"]: r for r in full}

# 1 master: exactly the 48 planned flips --------------------------------------------------------------------
master = rd(S + r"\resampling\output\master_accessibility_status_ward_level.csv")
mstat = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"] for r in master}
m0 = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"] for r in rd(PRE + r"\master_accessibility_status_ward_level.csv")}
fl = [k for k in mstat if mstat[k] != m0[k]]
check("master ward status: same 4,023 keys; exactly 48 status changes vs the pre-change master, all Accessible->Inaccessible",
      set(mstat) == set(m0) and len(mstat) == 4023 and len(fl) == 48 and all(m0[k] == "Accessible" and mstat[k] == "Inaccessible" for k in fl))
check("master: 'Partners covering this LGA-ward portion' unchanged in every row",
      {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Partners covering this LGA-ward portion"] for r in master} ==
      {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Partners covering this LGA-ward portion"] for r in rd(PRE + r"\master_accessibility_status_ward_level.csv")})
log0 = len(rd(PRE + r"\resampling_requests_log.csv")); log1 = len(rd(S + r"\resampling\output\resampling_requests_log.csv"))
check("requests log grew by exactly 48 rows (FACT 38, CRS 9, Street Child 1)", log1 - log0 == 48, f"{log0} -> {log1}")
check("cluster overlay unchanged (no cluster-level report in this change)", md5(S + r"\resampling\output\cluster_accessibility_overlay.csv") == md5(PRE + r"\cluster_accessibility_overlay.csv"))

# 2 frame files vs the snapshot -------------------------------------------------------------------------------
check("strata FULL byte-identical to pre-change snapshot", md5(F("strata_level_sampling_frame", "FULL")) == md5(SNAP + f"\\NGA_MSNA_2026_strata_level_sampling_frame_{V}_FULL.csv"))
f0 = rd(SNAP + f"\\NGA_MSNA_2026_stage2_sampling_frame_{V}_FULL.csv")
check("stage2 FULL: same rows (132,108), same keys, same 58 columns", len(f0) == len(full) == 132108 and [r["survey_id"] for r in f0] == [r["survey_id"] for r in full] and list(f0[0]) == list(full[0]) and len(full[0]) == 58)
chg = collections.Counter(); flips = collections.Counter()
for a, b in zip(f0, full):
    for c in a:
        if a[c] != b[c]:
            chg[c] += 1
            if c == "ward_accessible_status":
                flips[(a[c], b[c], b["adm1_name"], b["adm2_name"], b["adm3_name"])] += 1
check("stage2 FULL: the ONLY column that changed is ward_accessible_status", set(chg) == {"ward_accessible_status"}, f"{dict(chg)}")
flipped_keys = {(k[2], k[3], k[4]) for k in flips}
full_portions = {(r["adm1_name"], r["adm2_name"], r["adm3_name"]) for r in full}
check("stage2 FULL: every changed cell is Accessible->Inaccessible and sits in one of the 48 flipped master portions",
      all(k[0] == "Accessible" and k[1] == "Inaccessible" for k in flips) and flipped_keys <= set(fl), f"{sum(flips.values())} cells in {len(flipped_keys)} portions")
check("stage2 FULL: EVERY flipped master portion that has FULL rows was changed (none missed); the rest have no FULL rows",
      {k for k in fl if k in full_portions} == flipped_keys, f"{len(flipped_keys)} with FULL rows, {len(set(fl) - flipped_keys)} without")
check("WORKING has 58 columns, identical column names to FULL", list(work[0]) == list(full[0]) and len(work[0]) == 58)
check("WORKING is a strict subset of FULL and every WORKING row equals its FULL row on all 58 columns",
      all(r["survey_id"] in full_by and all(r[c] == full_by[r["survey_id"]][c] for c in r) for r in work), f"{len(work)} rows")
check("WORKING has no row in an Inaccessible ward", not any(r["ward_accessible_status"] == "Inaccessible" for r in work))
check("WORKING has 38,105 rows / 3,256 clusters", len(work) == 38105 and len({r["cluster_id"] for r in work}) == 3256)
w0 = rd(SNAP + f"\\NGA_MSNA_2026_stage2_sampling_frame_{V}_WORKING.csv")
check("WORKING change is REMOVALS ONLY (no row added, no row edited): 930 rows removed", {r["survey_id"] for r in work} <= {r["survey_id"] for r in w0} and len(w0) - len(work) == 930)
sw0 = rd(SNAP + f"\\NGA_MSNA_2026_strata_level_sampling_frame_{V}_WORKING.csv")
check("strata WORKING: same 307 strata, same columns; only achieved_clusters/achieved_sample/realized_moe_pct changed",
      [r["strata_id"] for r in sw0] == [r["strata_id"] for r in swork] and list(sw0[0]) == list(swork[0]) and
      {c for a, b in zip(sw0, swork) for c in a if a[c] != b[c]} <= {"achieved_clusters", "achieved_sample", "realized_moe_pct"})

# 3 master vs FULL and overlay vs WORKING ---------------------------------------------------------------------
bad = [r["survey_id"] for r in full if r["ward_accessible_status"] != mstat.get((r["adm1_name"], r["adm2_name"], r["adm3_name"]), "Accessible")]
check("every FULL row's ward_accessible_status equals the master ward status (unmatched = Accessible)", not bad, f"{len(bad)} mismatches")
ov = {r["cluster_id"] for r in rd(S + r"\resampling\output\cluster_accessibility_overlay.csv")}
tc = {r["cluster_id"] for r in rd(S + r"\resampling\output\target_correction_dropped_clusters.csv")}
wc = {r["cluster_id"] for r in work}
check("no WORKING cluster is in the cluster overlay or the target-correction drop list", not (wc & ov) and not (wc & tc), f"overlay {len(ov)}, drop list {len(tc)}")
check("Shagari (Sokoto) has no row left in WORKING (both pop types: every ward portion with clusters is Inaccessible)",
      not [r for r in work if r["adm1_name"] == "Sokoto" and r["adm2_name"] == "Shagari"])

# 4 mirrors and stamp -----------------------------------------------------------------------------------------
mirrors = [B + r"\2_monitoring\input_data\sampling_frame", B + r"\2_monitoring\dashboard_app\input_data\sampling_frame"]
for fn_ in [f"NGA_MSNA_2026_stage2_sampling_frame_{V}_FULL.csv", f"NGA_MSNA_2026_stage2_sampling_frame_{V}_WORKING.csv", f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_FULL.csv",
            f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_WORKING.csv", "_frame_version.txt"]:
    check(f"mirror x3 identical: {fn_[:60]}", len({md5(DC + "\\" + fn_)} | {md5(m + "\\" + fn_) for m in mirrors}) == 1)
for fn_ in ("master_accessibility_status_ward_level.csv", "master_accessibility_status_lga_level.csv"):
    ms = [B + r"\2_monitoring\input_data\accessibility", B + r"\2_monitoring\dashboard_app\input_data\accessibility"]
    check(f"mirror x3 identical: {fn_}", len({md5(S + "\\resampling\\output\\" + fn_)} | {md5(m + "\\" + fn_) for m in ms}) == 1)
stamp = dict(l.split(": ", 1) for l in open(lp(DC + r"\_frame_version.txt"), encoding="utf-8").read().splitlines() if ": " in l)
check("_frame_version.txt records the current WORKING and strata WORKING md5", stamp["working_csv_md5"] == md5(F("stage2_sampling_frame", "WORKING")) and stamp["strata_working_csv_md5"] == md5(F("strata_level_sampling_frame", "WORKING")) and stamp["working_csv_rows"] == str(len(work)))

# 5 data basis unchanged ---------------------------------------------------------------------------------------
real = B + r"\2_monitoring\data\real_submissions.csv"
check("real_submissions.csv is still the export the change was built on (md5 7499f647...)", md5(real).startswith("7499f647"), md5(real)[:8])

# 6 live partner folders untouched by me ----------------------------------------------------------------------
if os.path.exists(lp(STG + r"\workbooks\SEEDED_live_copies_md5.txt")):
    seeded = {l.split("  ")[2]: l.split("  ")[0] for l in open(lp(STG + r"\workbooks\SEEDED_live_copies_md5.txt"), encoding="utf-8").read().splitlines() if l.strip()}
    LIVE = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
    moved = [p for p, h in seeded.items() if md5(LIVE + f"\\{p}\\{p}_sampling_points_summary.xlsx") != h]
    check("all 17 live workbooks still byte-identical to the copies seeded on 26 Sep (no live write by me)", not moved, f"changed: {moved}" if moved else "")
open(lp(OUT), "w", encoding="utf-8").write("\n".join(lines) + f"\n\nOVERALL: {'ALL PASS' if ok_all else 'FAILURES PRESENT'} ({sum(l.startswith('[PASS]') for l in lines)} pass, {sum(l.startswith('[FAIL]') for l in lines)} fail)\n")
print("\nOVERALL:", "ALL PASS" if ok_all else "FAILURES PRESENT")
