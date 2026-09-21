# ==============================================================================
# 2026-09-21 SECOND round (evening), merge chain. Jack's own word: "yes, run
# the draw for all" and "don't need to ask, already go ahead and draw".
# Backs up output/data/data_collection/ once, then:
#   1. merges each staged partner that drew something, sequentially, stopping
#      at the first failure (later partners would otherwise merge onto a
#      frame in an unknown state). PLAN drew nothing (Kala/Balge: 0 of 7) and
#      is skipped - there is nothing to merge.
#   2. adds the extra interviews at the four certainty sites
#      (add_certainty_site_interviews_2026-09-21.py - FULL only).
#   3. refreshes WORKING from FULL (refresh_working_frame_daily.R), which also
#      rewrites the per-cluster status file 05 reads.
# 05, mirrors and partner packages are run separately afterwards.
# Usage: python merge_second_round_2026-09-21.py
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
BATCH = "2026-09-21_second_round"
PARTNERS = ["CARE", "CRS", "FACT", "INTERSOS", "Street Child of Nigeria"]
KEY_LINES = re.compile(r"Pre-flight|Excluding|FULL \d|Stranded|Strata-level updated|assert_plausible|DONE|Error|STOP", re.I)


def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "_", p).lower()


def main():
    bak = os.path.join(DATA, "_archive", "2026-09-21_pre_second_round")
    os.makedirs(bak, exist_ok=True)
    n = 0
    for f in os.listdir(DATA):
        if f.endswith(".csv"):
            shutil.copy2(os.path.join(DATA, f), os.path.join(bak, f)); n += 1
    print(f"BACKUP OK ({n} files) -> {bak}", flush=True)

    for p in PARTNERS:
        d = os.path.join(RUNS, p, BATCH)
        sf, sfi = os.path.join(d, f"{slug(p)}_shortfalls.csv"), os.path.join(d, f"{slug(p)}_shortfalls_idp.csv")
        log = os.path.join(d, "merge_run_log.txt")
        print(f"\n===== {p} merge starting {datetime.now():%H:%M:%S} =====", flush=True)
        with open(log, "w", encoding="utf-8") as out:
            rc = subprocess.run([RSCRIPT, os.path.join(SCRIPTS, "merge_partner_resample_batch.R"), p, d, sf, sfi],
                                cwd=PROJECT_DIR, stdout=out, stderr=subprocess.STDOUT).returncode
        with open(log, "a", encoding="utf-8") as out:
            out.write(f"EXIT={rc}\n")
        for line in open(log, encoding="utf-8", errors="replace"):
            if KEY_LINES.search(line):
                print("  " + line.rstrip(), flush=True)
        print(f"===== {p} merge EXIT={rc} =====", flush=True)
        if rc != 0:
            sys.exit(f"STOPPING CHAIN - {p} merge failed; later partners, the certainty-site edit and the refresh NOT run.")

    print(f"\n===== certainty-site interviews {datetime.now():%H:%M:%S} =====", flush=True)
    cs = subprocess.run([sys.executable, os.path.join(SCRIPTS, "one_off_analyses", "add_certainty_site_interviews_2026-09-21.py")],
                        cwd=PROJECT_DIR, capture_output=True, text=True)
    print(cs.stdout.strip(), cs.stderr.strip(), flush=True)
    if cs.returncode != 0:
        sys.exit("STOPPING CHAIN - certainty-site edit failed; refresh NOT run.")

    rlog = os.path.join(DATA, "_working_refresh_logs", "refresh_2026-09-21_post_second_round.log")
    os.makedirs(os.path.dirname(rlog), exist_ok=True)
    with open(rlog, "w", encoding="utf-8") as out:
        rc = subprocess.run([RSCRIPT, os.path.join(PROJECT_DIR, "scripts", "field_guide_production", "refresh_working_frame_daily.R")],
                            cwd=PROJECT_DIR, stdout=out, stderr=subprocess.STDOUT).returncode
    print(f"\nREFRESH_EXIT={rc}", flush=True)
    for line in open(rlog, encoding="utf-8", errors="replace"):
        if re.search(r"WORKING \(household-level, (new|previous)\)|assert_plausible|strata refreshed|Per-cluster status|Error", line):
            print("  " + line.rstrip(), flush=True)
    if rc != 0:
        sys.exit("REFRESH FAILED")
    print("\nSECOND ROUND MERGED + CERTAINTY SITES ADDED + REFRESHED. Next: 05, mirrors, packages.", flush=True)


if __name__ == "__main__":
    main()
