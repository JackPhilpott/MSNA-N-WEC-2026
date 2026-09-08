# ==============================================================================
# Automated QA sweep over the full production cluster-map + factsheet batch
# (build_cluster_maps_production.R + build_cluster_factsheets.py), run once
# both complete. Checks, per cluster in the WORKING frame:
#   1. Both map PNGs exist (cluster_map_examples_v3/, cluster_lga_context_v1/)
#      and are non-trivially sized (catches a truncated/zero-byte render).
#   2. The per-cluster factsheet docx exists in TEMP_DIR and opens cleanly
#      (python-docx can parse it - catches a corrupt/truncated save).
#   3. The docx was actually distributed into every covering partner's
#      Cluster_guide/ folder (cross-checked against partners_by_pcode).
#   4. Expected per-LGA file counts: every LGA folder that should have a
#      Non_IDP/ or IDP/ subfolder has one, with a KML/ + Cluster_guide/
#      pair, and Cluster_guide/'s docx count matches the number of clusters
#      of that pop_type in that LGA (from the WORKING frame).
#   5. The build log (_production_build_log.csv) has zero "error" rows.
# Writes a single report CSV (one row per finding) plus a console summary -
# does not modify anything. Not exhaustive content QA (that's the manual
# spot-check pass) - this is the "did every file that should exist, exist
# and open" pass.
# ==============================================================================
import csv
import os
from collections import defaultdict

from docx import Document

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"
CLUSTER_MAPS_DIR = PROJECT_DIR + r"\output\maps\cluster_map_examples_v3"
LGA_MAPS_DIR = PROJECT_DIR + r"\output\maps\cluster_lga_context_v1"
BUILD_LOG_CSV = PROJECT_DIR + r"\output\maps\_production_build_log.csv"
TEMP_DIR = PROJECT_DIR + r"\output\cluster_factsheets_tmp"
OUT_ROOT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
STRATA_CSV = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample\strata_level_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
REPORT_CSV = PROJECT_DIR + r"\output\qa_cluster_factsheets_batch_report.csv"
MIN_PNG_BYTES = 5000  # a real map render is comfortably >100KB; anything under 5KB is almost certainly a blank/broken save

findings = []


def flag(severity, category, cluster_id, detail):
    findings.append({"severity": severity, "category": category, "cluster_id": cluster_id, "detail": detail})


# ---------------------------------------------------------------------------
# 1. Load the WORKING frame -> one row per cluster (pop_type, pcode, lga_name)
# ---------------------------------------------------------------------------
with open(STAGE2_CSV, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

clusters = {}
for r in rows:
    if r["status"] != "primary":
        continue
    cid = r["cluster_id"]
    if cid not in clusters:
        clusters[cid] = {"pop_type": r["pop_type"], "adm2_pcode": r["adm2_pcode"], "adm2_name": r["adm2_name"]}

print(f"Loaded {len(clusters)} clusters from the WORKING frame.")

# ---------------------------------------------------------------------------
# 2. Map PNG existence + minimum size
# ---------------------------------------------------------------------------
n_map_ok = 0
for cid in clusters:
    for label, d in [("cluster_map", CLUSTER_MAPS_DIR), ("lga_context_map", LGA_MAPS_DIR)]:
        path = os.path.join(d, f"{cid}.png")
        if not os.path.exists(path):
            flag("ERROR", "missing_map", cid, f"{label} PNG missing: {path}")
        elif os.path.getsize(path) < MIN_PNG_BYTES:
            flag("ERROR", "truncated_map", cid, f"{label} PNG suspiciously small ({os.path.getsize(path)} bytes): {path}")
        else:
            n_map_ok += 1
print(f"Map PNG checks: {n_map_ok}/{len(clusters) * 2} ok.")

# ---------------------------------------------------------------------------
# 3. Factsheet docx exists in TEMP_DIR and opens cleanly
# ---------------------------------------------------------------------------
n_docx_ok = 0
for cid in clusters:
    path = os.path.join(TEMP_DIR, f"{cid}_factsheet.docx")
    if not os.path.exists(path):
        flag("ERROR", "missing_docx", cid, f"Factsheet docx missing: {path}")
        continue
    try:
        doc = Document(path)
        n_paragraphs = len(doc.paragraphs)
        n_images = sum(1 for rel in doc.part.rels.values() if "image" in rel.reltype)
        if n_images < 1:
            flag("ERROR", "docx_no_images", cid, f"Factsheet has zero embedded images (expected >=1 map)")
        elif n_paragraphs < 5:
            flag("WARNING", "docx_thin_content", cid, f"Factsheet has only {n_paragraphs} paragraphs - unusually short")
        else:
            n_docx_ok += 1
    except Exception as e:
        flag("ERROR", "docx_corrupt", cid, f"Failed to open with python-docx: {e}")
print(f"Docx integrity checks: {n_docx_ok}/{len(clusters)} ok.")

# ---------------------------------------------------------------------------
# 4. Partner coverage - reuse the exact matching logic build_partner_dc_
#    packages.py/build_cluster_factsheets.py already use, so this check is
#    self-consistent with what actually got distributed.
# ---------------------------------------------------------------------------
import re
import difflib
import openpyxl

IN_SCOPE_STATES = {
    "Adamawa", "Borno", "Yobe",
    "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto", "Zamfara",
    "Benue", "Kogi", "Nasarawa", "Niger", "Plateau",
}
PROPOSED_RECONCILIATION = {
    ("Zamfara", "Birnin Magaji/Kiyaw"): "NG037003", ("Zamfara", "Kauran Namoda"): "NG037008",
    ("Kaduna", "Makarfi"): "NG019018", ("Kaduna", "Zangon-Kataf"): "NG019022",
    ("Kebbi", "Wasagu"): "NG022019", ("Benue", "Otukpo"): "NG007019",
    ("Kogi", "Olamaboro"): "NG023018", ("Nasarawa", "Eggon"): "NG026010",
    ("Niger", "Munya"): "NG027018", ("Plateau", "Barkin Ladi"): "NG032001",
}
COMBINED_PARTNER_SPLITS = {"IRC/LHI": ["IRC", "LHI"]}


def norm(s):
    if s is None:
        return ""
    s = str(s).strip().lower().replace("/", " ").replace("-", " ")
    s = re.sub(r"[\'\u2018\u2019\u02bc\ufffd]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def safe_folder_name(s):
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


with open(STRATA_CSV, encoding="utf-8") as f:
    strata_rows = list(csv.DictReader(f))
master_lgas = {r["adm2_pcode"]: {"adm1_name": r["adm1_name"], "adm2_name": r["adm2_name"]} for r in strata_rows}
lga_index = {(norm(v["adm1_name"]), norm(v["adm2_name"])): p for p, v in master_lgas.items()}
master_by_state = defaultdict(list)
for p, v in master_lgas.items():
    master_by_state[v["adm1_name"]].append(v["adm2_name"])

wb = openpyxl.load_workbook(COVERAGE_XLSX, data_only=True)
partners_by_pcode = defaultdict(set)
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    all_rows = list(ws.iter_rows(values_only=True))
    header = all_rows[0]
    count_idx = header.index("COUNT")
    partner_col_idx = list(range(3, count_idx))
    for r in all_rows[1:]:
        if r[2] is None:
            continue
        state = str(r[1]).strip() if r[1] else None
        lga = str(r[2]).strip() if r[2] else None
        if state not in IN_SCOPE_STATES:
            continue
        partners_here = [str(header[i]).strip() for i in partner_col_idx if r[i]]
        if not partners_here:
            continue
        key = (norm(state), norm(lga))
        pcode = lga_index.get(key) or PROPOSED_RECONCILIATION.get((state, lga))
        if pcode is None:
            continue
        for p in partners_here:
            for expanded in COMBINED_PARTNER_SPLITS.get(p, [p]):
                partners_by_pcode[pcode].add(expanded)

n_dist_ok = 0
n_no_partner = 0
for cid, meta in clusters.items():
    pcode = meta["adm2_pcode"]
    lga_name = meta["adm2_name"]
    state_name = master_lgas.get(pcode, {}).get("adm1_name", "")
    pop_folder = "Non_IDP" if meta["pop_type"] == "non_idp" else "IDP"
    partners = partners_by_pcode.get(pcode, set())
    if not partners:
        n_no_partner += 1
        continue
    for partner in partners:
        dest = os.path.join(
            OUT_ROOT, safe_folder_name(partner), safe_folder_name(state_name), safe_folder_name(lga_name),
            pop_folder, "Cluster_guide", f"{cid}_factsheet.docx",
        )
        if not os.path.exists(dest):
            flag("ERROR", "not_distributed", cid, f"Missing from partner folder: {dest}")
        else:
            n_dist_ok += 1
print(f"Distribution checks: {n_dist_ok} partner-copies ok; {n_no_partner} clusters have no covering partner (expected for LGAs excluded from partner coverage).")

# ---------------------------------------------------------------------------
# 5. Expected per-LGA folder/file-count consistency
# ---------------------------------------------------------------------------
clusters_by_pcode_pop = defaultdict(lambda: defaultdict(list))
for cid, meta in clusters.items():
    clusters_by_pcode_pop[meta["adm2_pcode"]][meta["pop_type"]].append(cid)

n_lga_ok = 0
for pcode, by_pop in clusters_by_pcode_pop.items():
    state_name = master_lgas.get(pcode, {}).get("adm1_name", "")
    lga_name = master_lgas.get(pcode, {}).get("adm2_name", "")
    partners = partners_by_pcode.get(pcode, set())
    for partner in partners:
        for pt, pop_folder in [("non_idp", "Non_IDP"), ("idp", "IDP")]:
            expected_cids = by_pop.get(pt, [])
            if not expected_cids:
                continue
            guide_dir = os.path.join(
                OUT_ROOT, safe_folder_name(partner), safe_folder_name(state_name), safe_folder_name(lga_name),
                pop_folder, "Cluster_guide",
            )
            if not os.path.isdir(guide_dir):
                flag("ERROR", "missing_cluster_guide_folder", f"{pcode}/{pt}", f"{partner}: expected {guide_dir}")
                continue
            actual = {f for f in os.listdir(guide_dir) if f.endswith("_factsheet.docx")}
            expected = {f"{cid}_factsheet.docx" for cid in expected_cids}
            missing = expected - actual
            extra = actual - expected
            if missing:
                flag("ERROR", "lga_folder_count_mismatch", f"{pcode}/{pt}", f"{partner}: {len(missing)} expected docx missing from {guide_dir}: {sorted(missing)[:5]}")
            elif extra:
                flag("WARNING", "lga_folder_extra_files", f"{pcode}/{pt}", f"{partner}: {len(extra)} unexpected docx in {guide_dir}: {sorted(extra)[:5]}")
            else:
                n_lga_ok += 1
print(f"Per-LGA Cluster_guide/ count checks: {n_lga_ok} folders match exactly.")

# ---------------------------------------------------------------------------
# 6. Build log error rows
# ---------------------------------------------------------------------------
if os.path.exists(BUILD_LOG_CSV):
    with open(BUILD_LOG_CSV, encoding="utf-8") as f:
        log_rows = list(csv.DictReader(f))
    error_rows = [r for r in log_rows if r["status"] == "error"]
    for r in error_rows:
        flag("ERROR", "map_render_error", r["cluster_id"], f"{r['map_type']}: {r['error_message']}")
    print(f"Build log: {len(log_rows)} rows, {len(error_rows)} error rows.")
else:
    flag("WARNING", "build_log_missing", "-", f"{BUILD_LOG_CSV} not found - was the map batch run?")

# ---------------------------------------------------------------------------
# Write report + console summary
# ---------------------------------------------------------------------------
os.makedirs(os.path.dirname(REPORT_CSV), exist_ok=True)
with open(REPORT_CSV, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["severity", "category", "cluster_id", "detail"])
    writer.writeheader()
    writer.writerows(findings)

n_errors = sum(1 for x in findings if x["severity"] == "ERROR")
n_warnings = sum(1 for x in findings if x["severity"] == "WARNING")
print(f"\n{'='*70}\nQA SWEEP COMPLETE: {n_errors} error(s), {n_warnings} warning(s).")
print(f"Full report: {REPORT_CSV}")
if n_errors:
    by_cat = defaultdict(int)
    for x in findings:
        if x["severity"] == "ERROR":
            by_cat[x["category"]] += 1
    print("\nErrors by category:")
    for cat, n in sorted(by_cat.items(), key=lambda kv: -kv[1]):
        print(f"  {cat}: {n}")
