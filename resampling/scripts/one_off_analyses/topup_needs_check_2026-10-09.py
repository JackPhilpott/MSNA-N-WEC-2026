# ==============================================================================
# 2026-10-09 READ-ONLY (#28, Jack: "check to see if there are any strata that need resampling/new draws to help with
# their representativity targets"). One row per covered stratum, built on 05's own verdicts
# (strata_representativity_status.csv; Round 2 strict rule, 5% margin) with source re-derivations as cross-checks:
#   - real achieved re-derived from real_submissions + the deletions overlay (canonical rule, spare_clusters.py);
#   - remaining collectable primaries = WORKING primaries outside unused spares; unused-spare primaries as their own
#     column (not counted anywhere - a spare is the cheapest cover for a shortfall, before any new draw);
#   - last interview, days since, collectable clusters not started -> STALLED flag;
#   - the latest real draw that asked this stratum for clusters (requested vs delivered, and for Non-IDP the building
#     check's "drawable hexes" line) - the standing Tier 2 policy: "exhausted" only after a recent real draw.
# Category is preliminary until 05 has re-run on the day's data (STALE_05 is printed when 05 predates the submissions).
# Writes resampling/output/topup_needs_2026-10-09/topup_needs_by_stratum.csv and prints a summary.
# Usage (from 1_sampling): python resampling/scripts/one_off_analyses/topup_needs_check_2026-10-09.py
# ==============================================================================
import csv
import datetime
import glob
import os
import re
import sys
from collections import Counter, defaultdict

RS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S1 = os.path.dirname(RS)
sys.path.insert(0, os.path.join(S1, "scripts", "shared"))
import msna_paths  # noqa: E402
import spare_clusters  # noqa: E402

DC = os.path.join(S1, "output", "data", "data_collection")
MON = os.path.join(msna_paths.monitoring_dir(), "data")
OUT = os.path.join(RS, "output", "topup_needs_2026-10-09")
TODAY = datetime.date.today()
STALL_DAYS = 7


def rd(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def read_text(p):
    return open(p, encoding="utf-8", errors="replace").read() if os.path.isfile(p) else ""


def latest_draws():
    """strata_id -> (the most recent real batch that requested clusters for it, the most recent one that was a full
    exhaustion test). How each draw tested the pool, from its run log:
      Non-IDP - "Tier 1+2" (Stage D ran: settles "exhausted" under the standing Tier 2 policy), "Tier 1 only"
      (DRAW_TIER1_ONLY=1, e.g. the 5 Oct spares: does NOT settle it), "Tier 1 sufficed", or "not drawn (MSNA Light, R6)"
      (the draw dropped the stratum before drawing - nothing was tested);
      IDP - "site-level" (the site draw's candidate pool; its "Still short" line = exhausted under current DTM data)."""
    best, best_full = {}, {}
    for d in glob.glob(os.path.join(RS, "output", "resample_runs", "*", "2026-*")):
        batch = os.path.basename(d)
        if any(k in batch for k in ("timing_test", "depth")) or not os.path.isdir(d):
            continue
        date = batch[:10]
        # shortfall inputs are named per era (shortfalls_nonidp.csv, care_shortfalls_nonidp.csv, ...); some batches kept none,
        # so a stratum that only appears in a delivered summary is still a draw (requested unknown)
        req_by = {}
        for p in glob.glob(os.path.join(d, "*shortfall*.csv")):
            if "empty" in os.path.basename(p) or os.path.getsize(p) < 3:
                continue
            for r in rd(p):
                n = int(float(r.get("additional_clusters_needed") or 0))
                if r.get("strata_id") and n > 0:
                    req_by[r["strata_id"]] = n
        got = {}
        for sp in glob.glob(os.path.join(d, "summary_by_stratum*.csv")):
            if os.path.getsize(sp) > 2:
                for r in rd(sp):
                    if r.get("strata_id"):
                        got[r["strata_id"]] = got.get(r["strata_id"], 0) + int(float(r.get("new_clusters") or 0))
        log_ni = read_text(os.path.join(d, "run_log.txt"))
        drawable = {"non_idp_" + m.group(1): f"{m.group(2)}/{m.group(3)}"
                    for m in re.finditer(r"(NG\d{6}): (\d+) of (\d+) candidate hexes drawable", log_ni)}
        m = re.search(r"'MSNA Light'.*?dropping from this draw: ([^\n]+)", log_ni)
        r6 = set(m.group(1).split()) if m else set()
        tested_ni = ("Tier 1 only" if "DRAW_TIER1_ONLY=1" in log_ni else "Tier 1+2" if "Stage D: Tier 2 draw" in log_ni
                     else "Tier 1 sufficed" if "nothing unresolved after Tier 1" in log_ni else "unknown")
        for sid in set(req_by) | set(got):
            pop = "idp" if sid.startswith("idp_") else "non_idp"
            req = req_by.get(sid, "")
            tested = tested_ni if pop == "non_idp" else "site-level" if date >= "2026-09-02" else "IDP hex (pre site-level)"
            rec = {"last_draw_date": date, "last_draw_batch": f"{os.path.basename(os.path.dirname(d))}/{batch}",
                   "last_draw_requested": req, "last_draw_delivered": got.get(sid, 0),
                   "last_draw_drawable_hexes": drawable.get(sid, ""),
                   "last_draw_tested": "not drawn (MSNA Light, R6)" if sid in r6 else tested}
            key = (date, rec["last_draw_batch"])
            if sid not in best or key >= (best[sid]["last_draw_date"], best[sid]["last_draw_batch"]):
                best[sid] = rec
            if tested in ("Tier 1+2", "site-level") and sid not in r6 and (
                    sid not in best_full or key >= (best_full[sid]["last_draw_date"], best_full[sid]["last_draw_batch"])):
                best_full[sid] = rec
    return best, best_full


def main():
    os.makedirs(OUT, exist_ok=True)
    status = {r["Strata ID"]: r for r in rd(os.path.join(RS, "output", "strata_representativity_status.csv"))}
    t05 = datetime.datetime.fromtimestamp(os.path.getmtime(os.path.join(RS, "output", "strata_representativity_status.csv")))
    subs_p = os.path.join(MON, "real_submissions.csv")
    tsub = datetime.datetime.fromtimestamp(os.path.getmtime(subs_p))
    excluded = {r["uuid"] for r in rd(os.path.join(MON, "CONFIRMED_DELETIONS_OVERLAY.csv")) if r["status"] in ("confirmed", "contested")}
    ach_s, ach_c, last = Counter(), Counter(), {}
    for r in rd(subs_p):
        if r["interview_outcome"] == "completed" and r["matched_survey_id"] not in ("", "NA") and r["submission_uuid"] not in excluded:
            ach_s[r["matched_strata_id"]] += 1
            if r["matched_cluster_id"] not in ("", "NA"):
                ach_c[r["matched_cluster_id"]] += 1
            d = (r.get("submission_date") or "")[:10]
            if re.match(r"\d{4}-\d{2}-\d{2}$", d) and d > last.get(r["matched_strata_id"], ""):
                last[r["matched_strata_id"]] = d
    reg = spare_clusters.load_register(S1)
    unused = spare_clusters.unused_spare_ids(reg, ach_c)
    rem, rem_sp, res, todo_cl = Counter(), Counter(), Counter(), defaultdict(set)
    for r in rd(os.path.join(DC, "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv")):
        if r["status"] != "primary":
            if r["status"] == "reserve" and r["cluster_id"] not in unused:
                res[r["strata_id"]] += 1
            continue
        if r["cluster_id"] in unused:
            rem_sp[r["strata_id"]] += 1
        else:
            rem[r["strata_id"]] += 1
            todo_cl[r["strata_id"]].add(r["cluster_id"])
    draws, full_tests = latest_draws()
    method = {r["strata_id"]: r["sampling_method"] for r in rd(os.path.join(DC, "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv"))}
    rows = []
    for sid, s in status.items():
        verdict = s["Representativity (10% MoE threshold)"]
        bucket = s["Completion bucket"]
        not_started = sum(1 for c in todo_cl[sid] if ach_c.get(c, 0) == 0)
        dl = last.get(sid, "")
        days = (TODAY - datetime.date.fromisoformat(dl)).days if dl else None
        stalled = rem[sid] > 0 and (days is None or days > STALL_DAYS)
        dr = draws.get(sid, {})
        try:
            gap = max(0, int(float(s["Target sample (true requirement, incl. 5% margin)"])) - ach_s.get(sid, 0))
        except ValueError:
            gap = ""
        if verdict.startswith("N/A"):
            cat = "excluded"
        elif verdict.startswith("Not computable"):
            cat = "not computable (structural - no draw can fix)"
        elif verdict.startswith("Representative"):
            cat = "on track - representative now" if bucket.startswith("(a)") else "on track - needs collection only"
        elif "RECOVERABLE" in verdict and method.get(sid) == "MSNA Light":
            cat = "needs new clusters (05: recoverable) - but MSNA Light: Full Design draws blocked by R6 (policy question)"
        elif "RECOVERABLE" in verdict:
            cat = "needs new clusters (05: recoverable by a draw)" + (" - but the last real draw under-delivered" if dr and dr["last_draw_delivered"] < dr["last_draw_requested"] else "")
        else:
            cat = ("needs depth in existing collectable clusters (no pool for new clusters)" if todo_cl[sid] or rem[sid] > 0 or s["Pop type"] == "IDP"
                   else "not recoverable (no pool, no collectable cluster)")
        rows.append({
            "strata_id": sid, "state": s["State"], "lga": s["LGA"], "pop_type": s["Pop type"], "partners": s["Partners covering"],
            "category": cat, "verdict_05": verdict[:60], "bucket_05": bucket[:4], "projected_moe_05": s["Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)"],
            "target_05": s["Target sample (true requirement, incl. 5% margin)"], "achieved_05": s["Achieved (real, field-collected)"],
            "achieved_now": ach_s.get(sid, 0), "gap_to_target_now": gap, "remaining_collectable_primaries": rem[sid],
            "remaining_reserves": res[sid], "collection_alone_short_by": "" if gap == "" else max(0, gap - rem[sid] - res[sid]),
            "unused_spare_primaries": rem_sp[sid],
            "collectable_clusters_with_todo": len(todo_cl[sid]), "collectable_clusters_not_started": not_started,
            "last_interview": dl, "days_since_last": "" if days is None else days, "stalled": "YES" if stalled else "",
            "sampling_method": method.get(sid, ""),
            **{k: dr.get(k, "") for k in ("last_draw_date", "last_draw_batch", "last_draw_requested", "last_draw_delivered", "last_draw_drawable_hexes", "last_draw_tested")},
            **{"full_test_" + k[10:]: full_tests.get(sid, {}).get(k, "") for k in ("last_draw_date", "last_draw_batch", "last_draw_requested", "last_draw_delivered", "last_draw_tested")}})
    with open(os.path.join(OUT, "topup_needs_by_stratum.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: (r["category"], r["state"], r["lga"], r["pop_type"])))
    print(f"05 outputs: {t05:%Y-%m-%d %H:%M} | real_submissions: {tsub:%Y-%m-%d %H:%M}" + ("  ** STALE_05: 05 predates the submissions - verdicts are preliminary **" if t05 < tsub else ""))
    print(f"strata: {len(rows)} | unused spares: {len(unused)} | achieved (canonical) {sum(ach_s.values()):,}")
    for k, n in sorted(Counter(r["category"] for r in rows).items(), key=lambda x: -x[1]):
        print(f"  {n:4d}  {k}")
    st = [r for r in rows if r["stalled"] and r["category"].startswith("on track - needs")]
    print(f"STALLED among 'needs collection only': {len(st)} strata, {sum(r['remaining_collectable_primaries'] for r in st):,} primaries to do; by partner:",
          dict(Counter(r["partners"] for r in st).most_common(8)))
    sh = [r for r in rows if r["category"].startswith("on track - needs") and r["collection_alone_short_by"]]
    print(f"'needs collection only' strata whose remaining primaries+reserves cannot close the gap: {len(sh)}")
    for r in sh:
        print(f"  {r['lga'][:13]:13} {r['pop_type']:7} {r['partners'][:11]:11} gap {r['gap_to_target_now']} todo {r['remaining_collectable_primaries']}"
              f"+{r['remaining_reserves']}r short {r['collection_alone_short_by']} spare {r['unused_spare_primaries']}")
    print("\nNON-REPRESENTATIVE (top-up candidates):")
    for r in rows:
        if r["category"].startswith(("needs", "not recoverable")):
            print(f"  {r['lga'][:13]:13} {r['pop_type']:7} {r['partners'][:11]:11} MoE {r['projected_moe_05'][:5]:5} ach05 {r['achieved_05']:>4} now {r['achieved_now']:>4} "
                  f"| todo {r['remaining_collectable_primaries']:>4} in {r['collectable_clusters_with_todo']} cl | spare {r['unused_spare_primaries']} "
                  f"| last draw {r['last_draw_date'] or '-'} {r['last_draw_delivered']}/{r['last_draw_requested']} {r['last_draw_tested']} hex {r['last_draw_drawable_hexes']} "
                  f"| full test {r['full_test_date'] or '-'} {r['full_test_delivered']}/{r['full_test_requested']} {r['full_test_tested']} | {r['sampling_method']} | {r['category'][:60]}")


if __name__ == "__main__":
    main()
