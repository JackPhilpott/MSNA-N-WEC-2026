#!/usr/bin/env python3
# ==============================================================================
# run_frame_and_partner_update.py - PHASE 2 of the data officer's daily run.
# Written 4 Oct 2026 for the week Jack is away. 2_monitoring's launcher calls it
# after Phase 1 (data refresh + dashboard deploy) has exited 0. A failure here
# never touches Phase 1's deploy.
#
# One run is the proven 2 Oct afternoon chain, made fail-safe:
#   preflight -> archive the frame -> refresh WORKING (the Step 0 accessibility
#   resweep runs inside it) -> HARD frame checks (on failure the archived frame
#   is put back automatically) -> stamp + mirror sync -> partner packages built
#   into STAGING -> daily workbooks into the same staging -> MAP CHECK -> the
#   validity gate on staging -> publish to the live partner folders ONLY on a
#   pass (changed files only, backups first, all-or-nothing with rollback)
#   -> 05 (informational, never blocks) -> summary.
#
# Usage (any working directory; the workspace comes from MSNA_WORKSPACE or this
# file's own location):
#   <python> run_frame_and_partner_update.py [--dry-run] [--config FILE]
#   <python> run_frame_and_partner_update.py --no-publish
#       Frame-only: the real refresh, checks, stamp, mirror sync, staged build and
#       gate, but nothing is published (e.g. while OneDrive is not syncing). The
#       frame is accepted; the next normal run rebuilds and publishes.
#   <python> run_frame_and_partner_update.py --check-env
#   <python> run_frame_and_partner_update.py --reseed-baseline [--submissions-dir DIR]
#       Accept the CURRENT frame as the baseline that the next run's changes are
#       explained against. Run it after any resampling merge, never routinely.
#   <python> run_frame_and_partner_update.py --make-sandbox DIR
#       Copy the files this chain reads into DIR (for tests).
#
# Exit codes:
#   0 OK      published, nothing new to do, or (dry run) would publish
#   1 BLOCKED a hard check failed; partners keep their last good files, and if
#             the block was frame-level the frame was restored
#   2 ERROR   environment / crash / lock held; same guarantees
# Summary: 1_sampling/output/daily_update_runs/LATEST_SUMMARY.json and run folder.
# Guard levels and what each check means: README_daily_update.md beside this file.
# ==============================================================================
import argparse
import csv
import datetime
import glob
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import traceback
from collections import Counter, defaultdict


def _msna_shared_dir():
    for start in (os.environ.get("MSNA_WORKSPACE", "").strip(), os.path.dirname(os.path.abspath(__file__)), os.getcwd()):
        d = os.path.abspath(start) if start else ""
        while d:
            cand = os.path.join(d, "1_sampling", "scripts", "shared")
            if os.path.isfile(os.path.join(cand, "msna_paths.py")):
                return cand
            parent = os.path.dirname(d)
            d = "" if parent == d else parent
    raise SystemExit("Cannot find 1_sampling/scripts/shared/msna_paths.py - set MSNA_WORKSPACE.")


sys.path.insert(0, _msna_shared_dir())
import msna_paths  # noqa: E402

EXIT_OK, EXIT_BLOCKED, EXIT_ERROR = 0, 1, 2
FRAME_REL = os.path.join("1_sampling", "output", "data", "data_collection")
FULL_CSV = "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"
WORKING_CSV = "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv"
STRATA_FULL_CSV = "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"
STRATA_WORKING_CSV = "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"
CLUSTER_STATUS_CSV = "NGA_MSNA_2026_cluster_status_v14.csv"
MIRRORED = [FULL_CSV, WORKING_CSV, STRATA_FULL_CSV, STRATA_WORKING_CSV, "_frame_version.txt"]
# Columns that legitimately move with new submissions; everything else must hold still all week.
STRATA_SUBMISSION_COLS = {"achieved_sample", "achieved_clusters", "realized_moe_pct"}
CLUSTER_STATUS_SUBMISSION_COLS = {"n_achieved", "status"}
SKIP_STAGED_ROOT_FILES = {"dc_package_uuid_reconciliation_report.csv", "daily_refresh_map_check_STAGED.csv"}
# Every non-script input the chain reads. A run is skipped as NO_CHANGE only if ALL of these are unchanged since
# the last published run (4 Oct test T4: a changed exclusion list with unchanged submissions was skipped).
FINGERPRINT_INPUTS = {
    "real_submissions": ("2_monitoring", "data", "real_submissions.csv"),
    "overlay": ("2_monitoring", "data", "CONFIRMED_DELETIONS_OVERLAY.csv"),
    "working": ("1_sampling", "output", "data", "data_collection", WORKING_CSV),
    "full": ("1_sampling", "output", "data", "data_collection", FULL_CSV),
    "strata_full": ("1_sampling", "output", "data", "data_collection", STRATA_FULL_CSV),
    "master_ward_accessibility": ("1_sampling", "resampling", "output", "master_accessibility_status_ward_level.csv"),
    "cluster_accessibility_overlay": ("1_sampling", "resampling", "output", "cluster_accessibility_overlay.csv"),
    "target_correction_dropped": ("1_sampling", "resampling", "output", "target_correction_dropped_clusters.csv"),
    "targets": ("1_sampling", "resampling", "output", "target_sample_representativity_last_run.csv"),
    "partner_coverage_xlsx": ("1_sampling", "input_data", "boundaries", "partner_coverage", "Partnerscoverage.xlsx"),
    "idp_camp_backup_points": ("1_sampling", "output", "data", "data_collection", "idp_camp_backup_points.csv"),
    "spare_register": ("1_sampling", "output", "data", "data_collection", "buffer_cluster_register.csv"),  # "missing" = none
}
R05_OUTPUTS = ["strata_representativity_status.csv", "target_sample_representativity_last_run.csv",
               "NGA_MSNA_2026_accessibility_impact_workbook.xlsx",
               "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING_with_accessibility.csv"]

PRESETS = {
    "strict": {"working_change_rule": "explained", "max_unexplained_working_rows": 0, "full_must_be_unchanged": True,
               "require_gate": True, "require_map_check_ok": True, "max_leftover_files": 25},
    "standard": {"working_change_rule": "bounded", "max_unexplained_working_rows": 50, "full_must_be_unchanged": True,
                 "require_gate": True, "require_map_check_ok": True, "max_leftover_files": 60},
    "lenient": {"working_change_rule": "report_only", "max_unexplained_working_rows": None, "full_must_be_unchanged": False,
                "require_gate": False, "require_map_check_ok": False, "max_leftover_files": 200},
}
# keep_* = 0 means keep everything (default: nothing is ever deleted unattended; ~1 GB a week, mostly the
# 117 MB daily frame archive). Set a number to keep only that many of the newest.
DEFAULTS = {"guard_level": "strict", "skip_if_unchanged": True, "archive_leftover_package_files": True,
            # a one-off structural night (e.g. a reallocation): every no-longer-produced file must sit under one of these
            # package-relative paths (folders or files); empty = no such check
            "allowed_leftover_prefixes": [],
            "run_05_after_publish": True, "keep_runs": 0, "keep_frame_archives": 0, "keep_package_backups": 0,
            "timeouts_min": {"refresh": 45, "stamp": 10, "sync": 15, "build": 40, "daily": 40, "gate": 40, "r05": 40, "renv": 5}}

# Files a sandbox needs: (path relative to the workspace, kind). "tree" skips _archive* and run_history folders.
SANDBOX_ITEMS = [
    ("1_sampling/scripts", "tree"), ("1_sampling/resampling/scripts", "tree"),
    (FRAME_REL, "top"), ("1_sampling/output/maps/lga_summary", "tree"),
    ("1_sampling/resampling/output/master_accessibility_status_ward_level.csv", "file"),
    ("1_sampling/resampling/output/master_accessibility_status_lga_level.csv", "file"),
    ("1_sampling/resampling/output/cluster_accessibility_overlay.csv", "file"),
    ("1_sampling/resampling/output/target_correction_dropped_clusters.csv", "file"),
    ("1_sampling/resampling/output/target_sample_representativity_last_run.csv", "file"),
    # 05 (run after a publish) also reads these three; without them a sandbox test's 05 step fails (informational only)
    ("1_sampling/resampling/output/gis/accessible_area_lga_ward_portions.csv", "file"),
    ("1_sampling/resampling/output/gis/remaining_eligible_pool_non_idp.csv", "file"),
    ("1_sampling/resampling/output/gis/remaining_eligible_pool_idp.csv", "file"),
    ("1_sampling/input_data/boundaries/partner_coverage/Partnerscoverage.xlsx", "file"),
    ("1_sampling/_archive/2026-08-06_design_frame_post_nw_targeted_resample/strata_level_sampling_frame.csv", "file"),
    ("1_sampling/output/daily_update_runs/state", "tree-optional"),
    ("2_monitoring/data", "top"),  # ~16 MB; dashboard_app/global.R reads ../data/real_meta.rds and others
    ("2_monitoring/input_data", "tree"),  # ~115 MB without archives; dashboard_app/global.R reads ../input_data/*
    ("2_monitoring/dashboard_app", "tree"),
    ("2_monitoring/scripts", "tree"), ("validity_checks", "tree"),
]


class Blocked(Exception):
    pass


class RunError(Exception):
    pass


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def read_table(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        r = csv.reader(f)
        header = next(r)
        return header, [row for row in r]


def now_s():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------------ run context
class Run:
    def __init__(self, args):
        self.args = args
        self.live_ws = msna_paths.workspace()
        self.live_pkg_root = msna_paths.pkg_root()
        self.cfg = self._load_config(args.config)
        self.run_id = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        self.runs_root = os.path.join(self.live_ws, "1_sampling", "output", "daily_update_runs")
        self.state_dir = os.path.join(self.runs_root, "state")
        self.run_dir = os.path.join(self.runs_root, self.run_id + ("_DRYRUN" if args.dry_run else ""))
        os.makedirs(self.run_dir, exist_ok=True)
        self._log = open(os.path.join(self.run_dir, "run_log.txt"), "a", encoding="utf-8")
        self.checks, self.actions = [], []
        self.summary = {"run_id": self.run_id, "dry_run": bool(args.dry_run), "started": now_s(),
                        "machine": socket.gethostname(), "user": os.environ.get("USERNAME", ""),
                        "workspace": self.live_ws, "guard_level": self.cfg["guard_level"], "config": self.cfg}
        self.ws = self.live_ws
        self.tmp_base = None
        self.archive_dir = None
        self.frame_touched = False
        self.lock_path = None

    def _load_config(self, path):
        cfg = json.loads(json.dumps(DEFAULTS))
        user = {}
        if path:
            with open(path, encoding="utf-8") as f:
                user = json.load(f)
        level = user.get("guard_level", cfg["guard_level"])
        if level not in PRESETS:
            raise SystemExit(f"guard_level must be one of {sorted(PRESETS)}")
        unknown = sorted(set(user) - set(DEFAULTS) - set(PRESETS[level]))
        if unknown:  # a misspelt key would otherwise be ignored silently
            raise SystemExit(f"unknown config key(s) in {path}: {unknown}")
        cfg.update(PRESETS[level])
        cfg.update(user)
        return cfg

    def log(self, msg):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line, flush=True)
        self._log.write(line + "\n")
        self._log.flush()

    def check(self, name, ok, detail="", hard=True):
        status = "PASS" if ok else ("FAIL" if hard else "WARN")
        self.checks.append({"check": name, "status": status, "hard": hard, "detail": detail})
        self.log(f"  [{status}] {name}" + (f" - {detail}" if detail else ""))
        if hard and not ok:
            raise Blocked(f"{name}: {detail}")

    def info(self, name, detail):
        self.checks.append({"check": name, "status": "INFO", "hard": False, "detail": detail})
        self.log(f"  [INFO] {name} - {detail}")

    # paths inside the workspace the chain runs against (live, or the sandbox for a dry run)
    @property
    def sampling(self):
        return os.path.join(self.ws, "1_sampling")

    @property
    def monitoring(self):
        return os.path.join(self.ws, "2_monitoring")

    @property
    def frame_dir(self):
        return os.path.join(self.ws, FRAME_REL)

    def env(self, **extra):
        # Paths go to child processes with forward slashes: R code that builds a regular expression from a
        # path breaks on "\2..." (read as a back reference). Python and R both accept "/" on Windows.
        e = os.environ.copy()
        e.update({"MSNA_WORKSPACE": self.ws.replace("\\", "/"), "MSNA_PYTHON": sys.executable, "MSNA_RSCRIPT": self.rscript,
                  "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"})
        e.update({k: (v.replace("\\", "/") if k in ("MSNA_PKG_ROOT", "BUILD_DC_OUT_ROOT", "MAP_CHECK_KML_ROOT") else v)
                  for k, v in extra.items() if v is not None})
        return e

    def step(self, name, cmd, cwd, env, timeout_key):
        timeout = self.cfg["timeouts_min"].get(timeout_key, 30) * 60
        self.log(f"> {name}: {' '.join(os.path.basename(c) if i == 0 else c for i, c in enumerate(cmd))}")
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
            out, rc = p.stdout.decode("utf-8", errors="replace"), p.returncode
        except subprocess.TimeoutExpired as e:
            out, rc = (e.stdout or b"").decode("utf-8", errors="replace") + f"\nTIMEOUT after {timeout // 60} min", -9
        with open(os.path.join(self.run_dir, f"step_{name}.log"), "w", encoding="utf-8") as f:
            f.write(out)
        self.log(f"  {name}: exit {rc} in {time.time() - t0:.0f} s (log: step_{name}.log)")
        return rc, out


# ------------------------------------------------------------------ achieved snapshot (mirrors frame_status.R)
def achieved_snapshot(subs_csv, overlay_csv):
    """Exactly compute_achieved_lookup() in scripts/shared/frame_status.R: completed, matched, not a
    confirmed/contested deletion; Non-IDP by matched survey id, IDP by (cluster, matched_status) counts."""
    with open(overlay_csv, encoding="utf-8-sig", newline="") as f:
        dele = {r["uuid"] for r in csv.DictReader(f) if r.get("status") in ("confirmed", "contested")}
    nonidp, idp, n_total, n_ach = set(), Counter(), 0, 0
    with open(subs_csv, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            n_total += 1
            if r.get("interview_outcome") == "completed" and r.get("matched_survey_id") not in (None, "", "NA") \
                    and r.get("submission_uuid") not in dele:
                n_ach += 1
                if r.get("pop_type") == "non_idp":
                    nonidp.add(r["matched_survey_id"])
                elif r.get("pop_type") == "idp":
                    idp[(r.get("matched_cluster_id", ""), r.get("matched_status", ""))] += 1
    return {"nonidp": nonidp, "idp": idp, "n_total": n_total, "n_achieved": n_ach}


def save_snapshot(snap, path):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "key", "status", "count"])
        for sid in sorted(snap["nonidp"]):
            w.writerow(["non_idp", sid, "", 1])
        for (c, s), n in sorted(snap["idp"].items()):
            w.writerow(["idp", c, s, n])


def load_snapshot(path):
    nonidp, idp = set(), Counter()
    with open(path, encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            if r["kind"] == "non_idp":
                nonidp.add(r["key"])
            else:
                idp[(r["key"], r["status"])] = int(r["count"])
    return {"nonidp": nonidp, "idp": idp}


# ------------------------------------------------------------------ steps
def preflight(run):
    run.log("== preflight")
    run.check("Python can import openpyxl", _can_import("openpyxl"), sys.executable)
    try:
        run.rscript = msna_paths.rscript_exe()
    except SystemExit as e:
        raise RunError(str(e))
    rc, out = run.step("check_r_packages", [run.rscript, "-e",
                       "for (p in c('dplyr','readr','tools')) suppressPackageStartupMessages(library(p, character.only=TRUE)); cat('R-OK', R.version.string)"],
                       run.ws, run.env(), "renv")
    if rc != 0 or "R-OK" not in out:
        raise RunError("R or one of its packages (dplyr, readr) is missing - see step_check_r_packages.log")
    run.info("Interpreters", f"python {sys.version.split()[0]} ({sys.executable}); {out.strip().splitlines()[-1]}")
    need = [os.path.join(run.frame_dir, f) for f in (FULL_CSV, WORKING_CSV, STRATA_FULL_CSV, STRATA_WORKING_CSV, CLUSTER_STATUS_CSV, "_frame_version.txt")] + [
        os.path.join(run.monitoring, "data", "real_submissions.csv"), os.path.join(run.monitoring, "data", "CONFIRMED_DELETIONS_OVERLAY.csv"),
        os.path.join(run.sampling, "resampling", "output", "master_accessibility_status_ward_level.csv"),
        os.path.join(run.sampling, "resampling", "output", "cluster_accessibility_overlay.csv"),
        os.path.join(run.sampling, "resampling", "output", "target_correction_dropped_clusters.csv"),
        os.path.join(run.sampling, "resampling", "output", "target_sample_representativity_last_run.csv"),
        os.path.join(run.ws, "validity_checks", "run_all_checks.R")]
    missing = [p for p in need if not os.path.isfile(p)]
    if missing:
        raise RunError("missing input file(s): " + "; ".join(missing))
    run.check("OneDrive conflict copies next to the frame, mirrors or canonical data", not _conflict_copies(run),
              "; ".join(_conflict_copies(run)[:8]))
    if not run.args.dry_run:
        partners = [d for d in os.listdir(run.live_pkg_root) if os.path.isdir(os.path.join(run.live_pkg_root, d))] \
            if os.path.isdir(run.live_pkg_root) else []
        if len(partners) < 10:
            raise RunError(f"live partner package folder not found or nearly empty: {run.live_pkg_root} "
                           f"({len(partners)} partner folders). Is the SharePoint library synced? Set MSNA_PKG_ROOT.")
    run.inputs = {"real_submissions_md5": md5(need[6]), "overlay_md5": md5(need[7]),
                  "working_md5_before": md5(need[1]), "full_md5_before": md5(need[0])}
    run.fingerprint = {k: (md5(os.path.join(run.ws, *rel)) if os.path.isfile(os.path.join(run.ws, *rel)) else "missing")
                       for k, rel in FINGERPRINT_INPUTS.items()}
    run.summary["inputs"] = dict(run.inputs)
    run.log(f"  inputs: real_submissions {run.inputs['real_submissions_md5'][:8]}, overlay {run.inputs['overlay_md5'][:8]}, "
            f"WORKING {run.inputs['working_md5_before'][:8]}")
    fs = _read_json(os.path.join(run.state_dir_ws, "frame_state.json"))
    run.check("A baseline exists (frame_state.json; seed once with --reseed-baseline)", fs is not None,
              f"looked in {run.state_dir_ws}")
    run.check("The frame is the one the last accepted run left (nothing changed it outside this script)",
              fs["working_md5"] == run.inputs["working_md5_before"] and fs["full_md5"] == run.inputs["full_md5_before"],
              f"state WORKING {fs['working_md5'][:8]} / FULL {fs['full_md5'][:8]} vs now "
              f"{run.inputs['working_md5_before'][:8]} / {run.inputs['full_md5_before'][:8]}. After a resampling merge, "
              "re-baseline deliberately with --reseed-baseline.")
    run.frame_state = fs


def _can_import(mod):
    try:
        __import__(mod)
        return True
    except Exception:
        return False


def _read_json(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _conflict_copies(run):
    """OneDrive conflict copies look like NAME-<COMPUTERNAME>.ext beside NAME.ext."""
    hits = []
    for d in (run.frame_dir, os.path.join(run.monitoring, "data"), os.path.join(run.monitoring, "input_data", "sampling_frame")):
        if not os.path.isdir(d):
            continue
        names = set(os.listdir(d))
        for n in names:
            stem, ext = os.path.splitext(n)
            m = re.match(r"^(.*)-[A-Za-z0-9][A-Za-z0-9-]{2,30}$", stem)
            if m and (m.group(1) + ext) in names and (m.group(1) + ext).startswith(("NGA_MSNA_2026_", "_frame_version", "real_submissions", "CONFIRMED_DELETIONS")):
                hits.append(os.path.join(d, n))
    return hits


def unchanged_since_last_publish(run):
    """True only if EVERY chain input is byte-identical to the last published run's (FINGERPRINT_INPUTS)."""
    ps = _read_json(os.path.join(run.state_dir_ws, "publish_state.json"))
    if not ps or "fingerprint" not in ps:
        return False
    changed = [k for k, v in run.fingerprint.items() if ps["fingerprint"].get(k) != v]
    if changed:
        run.info("Inputs changed since the last published run", ", ".join(changed))
    return not changed


def archive_frame(run):
    run.log("== archive the frame")
    run.archive_dir = os.path.join(run.frame_dir, "_archive", f"{run.run_id[:10]}_daily_update_{run.run_id}")
    os.makedirs(run.archive_dir, exist_ok=True)
    files = [f for f in os.listdir(run.frame_dir) if os.path.isfile(os.path.join(run.frame_dir, f))]
    sums = {}
    for f in files:
        shutil.copy2(os.path.join(run.frame_dir, f), os.path.join(run.archive_dir, f))
        sums[f] = md5(os.path.join(run.archive_dir, f))
        if sums[f] != md5(os.path.join(run.frame_dir, f)):
            raise RunError(f"archive copy of {f} does not match the live file")
    with open(os.path.join(run.archive_dir, "MD5SUMS.txt"), "w", encoding="utf-8") as fh:
        fh.writelines(f"{v}  {k}\n" for k, v in sorted(sums.items()))
    run.archive_sums = sums
    run.actions.append(f"archived {len(files)} frame files to {run.archive_dir}")
    run.log(f"  {len(files)} files -> {run.archive_dir}")


def restore_frame(run, why):
    run.log(f"== RESTORING the archived frame ({why})")
    for f, s in run.archive_sums.items():
        shutil.copy2(os.path.join(run.archive_dir, f), os.path.join(run.frame_dir, f))
        if md5(os.path.join(run.frame_dir, f)) != s:
            raise RunError(f"restore of {f} failed its md5 check - restore it by hand from {run.archive_dir}")
    run.summary.setdefault("frame", {})["restored"] = True
    run.actions.append(f"frame restored from {run.archive_dir} ({why})")
    run.log("  frame restored and md5-verified")


def refresh_frame(run):
    run.log("== refresh WORKING (with the Step 0 accessibility resweep)")
    run.frame_touched = True
    rc, out = run.step("refresh_working_frame", [run.rscript, os.path.join("scripts", "field_guide_production", "refresh_working_frame_daily.R")],
                       run.sampling, run.env(), "refresh")
    if rc != 0:
        kind = Blocked if re.search(r"assert_plausible|plausib|Not safe to continue", out) else RunError
        raise kind(f"refresh_working_frame_daily.R exited {rc} - see step_refresh_working_frame.log")


def frame_checks(run):
    run.log("== frame checks (hard)")
    a, f, cfg = run.archive_dir, run.frame_dir, run.cfg
    fh_old, full_old = read_table(os.path.join(a, FULL_CSV))
    fh, full = read_table(os.path.join(f, FULL_CSV))
    same_full = fh_old == fh and full_old == full
    detail = ""
    if not same_full:
        idx = fh.index("survey_id")
        o, n = {r[idx]: r for r in full_old}, {r[idx]: r for r in full}
        cols = Counter(fh[i] for k in set(o) & set(n) for i in range(len(fh)) if fh == fh_old and o[k][i] != n[k][i])
        detail = f"rows {len(full_old)}->{len(full)}, changed cells by column: {dict(cols.most_common(5))}"
    run.check("FULL frame unchanged (no accessibility or design change mid-week)", same_full, detail, hard=cfg["full_must_be_unchanged"])
    sh_old, sf_old = read_table(os.path.join(a, STRATA_FULL_CSV))
    sh, sf = read_table(os.path.join(f, STRATA_FULL_CSV))
    run.check("Strata-level FULL unchanged", sh_old == sh and sf_old == sf, "", hard=cfg["full_must_be_unchanged"])

    wh, work = read_table(os.path.join(f, WORKING_CSV))
    wh_old, work_old = read_table(os.path.join(a, WORKING_CSV))
    run.check("WORKING has the FULL frame's columns", wh == fh and wh_old == wh)
    si, ci, pi, sti = fh.index("survey_id"), fh.index("cluster_id"), fh.index("pop_type"), fh.index("status")
    ids = [r[si] for r in work]
    run.check("WORKING has no duplicate survey_id", len(ids) == len(set(ids)), f"{len(ids) - len(set(ids))} duplicates")
    full_by_id = {r[si]: r for r in full}
    bad = sum(1 for r in work if full_by_id.get(r[si]) != r)
    run.check("Every WORKING row is an exact copy of its FULL row", bad == 0, f"{bad} rows differ or are not in FULL")

    prev = load_snapshot(os.path.join(run.state_dir_ws, "achieved_snapshot.csv"))
    now = achieved_snapshot(os.path.join(run.monitoring, "data", "real_submissions.csv"),
                            os.path.join(run.monitoring, "data", "CONFIRMED_DELETIONS_OVERLAY.csv"))
    run.now_snapshot = now
    old_ids, new_ids = {r[si]: r for r in work_old}, {r[si]: r for r in work}
    removed = [old_ids[k] for k in old_ids.keys() - new_ids.keys()]
    added = [new_ids[k] for k in new_ids.keys() - old_ids.keys()]
    rem_cs, add_cs = Counter(), Counter()
    unexplained = []
    for r in removed:
        if r[pi] == "idp":
            rem_cs[(r[ci], r[sti])] += 1
        elif r[si] not in now["nonidp"]:
            unexplained.append(("removed", r[si], "Non-IDP household removed although it is not achieved"))
    for r in added:
        if r[pi] == "idp":
            add_cs[(r[ci], r[sti])] += 1
        elif not (r[si] in prev["nonidp"] and r[si] not in now["nonidp"]):
            unexplained.append(("added", r[si], "Non-IDP household added back although its achieved status did not change"))
    for key, k in rem_cs.items():
        if now["idp"][key] - prev["idp"][key] < k:
            unexplained.append(("removed", f"{key[0]} {key[1]} x{k}", f"IDP achieved count {prev['idp'][key]}->{now['idp'][key]}"))
    for key, k in add_cs.items():
        if prev["idp"][key] - now["idp"][key] < k:
            unexplained.append(("added", f"{key[0]} {key[1]} x{k}", f"IDP achieved count {prev['idp'][key]}->{now['idp'][key]}"))
    still_todo = [r[si] for r in work if r[pi] == "non_idp" and r[si] in now["nonidp"]]
    run.check("No achieved Non-IDP household is still on a to-do list", not still_todo, f"{len(still_todo)} e.g. {still_todo[:3]}")
    with open(os.path.join(run.run_dir, "working_changes.csv"), "w", encoding="utf-8", newline="") as fh_:
        w = csv.writer(fh_)
        w.writerow(["change", "survey_id", "cluster_id", "pop_type", "status"])
        for r in removed:
            w.writerow(["removed", r[si], r[ci], r[pi], r[sti]])
        for r in added:
            w.writerow(["added", r[si], r[ci], r[pi], r[sti]])
    if unexplained:
        with open(os.path.join(run.run_dir, "working_changes_UNEXPLAINED.csv"), "w", encoding="utf-8", newline="") as fh_:
            w = csv.writer(fh_)
            w.writerow(["change", "what", "why_unexplained"])
            w.writerows(unexplained)
    rule, cap = cfg["working_change_rule"], cfg["max_unexplained_working_rows"]
    ok = rule == "report_only" or (len(unexplained) <= (cap or 0))
    run.check(f"Every WORKING change is explained by an achieved-status change (rule: {rule})", ok,
              f"{len(removed)} removed, {len(added)} added, {len(unexplained)} unexplained"
              + (f" e.g. {unexplained[:2]}" if unexplained else ""), hard=rule != "report_only")

    for name, key, allowed in ((STRATA_WORKING_CSV, "strata_id", STRATA_SUBMISSION_COLS), (CLUSTER_STATUS_CSV, "cluster_id", CLUSTER_STATUS_SUBMISSION_COLS)):
        h_old, t_old = read_table(os.path.join(a, name))
        h_new, t_new = read_table(os.path.join(f, name))
        k = h_new.index(key) if key in h_new else 0
        o, n = {r[k]: r for r in t_old}, {r[k]: r for r in t_new}
        moved = Counter(h_new[i] for kk in set(o) & set(n) for i in range(len(h_new)) if h_old == h_new and o[kk][i] != n[kk][i])
        frozen = {c: v for c, v in moved.items() if c not in allowed}
        run.check(f"{name}: same rows, only submission-driven columns moved", h_old == h_new and set(o) == set(n) and not frozen,
                  f"rows {len(o)}->{len(n)}; moved {dict(moved)}" + (f"; FROZEN columns moved: {frozen}" if frozen else ""))
    run.summary["frame"] = {"working_rows_before": len(work_old), "working_rows_after": len(work), "removed": len(removed),
                            "added": len(added), "unexplained": len(unexplained), "achieved_canonical": now["n_achieved"],
                            "working_md5_after": md5(os.path.join(f, WORKING_CSV)), "restored": False}


def stamp_and_sync(run):
    run.log("== stamp + mirror sync")
    for name, rel in (("stamp", ["scripts", "stamp_frame_version.R"]), ("sync_frame", ["resampling", "scripts", "sync_sampling_frame_mirrors.R"]),
                      ("sync_access", ["resampling", "scripts", "sync_accessibility_mirrors.R"])):
        rc, _ = run.step(name, [run.rscript, os.path.join(*rel)], run.sampling, run.env(), "sync" if name != "stamp" else "stamp")
        if rc != 0:
            raise RunError(f"{name} exited {rc}")
    mirror = os.path.join(run.monitoring, "input_data", "sampling_frame")
    bad = [m for m in MIRRORED if not os.path.isfile(os.path.join(mirror, m)) or md5(os.path.join(mirror, m)) != md5(os.path.join(run.frame_dir, m))]
    run.check("2_monitoring/input_data frame mirror == master (md5)", not bad, ", ".join(bad), hard=False)
    if bad:
        raise RunError("mirror sync left a mirror that differs from the master: " + ", ".join(bad))


def build_packages(run):
    run.log("== partner packages into staging")
    run.stage = os.path.join(run.tmp_base, "stage")
    if os.path.exists(run.stage):
        shutil.rmtree(run.stage)
    os.makedirs(run.stage)
    rc, out = run.step("build_packages", [sys.executable, os.path.join("scripts", "field_guide_production", "build_partner_dc_packages.py")],
                       run.sampling, run.env(BUILD_DC_OUT_ROOT=run.stage), "build")
    if rc != 0:
        raise Blocked(f"build_partner_dc_packages.py exited {rc} - see step_build_packages.log")
    run.check("Builder: KML and workbook agree on every outstanding point (UUID reconciliation)", "UUID RECONCILIATION: PASS" in out)
    run.check("Builder: no stale partner/LGA folders", "STALE PARTNER/LGA FOLDERS: none found" in out)
    rc, out = run.step("daily_workbooks", [sys.executable, os.path.join("scripts", "field_guide_production", "refresh_partner_workbooks_daily.py")],
                       run.sampling, run.env(BUILD_DC_OUT_ROOT=run.stage, MAP_CHECK_KML_ROOT=run.stage), "daily")
    if rc != 0:
        raise Blocked(f"refresh_partner_workbooks_daily.py exited {rc} - see step_daily_workbooks.log")
    mc = os.path.join(run.stage, "daily_refresh_map_check_STAGED.csv")
    wb_only = map_only = None
    if os.path.isfile(mc):
        with open(mc, encoding="utf-8-sig", newline="") as fh:
            rows = list(csv.DictReader(fh))
        wb_only = sum(int(r["workbook_only_non_idp"]) + int(r["workbook_only_idp"]) for r in rows)
        map_only = sum(int(r["map_only_non_idp"]) + int(r["map_only_idp"]) for r in rows)
    run.check("MAP CHECK: every to-do point in every staged workbook is on the staged map", wb_only == 0,
              f"to-do points missing from maps: {wb_only}; collected points still on maps: {map_only}", hard=run.cfg["require_map_check_ok"])
    run.summary["map_check"] = {"workbook_only": wb_only, "map_only": map_only}


def gate(run):
    run.log("== validity gate on staging")
    out_csv = os.path.join(run.run_dir, "gate_result.csv")
    rc, out = run.step("gate", [run.rscript, "run_all_checks.R", "--gate", "--out", out_csv],
                       os.path.join(run.ws, "validity_checks"), run.env(MSNA_PKG_ROOT=run.stage), "gate")
    counts = Counter()
    if os.path.isfile(out_csv):
        with open(out_csv, encoding="utf-8-sig", newline="") as fh:
            counts = Counter(r.get("status", "") for r in csv.DictReader(fh))
    run.summary["gate"] = {"exit": rc, "counts": dict(counts), "csv": out_csv}
    if rc == 2 or rc not in (0, 1):
        run.check("Validity gate ran", False, f"gate exit {rc} - see step_gate.log", hard=False)
        if run.cfg["require_gate"]:
            raise RunError(f"the validity gate could not run (exit {rc})")
        return
    run.check("Validity gate on staging: no FAIL (package alignment, oversampling roll-up, three-way reconciliation)",
              rc == 0, f"{dict(counts)}", hard=run.cfg["require_gate"])


def publish_plan(run):
    run.log("== publish plan (staging vs live)")
    staged = {}
    for root, _, files in os.walk(run.stage):
        for fn in files:
            rel = os.path.relpath(os.path.join(root, fn), run.stage)
            if os.path.dirname(rel) == "" and fn in SKIP_STAGED_ROOT_FILES:
                continue
            staged[rel] = md5(os.path.join(root, fn))
    plan = {"new": [], "changed": [], "identical": [], "leftover": [], "leftover_modified": [], "staged": staged}
    for rel, s in sorted(staged.items()):
        live = os.path.join(run.live_pkg_root, rel)
        if not os.path.isfile(live):
            plan["new"].append(rel)
        elif md5(live) != s:
            plan["changed"].append(rel)
        else:
            plan["identical"].append(rel)
    manifest = os.path.join(run.state_dir_ws, "last_published_manifest.csv")
    if os.path.isfile(manifest):
        with open(manifest, encoding="utf-8", newline="") as fh:
            last = {r["rel_path"]: r["md5"] for r in csv.DictReader(fh)}
        for rel, m in sorted(last.items()):
            live = os.path.join(run.live_pkg_root, rel)
            if rel in staged or not os.path.isfile(live):
                continue
            (plan["leftover"] if md5(live) == m else plan["leftover_modified"]).append(rel)
    with open(os.path.join(run.run_dir, "publish_plan.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["action", "rel_path"])
        for k in ("new", "changed", "leftover", "leftover_modified"):
            w.writerows([k, r] for r in plan[k])
    run.summary["packages"] = {"staged_files": len(staged), "new": len(plan["new"]), "changed": len(plan["changed"]),
                               "identical": len(plan["identical"]), "leftover_to_archive": len(plan["leftover"]),
                               "leftover_modified_untouched": len(plan["leftover_modified"]), "published": False}
    run.log(f"  staged {len(staged)} | new {len(plan['new'])} | changed {len(plan['changed'])} | identical {len(plan['identical'])}"
            f" | no-longer-produced {len(plan['leftover'])} (+{len(plan['leftover_modified'])} modified by someone, left alone)")
    run.check("No more no-longer-produced partner files than the guard allows (a mass disappearance means a structural change)",
              len(plan["leftover"]) <= run.cfg["max_leftover_files"], f"{len(plan['leftover'])} (limit {run.cfg['max_leftover_files']})")
    if run.cfg["allowed_leftover_prefixes"]:
        allowed = [os.path.normcase(os.path.normpath(p)) for p in run.cfg["allowed_leftover_prefixes"]]
        stray = [rel for rel in plan["leftover"] + plan["leftover_modified"]
                 if not any(os.path.normcase(os.path.normpath(rel)) == a or os.path.normcase(os.path.normpath(rel)).startswith(a + os.sep)
                            for a in allowed)]
        run.check("Every no-longer-produced file is one the config expects (allowed_leftover_prefixes)", not stray,
                  f"{len(stray)} unexpected, e.g. {stray[:3]}")
    if plan["leftover_modified"]:
        run.check("No-longer-produced files that someone edited are left in place", True,
                  f"{len(plan['leftover_modified'])} e.g. {plan['leftover_modified'][:2]}", hard=False)
    return plan


def publish(run, plan):
    run.log("== publish to the live partner folders (changed files only; all-or-nothing)")
    targets = plan["changed"] + (plan["leftover"] if run.cfg["archive_leftover_package_files"] else [])
    locked = []
    for rel in targets:
        try:
            with open(os.path.join(run.live_pkg_root, rel), "r+b"):
                pass
        except OSError:
            locked.append(rel)
    run.check("No live partner file is open/locked (e.g. in Excel)", not locked, f"{len(locked)} e.g. {locked[:3]}")
    bak = os.path.join(run.sampling, "resampling", "output", "_pkgbak", f"{run.run_id}_daily")
    done = []  # (kind, rel, extra) in order, for rollback
    # TEST ONLY: MSNA_DAILY_TEST_FAIL_PUBLISH_AFTER=N forces a failure after N copies, to prove the rollback.
    fail_after = int(os.environ.get("MSNA_DAILY_TEST_FAIL_PUBLISH_AFTER", "-1"))
    try:
        for rel in plan["changed"] + plan["new"]:
            if 0 <= fail_after <= len(done):
                raise RunError(f"TEST: simulated failure after {len(done)} copies")
            src, dst = os.path.join(run.stage, rel), os.path.join(run.live_pkg_root, rel)
            if rel in plan["changed"]:
                b = os.path.join(bak, rel)
                os.makedirs(os.path.dirname(b), exist_ok=True)
                shutil.copy2(dst, b)
                if md5(b) != md5(dst):
                    raise RunError(f"backup of {rel} does not match the live file")
                done.append(("replaced", rel, b))
            else:
                done.append(("created", rel, None))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            if md5(dst) != plan["staged"][rel]:
                raise RunError(f"live copy of {rel} does not match staging")
        if run.cfg["archive_leftover_package_files"]:
            stamp = run.run_id[:10]
            for rel in plan["leftover"]:
                src = os.path.join(run.live_pkg_root, rel)
                dst = os.path.join(os.path.dirname(src), f"_archived_not_produced_{stamp}", os.path.basename(src))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.move(src, dst)
                done.append(("moved", rel, dst))
    except Exception as e:
        run.log(f"  publish failed ({e}) - rolling back {len(done)} step(s)")
        problems = []
        for kind, rel, extra in reversed(done):
            live = os.path.join(run.live_pkg_root, rel)
            try:
                if kind == "replaced":
                    shutil.copy2(extra, live)
                elif kind == "created" and os.path.isfile(live):
                    os.remove(live)
                elif kind == "moved":
                    shutil.move(extra, live)
            except Exception as e2:
                problems.append(f"{rel}: {e2}")
        run.actions.append(f"publish ROLLED BACK ({len(done)} steps undone)" + (f"; {len(problems)} problem(s): {problems[:3]}" if problems else ""))
        raise RunError(f"publish failed and was rolled back: {e}" + (f" - ROLLBACK PROBLEMS: {problems[:3]}" if problems else ""))
    wrong = [rel for rel, s in plan["staged"].items() if md5(os.path.join(run.live_pkg_root, rel)) != s]
    if wrong:
        raise RunError(f"after publish, {len(wrong)} live file(s) differ from staging, e.g. {wrong[:3]}")
    with open(os.path.join(run.state_dir_ws, "last_published_manifest.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rel_path", "md5"])
        w.writerows(sorted(plan["staged"].items()))
    run.summary["packages"]["published"] = True
    run.summary["packages"]["backup_dir"] = bak
    run.actions.append(f"published: {len(plan['changed'])} changed + {len(plan['new'])} new file(s); "
                       f"{len(plan['leftover'])} no-longer-produced file(s) archived beside themselves; backups in {bak}")
    run.log(f"  done: {len(plan['changed'])} changed, {len(plan['new'])} new, {len(plan['leftover'])} archived; all {len(plan['staged'])} md5-verified")


def run_05(run):
    run.log("== 05 representativity workbook (informational - never blocks)")
    out_dir = os.path.join(run.sampling, "resampling", "output")
    bdir = os.path.join(run.tmp_base, "r05_backup")
    os.makedirs(bdir, exist_ok=True)
    for f in R05_OUTPUTS:
        if os.path.isfile(os.path.join(out_dir, f)):
            shutil.copy2(os.path.join(out_dir, f), os.path.join(bdir, f))
    rc, out = run.step("r05", [sys.executable, "05_build_accessibility_impact_workbook.py"],
                       os.path.join(run.sampling, "resampling", "scripts"), run.env(), "r05")
    m = re.search(r"Real achieved \(canonical, post-deletion\): (\d+)", out)
    if rc != 0:
        for f in os.listdir(bdir):
            shutil.copy2(os.path.join(bdir, f), os.path.join(out_dir, f))
        run.check("05 ran (its outputs restored from before the run)", False, f"exit {rc} - see step_r05.log", hard=False)
        return
    n = int(m.group(1)) if m else None
    run.check("05 national achieved == independent canonical count", n == run.now_snapshot["n_achieved"],
              f"05 {n} vs canonical {run.now_snapshot['n_achieved']}", hard=False)


def save_frame_state(run, ws_for_state, snap):
    os.makedirs(ws_for_state, exist_ok=True)
    save_snapshot(snap, os.path.join(ws_for_state, "achieved_snapshot.csv"))
    fdir = run.frame_dir
    st = {"working_md5": md5(os.path.join(fdir, WORKING_CSV)), "full_md5": md5(os.path.join(fdir, FULL_CSV)),
          "real_submissions_md5": run.inputs["real_submissions_md5"], "overlay_md5": run.inputs["overlay_md5"],
          "accepted_at": now_s(), "run_id": run.run_id, "machine": socket.gethostname()}
    with open(os.path.join(ws_for_state, "frame_state.json"), "w", encoding="utf-8") as f:
        json.dump(st, f, indent=1)


def prune(run):
    def keep_newest(paths, n):  # n == 0: keep everything
        for p in (sorted(paths)[:-n] if n > 0 else []):
            shutil.rmtree(p, ignore_errors=True)
            run.actions.append(f"pruned old {p}")
    keep_newest([p for p in glob.glob(os.path.join(run.runs_root, "20*")) if os.path.isdir(p)], run.cfg["keep_runs"])
    keep_newest(glob.glob(os.path.join(run.live_ws, FRAME_REL, "_archive", "*_daily_update_*")), run.cfg["keep_frame_archives"])
    keep_newest(glob.glob(os.path.join(run.live_ws, "1_sampling", "resampling", "output", "_pkgbak", "*_daily")), run.cfg["keep_package_backups"])


# ------------------------------------------------------------------ sandbox
def make_sandbox(src_ws, dst_ws, log=print):
    for rel, kind in SANDBOX_ITEMS:
        src, dst = os.path.join(src_ws, rel), os.path.join(dst_ws, rel)
        if kind.startswith("file"):
            if not os.path.isfile(src):
                if kind.endswith("optional"):
                    continue
                raise RunError(f"sandbox: missing {src}")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
        elif kind == "top":
            os.makedirs(dst, exist_ok=True)
            for n in os.listdir(src) if os.path.isdir(src) else []:
                if os.path.isfile(os.path.join(src, n)):
                    shutil.copy2(os.path.join(src, n), os.path.join(dst, n))
        else:
            if not os.path.isdir(src):
                if kind.endswith("optional"):
                    continue
                raise RunError(f"sandbox: missing folder {src}")
            shutil.copytree(src, dst, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("_archive*", "run_history", "__pycache__", "*.log"))
    log(f"  sandbox ready: {dst_ws}")


# ------------------------------------------------------------------ commands
def reseed_baseline(args):
    ws = msna_paths.workspace()
    fdir = os.path.join(ws, FRAME_REL)
    sdir = args.submissions_dir or os.path.join(ws, "2_monitoring", "data")
    snap = achieved_snapshot(os.path.join(sdir, "real_submissions.csv"), os.path.join(sdir, "CONFIRMED_DELETIONS_OVERLAY.csv"))
    wh, work = read_table(os.path.join(fdir, WORKING_CSV))
    si, pi = wh.index("survey_id"), wh.index("pop_type")
    left = [r[si] for r in work if r[pi] == "non_idp" and r[si] in snap["nonidp"]]
    if left:
        raise SystemExit(f"REFUSED: {len(left)} achieved Non-IDP households are still in WORKING (e.g. {left[:3]}), so this WORKING "
                         "was not built from these submissions. Refresh the frame first, or point --submissions-dir at the data it was built from.")
    state_dir = os.path.join(ws, "1_sampling", "output", "daily_update_runs", "state")
    os.makedirs(state_dir, exist_ok=True)
    save_snapshot(snap, os.path.join(state_dir, "achieved_snapshot.csv"))
    st = {"working_md5": md5(os.path.join(fdir, WORKING_CSV)), "full_md5": md5(os.path.join(fdir, FULL_CSV)),
          "real_submissions_md5": md5(os.path.join(sdir, "real_submissions.csv")), "overlay_md5": md5(os.path.join(sdir, "CONFIRMED_DELETIONS_OVERLAY.csv")),
          "accepted_at": now_s(), "run_id": "reseed", "machine": socket.gethostname(), "submissions_dir": sdir}
    with open(os.path.join(state_dir, "frame_state.json"), "w", encoding="utf-8") as f:
        json.dump(st, f, indent=1)
    if args.manifest_from:
        root = msna_paths.pkg_root()
        with open(args.manifest_from, encoding="utf-8", newline="") as fh:
            rels = [r["rel_path"] for r in csv.DictReader(fh)]
        with open(os.path.join(state_dir, "last_published_manifest.csv"), "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["rel_path", "md5"])
            w.writerows([rel, md5(os.path.join(root, rel))] for rel in sorted(rels) if os.path.isfile(os.path.join(root, rel)))
    print(f"baseline written to {state_dir}: WORKING {st['working_md5'][:8]}, submissions {st['real_submissions_md5'][:8]}, "
          f"{snap['n_achieved']} achieved")
    return EXIT_OK


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Phase 2: refresh the frame and update partner folders, fail-safe.")
    ap.add_argument("--dry-run", action="store_true", help="run the whole chain in a sandbox; write nothing live")
    ap.add_argument("--config", help="JSON file overriding the defaults (see README_daily_update.md)")
    ap.add_argument("--keep-sandbox", action="store_true", help="dry run: keep the sandbox for inspection")
    ap.add_argument("--no-publish", action="store_true",
                    help="real run up to the gate, but publish nothing (e.g. while OneDrive is not syncing); the next normal run publishes")
    ap.add_argument("--check-env", action="store_true", help="only check that this machine can run the chain")
    ap.add_argument("--reseed-baseline", action="store_true", help="accept the current frame as the baseline (after a resampling merge)")
    ap.add_argument("--submissions-dir", help="with --reseed-baseline: folder holding the real_submissions/overlay the frame was built from")
    ap.add_argument("--manifest-from", help="with --reseed-baseline: a previous push manifest CSV (rel_path column) to seed the publish manifest")
    ap.add_argument("--make-sandbox", metavar="DIR", help="copy what this chain reads into DIR/<workspace name> and stop")
    args = ap.parse_args()
    if args.reseed_baseline:
        return reseed_baseline(args)
    if args.make_sandbox:
        ws = msna_paths.workspace()
        make_sandbox(ws, os.path.join(os.path.abspath(args.make_sandbox), os.path.basename(ws)))
        return EXIT_OK

    run = Run(args)
    run.state_dir_ws = run.state_dir
    exit_code, status = EXIT_ERROR, "ERROR"
    try:
        run.log(f"Phase 2 run {run.run_id} on {socket.gethostname()} | workspace {run.live_ws} | dry_run={args.dry_run} | guard={run.cfg['guard_level']}")
        if not args.dry_run and not args.check_env:
            run.lock_path = os.path.join(run.runs_root, ".daily_update.lock")
            if os.path.isfile(run.lock_path) and time.time() - os.path.getmtime(run.lock_path) < 6 * 3600:
                with open(run.lock_path, encoding="utf-8") as f:
                    raise RunError(f"another run holds the lock: {f.read().strip()} - wait, or delete {run.lock_path} if that run is dead")
            with open(run.lock_path, "w", encoding="utf-8") as f:
                f.write(f"{socket.gethostname()} pid {os.getpid()} since {now_s()}")
        run.tmp_base = os.path.join(tempfile.gettempdir(), "msna_daily", run.run_id)
        os.makedirs(run.tmp_base, exist_ok=True)
        if args.dry_run:
            run.log("== DRY RUN: building a sandbox copy of what the chain reads (nothing live is written)")
            run.ws = os.path.join(run.tmp_base, "ws", os.path.basename(run.live_ws))
            make_sandbox(run.live_ws, run.ws, run.log)
            run.state_dir_ws = os.path.join(run.ws, "1_sampling", "output", "daily_update_runs", "state")
        preflight(run)
        if args.check_env:
            status, exit_code = "OK", EXIT_OK
            run.summary["message"] = "environment OK - this machine can run the daily update"
            return exit_code
        if not args.dry_run and run.cfg["skip_if_unchanged"] and unchanged_since_last_publish(run):
            status, exit_code = "NO_CHANGE", EXIT_OK
            run.summary["message"] = "no new submissions or deletions since the last published run - nothing to do"
            run.log(run.summary["message"])
            return exit_code
        archive_frame(run)
        try:
            refresh_frame(run)
            frame_checks(run)
        except (Blocked, RunError) as e:
            restore_frame(run, f"frame-level failure: {e}")
            raise
        except Exception as e:
            restore_frame(run, f"unexpected error during the frame refresh: {e}")
            raise
        if not args.dry_run:
            save_frame_state(run, run.state_dir, run.now_snapshot)
        stamp_and_sync(run)
        build_packages(run)
        gate(run)
        plan = publish_plan(run)
        if args.dry_run:
            run.summary["message"] = (f"DRY RUN OK - would publish {len(plan['changed'])} changed + {len(plan['new'])} new partner file(s)"
                                      f" and archive {len(plan['leftover'])} no-longer-produced file(s); WORKING "
                                      f"{run.summary['frame']['working_rows_before']} -> {run.summary['frame']['working_rows_after']}")
        elif args.no_publish:
            # The frame is accepted (save_frame_state above); publish_state.json is NOT updated, so the next
            # normal run does not see NO_CHANGE: it rebuilds from this frame and publishes.
            run.summary["packages"]["publish_held"] = True
            run.actions.append("publish HELD (--no-publish): no partner file touched; the next normal run rebuilds and publishes")
            run.summary["message"] = (f"OK (publish held) - WORKING {run.summary['frame']['working_rows_before']} -> "
                                      f"{run.summary['frame']['working_rows_after']} rows; partner files built and gated but NOT published "
                                      f"({len(plan['changed'])} changed + {len(plan['new'])} new waiting); the next normal run publishes them")
        else:
            publish(run, plan)
            fp = {k: (md5(os.path.join(run.ws, *rel)) if os.path.isfile(os.path.join(run.ws, *rel)) else "missing")
                  for k, rel in FINGERPRINT_INPUTS.items()}  # after the refresh: WORKING is the published one
            with open(os.path.join(run.state_dir, "publish_state.json"), "w", encoding="utf-8") as f:
                json.dump({"real_submissions_md5": run.inputs["real_submissions_md5"], "overlay_md5": run.inputs["overlay_md5"],
                           "working_md5": run.summary["frame"]["working_md5_after"], "fingerprint": fp,
                           "published_at": now_s(), "run_id": run.run_id}, f, indent=1)
            if run.cfg["run_05_after_publish"]:
                run_05(run)
            run.summary["message"] = (f"OK - WORKING {run.summary['frame']['working_rows_before']} -> {run.summary['frame']['working_rows_after']} rows;"
                                      f" partners: {len(plan['changed'])} changed + {len(plan['new'])} new file(s) published,"
                                      f" {len(plan['leftover'])} no-longer-produced archived")
        status, exit_code = "OK", EXIT_OK
    except Blocked as e:
        status, exit_code = "BLOCKED", EXIT_BLOCKED
        run.summary["message"] = f"BLOCKED - {e}. Partners keep their last good files."
        run.log(run.summary["message"])
    except (RunError, Exception) as e:
        status, exit_code = "ERROR", EXIT_ERROR
        run.summary["message"] = f"ERROR - {e}. Partners keep their last good files."
        run.log(run.summary["message"])
        if not isinstance(e, RunError):
            run.log(traceback.format_exc())
    finally:
        run.summary.update({"status": status, "exit_code": exit_code, "finished": now_s(), "checks": run.checks,
                            "failed_checks": [c for c in run.checks if c["status"] == "FAIL"],
                            "warnings": [c for c in run.checks if c["status"] == "WARN"], "actions": run.actions,
                            "run_dir": run.run_dir})
        for p in (os.path.join(run.run_dir, "summary.json"), os.path.join(run.runs_root, "LATEST_SUMMARY.json")):
            with open(p, "w", encoding="utf-8") as f:
                json.dump(run.summary, f, indent=1)
        if run.lock_path and os.path.isfile(run.lock_path):
            os.remove(run.lock_path)
        if run.tmp_base and os.path.isdir(run.tmp_base) and (exit_code == EXIT_OK and not (args.dry_run and args.keep_sandbox)):
            shutil.rmtree(run.tmp_base, ignore_errors=True)
        if not args.dry_run and not args.check_env:
            prune(run)
        run.log(f"RESULT: {status} (exit {exit_code}) - {run.summary.get('message', '')}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
