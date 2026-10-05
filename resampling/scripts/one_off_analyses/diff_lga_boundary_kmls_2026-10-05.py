# ==============================================================================
# 2026-10-05 READ-ONLY: compares partners' LGA_boundaries_<P>.kml (build_partner_lga_boundary_kml.R) in three places,
# by covered LGA (placemarks styled #lgaCoveredStyle):
#   staged  - a BUILD_DC_OUT_ROOT staging build (after the 4 Oct reallocation, Partnerscoverage.xlsx 22:49)
#   live    - what partners have now in the synced package root (rebuilt last on 25 Sep / 19 Aug)
#   frame   - the live strata FULL frame: partners_covering of covered, not-excluded strata (either population)
# LGAs are matched on (state, normalised name). Writes <staging>/../lga_boundary_kml_diff.csv and prints a summary.
# Usage: python diff_lga_boundary_kmls_2026-10-05.py <staging root> [<live root>]
# ==============================================================================
import csv
import glob
import os
import re
import sys
from collections import defaultdict


def _pkg_root():  # MSNA_PKG_ROOT, else the 02. MSNA package path (the separate 4 Oct sync folder is retired by the 5 Oct re-link)
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "scripts", "shared"))
    import msna_paths
    return msna_paths.pkg_root()

S1 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PLACEMARK = re.compile(r"<Placemark[^>]*>\s*<name>(.*?)</name>\s*<description>State: (.*?)&#10;.*?</description>\s*"
                       r"<styleUrl>#(lgaCoveredStyle|lgaContextStyle)</styleUrl>", re.S)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower().replace("&amp;", "&"))


def covered(path):
    if not os.path.isfile(path):
        return None
    t = open(path, encoding="utf-8", errors="replace").read()
    return {(norm(st), norm(n)): f"{st}/{n}" for n, st, style in PLACEMARK.findall(t) if style == "lgaCoveredStyle"}


def main():
    staging = sys.argv[1]
    live = sys.argv[2] if len(sys.argv) > 2 else _pkg_root()
    frame = defaultdict(dict)
    with open(os.path.join(S1, "output", "data", "data_collection", "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv"),
              encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if r["coverage_status"] != "covered" or r["exclusion_reason"] not in ("none", "", "NA"):
                continue
            for p in (x.strip() for x in r["partners_covering"].split(",")):
                if p:
                    frame[p][(norm(r["adm1_name"]), norm(r["adm2_name"]))] = f"{r['adm1_name']}/{r['adm2_name']}"
    partners = sorted({os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(staging, "*", "LGA_boundaries_*.kml"))} | set(frame))
    rows = []
    for p in partners:
        st = covered(os.path.join(staging, p, f"LGA_boundaries_{p}.kml"))
        lv = covered(os.path.join(live, p, f"LGA_boundaries_{p}.kml"))
        fr = frame.get(p, {})
        s, l = set(st or {}), set(lv or {})
        names = {**(lv or {}), **(st or {}), **fr}
        row = {"partner": p, "staged_file": st is not None, "live_file": lv is not None, "n_staged": len(s), "n_live": len(l), "n_frame": len(fr),
               "added_vs_live": "; ".join(sorted(names[k] for k in s - l)), "removed_vs_live": "; ".join(sorted(names[k] for k in l - s)),
               "frame_not_in_staged": "; ".join(sorted(names[k] for k in set(fr) - s)),
               "staged_not_in_frame": "; ".join(sorted(names[k] for k in s - set(fr)))}
        rows.append(row)
    out = os.path.join(os.path.dirname(os.path.normpath(staging)), "lga_boundary_kml_diff.csv")
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    for r in rows:
        changed = r["added_vs_live"] or r["removed_vs_live"] or r["staged_file"] != r["live_file"]
        print(f"{r['partner'][:24]:24} staged {r['n_staged']:>3} | live {r['n_live']:>3}{'' if r['live_file'] else ' (no file)'} | frame {r['n_frame']:>3}"
              f"{' | CHANGES' if changed else ''}{' | MISMATCH vs frame' if r['frame_not_in_staged'] or r['staged_not_in_frame'] else ''}")
        for k in ("added_vs_live", "removed_vs_live", "frame_not_in_staged", "staged_not_in_frame"):
            if r[k]:
                print(f"    {k}: {r[k][:300]}")
    print(f"written {out}")


if __name__ == "__main__":
    main()
