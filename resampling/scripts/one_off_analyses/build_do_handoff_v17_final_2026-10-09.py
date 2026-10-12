# ==============================================================================
# 2026-10-09 (#1 b): the v17_final DO hand-off, built from the WORKING frame left by today's Phase 2 run. It supersedes
# the 6 Oct v17 (post-depth) hand-off; the only content change is households achieved since then, removed from the
# WORKING to-do list by the daily refreshes. For the DO's tool update today.
# Steps:
#   1. preconditions: the latest orchestrator run is a real (not dry) run that ended OK; the live WORKING is the one it
#      published; no run holds the lock (pass --test to skip these and build from whatever is live, for a rehearsal);
#   2. proof that only achieved removals changed since the 6 Oct v17 (its hand-off files are the baseline):
#      stage2 WORKING: 0 rows added, 0 rows changed, removed = the sum of the accepted refreshes' "removed" since
#      6 Oct, each with 0 unexplained; strata WORKING: same strata, only achieved_clusters / achieved_sample /
#      realized_moe_pct moved; FULL and the spare register unchanged;
#   3. build_do_handoff_2026-10-04.py (same file set and ALT folder as the 6 Oct v17), then: its "night of 4 Oct"
#      wording made right for today, the spare register added with its README row, MD5.txt and the zip rebuilt.
# The live frame is only read. Refuses to overwrite.
# Usage (from 1_sampling): python resampling/scripts/one_off_analyses/build_do_handoff_v17_final_2026-10-09.py [--out DIR] [--test]
# ==============================================================================
import argparse
import csv
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
DC = os.path.join(S1, "output", "data", "data_collection")
RUNS = os.path.join(S1, "output", "daily_update_runs")
V17 = os.path.join(RS, "output", "do_handoff_v17_post_depth_2026-10-06")
sys.path.insert(0, os.path.join(S1, "scripts", "shared"))
import msna_paths  # noqa: E402
# 2026-10-12 (#17): the live names come from the version on the files (msna_paths); the 6 Oct hand-off keeps its _v17_ names
V_LIVE = msna_paths.frame_version(DC)
S2, ST, FULL = (msna_paths.FRAME_FAMILY[k].format(v=V_LIVE) for k in ("stage2_WORKING", "strata_WORKING", "stage2_FULL"))
S2_V17, ST_V17 = (msna_paths.FRAME_FAMILY[k].format(v="v17") for k in ("stage2_WORKING", "strata_WORKING"))
REG = "buffer_cluster_register.csv"
V17_FULL_MD5, V17_REG_MD5, V17_WORKING_MD5 = "23c20392da92b55025c222e8224068f1", "7721a420715f7e51126df7f978c5149e", "070a24ec6ea122fe28872f11b4219c9d"
ACHIEVED_COLS = {"achieved_clusters", "achieved_sample", "realized_moe_pct"}


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rows(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def accepted_refreshes_since_v17():
    """Real orchestrator runs after the 6 Oct publish whose frame refresh was accepted (frame.restored is False)."""
    out = []
    for p in sorted(glob.glob(os.path.join(RUNS, "2026-10-*", "summary.json"))):
        s = json.load(open(p, encoding="utf-8"))
        if s.get("dry_run") or s["run_id"] <= "2026-10-06_215057" or "frame" not in s or s["frame"].get("restored"):
            continue
        out.append(s)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(RS, "output", "do_handoff_v17_final_2026-10-09"))
    ap.add_argument("--test", action="store_true", help="rehearsal: skip the Phase 2 preconditions")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    live = {f: os.path.join(DC, f) for f in (S2, ST, REG, FULL)}

    # 1. preconditions
    latest = json.load(open(os.path.join(RUNS, "LATEST_SUMMARY.json"), encoding="utf-8"))
    pre = [("latest run is a real run", not latest.get("dry_run")), ("latest run ended OK", latest.get("status") == "OK"),
           ("live WORKING is the one it published", md5(live[S2]) == latest.get("frame", {}).get("working_md5_after")),
           ("no run holds the lock", not os.path.exists(os.path.join(RUNS, ".daily_update.lock")))]
    for name, ok in pre:
        print(f"  [{'PASS' if ok else ('SKIP' if a.test else 'FAIL')}] {name}")
    if not a.test and not all(ok for _, ok in pre):
        sys.exit(f"STOP: Phase 2 has not left a published frame (latest run {latest.get('run_id')}: {latest.get('status')})")

    # 2. only achieved removals since the 6 Oct v17
    base = {r["survey_id"]: r for r in rows(os.path.join(V17, S2_V17))}
    if md5(os.path.join(V17, S2_V17)) != V17_WORKING_MD5:
        sys.exit("STOP: the 6 Oct v17 hand-off WORKING is not 070a24ec")
    now = {r["survey_id"]: r for r in rows(live[S2])}
    added, removed = set(now) - set(base), set(base) - set(now)
    changed = [k for k in set(now) & set(base) if now[k] != base[k]]
    runs = accepted_refreshes_since_v17()
    removed_by_runs = sum(s["frame"]["removed"] for s in runs)
    unexplained = sum(s["frame"].get("unexplained", 0) for s in runs) + sum(s["frame"].get("added", 0) for s in runs)
    sb = {r["strata_id"]: r for r in rows(os.path.join(V17, ST_V17))}
    sn = {r["strata_id"]: r for r in rows(live[ST])}
    moved = {c for k in sb if k in sn for c in sn[k] if sn[k][c] != sb[k].get(c)}
    checks = [
        (f"stage2 WORKING: 0 added (got {len(added)}), 0 changed (got {len(changed)})", not added and not changed),
        (f"stage2 WORKING: {len(removed):,} removed = the accepted refreshes' removals since 6 Oct "
         f"({' + '.join(str(s['frame']['removed']) + ' (' + s['run_id'] + ')' for s in runs)} = {removed_by_runs:,}), 0 unexplained (got {unexplained})",
         len(removed) == removed_by_runs and unexplained == 0),
        (f"strata WORKING: same {len(sb)} strata; columns moved {sorted(moved)} within {sorted(ACHIEVED_COLS)}",
         set(sb) == set(sn) and moved <= ACHIEVED_COLS),
        ("FULL unchanged since v17 (23c20392)", md5(live[FULL]) == V17_FULL_MD5),
        ("spare register unchanged since v17 (7721a420)", md5(live[REG]) == V17_REG_MD5),
    ]
    for name, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if not all(ok for _, ok in checks):
        sys.exit("STOP: something other than achieved removals changed since the 6 Oct v17 - this is not a v17_final")

    # 3. build, then make the README right for today
    if os.path.exists(out) or os.path.exists(out + ".zip"):
        sys.exit(f"STOP: {out} (or its zip) already exists")
    tmp = os.path.join(os.path.dirname(out), "_changes_v17_final.md")
    clusters = len({base[k]["cluster_id"] for k in removed})
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join([
            "**This version supersedes the 6 Oct v17 (post-depth) hand-off. Use it for today's tool update.**", "",
            f"The only change is progress: **{len(removed):,} households** in {clusters:,} clusters, which teams have "
            "completed since 6 Oct, are no longer on the WORKING to-do list. In the strata file only achieved_clusters / "
            "achieved_sample / realized_moe_pct moved.",
            "No clusters, households, targets, spares or partner assignments changed. The FULL frame and the spare register "
            "are unchanged.", "",
            "| refresh run | households removed |", "|---|---|",
            *[f"| {s['run_id']} | {s['frame']['removed']:,} |" for s in runs]]) + "\n")
    try:
        p = subprocess.run([sys.executable, os.path.join(S1, "scripts", "one_off_analyses", "build_do_handoff_2026-10-04.py"),
                            "--out", out, "--changes", tmp, "--baseline-working", os.path.join(V17, S2_V17),
                            "--dest-version", "v17", "--label", "final"], capture_output=True, text=True, encoding="utf-8")
    finally:
        os.remove(tmp)
    if p.returncode:
        sys.exit(f"STOP: the builder failed:\n{p.stdout}\n{p.stderr}")
    readme_p = os.path.join(out, "README.md")
    readme = open(readme_p, encoding="utf-8").read()
    shutil.copy2(live[REG], os.path.join(out, REG))
    reg_rows = len(rows(live[REG]))
    for old, new in [
        ("for the new KoBo tool version (WORKING), night of 4 Oct 2026", "for the new KoBo tool version (WORKING), 9 Oct 2026"),
        ("A read-only copy of the live frame after tonight's final run.",
         f"A read-only copy of the live frame after today's frame refresh and partner publish (run {latest.get('run_id')})."),
        *([("(no internal rename tonight)", "(no internal rename yet)")] if V_LIVE != "v17" else []),  # no version note when the names match
        ("Tonight's starting point:", "Starting point (the 6 Oct v17 hand-off):"),
        (os.path.join(V17, S2_V17),
         "1_sampling/resampling/output/do_handoff_v17_post_depth_2026-10-06/" + S2_V17),
        ("where the count changed tonight", "where the count changed since the 6 Oct v17"),
        ("| start of the night |", "| 6 Oct v17 |"),
        ("## What changed tonight", "## What changed since the 6 Oct v17"),
    ]:
        if readme.count(old) != 1:
            sys.exit(f"STOP: README wording not found once: {old!r}")
        readme = readme.replace(old, new)
    anchor = next(ln for ln in readme.splitlines() if ln.startswith("| `_frame_version.txt` |"))
    readme = readme.replace(anchor, anchor + "\n" + f"| `{REG}` | the {reg_rows} spare clusters, one row each (cluster, stratum, population, "
                            f"partner, rank) - for the DO's reference, not for the tool | 8 columns | `{md5(live[REG])}` |", 1)
    with open(readme_p, "w", encoding="utf-8") as f:
        f.write(readme)
    lines = sorted((f"{md5(os.path.join(r, fn))}  {os.path.relpath(os.path.join(r, fn), out).replace(os.sep, '/')}"
                    for r, _, fs in os.walk(out) for fn in fs if fn != "MD5.txt"), key=lambda x: x.split("  ", 1)[1])
    with open(os.path.join(out, "MD5.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.remove(out + ".zip")
    with zipfile.ZipFile(out + ".zip", "w", zipfile.ZIP_DEFLATED) as z:
        for r, _, fs in os.walk(out):
            for fn in fs:
                z.write(os.path.join(r, fn), os.path.join(os.path.basename(out), os.path.relpath(os.path.join(r, fn), out)))
    with zipfile.ZipFile(out + ".zip") as z:
        bad, names = z.testzip(), z.namelist()
    print(f"hand-off: {out}")
    for ln in lines + [f"{md5(os.path.join(out, 'MD5.txt'))}  MD5.txt"]:
        print("  ", ln)
    print(f"zip: {out}.zip ({os.path.getsize(out + '.zip') / 1e6:.1f} MB, {len(names)} files, md5 {md5(out + '.zip')}); "
          f"zip test: {'OK' if bad is None else 'BAD ' + bad}")
    print("live frame untouched:", all(md5(p_) == m for p_, m in [(live[FULL], V17_FULL_MD5), (live[REG], V17_REG_MD5)]))


if __name__ == "__main__":
    main()
