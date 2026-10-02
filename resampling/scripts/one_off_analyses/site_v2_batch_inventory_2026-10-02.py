# ==============================================================================
# 2026-10-02 READ-ONLY (Coordinator request, for the Option 3 IDP weights):
# inventory of every site-level (site_v2) IDP draw batch under resample_runs.
# For each staged new_clusters_idp_sitelevel.csv: batch time (from the draw's
# own run log, never file mtime), per-stratum k (n_drawn_this_stratum), the
# staged clusters, and merge evidence (is each staged cluster_id live in FULL
# with the SAME site - cluster ids get reused, so id alone is not enough).
# Writes site_v2_batch_inventory_2026-10-02.csv; touches nothing else.
# ==============================================================================
import csv
import glob
import os
import re
from collections import defaultdict

S = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
RR = S + r"\resampling\output\resample_runs"
FULL = S + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"
OUT = S + r"\resampling\output\full_weighting_build_2026-09-28\site_v2_batch_inventory_2026-10-02.csv"

live = {}
with open(FULL, encoding="utf-8-sig", newline="") as f:
    for r in csv.DictReader(f):
        if r["pop_type"] == "idp" and r["cluster_id"] not in live:
            live[r["cluster_id"]] = (r["psu_definition_version"], r["uuid_hex"], r["strata_id"])


def batch_time(d):
    for lg in ("run_log_idp_sitelevel.txt", "draw_idp_run_log.txt", "run_log_idp.txt"):
        p = os.path.join(d, lg)
        if os.path.exists(p):
            with open(p, encoding="utf-8", errors="replace") as f:
                head = f.read(600)
            if "Site-level" in head or lg == "run_log_idp_sitelevel.txt":
                m = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", head)
                if m:
                    return m.group(1), lg
    m = re.match(r"(\d{4}-\d{2}-\d{2})", os.path.basename(d))
    return (m.group(1) + " 00:00:00", "folder_date") if m else ("", "none")


def merge_site_v2_count(d):
    out = []
    for p in glob.glob(os.path.join(d, "merge*log*.txt")):
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.search(r"(\d+) new IDP cluster\(s\) \[site_v2\]", line)
                if m:
                    out.append(int(m.group(1)))
    return max(out) if out else None


rows = []
for p in sorted(glob.glob(RR + r"\*\*\new_clusters_idp_sitelevel.csv")):
    d = os.path.dirname(p)
    with open(p, encoding="utf-8-sig", newline="") as f:
        staged = list(csv.DictReader(f))
    if not staged:
        continue
    t, src = batch_time(d)
    merged_n = merge_site_v2_count(d)
    by_stratum = defaultdict(list)
    for r in staged:
        by_stratum[r["strata_id"]].append(r)
    for sid, rs in by_stratum.items():
        ks = {r.get("n_drawn_this_stratum") for r in rs}
        live_match = sum(1 for r in rs if live.get(r["cluster_id"], ("", "", ""))[1] == r.get("uuid_site") and live[r["cluster_id"]][0] == "site_v2")
        rows.append({
            "batch": os.path.relpath(d, RR).replace("\\", "/"), "batch_time": t, "time_source": src,
            "strata_id": sid, "adm2_pcode": rs[0].get("adm2_pcode"),
            "k_n_drawn_this_stratum": ";".join(sorted(k for k in ks if k)),
            "staged_clusters": len(rs), "staged_selection_count_sum": sum(int(float(r.get("selection_count") or 1)) for r in rs),
            "staged_live_same_site": live_match,
            "merge_log_site_v2_clusters": "" if merged_n is None else merged_n,
            "cluster_ids": "|".join(r["cluster_id"] for r in rs),
            "uuid_sites": "|".join(r.get("uuid_site", "") for r in rs),
        })

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(sorted(rows, key=lambda r: (r["batch_time"], r["batch"], r["strata_id"])))

batches = sorted({(r["batch_time"], r["batch"]) for r in rows})
print(f"site_v2 staged batches (non-empty): {len(batches)}; batch x stratum rows: {len(rows)}")
print("time sources:", dict(sorted({r['time_source']: 0 for r in rows}.items())))
live_v2 = sum(1 for v in live.values() if v[0] == "site_v2")
claimed = set()
for r in rows:
    for c, u in zip(r["cluster_ids"].split("|"), r["uuid_sites"].split("|")):
        if live.get(c, ("", "", ""))[1] == u and live[c][0] == "site_v2":
            claimed.add(c)
print(f"live site_v2 clusters: {live_v2}; matched to a staged batch by id+site: {len(claimed)}; unmatched: {live_v2 - len(claimed)}")
dupe = defaultdict(list)
for r in rows:
    for c, u in zip(r["cluster_ids"].split("|"), r["uuid_sites"].split("|")):
        dupe[(c, u)].append(r["batch"])
multi = {k: v for k, v in dupe.items() if len(set(v)) > 1 and live.get(k[0], ("", "", ""))[1] == k[1]}
print(f"live clusters staged (same id+site) in >1 batch folder: {len(multi)}")
for k, v in list(multi.items())[:8]:
    print("  ", k[0], sorted(set(v)))
print("wrote", OUT)
