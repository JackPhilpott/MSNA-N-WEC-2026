# ==============================================================================
# Retroactive fix for a real bug Jack found: merge_partner_resample_batch.R's
# generic "fill any column missing from a staged batch as NA" fallback (see
# that script's own updated comment, same date) was defaulting sampling_
# method to NA for every row merged through it, instead of "MSNA Full
# Design" - since that column was introduced 2026-09-11 and this merge
# script has run many times since (09-13's draws, tonight's two rounds),
# NA rows accumulated across every one of those merges, not just tonight's.
#
# Every NA row here is unconditionally a MSNA Full Design row - confirmed
# directly: MSNA Light rows are added ONLY via scripts/one_off_analyses/
# merge_msna_light_3lga_2026-09-11.R, a direct append that never goes
# through merge_partner_resample_batch.R at all, and that script has always
# stamped sampling_method correctly (564 rows show "MSNA Light" in both
# FULL and WORKING today, zero of them NA). So this is a safe, unconditional
# backfill, not a guess.
#
# msna_light_settlement_name is NOT touched - NA/blank is its correct value
# for a non-MSNA-Light row.
#
# Backs up both files first (matches this project's established convention).
# ==============================================================================
import csv
import shutil

FILES = [
    r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv",
    r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v8_WORKING.csv",
]

for path in FILES:
    backup = path.replace(".csv", "_PRE_sampling_method_na_backfill_2026-09-14.csv.bak")
    shutil.copy2(path, backup)
    print(f"Backed up to {backup}")

    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)

    n_fixed = 0
    n_msna_light = 0
    for r in rows:
        v = r.get("sampling_method")
        if v in (None, "", "NA"):
            r["sampling_method"] = "MSNA Full Design"
            n_fixed += 1
        elif v == "MSNA Light":
            n_msna_light += 1

    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"{path}: {n_fixed} row(s) backfilled to 'MSNA Full Design', "
          f"{n_msna_light} row(s) confirmed untouched 'MSNA Light', {len(rows)} total rows.")
