# ==============================================================================
# QA pass over every file currently sitting in accessibility_reports_returned/,
# BEFORE running 02_ingest_accessibility_reports.py on them. Read-only - writes
# nothing, just prints findings per partner so a human can decide what's safe
# to ingest as-is vs. needs a fix or a question back to the partner first.
#
# Checks, per partner file:
# 1. Completeness - every (State, LGA, Ward) actually SENT to this partner (the
#    canonical file in accessibility_reports_generated/) has a matching Ward
#    Accessibility row in what came back. Flags any missing, or any extra.
#
#    METHODOLOGY CORRECTION (2026-09-08, caught by Jack on FACT's returned
#    report): this used to compare against the *current, live* WORKING frame's
#    partners_covering (build_partner_ward_universe(), below) instead of what
#    was actually sent. That baseline drifts every time a stratum is dropped or
#    added after the report was generated - caught because FACT's report showed
#    294 "EXTRA" + 51 "MISSING" findings that looked alarming, but checking
#    archived frame versions showed FACT's WORKING-based ward count had moved
#    1,160 (v2) -> 1,074 (v3) -> 867 (v4) -> 843 (v5) -> 901 (v6, tonight's
#    redraw) through several unrelated resampling rounds since their report was
#    generated (Sep 2, ~1,067 wards). Direct check: FACT's return matched
#    1,067/1,067 of what was actually sent, plus 77 genuinely-extra wards - not
#    294. build_sent_ward_universe() (below) is the corrected baseline; the old
#    WORKING-based function is kept only as a still-useful, separate concept
#    (which wards a partner currently has clusters in per WORKING right now),
#    not as the completeness comparison.
# 2. Duplicate ward rows (same State/LGA/Ward appearing more than once).
# 3. Partial answers - Accessible filled but Reason category blank, or the
#    reverse (excluding "N/A - fully accessible" which legitimately pairs with
#    Yes and no notes).
# 4. Yes/No vs reason-text contradiction - keyword scan for insecurity/access-
#    denial language on a row marked Accessible=Yes, or "N/A - fully
#    accessible"/empty-sounding reason text on a row marked Accessible=No.
# 5. Geospatial/map-identification triage (per README, decided 2026-08-21) -
#    a No row whose reason text reads like a map/GPS-tool problem ("not on
#    the map", "doesn't match", "wrong LGA/ward name") rather than a genuine
#    access problem. These should NOT be logged as inaccessible per that
#    policy - flagged here so they get corrected/excluded before ingest, not
#    caught after.
# 6. Cluster Accessibility rows whose (State, LGA, Ward) has no corresponding
#    Ward Accessibility row at all in the same file (orphaned cluster claim).
# 7. pct_target_achieved out of [0, 100] where present.
#
# This is a read-only QA tool, not part of the numbered 00-08 core sequence -
# rerun any time new files land in accessibility_reports_returned/.
# ==============================================================================
import csv
import glob
import os
import re
from collections import defaultdict

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING.csv"
RETURNED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned"
GENERATED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_generated"

MAP_ISSUE_PATTERNS = [
    r"not on (the |a )?map", r"doesn'?t match", r"wrong lga", r"wrong ward",
    r"different lga", r"different ward", r"kml", r"maps\.me", r"gps (point|tool|issue)",
    r"map (issue|error|problem)", r"actually (in|belongs to)",
]
ACCESS_DENIAL_PATTERNS = [
    r"insecur", r"inaccess", r"denied", r"conflict", r"unsafe", r"attack",
    r"kidnap", r"bandit", r"displac", r"flood", r"blocked", r"no[- ]go",
    # Widened 2026-09-08: FACT's Bachaka/Kuka rows ("...team had to be
    # evacuated this morning as gun men opened fire...") scored Accessible=Yes
    # with no CONTRADICTION flag, because the only denial-sounding word
    # ("conflict") was in the Reason category dropdown, not the notes text
    # this scan actually reads. Caught by Jack asking for the two rows'
    # own Yes/No rather than trusting the original 19-item list was complete.
    r"evacuat", r"gun[- ]?men", r"opened fire", r"gunfire", r"shoot",
    r"ambush", r"abduct", r"raid", r"clash", r"armed group",
]


def norm(s):
    return (s or "").strip()


def build_partner_ward_universe():
    """{(partner, State, LGA, Ward (GRID3))} that partner genuinely has
    clusters in, per the same ward-splitting logic 01/04 already use -
    duplicated here per this project's standalone-script convention."""
    with open(STAGE2_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    cluster_rows = defaultdict(list)
    for r in rows:
        cluster_rows[r["cluster_id"]].append(r)

    universe = set()
    for cid, crows in cluster_rows.items():
        any_row = crows[0]
        partners = {p.strip() for p in any_row["partners_covering"].split(",") if p.strip() and p.strip() != "NA"}
        wards_touched = {(r["adm1_name"], r["adm2_name"], r["adm3_name"]) for r in crows}
        for p in partners:
            for (state, lga, ward) in wards_touched:
                universe.add((p, state, lga, ward))
    return universe


def build_sent_ward_universe():
    """{(partner, State, LGA, Ward (GRID3))} from the canonical report actually
    generated and sent to each partner (accessibility_reports_generated/,
    current file only - dated/followup snapshot copies excluded, same filter as
    the returned-file scan below). This is the correct completeness baseline:
    what a partner reported should be checked against what they were asked
    about, not against whatever the live WORKING frame contains today. See the
    2026-09-08 methodology-correction note in this file's header comment."""
    files = sorted(glob.glob(os.path.join(GENERATED_DIR, "*_accessibility_report.xlsx")))
    files = [f for f in files if not re.search(r"_\d{4}-\d{2}-\d{2}\.xlsx$", f)]

    universe = set()
    for path in files:
        partner = os.path.basename(path)[: -len("_accessibility_report.xlsx")]
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
        if "Ward Accessibility" not in wb.sheetnames:
            wb.close()
            continue
        ws = wb["Ward Accessibility"]
        headers = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
        idx = {h: i for i, h in enumerate(headers) if h}
        for row in ws.iter_rows(min_row=2, values_only=True):
            if all(v is None for v in row):
                continue
            state = norm(row[idx["State"]]) if "State" in idx else ""
            lga = norm(row[idx["LGA"]]) if "LGA" in idx else ""
            ward = norm(row[idx["Ward (GRID3)"]]) if "Ward (GRID3)" in idx else ""
            if state and lga and ward:
                universe.add((partner, state, lga, ward))
        wb.close()
    return universe


def read_sheet(ws):
    headers = [c.value for c in ws[1]]
    idx = {h: i for i, h in enumerate(headers)}
    out = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        if all(v is None for v in row):
            continue
        rec = {h: row[i] for h, i in idx.items()}
        out.append(rec)
    return rec_list_clean(out)


def rec_list_clean(recs):
    return recs


def matches_any(text, patterns):
    t = (text or "").lower()
    return any(re.search(p, t) for p in patterns)


def review_partner(path):
    partner = os.path.basename(path)[: -len("_accessibility_report.xlsx")]
    findings = []
    try:
        wb = openpyxl.load_workbook(path, data_only=True)
    except Exception as e:
        return partner, [f"COULD NOT OPEN FILE: {e}"]

    ward_rows = read_sheet(wb["Ward Accessibility"]) if "Ward Accessibility" in wb.sheetnames else []
    cluster_rows = read_sheet(wb["Cluster Accessibility"]) if "Cluster Accessibility" in wb.sheetnames else []

    seen_wards = set()
    reported_wards = set()
    for r in ward_rows:
        state, lga, ward = norm(r.get("State")), norm(r.get("LGA")), norm(r.get("Ward (GRID3)"))
        key = (state, lga, ward)
        accessible = norm(r.get("Accessible (Y/N)"))
        reason = norm(r.get("Reason category"))
        notes = norm(r.get("Reason notes"))
        pct = r.get("% of target achieved so far")

        if not any(key):
            continue

        if key in seen_wards:
            findings.append(f"DUPLICATE ward row: {state}/{lga}/{ward}")
        seen_wards.add(key)

        if accessible:
            reported_wards.add(key)

        if accessible and not reason:
            findings.append(f"PARTIAL: {state}/{lga}/{ward} - Accessible={accessible} but Reason category blank")
        if reason and not accessible:
            findings.append(f"PARTIAL: {state}/{lga}/{ward} - Reason category='{reason}' but Accessible blank")

        if accessible.lower() == "yes" and matches_any(notes, ACCESS_DENIAL_PATTERNS):
            findings.append(f"CONTRADICTION: {state}/{lga}/{ward} - marked Accessible=Yes but notes read like an "
                             f"access problem: \"{notes[:120]}\"")
        if accessible.lower() == "no" and (reason == "N/A - fully accessible"):
            findings.append(f"CONTRADICTION: {state}/{lga}/{ward} - marked Accessible=No but Reason category is "
                             f"'N/A - fully accessible'")

        if accessible.lower() == "no" and matches_any(notes, MAP_ISSUE_PATTERNS) and not matches_any(notes, ACCESS_DENIAL_PATTERNS):
            findings.append(f"MAP/GPS TRIAGE (per 2026-08-21 policy - should NOT be logged as inaccessible): "
                             f"{state}/{lga}/{ward} - \"{notes[:120]}\"")

        if pct not in (None, ""):
            try:
                pctf = float(pct)
                if not (0 <= pctf <= 100):
                    findings.append(f"OUT-OF-RANGE %: {state}/{lga}/{ward} - % target achieved = {pct}")
            except (TypeError, ValueError):
                findings.append(f"NON-NUMERIC %: {state}/{lga}/{ward} - % target achieved = '{pct}'")

    for r in cluster_rows:
        state, lga, ward = norm(r.get("State")), norm(r.get("LGA")), norm(r.get("Ward (GRID3)"))
        key = (state, lga, ward)
        if not any(key):
            continue
        if key not in seen_wards:
            findings.append(f"ORPHANED cluster row: {state}/{lga}/{ward} / cluster {r.get('Cluster ID')} - "
                             f"no matching Ward Accessibility row in this same file")

    return partner, findings, reported_wards, seen_wards


def main():
    universe = build_sent_ward_universe()
    files = sorted(glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx")))
    # Skip dated snapshot copies (YYYY-MM-DD suffix) - only review the canonical file per partner.
    files = [f for f in files if not re.search(r"_\d{4}-\d{2}-\d{2}\.xlsx$", f)]

    for path in files:
        partner, findings, reported_wards, seen_wards = review_partner(path)
        expected = {k[1:] for k in universe if k[0] == partner}
        missing = expected - seen_wards
        extra = seen_wards - expected

        print(f"\n{'='*70}\n{partner}\n{'='*70}")
        print(f"Ward rows in file: {len(seen_wards)} | Expected (per what was actually sent): {len(expected)}")
        if missing:
            print(f"MISSING {len(missing)} sent ward row(s) not in file:")
            for m in sorted(missing):
                print(f"  - {'/'.join(m)}")
        if extra:
            print(f"{len(extra)} ward row(s) in file beyond what was sent to this partner (typo / wrong partner / partner-initiated expansion?):")
            for e in sorted(extra):
                print(f"  - {'/'.join(e)}")
        if findings:
            print(f"{len(findings)} finding(s):")
            for f in findings:
                print(f"  - {f}")
        else:
            print("No row-level issues found.")


if __name__ == "__main__":
    main()
