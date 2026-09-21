# ==============================================================================
# 2026-09-21 late evening, Jack: redraw for Street Child (two Madagali wards
# flipped: Gulak -> inaccessible, Madagali -> accessible) and NRC (14 Non-IDP
# clusters newly reported inaccessible, 21 Sep report), frame first, packages
# later. Staging only - same chain as stage_second_round_2026-09-21.py
# (extract -> scope filter -> draw -> ward-status stamp -> post-draw MoE
# projection), now on the fixed Non-IDP draw (Stage B2/F, commit 4f36532).
#
# Scope is self-derived from the REBUILT record (after run_accessibility_
# refresh.py + the WORKING refresh): every stratum covered by one of these
# two partners that 05 now calls "Indicative now - RECOVERABLE via
# supplementary draw". Negligible-gap and not-recoverable strata are listed
# for the record but not drawn (same scope rule as tonight's second round).
# One batch label for both partners - Coordinator's round-landing guard
# groups a round by its shared folder label.
# Usage: python stage_ward_flips_2026-09-21.py
# ==============================================================================
import csv
import os
import re
import subprocess
import sys
from collections import defaultdict

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
SCRIPTS = os.path.join(PROJECT_DIR, "resampling", "scripts")
RUNS = os.path.join(PROJECT_DIR, "resampling", "output", "resample_runs")
REPR_CSV = os.path.join(PROJECT_DIR, "resampling", "output", "strata_representativity_status.csv")
RSCRIPT = r"C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\Rscript.exe"
BATCH = "2026-09-21_ward_flips"
SEED = "2026092105"
PARTNERS = ["Street Child of Nigeria", "NRC"]
SCOPE_VERDICT = "Indicative now - RECOVERABLE via supplementary draw"


def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "_", p).lower()


def run(cmd, log_path, cwd=PROJECT_DIR):
    with open(log_path, "w", encoding="utf-8") as out:
        return subprocess.run(cmd, cwd=cwd, stdout=out, stderr=subprocess.STDOUT).returncode


def read_rows(p):
    if not os.path.exists(p):
        return [], None
    with open(p, encoding="utf-8", newline="") as f:
        r = csv.DictReader(f)
        return list(r), r.fieldnames


def write_rows(p, rows, fields):
    with open(p, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    with open(REPR_CSV, encoding="utf-8-sig") as f:
        rep = list(csv.DictReader(f))
    vcol = [k for k in rep[0] if k.startswith("Representativity (")][0]
    mcol = [k for k in rep[0] if "DRIVES the verdict" in k][0]
    scope = defaultdict(list)
    print("Current verdicts for every stratum these partners cover that is not Representative:")
    for r in rep:
        ps = [p.strip() for p in r["Partners covering"].split(",")]
        mine = [p for p in ps if p in PARTNERS]
        if not mine or r[vcol].startswith("Representative"):
            continue
        # Same scope as the morning round (Jack's 2026-09-21 rule): closeable
        # strata, plus "exceeds remaining pool" strata drawn for whatever the
        # pool can deliver; "no remaining pool" strata skipped. Added after the
        # rebuilt record showed Street Child's only affected stratum (Madagali
        # Non-IDP, 10.12 -> 18.76 after Gulak) is exceeds-pool, not closeable.
        drawn = r[vcol] == SCOPE_VERDICT or r["Feasibility"].startswith("Not closeable - exceeds remaining pool")
        print(f"  {'DRAW ' if drawn else '     '}{r['LGA']} {r['Pop type']} ({r['Partners covering']}): {r[mcol]}% - {r[vcol][:60]}")
        if drawn:
            if len(ps) != 1:
                sys.exit(f"STOP: {r['Strata ID']} is covered by {ps} - dual coverage needs an owner decision first.")
            scope[mine[0]].append(r["Strata ID"])
    if not scope:
        print("\nNothing draw-recoverable for these partners - no draw needed.")
        return

    for p, sids in sorted(scope.items()):
        d = os.path.join(RUNS, p, BATCH)
        os.makedirs(d, exist_ok=True)
        if run([RSCRIPT, os.path.join(SCRIPTS, "extract_partner_shortfalls.R"), p, d], os.path.join(d, "extract_log.txt")) != 0:
            sys.exit(f"[{p}] extract failed")
        kept_by_kind = {}
        for kind in ("", "_idp"):
            fn = os.path.join(d, f"{slug(p)}_shortfalls{kind}.csv")
            rows, fields = read_rows(fn)
            write_rows(fn.replace(".csv", "_ALL_unfiltered.csv"), rows, fields)
            kept = [r for r in rows if r["strata_id"] in sids]
            write_rows(fn, kept, fields)
            kept_by_kind[kind] = (fn, kept)
        missing = set(sids) - {r["strata_id"] for k in kept_by_kind.values() for r in k[1]}
        if missing:
            sys.exit(f"[{p}] STOP: scope strata missing from the extract: {sorted(missing)}")
        for kind, (fn, kept) in kept_by_kind.items():
            if not kept:
                continue
            need = sum(int(float(r["additional_clusters_needed"])) for r in kept)
            print(f"\n===== {p}: {len(kept)} {'IDP' if kind else 'Non-IDP'} strata, {need} clusters =====", flush=True)
            script, hh_name, log = (("draw_supplementary_idp_sites_batch.R", "new_households_idp_sitelevel.csv", "draw_idp_run_log.txt") if kind
                                    else ("draw_supplementary_clusters_batch.R", "new_households.csv", "draw_non_idp_run_log.txt"))
            rc = run([RSCRIPT, os.path.join(SCRIPTS, script), fn, d, SEED], os.path.join(d, log))
            print(f"[{p}] draw rc={rc}", flush=True)
            hh = os.path.join(d, hh_name)
            if rc == 0 and os.path.exists(hh) and os.path.getsize(hh) > 0:
                rc2 = run([sys.executable, os.path.join(SCRIPTS, "stamp_ward_accessible_status.py"), hh],
                          os.path.join(d, f"stamp{kind or '_non_idp'}_log.txt"), cwd=SCRIPTS)
                print(f"[{p}] stamp rc={rc2}", flush=True)
        proj = subprocess.run([sys.executable, os.path.join(SCRIPTS, "one_off_analyses", "project_post_draw_moe_2026-09-21.py"), p, d],
                              cwd=PROJECT_DIR, capture_output=True, text=True)
        print(proj.stdout.strip() or proj.stderr.strip(), flush=True)
    print("\nWARD-FLIPS ROUND STAGED - nothing merged.")


if __name__ == "__main__":
    main()
