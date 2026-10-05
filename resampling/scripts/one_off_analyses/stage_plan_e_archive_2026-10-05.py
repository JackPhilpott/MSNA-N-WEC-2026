# ==============================================================================
# 2026-10-05 READ-ONLY staging of "plan E" (Jack, in Resampling's window, ~06:25: "yes" to "Plan E: archive" -
# staged and sandbox-tested first, reported before and after). Scope from the Coordinator:
#   1) the 17 reallocated-LGA folders of the outgoing partners (the 17 folder entries of
#      daily_update_config_reallocation_2026-10-04.json's allowed_leftover_prefixes), ALL files in them;
#   2) partner-level files that now mislead, for the partners left with 0 active LGAs: the summary workbook and the
#      LGA_boundaries KML;
#   3) anything that is not a builder output (partner uploads, master logs, returned accessibility reports, guides,
#      earlier archives) is listed separately and STAYS in place.
# Destination: <Partner>/_archived_reallocated_2026-10-04/<same path below the partner>. Nothing is deleted.
# A file the builder still produces (in the current last_published_manifest.csv) is never moved: the next run would
# publish it again. It is listed for a decision instead.
# Reads directory metadata only: a cloud-only (OneDrive Files On-Demand) file is NOT opened, so no download; md5 only
# for files already on disk.
# Usage: python stage_plan_e_archive_2026-10-05.py [--root <package root>] [--out <dir>]
# ==============================================================================
import argparse
import csv
import hashlib
import json
import os
from collections import Counter

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
CFG = os.path.join(S1, "scripts", "daily_update", "daily_update_config_reallocation_2026-10-04.json")
MANIFEST = os.path.join(S1, "output", "daily_update_runs", "state", "last_published_manifest.csv")
ARCH = "_archived_reallocated_2026-10-04"
ZERO_LGA = ["FHI 360", "Solidarités", "Street Child of Nigeria", "IRC", "LHI"]
RECALL = 0x400000 | 0x1000  # FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | FILE_ATTRIBUTE_OFFLINE: cloud-only


def placeholder(path):
    return bool(getattr(os.stat(path), "st_file_attributes", 0) & RECALL)


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("MSNA_PKG_ROOT", r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - NGA MSNA 2026 Package"))
    ap.add_argument("--out", default=os.path.join(RS, "output", "plan_e_2026-10-05"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    prefixes = json.load(open(CFG, encoding="utf-8"))["allowed_leftover_prefixes"]
    folders = [p for p in prefixes if not p.lower().endswith(".xlsx")]
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        produced = {os.path.normcase(os.path.normpath(r["rel_path"])) for r in csv.DictReader(f)}
    moves, stays, keep_produced = [], [], []

    def row(rel, scope, lga):
        p = os.path.join(a.root, rel)
        partner = rel.split(os.sep)[0]
        dst = os.path.join(partner, ARCH, os.path.relpath(rel, partner))
        ph = placeholder(p)
        return {"partner": partner, "scope": scope, "lga": lga, "src_rel": rel, "dst_rel": dst,
                "size": os.path.getsize(p), "cloud_only": "Y" if ph else "N", "md5": "" if ph else md5(p)}

    for fol in folders:  # 1) the 17 reallocated-LGA folders, every file
        base = os.path.join(a.root, fol)
        if not os.path.isdir(base):
            raise SystemExit(f"STOP: {base} is missing")
        for r, _, fs in os.walk(base):
            for fn in sorted(fs):
                rel = os.path.relpath(os.path.join(r, fn), a.root)
                if os.path.normcase(rel) in produced:
                    keep_produced.append({"rel_path": rel, "why": "still produced by the builder (current manifest)"})
                    continue
                moves.append(row(rel, "reallocated_lga", fol.split(os.sep)[-1]))
    for partner in ZERO_LGA:  # 2) + 3) partner-level files of the 0-LGA partners, and what else they hold
        base = os.path.join(a.root, partner)
        for r, ds, fs in os.walk(base):
            ds[:] = [d for d in ds if d != ARCH]
            for fn in sorted(fs):
                full = os.path.join(r, fn)
                rel = os.path.relpath(full, a.root)
                if any(os.path.normcase(rel).startswith(os.path.normcase(f) + os.sep) for f in folders):
                    continue  # already in 1)
                if os.path.normcase(rel) in produced:
                    keep_produced.append({"rel_path": rel, "why": "still produced by the builder (current manifest) - "
                                          "moving it is pointless while the builder makes it; decide separately"})
                    continue
                inner = os.path.relpath(full, base)
                if inner in (f"{partner}_sampling_points_summary.xlsx", f"LGA_boundaries_{partner}.kml"):
                    moves.append(row(rel, "partner_level", ""))
                else:
                    why = ("partner master log" if inner.startswith("master_log") else
                           "earlier archive" if inner.startswith("_archive") else
                           "returned/working accessibility report" if inner.endswith("_accessibility_report.xlsx") else
                           "generic guide" if inner.endswith(".pdf") else "not a builder output for a reallocated LGA")
                    stays.append({"rel_path": rel, "why": why, "size": os.path.getsize(full)})
    clash = [m for m in moves if os.path.exists(os.path.join(a.root, m["dst_rel"]))]
    if clash:
        raise SystemExit(f"STOP: {len(clash)} destination(s) already exist, e.g. {clash[0]['dst_rel']}")
    for name, rows, cols in (("move_list.csv", moves, list(moves[0]) if moves else ["src_rel"]),
                             ("stay_list.csv", stays, ["rel_path", "why", "size"]),
                             ("still_produced_not_moved.csv", keep_produced, ["rel_path", "why"])):
        with open(os.path.join(a.out, name), "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            w.writerows(rows)
    by = Counter((m["partner"], m["lga"] or "(partner level)") for m in moves)
    print(f"root: {a.root}")
    print(f"MOVE {len(moves)} file(s) ({sum(m['size'] for m in moves) / 1e6:.1f} MB; cloud-only {sum(m['cloud_only'] == 'Y' for m in moves)}, "
          f"md5 recorded for {sum(bool(m['md5']) for m in moves)}) into <Partner>/{ARCH}/")
    for (p, l), n in sorted(by.items()):
        print(f"  {p} | {l}: {n}")
    print(f"STAY {len(stays)} file(s): {dict(Counter(s['why'] for s in stays))}")
    print(f"still produced, NOT moved: {len(keep_produced)}" + (f" e.g. {keep_produced[0]['rel_path']}" if keep_produced else ""))
    print(f"lists in {a.out}")


if __name__ == "__main__":
    main()
