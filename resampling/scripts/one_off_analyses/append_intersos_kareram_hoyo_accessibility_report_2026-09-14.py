"""
Appends 2 new ward-level accessibility log rows for INTERSOS/Magumeri
(Kareram, Hoyo Chingua), Borno - both reported accessible directly in
INTERSOS's own _1409 follow-up email (not the attached spreadsheet, which
never listed these 2 wards at all - see resampling/scripts/one_off_analyses/
draw_intersos_kareram_hoyo_non_idp_2026-09-14.R's own header for full
context). Neither ward has ever appeared in the sampling frame before today
(no cluster ever drawn there), so 04_build_master_accessibility_status.py's
build_universe() - which derives the ward universe from the FULL household
frame's own clusters - could never have picked them up until AFTER today's
dedicated supplementary draw (that script) was merged in. Idempotent: run
this only once per real report; rerunning would duplicate the log entry
(02_ingest_accessibility_reports.py's own de-dup logic works on RETURNED
FILES, not on manually-appended log rows like this one).
"""
import csv

LOG_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\output\resampling_requests_log.csv"

with open(LOG_CSV, encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    rows = list(reader)

already_logged = any(
    r["partner"] == "INTERSOS" and r["lga"] == "Magumeri" and r["ward_name"] in ("Kareram", "Hoyo Chingua")
    for r in rows
)
if already_logged:
    raise SystemExit("Kareram/Hoyo Chingua already have a log entry for INTERSOS - not appending again. "
                      "Check resampling_requests_log.csv directly before rerunning this script.")

next_id = max(int(r["request_id"]) for r in rows) + 1

new_rows = []
for ward in ["Kareram", "Hoyo Chingua"]:
    row = {k: "" for k in fieldnames}
    row.update({
        "request_id": str(next_id),
        "date_added": "2026-09-14",
        "partner": "INTERSOS",
        "report_level": "ward",
        "state": "Borno",
        "lga": "Magumeri",
        "ward_name": ward,
        "cluster_id": "",
        "pop_type": "",
        "source_channel": "Email",
        "reported_by": "Partner",
        "accessible": "Yes",
        "reason_category": "N/A - fully accessible",
        "reason_notes": (
            "INTERSOS's own _1409 accessibility follow-up email (Jesse Amos, 2026-09-14): "
            "\"While most locations in Magumeri are currently inaccessible, Kareram and Hoyo wards "
            "are accessible; however, these two wards were not included in the clustering for this "
            "exercise.\" Never in the ward universe before today (no cluster ever drawn there) - a "
            "dedicated supplementary draw was run 2026-09-14 (resampling/output/resample_runs/"
            "INTERSOS/2026-09-14_kareram_hoyo/) to give both real, visitable points."
        ),
        "pct_target_achieved": "",
        "date_reported_by_partner": "2026-09-14",
        "status": "new",
        "resolution_mechanism": "",
        "resolution_date": "",
        "resolution_notes": "",
        "supersedes_request_id": "",
    })
    new_rows.append(row)
    next_id += 1

with open(LOG_CSV, "a", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    for row in new_rows:
        writer.writerow(row)

print(f"Appended {len(new_rows)} rows (request_id {new_rows[0]['request_id']}-{new_rows[-1]['request_id']})")
