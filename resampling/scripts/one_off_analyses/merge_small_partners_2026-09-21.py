# ==============================================================================
# 2026-09-21 resampling round: merges the 12 staged small-partner batches into
# the live FULL/WORKING frame, one partner at a time, sequentially, stopping
# at the first failure (later partners would otherwise merge onto a frame in
# an unknown state). Backs up output/data/data_collection/ first, per the
# standing convention. Runs refresh_working_frame_daily.R at the end.
#
# Deliberately does NOT rebuild the accessibility impact workbook (05) -
# that script is being edited in parallel tonight (certainty-PSU-aware MoE
# column); the workbook is rebuilt by hand once both this chain and that
# edit are done, so the chain can never run a half-edited script.
#
# Jack approved all 12 merges ~03:30. Dual-coverage strata (Zuru, Tangaza)
# are already attributed to IRC in the staged CSVs (see stage_small_
# partners_2026-09-21.py) - LHI has no batch of its own.
# Usage: python merge_small_partners_2026-09-21.py
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
BATCH = "2026-09-21_post_feasibility_fix"

PARTNERS = ["Save the Children", "IRC", "Malteser", "MDM", "ZOA", "DRC", "IMC",
            "Street Child of Nigeria", "ACF", "PLAN", "FHI 360", "Solidarités"]

KEY_LINES = re.compile(r"Pre-flight|Excluding|FULL \d|Stranded|Strata-level updated|assert_plausible|DONE|Error|STOP", re.I)


def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "_", p).lower()


def main():
    bak = os.path.join(DATA, "_archive", "2026-09-21_pre_small_partners_merge")
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
            print(f"STOPPING CHAIN - {p} merge failed; later partners NOT merged.", flush=True)
            sys.exit(1)

    rlog = os.path.join(DATA, "_working_refresh_logs", "refresh_2026-09-21_post_small_partners_merge.log")
    with open(rlog, "w", encoding="utf-8") as out:
        rc = subprocess.run([RSCRIPT, os.path.join(PROJECT_DIR, "scripts", "field_guide_production", "refresh_working_frame_daily.R")],
                            cwd=PROJECT_DIR, stdout=out, stderr=subprocess.STDOUT).returncode
    print(f"\nREFRESH_EXIT={rc}", flush=True)
    for line in open(rlog, encoding="utf-8", errors="replace"):
        if re.search(r"WORKING \(household-level, new\)|assert_plausible|strata refreshed|Error", line):
            print("  " + line.rstrip(), flush=True)
    print("\nALL SMALL PARTNERS MERGED + REFRESHED. Workbook (05) NOT rebuilt here - run it by hand.", flush=True)


if __name__ == "__main__":
    main()
