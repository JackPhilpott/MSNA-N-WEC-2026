# ==============================================================================
# ACF -> ZOA handover of five Sokoto LGAs (Bodinga, Goronyo, Gwadabawa, Rabah, Tambuwal), staged -> LIVE partner folders
# (2026-09-25). Same design and same safeties as handover_chibok_damboa_to_FACT_2026-09-25.py (its sibling).
# DRY-RUN BY DEFAULT. Every live write needs --execute AND a recorded go (--jack-go "<who, when>"). The go must match what
# Jack actually confirmed; never run --execute on an unrecorded or paraphrased go.
#
# Order (each phase re-verifies what came before, and refuses if it can't):
#   manifest     write HANDOVER_MANIFEST_md5.txt for the staged files (staging only)
#   preflight    read-only checks of staging and live state
#   zoa          copy ZOA/Sokoto/<5 LGAs> into LIVE ZOA, md5-verify every file (refuses if any target LGA folder already exists)
#   boundary     back up, then overwrite, LIVE ZOA/LGA_boundaries_ZOA.kml (now draws all six ZOA LGAs), md5-verify
#   acf-remove   back up LIVE ACF/Sokoto (verify count + md5 of every file), THEN remove it. Last.
# NOT touched by this script (open items, reported separately): ACF's workbook, accessibility report, master_log, PDFs,
# LGA_boundaries_ACF.kml (the boundary builder writes nothing for a partner with no LGA, so it stays stale), and the staged
# PARTIAL ZOA_sampling_points_summary.xlsx (never copied; the fresh workbook comes from the staged workbook root instead).
# The KoBo tool is not touched (Jack: the DO rebuilds it from the WORKING frame). No partner note is sent by this script.
#
# Usage:  python handover_acf_sokoto_to_ZOA_2026-09-25.py <phase> [--execute --jack-go "..."] [--tool-live-confirmed]
# Rehearsal on a scratch replica: --live-root / --backup-root / --log-dir override the defaults.
# Rollback: "zoa" only ever creates ZOA/Sokoto/<LGA> folders (verified absent first), so delete those five folders;
# "boundary" and "acf-remove" keep verified backups under _archive_partner_package_backups/.
# ==============================================================================
import argparse
import csv
import hashlib
import os
import shutil
import stat
import sys
import time
from datetime import datetime
from pathlib import Path

WS = Path(r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA")
SAMPLING = WS / "4. Data" / "MSNA N-WEC 2026" / "1_sampling"
STAGE = SAMPLING / "resampling" / "output" / "staged_acf_to_zoa_2026-09-25" / "packages"
LOG_DIR_DEFAULT = SAMPLING / "resampling" / "output" / "staged_acf_to_zoa_2026-09-25"
MANIFEST = LOG_DIR_DEFAULT / "HANDOVER_MANIFEST_md5.txt"
LGAS = ["Bodinga", "Goronyo", "Gwadabawa", "Rabah", "Tambuwal"]
EXPECT_LGA_FILES = {"Bodinga": 17, "Goronyo": 19, "Gwadabawa": 22, "Rabah": 26, "Tambuwal": 19}   # = 103, counted from staging 2026-09-25
EXPECT_ACF_SOKOTO_FILES = 176
BOUNDARY = "ZOA/LGA_boundaries_ZOA.kml"


def lp(p):
    """Extended-length path (\\\\?\\...) so paths over 260 chars work on Windows. The real backup root is ~198 chars deep, so most
    backup destination paths exceed MAX_PATH (found live 2026-09-25 on the IMC/Borno backup; a short-path rehearsal hid it)."""
    s = os.path.abspath(str(p))
    return Path(s if s.startswith("\\\\?\\") else "\\\\?\\" + s)


def plain(p):
    s = str(p)
    return s[4:] if s.startswith("\\\\?\\") else s


def _clear_readonly_then_retry(func, p, exc):
    """Every folder in these OneDrive package trees carries the ReadOnly attribute (found live 2026-09-25: all 20 dirs of IMC/Borno,
    and copytree copies it onto the backup), so rmdir raises 'Access denied' until the attribute is cleared."""
    os.chmod(p, stat.S_IWRITE)
    func(p)


def rmtree_retry(path, tries=8, delay=6):
    """rmtree that clears the ReadOnly attribute, and retries in case OneDrive briefly holds a syncing folder (it resumes from what is left)."""
    for i in range(tries):
        try:
            shutil.rmtree(path, onexc=_clear_readonly_then_retry)
            return
        except OSError as e:
            print(f"  (delete retry {i + 1}/{tries}: {type(e).__name__}: {str(e)[:70]})")
            time.sleep(delay)
    shutil.rmtree(path, onexc=_clear_readonly_then_retry)


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(p, base):
    return Path(p).relative_to(base).as_posix()


def staged_files():
    files = []
    for lga in LGAS:
        files += sorted(p for p in (STAGE / "ZOA" / "Sokoto" / lga).rglob("*") if p.is_file())
    files.append(STAGE / BOUNDARY)
    return files


def load_manifest():
    if not MANIFEST.exists():
        return None
    out = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if line.strip():
            h, r = line.split("  ", 1)
            out[r] = h
    return out


class Run:
    def __init__(self, a):
        self.a = a
        self.live = Path(a.live_root)
        self.backup_root = Path(a.backup_root)
        self.log_path = Path(a.log_dir) / "handover_execution_log.csv"
        self.ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.fails = []

    def check(self, ok, msg):
        print(("  PASS  " if ok else "  FAIL  ") + msg)
        if not ok:
            self.fails.append(msg)
        return ok

    def log(self, phase, action, src="", dst="", h="", ok=True):
        if not self.a.execute:
            return
        new = not self.log_path.exists()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.log_path, "a", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["timestamp", "phase", "action", "src", "dst", "md5", "ok", "jack_go"])
            w.writerow([datetime.now().isoformat(timespec="seconds"), phase, action, src, dst, h, ok, self.a.jack_go])

    def phase_done(self, name):
        if not self.log_path.exists():
            return False
        with open(self.log_path, encoding="utf-8") as f:
            return any(r["phase"] == name and r["action"] == "PHASE_DONE" and r["ok"] == "True" for r in csv.DictReader(f))

    # ---------------- checks shared by all phases ----------------
    def staging_checks(self):
        man = load_manifest()
        if not self.check(man is not None, f"manifest present ({MANIFEST.name}); run 'manifest' first if not"):
            return None
        files = staged_files()
        want = sum(EXPECT_LGA_FILES.values()) + 1
        self.check(len(files) == want, f"staged file count = {len(files)} (expected {want})")
        for lga in LGAS:
            n = sum(1 for p in files if f"/Sokoto/{lga}/" in p.as_posix())
            self.check(n == EXPECT_LGA_FILES[lga], f"staged {lga} files = {n} (expected {EXPECT_LGA_FILES[lga]})")
        self.check(not any(p.suffix == ".xlsx" for p in files), "no workbook in the staged handover set (the partial staged workbook is excluded)")
        bad = [rel(p, STAGE) for p in files if man.get(rel(p, STAGE)) != md5(p)]
        self.check(not bad, f"every staged file matches the manifest md5 ({len(files)} files)" + (f"; MISMATCH: {bad[:5]}" if bad else ""))
        return man

    def live_state_checks(self, expect_zoa_absent=True):
        self.check((self.live / "ZOA").is_dir(), "live ZOA folder exists")
        self.check((self.live / "ZOA" / "Sokoto" / "Wurno").is_dir(), "live ZOA/Sokoto/Wurno exists (ZOA's existing LGA is untouched)")
        self.check((self.live / "ACF" / "Sokoto").is_dir(), "live ACF/Sokoto exists")
        if expect_zoa_absent:
            for lga in LGAS:
                self.check(not (self.live / "ZOA" / "Sokoto" / lga).exists(), f"live ZOA/Sokoto/{lga} does NOT exist yet (no overwrite possible)")
        self.check((self.live / BOUNDARY).is_file(), f"live {BOUNDARY} exists")
        n = sum(1 for p in (self.live / "ACF" / "Sokoto").rglob("*") if p.is_file()) if (self.live / "ACF" / "Sokoto").is_dir() else -1
        self.check(n == EXPECT_ACF_SOKOTO_FILES, f"live ACF/Sokoto file count = {n} (expected {EXPECT_ACF_SOKOTO_FILES})")
        self.check(self.backup_root.is_dir(), f"backup root exists: {self.backup_root}")

    def require_execute_flags(self, need_tool=False):
        if not self.a.execute:
            return True
        ok = self.check(bool(self.a.jack_go and self.a.jack_go.strip()), "--jack-go given (the recorded go, written to the log)")
        if need_tool:
            ok &= self.check(self.a.tool_live_confirmed, "--tool-live-confirmed given (tool question answered; the reason is in --jack-go)")
        return ok

    # ---------------- phases ----------------
    def manifest(self):
        files = staged_files()
        lines = [f"{md5(p)}  {rel(p, STAGE)}" for p in files]
        print(f"{len(files)} staged files")
        if self.a.execute:
            MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print("wrote", MANIFEST)
        else:
            print("(dry-run) would write", MANIFEST)
            print("\n".join(lines[:3] + ["..."]))

    def preflight(self):
        print("== preflight (read-only) ==")
        self.staging_checks()
        self.live_state_checks()

    def zoa(self):
        print("== phase zoa: copy 5 LGA folders into live ZOA/Sokoto ==")
        man = self.staging_checks()
        self.live_state_checks(expect_zoa_absent=True)
        ok = self.require_execute_flags(need_tool=True)
        if self.fails or man is None or not ok:
            return self.stop()
        items = [p for p in staged_files() if "/Sokoto/" in p.as_posix()]
        print(f"  plan: copy {len(items)} files into {self.live / 'ZOA' / 'Sokoto'}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied")
        for p in items:
            dst = self.live / "ZOA" / p.relative_to(STAGE / "ZOA")
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dst)
            h = md5(dst)
            good = h == man[rel(p, STAGE)]
            self.log("zoa", "COPY", str(p), str(dst), h, good)
            if not good:
                print(f"  FAIL md5 mismatch after copy: {dst}")
                return self.stop()
        self.log("zoa", "PHASE_DONE")
        print(f"  DONE: {len(items)} files copied and md5-verified")

    def boundary(self):
        print("== phase boundary: back up then overwrite ZOA's LGA boundary KML ==")
        man = self.staging_checks()
        self.live_state_checks(expect_zoa_absent=False)
        ok = self.require_execute_flags()
        if self.a.execute and not self.phase_done("zoa"):
            self.check(False, "phase 'zoa' not completed in the log yet")
        if self.fails or man is None or not ok:
            return self.stop()
        bdir = self.backup_root / f"{self.ts}_zoa_boundary_kml_pre_handover"
        print(f"  plan: back up {BOUNDARY} to {bdir}, then overwrite from staging")
        if not self.a.execute:
            return print("  (dry-run) nothing written")
        bdir.mkdir(parents=True, exist_ok=True)
        live_p, src = self.live / BOUNDARY, STAGE / BOUNDARY
        bak = bdir / (BOUNDARY.split("/")[0] + "_" + Path(BOUNDARY).name)
        shutil.copy2(live_p, bak)
        good = md5(bak) == md5(live_p)
        self.log("boundary", "BACKUP", str(live_p), str(bak), md5(bak), good)
        if not good:
            return self.stop()
        shutil.copy2(src, live_p)
        h = md5(live_p)
        good = h == man[BOUNDARY]
        self.log("boundary", "OVERWRITE", str(src), str(live_p), h, good)
        if not good:
            return self.stop()
        self.log("boundary", "PHASE_DONE")
        print("  DONE: ZOA boundary KML backed up and replaced, md5-verified")

    def acf_remove(self):
        print("== phase acf-remove: verified backup of ACF/Sokoto, THEN removal (last step) ==")
        man = self.staging_checks()
        self.live_state_checks(expect_zoa_absent=False)
        ok = self.require_execute_flags()
        zoa_bad = [rel(p, STAGE) for p in staged_files()
                   if "/Sokoto/" in p.as_posix() and not ((self.live / "ZOA" / p.relative_to(STAGE / "ZOA")).is_file()
                                                          and md5(self.live / "ZOA" / p.relative_to(STAGE / "ZOA")) == (man or {}).get(rel(p, STAGE)))]
        self.check(not zoa_bad, f"live ZOA holds all {sum(EXPECT_LGA_FILES.values())} copied files with matching md5 ({len(zoa_bad)} missing/different)")
        self.check((self.live / BOUNDARY).is_file() and md5(self.live / BOUNDARY) == (man or {}).get(BOUNDARY), "live LGA_boundaries_ZOA.kml matches the manifest")
        if self.a.execute:
            self.check(self.phase_done("zoa") and self.phase_done("boundary"), "phases 'zoa' and 'boundary' are both PHASE_DONE in the log")
        if self.fails or man is None or not ok:
            return self.stop()
        src = lp(self.live / "ACF" / "Sokoto")
        dst = lp(self.backup_root / f"{self.ts}_acf_sokoto_reassigned_to_ZOA" / "ACF_Sokoto")
        print(f"  plan: copy {plain(src)} -> {plain(dst)}, verify {EXPECT_ACF_SOKOTO_FILES} files by md5, then remove {plain(src)}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied or removed")
        shutil.copytree(src, dst)
        src_files = sorted(p for p in src.rglob("*") if p.is_file())
        bad = [rel(p, src) for p in src_files if not (dst / p.relative_to(src)).is_file() or md5(dst / p.relative_to(src)) != md5(p)]
        n_dst = sum(1 for p in dst.rglob("*") if p.is_file())
        good = (not bad) and n_dst == len(src_files) == EXPECT_ACF_SOKOTO_FILES
        self.log("acf-remove", "BACKUP_VERIFIED", plain(src), plain(dst), f"{n_dst} files", good)
        if not good:
            print(f"  FAIL backup verification: {len(bad)} bad, {n_dst} backed up vs {len(src_files)} source. ACF/Sokoto NOT removed.")
            return self.stop()
        rmtree_retry(src)
        gone = not src.exists()
        self.log("acf-remove", "REMOVED", plain(src), "", "", gone)
        if not gone:
            return self.stop()
        self.log("acf-remove", "PHASE_DONE")
        print(f"  DONE: backup verified ({n_dst} files) at {plain(dst)}; ACF/Sokoto removed")

    def stop(self):
        print("\nSTOPPED, nothing further was done:")
        for m in self.fails:
            print("  -", m)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["manifest", "preflight", "zoa", "boundary", "acf-remove"])
    ap.add_argument("--execute", action="store_true", help="really write (default is a read-only dry run)")
    ap.add_argument("--jack-go", default="", help='the recorded go, e.g. "Jack Philpott, <ISO time of his confirmation click>, register page decision R"')
    ap.add_argument("--tool-live-confirmed", action="store_true")
    ap.add_argument("--live-root", default=str(WS / "3. External coordination" / "NGA MSNA 2026 Package"))
    ap.add_argument("--backup-root", default=str(SAMPLING / "resampling" / "output" / "_archive_partner_package_backups"))
    ap.add_argument("--log-dir", default=str(LOG_DIR_DEFAULT))
    a = ap.parse_args()
    r = Run(a)
    print(("EXECUTE" if a.execute else "DRY-RUN"), "|", a.phase, "| live root:", a.live_root)
    {"manifest": r.manifest, "preflight": r.preflight, "zoa": r.zoa, "boundary": r.boundary, "acf-remove": r.acf_remove}[a.phase]()
    if r.fails:
        r.stop()
    print("\nno failed checks" if not a.execute else "\ndone")


if __name__ == "__main__":
    main()
