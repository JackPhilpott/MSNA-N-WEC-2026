"""Extract, from the final Round 1 dataset (v5), the household keys the analysis weights on plus the FSL composite
indicators, for the #44 impact check (build_round1_estimate_impact_dtm_2026-10-13.py). Read only on v5.
Writes ONE household-level file to a LOCAL temp folder outside OneDrive (no GPS, no names, no free text):
  %TEMP%\\r1dtm\\v5_keys_fsl.csv
Usage: py extract_v5_keys_and_fsl_2026-10-13.py"""
import csv, hashlib, os, re, sys, time
import openpyxl

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
V5 = os.path.join(WS, "2_monitoring", "cleaning", "NGA2605_MSNA_UNHCR_Combined_Cleaning", "output", "final",
                  "IMPACT_NGA_Dataset_MSNA-UNHCR-2026-Round1_08102026_v5.xlsx")
V5_MD5 = "02fa3d2cf4db5e5c8203cabdd07e0dc4"
OUT_DIR = os.path.join(os.environ["TEMP"], "r1dtm")
KEYS = ["uuid", "assessment", "admin1", "admin1_name", "admin2", "admin2_name", "pop_group", "pop_type", "population_type", "strata_id", "setting"]
FSL = re.compile(r"^fsl_(fcs_(score|cat)|rcsi_(score|cat)|hhs_(score|cat|cat_ipc|comp)|lcsi_(cat|cat_yes|cat_exhaust)|fc_(cell|phase)|fews|cari)", re.I)
BANNED = re.compile(r"gps|latitude|longitude|_lat$|_lon$|geopoint|name_|phone|sample_point", re.I)

t0 = time.time()
h = hashlib.md5()
with open(V5, "rb") as f:
    for b in iter(lambda: f.read(1 << 22), b""):
        h.update(b)
if h.hexdigest() != V5_MD5:
    sys.exit("STOPPED: v5 md5 %s, expected %s" % (h.hexdigest(), V5_MD5))
wb = openpyxl.load_workbook(V5, read_only=True)
ws = wb["hh_clean_data"]
ws.reset_dimensions()
it = ws.iter_rows(values_only=True)
hdr = [str(x) if x is not None else "" for x in next(it)]
fsl_cols = [c for c in hdr if c.lower().startswith("fsl_")]
print("all fsl_ columns (%d):" % len(fsl_cols), fsl_cols)
want = [c for c in KEYS if c in hdr] + [c for c in hdr if FSL.match(c)]
missing = [c for c in KEYS if c not in hdr]
print("keys missing from v5:", missing or "none")
assert not any(BANNED.search(c) for c in want), [c for c in want if BANNED.search(c)]
idx = [hdr.index(c) for c in want]
os.makedirs(OUT_DIR, exist_ok=True)
out = os.path.join(OUT_DIR, "v5_keys_fsl.csv")
n = 0
with open(out, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(want)
    for row in it:
        if row is None or all(v is None for v in row):
            continue
        w.writerow(["" if row[i] is None else row[i] for i in idx])
        n += 1
print("rows %d | columns %s | %s | %.0fs" % (n, want, out, time.time() - t0))
assert n == 24095, n
