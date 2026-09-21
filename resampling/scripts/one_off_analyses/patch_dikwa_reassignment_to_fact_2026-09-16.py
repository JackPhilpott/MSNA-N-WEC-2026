# ==============================================================================
# Jack's direct instruction (raw comms review, 2026-09-16): Dikwa LGA (Borno)
# should be completely reassigned from Street Child of Nigeria to FACT -
# "and this should be reflected everywhere." Street Child's own accessibility
# report never had any confirmed accessibility status for Dikwa's 10 wards
# (all blank in their returned file) - this is a straight coverage handoff,
# not a data-quality correction.
#
# Scope tonight, per Jack's own explicit confirmation: patch partners_covering
# in the strata-level and household-level frame (FULL + WORKING, both
# currently v9), and separately move Dikwa's wards from Street Child's
# accessibility report to FACT's (handled by a separate script in the same
# batch - merge_accessibility_reports_2026-09-16.py). FACT's/Street Child's
# EXTERNAL partner package (KML/summary workbook in "3. External
# coordination\NGA MSNA 2026 Package\") is explicitly OUT of scope tonight -
# that's the resampling-push tier, sent only with an announced email, per
# this project's established two-tier cadence (see CLAUDE.md's 2026-09-08b
# entry).
#
# Dikwa is solely Street Child's (no shared-LGA blending) - a clean 1:1
# string swap, not a multi-partner comma-list edit.
# ==============================================================================
import csv
import shutil
from datetime import date

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
TODAY = date.today().isoformat()

FILES = [
    PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v9_FULL.csv",
    PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v9_WORKING.csv",
    PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v9_FULL.csv",
    PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v9_WORKING.csv",
]

OLD_PARTNER = "Street Child of Nigeria"
NEW_PARTNER = "FACT"


def backup(path):
    bak = path.replace(".csv", f"_PRE_dikwa_reassignment_{TODAY}.csv.bak")
    shutil.copy2(path, bak)
    print(f"  backed up -> {bak}")


def patch(path):
    print(f"Patching {path} ...")
    backup(path)
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    adm2_i = header.index("adm2_name")
    pc_i = header.index("partners_covering")
    n_patched = 0
    for r in rows[1:]:
        if r[adm2_i].strip().lower() == "dikwa" and r[pc_i] == OLD_PARTNER:
            r[pc_i] = NEW_PARTNER
            n_patched += 1
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows[1:])
    print(f"  patched {n_patched} row(s) (partners_covering: '{OLD_PARTNER}' -> '{NEW_PARTNER}').")


if __name__ == "__main__":
    for path in FILES:
        patch(path)
    print("\nDone.")
