# ==============================================================================
# 2026-10-05 "plan E" mover (Jack's go in Resampling's window ~06:25, conditional on staging + a sandbox test):
# moves the files of stage_plan_e_archive_2026-10-05.py's move_list.csv to <Partner>/_archived_reallocated_2026-10-04/
# inside the same package root. A move within one OneDrive/SharePoint library is a rename (cloud-only files are NOT
# downloaded). Nothing is deleted. All pre-checks pass before the first move, or nothing moves:
#   every source exists with the listed size (and md5 where one was recorded), no destination exists.
# Each move is logged (moved_log_<time>.csv); --rollback <log> moves them back the same way.
# Default is a DRY RUN (pre-checks only). Usage:
#   python apply_plan_e_archive_2026-10-05.py --list <move_list.csv> [--root <package root>] [--execute]
#   python apply_plan_e_archive_2026-10-05.py --rollback <moved_log.csv> [--root <package root>] [--execute]
# ==============================================================================
import argparse
import csv
import datetime
import hashlib
import os
import stat
import sys

RECALL = 0x400000 | 0x1000


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def cloud_only(path):
    return bool(getattr(os.stat(path), "st_file_attributes", 0) & RECALL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("MSNA_PKG_ROOT", r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - NGA MSNA 2026 Package"))
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--list")
    g.add_argument("--rollback")
    g.add_argument("--cleanup", help="a moved_log: only remove the folders that move left empty (no file is touched)")
    ap.add_argument("--execute", action="store_true")
    a = ap.parse_args()
    if a.cleanup:
        with open(a.cleanup, encoding="utf-8", newline="") as f:
            done = list(csv.DictReader(f))
        if not a.execute:
            print(f"DRY RUN - would remove the empty folders left by {len(done)} logged move(s) (add --execute)")
            return
        cleanup(a.root, done, os.path.basename(a.cleanup).startswith("rolled_back"),
                a.cleanup.replace(".csv", f"_empty_dirs_removed_{datetime.datetime.now():%H%M%S}.txt"))
        return
    src_file = a.list or a.rollback
    with open(src_file, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    if a.rollback:  # reverse a move log: dst -> src
        rows = [{"src_rel": r["dst_rel"], "dst_rel": r["src_rel"], "size": r["size"], "md5": ""} for r in reversed(rows)]
    problems = []
    for r in rows:
        s, d = os.path.join(a.root, r["src_rel"]), os.path.join(a.root, r["dst_rel"])
        if not os.path.isfile(s):
            problems.append(f"source missing: {r['src_rel']}")
            continue
        if os.path.getsize(s) != int(r["size"]):
            problems.append(f"size changed since staging: {r['src_rel']} ({os.path.getsize(s)} vs {r['size']})")
        if r.get("md5") and not cloud_only(s) and md5(s) != r["md5"]:
            problems.append(f"content changed since staging: {r['src_rel']}")
        if os.path.exists(d):
            problems.append(f"destination exists: {r['dst_rel']}")
    print(f"{'ROLLBACK' if a.rollback else 'MOVE'} {len(rows)} file(s) under {a.root}: pre-checks "
          f"{'PASS' if not problems else 'FAIL (' + str(len(problems)) + ')'}")
    for p in problems[:20]:
        print("  " + p)
    if problems:
        sys.exit("STOP: nothing moved")
    if not a.execute:
        print("DRY RUN - nothing moved (add --execute)")
        return
    log = os.path.join(os.path.dirname(os.path.abspath(src_file)),
                       f"{'rolled_back' if a.rollback else 'moved'}_log_{datetime.datetime.now():%Y-%m-%d_%H%M%S}.csv")
    done = []
    try:
        for r in rows:
            s, d = os.path.join(a.root, r["src_rel"]), os.path.join(a.root, r["dst_rel"])
            os.makedirs(os.path.dirname(d), exist_ok=True)
            os.rename(s, d)
            done.append({"src_rel": r["src_rel"], "dst_rel": r["dst_rel"], "size": r["size"],
                         "moved_at": datetime.datetime.now().isoformat(timespec="seconds")})
    finally:
        with open(log, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["src_rel", "dst_rel", "size", "moved_at"])
            w.writeheader()
            w.writerows(done)
        print(f"moved {len(done)} of {len(rows)}; log {log}")
    bad = [r for r in done if os.path.exists(os.path.join(a.root, r["src_rel"]))
           or not os.path.isfile(os.path.join(a.root, r["dst_rel"]))
           or os.path.getsize(os.path.join(a.root, r["dst_rel"])) != int(r["size"])]
    print(f"post-check: {len(done) - len(bad)} of {len(done)} at the destination with the same size, source gone -> "
          f"{'PASS' if not bad and len(done) == len(rows) else 'FAIL'}")
    if bad or len(done) != len(rows):
        sys.exit(1)
    # Folders left with no file at all (the suite counts stale LGA *folders*, and an empty "Argungu" in a package
    # confuses teams). os.rmdir only ever removes an EMPTY directory - no file can be deleted here. Forward move: the
    # moved LGA folders (incl. any that were empty from the start, e.g. Tsafe/IDP/KML) and then their state folder if
    # nothing else is left. Rollback: the emptied _archived_reallocated_2026-10-04 trees.
    cleanup(a.root, done, bool(a.rollback), log.replace(".csv", "_empty_dirs_removed.txt"))


def rmdir_empty(d):
    """Remove d only if it is an empty directory. OneDrive marks synced folders ReadOnly, which makes Windows refuse
    RemoveDirectory (WinError 5, seen 5 Oct 08:03): clear that attribute, then retry once. Never touches a file."""
    if not os.path.isdir(d) or os.listdir(d):
        return False
    try:
        os.rmdir(d)
    except PermissionError:
        os.chmod(d, stat.S_IWRITE | stat.S_IREAD | stat.S_IEXEC)
        os.rmdir(d)
    return True


def cleanup(root, done, rollback, out_txt):
    if rollback:
        roots = sorted({os.sep.join(r["src_rel"].split(os.sep)[:2]) for r in done})  # <Partner>/_archived_...
        states = []
    else:
        roots = sorted({os.sep.join(r["src_rel"].split(os.sep)[:3]) for r in done if len(r["src_rel"].split(os.sep)) > 3})
        states = sorted({os.path.dirname(x) for x in roots})
    removed, failed = [], []
    cands =sorted({t[0] for top in roots for t in os.walk(os.path.join(root, top))}, key=lambda x: -x.count(os.sep))
    for d in cands + [os.path.join(root, s) for s in states]:
        try:
            if rmdir_empty(d):
                removed.append(os.path.relpath(d, root))
        except OSError as e:
            failed.append(f"{os.path.relpath(d, root)}: {e}")
    with open(out_txt, "w", encoding="utf-8") as f:
        f.write("\n".join(removed) + "\n" + ("\nFAILED:\n" + "\n".join(failed) + "\n" if failed else ""))
    still = [x for x in roots if os.path.isdir(os.path.join(root, x))]
    print(f"empty folders removed: {len(removed)} (failed {len(failed)}); of {len(roots)} {'archive' if rollback else 'moved LGA'} "
          f"folder(s), {len(still)} still present{' (' + ', '.join(still[:5]) + ')' if still else ''}")
    for x in failed[:5]:
        print("  " + x)


if __name__ == "__main__":
    main()
