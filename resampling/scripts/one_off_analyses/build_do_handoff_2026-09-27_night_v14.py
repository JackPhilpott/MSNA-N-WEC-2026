# ==============================================================================
# 2026-09-27 night, v14: re-points do_handoff_2026-09-27_night to the v14 file
# names/content. NOT a pure rename - the previous v13-named packet (built
# 22:42) predates 3 real draws merged afterward (Damboa/Kala-Balge/Ngala,
# 22:56-23:00) and the v14 bump itself (23:11) - this rebuilds from the
# CURRENT live v14 files so the packet reflects everything, not just a
# renamed stale copy. Writes ONLY into resampling/output/do_handoff_2026-09-27_night/.
# ==============================================================================
import csv
import hashlib
import os
import shutil

B = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
DC = B + r"\output\data\data_collection"
OUT = B + r"\resampling\output\do_handoff_2026-09-27_night"
FILES = ["NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"]
OLD_FILES = ["NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", "NGA_MSNA_2026_strata_level_sampling_frame_v13_WORKING.csv"]


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


# remove the superseded v13-named copies from this folder
for f in OLD_FILES:
    p = os.path.join(OUT, f)
    if os.path.exists(p):
        os.remove(p)
        print("removed stale:", f)

for f in FILES + ["_frame_version.txt"]:
    shutil.copy2(os.path.join(DC, f), os.path.join(OUT, f))
    assert md5(os.path.join(DC, f)) == md5(os.path.join(OUT, f))

lines = [f"{md5(os.path.join(OUT, f))}  {f}" for f in FILES + ["_frame_version.txt"]]
open(os.path.join(OUT, "MD5.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("Copied + verified:")
for l in lines:
    print(" ", l)
