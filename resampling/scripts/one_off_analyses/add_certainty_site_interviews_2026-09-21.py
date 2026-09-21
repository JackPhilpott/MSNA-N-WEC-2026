# ==============================================================================
# 2026-09-21 evening, Jack's direct instruction ("don't need to ask, already
# go ahead and draw"): put the extra interviews at certainty sites into the
# frame, so they reach partners through the normal packages instead of a
# separate request.
#
# The route (05's certainty_site_topup_needed(), accepted by Jack the same
# night): a certainty site is its own stratum under the verdict formula, so
# k more interviews at ONE existing, accessible certainty site - everything
# else held - bring the stratum to <= 10% MoE. 05 models that as the
# cluster's achievable ceiling rising by exactly k. So each cluster's target
# becomes (current ceiling + k), using 05's own ceiling rule (max(accessible
# primaries, achieved) for completed / partially_completed_access_lost,
# accessible primaries otherwise). New primary rows HH<n> are copies of the
# cluster's HH01 row, and new reserve rows R<n> copies of R01, keeping the
# cluster's 1:1 reserve ratio. target_households / reserve_households are
# raised on every row of the cluster. A NEW cluster at the same site would
# NOT do this: 05 would treat it as an ordinary sampled PSU, not part of the
# certainty unit.
#
# Self-derived from 05's own Feasibility labels in the representativity
# record, then asserted against the four routes Jack approved (so a changed
# record can't silently change what gets written). Only FULL is written;
# refresh_working_frame_daily.R rebuilds WORKING from FULL afterwards.
# Guard: a no-change round trip of FULL must be byte-identical to the file
# on disk, or nothing is written (never silently reformat the frame).
#
# MISSED (same night, caught by Coordinator's validity suite): this script
# did not recompute strata-level FULL (achieved_clusters/achieved_sample/
# realized_moe_pct), which every merge does via recompute_strata(). Fixed by
# recompute_strata_full_certainty_sites_2026-09-21.R. Any reuse of this
# approach must run that recompute too.
#
# PRECONDITION: back up output/data/data_collection/ first.
# Usage: python add_certainty_site_interviews_2026-09-21.py
# ==============================================================================
import csv
import io
import os
import re
import sys

sys.exit("SPENT ONE-OFF: applied once on 2026-09-21 (ab9f799). Re-running would add the interviews a second time "
         "- or, after the v12 bump, edit the frozen v11. Refusing to run.")

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
DC = os.path.join(PROJECT_DIR, "output", "data", "data_collection")
FULL_CSV = os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v11_FULL.csv")
CLUSTER_STATUS_CSV = os.path.join(DC, "NGA_MSNA_2026_cluster_status_v11.csv")
REPR_CSV = os.path.join(PROJECT_DIR, "resampling", "output", "strata_representativity_status.csv")
APPROVED = {"idp_NG008023_supp2": 29, "idp_NG021007_12": 2, "idp_NG021032_supp9": 5, "idp_NG021017_3": 1}
ROUTE = re.compile(r"^Closeable via extra interviews at a certainty site \(\+(\d+) at (?:.*, )?(idp_\S+?)\)$")


def serialize(fieldnames, rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=fieldnames, lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def main():
    with open(REPR_CSV, encoding="utf-8-sig") as f:
        routes = {}
        for r in csv.DictReader(f):
            m = ROUTE.match(r["Feasibility"])
            if m:
                routes[m.group(2)] = int(m.group(1))
    if routes != APPROVED:
        sys.exit(f"STOP: the record's certainty-site routes {routes} differ from the approved {APPROVED} - nothing written.")

    with open(CLUSTER_STATUS_CSV, encoding="utf-8") as f:
        cs = {r["cluster_id"]: r for r in csv.DictReader(f)}

    with open(FULL_CSV, encoding="utf-8", newline="") as f:
        original = f.read()
    reader = csv.DictReader(io.StringIO(original))
    fields = reader.fieldnames
    rows = list(reader)
    if serialize(fields, rows) != original:
        sys.exit("STOP: a no-change round trip of FULL is not byte-identical - refusing to rewrite the frame.")
    n_before = len(rows)

    added = []
    for cid, k in APPROVED.items():
        s = cs[cid]
        acc, ach = int(s["n_accessible_primary_post_threshold"]), int(s["n_achieved"])
        if acc <= 0:
            sys.exit(f"STOP: {cid} has no accessible primaries ({s['status']}) - the route needs an accessible site.")
        ceiling = max(acc, ach) if s["status"] in ("completed", "partially_completed_access_lost") else acc
        new_target = ceiling + k
        crow = [r for r in rows if r["cluster_id"] == cid]
        prim = [r for r in crow if r["status"] == "primary"]
        resv = [r for r in crow if r["status"] == "reserve"]
        old_target = int(crow[0]["target_households"])
        if len({r["target_households"] for r in crow}) != 1 or len(prim) != old_target or len(resv) != int(crow[0]["reserve_households"]):
            sys.exit(f"STOP: {cid} rows don't match their own target/reserve fields - not editing a cluster in an unexpected state.")
        if new_target <= old_target:
            sys.exit(f"STOP: {cid} new target {new_target} is not above the current {old_target}.")
        tmpl_p = next(r for r in prim if r["interview_number"] == "1")
        tmpl_r = next(r for r in resv if r["replacement_rank"] == "1")
        for r in crow:
            r["target_households"] = str(new_target)
            r["reserve_households"] = str(new_target)
        new_rows = []
        for n in range(old_target + 1, new_target + 1):
            p = dict(tmpl_p, survey_id=f"{cid}_HH{n:02d}", interview_number=str(n))
            q = dict(tmpl_r, survey_id=f"{cid}_R{n:02d}", replacement_rank=str(n))
            new_rows += [p, q]
        live_ids = {r["survey_id"] for r in rows}
        clash = [r["survey_id"] for r in new_rows if r["survey_id"] in live_ids]
        if clash:
            sys.exit(f"STOP: new survey_ids already exist: {clash[:5]}")
        # keep the cluster's rows together: primaries after its last primary, reserves after its last reserve
        last_p = max(i for i, r in enumerate(rows) if r["cluster_id"] == cid and r["status"] == "primary")
        rows[last_p + 1:last_p + 1] = [r for r in new_rows if r["status"] == "primary"]
        last_r = max(i for i, r in enumerate(rows) if r["cluster_id"] == cid and r["status"] == "reserve")
        rows[last_r + 1:last_r + 1] = [r for r in new_rows if r["status"] == "reserve"]
        added.append((cid, crow[0]["iom_site_name"], s["status"], ceiling, k, old_target, new_target, len(new_rows)))

    out = serialize(fields, rows)
    tmp = FULL_CSV + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    os.replace(tmp, FULL_CSV)
    print(f"FULL {n_before} -> {len(rows)} rows (+{len(rows) - n_before})")
    for cid, site, st, ceil, k, old, new, nr in added:
        print(f"  {cid} ({site}, {st}): ceiling {ceil} + {k} -> target {old} -> {new}; +{nr} rows ({nr // 2} primary, {nr // 2} reserve)")


if __name__ == "__main__":
    main()
