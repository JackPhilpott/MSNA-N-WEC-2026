# ==============================================================================
# Cluster-field-guide sweep, 2026-10-14 - the archiving half of the guides push (Jack, 14 Oct, Resampling window: "continue
# updating the partner folders (workbooks, kmls, factsheets) as usual"). Same mechanism and scope test as
# sweep_cluster_field_guides_2026-09-21.py (read its header); first sweep since then, so it catches every cluster that left
# the factsheet scope in the 4 Oct reallocation, the 5-12 Oct rounds, the 12 Oct Maru change and ordinary completion.
# Found by INTERSOS's Maru teams following guides for clusters removed on 12 Oct (those 9 were archived first, by
# resampling/scripts/one_off_analyses/archive_intersos_maru_stale_guides_2026-10-14.py).
#
# Scope test (= build_cluster_factsheets.py's real scope): a cluster keeps its factsheet only if it still has a PRIMARY row
# in the current WORKING frame and is not MSNA Light. Non-destructive: files are MOVED into a sibling
# "_archived_dropped_clusters_2026-10-14/" inside the same Cluster_guide folder; a manifest is written; --restore undoes it.
#   py sweep_cluster_field_guides_2026-10-14.py             dry run (counts per partner, nothing moved)
#   py sweep_cluster_field_guides_2026-10-14.py --execute
#   py sweep_cluster_field_guides_2026-10-14.py --restore
# ==============================================================================
import csv, os, shutil, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "shared"))
import msna_paths  # noqa: E402

TAG = "2026-10-14"
ARCHIVE_SUBDIR_NAME = f"_archived_dropped_clusters_{TAG}"
PACKAGE_ROOT = msna_paths.pkg_root()
MANIFEST_CSV = os.path.join(msna_paths.sampling_dir(), "resampling", "output", f"cluster_field_guide_sweep_{TAG}",
                            "archived_stale_factsheets_manifest.csv")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--restore":
        rows = list(csv.DictReader(open(MANIFEST_CSV, encoding="utf-8")))
        for r in rows:
            assert os.path.isfile(r["to_path"]) and not os.path.exists(r["from_path"]), r
        for r in rows:
            shutil.move(r["to_path"], r["from_path"])
        print(f"restored {len(rows)} file(s)")
        return
    with open(msna_paths.frame_file("stage2_WORKING"), encoding="utf-8-sig") as f:
        scope = {r["cluster_id"] for r in csv.DictReader(f)
                 if r["status"] == "primary" and "MSNA Light" not in (r.get("sampling_method") or "")}
    print(f"{len(scope)} clusters with a primary row in WORKING (excl. MSNA Light) = the factsheet scope")
    plan, scanned = [], Counter()
    for dirpath, dirnames, filenames in os.walk(PACKAGE_ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith("_archive")]   # never descend into any archive folder
        if os.path.basename(dirpath) != "Cluster_guide":
            continue
        partner = os.path.relpath(dirpath, PACKAGE_ROOT).split(os.sep)[0]
        for fn in filenames:
            if not fn.endswith("_factsheet.docx"):
                continue
            scanned[partner] += 1
            cid = fn[: -len("_factsheet.docx")]
            if cid not in scope:
                plan.append({"partner": partner, "cluster_id": cid, "from_path": os.path.join(dirpath, fn),
                             "to_path": os.path.join(dirpath, ARCHIVE_SUBDIR_NAME, fn)})
    moved = Counter(p["partner"] for p in plan)
    print(f"scanned {sum(scanned.values())} factsheet(s) in live Cluster_guide folders; out of scope: {len(plan)}")
    for p in sorted(scanned):
        print(f"  {p}: {scanned[p]} scanned / {moved.get(p, 0)} to archive")
    if mode != "--execute":
        print("dry run: nothing moved (add --execute)")
        return
    for p in plan:
        assert not os.path.exists(p["to_path"]), f"STOP: already archived {p['to_path']}"
    os.makedirs(os.path.dirname(MANIFEST_CSV), exist_ok=True)
    done = []
    try:
        for p in plan:
            os.makedirs(os.path.dirname(p["to_path"]), exist_ok=True)
            shutil.move(p["from_path"], p["to_path"])
            done.append(p)
    finally:
        with open(MANIFEST_CSV, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["partner", "cluster_id", "from_path", "to_path"])
            w.writeheader()
            w.writerows(done)
    print(f"archived {len(done)} file(s); manifest {MANIFEST_CSV}")


if __name__ == "__main__":
    main()
