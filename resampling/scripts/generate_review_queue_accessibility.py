"""
generate_review_queue_accessibility.py - the "classify + stage" half of the
shared review-queue engine (2026-09-08 rebuild), accessibility side.
Counterpart to 2_monitoring's generate_review_queue.R (deletion side) -
same output shape, so a session presenting both domains to Jack can use one
consistent format.

Reuses analysis_review_returned_reports.py's own review_partner() and
build_partner_ward_universe() by import, not duplication - that script
already does exactly the classification work needed (partial answers,
contradictions, map/GPS triage, orphaned rows, missing/extra ward coverage);
this wrapper's only job is grouping those findings the same way the deletion
side groups its own review items, and writing them to the shared JSON shape
instead of printing to stdout.

Grouping: by (partner, finding_type) - finding_type extracted from each
finding string's own leading label (PARTIAL / CONTRADICTION / DUPLICATE /
etc.), already a clean, consistent prefix in every finding
analysis_review_returned_reports.py produces.

There is currently no "confirmed" (auto-applied) bucket on this side, unlike
deletion - accessibility rules 1/2 (never-reported defaults Accessible;
previously-reported persists unless explicitly re-stated) are applied
directly by 04_build_master_accessibility_status.py at ingest time, not
staged for review, since neither is a judgment call. Only the QA findings
below are.

Usage: python generate_review_queue_accessibility.py [output_path]
"""
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analysis_review_returned_reports import (  # noqa: E402
    RETURNED_DIR, build_sent_ward_universe, review_partner,
)
import glob  # noqa: E402


# First run of ALL-CAPS word(s) at the start of a finding string (e.g.
# "PARTIAL", "MISSING ward row" -> "MISSING", "MAP/GPS TRIAGE" -> "MAP/GPS
# TRIAGE") - takes only the leading all-caps tokens, not the whole phrase up
# to the colon, so a mixed-case tail ("ward row:") doesn't break the match.
FINDING_TYPE_RE = re.compile(r"^([A-Z][A-Z/\-]*(?:\s[A-Z][A-Z/\-]*)*)")


def finding_type(finding_text):
    m = FINDING_TYPE_RE.match(finding_text)
    return m.group(1).strip() if m else "OTHER"


def generate_review_queue_accessibility(output_path=None):
    universe = build_sent_ward_universe()
    files = sorted(glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx")))
    files = [f for f in files if not re.search(r"_\d{4}-\d{2}-\d{2}\.xlsx$", f)]

    queue = {}
    for path in files:
        partner, findings, reported_wards, seen_wards = review_partner(path)
        expected = {k[1:] for k in universe if k[0] == partner}
        missing = expected - seen_wards
        extra = seen_wards - expected

        all_findings = list(findings)
        for m in sorted(missing):
            all_findings.append(f"MISSING ward row: {'/'.join(m)} (sent to this partner, not in returned file)")
        for e in sorted(extra):
            all_findings.append(f"EXTRA ward row: {'/'.join(e)} (in file, beyond what was sent to this partner - typo, wrong partner, or partner-initiated expansion?)")

        groups = defaultdict(list)
        for f in all_findings:
            groups[finding_type(f)].append(f)

        queue[partner] = {
            "org_id": partner,
            "ward_rows_in_file": len(seen_wards),
            "ward_rows_expected": len(expected),
            "needs_review": {
                "total": len(all_findings),
                "groups": [
                    {"finding_type": ftype, "n": len(items), "examples": items[:5]}
                    for ftype, items in sorted(groups.items(), key=lambda kv: -len(kv[1]))
                ],
            },
        }

    if output_path is None:
        out_dir = os.path.join(os.path.dirname(RETURNED_DIR), "..", "output", "_review_queue_accessibility")
        out_dir = os.path.normpath(out_dir)
        os.makedirs(out_dir, exist_ok=True)
        output_path = os.path.join(out_dir, f"{datetime.now().strftime('%Y-%m-%d')}.json")

    partners_with_review = [p for p, v in queue.items() if v["needs_review"]["total"] > 0]
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({
            "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "partners_with_pending_review": partners_with_review,
            "queue": queue,
        }, f, indent=2)

    total_findings = sum(v["needs_review"]["total"] for v in queue.values())
    print(f"generate_review_queue_accessibility(): wrote {output_path}")
    print(f"{len(partners_with_review)} partner(s) have findings needing review, {total_findings} total across "
          f"{sum(len(v['needs_review']['groups']) for v in queue.values())} group(s).")
    return output_path


if __name__ == "__main__":
    generate_review_queue_accessibility(sys.argv[1] if len(sys.argv) > 1 else None)
