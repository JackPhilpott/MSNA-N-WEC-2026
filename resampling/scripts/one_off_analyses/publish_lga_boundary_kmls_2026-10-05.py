# ==============================================================================
# 2026-10-05: publishes the 4 rebuilt LGA_boundaries_<P>.kml (CARE, FACT, Malteser, ZOA) from the verified staging
# build (build_partner_lga_boundary_kml.R with BUILD_DC_OUT_ROOT; diff verified by Resampling and the Coordinator)
# into the synced package root. Partner-facing: run with --execute ONLY on Jack's word in Resampling's window.
# Per file: the live file moves to <Partner>/_archived_superseded_2026-10-05/ (nothing deleted), the staged file is
# copied in, md5 checked. Pre-checks (all or nothing): staged and live md5s are the verified ones, no archive copy yet.
# Not touched: IRC/LHI (staged files would re-mark the excluded Isa/Sabon Birni) and the 8 byte-identical partners.
# The orchestrator neither builds nor tracks these files (not in last_published_manifest.csv), so a daily run
# leaves them alone. --rollback puts the archived files back.
# Usage (from 1_sampling): python publish_lga_boundary_kmls_2026-10-05.py [--execute | --rollback]
# ==============================================================================
import argparse
import datetime
import hashlib
import os
import shutil
import sys


def _pkg_root():  # MSNA_PKG_ROOT, else the 02. MSNA package path (the separate 4 Oct sync folder is retired by the 5 Oct re-link)
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "scripts", "shared"))
    import msna_paths
    return msna_paths.pkg_root()

S1 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
STAGING = os.path.join(S1, "resampling", "output", "lga_boundary_kml_staging_2026-10-05", "staging")
ROOT = None  # resolved in main() via _pkg_root()
ARCH = "_archived_superseded_2026-10-05"
# partner: (verified staged md5, verified live md5 at staging time)
FILES = {"CARE": ("8b3fccc56c6a53d83588d6c43a43df34", "e06676d9"), "FACT": ("d4b2271313346852ce1f3cdb7b9cc2f2", "920407ee"),
         "Malteser": ("0905718877a80a2db6db54db9165a2c7", "b26f8a23"), "ZOA": ("9f90ccc7fa26ba2ba17a65d0e7bcecd8", "4c46a2c6")}


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def paths(p):
    name = f"LGA_boundaries_{p}.kml"
    return os.path.join(STAGING, p, name), os.path.join(ROOT, p, name), os.path.join(ROOT, p, ARCH, name)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--execute", action="store_true")
    g.add_argument("--rollback", action="store_true")
    a = ap.parse_args()
    global ROOT
    ROOT = _pkg_root()
    if a.rollback:
        for p in FILES:
            _, live, arch = paths(p)
            if os.path.isfile(arch):
                os.replace(arch, live)
                print(f"rolled back {p}: {md5(live)[:8]}")
        return
    problems = []
    for p, (staged_md5, live8) in FILES.items():
        staged, live, arch = paths(p)
        if not os.path.isfile(staged) or md5(staged) != staged_md5:
            problems.append(f"{p}: staged file missing or not the verified one")
        if not os.path.isfile(live) or md5(live)[:8] != live8:
            problems.append(f"{p}: live file missing or changed since verification ({md5(live)[:8] if os.path.isfile(live) else 'missing'} vs {live8})")
        if os.path.exists(arch):
            problems.append(f"{p}: {arch} already exists")
    print(f"PUBLISH {len(FILES)} LGA boundary KML(s) into {ROOT}: pre-checks {'PASS' if not problems else 'FAIL'}")
    for x in problems:
        print("  " + x)
    if problems:
        sys.exit("STOP: nothing published")
    if not a.execute:
        print("DRY RUN - nothing published (add --execute, on Jack's word only)")
        return
    for p, (staged_md5, _) in FILES.items():
        staged, live, arch = paths(p)
        os.makedirs(os.path.dirname(arch), exist_ok=True)
        os.replace(live, arch)
        shutil.copy2(staged, live)
        ok = md5(live) == staged_md5
        print(f"{datetime.datetime.now():%H:%M:%S} {p}: old -> {ARCH}/, new {md5(live)[:8]} {'OK' if ok else 'MD5 MISMATCH'}")
        if not ok:
            sys.exit("STOP: md5 mismatch after copy - run --rollback")
    print("published 4 of 4")


if __name__ == "__main__":
    main()
