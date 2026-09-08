# ==============================================================================
# Builds ONE accessibility picture across the WHOLE sampling universe, not
# scoped to a single partner - the "master accessibility layer" (2026-08-25).
#
# Two purposes (per user, 2026-08-25):
# 1. Feeds the resampling policy decision (2026-08-24: an inaccessible ward is
#    treated as permanently OUTSIDE the sampling universe for its stratum,
#    same mechanism as the international border buffer - no reallocation into
#    it). That mechanism needs a single "is this ward currently in the
#    universe?" lookup; right now that answer only exists fragmented across 19
#    partner-scoped Excel files.
# 2. Feeds tomorrow's presentation to the global technical team on the current
#    extent of inaccessibility - needs a global, not per-partner, view.
#
# Default rule (explicit user instruction): every (State, LGA, Ward) portion
# in the WORKING frame's universe defaults to Accessible, and is flipped to
# Inaccessible only once a partner's ingested report says so. This is a
# GENUINE default (most of the universe hasn't been reported on yet - only a
# few of 19 partners have returned reports as of today), not a finding - see
# the "coverage caveat" columns below, which exist specifically so this
# distinction is never silently lost downstream.
#
# Ward rows are (State, LGA, Ward) - a partner's OWN LGA-scoped portion of a
# ward, never the bare ward name (2026-08-25 user clarification, restating the
# existing project-wide rule: GRID3 ward polygons don't nest cleanly inside
# LGA polygons, so a ward can genuinely span >1 LGA - see 01_generate_
# accessibility_reports.py's header and resampling/README.md). "Ward spans
# multiple LGAs" / "Other LGA(s) sharing this ward" columns make this visible
# on the sheet itself, not just in code comments - same fields 01 already
# shows per partner, reused here at the universe level.
#
# Ward-splitting logic (by_ward keyed on (adm1_name, adm2_name, adm3_name),
# one record per cluster x ward actually touched, target HH counted only from
# that ward's own household rows) is DELIBERATELY duplicated from 01, not
# imported - matches this project's existing standalone-script convention
# (e.g. build_partner_dc_packages.py's own note on this), and this script
# needs the UNION across all partners at once, not one partner's subset.
#
# Rerun-safe / idempotent by design: recomputes fully from the current WORKING
# frame + the current resampling_requests_log.csv every run, writes nothing
# incremental. Intended to be rerun after every new partner report is
# ingested via 02_ingest_accessibility_reports.py, as the user feeds more in
# through today's session - no state carried between runs.
#
# Two outputs (see "Not yet done" below for what's still a placeholder):
# - output/master_accessibility_status_ward_level.csv - the atomic layer.
# - output/master_accessibility_status_lga_level.csv - LGA/stratum rollup,
#   the grain the user said the tomorrow presentation actually needs. Columns
#   here are a FIRST PASS ONLY - user said they'll specify exactly what's
#   most useful (population count, % of area accessible, etc.) once they've
#   been through more partner reports; don't treat this as final.
# ==============================================================================
import csv
import glob
import os
from collections import defaultdict
from datetime import date, datetime

import openpyxl

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
# FULL, not WORKING (2026-09-01 fix - was WORKING right after the v2->v4
# path bump, which is circular for this specific script): build_universe()
# below defines the ward universe as "every ward with >=1 cluster in this
# frame" - v4 WORKING already excludes rows sitting in a currently-
# inaccessible ward, so building the universe FROM WORKING means a ward
# that's fully inaccessible (all its clusters stripped, e.g. every Dandume/
# Faskari ward) would vanish from this table entirely instead of showing
# as Inaccessible - the table can no longer show what it exists to show.
# FULL keeps every designed cluster regardless of current accessibility;
# filtered below to coverage_status=="covered" & exclusion_reason=="none"
# so population-floor/certainty-excluded strata still don't reappear.
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"
STRATA_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"
LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"
RETURNED_DIR = PROJECT_DIR + r"\resampling\input\accessibility_reports_returned"
WARD_OUT_CSV = PROJECT_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"
LGA_OUT_CSV = PROJECT_DIR + r"\resampling\output\master_accessibility_status_lga_level.csv"


def norm_pop_type(pt):
    return "Non-IDP" if pt == "non_idp" else "IDP"


def build_universe():
    """(State, LGA, Ward) universe across every partner at once, mirroring
    01_generate_accessibility_reports.py's per-cluster ward-splitting fix
    (2026-08-21) so the same cluster-spanning->1-ward case is handled
    correctly here too - a cluster's households are split by their OWN ward,
    never collapsed to one representative ward per cluster."""
    with open(STAGE2_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    # Exclude only never-in-scope rows (no partner ever covers this LGA) -
    # NOT population-floor/certainty-excluded ones. Those were genuinely
    # part of the active universe until a later decision dropped them, and
    # this table is a status/audit picture (has FACT reported this ward
    # accessible or not?), not a "what still needs action" list - that
    # distinction belongs to the impact workbook (05), which does drop them.
    # Dropping them here too would make e.g. every Dandume/Faskari ward
    # silently vanish from this table the moment the stratum was excluded,
    # losing the exact record used to confirm FACT's own 24 Aug report.
    rows = [r for r in rows if r.get("coverage_status") != "not_covered"]

    ward_to_lgas = defaultdict(set)
    for r in rows:
        ward_to_lgas[(r["adm1_name"], r["adm3_name"])].add(r["adm2_name"])
    ward_to_lgas = {k: sorted(v) for k, v in ward_to_lgas.items()}

    cluster_rows = defaultdict(list)
    for r in rows:
        cluster_rows[r["cluster_id"]].append(r)

    agg = defaultdict(lambda: {
        "ward_cod": "", "non_idp_clusters": set(), "idp_clusters": set(),
        "target_hh": 0, "partners": set(),
    })

    for cid, crows in cluster_rows.items():
        any_row = crows[0]
        partners = {p.strip() for p in any_row["partners_covering"].split(",") if p.strip() and p.strip() != "NA"}
        pop_type_norm = norm_pop_type(any_row["pop_type"])

        by_ward = defaultdict(lambda: {"primary": 0, "ward_cod": ""})
        for r in crows:
            key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
            w = by_ward[key]
            if r["status"] == "primary":
                w["primary"] += 1
            ward_cod = r.get("admin3_cod_name")
            if ward_cod and ward_cod != "NA":
                w["ward_cod"] = ward_cod

        for (state, lga, ward), w in by_ward.items():
            a = agg[(state, lga, ward)]
            a["ward_cod"] = w["ward_cod"]
            a["target_hh"] += w["primary"]
            a["partners"] |= partners
            if pop_type_norm == "Non-IDP":
                a["non_idp_clusters"].add(cid)
            else:
                a["idp_clusters"].add(cid)

    return agg, ward_to_lgas


def latest_ward_reports():
    """Latest (highest request_id) non-superseded-in-spirit ward-level log
    row per (partner, state, lga, ward_name) - same key/latest-wins logic as
    02_ingest_accessibility_reports.py's own latest_by_key(), scoped to
    report_level == 'ward' only (cluster-level requests don't affect universe
    membership under the 2026-08-24 policy - only ward-wide exclusion does)."""
    try:
        with open(LOG_CSV, encoding="utf-8", newline="") as f:
            log_rows = list(csv.DictReader(f))
    except FileNotFoundError:
        return {}

    latest = {}
    for r in log_rows:
        if r["report_level"] != "ward":
            continue
        key = (r["partner"], r["state"], r["lga"], r["ward_name"])
        if key not in latest or int(r["request_id"]) > int(latest[key]["request_id"]):
            latest[key] = r
    return latest


def wards_present_in_returned_files():
    """{partner: {(state, lga, ward), ...}} - every ward that actually
    APPEARS AS A ROW in that partner's current returned file, regardless of
    whether Accessible/Reason was filled in. Replaces the old per-PARTNER
    'did they return anything at all' check (2026-08-26), found 2026-08-27
    to be wrong: it treated a partner's ENTIRE current assignment as
    'reviewed, nothing flagged' the moment they returned ANY report, with no
    check that a given ward was actually part of what they returned.
    Confirmed live and wrong for FACT specifically - 189 wards currently
    assigned to FACT were never rows in their returned file at all (a known,
    separately-tracked gap - see the FACT cleaned-listing workbook's "Issues
    to Review" sheet), yet were showing as "confirmed_by_partner_report
    (blank row - not flagged)" here, silently overstating how much of
    FACT's area has actually been reviewed. This is now a per-(partner,
    ward) fact - was this SPECIFIC ward a row in what they returned - not a
    per-partner fact, closing that gap for FACT and for any future partner
    whose assignment grows after they've already reported.

    Reads directly from accessibility_reports_returned/ rather than the
    master log, because the log only stores rows 02_ingest_accessibility_
    reports.py actually logs (Accessible or Reason non-blank) - a row that's
    genuinely blank-but-present in the partner's file and a row that was
    never present at all are equally invisible to the log, so only the
    returned file itself can tell them apart."""
    out = defaultdict(set)
    for path in glob.glob(os.path.join(RETURNED_DIR, "*_accessibility_report.xlsx")):
        partner = os.path.basename(path)[: -len("_accessibility_report.xlsx")]
        try:
            wb = openpyxl.load_workbook(path, data_only=True)
        except Exception as e:
            print(f"  WARNING: could not read {path} for ward-presence check: {e}")
            continue
        if "Ward Accessibility" not in wb.sheetnames:
            continue
        ws = wb["Ward Accessibility"]
        headers = [c.value for c in ws[1]]
        idx = {h: i for i, h in enumerate(headers)}
        for row in ws.iter_rows(min_row=2, values_only=True):
            ward = row[idx["Ward (GRID3)"]] if "Ward (GRID3)" in idx else None
            if ward:
                out[partner].add((row[idx["State"]], row[idx["LGA"]], ward))
    return dict(out)


DATE_FORMATS = ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d/%m/%Y")


def parse_date_flexible(raw, today):
    """Tries every known date format this workflow's partners have actually
    used (checked directly against the log, 2026-08-27: 1,749 DD/MM/YYYY,
    239 YYYY-MM-DD, 31 with a time component, plus rare garbage like a
    literal 'Date reported' header value). A parsed date AFTER today is
    treated as unparseable too, not a real future date - this is the known
    FACT Excel-autofill-drag corruption (see resampling/README.md), which
    checked directly affects 451 rows, some drifting as far as the year
    2261. Deliberately excluded rather than guessed at a "real" date -
    matches this project's standing rule of never inventing a corrected
    value for known-corrupted partner data (see patch_fact_report_2026-08-
    26.py's own precedent: flagged to the partner, not invented)."""
    if not raw:
        return None
    raw = raw.strip()
    for fmt in DATE_FORMATS:
        try:
            d = datetime.strptime(raw, fmt).date()
        except ValueError:
            continue
        return d if d <= today else None
    return None


def summarize_reported_by(reps, covering_partners_with_ward_present):
    """One of: 'Partner' (every contributing report/coverage is partner-
    sourced), 'Needs review' (every one is an unclassified log row - see
    patch_add_reported_by_column.py), a semicolon-joined mix of both, or
    None (caller substitutes 'Not yet reported' - no reps and no partner
    coverage at all)."""
    if reps:
        vals = {(r.get("reported_by") or "Needs review") for r in reps}
        return "; ".join(sorted(vals))
    if covering_partners_with_ward_present:
        return "Partner"
    return None


def summarize_last_reported_date(reps, today):
    """Most recent VALID (parseable, not-in-the-future) date among this
    ward's reports, as an ISO string - or 'Unknown (see Date reported by
    partner column)' if reports exist but every date is unparseable/
    corrupted (a real, distinguishable case from 'never reported' - see
    parse_date_flexible()'s docstring), or '' if there are no reports at
    all."""
    if not reps:
        return ""
    parsed = [parse_date_flexible(r.get("date_reported_by_partner"), today) for r in reps]
    valid = [d for d in parsed if d]
    if valid:
        return max(valid).isoformat()
    return "Unknown (see Date reported by partner column)"


def build_ward_level(agg, ward_to_lgas, ward_reports, wards_present_by_partner):
    today = date.today()
    # Group latest ward reports by (state, lga, ward) - usually one partner,
    # but a dual-coverage LGA (e.g. Sokoto/Isa: DRC + IRC/LHI) could carry
    # more than one report for the physically same ward portion.
    reports_by_ward = defaultdict(list)
    for (partner, state, lga, ward), rep in ward_reports.items():
        reports_by_ward[(state, lga, ward)].append(rep)

    out = []
    for (state, lga, ward), a in agg.items():
        other_lgas = [l for l in ward_to_lgas.get((state, ward), [lga]) if l != lga]
        reps = reports_by_ward.get((state, lga, ward), [])
        # Conservative per the 2026-08-24 policy: if ANY partner covering
        # this specific LGA-scoped ward portion has reported it inaccessible,
        # treat the portion as outside the universe - not an average/majority
        # call across reports.
        any_no = any(r["accessible"].strip().lower() == "no" for r in reps)
        status = "Inaccessible" if any_no else "Accessible"

        # Confirmed if EITHER this specific ward has an explicit logged row,
        # OR this specific ward was actually a ROW (filled or not) in the
        # returned file of a partner covering it (2026-08-27 fix - see
        # wards_present_in_returned_files()'s docstring for why this must be
        # per-ward, not per-partner). The latter case still defaults the
        # status itself to Accessible (no explicit statement exists for this
        # exact ward), only the SOURCE label changes.
        ward_key = (state, lga, ward)
        covering_partners_with_ward_present = {
            p for p in a["partners"] if ward_key in wards_present_by_partner.get(p, set())
        }
        if reps:
            source = "confirmed_by_partner_report"
        elif covering_partners_with_ward_present:
            source = "confirmed_by_partner_report (blank row - not flagged)"
        else:
            source = "default_unreported"

        reported_by = summarize_reported_by(reps, covering_partners_with_ward_present) or "Not yet reported"

        out.append({
            "State": state, "LGA": lga, "Ward (GRID3)": ward, "Ward (OCHA/COD)": a["ward_cod"],
            "Ward spans multiple LGAs (Y/N)": "Yes" if other_lgas else "No",
            "Other LGA(s) sharing this ward": "; ".join(other_lgas),
            "Partners covering this LGA-ward portion": "; ".join(sorted(a["partners"])),
            "Non-IDP clusters": len(a["non_idp_clusters"]), "IDP clusters": len(a["idp_clusters"]),
            "Total target HHs (primary)": a["target_hh"],
            "Accessible status": status,
            "Status source": source,
            "Reporting partner(s)": "; ".join(sorted({r["partner"] for r in reps})),
            "Reported by": reported_by,
            "Reason category": "; ".join(sorted({r["reason_category"] for r in reps if r["reason_category"]})),
            "Reason notes": " | ".join(r["reason_notes"] for r in reps if r["reason_notes"]),
            "Date reported by partner": "; ".join(sorted({r["date_reported_by_partner"] for r in reps if r["date_reported_by_partner"]})),
            "Last reported date": summarize_last_reported_date(reps, today),
            "% target achieved so far (as reported)": "; ".join(sorted({r["pct_target_achieved"] for r in reps if r["pct_target_achieved"]})),
        })

    out.sort(key=lambda r: (r["State"], r["LGA"], -r["Total target HHs (primary)"], r["Ward (GRID3)"]))
    return out


def build_lga_level(ward_rows):
    """FIRST-PASS rollup only - user to confirm exact columns wanted for the
    tomorrow presentation (population count, % area accessible, etc. already
    flagged by the user as coming). Grain: (State, LGA). Population/sample
    figures joined in from the strata CSV per pop_type since that's this
    project's native stratum grain (LGA x pop_type), shown as two column
    groups rather than collapsed into one, since a ward being inaccessible
    doesn't inherently split by pop_type."""
    agg = defaultdict(lambda: {"total_wards": 0, "inaccessible_wards": 0,
                                "total_target_hh": 0, "inaccessible_target_hh": 0,
                                "partners": set(), "reported_by": set(), "dates": []})
    for r in ward_rows:
        a = agg[(r["State"], r["LGA"])]
        a["total_wards"] += 1
        a["total_target_hh"] += r["Total target HHs (primary)"]
        a["partners"] |= {p for p in r["Partners covering this LGA-ward portion"].split("; ") if p}
        if r["Accessible status"] == "Inaccessible":
            a["inaccessible_wards"] += 1
            a["inaccessible_target_hh"] += r["Total target HHs (primary)"]
        # "Reported by"/"Last reported date" rolled up from the per-ward
        # values already computed above - a LGA mixing e.g. some Partner-
        # reported and some not-yet-reported wards shows both, joined (this
        # is the expected, common case for a LGA with several wards, not an
        # error - see resampling/README.md's 2026-08-27 note on this).
        a["reported_by"] |= set(r["Reported by"].split("; "))
        if r["Last reported date"] and not r["Last reported date"].startswith("Unknown"):
            a["dates"].append(r["Last reported date"])

    with open(STRATA_CSV, encoding="utf-8") as f:
        strata_rows = list(csv.DictReader(f))
    strata_by_lga_pop = defaultdict(list)
    for r in strata_rows:
        strata_by_lga_pop[(r["adm1_name"], r["adm2_name"])].append(r)

    out = []
    for (state, lga), a in agg.items():
        pct_wards = round(100 * a["inaccessible_wards"] / a["total_wards"], 1) if a["total_wards"] else 0
        pct_hh = round(100 * a["inaccessible_target_hh"] / a["total_target_hh"], 1) if a["total_target_hh"] else 0
        srows = strata_by_lga_pop.get((state, lga), [])
        non_idp = next((s for s in srows if s["pop_type"] == "non_idp"), None)
        idp = next((s for s in srows if s["pop_type"] == "idp"), None)
        out.append({
            "State": state, "LGA": lga,
            "Partners covering": "; ".join(sorted(a["partners"])),
            "Total wards (LGA-scoped portions)": a["total_wards"],
            "Wards reported inaccessible": a["inaccessible_wards"],
            "% of wards inaccessible (by count)": pct_wards,
            "% of target HHs inaccessible (by ward, weighted)": pct_hh,
            "Reported by (across all wards)": "; ".join(sorted(a["reported_by"])),
            "Most recent report date (across all wards)": max(a["dates"]) if a["dates"] else "",
            "Non-IDP: population (n_pop)": non_idp["n_pop"] if non_idp else "",
            "Non-IDP: N_hh": non_idp["N_hh"] if non_idp else "",
            "Non-IDP: realized MoE %": non_idp["realized_moe_pct"] if non_idp else "",
            "IDP: population (n_pop)": idp["n_pop"] if idp else "",
            "IDP: N_hh": idp["N_hh"] if idp else "",
            "IDP: realized MoE %": idp["realized_moe_pct"] if idp else "",
        })

    out.sort(key=lambda r: (-r["% of wards inaccessible (by count)"], r["State"], r["LGA"]))
    return out


def write_csv(path, rows):
    if not rows:
        print(f"Nothing to write for {path}")
        return
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {path}")


def main():
    agg, ward_to_lgas = build_universe()
    ward_reports = latest_ward_reports()
    wards_present_by_partner = wards_present_in_returned_files()
    ward_rows = build_ward_level(agg, ward_to_lgas, ward_reports, wards_present_by_partner)
    lga_rows = build_lga_level(ward_rows)

    write_csv(WARD_OUT_CSV, ward_rows)
    write_csv(LGA_OUT_CSV, lga_rows)

    n_reported = sum(1 for r in ward_rows if r["Status source"].startswith("confirmed_by_partner_report"))
    n_explicit = sum(1 for r in ward_rows if r["Status source"] == "confirmed_by_partner_report")
    n_inaccessible = sum(1 for r in ward_rows if r["Accessible status"] == "Inaccessible")
    print(f"\n{len(ward_rows)} LGA-scoped ward portions in the universe.")
    print(f"{n_reported} confirmed by a partner report ({n_explicit} with an explicit answer, "
          f"{n_reported - n_explicit} present-but-blank in a returned file; "
          f"{len(wards_present_by_partner)} partner(s) have a returned file: "
          f"{', '.join(sorted(wards_present_by_partner))}).")
    print(f"{n_inaccessible} currently flagged Inaccessible.")
    print(f"{len(ward_rows) - n_reported} still on the default Accessible status (not yet reported on).")


if __name__ == "__main__":
    main()
