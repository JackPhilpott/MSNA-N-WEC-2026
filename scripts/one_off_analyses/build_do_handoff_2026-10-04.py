# ==============================================================================
# 2026-10-04: the DO hand-off for the new KoBo tool version, built AFTER tonight's final frame run. Same file set as the
# 25-27 Sep hand-offs (Jack: "we updated the WORKING frame and give to the DO to upload and new version of the tool"),
# and only that:
#   <out>/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv        58 columns (as the DO received on 27 Sep)
#   <out>/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv  31 columns
#   <out>/_frame_version.txt                                          the stamp of the two files
#   <out>/ALT_no_audit_cols_56_29/   same two files without
#        original_partner_covering + coverage_reallocated_on (the 25 Sep fallback)
#   <out>/MD5.txt, <out>/README.md (facts computed here + the hand-written "what changed tonight" section)
#   <out>.zip                                                          one file Jack can attach, md5 printed
# Copies are byte-identical to the live files (md5-checked); the live frame is only read. Refuses to overwrite.
#
# Usage: python build_do_handoff_2026-10-04.py --out <dir> --changes <changes.md> [--baseline-working <csv>]
#   --changes          a markdown file with the "what changed tonight" text (written by hand after the final run)
#   --baseline-working the WORKING the night started from (default: tonight's pre-Step-1 frame archive), for the
#                      computed row / cluster / partner deltas
# ==============================================================================
import argparse
import csv
import hashlib
import os
import shutil
import sys
import zipfile
from collections import Counter

DC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "output", "data", "data_collection")
S2, ST, STAMP = ("NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv",
                 "_frame_version.txt")
AUDIT = ("original_partner_covering", "coverage_reallocated_on")
BASELINE = os.path.join(DC, "_archive", "2026-10-04_daily_update_2026-10-04_222328", S2)


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rows(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        rd = csv.DictReader(f)
        return rd.fieldnames, list(rd)


def drop_audit(src, dst):
    with open(src, encoding="utf-8-sig", newline="") as f:
        rd = csv.reader(f)
        hdr = next(rd)
        keep = [i for i, c in enumerate(hdr) if c not in AUDIT]
        if len(keep) != len(hdr) - 2:
            sys.exit(f"STOP: {src} does not carry both audit columns")
        with open(dst, "w", encoding="utf-8", newline="") as g:
            w = csv.writer(g)
            w.writerow([hdr[i] for i in keep])
            for r in rd:
                w.writerow([r[i] for i in keep])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--changes", required=True)
    ap.add_argument("--baseline-working", default=BASELINE)
    ap.add_argument("--dest-version", default="v14", help="DO-facing frame version in the hand-off file names (e.g. v15)")
    ap.add_argument("--label", default="", help="DO-facing label, e.g. 'pre-spares'")
    a = ap.parse_args()
    dv = a.dest_version
    dname = lambda f: f.replace("_v14_", f"_{dv}_")
    out = os.path.abspath(a.out)
    if os.path.exists(out) or os.path.exists(out + ".zip"):
        sys.exit(f"STOP: {out} (or its zip) already exists - choose a new name")
    os.makedirs(os.path.join(out, "ALT_no_audit_cols_56_29"))
    live = {f: os.path.join(DC, f) for f in (S2, ST, STAMP)}
    before = {f: md5(p) for f, p in live.items()}
    for f, p in live.items():
        shutil.copy2(p, os.path.join(out, dname(f)))
        if md5(os.path.join(out, dname(f))) != before[f]:
            sys.exit(f"STOP: copy of {f} does not match the live file")
    alt = os.path.join(out, "ALT_no_audit_cols_56_29")
    for f in (S2, ST):
        drop_audit(live[f], os.path.join(alt, dname(f)))
    shutil.copy2(live[STAMP], os.path.join(alt, STAMP))

    h2, r2 = rows(live[S2])
    hs, rs = rows(live[ST])
    _, r0 = rows(a.baseline_working)
    clusters = len({r["cluster_id"] for r in r2})
    target = sum(float(r["target_sample"] or 0) for r in rs)
    pc_now = Counter(r["partners_covering"] for r in r2)
    pc_before = Counter(r["partners_covering"] for r in r0)
    facts = [
        f"| `{dname(S2)}` | {len(r2):,} rows, {clusters:,} clusters | {len(h2)} columns | `{md5(live[S2])}` |",
        f"| `{dname(ST)}` | {len(rs)} strata, total target {target:,.0f} | {len(hs)} columns | `{md5(live[ST])}` |",
        f"| `{STAMP}` | stamp of the two files above | | `{md5(live[STAMP])}` |",
    ]
    mapping = [f"| `{dname(f)}` | `1_sampling/output/data/data_collection/{f}` | `{before[f]}` |" for f in (S2, ST, STAMP)]
    delta = [f"| {p or '(blank)'} | {pc_before.get(p, 0):,} | {pc_now.get(p, 0):,} | {pc_now.get(p, 0) - pc_before.get(p, 0):+,} |"
             for p in sorted(set(pc_now) | set(pc_before), key=lambda x: (x or ""))
             if pc_now.get(p, 0) != pc_before.get(p, 0)]
    with open(a.changes, encoding="utf-8") as f:
        changes = f.read().strip()
    readme = "\n".join([
        f"# Sampling frame {dv}{(' (' + a.label + ')') if a.label else ''} for the new KoBo tool version (WORKING), night of 4 Oct 2026", "",
        "A read-only copy of the live frame after tonight's final run. Nothing here has been uploaded anywhere.",
        *([f"**Version note:** for the DO this frame is **{dv}**{(' (' + a.label + ')') if a.label else ''}. Inside our workspace the same files",
           "are still named `_v14_` (no internal rename tonight); their content is byte-identical to the files here, see the",
           "mapping below. The DO's daily runs are unaffected: they keep reading the `_v14_` files.", ""] if dv != "v14" else []),
        "Hand over the two files in this folder (58 / 31 columns, the same schema the DO received on 27 Sep). Use the",
        "`ALT_...` folder only if the tool build rejects the 2 audit columns (`original_partner_covering`,",
        "`coverage_reallocated_on`).", "",
        "## Files (md5 also in `MD5.txt`)", "| file | content | columns | md5 |", "|---|---|---|---|", *facts, "",
        f"Tonight's starting point: {len(r0):,} WORKING rows ({a.baseline_working.split(os.sep + '_archive' + os.sep)[-1]}).", "",
        *(["## Mapping to the internal files (byte-identical)", "| hand-off file | internal file | md5 |", "|---|---|---|", *mapping, ""]
          if dv != "v14" else []),
        "## WORKING rows by `partners_covering`, where the count changed tonight",
        "| partners_covering | start of the night | now | change |", "|---|---|---|---|", *delta, "",
        "## What changed tonight", changes, ""])
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
        f.write(readme)
    lines = []
    for root, _, files in os.walk(out):
        for fn in sorted(files):
            p = os.path.join(root, fn)
            lines.append(f"{md5(p)}  {os.path.relpath(p, out).replace(os.sep, '/')}")
    with open(os.path.join(out, "MD5.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(lines, key=lambda x: x.split('  ', 1)[1])) + "\n")
    with zipfile.ZipFile(out + ".zip", "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(out):
            for fn in files:
                p = os.path.join(root, fn)
                z.write(p, os.path.join(os.path.basename(out), os.path.relpath(p, out)))
    with zipfile.ZipFile(out + ".zip") as z:
        bad = z.testzip()
    after = {f: md5(p) for f, p in live.items()}
    print(f"hand-off: {out}")
    for ln in sorted(lines, key=lambda x: x.split('  ', 1)[1]):
        print("  ", ln)
    print(f"zip: {out}.zip ({os.path.getsize(out + '.zip') / 1e6:.1f} MB, md5 {md5(out + '.zip')}); zip test: {'OK' if bad is None else 'BAD ' + bad}")
    print("live frame untouched:", before == after)


if __name__ == "__main__":
    main()
