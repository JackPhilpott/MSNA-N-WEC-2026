# ==============================================================================
# Chibok + Damboa handover, staged -> LIVE partner folders (2026-09-25).
# DRY-RUN BY DEFAULT. Every live write needs --execute AND Jack's direct go
# (--jack-go "<who, when>"), which is recorded in the log. Never run --execute
# on a peer's word alone.
#
# Order (each phase re-verifies what came before, and refuses if it can't):
#   0. Jack confirms the LIVE KoBo form version and uploads the patched forms
#      (tool_update_2026-09-25_chibok_damboa_imc_to_fact/). Manual; the "fact"
#      phase demands --tool-live-confirmed so it cannot be skipped by accident.
#   manifest    write HANDOVER_MANIFEST_md5.txt for the staged files (staging only)
#   preflight   read-only checks of staging and live state
#   fact        copy FACT/Borno/Chibok and FACT/Borno/Damboa into LIVE FACT, md5-verify every file
#   boundary    back up, then overwrite, LIVE LGA_boundaries_FACT.kml and LGA_boundaries_IMC.kml, md5-verify
#   imc-remove  back up LIVE IMC/Borno (verify count + md5 of every file), THEN remove it. Last.
# Then Jack sends the two notes (NOTE_to_*_DRAFT.html). FACT/IMC workbooks wait for the data repair.
#
# Usage:  python handover_chibok_damboa_to_FACT_2026-09-25.py <phase> [--execute --jack-go "..."] [--tool-live-confirmed]
# Rehearsal on a scratch replica: --live-root / --backup-root / --log-dir override the defaults.
# Rollback: "fact" only ever creates FACT/Borno/Chibok and FACT/Borno/Damboa (verified absent first), so delete those two
# folders; "boundary" and "imc-remove" keep verified backups under _archive_partner_package_backups/.
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
STAGE = SAMPLING / "resampling" / "output" / "staged_packages_2026-09-25_chibok_damboa_to_FACT"
MANIFEST = STAGE / "HANDOVER_MANIFEST_md5.txt"
LGAS = ["Chibok", "Damboa"]
EXPECT_LGA_FILES = {"Chibok": 27, "Damboa": 27}
EXPECT_IMC_BORNO_FILES = 103
BOUNDARIES = ["FACT/LGA_boundaries_FACT.kml", "IMC/LGA_boundaries_IMC.kml"]


def lp(p):
    """Extended-length path (\\\\?\\...) so paths over 260 chars work on Windows. Needed for the IMC/Borno backup: the real backup
    root is ~198 chars deep, so 74 of the 103 destination paths exceed MAX_PATH (found live 2026-09-25; a short-path rehearsal hid it)."""
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
        files += sorted(p for p in (STAGE / "FACT" / "Borno" / lga).rglob("*") if p.is_file())
    files += [STAGE / b for b in BOUNDARIES]
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
        self.check(len(files) == sum(EXPECT_LGA_FILES.values()) + len(BOUNDARIES), f"staged file count = {len(files)} (expected {sum(EXPECT_LGA_FILES.values()) + len(BOUNDARIES)})")
        for lga in LGAS:
            n = sum(1 for p in files if f"/Borno/{lga}/" in p.as_posix())
            self.check(n == EXPECT_LGA_FILES[lga], f"staged {lga} files = {n} (expected {EXPECT_LGA_FILES[lga]})")
        bad = [rel(p, STAGE) for p in files if man.get(rel(p, STAGE)) != md5(p)]
        self.check(not bad, f"every staged file matches the manifest md5 ({len(files)} files)" + (f"; MISMATCH: {bad[:5]}" if bad else ""))
        return man

    def live_state_checks(self, expect_fact_absent=True):
        self.check((self.live / "FACT").is_dir(), "live FACT folder exists")
        self.check((self.live / "IMC" / "Borno").is_dir(), "live IMC/Borno exists")
        if expect_fact_absent:
            for lga in LGAS:
                self.check(not (self.live / "FACT" / "Borno" / lga).exists(), f"live FACT/Borno/{lga} does NOT exist yet (no overwrite possible)")
        for b in BOUNDARIES:
            self.check((self.live / b).is_file(), f"live {b} exists")
        n = sum(1 for p in (self.live / "IMC" / "Borno").rglob("*") if p.is_file()) if (self.live / "IMC" / "Borno").is_dir() else -1
        self.check(n == EXPECT_IMC_BORNO_FILES, f"live IMC/Borno file count = {n} (expected {EXPECT_IMC_BORNO_FILES})")
        self.check(self.backup_root.is_dir(), f"backup root exists: {self.backup_root}")

    def require_execute_flags(self, need_tool=False):
        if not self.a.execute:
            return True
        ok = self.check(bool(self.a.jack_go and self.a.jack_go.strip()), "--jack-go given (Jack's direct go, recorded in the log)")
        if need_tool:
            ok &= self.check(self.a.tool_live_confirmed, "--tool-live-confirmed given (forms live, Jack confirmed the live version)")
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

    def fact(self):
        print("== phase fact: copy 2 LGA folders into live FACT ==")
        man = self.staging_checks()
        self.live_state_checks(expect_fact_absent=True)
        ok = self.require_execute_flags(need_tool=True)
        if self.fails or man is None or not ok:
            return self.stop()
        items = [p for p in staged_files() if "/Borno/" in p.as_posix()]
        print(f"  plan: copy {len(items)} files into {self.live / 'FACT' / 'Borno'}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied")
        for p in items:
            dst = self.live / "FACT" / p.relative_to(STAGE / "FACT")
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dst)
            h = md5(dst)
            good = h == man[rel(p, STAGE)]
            self.log("fact", "COPY", str(p), str(dst), h, good)
            if not good:
                print(f"  FAIL md5 mismatch after copy: {dst}")
                return self.stop()
        self.log("fact", "PHASE_DONE")
        print(f"  DONE: {len(items)} files copied and md5-verified")

    def boundary(self):
        print("== phase boundary: back up then overwrite the two LGA boundary KMLs ==")
        man = self.staging_checks()
        self.live_state_checks(expect_fact_absent=False)
        ok = self.require_execute_flags()
        if self.a.execute and not self.phase_done("fact"):
            self.check(False, "phase 'fact' not completed in the log yet")
        if self.fails or man is None or not ok:
            return self.stop()
        bdir = self.backup_root / f"{self.ts}_boundary_kml_pre_handover"
        print(f"  plan: back up {BOUNDARIES} to {bdir}, then overwrite from staging")
        if not self.a.execute:
            return print("  (dry-run) nothing written")
        bdir.mkdir(parents=True, exist_ok=True)
        for b in BOUNDARIES:
            live_p, src = self.live / b, STAGE / b
            bak = bdir / (b.split("/")[0] + "_" + Path(b).name)
            shutil.copy2(live_p, bak)
            good = md5(bak) == md5(live_p)
            self.log("boundary", "BACKUP", str(live_p), str(bak), md5(bak), good)
            if not good:
                return self.stop()
            shutil.copy2(src, live_p)
            h = md5(live_p)
            good = h == man[b]
            self.log("boundary", "OVERWRITE", str(src), str(live_p), h, good)
            if not good:
                return self.stop()
        self.log("boundary", "PHASE_DONE")
        print("  DONE: both boundary KMLs backed up and replaced, md5-verified")

    def imc_remove(self):
        print("== phase imc-remove: verified backup of IMC/Borno, THEN removal (last step) ==")
        man = self.staging_checks()
        self.live_state_checks(expect_fact_absent=False)
        ok = self.require_execute_flags()
        # FACT must already hold verified copies of everything
        fact_bad = [rel(p, STAGE) for p in staged_files()
                    if "/Borno/" in p.as_posix() and not ((self.live / "FACT" / p.relative_to(STAGE / "FACT")).is_file()
                                                          and md5(self.live / "FACT" / p.relative_to(STAGE / "FACT")) == (man or {}).get(rel(p, STAGE)))]
        self.check(not fact_bad, f"live FACT holds all 54 copied files with matching md5 ({len(fact_bad)} missing/different)")
        self.check((self.live / BOUNDARIES[0]).is_file() and md5(self.live / BOUNDARIES[0]) == (man or {}).get(BOUNDARIES[0]), "live LGA_boundaries_FACT.kml matches the manifest")
        if self.a.execute:
            self.check(self.phase_done("fact") and self.phase_done("boundary"), "phases 'fact' and 'boundary' are both PHASE_DONE in the log")
        if self.fails or man is None or not ok:
            return self.stop()
        src = lp(self.live / "IMC" / "Borno")
        dst = lp(self.backup_root / f"{self.ts}_imc_chibok_damboa_reassigned_to_FACT" / "IMC_Borno")
        print(f"  plan: copy {plain(src)} -> {plain(dst)}, verify {EXPECT_IMC_BORNO_FILES} files by md5, then remove {plain(src)}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied or removed")
        shutil.copytree(src, dst)
        src_files = sorted(p for p in src.rglob("*") if p.is_file())
        bad = [rel(p, src) for p in src_files if not (dst / p.relative_to(src)).is_file() or md5(dst / p.relative_to(src)) != md5(p)]
        n_dst = sum(1 for p in dst.rglob("*") if p.is_file())
        good = (not bad) and n_dst == len(src_files) == EXPECT_IMC_BORNO_FILES
        self.log("imc-remove", "BACKUP_VERIFIED", plain(src), plain(dst), f"{n_dst} files", good)
        if not good:
            print(f"  FAIL backup verification: {len(bad)} bad, {n_dst} backed up vs {len(src_files)} source. IMC/Borno NOT removed.")
            return self.stop()
        rmtree_retry(src)
        gone = not src.exists()
        self.log("imc-remove", "REMOVED", plain(src), "", "", gone)
        if not gone:
            return self.stop()
        self.log("imc-remove", "PHASE_DONE")
        print(f"  DONE: backup verified ({n_dst} files) at {plain(dst)}; IMC/Borno removed")

    def stop(self):
        print("\nSTOPPED, nothing further was done:")
        for m in self.fails:
            print("  -", m)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["manifest", "preflight", "fact", "boundary", "imc-remove"])
    ap.add_argument("--execute", action="store_true", help="really write (default is a read-only dry run)")
    ap.add_argument("--jack-go", default="", help='Jack\'s direct go, e.g. "Jack, 2026-09-25 HH:MM, direct"')
    ap.add_argument("--tool-live-confirmed", action="store_true")
    ap.add_argument("--live-root", default=str(WS / "3. External coordination" / "NGA MSNA 2026 Package"))
    ap.add_argument("--backup-root", default=str(SAMPLING / "resampling" / "output" / "_archive_partner_package_backups"))
    ap.add_argument("--log-dir", default=str(STAGE))
    a = ap.parse_args()
    r = Run(a)
    print(("EXECUTE" if a.execute else "DRY-RUN"), "|", a.phase, "| live root:", a.live_root)
    {"manifest": r.manifest, "preflight": r.preflight, "fact": r.fact, "boundary": r.boundary, "imc-remove": r.imc_remove}[a.phase]()
    if r.fails:
        r.stop()
    print("\nno failed checks" if not a.execute else "\ndone")


if __name__ == "__main__":
    main()
