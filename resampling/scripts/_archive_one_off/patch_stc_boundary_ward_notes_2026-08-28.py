# ==============================================================================
# One-off correction (2026-08-28): 7 Save the Children Katsina wards (Gallu,
# Sabon Gari, Bamle, Ubandawaki A, Ubandawaki B in Mai'adua; Fago B, Maibara
# in Zango) originally carried the partner's SPECIFIC boundary-disagreement
# comment (e.g. "This Mashi LGA not Maiadua and should be remove from the
# list") as their reason note. Somewhere in an earlier regeneration round
# (traced to log rows added 2026-08-25), 6 of the 7 got silently overwritten
# with the generic "Marked accessible by default... given the scope of their
# review" boilerplate meant for wards the partner never commented on at all -
# losing the more accurate, specific reasoning (the GRID3/OCHA boundary
# disagreement Jack already resolved directly with the partner on 2026-08-11,
# see the raw email in resampling/input/partner_raw_comms/Save the Children/).
# The 7th, Ubandawaki A, never got logged with an Accessible value at all and
# was sitting fully blank.
#
# Found 2026-08-28 while checking Save the Children's latest email/attachment
# against our current record (the attachment turned out to be an earlier,
# more accurate copy of our own file - not new partner data - which is what
# surfaced this). None of these 7 wards' actual accessibility DETERMINATION
# changes here - all 7 were and remain Accessible=Yes, per Jack's own already-
# communicated 2026-08-11 decision to retain the original OCHA/COD-based LGA
# assignment for all 54 boundary-flagged points. This only restores the
# specific, accurate reason note (and fills in Ubandawaki A's missing Yes,
# consistent with its 6 identical-pattern siblings) - not a new decision.
#
# Appends corrected rows to the log rather than editing history in place
# (matches 02_ingest_accessibility_reports.py's own append-only convention -
# latest_by_key() in that script already prefers the highest request_id per
# key, so these simply supersede the earlier, wrong rows on the next rebuild).
# Run once; rerun run_accessibility_refresh.py afterward to rebuild every
# downstream output from the corrected log.
#
# ADDENDUM (same day): appending to the log alone did NOT stick - the next
# run_accessibility_refresh.py's ingest step re-read the still-unpatched
# returned .xlsx, saw its content differ from what the log now said, and
# logged THAT as a newer "change", re-asserting the old boilerplate at an
# even higher request_id (silently superseding this patch's own rows). The
# returned .xlsx is what 02_ingest_accessibility_reports.py treats as
# authoritative on every run, so the actually-effective fix was editing
# Save the Children_accessibility_report.xlsx's Ward Accessibility sheet
# directly (same 7 rows/values as CORRECTIONS below), then rerunning the
# refresh chain once more. Leaving this script as-is for the record; a
# future correction of this kind should patch the returned file directly,
# not the log.
#
# SECOND ADDENDUM (2026-08-29, found during the pre-resampling sanity
# sweep): the ADDENDUM fix above worked for 6 of the 7 wards, but Ubandawaki
# A had NO pre-existing log row at all (unlike its 6 siblings, which had the
# old wrong boilerplate to differ against) - so when the returned .xlsx was
# patched with the SAME reason-note text this script had already logged at
# request_id 2243, 02_ingest's content-diff saw no difference from what was
# already logged and never wrote a fresh, correctly-defaulted row. Request
# id 2243 (reported_by = "IMPACT (default - accessible until reported
# otherwise)", from this script's own flawed first attempt) was left as the
# permanent "latest" entry for that one ward, which analysis_sanity_check_
# accessibility_workflow.py's "Reported by" category check correctly caught
# as a FAIL. Fixed by appending one more corrected row (reported_by =
# "Partner", matching the other 6) directly to the log - safe in this one
# case since it's a metadata-only field (who reported it), not the
# accessibility determination itself, which 02_ingest's own content-diff
# already treats as unchanged either way. Lesson: don't reuse identical
# reason-note text across a log-only attempt and its later direct-file fix -
# it defeats the ingest step's own change detection.
# ==============================================================================
import csv
from datetime import date

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"

LOG_FIELDS = [
    "request_id", "date_added", "partner", "report_level", "state", "lga", "ward_name", "cluster_id", "pop_type",
    "source_channel", "reported_by", "accessible", "reason_category", "reason_notes", "pct_target_achieved",
    "date_reported_by_partner", "status", "resolution_mechanism", "resolution_date",
    "resolution_notes", "supersedes_request_id",
]

NOTE_TEMPLATE = (
    "This ward's GRID3 polygon disagrees with the official OCHA/COD LGA boundary at this point - GRID3 places it "
    "in {other_lga}, but OCHA/COD (the officially endorsed boundary source) places it in {home_lga}. Save the "
    "Children flagged this on the ground (email 2026-08-08/19); Jack re-verified all 54 similarly-flagged points "
    "directly against OCHA/COD on 2026-08-11 and retained the original LGA assignment for all of them - a genuine "
    "boundary-dataset disagreement at a contested edge, not a data-entry error - see the full reasoning in the raw "
    "email (resampling/input/partner_raw_comms/Save the Children/). No change to the sampling frame; ward remains "
    "accessible."
)

CORRECTIONS = [
    # (state, lga, ward_name, other_lga_named_by_partner)
    ("Katsina", "Mai'adua", "Gallu", "Mashi"),
    ("Katsina", "Mai'adua", "Sabon Gari", "Daura"),
    ("Katsina", "Mai'adua", "Bamle", "Mashi"),
    ("Katsina", "Mai'adua", "Ubandawaki A", "Daura"),
    ("Katsina", "Mai'adua", "Ubandawaki B", "Daura"),
    ("Katsina", "Zango", "Fago B", "Sandamu"),
    ("Katsina", "Zango", "Maibara", "Baure"),
]


def main():
    with open(LOG_CSV, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    next_id = max(int(r["request_id"]) for r in rows) + 1
    today = date.today().isoformat()

    new_rows = []
    for state, lga, ward, other_lga in CORRECTIONS:
        new_rows.append({
            "request_id": str(next_id), "date_added": today, "partner": "Save the Children",
            "report_level": "ward", "state": state, "lga": lga, "ward_name": ward, "cluster_id": "",
            "pop_type": "", "source_channel": "Point-level file annotation", "reported_by": "IMPACT (default - accessible until reported otherwise)",
            "accessible": "Yes", "reason_category": "N/A - fully accessible",
            "reason_notes": NOTE_TEMPLATE.format(other_lga=other_lga, home_lga=lga),
            "pct_target_achieved": "", "date_reported_by_partner": today, "status": "new",
            "resolution_mechanism": "manual_correction_patch_2026-08-28", "resolution_date": today,
            "resolution_notes": "Restores the specific boundary-disagreement reason note lost in an earlier "
                                 "regeneration (or, for Ubandawaki A, fills in the missing determination) - "
                                 "found while cross-checking Save the Children's 2026-08-26 email/attachment "
                                 "against the current record. No change to the underlying accessibility "
                                 "determination (all 7 were/remain Accessible=Yes).",
            "supersedes_request_id": "",
        })
        next_id += 1

    with open(LOG_CSV, "a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=LOG_FIELDS)
        for r in new_rows:
            writer.writerow(r)

    print(f"Appended {len(new_rows)} correction rows (request_id {new_rows[0]['request_id']}-{new_rows[-1]['request_id']}) to {LOG_CSV}")
    for r in new_rows:
        print(f"  {r['state']}/{r['lga']}/{r['ward_name']}")


if __name__ == "__main__":
    main()
