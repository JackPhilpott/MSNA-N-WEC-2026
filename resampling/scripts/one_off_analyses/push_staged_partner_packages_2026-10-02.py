# ==============================================================================
# 2026-10-02 ONE-OFF (Coordinator instruction under Jack's 3-hour approval
# window, ~01:30-04:30 2 Oct): push the staged full partner-package build
# (build_partner_dc_packages.py run with BUILD_DC_OUT_ROOT=staging) to the
# live partner folders.
#
# Why staged + per-file backup instead of "back up the whole live tree":
# the live package root holds 7,151 files, mostly OneDrive online-only
# placeholders; copying the tree hydrates every one (744 files took 10 min,
# 476 MB). Only files the build REPLACES need a backup.
#
# For every staged file (except the root-level dc_package_uuid_
# reconciliation_report.csv, which has never lived at the partner-facing
# root): back up the live counterpart if it exists, copy staged -> live,
# then verify live == staged by MD5. Never deletes anything live (leftovers
# from a no-longer-produced LGA/cluster are a morning item).
# Writes a manifest CSV next to the backup folder.
# ==============================================================================
import csv
import hashlib
import os
import shutil
import sys

STAGE = r"C:\Users\JACKPH~1\AppData\Local\Temp\msna_pkg_stage_20261002"
LIVE = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
BAK = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\output\_pkgbak\2026-10-02_replaced"
SKIP_ROOT_FILES = {"dc_package_uuid_reconciliation_report.csv"}
DRY_RUN = "--dry-run" in sys.argv


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


staged = []
for root, _, files in os.walk(STAGE):
    for fn in files:
        rel = os.path.relpath(os.path.join(root, fn), STAGE)
        if os.path.dirname(rel) == "" and fn in SKIP_ROOT_FILES:
            continue
        staged.append(rel)
staged.sort()
print(f"staged files to push: {len(staged)} | dry_run={DRY_RUN}")

manifest = []
for i, rel in enumerate(staged, 1):
    src = os.path.join(STAGE, rel)
    dst = os.path.join(LIVE, rel)
    existed = os.path.exists(dst)
    live_before = md5(dst) if existed else ""
    staged_md5 = md5(src)
    if not DRY_RUN:
        if existed:
            bak = os.path.join(BAK, rel)
            os.makedirs(os.path.dirname(bak), exist_ok=True)
            shutil.copy2(dst, bak)
            if md5(bak) != live_before:
                raise SystemExit(f"STOP: backup of {rel} does not match the live file - nothing further copied.")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        live_after = md5(dst)
        if live_after != staged_md5:
            raise SystemExit(f"STOP: live copy of {rel} does not match staged - investigate before continuing.")
    else:
        live_after = ""
    manifest.append({"rel_path": rel, "existed_live": existed, "changed": existed and live_before != staged_md5,
                     "live_md5_before": live_before, "staged_md5": staged_md5, "live_md5_after": live_after})
    if i % 100 == 0:
        print(f"  {i}/{len(staged)}")

out = BAK + ("_DRYRUN_manifest.csv" if DRY_RUN else "_manifest.csv")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(manifest[0].keys()))
    w.writeheader()
    w.writerows(manifest)
n_new = sum(1 for m in manifest if not m["existed_live"])
n_changed = sum(1 for m in manifest if m["changed"])
n_same = len(manifest) - n_new - n_changed
print(f"done: {len(manifest)} files | new {n_new} | replaced-with-changes {n_changed} | identical-already {n_same}")
print("manifest:", out)
