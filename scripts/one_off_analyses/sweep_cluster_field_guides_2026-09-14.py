# ==============================================================================
# Comprehensive cluster-field-guide sweep, 2026-09-14 overnight session.
#
# Jack's ask: build_cluster_factsheets.py has always OVERWRITTEN a current
# cluster's factsheet but never removed one for a cluster that's since left
# WORKING (flagged as a known gap back on 2026-09-03's Mobbar build, never
# fixed project-wide - see CLAUDE.md "Revision 2026-09-03"). With this
# week's huge amount of resampling churn (v5->v8, multiple FACT rounds,
# Dandume/Faskari/Matazu/Musawa/Sabuwa reinstatement, MSNA Light, Task 5
# target-correction drops), partner Cluster_guide/ folders are full of
# stale factsheets for clusters that no longer exist in WORKING at all.
#
# This script does the ARCHIVING half only (moves stale files aside, never
# deletes - matches this project's standing convention). The GENERATING
# half (new/refreshed factsheets for every current WORKING cluster) is
# build_cluster_factsheets.py's own normal full-batch run - unmodified,
# run separately, after this script and after all current WORKING clusters
# have a rendered map pair (build_cluster_maps_production.R, resumable,
# run first).
#
# Mechanism: walk every partner's package tree for a "Cluster_guide" folder
# (at any depth - Non_IDP/Cluster_guide and IDP/Cluster_guide both match),
# and for every "<cluster_id>_factsheet.docx" whose cluster_id is NOT in
# the current v8 WORKING frame, move it into a sibling subfolder
# "_archived_dropped_clusters_2026-09-14/" inside that same Cluster_guide
# folder - nested within the existing partner/LGA/pop_type structure per
# the project's folder-placement rule (never a new top-level location),
# non-destructive (move, not delete), and easy for a partner-facing
# follow-up to find if ever questioned. A full manifest (partner, from
# path, to path, cluster_id) is written for the record, since this
# directly touches partner-facing folders.
# ==============================================================================
import csv
import os
import shutil

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v8_WORKING.csv"
PACKAGE_ROOT = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
ARCHIVE_SUBDIR_NAME = "_archived_dropped_clusters_2026-09-14"
MANIFEST_CSV = PROJECT_DIR + r"\resampling\output\cluster_field_guide_sweep_2026-09-14\archived_stale_factsheets_manifest.csv"

# Pass 2 correction (found via qa_cluster_factsheets_batch.py's own "extra
# files" warning, 167 LGA/pop_type/partner combos): pass 1's criterion
# ("cluster_id appears ANYWHERE in WORKING, primary or reserve") was too
# loose. build_cluster_factsheets.py's real scope - what actually gets a
# factsheet built/kept - is narrower: a primary row must still exist (see
# that script's own 2026-09-14 comment). 693 clusters nationally sit in
# WORKING with reserve rows only (663 status=="completed" - every primary
# row already achieved and correctly dropped from the household-level
# to-do list, only never-used reserve capacity remains; 30 access-lost
# with a reserve remnant) - these correctly get NO factsheet, so their
# OLD (pre-completion) factsheet is now equally "no longer relevant" as a
# genuinely-dropped cluster's, and pass 1 wrongly left it in place since
# the cluster_id technically still exists somewhere in WORKING. Verified
# directly on 4 of the QA-flagged examples before fixing this: all 4 show
# status=="completed", n_achieved==target_households==6 in cluster_status_
# v8.csv - exactly this case, not a new/different problem.
with open(STAGE2_CSV, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
working_clusters = {
    r["cluster_id"] for r in rows
    if r["status"] == "primary" and r.get("sampling_method") != "MSNA Light"
}
print(f"{len(working_clusters)} distinct clusters with a primary row in current v8 WORKING (excl. MSNA Light) - "
      f"the actual factsheet-generation scope, not just 'appears somewhere in WORKING'.")

cluster_guide_dirs = []
for dirpath, dirnames, filenames in os.walk(PACKAGE_ROOT):
    if os.path.basename(dirpath) == "Cluster_guide":
        cluster_guide_dirs.append(dirpath)
    # Never descend into an archive subfolder we (or a prior run) created, OR
    # a pre-existing frozen backup snapshot (e.g. FACT's own "_archive/2026-
    # 09-13_pre_msna_light_sampling_method_fix/" full-folder-tree backup) -
    # found live the first time this ran: os.walk was happily walking INTO
    # that historical snapshot's own Cluster_guide folders too, which are
    # frozen-in-time copies, not live/currently-distributed content, and
    # must never be touched by this sweep. 70 such folders exist nationally
    # (vs. 334 genuinely live ones) - excluded by name prefix, not by a
    # one-off hardcoded path, so any future dated backup folder is
    # automatically excluded the same way.
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
print(f"Total archived (cluster no longer in WORKING): {n_moved}")
print("\nPer partner (total scanned / archived):")
for p in sorted(per_partner):
    s = per_partner[p]
    print(f"  {p}: {s['total']} / {s['moved']}")
print(f"\nManifest written to: {MANIFEST_CSV}")
