# ==============================================================================
# Marte (Borno, NG008022): relabel exclusion_reason "partner_coverage_declined" -> "insecurity_related_inaccessibility"
# in the two FULL frame files (2026-09-25, Coordinator relaying Jack's decision: "excluded due to insecurity-related
# inaccessibility"). coverage_status stays "not_covered"; nothing else changes. The old value was the design script's DEFAULT
# label for an LGA with no partner, not a recorded reason. Marte has no rows in either WORKING file (asserted), so those are
# left alone. In place, no version bump (values only, roster unchanged).
#
# Byte-preserving: the files are patched by exact text substitution on the affected lines only, so line endings, quoting and
# every other byte are untouched. The result is re-parsed and compared cell by cell against the original.
# DRY-RUN BY DEFAULT (writes nothing). --execute snapshots the 4 frame files + stamp (md5-verified) THEN patches the 2 FULL files.
# Usage: python relabel_marte_exclusion_reason_2026-09-25.py [--execute]
# Afterwards (separate steps): stamp_frame_version.R, canonical sync_sampling_frame_mirrors.R, md5 check x3, tell Dashboard.
# ==============================================================================
import argparse, csv, hashlib, io, shutil, sys
from pathlib import Path

DC = Path(r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\data\data_collection")
V = "v13"
OLD, NEW = "partner_coverage_declined", "insecurity_related_inaccessibility"
FULL = [f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_FULL.csv", f"NGA_MSNA_2026_stage2_sampling_frame_{V}_FULL.csv"]
WORKING = [f"NGA_MSNA_2026_strata_level_sampling_frame_{V}_WORKING.csv", f"NGA_MSNA_2026_stage2_sampling_frame_{V}_WORKING.csv"]
SNAP = DC / "_archive" / "2026-09-25_marte_exclusion_reason_relabel"
EXPECT = {FULL[0]: 1, FULL[1]: 205}


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def patched_text(path):
    """Return (new_text, n_changed, old_rows, new_rows) with only the Marte / OLD lines touched."""
    raw = Path(path).read_bytes().decode("utf-8")
    lines = raw.splitlines(keepends=True)
    rows_old = list(csv.reader(io.StringIO(raw, newline="")))
    assert len(rows_old) == len(lines), f"{Path(path).name}: a field contains a line break; this line-based patch does not apply"
    hdr = rows_old[0]
    i_lga, i_reason, i_status = hdr.index("adm2_name"), hdr.index("exclusion_reason"), hdr.index("coverage_status")
    out, n = [], 0
    for line, row in zip(lines, rows_old):
        if row and row[i_lga] == "Marte" and row[i_reason] == OLD:
            assert row[i_status] == "not_covered", f"unexpected status {row[i_status]}"
            assert line.count(OLD) == 1, "old value occurs other than once on the line"
            line = line.replace(OLD, NEW, 1)
            n += 1
        out.append(line)
    new = "".join(out)
    return new, n, rows_old, list(csv.reader(io.StringIO(new, newline="")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--execute", action="store_true")
    a = ap.parse_args()
    print("EXECUTE" if a.execute else "DRY-RUN")
    # Marte must have no rows in WORKING (otherwise those would need patching too)
    for w in WORKING:
        rows = list(csv.DictReader(open(DC / w, encoding="utf-8-sig", newline="")))
        n = sum(1 for r in rows if r["adm2_name"] == "Marte")
        print(f"  {w}: {len(rows)} rows, Marte rows = {n}")
        assert n == 0, "Marte now has rows in WORKING; the plan needs revisiting"
    plan = {}
    for f in FULL:
        new, n, old_rows, new_rows = patched_text(DC / f)
        assert n == EXPECT[f], f"{f}: {n} rows would change, expected {EXPECT[f]}"
        assert len(old_rows) == len(new_rows) and old_rows[0] == new_rows[0]
        idx = old_rows[0].index("exclusion_reason")
        diffs = [(i, j) for i, (a_, b_) in enumerate(zip(old_rows, new_rows)) for j in range(len(a_)) if a_[j] != b_[j]]
        assert len(diffs) == n and all(j == idx for _, j in diffs), "cell diff is not exactly the exclusion_reason cells of the target rows"
        assert all(new_rows[i][old_rows[0].index("coverage_status")] == "not_covered" for i, _ in diffs)
        print(f"  {f}: {n} rows change; cell-level diff = exactly {n} exclusion_reason cells; all other cells identical; still not_covered")
        plan[f] = new
    if not a.execute:
        return print("(dry-run) nothing written")
    assert not SNAP.exists() or not any(SNAP.iterdir()), "snapshot dir already used"
    SNAP.mkdir(parents=True, exist_ok=True)
    keep = FULL + WORKING + ["_frame_version.txt"]
    with open(SNAP / "MD5_pre_change.txt", "w", encoding="utf-8") as m:
        for f in keep:
            shutil.copy2(DC / f, SNAP / f)
            assert md5(DC / f) == md5(SNAP / f), f"snapshot md5 mismatch {f}"
            m.write(f"{md5(SNAP / f)}  {f}\n")
    print("snapshot written and md5-verified:", SNAP)
    for f, text in plan.items():
        (DC / f).write_bytes(text.encode("utf-8"))
        print(f"  patched {f}: md5 {md5(DC / f)}")
    print("DONE. Next: stamp_frame_version.R, canonical sync_sampling_frame_mirrors.R, md5 check x3, tell Dashboard.")


if __name__ == "__main__":
    main()
