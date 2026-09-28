# ==============================================================================
# Swap the freshly built FACT / IMC / ZOA partner workbooks (staged 2026-09-25 on the 25 Sep pull) over the live ones.
# DRY-RUN BY DEFAULT. --execute needs --jack-go "<recorded go>" and only ever touches the three live workbooks named below.
#   preflight  read-only: staged files exist and match STAGED_WORKBOOKS_MD5.txt; each LIVE workbook still has the md5 it had when the
#              staged copy was seeded from it (SEEDED_live_copies_md5.txt), i.e. nobody has saved or replaced it since
#   manifest   write STAGED_WORKBOOKS_MD5.txt (staging only)
#   swap       back up the 3 live workbooks (verified), copy the staged ones over them, md5-verify each
# Not touched: ACF's workbook (ACF has no LGA any more; its stale file is an open item), any other partner's workbook.
# Rollback: copy the three files back from the backup folder named in the log.
# ==============================================================================
import argparse, csv, hashlib, shutil, sys
from datetime import datetime
from pathlib import Path

WS = Path(r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA")
SAMPLING = WS / "4. Data" / "MSNA N-WEC 2026" / "1_sampling"
STAGE = SAMPLING / "resampling" / "output" / "staged_workbooks_2026-09-25_fact_imc_zoa"
MANIFEST = STAGE / "STAGED_WORKBOOKS_MD5.txt"
SEEDED = STAGE / "SEEDED_live_copies_md5.txt"
PARTNERS = ["FACT", "IMC", "ZOA"]


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def wb(root, p):
    return Path(root) / p / f"{p}_sampling_points_summary.xlsx"


def read_md5_file(path):
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            h, r = line.replace("*", " ").split(None, 1)
            out[r.strip().replace("\\", "/")] = h
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["manifest", "preflight", "swap"])
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--jack-go", default="")
    ap.add_argument("--live-root", default=str(WS / "3. External coordination" / "NGA MSNA 2026 Package"))
    ap.add_argument("--backup-root", default=str(SAMPLING / "resampling" / "output" / "_archive_partner_package_backups"))
    ap.add_argument("--log-dir", default=str(STAGE))
    a = ap.parse_args()
    fails = []

    def check(ok, msg):
        print(("  PASS  " if ok else "  FAIL  ") + msg)
        if not ok:
            fails.append(msg)
        return ok

    print(("EXECUTE" if a.execute else "DRY-RUN"), "|", a.phase)
    if a.phase == "manifest":
        lines = [f"{md5(wb(STAGE, p))}  {p}/{p}_sampling_points_summary.xlsx" for p in PARTNERS]
        print("\n".join(lines))
        if a.execute:
            MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print("wrote", MANIFEST)
        return
    man = read_md5_file(MANIFEST) if MANIFEST.exists() else None
    seeded = read_md5_file(SEEDED) if SEEDED.exists() else None
    check(man is not None, "STAGED_WORKBOOKS_MD5.txt present (run 'manifest --execute' first if not)")
    check(seeded is not None, "SEEDED_live_copies_md5.txt present")
    for p in PARTNERS:
        key = f"{p}/{p}_sampling_points_summary.xlsx"
        s, l = wb(STAGE, p), wb(a.live_root, p)
        check(s.is_file() and man is not None and md5(s) == man.get(key), f"staged {p} workbook matches the manifest")
        check(l.is_file() and seeded is not None and md5(l) == seeded.get(key),
              f"live {p} workbook is still exactly the file the staged one was built from (nobody saved over it since)")
    check(Path(a.backup_root).is_dir(), f"backup root exists: {a.backup_root}")
    if a.phase == "preflight" or fails:
        if fails:
            print("\nSTOPPED, nothing was done:")
            [print("  -", m) for m in fails]
            sys.exit(1)
        return print("\nno failed checks")
    # ---- swap ----
    if a.execute and not a.jack_go.strip():
        print("  FAIL  --jack-go required with --execute"); sys.exit(1)
    bdir = Path(a.backup_root) / f"{datetime.now():%Y%m%d_%H%M%S}_workbooks_fact_imc_zoa_pre_swap"
    print(f"  plan: back up the 3 live workbooks to {bdir}, then copy the staged ones over them")
    if not a.execute:
        return print("  (dry-run) nothing written")
    log = Path(a.log_dir) / "handover_workbooks_execution_log.csv"
    new = not log.exists()
    with open(log, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["timestamp", "partner", "action", "md5", "ok", "jack_go"])
        for p in PARTNERS:
            l, s = wb(a.live_root, p), wb(STAGE, p)
            bak = bdir / p / l.name
            bak.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(l, bak)
            ok = md5(bak) == md5(l)
            w.writerow([datetime.now().isoformat(timespec="seconds"), p, "BACKUP", md5(bak), ok, a.jack_go])
            if not ok:
                print(f"  FAIL backup of {p}; nothing swapped for it or after"); sys.exit(1)
            shutil.copy2(s, l)
            ok = md5(l) == md5(s)
            w.writerow([datetime.now().isoformat(timespec="seconds"), p, "SWAPPED", md5(l), ok, a.jack_go])
            print(f"  {p}: backed up and swapped, md5 {md5(l)[:8]} {'OK' if ok else 'MISMATCH'}")
            if not ok:
                sys.exit(1)
    print("  DONE")


if __name__ == "__main__":
    main()
