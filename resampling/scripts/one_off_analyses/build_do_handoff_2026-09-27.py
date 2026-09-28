# ==============================================================================
# 2026-09-26 evening (Jack, via the Coordinator): a read-only export of the frame for the data officer (DO), who updates the KoBo tool
# from WORKING for Monday 28 Sep. Writes ONLY into resampling/output/do_handoff_2026-09-27/. Never touches the frame, the KoBo tool
# or the old tool_update_2026-09-25_.../frame_for_DO folder (stale, must not be used).
# Main files = the live WORKING pair exactly as written (58 / 31 columns). ALT folder = the same rows without the two audit columns
# (original_partner_covering, coverage_reallocated_on), i.e. the 56 / 29 column schema the DO's earlier files had; only for the case where
# the DO's builder rejects the extra columns (unverified either way).
# ==============================================================================
import csv
import hashlib
import os
import shutil

B = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
DC = B + r"\output\data\data_collection"
OUT = B + r"\resampling\output\do_handoff_2026-09-27"
ALT = OUT + r"\ALT_only_if_the_2_extra_columns_are_rejected_56_and_29_columns"
FILES = ["NGA_MSNA_2026_stage2_sampling_frame_v13_WORKING.csv", "NGA_MSNA_2026_strata_level_sampling_frame_v13_WORKING.csv"]
AUDIT = ["original_partner_covering", "coverage_reallocated_on"]


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.reader(f))


os.makedirs(ALT, exist_ok=True)
for f in FILES + ["_frame_version.txt"]:
    shutil.copy2(os.path.join(DC, f), os.path.join(OUT, f))
    assert md5(os.path.join(DC, f)) == md5(os.path.join(OUT, f))
# ALT: drop the two audit columns, keep every other cell and the row order exactly
for f in FILES:
    rows = rd(os.path.join(DC, f))
    hdr = rows[0]
    keep = [i for i, c in enumerate(hdr) if c not in AUDIT]
    assert len(keep) == len(hdr) - 2
    with open(os.path.join(ALT, f), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        for r in rows:
            w.writerow([r[i] for i in keep])
    back = rd(os.path.join(ALT, f))
    assert back == [[r[i] for i in keep] for r in rows], "ALT round trip differs"
shutil.copy2(os.path.join(DC, "_frame_version.txt"), os.path.join(ALT, "_frame_version.txt"))
lines = []
for d, lab in ((OUT, ""), (ALT, "ALT_only_if_the_2_extra_columns_are_rejected_56_and_29_columns/")):
    for f in FILES + ["_frame_version.txt"]:
        lines.append(f"{md5(os.path.join(d, f))}  {lab}{f}")
open(os.path.join(OUT, "MD5.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")

# numbers for the README, all read from the files just copied
st2 = rd(os.path.join(OUT, FILES[0])); sl = rd(os.path.join(OUT, FILES[1]))
h2, hs = st2[0], sl[0]
n_rows, n_cl = len(st2) - 1, len({r[h2.index("cluster_id")] for r in st2[1:]})
tgt = sum(float(r[hs.index("target_sample")]) for r in sl[1:])
print("stage2 rows", n_rows, "clusters", n_cl, "| strata", len(sl) - 1, "target", tgt, "| columns", len(h2), len(hs))
print("\n".join(lines))
print("stage2 columns:", ", ".join(h2))
print("strata columns:", ", ".join(hs))
