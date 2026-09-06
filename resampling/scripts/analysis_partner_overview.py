# ==============================================================================
# On-demand partner accessibility-reporting status table. Read-only - never
# writes anything. Built 2026-08-27 in preference to a maintained file/
# artifact: partner status changes almost every session, so a static output
# would just be one more thing that goes stale (exactly the class of problem
# the Solidarités/two-session cleanup this same day was about) - this always
# reflects the current state of the master log + input folders at run time.
#
# "Wards assigned" is recomputed fresh from the live WORKING frame (same
# logic 01_generate_accessibility_reports.py uses), not read from any
# generated report file, so it's correct even if a partner's report hasn't
# been regenerated since their last cluster reallocation.
#
# "Wards reported" counts a ward as reported if the LATEST (non-superseded)
# logged row for that (partner, state, lga, ward) key has a real answer -
# mirrors 04_build_master_accessibility_status.py's own latest-wins logic.
# ==============================================================================
import csv
import glob
import os
from collections import defaultdict

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v5_WORKING.csv"
LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"
GENERATED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_generated"
RETURNED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned"
DRAFTS_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_drafts"
RAW_COMMS_DIR = PROJECT_DIR + r"\resampling\input\partner_raw_comms"


def wards_assigned_by_partner():
    with open(STAGE2_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    out = defaultdict(set)
    for r in rows:
        partners = [p.strip() for p in r["partners_covering"].split(",") if p.strip() and p.strip() != "NA"]
        key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
        for p in partners:
            out[p].add(key)
    return out


def latest_log_rows():
    if not os.path.exists(LOG_CSV):
        return []
    with open(LOG_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    latest = {}
    for r in rows:
        key = (r["partner"], r["report_level"], r["state"], r["lga"], r["ward_name"], r["cluster_id"])
        if key not in latest or int(r["request_id"]) > int(latest[key]["request_id"]):
            latest[key] = r
    return list(latest.values())


def cluster_only_partners(all_latest_rows):
    """Partners whose only logged rows are cluster-level (report_level ==
    'cluster') - i.e. they returned something, just not at the ward
    granularity this workflow primarily tracks. Distinguished from a true
    zero-engagement partner so the status table doesn't conflate the two."""
    has_ward = set()
    has_cluster = set()
    for r in all_latest_rows:
        if r["accessible"]:
            (has_ward if r["report_level"] == "ward" else has_cluster).add(r["partner"])
    return has_cluster - has_ward


def staged_partner_names():
    files = glob.glob(os.path.join(GENERATED_DIR, "*_accessibility_report.xlsx"))
    return sorted(os.path.basename(f)[: -len("_accessibility_report.xlsx")] for f in files)


def build_overview():
    assigned = wards_assigned_by_partner()
    all_latest = latest_log_rows()
    cluster_only = cluster_only_partners(all_latest)
    log_rows = [r for r in all_latest if r["report_level"] == "ward"]

    reported_wards = defaultdict(set)
    no_wards = defaultdict(set)
    last_date = defaultdict(str)
    for r in log_rows:
        key = (r["state"], r["lga"], r["ward_name"])
        p = r["partner"]
        if r["accessible"]:
            reported_wards[p].add(key)
            if r["accessible"].strip().lower() == "no":
                no_wards[p].add(key)
        d = r.get("date_reported_by_partner") or r.get("date_added") or ""
        if d and d > last_date[p]:
            last_date[p] = d

    returned_partners = {os.path.basename(f)[: -len("_accessibility_report.xlsx")]
                          for f in glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx"))}
    draft_partners = {os.path.basename(f)[: -len("_accessibility_report_DRAFT.xlsx")]
                       for f in glob.glob(os.path.join(DRAFTS_DIR, "*_accessibility_report_DRAFT.xlsx"))}
    raw_comms_partners = set()
    if os.path.isdir(RAW_COMMS_DIR):
        for name in os.listdir(RAW_COMMS_DIR):
            folder = os.path.join(RAW_COMMS_DIR, name)
            if os.path.isdir(folder) and any(os.path.isfile(os.path.join(folder, f)) for f in os.listdir(folder)):
                raw_comms_partners.add(name)

    rows = []
    for partner in staged_partner_names():
        n_assigned = len(assigned.get(partner, set()))
        n_reported = len(reported_wards.get(partner, set()))
        n_no = len(no_wards.get(partner, set()))
        pct = round(100 * n_reported / n_assigned) if n_assigned else 0
        returned = partner in returned_partners

        if n_reported == 0 and not returned and partner not in draft_partners and partner not in raw_comms_partners:
            status = "Not started"
        elif n_reported == 0 and partner in cluster_only:
            status = "Returned, but cluster-level only - 0 ward-level rows"
        elif n_reported == 0 and (partner in raw_comms_partners or partner in draft_partners):
            status = "In progress (raw comms only, no formal return yet)"
        elif returned and n_reported >= n_assigned and n_assigned > 0:
            status = "Complete"
        elif returned:
            status = "Partial (returned but not all wards covered)"
        else:
            status = "Partial"

        rows.append({
            "partner": partner, "assigned": n_assigned, "reported": n_reported, "pct": pct,
            "no": n_no, "last_date": last_date.get(partner, ""), "status": status,
        })
    return rows


def print_table(rows):
    headers = ["Partner", "Wards assigned", "Wards reported", "% covered", "Reported No", "Last report date", "Status"]
    widths = [24, 14, 14, 9, 12, 16, 52]
    print("  ".join(h.ljust(w) for h, w in zip(headers, widths)))
    print("  ".join("-" * w for w in widths))
    for r in sorted(rows, key=lambda r: (r["pct"], r["partner"])):
        vals = [r["partner"], str(r["assigned"]), str(r["reported"]), f"{r['pct']}%",
                str(r["no"]), r["last_date"] or "-", r["status"]]
        print("  ".join(v.ljust(w) for v, w in zip(vals, widths)))

    n_complete = sum(1 for r in rows if r["status"] == "Complete")
    n_not_started = sum(1 for r in rows if r["status"] == "Not started")
    n_in_progress = sum(1 for r in rows if "In progress" in r["status"])
    n_partial = len(rows) - n_complete - n_not_started - n_in_progress
    print(f"\n{len(rows)} partners total: {n_complete} complete, {n_partial} partial, "
          f"{n_in_progress} in progress (raw comms only), {n_not_started} not started.")
    print("\nFollow-up needed from:", ", ".join(sorted(
        r["partner"] for r in rows if r["status"] != "Complete")) or "none - all complete")


if __name__ == "__main__":
    print_table(build_overview())
