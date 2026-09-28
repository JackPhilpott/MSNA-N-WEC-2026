# ==============================================================================
# 2026-09-26: my own integrity + tie-out checks after the Conpad accessibility change (Step 5). READ-ONLY.
# Writes one results file: resampling/output/conpad_accessibility_change_2026-09-26/INTEGRITY_CHECKS.txt
# ==============================================================================
import csv
import collections
import hashlib
import os
import sys

B = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S = B + r"\1_sampling"
DC = S + r"\output\data\data_collection"
SNAP = DC + r"\_archive\2026-09-26_pre_conpad_accessibility"
STG = S + r"\resampling\output\staged_packages_2026-09-26_conpad_accessibility"
OUT = S + r"\resampling\output\conpad_accessibility_change_2026-09-26\INTEGRITY_CHECKS.txt"
sys.path.insert(0, S + r"\scripts\shared")
from cluster_exclusions import extract_workbook_active_ids, kml_active_ids_for_partner  # noqa: E402


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
sfull = rd(F("strata_level_sampling_frame", "FULL")); swork = rd(F("strata_level_sampling_frame", "WORKING"))
full_by = {r["survey_id"]: r for r in full}

# 1 frame files vs the snapshot -------------------------------------------------------------------------------
check("strata FULL byte-identical to pre-change snapshot", md5(F("strata_level_sampling_frame", "FULL")) == md5(SNAP + f"\\NGA_MSNA_2026_strata_level_sampling_frame_{V}_FULL.csv"))
f0 = rd(SNAP + f"\\NGA_MSNA_2026_stage2_sampling_frame_{V}_FULL.csv")
check("stage2 FULL: same rows (132,108), same keys, same 58 columns", len(f0) == len(full) == 132108 and [r["survey_id"] for r in f0] == [r["survey_id"] for r in full] and list(f0[0]) == list(full[0]) and len(full[0]) == 58)
chg = collections.Counter(); flips = collections.Counter()
for a, b in zip(f0, full):
    for c in a:
        if a[c] != b[c]:
            chg[c] += 1
            if c == "ward_accessible_status":
                flips[(a[c], b[c], b["adm2_name"], b["adm3_name"])] += 1
check("stage2 FULL: the ONLY column that changed is ward_accessible_status", set(chg) == {"ward_accessible_status"}, f"{dict(chg)}")
check("stage2 FULL: 885 cells changed, all Accessible->Inaccessible, in exactly the 11 flipped LGA-ward portions",
      sum(flips.values()) == 885 and all(k[0] == "Accessible" and k[1] == "Inaccessible" for k in flips) and
      {(k[2], k[3]) for k in flips} == {("Matazu", "Dissi"), ("Dandume", "Mahuta C"), ("Faskari", "Yankara"), ("Funtua", "Goya"), ("Funtua", "Maigamji"), ("Funtua", "Makera"),
                                        ("Dandume", "Damari"), ("Dandume", "Gamji"), ("Dandume", "Makera"), ("Faskari", "Yankuzo A"), ("Malumfashi", "Rugoji")})
check("WORKING has 58 columns, identical column names to FULL", list(work[0]) == list(full[0]) and len(work[0]) == 58)
check("WORKING is a strict subset of FULL and every WORKING row equals its FULL row on all 58 columns",
      all(r["survey_id"] in full_by and all(r[c] == full_by[r["survey_id"]][c] for c in r) for r in work), f"{len(work)} rows")
check("WORKING has no row in an Inaccessible ward", not any(r["ward_accessible_status"] == "Inaccessible" for r in work))
check("WORKING has 39,035 rows / 3,321 clusters", len(work) == 39035 and len({r["cluster_id"] for r in work}) == 3321)
sw0 = rd(SNAP + f"\\NGA_MSNA_2026_strata_level_sampling_frame_{V}_WORKING.csv")
check("strata WORKING: same 307 strata, same columns; only achieved_clusters/achieved_sample/realized_moe_pct changed",
      [r["strata_id"] for r in sw0] == [r["strata_id"] for r in swork] and list(sw0[0]) == list(swork[0]) and
      {c for a, b in zip(sw0, swork) for c in a if a[c] != b[c]} <= {"achieved_clusters", "achieved_sample", "realized_moe_pct"})

# 2 master vs FULL and overlay vs WORKING ---------------------------------------------------------------------
master = rd(S + r"\resampling\output\master_accessibility_status_ward_level.csv")
mstat = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"] for r in master}
bad = [r["survey_id"] for r in full if r["ward_accessible_status"] != mstat.get((r["adm1_name"], r["adm2_name"], r["adm3_name"]), "Accessible")]
check("every FULL row's ward_accessible_status equals the master ward status (unmatched = Accessible)", not bad, f"{len(bad)} mismatches")
ov = {r["cluster_id"] for r in rd(S + r"\resampling\output\cluster_accessibility_overlay.csv")}
tc = {r["cluster_id"] for r in rd(S + r"\resampling\output\target_correction_dropped_clusters.csv")}
wc = {r["cluster_id"] for r in work}
check("no WORKING cluster is in the cluster overlay or the target-correction drop list", not (wc & ov) and not (wc & tc), f"overlay {len(ov)}, drop list {len(tc)}")
check("the 7 Malumfashi B points Conpad flagged are not in WORKING (clusters already overlay-excluded)",
      not ({"non_idp_NG021025_4_HH02"} | {f"non_idp_NG021025_5_HH{n}" for n in ("03", "06", "07", "11", "13", "18")}) & {r["survey_id"] for r in work})
mw = [r for r in work if r["adm2_name"] == "Malumfashi" and r["adm3_name"] == "Malumfashi B"]
check("Malumfashi B unchanged at ward level (still Accessible in master and FULL)", mstat[("Katsina", "Malumfashi", "Malumfashi B")] == "Accessible", f"{len(mw)} WORKING rows there")
m0 = {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"] for r in rd(S + r"\resampling\output\_archive_accessibility_pre_conpad_2026-09-26\master_accessibility_status_ward_level.csv")}
fl = [k for k in mstat if mstat[k] != m0[k]]
check("master ward status: exactly 11 status changes vs the pre-change master, all Accessible->Inaccessible", len(fl) == 11 and all(m0[k] == "Accessible" and mstat[k] == "Inaccessible" for k in fl))

# 3 mirrors --------------------------------------------------------------------------------------------------
mirrors = [B + r"\2_monitoring\input_data\sampling_frame", B + r"\2_monitoring\dashboard_app\input_data\sampling_frame"]
for fn_ in [f"NGA_MSNA_2026_stage2_sampling_frame_{V}_FULL.csv", f"NGA_MSNA_2026_stage2_sampling_frame_{V}_WORKING.csv", f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_FULL.csv",
            f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_WORKING.csv", "_frame_version.txt"]:
    check(f"mirror x3 identical: {fn_[:60]}", len({md5(DC + "\\" + fn_)} | {md5(m + "\\" + fn_) for m in mirrors}) == 1)
for fn_ in ("master_accessibility_status_ward_level.csv", "master_accessibility_status_lga_level.csv"):
    ms = [B + r"\2_monitoring\input_data\accessibility", B + r"\2_monitoring\dashboard_app\input_data\accessibility"]
    check(f"mirror x3 identical: {fn_}", len({md5(S + "\\resampling\\output\\" + fn_)} | {md5(m + "\\" + fn_) for m in ms}) == 1)
stamp = dict(l.split(": ", 1) for l in open(lp(DC + r"\_frame_version.txt"), encoding="utf-8").read().splitlines() if ": " in l)
check("_frame_version.txt records the current WORKING and strata WORKING md5", stamp["working_csv_md5"] == md5(F("stage2_sampling_frame", "WORKING")) and stamp["strata_working_csv_md5"] == md5(F("strata_level_sampling_frame", "WORKING")) and stamp["working_csv_rows"] == str(len(work)))

# 4 staged workbooks vs WORKING (to-do sets), per partner ----------------------------------------------------
partners_lgas = collections.defaultdict(set)
for r in work:
    for p in [x.strip() for x in r["partners_covering"].split(",") if x.strip() and x.strip() != "NA"]:
        partners_lgas[p].add(r["adm2_pcode"])
PARTNERS = ["CARE", "COOPI", "CRS", "DRC", "FACT", "FHI 360", "INTERSOS", "IRC", "LHI", "MDM", "Malteser", "NRC", "PLAN", "Save the Children", "Solidarités", "Street Child of Nigeria", "ZOA"]
for p in PARTNERS:
    wb = STG + f"\\workbooks\\{p}\\{p}_sampling_points_summary.xlsx"
    wn, wi = extract_workbook_active_ids(lp(wb))
    pcs = partners_lgas.get(p, set())
    # workbooks list every stratum of the partner's LGAs (an LGA shared with another partner on only some strata still lists all of them), so compare at LGA level
    rows = [r for r in work if r["adm2_pcode"] in pcs and r.get("sampling_method") != "MSNA Light"]
    fn_ = {r["survey_id"] for r in rows if r["pop_type"] == "non_idp" and r["status"] in ("primary", "reserve")}
    fi = {r["cluster_id"] for r in rows if r["pop_type"] == "idp" and r["status"] == "primary"}
    wn2 = {x for x in wn if any(pc in x for pc in pcs)}; wi2 = {x for x in wi if any(pc in x for pc in pcs)}
    check(f"staged workbook {p}: to-do Non-IDP points == WORKING ({len(fn_)}), IDP primary clusters == WORKING ({len(fi)})", wn2 == fn_ and wi2 == fi,
          f"wb {len(wn2)}/{len(wi2)} vs WORKING {len(fn_)}/{len(fi)}; wb-only {len(wn2 - fn_)}/{len(wi2 - fi)}, working-only {len(fn_ - wn2)}/{len(fi - wi2)}")

# 5 staged FACT package KMLs vs WORKING (15 LGAs) --------------------------------------------------------------
name2pc = {(r["adm1_name"], r["adm2_name"]): r["adm2_pcode"] for r in work}
for st in ("Katsina", "Borno"):
    d = STG + f"\\FACT\\{st}"
    if not os.path.isdir(lp(d)):
        continue
    for lga in sorted(os.listdir(lp(d))):
        pc = name2pc.get((st, lga))
        Kn, Ki = kml_active_ids_for_partner(lp(d + "\\" + lga))
        r = [x for x in work if x["adm2_pcode"] == pc and x.get("sampling_method") != "MSNA Light"]
        Fn = {x["survey_id"] for x in r if x["pop_type"] == "non_idp" and x["status"] in ("primary", "reserve")}
        Fi = {x["cluster_id"] for x in r if x["pop_type"] == "idp" and x["status"] == "primary"}
        check(f"staged FACT/{st}/{lga}: KML Non-IDP points == WORKING ({len(Fn)}), IDP primary clusters == WORKING ({len(Fi)})", Kn == Fn and Ki == Fi, f"KML {len(Kn)}/{len(Ki)}")
        # each staged factsheet is for a cluster with a primary row in WORKING
        cg = [f for dp, dn, fs in os.walk(lp(d + "\\" + lga)) for f in fs if f.endswith("_factsheet.docx")]
        prim = {x["cluster_id"] for x in r if x["status"] == "primary"}
        check(f"staged FACT/{st}/{lga}: every staged factsheet is for a cluster with a primary row in WORKING", all(f[:-len('_factsheet.docx')] in prim for f in cg), f"{len(cg)} factsheets")

# 6 live folders untouched by me ----------------------------------------------------------------------------
seeded = {l.split("  ")[2]: l.split("  ")[0] for l in open(lp(STG + r"\workbooks\SEEDED_live_copies_md5.txt"), encoding="utf-8").read().splitlines() if l.strip()}
LIVE = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
moved = [p for p, h in seeded.items() if md5(LIVE + f"\\{p}\\{p}_sampling_points_summary.xlsx") != h]
check("all 17 live workbooks still byte-identical to the copies seeded at 21:4x (no live write by me)", not moved, f"changed: {moved}" if moved else "")
open(lp(OUT), "w", encoding="utf-8").write("\n".join(lines) + f"\n\nOVERALL: {'ALL PASS' if ok_all else 'FAILURES PRESENT'} ({sum(l.startswith('[PASS]') for l in lines)} pass, {sum(l.startswith('[FAIL]') for l in lines)} fail)\n")
print("\nOVERALL:", "ALL PASS" if ok_all else "FAILURES PRESENT")
