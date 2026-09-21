# ==============================================================================
# 2026-09-21 late evening, merge chain for the Street Child / NRC ward-flips
# round (stage_ward_flips_2026-09-21.py), on Jack's go ("fly through to
# update the sampling frame, worry about building out the partner packages
# later"). Backs up output/data/data_collection/ (post-resweep state), merges
# every partner that has a staged batch with real households, sequentially,
# stopping at the first failure, then refreshes WORKING. 05 / mirrors are run
# afterwards; partner packages deliberately NOT (Jack: later).
# Usage: python merge_ward_flips_2026-09-21.py
# ==============================================================================
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
SCRIPTS = os.path.join(PROJECT_DIR, "resampling", "scripts")
RUNS = os.path.join(PROJECT_DIR, "resampling", "output", "resample_runs")
DATA = os.path.join(PROJECT_DIR, "output", "data", "data_collection")
RSCRIPT = r"C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\Rscript.exe"
BATCH = "2026-09-21_ward_flips"
PARTNERS = ["Street Child of Nigeria", "NRC"]
KEY_LINES = re.compile(r"Pre-flight|Excluding|FULL \d|Stranded|Strata-level updated|assert_plausible|DONE|Error|STOP", re.I)


def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "_", p).lower()


def has_rows(p):
    return os.path.exists(p) and os.path.getsize(p) > 5 and sum(1 for _ in open(p, encoding="utf-8")) > 1


def main():
    bak = os.path.join(DATA, "_archive", "2026-09-21_pre_ward_flips_merge")
    os.makedirs(bak, exist_ok=True)
    for f in os.listdir(DATA):
        if f.endswith(".csv"):
            shutil.copy2(os.path.join(DATA, f), os.path.join(bak, f))
    print(f"BACKUP OK -> {bak}", flush=True)

    for p in PARTNERS:
        d = os.path.join(RUNS, p, BATCH)
        if not (has_rows(os.path.join(d, "new_households.csv")) or has_rows(os.path.join(d, "new_households_idp_sitelevel.csv"))):
            print(f"\n===== {p}: nothing staged with real households - skipped =====", flush=True)
            continue
        sf, sfi = os.path.join(d, f"{slug(p)}_shortfalls.csv"), os.path.join(d, f"{slug(p)}_shortfalls_idp.csv")
        log = os.path.join(d, "merge_run_log.txt")
        print(f"\n===== {p} merge starting {datetime.now():%H:%M:%S} =====", flush=True)
        with open(log, "w", encoding="utf-8") as out:
            rc = subprocess.run([RSCRIPT, os.path.join(SCRIPTS, "merge_partner_resample_batch.R"), p, d, sf, sfi],
                                cwd=PROJECT_DIR, stdout=out, stderr=subprocess.STDOUT).returncode
        for line in open(log, encoding="utf-8", errors="replace"):
            if KEY_LINES.search(line):
                print("  " + line.rstrip(), flush=True)
        print(f"===== {p} merge EXIT={rc} =====", flush=True)
        if rc != 0:
            sys.exit(f"STOPPING CHAIN - {p} merge failed; refresh NOT run.")

    rlog = os.path.join(DATA, "_working_refresh_logs", "refresh_2026-09-21_post_ward_flips.log")
    with open(rlog, "w", encoding="utf-8") as out:
        rc = subprocess.run([RSCRIPT, os.path.join(PROJECT_DIR, "scripts", "field_guide_production", "refresh_working_frame_daily.R")],
                            cwd=PROJECT_DIR, stdout=out, stderr=subprocess.STDOUT).returncode
    print(f"\nREFRESH_EXIT={rc}", flush=True)
    for line in open(rlog, encoding="utf-8", errors="replace"):
        if re.search(r"WORKING \(household-level, (new|previous)\)|assert_plausible|Per-cluster status|Error", line):
            print("  " + line.rstrip(), flush=True)
    if rc != 0:
        sys.exit("REFRESH FAILED")
    print("\nWARD-FLIPS ROUND MERGED + REFRESHED. Next: 05, mirrors. Packages later (Jack).", flush=True)


if __name__ == "__main__":
    main()
