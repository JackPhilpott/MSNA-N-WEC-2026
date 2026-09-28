# ==============================================================================
# 2026-09-27 night (Jack, via the Coordinator, under a 1-hour clock): a fresh
# read-only export of the frame for the DO, superseding do_handoff_2026-09-27
# (built 26 Sep 21:35 - that is the baseline this one diffs against). Writes
# ONLY into resampling/output/do_handoff_2026-09-27_night/. Never touches the
# frame or the KoBo tool. Same structure/mechanism as the 26 Sep precedent -
# ported, not re-derived.
# ==============================================================================
import csv
import hashlib
import os
import shutil

B = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
DC = B + r"\output\data\data_collection"
OUT = B + r"\resampling\output\do_handoff_2026-09-27_night"
FILES = ["NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", "NGA_MSNA_2026_strata_level_sampling_frame_v13_WORKING.csv"]


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


os.makedirs(OUT, exist_ok=True)
for f in FILES + ["_frame_version.txt"]:
    shutil.copy2(os.path.join(DC, f), os.path.join(OUT, f))
    assert md5(os.path.join(DC, f)) == md5(os.path.join(OUT, f))

lines = [f"{md5(os.path.join(OUT, f))}  {f}" for f in FILES + ["_frame_version.txt"]]
open(os.path.join(OUT, "MD5.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("Copied + verified:")
for l in lines:
    print(" ", l)
