# ==============================================================================
# 2026-10-12: the v18 DO hand-off (Jack's go in Resampling's window: "v18 hand-off now"), built from the WORKING frame
# published at 15:37 (run 2026-10-12_153132), so the KoBo tool gets today's Maru points. The internal files keep their
# _v17_ names (no internal rename yet); the README maps v17 -> v18, as on 4-6 Oct.
# Steps:
#   1. preconditions: the latest orchestrator run is a real run that ended OK; the live WORKING is the one it published;
#      no run holds the lock (--test skips these, for a rehearsal);
#   2. what changed since the 9 Oct v17_final hand-off (its WORKING is the baseline): rows added / removed / changed,
#      split into the Maru accessibility change, the Maru redraw + depth top-up, and progress from the daily refreshes;
#   3. build_do_handoff_2026-10-04.py --dest-version v18 (same file set and ALT folder as v17_final), then today's wording
#      in the README, the spare register with its README row, MD5.txt and the zip rebuilt.
# The live frame is only read. Refuses to overwrite.
# Usage (from 1_sampling): py resampling/scripts/one_off_analyses/build_do_handoff_v18_maru_2026-10-12.py [--out DIR] [--test]
# ==============================================================================
import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile
from collections import Counter

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
DC = os.path.join(S1, "output", "data", "data_collection")
RUNS = os.path.join(S1, "output", "daily_update_runs")
sys.path.insert(0, os.path.join(S1, "scripts", "shared"))
import msna_paths  # noqa: E402

V17F = os.path.join(RS, "output", "do_handoff_v17_final_2026-10-09")
BASE = os.path.join(V17F, "NGA_MSNA_2026_stage2_sampling_frame_v17_WORKING.csv")
BASE_MD5_PREFIX = "d3ab4295"   # the 9 Oct v17_final WORKING, as recorded in the Coordinator's verification
REG = "buffer_cluster_register.csv"
MARU_NEW = {f"non_idp_NG037010_supp{i}" for i in range(33, 39)}
MARU_DEPTH = {f"non_idp_NG037010_{c}" for c in ("supp2", "supp3", "supp11", "supp12", "supp19", "supp21")}
MARU_CROSS_WARD = {"non_idp_NG037010_supp18", "non_idp_NG037010_supp28"}


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rows(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(RS, "output", "do_handoff_v18_maru_2026-10-12"))
    ap.add_argument("--test", action="store_true", help="rehearsal: skip the publish preconditions")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    live_w = msna_paths.frame_file("stage2_WORKING")

    # 1. preconditions
    latest = json.load(open(os.path.join(RUNS, "LATEST_SUMMARY.json"), encoding="utf-8"))
    pre = [("latest run is a real run", not latest.get("dry_run")), ("latest run ended OK", latest.get("status") == "OK"),
           ("live WORKING is the one it published", md5(live_w) == latest.get("frame", {}).get("working_md5_after")),
           ("no run holds the lock", not os.path.exists(os.path.join(RUNS, ".daily_update.lock")))]
    if a.test:
        pre = [(name + " (skipped: --test)", True) for name, _ in pre]
    pre.append(("the v17_final baseline is the 9 Oct hand-off (d3ab4295)", md5(BASE).startswith(BASE_MD5_PREFIX)))
    for name, ok in pre:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if not all(ok for _, ok in pre):
        sys.exit(f"STOP: preconditions not met (latest run {latest.get('run_id')}: {latest.get('status')})")
    if os.path.exists(out) or os.path.exists(out + ".zip"):
        sys.exit(f"STOP: {out} (or its zip) already exists")

    # 2. what changed since v17_final
    base = {r["survey_id"]: r for r in rows(BASE)}
    now = {r["survey_id"]: r for r in rows(live_w)}
    added, removed = set(now) - set(base), set(base) - set(now)
    changed = [k for k in set(now) & set(base) if now[k] != base[k]]

    def why_removed(r):
        if r["adm2_name"] == "Maru" and r["adm1_name"] == "Zamfara" and (r["adm3_name"] != "Maru" or r["cluster_id"] in MARU_CROSS_WARD):
            return "maru_access"
        return "progress"

    def why_added(r):
        return "maru_new" if r["cluster_id"] in MARU_NEW else ("maru_depth" if r["cluster_id"] in MARU_DEPTH else "put_back")

    rem = Counter(why_removed(base[k]) for k in removed)
    add = Counter(why_added(now[k]) for k in added)
    chg = Counter("maru_depth" if now[k]["cluster_id"] in MARU_DEPTH else "other:" + "+".join(sorted(c for c in now[k] if now[k][c] != base[k].get(c)))
                  for k in changed)
    rem_cl = len({base[k]["cluster_id"] for k in removed if why_removed(base[k]) == "progress"})
    put_back_cl = len({now[k]["cluster_id"] for k in added if why_added(now[k]) == "put_back"})
    print(f"since v17_final: removed {len(removed):,} {dict(rem)}; added {len(added):,} {dict(add)}; changed {len(changed):,} {dict(chg)}")
    if any(k.startswith("other:") for k in chg):
        sys.exit("STOP: rows changed for a reason other than the Maru depth top-up - look before handing over")
    run_ids = sorted(d for d in os.listdir(RUNS) if os.path.isdir(os.path.join(RUNS, d)) and d[:4].isdigit()
                     and d > "2026-10-09_122718" and not d.endswith("_DRYRUN"))

    tmp = os.path.join(os.path.dirname(out), "_changes_v18_maru.md")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join([
            "**This version supersedes v17_final (9 Oct). Use it for the next tool update: it carries the new Maru points.**", "",
            "1. **Maru LGA (Zamfara, INTERSOS): only the main Maru town ward is accessible.** Jack Philpott's instruction of 12 Oct 2026, "
            "relaying the INTERSOS field team's report: all other Maru wards are inaccessible because of insecurity.",
            f"   - {rem['maru_access']:,} to-do points left the list: those in the closed wards (Ruwan Doruma, Mayanchi, Bena, Gwashi), "
            "plus the single Maru-ward point of each of the two clusters that straddled a closed ward (too few accessible households left).",
            "   - Maru IDP has no to-do points left (the only accessible site, Shiyar Fada, is complete).",
            f"2. **Maru Non-IDP redraw, all inside Maru ward:** {add['maru_new']:,} points in 6 new clusters "
            "(`non_idp_NG037010_supp33` to `supp38`), and "
            f"{add['maru_depth']:,} points added to 6 existing clusters (`supp2`, `supp3`, `supp11`, `supp12`, `supp19`, `supp21`), "
            f"whose targets go from 6 to 12 households ({chg['maru_depth']:,} existing rows of those clusters carry the new target).",
            f"3. **Progress:** {rem['progress']:,} points in {rem_cl:,} clusters completed since 9 Oct left the list; "
            f"{add['put_back']:,} points in {put_back_cl:,} clusters came back on it after the 12 Oct audit refresh "
            "(interviews no longer counted as achieved).", "",
            "No other cluster, target, spare or partner assignment changed.",
            f"Refresh/publish runs since v17_final: {', '.join(run_ids)}."]) + "\n")
    try:
        p = subprocess.run([sys.executable, os.path.join(S1, "scripts", "one_off_analyses", "build_do_handoff_2026-10-04.py"),
                            "--out", out, "--changes", tmp, "--baseline-working", BASE, "--dest-version", "v18", "--label", "Maru update"],
                           capture_output=True, text=True, encoding="utf-8")
    finally:
        os.remove(tmp)
    if p.returncode:
        sys.exit(f"STOP: the builder failed:\n{p.stdout}\n{p.stderr}")

    # 3. today's wording, the spare register, MD5.txt and the zip
    readme_p = os.path.join(out, "README.md")
    readme = open(readme_p, encoding="utf-8").read()
    shutil.copy2(os.path.join(DC, REG), os.path.join(out, REG))
    for old, new in [
        ("for the new KoBo tool version (WORKING), night of 4 Oct 2026", "for the new KoBo tool version (WORKING), 12 Oct 2026"),
        ("A read-only copy of the live frame after tonight's final run.",
         f"A read-only copy of the live frame after today's frame update and partner publish (run {latest.get('run_id')})."),
        ("(no internal rename tonight)", "(no internal rename yet)"),
        ("Tonight's starting point:", "Starting point (the 9 Oct v17_final hand-off):"),
        (BASE, "1_sampling/resampling/output/do_handoff_v17_final_2026-10-09/NGA_MSNA_2026_stage2_sampling_frame_v17_WORKING.csv"),
        ("where the count changed tonight", "where the count changed since v17_final"),
        ("| start of the night |", "| v17_final (9 Oct) |"),
        ("## What changed tonight", "## What changed since v17_final (9 Oct)"),
    ]:
        if readme.count(old) != 1:
            sys.exit(f"STOP: README wording not found once: {old!r}")
        readme = readme.replace(old, new)
    anchor = next(ln for ln in readme.splitlines() if ln.startswith("| `_frame_version.txt` |"))
    readme = readme.replace(anchor, anchor + "\n" + f"| `{REG}` | the {len(rows(os.path.join(DC, REG)))} spare clusters, one row each (cluster, stratum, "
                            f"population, partner, rank) - for the DO's reference, not for the tool | 8 columns | `{md5(os.path.join(DC, REG))}` |", 1)
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
    print("live WORKING untouched:", md5(live_w) == latest.get("frame", {}).get("working_md5_after"))


if __name__ == "__main__":
    main()
