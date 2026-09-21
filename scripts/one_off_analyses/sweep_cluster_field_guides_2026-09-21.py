# ==============================================================================
# Cluster-field-guide sweep, 2026-09-21 - the archiving half of the guides
# push that follows the post-Feasibility-fix draw round (v10 -> v11).
#
# Same mechanism and same reasoning as sweep_cluster_field_guides_2026-09-14.py
# (read that script's header for the full rationale, incl. why "appears
# anywhere in WORKING" is the WRONG scope test); this is a re-run against the
# CURRENT v11 WORKING frame, since that round added ~630 clusters and moved
# many others out of scope. build_cluster_factsheets.py has never deleted a
# factsheet for a cluster that has since left its own generation scope, so
# without this pass a partner's Cluster_guide/ folder keeps stale guides
# alongside the fresh ones.
#
# Scope test (must match build_cluster_factsheets.py's real scope, not a
# looser proxy): a cluster keeps its factsheet only if it still has a PRIMARY
# row in v11 WORKING and is not MSNA Light (whose government-enumerator
# methodology the standard guide text does not describe - deliberately out of
# scope since 2026-09-14, still Jack's own design call to make).
#
# Non-destructive: files are MOVED into a sibling
# "_archived_dropped_clusters_2026-09-21/" folder inside the same
# Cluster_guide directory (never deleted, never a new top-level location),
# and a full manifest is written since this touches partner-facing folders.
# ==============================================================================
import csv
import os
import re
import shutil


def latest_frame_file(directory, template):
    """Newest-version frame file in `directory` (top level only). Added at the
    v11 -> v12 bump (2026-09-21): reading a frozen older WORKING here would
    treat every cluster drawn since as out of scope and archive its guide."""
    rx = re.compile("^" + re.escape(template).replace(r"\{\}", r"(\d+)") + "$")
    hits = [(int(m.group(1)), f) for f in os.listdir(directory) for m in [rx.match(f)] if m]
    if not hits:
        raise SystemExit(f"No file matching {template} in {directory}")
    return os.path.join(directory, max(hits)[1])


PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = latest_frame_file(PROJECT_DIR + r"\output\data\data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v{}_WORKING.csv")
PACKAGE_ROOT = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
ARCHIVE_SUBDIR_NAME = "_archived_dropped_clusters_2026-09-21"
MANIFEST_CSV = PROJECT_DIR + r"\resampling\output\cluster_field_guide_sweep_2026-09-21\archived_stale_factsheets_manifest.csv"

with open(STAGE2_CSV, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
working_clusters = {
    r["cluster_id"] for r in rows
    if r["status"] == "primary" and r.get("sampling_method") != "MSNA Light"
}
print(f"{len(working_clusters)} distinct clusters with a primary row in current WORKING (excl. MSNA Light) - "
      f"the actual factsheet-generation scope.")

cluster_guide_dirs = []
for dirpath, dirnames, filenames in os.walk(PACKAGE_ROOT):
    if os.path.basename(dirpath) == "Cluster_guide":
        cluster_guide_dirs.append(dirpath)
    # Never descend into an archive subfolder (ours, a prior sweep's, or a
    # frozen full-tree backup snapshot) - those are historical copies, not
    # live distributed content. Excluded by name prefix, not a hardcoded path.
    dirnames[:] = [d for d in dirnames if not d.startswith("_archived_dropped_clusters") and not d.startswith("_archive")]
print(f"{len(cluster_guide_dirs)} Cluster_guide folders found.")

os.makedirs(os.path.dirname(MANIFEST_CSV), exist_ok=True)
manifest_rows = []
n_total = 0
n_moved = 0
per_partner = {}

for guide_dir in cluster_guide_dirs:
    partner = guide_dir.split(f"{PACKAGE_ROOT}\\")[1].split(os.sep)[0]
    stats = per_partner.setdefault(partner, {"total": 0, "moved": 0})
    files = [f for f in os.listdir(guide_dir) if f.endswith("_factsheet.docx")]
    n_total += len(files)
    stats["total"] += len(files)
    stale = [f for f in files if f[: -len("_factsheet.docx")] not in working_clusters]
    if not stale:
        continue
    archive_dir = os.path.join(guide_dir, ARCHIVE_SUBDIR_NAME)
    os.makedirs(archive_dir, exist_ok=True)
    for fn in stale:
        cid = fn[: -len("_factsheet.docx")]
        src = os.path.join(guide_dir, fn)
        dst = os.path.join(archive_dir, fn)
        shutil.move(src, dst)
        n_moved += 1
        stats["moved"] += 1
        manifest_rows.append({"partner": partner, "cluster_id": cid, "from_path": src, "to_path": dst})

with open(MANIFEST_CSV, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["partner", "cluster_id", "from_path", "to_path"])
    w.writeheader()
    w.writerows(manifest_rows)

print(f"\nTotal factsheet docx files scanned: {n_total}")
print(f"Total archived (cluster no longer in factsheet scope): {n_moved}")
print("\nPer partner (total scanned / archived):")
for p in sorted(per_partner):
    s = per_partner[p]
    print(f"  {p}: {s['total']} / {s['moved']}")
print(f"\nManifest written to: {MANIFEST_CSV}")
