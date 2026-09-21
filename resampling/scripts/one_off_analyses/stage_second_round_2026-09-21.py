# ==============================================================================
# 2026-09-21 SECOND resampling round (evening), staging only. Jack's own word:
# "yes, run the draw for all" - every stratum the representativity record
# currently calls "Indicative now - RECOVERABLE via supplementary draw" (13,
# all Non-IDP), including the three this morning's round under-delivered on
# (Kala/Balge, Ngala, Monguno - Non-IDP pool is a hex count, not building-
# validated). Same chain as stage_small_partners_2026-09-21.py: extract ->
# scope filter -> Non-IDP draw -> ward-status stamp -> post-draw MoE
# projection, one partner at a time. Nothing here merges.
#
# Scope is self-derived from strata_representativity_status.csv, not a
# hardcoded list, and asserted against the 13 Jack approved so a changed
# record can't silently widen or shrink the round. Clusters drawn = 05's own
# "Additional clusters needed" - no hidden buffer for expected duds (this
# morning 16 of 64 new clusters in these strata had < 4 accessible primaries
# at staging; the rebuilt 05 will show whatever gap remains).
#
# Run only when nothing else is reading/writing the FULL frame.
# Usage: python stage_second_round_2026-09-21.py
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
BATCH = "2026-09-21_second_round"
SEED = "2026092102"
SCOPE_VERDICT = "Indicative now - RECOVERABLE via supplementary draw"
EXPECTED_N_STRATA, EXPECTED_N_CLUSTERS = 13, 44   # what Jack approved on the review page


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
    scope = {r["Strata ID"]: r for r in rep if r[vcol] == SCOPE_VERDICT}
    n_clusters = sum(int(float(r["Additional clusters needed"])) for r in scope.values())
    if len(scope) != EXPECTED_N_STRATA or n_clusters != EXPECTED_N_CLUSTERS:
        sys.exit(f"STOP: record now has {len(scope)} draw-recoverable strata / {n_clusters} clusters, "
                 f"not the {EXPECTED_N_STRATA} / {EXPECTED_N_CLUSTERS} Jack approved - nothing drawn.")
    if any(r["Pop type"] != "Non-IDP" for r in scope.values()):
        sys.exit("STOP: an IDP stratum is in scope - this script only runs the Non-IDP draw.")
    partners = defaultdict(list)
    for sid, r in scope.items():
        ps = [p.strip() for p in r["Partners covering"].split(",")]
        if len(ps) != 1:
            sys.exit(f"STOP: {sid} is covered by {ps} - dual coverage needs an owner decision first.")
        partners[ps[0]].append(sid)
    print(f"Scope: {len(scope)} strata, {n_clusters} clusters, {len(partners)} partners")

    for p, sids in sorted(partners.items()):
        d = os.path.join(RUNS, p, BATCH)
        os.makedirs(d, exist_ok=True)
        rc = run([RSCRIPT, os.path.join(SCRIPTS, "extract_partner_shortfalls.R"), p, d], os.path.join(d, "extract_log.txt"))
        if rc != 0:
            sys.exit(f"[{p}] extract failed rc={rc} - see {d}\\extract_log.txt")
        fn, fn_idp = os.path.join(d, f"{slug(p)}_shortfalls.csv"), os.path.join(d, f"{slug(p)}_shortfalls_idp.csv")
        rows, fields = read_rows(fn)
        write_rows(fn.replace(".csv", "_ALL_unfiltered.csv"), rows, fields)
        kept = [r for r in rows if r["strata_id"] in sids]
        missing = set(sids) - {r["strata_id"] for r in kept}
        if missing:
            sys.exit(f"[{p}] STOP: scope strata missing from the extract: {sorted(missing)}")
        write_rows(fn, kept, fields)
        idp_rows, idp_fields = read_rows(fn_idp)
        write_rows(fn_idp.replace(".csv", "_ALL_unfiltered.csv"), idp_rows, idp_fields)
        write_rows(fn_idp, [], idp_fields)   # nothing IDP in scope; the merge still needs the file
        need = sum(int(float(r["additional_clusters_needed"])) for r in kept)
        print(f"\n===== {p}: {len(kept)} Non-IDP strata, {need} clusters =====", flush=True)

        rc = run([RSCRIPT, os.path.join(SCRIPTS, "draw_supplementary_clusters_batch.R"), fn, d, SEED],
                 os.path.join(d, "draw_non_idp_run_log.txt"))
        print(f"[{p}] Non-IDP draw rc={rc}", flush=True)
        hh = os.path.join(d, "new_households.csv")
        if rc == 0 and os.path.exists(hh) and os.path.getsize(hh) > 0:
            rc2 = run([sys.executable, os.path.join(SCRIPTS, "stamp_ward_accessible_status.py"), hh],
                      os.path.join(d, "stamp_non_idp_log.txt"), cwd=SCRIPTS)
            print(f"[{p}] stamp rc={rc2}", flush=True)
        proj = subprocess.run([sys.executable, os.path.join(SCRIPTS, "one_off_analyses", "project_post_draw_moe_2026-09-21.py"), p, d],
                              cwd=PROJECT_DIR, capture_output=True, text=True)
        print(proj.stdout.strip() or proj.stderr.strip(), flush=True)

    print("\nSECOND ROUND STAGED - nothing merged.")


if __name__ == "__main__":
    main()
