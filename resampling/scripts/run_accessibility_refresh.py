# ==============================================================================
# One-command refresh of the whole accessibility-reporting chain, run
# whenever new or updated partner accessibility reports are dropped into
# accessibility_reports_returned/ (2026-08-26 - built specifically so this
# doesn't require remembering the right script order by hand each time).
#
# Every step this calls is already individually rerun-safe / idempotent -
# each one recomputes fully from its current source files rather than
# accumulating state, EXCEPT step 1 (the master log), which is deliberately
# append-only and diffs against its own latest rows to avoid duplicate
# entries on a re-ingest of unchanged content (see
# 02_ingest_accessibility_reports.py's own header). Nothing here needs a
# cache cleared and nothing needs deleting before a rerun.
#
# Order matters (each step reads the previous step's output):
#   1. 02_ingest_accessibility_reports.py   - returned/*.xlsx -> master log
#   2. 04_build_master_accessibility_status.py - master log -> ward/LGA status CSVs
#   3. analysis_accessible_area_layer.R     - ward status -> GIS polygon layer
#   4. analysis_remaining_eligible_pool.R   - GIS layer -> remaining hex/site pools
#   5. 05_build_accessibility_impact_workbook.py - everything -> the workbook
#
# Usage: py run_accessibility_refresh.py
# Stops at the first failing step (prints its full output either way) rather
# than continuing on to steps that would read incomplete/stale input.
# ==============================================================================
import subprocess
import sys

SCRIPTS_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\scripts"
RSCRIPT_EXE = r"C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\Rscript.exe"

STEPS = [
    ("Ingest returned partner reports into the master log", [sys.executable, "02_ingest_accessibility_reports.py"]),
    ("Build master ward/LGA accessibility status", [sys.executable, "04_build_master_accessibility_status.py"]),
    ("Build GIS accessible-area polygon layer", [RSCRIPT_EXE, "analysis_accessible_area_layer.R"]),
    ("Build remaining eligible pool (hexes/DTM sites)", [RSCRIPT_EXE, "analysis_remaining_eligible_pool.R"]),
    ("Build the accessibility impact workbook", [sys.executable, "05_build_accessibility_impact_workbook.py"]),
]


def main():
    for i, (label, cmd) in enumerate(STEPS, start=1):
        print(f"\n{'='*70}\nStep {i}/{len(STEPS)}: {label}\n{'='*70}")
        result = subprocess.run(cmd, cwd=SCRIPTS_DIR, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            print(f"\nSTOPPED at step {i} ({label}) - fix the error above before rerunning. "
                  f"Later steps were not run, so their outputs are now one step behind this failure.")
            sys.exit(1)
    print(f"\n{'='*70}\nAll {len(STEPS)} steps completed - every accessibility output is current.\n{'='*70}")


if __name__ == "__main__":
    main()
