# ==============================================================================
# R2 batch (2026-09-25): Kankia (Katsina, NG021020) IMC -> FACT handover, plus the stale leftovers of ACF and IMC (register decision T,
# option 2). Sibling of handover_chibok_damboa_to_FACT_2026-09-25.py and handover_acf_sokoto_to_ZOA_2026-09-25.py, with their lessons built in:
# extended-length paths for the backups (the real backup root is ~198 chars deep), ReadOnly attribute cleared before removal (every folder in these
# OneDrive trees carries it), content-level comparison for .xlsx (Microsoft 365 rewrites metadata parts, so xlsx md5s drift).
# DRY-RUN BY DEFAULT. --execute needs --jack-go "<the recorded go: who, when, which register decision>" and only touches what is listed below.
#
# Order (each phase re-verifies what came before and refuses if it can't):
#   manifest             write HANDOVER_MANIFEST_md5.txt for the staged Kankia package (staging only)
#   preflight            read-only checks of staging and live state
#   fact                 copy FACT/Katsina/Kankia (27 files) into LIVE FACT (refuses if the folder already exists)
#   boundary             back up, then overwrite, LIVE FACT/LGA_boundaries_FACT.kml (adds Kankia)
#   workbook             back up, then replace, the LIVE FACT workbook with the staged one that includes Kankia
#   imc-katsina-remove   per-file manifest, verified backup, THEN removal of LIVE IMC/Katsina (39 files). Needs FACT to hold every file first.
#   leftovers            per-file manifest, verified backup, THEN removal of 4 stale files: ACF and IMC sampling workbook + LGA boundary KML
#                        (ACF and IMC have no LGA left). KEPT: accessibility reports, PDFs, master_log folders.
# Traceability (Jack's condition on T): every removal leaves (a) a verified backup under the backup root, (b) a per-file manifest CSV
# (relative path, size, md5) BEFORE removal and a per-file verification CSV after, (c) dated log lines. All in handover_traceability_2026-09-25/.
# The KoBo tool is not touched and no partner note is sent.
# Usage: python handover_kankia_and_leftovers_2026-09-25.py <phase> [--execute --jack-go "..."]
# Rehearsal on a scratch replica: --live-root / --backup-root / --log-dir / --trace-dir override the defaults.
# ==============================================================================
import argparse
import csv
import hashlib
import os
import shutil
import stat
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path

BS = chr(92)
WS = Path(r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA")
SAMPLING = WS / "4. Data" / "MSNA N-WEC 2026" / "1_sampling"
OUT = SAMPLING / "resampling" / "output"
STAGE = OUT / "staged_packages_2026-09-25_kankia_to_FACT"
WB_STAGE = OUT / "staged_workbooks_2026-09-25_kankia_fact"
WB_SEED_REF = OUT / "staged_workbooks_2026-09-25_fact_imc_zoa" / "FACT" / "FACT_sampling_points_summary.xlsx"   # what R's swap put live (content)
TRACE_DEFAULT = OUT / "handover_traceability_2026-09-25"
MANIFEST = STAGE / "HANDOVER_MANIFEST_md5.txt"
EXPECT_KANKIA_FILES = 27
EXPECT_IMC_KATSINA_FILES = 39
BOUNDARY = "FACT/LGA_boundaries_FACT.kml"
WORKBOOK = "FACT/FACT_sampling_points_summary.xlsx"
LEFTOVERS = [("ACF", "ACF_sampling_points_summary.xlsx"), ("ACF", "LGA_boundaries_ACF.kml"),
             ("IMC", "IMC_sampling_points_summary.xlsx"), ("IMC", "LGA_boundaries_IMC.kml")]
KEEP = {"ACF": {"ACF_accessibility_report.xlsx", "How_To_Use_This_Package.pdf", "MSNA_NGA_MapsMe_Guide.pdf", "NGA_MSNA_2026_Data_Collection_SOP.pdf"},
        "IMC": {"IMC_accessibility_report.xlsx", "How_To_Use_This_Package.pdf", "MSNA_NGA_MapsMe_Guide.pdf", "NGA_MSNA_2026_Data_Collection_SOP.pdf"}}
KEEP_MASTER_LOG = {"ACF": 6, "IMC": 2}
META = ("docProps/", "customXml/", "[trash]/")


def lp(p):
    """Extended-length path so paths over 260 chars work on Windows."""
    s = os.path.abspath(str(p))
    pre = BS * 2 + "?" + BS
    return Path(s if s.startswith(pre) else pre + s)


def plain(p):
    s = str(p)
    pre = BS * 2 + "?" + BS
    return s[4:] if s.startswith(pre) else s


def _clear_readonly_then_retry(func, p, exc):
    os.chmod(p, stat.S_IWRITE)
    func(p)


def rmtree_retry(path, tries=8, delay=6):
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
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def xlsx_content(path):
    z = zipfile.ZipFile(path)
    return {i.filename: i.CRC for i in z.infolist() if not i.filename.startswith(META)}


def rel(p, base):
    return Path(p).relative_to(base).as_posix()


def staged_files():
    files = sorted(p for p in (STAGE / "FACT" / "Katsina" / "Kankia").rglob("*") if p.is_file())
    return files + [STAGE / BOUNDARY]


def load_manifest():
    if not MANIFEST.exists():
        return None
    return {l.split("  ", 1)[1].strip(): l.split("  ", 1)[0] for l in MANIFEST.read_text(encoding="utf-8").splitlines() if l.strip()}


class Run:
    def __init__(self, a):
        self.a = a
        self.live, self.backup_root, self.trace = Path(a.live_root), Path(a.backup_root), Path(a.trace_dir)
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
                w.writerow(["timestamp", "phase", "action", "src", "dst", "md5", "ok", "go"])
            w.writerow([datetime.now().isoformat(timespec="seconds"), phase, action, src, dst, h, ok, self.a.jack_go])

    def phase_done(self, name):
        if not self.log_path.exists():
            return False
        with open(self.log_path, encoding="utf-8") as f:
            return any(r["phase"] == name and r["action"] == "PHASE_DONE" and r["ok"] == "True" for r in csv.DictReader(f))

    def stop(self):
        print("\nSTOPPED, nothing further was done:")
        for m in self.fails:
            print("  -", m)
        sys.exit(1)

    def need_flags(self):
        return (not self.a.execute) or self.check(bool(self.a.jack_go.strip()), "--jack-go given (recorded in the log)")

    # ---------------- shared checks ----------------
    def staging_checks(self):
        man = load_manifest()
        if not self.check(man is not None, f"manifest present ({MANIFEST.name}); run 'manifest --execute' first if not"):
            return None
        files = staged_files()
        self.check(len(files) == EXPECT_KANKIA_FILES + 1, f"staged file count = {len(files)} (expected {EXPECT_KANKIA_FILES + 1}: 27 Kankia files + boundary KML)")
        bad = [rel(p, STAGE) for p in files if man.get(rel(p, STAGE)) != md5(p)]
        self.check(not bad, f"every staged file matches the manifest md5 ({len(files)} files)" + (f"; MISMATCH {bad[:3]}" if bad else ""))
        swb = WB_STAGE / WORKBOOK
        self.check(swb.is_file(), "staged FACT workbook (with Kankia) exists")
        return man

    def live_state_checks(self, kankia_absent):
        self.check((self.live / "FACT" / "Katsina").is_dir(), "live FACT/Katsina exists")
        if kankia_absent:
            self.check(not (self.live / "FACT" / "Katsina" / "Kankia").exists(), "live FACT/Katsina/Kankia does NOT exist yet (no overwrite possible)")
        self.check((self.live / BOUNDARY).is_file(), f"live {BOUNDARY} exists")
        self.check((self.live / WORKBOOK).is_file(), f"live {WORKBOOK} exists")
        kp = self.live / "IMC" / "Katsina"
        n = sum(1 for p in lp(kp).rglob("*") if p.is_file()) if kp.is_dir() else -1
        self.check(n == EXPECT_IMC_KATSINA_FILES or self.phase_done("imc-katsina-remove"), f"live IMC/Katsina file count = {n} (expected {EXPECT_IMC_KATSINA_FILES})")
        for part, fn in LEFTOVERS:
            self.check((self.live / part / fn).is_file() or self.phase_done("leftovers"), f"live {part}/{fn} exists")
        self.check(self.backup_root.is_dir(), f"backup root exists: {self.backup_root}")

    def write_manifest_csv(self, name, entries):
        """entries: list of (label, absolute Path). Written to the trace dir BEFORE anything is removed."""
        self.trace.mkdir(parents=True, exist_ok=True)
        path = self.trace / name
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["relative_path", "size_bytes", "md5"])
            for label, p in entries:
                lpth = lp(p)
                w.writerow([label, lpth.stat().st_size, md5(lpth)])
        return path

    def verify_backup_csv(self, manifest_path, backup_root_dir, out_name):
        rows = list(csv.DictReader(open(manifest_path, encoding="utf-8")))
        res = []
        for r in rows:
            f = lp(backup_root_dir / r["relative_path"].replace("/", os.sep))
            good = f.is_file() and f.stat().st_size == int(r["size_bytes"]) and md5(f) == r["md5"]
            res.append({**r, "backup_path": plain(f), "backup_verified": good})
        with open(self.trace / out_name, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(res[0].keys()))
            w.writeheader()
            w.writerows(res)
        return all(x["backup_verified"] for x in res), len(rows)

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

    def preflight(self):
        print("== preflight (read-only) ==")
        self.staging_checks()
        self.live_state_checks(kankia_absent=True)
        ref = xlsx_content(WB_SEED_REF) if WB_SEED_REF.is_file() else None
        live = self.live / WORKBOOK
        self.check(ref is not None and live.is_file() and xlsx_content(live) == ref,
                   "live FACT workbook is content-identical to the file the staged workbook was built over (nobody has saved over it since; metadata parts ignored)")

    def fact(self):
        print("== phase fact: copy Kankia (27 files) into live FACT/Katsina ==")
        man = self.staging_checks()
        self.live_state_checks(kankia_absent=True)
        self.need_flags()
        if self.fails or man is None:
            return self.stop()
        items = [p for p in staged_files() if "/Katsina/Kankia/" in p.as_posix()]
        print(f"  plan: copy {len(items)} files into {self.live / 'FACT' / 'Katsina'}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied")
        for p in items:
            dst = lp(self.live / "FACT" / p.relative_to(STAGE / "FACT"))
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dst)
            h = md5(dst)
            good = h == man[rel(p, STAGE)]
            self.log("fact", "COPY", str(p), plain(dst), h, good)
            if not good:
                print(f"  FAIL md5 mismatch after copy: {plain(dst)}")
                return self.stop()
        self.log("fact", "PHASE_DONE")
        print(f"  DONE: {len(items)} files copied and md5-verified")

    def boundary(self):
        print("== phase boundary: back up then overwrite FACT's LGA boundary KML ==")
        man = self.staging_checks()
        self.live_state_checks(kankia_absent=False)
        self.need_flags()
        if self.a.execute:
            self.check(self.phase_done("fact"), "phase 'fact' is PHASE_DONE in the log")
        if self.fails or man is None:
            return self.stop()
        bdir = self.backup_root / f"{self.ts}_fact_boundary_kml_pre_kankia"
        print(f"  plan: back up {BOUNDARY} to {bdir}, then overwrite from staging")
        if not self.a.execute:
            return print("  (dry-run) nothing written")
        bdir.mkdir(parents=True, exist_ok=True)
        live_p, src = self.live / BOUNDARY, STAGE / BOUNDARY
        bak = bdir / "FACT_LGA_boundaries_FACT.kml"
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
        print("  DONE: FACT boundary KML backed up and replaced, md5-verified")

    def workbook(self):
        print("== phase workbook: back up then replace the live FACT workbook with the staged one (includes Kankia) ==")
        self.staging_checks()
        self.live_state_checks(kankia_absent=False)
        self.need_flags()
        ref = xlsx_content(WB_SEED_REF) if WB_SEED_REF.is_file() else None
        live = self.live / WORKBOOK
        self.check(ref is not None and xlsx_content(live) == ref, "live FACT workbook is content-identical to the file the staged one was built over")
        if self.a.execute:
            self.check(self.phase_done("boundary"), "phase 'boundary' is PHASE_DONE in the log")
        if self.fails:
            return self.stop()
        bdir = self.backup_root / f"{self.ts}_fact_workbook_pre_kankia"
        print(f"  plan: back up the live FACT workbook to {bdir}, then copy the staged one over it")
        if not self.a.execute:
            return print("  (dry-run) nothing written")
        bdir.mkdir(parents=True, exist_ok=True)
        bak, src = bdir / live.name, WB_STAGE / WORKBOOK
        shutil.copy2(live, bak)
        good = md5(bak) == md5(live)
        self.log("workbook", "BACKUP", str(live), str(bak), md5(bak), good)
        if not good:
            return self.stop()
        shutil.copy2(src, live)
        good = xlsx_content(live) == xlsx_content(src)
        self.log("workbook", "SWAPPED", str(src), str(live), md5(live), good)
        if not good:
            return self.stop()
        self.log("workbook", "PHASE_DONE")
        print(f"  DONE: FACT workbook backed up and replaced (content-verified), md5 {md5(live)[:8]}")

    def imc_katsina_remove(self):
        print("== phase imc-katsina-remove: per-file manifest, verified backup of IMC/Katsina, THEN removal ==")
        man = self.staging_checks()
        self.live_state_checks(kankia_absent=False)
        self.need_flags()
        held = [rel(p, STAGE) for p in staged_files() if "/Katsina/Kankia/" in p.as_posix()
                and not ((self.live / "FACT" / p.relative_to(STAGE / "FACT")).is_file() and md5(lp(self.live / "FACT" / p.relative_to(STAGE / "FACT"))) == (man or {}).get(rel(p, STAGE)))]
        self.check(not held, f"live FACT holds all {EXPECT_KANKIA_FILES} Kankia files with matching md5 ({len(held)} missing/different)")
        self.check((self.live / BOUNDARY).is_file() and md5(self.live / BOUNDARY) == (man or {}).get(BOUNDARY), "live FACT boundary KML matches the manifest")
        wb_ok = (self.live / WORKBOOK).is_file() and xlsx_content(self.live / WORKBOOK) == xlsx_content(WB_STAGE / WORKBOOK)
        self.check(wb_ok, "live FACT workbook content equals the staged workbook (Kankia included)")
        if self.a.execute:
            self.check(all(self.phase_done(x) for x in ("fact", "boundary", "workbook")), "phases 'fact', 'boundary' and 'workbook' are all PHASE_DONE in the log")
        if self.fails or man is None:
            return self.stop()
        src = lp(self.live / "IMC" / "Katsina")
        dst_dir = self.backup_root / f"{self.ts}_imc_katsina_kankia_reassigned_to_FACT"
        dst = lp(dst_dir / "IMC_Katsina")
        print(f"  plan: manifest, then copy {plain(src)} -> {plain(dst)}, verify {EXPECT_IMC_KATSINA_FILES} files by path/size/md5, then remove {plain(src)}")
        if not self.a.execute:
            return print("  (dry-run) nothing copied or removed")
        files = sorted(p for p in src.rglob("*") if p.is_file())
        mpath = self.write_manifest_csv("R2_manifest_IMC_Katsina_BEFORE_REMOVAL.csv", [(rel(p, src), p) for p in files])
        shutil.copytree(src, dst)
        ok, n = self.verify_backup_csv(mpath, dst_dir / "IMC_Katsina", "R2_backup_verification_IMC_Katsina.csv")
        n_dst = sum(1 for p in dst.rglob("*") if p.is_file())
        good = ok and n == len(files) == n_dst == EXPECT_IMC_KATSINA_FILES
        self.log("imc-katsina-remove", "BACKUP_VERIFIED", plain(src), plain(dst), f"{n_dst} files", good)
        if not good:
            print(f"  FAIL backup verification. IMC/Katsina NOT removed.")
            return self.stop()
        rmtree_retry(src)
        gone = not src.exists()
        self.log("imc-katsina-remove", "REMOVED", plain(src), "", "", gone)
        if not gone:
            return self.stop()
        self.log("imc-katsina-remove", "PHASE_DONE")
        print(f"  DONE: backup verified ({n_dst} files) at {plain(dst)}; IMC/Katsina removed")

    def leftovers(self):
        print("== phase leftovers: per-file manifest, verified backup, THEN removal of ACF's and IMC's stale workbook + boundary KML (4 files) ==")
        self.live_state_checks(kankia_absent=False)
        self.need_flags()
        if self.a.execute:
            self.check(self.phase_done("imc-katsina-remove"), "phase 'imc-katsina-remove' is PHASE_DONE (IMC has nothing left to serve)")
        if self.fails:
            return self.stop()
        bdir = self.backup_root / f"{self.ts}_acf_imc_stale_workbook_and_boundary_kml_removed"
        print(f"  plan: back up {[f'{p}/{f}' for p, f in LEFTOVERS]} to {bdir}, verify, then remove them; keep accessibility reports, PDFs and master_log folders")
        if not self.a.execute:
            return print("  (dry-run) nothing copied or removed")
        entries = [(f"{p}/{f}", self.live / p / f) for p, f in LEFTOVERS]
        mpath = self.write_manifest_csv("R2_manifest_ACF_IMC_leftovers_BEFORE_REMOVAL.csv", entries)
        for label, src in entries:
            dst = bdir / label
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        ok, n = self.verify_backup_csv(mpath, bdir, "R2_backup_verification_ACF_IMC_leftovers.csv")
        self.log("leftovers", "BACKUP_VERIFIED", "4 files", plain(bdir), f"{n} files", ok and n == 4)
        if not (ok and n == 4):
            print("  FAIL backup verification. Nothing removed.")
            return self.stop()
        for label, src in entries:
            os.chmod(src, stat.S_IWRITE)
            os.remove(src)
            self.log("leftovers", "REMOVED", str(src), "", "", not src.exists())
            if src.exists():
                return self.stop()
        # what must still be there
        for part in ("ACF", "IMC"):
            here = {p.name for p in (self.live / part).iterdir() if p.is_file()}
            n_ml = sum(1 for p in (self.live / part / "master_log").rglob("*") if p.is_file()) if (self.live / part / "master_log").is_dir() else 0
            self.check(KEEP[part] <= here and n_ml == KEEP_MASTER_LOG[part], f"{part}: kept {sorted(KEEP[part])} + master_log x{n_ml}")
        if self.fails:
            return self.stop()
        self.log("leftovers", "PHASE_DONE")
        print(f"  DONE: 4 stale files backed up (verified) at {plain(bdir)} and removed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["manifest", "preflight", "fact", "boundary", "workbook", "imc-katsina-remove", "leftovers"])
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--jack-go", default="")
    ap.add_argument("--live-root", default=str(WS / "3. External coordination" / "NGA MSNA 2026 Package"))
    ap.add_argument("--backup-root", default=str(OUT / "_archive_partner_package_backups"))
    ap.add_argument("--log-dir", default=str(STAGE))
    ap.add_argument("--trace-dir", default=str(TRACE_DEFAULT))
    a = ap.parse_args()
    r = Run(a)
    print(("EXECUTE" if a.execute else "DRY-RUN"), "|", a.phase, "| live root:", a.live_root)
    {"manifest": r.manifest, "preflight": r.preflight, "fact": r.fact, "boundary": r.boundary, "workbook": r.workbook,
     "imc-katsina-remove": r.imc_katsina_remove, "leftovers": r.leftovers}[a.phase]()
    if r.fails:
        r.stop()
    print("\nno failed checks" if not a.execute else "\ndone")


if __name__ == "__main__":
    main()
