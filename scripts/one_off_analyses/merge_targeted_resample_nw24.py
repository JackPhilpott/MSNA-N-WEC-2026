# ==============================================================================
# Merges the 2026-08-06 targeted 24-LGA resample (NW Niger-border buffer
# 20km->5km) into the live design frame - replaces ONLY the 24 target LGAs'
# rows in both strata- and household-level frames; every other LGA's rows
# are carried over byte-identical from the live, already-delivered design,
# so partner field materials already distributed outside these 24 LGAs stay
# valid. Writes the merged pair to a new dated archive folder, matching this
# project's existing design-frame-snapshot convention.
# ==============================================================================
import csv
import os

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
LIVE_DIR = PROJECT_DIR + r"\_archive\2026-08-04_design_frame_pre_coverage"
RESAMPLE_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling_targeted_resample_nw24\output"
OUT_DIR = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample"
os.makedirs(OUT_DIR, exist_ok=True)

TARGET_PCODES = {
    "NG021003", "NG021004", "NG021010", "NG021016", "NG021018",
    "NG021021", "NG021024", "NG021027", "NG021033", "NG021034",
    "NG022002", "NG022005", "NG022007", "NG022008",
    "NG034004", "NG034005", "NG034006", "NG034007",
    "NG034008", "NG034009", "NG034013", "NG034019",
    "NG037011", "NG037014",
}
assert len(TARGET_PCODES) == 24


def merge(filename, out_filename=None):
    out_filename = out_filename or filename
    with open(os.path.join(LIVE_DIR, filename), encoding="utf-8") as f:
        live_reader = csv.DictReader(f)
        live_fieldnames = live_reader.fieldnames
        live_rows = list(live_reader)
    with open(os.path.join(RESAMPLE_DIR, filename), encoding="utf-8") as f:
        new_reader = csv.DictReader(f)
        new_fieldnames = new_reader.fieldnames
        new_rows = list(new_reader)

    assert live_fieldnames == new_fieldnames, f"Column mismatch in {filename}"

    kept = [r for r in live_rows if r["adm2_pcode"] not in TARGET_PCODES]
    replaced_count = len(live_rows) - len(kept)
    new_pcodes_present = set(r["adm2_pcode"] for r in new_rows)

    merged = kept + new_rows
    with open(os.path.join(OUT_DIR, out_filename), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=live_fieldnames)
        w.writeheader()
        w.writerows(merged)

    print(f"{filename}: live={len(live_rows)} rows, removed {replaced_count} rows for 24 target LGAs, "
          f"added {len(new_rows)} new rows ({len(new_pcodes_present)} distinct LGAs present in resample) -> merged={len(merged)} rows")
    missing = TARGET_PCODES - new_pcodes_present
    if missing:
        print(f"  NOTE: {len(missing)} target LGA(s) have zero rows in the resample output for this file (expected for pop_types with no eligible population): {missing}")


merge("stage2_sampling_frame.csv")
merge("strata_level_sampling_frame.csv")

print("\nDONE. Merged design frame written to:", OUT_DIR)
