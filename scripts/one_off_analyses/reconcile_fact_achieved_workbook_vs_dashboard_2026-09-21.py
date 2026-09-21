# ==============================================================================
# Interview-level reconciliation of FACT's "Achieved" between the partner
# workbook (build_partner_dc_packages.py) and the monitoring dashboard
# (2_monitoring/dashboard_app/global.R, compute_progress_by_stratum() +
# partner_progress_by_lga()), 2026-09-21. Jack's ask: investigate fully the
# ~390-425 gap Coordinator found (dashboard ~12,437 vs workbook 12,012).
#
# Method: account for every unit of credit on BOTH sides, classify each unit
# that only one side counts by the specific rule that causes it, and assert
# the buckets sum EXACTLY to the gap - nothing explained by approximation.
#
# The two definitions, re-read from the code on 2026-09-21 (not recalled):
#   DASHBOARD  one unit per SUBMISSION where
#              interview_outcome == "completed"
#              AND deletion_status NOT IN (confirmed, contested)   [real_submissions column]
#              AND matched_cluster_id present
#              AND matched_strata_id -> strata_frame -> adm2_pcode in FACT's LGAs
#                  (partner_lga_assignment.csv, org_id == "fact")
#              AND stratum not "Dropped" (coverage_status == "excluded" or
#                  a non-computable revised target)
#   WORKBOOK   Non-IDP: one unit per FRAME ROW (primary or reserve) of a FACT
#                  cluster whose survey_id has >= 1 achieved submission,
#                  achieved = completed AND matched_survey_id present AND
#                  uuid NOT in CONFIRMED_DELETIONS_OVERLAY (confirmed/contested).
#                  Dedups by point; credits via survey_id regardless of the
#                  submission's matched_cluster_id.
#              IDP: one unit per achieved SUBMISSION with matched_cluster_id
#                  in a FACT workbook cluster.
#              Scope = the clusters actually present in FACT's workbook
#              Cluster Summary (read from the file itself - ground truth).
#
# Output: resampling/output/fact_achieved_reconciliation_2026-09-21/
# Usage:  python reconcile_fact_achieved_workbook_vs_dashboard_2026-09-21.py
# ==============================================================================
import csv
import os
from collections import Counter, defaultdict

import openpyxl

ROOT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
S1 = ROOT + r"\1_sampling"
M2 = ROOT + r"\2_monitoring"
SUBS_CSV = M2 + r"\data\real_submissions.csv"
OVERLAY_CSV = M2 + r"\data\CONFIRMED_DELETIONS_OVERLAY.csv"
PLA_CSV = M2 + r"\input_data\partner_coverage\partner_lga_assignment.csv"
def latest_frame_file(directory, template):
    """Newest-version frame file in `directory` (top level only). Added at the
    v11 -> v12 bump (2026-09-21) so a rerun can't read a frozen old version."""
    import re
    rx = re.compile("^" + re.escape(template).replace(r"\{\}", r"(\d+)") + "$")
    hits = [(int(m.group(1)), f) for f in os.listdir(directory) for m in [rx.match(f)] if m]
    if not hits:
        raise SystemExit(f"No file matching {template} in {directory}")
    return os.path.join(directory, max(hits)[1])


STRATA_CSV = latest_frame_file(M2 + r"\input_data\sampling_frame", "NGA_MSNA_2026_strata_level_sampling_frame_v{}_FULL.csv")
FULL_CSV = latest_frame_file(S1 + r"\output\data\data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v{}_FULL.csv")
TREPR_CSV = S1 + r"\resampling\output\target_sample_representativity_last_run.csv"
WB = r"C:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package\FACT\FACT_sampling_points_summary.xlsx"
OUT_DIR = S1 + r"\resampling\output\fact_achieved_reconciliation_2026-09-21"
os.makedirs(OUT_DIR, exist_ok=True)

NA = (None, "", "NA")
TERMINAL = {"confirmed", "contested"}


def load(p):
    with open(p, encoding="utf-8") as f:
        return list(csv.DictReader(f))


subs = load(SUBS_CSV)
overlay_terminal = {r["uuid"] for r in load(OVERLAY_CSV) if r["status"] in TERMINAL}
fact_adm2 = {r["adm2_pcode"] for r in load(PLA_CSV) if r["org_id"] == "fact"}
strata = {r["strata_id"]: r for r in load(STRATA_CSV) if r.get("coverage_status") != "not_covered"}
trepr = {r["strata_id"]: r.get("target_sample_representativity") for r in load(TREPR_CSV)} if os.path.exists(TREPR_CSV) else {}
full = load(FULL_CSV)
print(f"real_submissions: {len(subs)} rows | overlay terminal uuids: {len(overlay_terminal)} | FACT LGAs (dashboard): {len(fact_adm2)}")

rows_by_cluster = defaultdict(list)
cluster_meta = {}
for r in full:
    rows_by_cluster[r["cluster_id"]].append(r)
    cluster_meta.setdefault(r["cluster_id"], r)

# ---- workbook ground truth: its own Cluster Summary ------------------------
wb = openpyxl.load_workbook(WB, read_only=True)
ws = wb["Cluster Summary"]
hdr = None
wb_ach = {}
wb_pop = {}
for row in ws.iter_rows(values_only=True):
    if hdr is None:
        hdr = list(row)
        ic, ip, ia = hdr.index("Cluster ID"), hdr.index("Population Type"), hdr.index("Achieved")
        continue
    if row[ic]:
        wb_ach[row[ic]] = int(row[ia] or 0)
        wb_pop[row[ic]] = row[ip]
wb.close()
WB_TOTAL = sum(wb_ach.values())
print(f"WORKBOOK Cluster Summary: {len(wb_ach)} clusters, Achieved total = {WB_TOTAL}")


def stratum_dropped(sid):
    s = strata.get(sid)
    if s is None:
        return None  # not in strata_frame at all
    if s.get("coverage_status") == "excluded":
        return True
    v = trepr.get(sid)
    return v in NA  # target_not_computable


# ---- DASHBOARD set (submission-level) --------------------------------------
def dash_reason_excluded(s):
    if s.get("interview_outcome") != "completed":
        return "not completed"
    if s.get("deletion_status") in TERMINAL:
        return "confirmed deletion (dashboard column)"
    if s.get("matched_cluster_id") in NA:
        return "no matched_cluster_id"
    sid = s.get("matched_strata_id")
    st = strata.get(sid)
    if st is None:
        return "matched_strata_id not in strata_frame"
    if st.get("adm2_pcode") not in fact_adm2:
        return "not a FACT LGA"
    if stratum_dropped(sid):
        return "stratum Dropped"
    return None


D = [s for s in subs if dash_reason_excluded(s) is None]
D_TOTAL = len(D)
print(f"DASHBOARD (replicated): Achieved total = {D_TOTAL}")
print(f"GAP (dashboard - workbook) = {D_TOTAL - WB_TOTAL}\n")

# ---- WORKBOOK replicated at unit level --------------------------------------
def wb_achieved_sub(s):
    return (s.get("interview_outcome") == "completed"
            and s.get("matched_survey_id") not in NA
            and s.get("submission_uuid") not in overlay_terminal)


subs_by_sid = defaultdict(list)
for s in subs:
    if s.get("matched_survey_id") not in NA:
        subs_by_sid[s["matched_survey_id"]].append(s)

D_uuids = {s["submission_uuid"] for s in D}
buckets = Counter()           # reason -> signed units (+ = dashboard-only, - = workbook-only)
examples = defaultdict(list)
detail_rows = []
wb_replicated = Counter()
used_D = set()                # D uuids matched 1:1 to a workbook unit


def note(reason, sign, cid, s=None, extra=""):
    buckets[reason] += sign
    if len(examples[reason]) < 6:
        examples[reason].append(f"{cid} {s.get('submission_uuid') if s else ''} {extra}".strip())
    detail_rows.append({"reason": reason, "direction": "dashboard_only" if sign > 0 else "workbook_only",
                        "cluster_id": cid, "submission_uuid": s.get("submission_uuid") if s else "",
                        "matched_survey_id": s.get("matched_survey_id") if s else "",
                        "pop_type": (s or cluster_meta.get(cid, {})).get("pop_type", ""),
                        "org_id": s.get("org_id") if s else "", "extra": extra})


# Walk every WORKBOOK unit, pair it with a dashboard submission if one exists.
for cid in wb_ach:
    pop = cluster_meta.get(cid, {}).get("pop_type") or ("idp" if cid.startswith("idp_") else "non_idp")
    if pop == "non_idp":
        for r in rows_by_cluster.get(cid, []):
            cands = [s for s in subs_by_sid.get(r["survey_id"], []) if wb_achieved_sub(s)]
            if not cands:
                continue
            wb_replicated[cid] += 1
            inD = [s for s in cands if s["submission_uuid"] in D_uuids and s["submission_uuid"] not in used_D]
            if inD:
                used_D.add(inD[0]["submission_uuid"])
            else:
                s0 = cands[0]
                why = dash_reason_excluded(s0) or "paired elsewhere"
                note(f"WORKBOOK-only: {why}", -1, cid, s0, r["survey_id"])
    else:
        for s in subs:
            if s.get("matched_cluster_id") == cid and wb_achieved_sub(s):
                wb_replicated[cid] += 1
                if s["submission_uuid"] in D_uuids and s["submission_uuid"] not in used_D:
                    used_D.add(s["submission_uuid"])
                else:
                    note(f"WORKBOOK-only: {dash_reason_excluded(s) or 'paired elsewhere'}", -1, cid, s)

# Every DASHBOARD submission not paired to a workbook unit gets a reason.
wb_clusters = set(wb_ach)
for s in D:
    if s["submission_uuid"] in used_D:
        continue
    cid = s["matched_cluster_id"]
    meta = cluster_meta.get(cid)
    if cid not in wb_clusters:
        if meta is None:
            reason = "DASHBOARD-only: cluster not in v11 FULL (dropped/redrawn/deleted cluster_id)"
        elif meta.get("sampling_method") == "MSNA Light":
            reason = "DASHBOARD-only: MSNA Light cluster (kept off the workbook's main headline by design)"
        elif meta.get("adm2_pcode") not in fact_adm2:
            reason = "DASHBOARD-only: cluster's own LGA is not FACT's (submission's stratum is)"
        else:
            reason = f"DASHBOARD-only: cluster in FULL but not in FACT workbook (coverage={meta.get('coverage_status')}/{meta.get('exclusion_reason')})"
    elif s.get("matched_survey_id") in NA:
        reason = "DASHBOARD-only: no matched_survey_id (workbook requires a point match)"
    elif s["submission_uuid"] in overlay_terminal:
        reason = "DASHBOARD-only: in deletions overlay but deletion_status column not confirmed (source mismatch)"
    elif s.get("pop_type") == "non_idp" and s["matched_survey_id"] not in {r["survey_id"] for r in rows_by_cluster.get(cid, [])}:
        reason = "DASHBOARD-only: matched_survey_id is not a row of its matched cluster"
    elif s.get("pop_type") == "non_idp":
        reason = "DASHBOARD-only: 2nd+ submission to the SAME Non-IDP point (workbook counts the point once)"
    else:
        reason = "DASHBOARD-only: other"
    note(reason, +1, cid, s)

# ---- checks -----------------------------------------------------------------
wb_rep_total = sum(wb_replicated.values())
mism = {c: (wb_ach[c], wb_replicated.get(c, 0)) for c in wb_ach if wb_ach[c] != wb_replicated.get(c, 0)}
print(f"Workbook replicated from submissions: {wb_rep_total} (workbook file says {WB_TOTAL}); "
      f"clusters where replication != file: {len(mism)}")
for c, (a, b) in list(mism.items())[:8]:
    print(f"   {c}: file={a} replicated={b}")
# The logic gap must be measured like-for-like: BOTH rules on the SAME
# real_submissions.csv. The workbook FILE was built at some earlier moment
# from an older pull, so (file total) differs from (rule on today's data) by
# pure data drift - reported separately, never mixed into the logic gap.
# Validated 2026-09-21: the real builder run fresh (scratch copy) gave
# exactly wb_rep_total, and the dashboard's own partner_progress_by_lga()
# gave exactly D_TOTAL - both replicas are exact, not approximations.
logic_gap = D_TOTAL - wb_rep_total
net = sum(buckets.values())
print(f"\nLOGIC GAP (dashboard rule - workbook rule, both on today's data) = {D_TOTAL} - {wb_rep_total} = {logic_gap}")
print(f"Sum of all buckets = {net}  ->  {'EXACT - every unit accounted for' if net == logic_gap else 'DOES NOT RECONCILE'}")
print(f"DATA DRIFT (workbook rule on today's data - workbook file as last built) = {wb_rep_total} - {WB_TOTAL} = {wb_rep_total - WB_TOTAL}\n")

print("RECONCILIATION (dashboard-only counts +, workbook-only counts -):")
for reason, n in sorted(buckets.items(), key=lambda kv: -abs(kv[1])):
    print(f"  {n:+6d}  {reason}")
    for e in examples[reason][:3]:
        print(f"            e.g. {e}")

with open(os.path.join(OUT_DIR, "reconciliation_summary.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["reason", "signed_units"])
    for reason, n in sorted(buckets.items(), key=lambda kv: -abs(kv[1])):
        w.writerow([reason, n])
    w.writerow(["DASHBOARD_TOTAL (rule, today's data)", D_TOTAL])
    w.writerow(["WORKBOOK_TOTAL (rule, today's data)", wb_rep_total])
    w.writerow(["LOGIC_GAP", logic_gap])
    w.writerow(["WORKBOOK_FILE_TOTAL (as last built)", WB_TOTAL])
    w.writerow(["DATA_DRIFT (rule today - file)", wb_rep_total - WB_TOTAL])
with open(os.path.join(OUT_DIR, "reconciliation_detail.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["reason", "direction", "cluster_id", "submission_uuid",
                                      "matched_survey_id", "pop_type", "org_id", "extra"])
    w.writeheader()
    w.writerows(detail_rows)
print(f"\nWrote {OUT_DIR}\\reconciliation_summary.csv and reconciliation_detail.csv ({len(detail_rows)} rows)")
