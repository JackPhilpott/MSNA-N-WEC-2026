# ==============================================================================
# 2026-10-12: ingest ONE partner's returned accessibility report into the master log (resampling_requests_log.csv),
# with exactly 02_ingest_accessibility_reports.py's own row-building and diff (imported from it, not copied).
# Why not 02 itself: on 12 Oct a scratch run of 02 over the whole returned folder found 10 stale rows in the reports of
# the partners who lost LGAs to FACT on 4 Oct (FHI 360, IRC, Solidarites, Street Child). Re-logging them would put their
# old answers back on top of FACT's 4 Oct decisions (e.g. Dalori, Yandoton Daji, Gulak, Kekeno). This step logs only the
# named partner's file, and --expect-lga refuses any new row outside the LGA(s) the change is about.
# Dry run by default (prints the rows it would log); --execute appends them.
# Usage: py ingest_partner_report_only_2026-10-12.py --partner INTERSOS --expect-lga Maru [--execute]
# ==============================================================================
import argparse
import csv
import importlib.util
import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("ingest02", os.path.join(os.path.dirname(HERE), "02_ingest_accessibility_reports.py"))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--partner", required=True)
    ap.add_argument("--expect-lga", action="append", default=[], help="refuse if a new/changed row is outside these LGA(s)")
    ap.add_argument("--execute", action="store_true")
    a = ap.parse_args()
    path = os.path.join(m.RETURNED_DIR, f"{a.partner}_accessibility_report.xlsx")
    log_rows = m.load_existing_log()
    latest = m.latest_by_key(log_rows)
    req_id = m.next_request_id(log_rows)
    new_rows = []
    for rep in m.read_returned_file(path, a.partner):
        key = (a.partner, rep["report_level"], rep["state"], rep["lga"], rep["ward_name"], rep["cluster_id"])
        prior = latest.get(key)
        if prior is not None and all(str(prior.get(f, "")) == str(rep.get(f, "")) for f in m.COMPARE_FIELDS):
            continue
        row = {f: "" for f in m.LOG_FIELDS}
        row.update(rep)
        row.update(request_id=req_id, date_added=date.today().isoformat(), status="new",
                   source_channel=rep["source_channel"] or m.DEFAULT_SOURCE_CHANNEL,
                   reported_by=rep["reported_by"] or m.DEFAULT_REPORTED_BY,
                   supersedes_request_id=prior["request_id"] if prior else "")
        new_rows.append(row)
        latest[key] = row
        req_id += 1
    print(f"{a.partner}: {len(new_rows)} new/changed row(s) against the log ({m.LOG_CSV})")
    for r in new_rows:
        print(f"  {r['request_id']}: {r['report_level']} {r['state']}/{r['lga']}/{r['ward_name'] or r['cluster_id']} -> "
              f"{r['accessible']} ({r['reason_category']}), supersedes {r['supersedes_request_id'] or '-'}")
    outside = [r for r in new_rows if a.expect_lga and r["lga"] not in a.expect_lga]
    if outside:
        sys.exit(f"STOP: {len(outside)} new row(s) outside {a.expect_lga} - nothing written")
    if not a.execute:
        print("dry run: nothing written")
        return
    if new_rows:
        with open(m.LOG_CSV, "a", encoding="utf-8", newline="") as f:
            csv.DictWriter(f, fieldnames=m.LOG_FIELDS).writerows(new_rows)
    print(f"appended {len(new_rows)} row(s) to {m.LOG_CSV}")


if __name__ == "__main__":
    main()
