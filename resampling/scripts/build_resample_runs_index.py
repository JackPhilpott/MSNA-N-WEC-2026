# ==============================================================================
# Regenerates resample_runs/_INDEX.csv - a GENERATED index, not hand-
# maintained (matches Jack's stated preference for self-deriving mechanisms
# over lists that drift, see 1_sampling/CLAUDE.md's "Update 2026-09-08i").
# Walks every <Partner>/<date>/ batch folder (exactly 2 levels under
# resample_runs, per that same update's hard constraint - also what
# 2_monitoring's prep_psu_geometries.R globs for PSU geometry) and extracts
# each one's own merge_log/run_log DONE-line, rather than being typed by
# hand - same approach as the original 2026-09-08i index build.
#
# Re-run any time new batches land (safe, read-only against everything
# except _INDEX.csv itself) - there's no automatic trigger, same as every
# other daily-cadence piece in this pipeline; run by hand after a
# resampling session, or whenever the index looks stale.
#
# Usage: python build_resample_runs_index.py
# ==============================================================================
import csv
import os
import re

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
RUNS_DIR = os.path.join(PROJECT_DIR, "resampling", "output", "resample_runs")
OUT_CSV = os.path.join(RUNS_DIR, "_INDEX.csv")

MERGE_LOG_RE = re.compile(r"^merge_.*_log\.txt$", re.IGNORECASE)


def find_summary_line(batch_path):
    """Prefer a merge log's own summary (Merge header + Verified line);
    fall back to a run_log's own DONE line if no merge has happened yet."""
    files = os.listdir(batch_path)
    merge_logs = [f for f in files if MERGE_LOG_RE.match(f)]
    if merge_logs:
        merge_log = os.path.join(batch_path, sorted(merge_logs)[-1])
        try:
            with open(merge_log, encoding="utf-8", errors="replace") as f:
                lines = [l.rstrip("\n") for l in f]
        except OSError:
            return True, ""
        header = next((l for l in lines if l.strip().startswith("==== Merge")), "")
        verified = next((l for l in lines if l.strip().startswith("Verified:")), "")
        return True, " | ".join(x for x in (header, verified) if x)

    run_log = os.path.join(batch_path, "run_log.txt")
    if os.path.exists(run_log):
        try:
            with open(run_log, encoding="utf-8", errors="replace") as f:
                lines = [l.rstrip("\n") for l in f]
        except OSError:
            return False, ""
        done = next((l for l in lines if l.strip().startswith("==== DONE")), "")
        return False, done

    return False, ""


def build():
    rows = []
    for partner in sorted(os.listdir(RUNS_DIR)):
        partner_path = os.path.join(RUNS_DIR, partner)
        if not os.path.isdir(partner_path) or partner.startswith("_INDEX") or partner.startswith("."):
            continue
        for date_folder in sorted(os.listdir(partner_path)):
            batch_path = os.path.join(partner_path, date_folder)
            if not os.path.isdir(batch_path):
                continue
            all_files = []
            total_bytes = 0
            has_gpkg = False
            for dirpath, _, files in os.walk(batch_path):
                for fn in files:
                    all_files.append(fn)
                    fp = os.path.join(dirpath, fn)
                    try:
                        total_bytes += os.path.getsize(fp)
                    except OSError:
                        pass
                    if fn.lower().endswith(".gpkg"):
                        has_gpkg = True
            merged, summary = find_summary_line(batch_path)
            rows.append({
                "partner": partner,
                "date_folder": date_folder,
                "n_files": len(all_files),
                "size_mb": round(total_bytes / 1024 / 1024, 2),
                "has_gpkg": has_gpkg,
                "merged": merged,
                "summary": summary,
            })

    with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["partner", "date_folder", "n_files", "size_mb", "has_gpkg", "merged", "summary"])
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote {OUT_CSV} - {len(rows)} batch folder(s) indexed.")
    no_gpkg = [r for r in rows if not r["has_gpkg"]]
    no_merge_log = [r for r in rows if not r["merged"] and not r["summary"]]
    if no_gpkg:
        print(f"\n{len(no_gpkg)} batch(es) with no new_clusters*.gpkg at all (invisible to the Coverage Map):")
        for r in no_gpkg:
            print(f"  {r['partner']}/{r['date_folder']}")
    if no_merge_log:
        print(f"\n{len(no_merge_log)} batch(es) with neither a merge log nor a run_log DONE line found:")
        for r in no_merge_log:
            print(f"  {r['partner']}/{r['date_folder']}")


if __name__ == "__main__":
    build()
