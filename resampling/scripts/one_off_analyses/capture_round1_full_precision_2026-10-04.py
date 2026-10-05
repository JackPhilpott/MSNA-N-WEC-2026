# Re-runs the verified Round 1 representativity build (build_round1_representativity_prototype_2026-10-02.py), UNCHANGED,
# on the DO-aligned candidate snapshot, and captures its full-precision stratum values (N_hh, N_acc, variance), which its
# CSVs round. The capture is saved only if the re-run's tables are byte-identical to the candidate's verified tables.
# Used by build_round1_ipc_ch_workbook_2026-10-04.py. Writes only under the IPC/CH report's _build_intermediate folder.
import csv, hashlib, importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
BUILD = os.path.join(HERE, "build_round1_representativity_prototype_2026-10-02.py")
CAND = os.path.join(WS, "1_sampling", "resampling", "output", "round1_candidate_aligned_to_DO_clean_2026-10-04")
SNAP = os.path.join(CAND, "snapshot")
OUT = os.path.join(WS, "2_monitoring", "reports", "round1_ipc_ch_representativity_2026-10-04", "_build_intermediate")
RERUN = os.path.join(OUT, "rerun_round1_tables")
os.makedirs(RERUN, exist_ok=True)

def md5(p):
    with open(p, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

captured = []
RealDictWriter = csv.DictWriter

class CaptureDictWriter(RealDictWriter):
    def writerows(self, rows):
        rows = list(rows)
        if rows and "_N_acc" in rows[0]:
            captured.extend(rows)
        return super().writerows(rows)

csv.DictWriter = CaptureDictWriter
try:
    sys.argv = [BUILD, SNAP, RERUN]
    spec = importlib.util.spec_from_file_location("r1proto", BUILD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.main()
finally:
    csv.DictWriter = RealDictWriter

ok = True
for name in ("round1_strata.csv", "round1_lga.csv", "round1_state.csv"):
    a, b = md5(os.path.join(RERUN, name)), md5(os.path.join(CAND, "representativity", name))
    print("%-18s re-run %s | candidate %s | %s" % (name, a, b, "IDENTICAL" if a == b else "DIFFERENT"))
    ok = ok and a == b
if not ok:
    print("STOPPED: the re-run does not reproduce the candidate's verified tables; capture NOT saved.")
    sys.exit(1)
cols = ["strata_id", "State", "LGA", "Pop type", "Achieved (Round 1)", "Round 1 label", "Round 1 reason", "_N_hh", "_N_acc", "_var"]
with open(os.path.join(OUT, "full_precision_strata.csv"), "w", encoding="utf-8", newline="") as f:
    w = RealDictWriter(f, fieldnames=cols + ["Z"])
    w.writeheader()
    for r in captured:
        row = {c: (repr(r[c]) if c.startswith("_") and r[c] is not None else r[c]) for c in cols}
        row["Z"] = repr(mod.Z)
        w.writerow(row)
print("captured %d strata at full precision -> %s (Z = %r)" % (len(captured), os.path.join(OUT, "full_precision_strata.csv"), mod.Z))
