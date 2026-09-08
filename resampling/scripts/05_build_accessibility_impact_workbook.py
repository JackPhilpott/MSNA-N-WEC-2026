# ==============================================================================
# Builds the stratum/LGA-level accessibility-extent report for the
# 2026-08-25 technical-team meeting: how much of each stratum's area/
# population/clusters/sample sits inside the currently-accessible portion of
# its LGA, using the EXISTING delivered clusters (no new draw) - see
# analysis_accessible_area_layer.R's header for why this is a standalone
# recompute, not a pipeline rerun.
#
# Reconciling two population sources (deliberate, not an oversight): the
# strata CSV's own n_pop/N_hh (Stage 1's hex-clipped WorldPop aggregation,
# already vetted/used throughout the methodology doc) is kept as the
# authoritative TOTAL. The new ward-clipped GIS layer (analysis_accessible_
# area_layer.R's output) is used only to derive the ACCESSIBLE FRACTION of
# that total (accessible ward-portion population / total ward-portion
# population within the same LGA) - because the two layers clip on different
# boundaries (hex vs ward) their absolute totals don't match exactly, but the
# fraction is internally consistent (numerator and denominator computed the
# same way) and lets "updated population" be reported as n_pop * fraction,
# never as two different, confusing absolute totals for the same LGA. Area
# has no pre-existing authoritative figure to reconcile against, so area
# figures come directly from the new GIS layer.
#
# Clusters/samples are classified directly, not scaled by a fraction: each
# PRIMARY household row's own (State, LGA, Ward) is looked up against the
# master ward-level accessible status - a hard count, not an estimate. A
# cluster counts as "within the accessible area" if it has at least one
# accessible primary household (clusters spanning >1 ward are rare but real -
# see the known ward-splitting fix in 01_generate_accessibility_reports.py;
# treating any partially-accessible cluster as operable, not excluded
# wholesale, matches how field teams would actually treat it).
#
# realized_moe() is ported verbatim from 01_sampling_pipeline_main.R (same
# formula, same defaults) - a summary-statistic formula, not something that
# needs cluster reselection, so it's valid to apply directly to the
# accessible-only achieved_sample/N_hh figures computed here.
#
# "Collected samples" = real_submissions.csv, interview_outcome == "completed"
# AND any_quality_flag == "FALSE" (per user decision 2026-08-25) - both
# primary- and reserve-slot completions count (a reserve interview replacing
# a non-responding primary is still a genuine collected interview toward the
# stratum's target).
# ==============================================================================
import csv
import math
import os
from collections import defaultdict

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
SAMPLING_DIR = PROJECT_DIR + r"\1_sampling"
# FULL, not WORKING (2026-09-01 fix - was WORKING right after the v2->v4
# path bump, which is wrong for this script specifically): v4 WORKING now
# excludes both achieved households AND rows sitting in a currently-
# inaccessible ward - but THIS script's whole job is to compute accessible
# vs inaccessible and achieved vs not, using the master ward status and
# real_submissions.csv itself. Reading WORKING here would silently make
# every remaining row look "Accessible" (the inaccessible ones are already
# gone) and undercount achieved households in acc_capacity - i.e. it would
# quietly break the "Additional clusters needed"/"Feasibility" columns
# that extract_partner_shortfalls.R depends on for every future resampling
# round. Filtered below to coverage_status=="covered" & exclusion_reason
# =="none" to still exclude population-floor/certainty-excluded strata,
# which genuinely shouldn't reappear here.
STRATA_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"
HOUSEHOLD_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v7_FULL.csv"
MASTER_WARD_CSV = SAMPLING_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"
GIS_WARD_CSV = SAMPLING_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
POOL_NON_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_non_idp.csv"
POOL_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_idp.csv"
REAL_SUBMISSIONS_CSV = PROJECT_DIR + r"\2_monitoring\dashboard_app\data\real_submissions.csv"

# 2026-09-06: repointed from the abandoned revised_deletion_log_for_resampling_
# *.csv handoff (2_monitoring/cleaning/real/handoff_for_resampling/ - last fed
# 2026-08-30_v2, 8 days stale by the time this was caught) to
# CONFIRMED_DELETIONS_OVERLAY.csv - its deliberate, version-stamped
# replacement, built from 2_monitoring's recovery_issue_tracker.csv. Verified
# before repointing (not just per the orchestrator's word): join key is
# "uuid" on both sides, same as the old log; row counts/status breakdown
# checked directly against the file on disk. Only status=="confirmed" rows
# count as deletions - the overlay also carries "contested" rows (10 as of
# this writing, none finalized either way) that must NOT be treated as
# deleted, per Jack's explicit policy: deletion confirmation requires a
# genuine, deliberate decision (partner recovery-workbook response or a
# reviewed internal call), never an automatic default.
CONFIRMED_DELETIONS_OVERLAY_CSV = PROJECT_DIR + r"\2_monitoring\data\CONFIRMED_DELETIONS_OVERLAY.csv"
if not os.path.exists(CONFIRMED_DELETIONS_OVERLAY_CSV):
    raise FileNotFoundError(f"CONFIRMED_DELETIONS_OVERLAY.csv not found at {CONFIRMED_DELETIONS_OVERLAY_CSV}")
print(f"Using confirmed-deletions overlay: {os.path.basename(CONFIRMED_DELETIONS_OVERLAY_CSV)}")

TARGET_MOE_PCT = 10.0

OUT_DIR = SAMPLING_DIR + r"\resampling\output"
WORKBOOK_PATH = OUT_DIR + r"\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
UPDATED_FRAME_CSV = OUT_DIR + r"\NGA_MSNA_2026_stage2_sampling_frame_v7_WORKING_with_accessibility.csv"


def realized_moe(achieved_sample, N_hh, m, ICC=0.06, Z=1.6448536269514722, p=0.5):
    """Port of 01_sampling_pipeline_main.R's realized_moe() - same formula,
    same defaults (Z = qnorm(0.95))."""
    if achieved_sample <= 0 or N_hh <= achieved_sample:
        return None
    deff = 1 + (m - 1) * ICC
    ndeff = achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
    n0 = ndeff / deff
    if n0 <= 0:
        return None
    return math.sqrt(Z ** 2 * p * (1 - p) / n0) * 100


def sample_needed_for_moe(target_moe_pct, N_hh, m, ICC=0.06, Z=1.6448536269514722, p=0.5):
    """Inverts realized_moe() - the achieved_sample needed to hit
    target_moe_pct against a population of N_hh, keeping m fixed (per the
    2026-07-22 lesson: raise cluster COUNT, not cluster SIZE - see this
    script's module docstring). Returns None if N_hh is too small for the
    formula to be meaningful (finite-population correction requires N_hh > 1)."""
    if N_hh is None or N_hh <= 1:
        return None
    deff = 1 + (m - 1) * ICC
    target_moe = target_moe_pct / 100
    n0_needed = (Z ** 2) * p * (1 - p) / (target_moe ** 2)
    ndeff_needed = n0_needed * deff
    # invert ndeff = n*(N-1)/(N-n)  =>  n = ndeff*N / (ndeff + N - 1)
    achieved_needed = ndeff_needed * N_hh / (ndeff_needed + N_hh - 1)
    return min(achieved_needed, N_hh)  # can never need to sample more than exists


def load_pool_lookup(path, pool_field):
    rows = load_csv(path)
    return {r["adm2_pcode"]: int(float(r[pool_field])) for r in rows}


def load_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_ward_status_lookup():
    """(State, LGA, Ward) -> 'Accessible'/'Inaccessible', from the master
    ward-level status file (already reconciles every ingested partner
    report)."""
    rows = load_csv(MASTER_WARD_CSV)
    return {(r["State"], r["LGA"], r["Ward (GRID3)"]): r["Accessible status"] for r in rows}


def load_ward_provenance_lookup():
    """(State, LGA, Ward) -> ("Reported by" str, "Last reported date" str),
    read directly from the two columns 04_build_master_accessibility_
    status.py computes once (2026-08-27) - not re-derived here, so this
    stays consistent with the master ward file as the single source of
    truth for provenance, same principle as load_ward_status_lookup()
    above."""
    rows = load_csv(MASTER_WARD_CSV)
    return {(r["State"], r["LGA"], r["Ward (GRID3)"]): (r["Reported by"], r["Last reported date"])
            for r in rows}


def aggregate_provenance(ward_keys, provenance_lookup):
    """Given a set of (State, LGA, Ward) keys - a cluster's touched wards,
    a stratum's, or a LGA's - returns (reported_by_summary, last_date_str):
    the union of distinct 'Reported by' categories across all of them
    (usually one value; joined with '; ' when genuinely mixed, e.g. some
    wards Partner-reported and others not yet reported - the common,
    expected case for anything above ward grain, not an error), and the
    single most recent valid date among them (blank if none)."""
    reported_by_vals = set()
    dates = []
    for k in ward_keys:
        rb, dt = provenance_lookup.get(k, ("Not yet reported", ""))
        reported_by_vals.add(rb)
        if dt and not dt.startswith("Unknown"):
            dates.append(dt)
    reported_by_summary = "; ".join(sorted(reported_by_vals)) if reported_by_vals else "Not yet reported"
    return reported_by_summary, (max(dates) if dates else "")


TOTAL_PARTNERS_IN_ASSESSMENT = 19


def compute_reporting_stats():
    """Partner-reporting completeness, computed fresh every run (not
    hardcoded) - counts, not ward names/locations, per the 2026-08-25
    request to keep this section high-level.

    Partner list/count comes from the master REQUEST LOG (every partner who
    has submitted ANY report, ward- or cluster-level) - the ward-level
    master status file alone would undercount a partner who has only
    reported cluster-level issues so far (their clusters still get a
    reallocation request logged, they just don't carry a ward-wide
    accessible/inaccessible call yet). Ward-completeness figures still come
    from the ward-level file specifically, since that's the layer this
    whole workbook's area/population figures are built from."""
    log_rows = load_csv(SAMPLING_DIR + r"\resampling\output\resampling_requests_log.csv")
    reporting_partners = sorted({r["partner"] for r in log_rows})

    ward_rows = load_csv(MASTER_WARD_CSV)
    total_wards = len(ward_rows)
    reported_wards = sum(1 for r in ward_rows if r["Status source"].startswith("confirmed_by_partner_report"))
    inaccessible_wards = sum(1 for r in ward_rows if r["Accessible status"] == "Inaccessible")
    return {
        "n_partners_reported": len(reporting_partners),
        "partner_names": reporting_partners,
        "total_wards": total_wards,
        "reported_wards": reported_wards,
        "inaccessible_wards": inaccessible_wards,
    }


def load_lga_area_pop_fractions():
    """(adm2_pcode, pop_type_label) -> dict(total_area_km2, accessible_area_km2,
    pct_area, total_pop_gis, accessible_pop_gis, pct_pop). From the
    ward-clipped GIS layer - see module docstring for why this is used as a
    FRACTION only, not as the reported total.

    Keyed by pop_type_label ("Non-IDP"/"IDP", matching the GIS layer's own
    column, NOT the strata CSV's lowercase "non_idp"/"idp" - callers must
    normalize) since 2026-08-27 - the GIS layer is now split by pop_type
    (see analysis_accessible_area_layer.R's 2026-08-27 fix), because
    eligibility genuinely differs by pop_type (e.g. a LGA can have Non-IDP
    coverage with its IDP stratum certainty-excluded, or vice versa) and a
    ward eligible for both carries two rows with identical area/population -
    summing them under one blended key would double-count that ward for any
    LGA with dual-eligible wards, which is exactly the bug this fixes."""
    rows = load_csv(GIS_WARD_CSV)
    agg = defaultdict(lambda: {"total_area": 0.0, "acc_area": 0.0, "total_pop": 0.0, "acc_pop": 0.0})
    for r in rows:
        a = agg[(r["adm2_pcode"], r["pop_type"])]
        area = float(r["area_km2"])
        pop = float(r["pop_total"])
        a["total_area"] += area
        a["total_pop"] += pop
        if r["accessible_status"] == "Accessible":
            a["acc_area"] += area
            a["acc_pop"] += pop
    out = {}
    for key, a in agg.items():
        out[key] = {
            "total_area_km2": a["total_area"],
            "accessible_area_km2": a["acc_area"],
            "pct_area_accessible": 100 * a["acc_area"] / a["total_area"] if a["total_area"] else 0,
            "pct_pop_accessible_gis": 100 * a["acc_pop"] / a["total_pop"] if a["total_pop"] else 0,
        }
    return out


def classify_households(ward_status):
    """Loads the household-level WORKING frame and tags every row with
    accessible_status, using its own (adm1_name, adm2_name, adm3_name) - the
    exact same per-household ward attribution used everywhere else in this
    project (Stage 2's own point-in-polygon join). Rows whose ward has no
    entry in the master status (no partner's clusters ever touched it,
    vanishingly rare given the master file is itself built from this same
    frame) default Accessible."""
    rows = load_csv(HOUSEHOLD_CSV)
    # FULL includes population-floor/certainty-excluded strata (correctly
    # dropped from the sampling universe altogether, e.g. Dandume/Faskari) -
    # excluded here so they don't reappear in the accessibility picture,
    # same scope WORKING used to give this script before the FULL switch.
    rows = [r for r in rows if r.get("coverage_status") == "covered" and r.get("exclusion_reason") in ("none", "", None)]
    for r in rows:
        key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
        r["_accessible_status"] = ward_status.get(key, "Accessible")
    return rows


def build_cluster_level(household_rows, provenance_lookup):
    """One row per cluster_id: strata_id, pop_type, any_accessible (bool -
    at least one PRIMARY household accessible), all_accessible (bool - every
    primary household accessible), primary/reserve counts, state/lga/wards
    touched, and (2026-08-28) reported_by/last_reported_date - aggregated
    across every ward this cluster's households actually touch (clusters
    spanning >1 ward are real, ~35% nationally - see 01_generate_
    accessibility_reports.py's known ward-splitting fix), not just one
    representative ward, via the same aggregate_provenance() used at
    strata/LGA grain below - so a multi-ward cluster correctly shows
    'Mixed'-style provenance rather than silently picking one ward's."""
    by_cluster = defaultdict(list)
    for r in household_rows:
        by_cluster[r["cluster_id"]].append(r)

    out = []
    for cid, rows in by_cluster.items():
        primaries = [r for r in rows if r["status"] == "primary"]
        any_row = rows[0]
        acc_primaries = [r for r in primaries if r["_accessible_status"] == "Accessible"]
        # 2026-08-29: capacity ceiling for the resampling decision - EVERY
        # household row (primary + reserve) in an accessible ward, not just
        # primary. Same per-household accessible-ward filter n_primary_
        # accessible already uses (a multi-ward cluster's inaccessible-ward
        # rows still don't count), just extended to include reserve slots -
        # this is "if every currently-assigned, accessible slot in this
        # cluster were completed," the actual ceiling the resampling
        # decision needs (see load_real_achieved()'s caller).
        acc_capacity = [r for r in rows if r["_accessible_status"] == "Accessible"]
        wards = sorted({r["adm3_name"] for r in rows})
        ward_keys = {(r["adm1_name"], r["adm2_name"], r["adm3_name"]) for r in rows}
        reported_by, last_date = aggregate_provenance(ward_keys, provenance_lookup)
        out.append({
            "cluster_id": cid,
            "strata_id": any_row["strata_id"],
            "pop_type": any_row["pop_type"],
            "state": any_row["adm1_name"],
            "lga": any_row["adm2_name"],
            "wards": "; ".join(wards),
            "ward_keys": ward_keys,
            "n_primary": len(primaries),
            "n_primary_accessible": len(acc_primaries),
            "n_capacity_accessible": len(acc_capacity),
            "any_accessible": len(acc_primaries) > 0,
            "all_accessible": len(acc_primaries) == len(primaries) and len(primaries) > 0,
            "reported_by": reported_by,
            "last_reported_date": last_date,
        })
    return out


def load_collected_samples():
    """matched_strata_id -> collected count (completed, not quality-flagged).
    Also matched_cluster_id -> collected count, for the accessible-area-only
    figure. Also returns the earliest submission_date in the file, for the
    README's data-recency note - computed from the real data every run
    rather than hardcoded, so it can't go stale."""
    rows = load_csv(REAL_SUBMISSIONS_CSV)
    clean = [r for r in rows if r["interview_outcome"] == "completed" and r["any_quality_flag"] == "FALSE"]
    by_strata = defaultdict(int)
    by_cluster = defaultdict(int)
    for r in clean:
        by_strata[r["matched_strata_id"]] += 1
        if r["matched_cluster_id"]:
            by_cluster[r["matched_cluster_id"]] += 1
    min_date = min((r["submission_date"] for r in rows if r["submission_date"]), default="N/A")
    return by_strata, by_cluster, min_date


def load_real_achieved():
    """TRUE achieved sample per matched_cluster_id/matched_strata_id - the
    resampling-decision figure, added 2026-08-29 per Jack's own explicit
    formula (2_monitoring is the single source of truth for this, don't
    re-derive it differently):
        is_collected = interview_outcome == "completed"
        is_achieved  = is_collected & !is_duplicate & !is.na(matched_survey_id)
    - the exact same is_achieved() the dashboard uses (2_monitoring/
    dashboard_app/global.R:584), MINUS every uuid marked status=="confirmed"
    in CONFIRMED_DELETIONS_OVERLAY.csv (2026-09-06, repointed from the
    abandoned revised_deletion_log_for_resampling_*.csv handoff - see the
    module-level comment above `CONFIRMED_DELETIONS_OVERLAY_CSV`). Treated
    as not-achieved regardless of what real_submissions.csv's own
    quality_exclusion_reason says, since that column currently only reflects
    duration_under_20/fcs_zero and can lag the tracker (confirmed directly,
    2026-09-06: the overlay's confirmed set was larger than real_submissions.
    csv's own column in every category at the time of this repoint - the
    overlay, not real_submissions.csv, is the authoritative source here).
    "Contested" rows are explicitly EXCLUDED from deletion_uuids - a
    contested-but-unresolved issue is not a genuine deliberate deletion
    decision under Jack's policy, so it must not silently reduce achieved.

    NOT the same thing as load_collected_samples() above (interview_
    outcome=="completed" & any_quality_flag=="FALSE", Jack's own separate
    2026-08-25 decision for the general-purpose "Collected samples" columns
    elsewhere in this workbook) - that definition stays as-is for its own
    columns. This one feeds the MoE/Feasibility/resampling-need columns
    specifically, and previously those were driven by primaries_accessible
    (a DESIGN-target count within the accessible area, not real field data
    at all) - see this function's caller for the 2026-08-29 fix.

    Deliberately NOT capped at each cluster's target_households the way
    the dashboard's compute_progress_by_stratum() caps ACHIEVED before
    summing (global.R ~line 574) - that cap exists so an oversampled
    cluster's surplus doesn't visually overstate progress-toward-target on
    the dashboard, but a genuine extra interview does reduce sampling
    variance, and realized_moe() below is a precision calculation, not a
    progress display. Flagging this as a deliberate choice, not a copy
    error, in case a dashboard-consistent (capped) figure is wanted instead
    for a future use of this function."""
    rows = load_csv(REAL_SUBMISSIONS_CSV)
    deletion_uuids = {r["uuid"] for r in load_csv(CONFIRMED_DELETIONS_OVERLAY_CSV) if r["status"] == "confirmed"}

    def is_achieved(r):
        return (
            r["interview_outcome"] == "completed"
            and r["is_duplicate"] != "TRUE"
            and r["matched_survey_id"] not in (None, "", "NA")
            and r["submission_uuid"] not in deletion_uuids
        )

    achieved = [r for r in rows if is_achieved(r)]
    by_strata = defaultdict(int)
    by_cluster = defaultdict(int)
    for r in achieved:
        by_strata[r["matched_strata_id"]] += 1
        if r["matched_cluster_id"]:
            by_cluster[r["matched_cluster_id"]] += 1
    print(f"  Real achieved (canonical, post-deletion): {len(achieved)} of {len(rows)} submissions "
          f"({len(deletion_uuids)} deletion-log rows applied)")
    return by_strata, by_cluster


def main():
    print("Loading master ward status...")
    ward_status = load_ward_status_lookup()
    provenance_lookup = load_ward_provenance_lookup()
    lga_fractions = load_lga_area_pop_fractions()

    print("Classifying households by accessible status...")
    household_rows = classify_households(ward_status)
    cluster_rows = build_cluster_level(household_rows, provenance_lookup)
    cluster_by_id = {c["cluster_id"]: c for c in cluster_rows}

    print("Loading real submissions (collected samples)...")
    collected_by_strata, collected_by_cluster, min_submission_date = load_collected_samples()
    print("Loading real achieved samples for resampling decisions (canonical formula + deletion log)...")
    real_achieved_by_strata, real_achieved_by_cluster = load_real_achieved()

    print("Loading remaining eligible pool (non-IDP hexes, IDP DTM sites)...")
    pool_non_idp = load_pool_lookup(POOL_NON_IDP_CSV, "accessible_unselected_hexes")
    pool_idp = load_pool_lookup(POOL_IDP_CSV, "accessible_unselected_sites")

    print("Loading strata frame and computing stratum-level summary...")
    strata_rows = load_csv(STRATA_CSV)
    strata_rows = [s for s in strata_rows if s.get("coverage_status") == "covered" and s.get("exclusion_reason") in ("none", "", None)]

    strata_clusters = defaultdict(list)
    for c in cluster_rows:
        strata_clusters[c["strata_id"]].append(c)

    summary_rows = []
    for s in strata_rows:
        strata_id = s["strata_id"]
        adm2_pcode = s["adm2_pcode"]
        pop_type = s["pop_type"]
        m_used = int(s["m_used"])
        n_pop = float(s["n_pop"])
        N_hh = float(s["N_hh"])
        achieved_sample = int(s["achieved_sample"])
        target_sample = int(s["target_sample"])
        achieved_clusters = int(s["achieved_clusters"])
        clusters_target = int(s["clusters_target_stage1"])

        clusters = strata_clusters.get(strata_id, [])
        n_clusters_total = len(clusters)
        strata_ward_keys = set().union(*(c["ward_keys"] for c in clusters)) if clusters else set()
        strata_reported_by, strata_last_date = aggregate_provenance(strata_ward_keys, provenance_lookup)
        n_clusters_accessible = sum(1 for c in clusters if c["any_accessible"])
        primaries_total = sum(c["n_primary"] for c in clusters)
        primaries_accessible = sum(c["n_primary_accessible"] for c in clusters)

        pop_type_label = "Non-IDP" if pop_type == "non_idp" else "IDP"
        frac = lga_fractions.get((adm2_pcode, pop_type_label), {
            "total_area_km2": 0, "accessible_area_km2": 0,
            "pct_area_accessible": 0, "pct_pop_accessible_gis": 0,
        })
        pct_pop_accessible = frac["pct_pop_accessible_gis"]
        n_pop_accessible = n_pop * pct_pop_accessible / 100
        N_hh_accessible = N_hh * pct_pop_accessible / 100

        collected_full = collected_by_strata.get(strata_id, 0)
        collected_accessible = sum(
            collected_by_cluster.get(c["cluster_id"], 0) for c in clusters if c["any_accessible"]
        )
        # Real achieved so far (real field data, canonical is_achieved formula,
        # deletion-log-adjusted) within accessible-area clusters - informational
        # only (shows current fielding progress), added 2026-08-29.
        real_achieved_accessible = sum(
            real_achieved_by_cluster.get(c["cluster_id"], 0) for c in clusters if c["any_accessible"]
        )
        # Achievable CEILING - what this stratum could reach if every currently-
        # assigned, accessible cluster's PRIMARY slots were fully completed.
        # THIS (primary only), not real_achieved_accessible and NOT primary+
        # reserve, is what drives the resampling decision below.
        #
        # Three passes to land here, 2026-08-29 (worth keeping straight):
        # pass 1 used the design target (not real data at all); pass 2 used
        # real achieved-to-date, which conflated "still mid-fieldwork" with
        # "genuinely can't reach representativity"; pass 3 used primary+
        # reserve capacity together, which Jack rejected on a real
        # methodological ground - reserve exists as a 1:1 non-response
        # backstop, not routine bonus sample, and reserve_households ==
        # target_households uniformly (2026-07-22c/08-04 design decision),
        # so counting it toward the ceiling everywhere would have silently
        # required exhausting reserves as standard practice. Doing that
        # would make actual achieved sample size cluster-dependent on which
        # clusters still happen to have reserve capacity available, breaking
        # PPS's core assumption that every selected cluster contributes the
        # same target size - a real spatial/coverage bias risk, not a minor
        # one. Primary-only avoids this entirely: it's exactly the ceiling
        # the original design already assumed, just scoped to the
        # currently-accessible portion.
        primary_ceiling_accessible = primaries_accessible
        # Reference only, NOT used for the decision - what the ceiling WOULD
        # be if reserves were also fully exhausted. Kept visible so the
        # tradeoff (a specific stratum's gap could technically be closed by
        # asking a partner to fully work their reserve list instead of
        # resampling) stays visible, even though it's not being used as a
        # standard lever - see resampling/RESAMPLING_DECISION_RULES.md §3.
        capacity_ceiling_accessible = sum(
            c["n_capacity_accessible"] for c in clusters if c["any_accessible"]
        )

        moe_updated = realized_moe(primary_ceiling_accessible, N_hh_accessible, m_used) if N_hh_accessible > 0 else None

        # --- Feasibility: additional clusters needed to reach TARGET_MOE_PCT, and
        # whether the remaining accessible-unselected pool can actually supply them.
        # Driven by the primary-only achievable ceiling - see above.
        pool = pool_non_idp.get(adm2_pcode, 0) if pop_type == "non_idp" else pool_idp.get(adm2_pcode, 0)
        if moe_updated is not None and moe_updated <= TARGET_MOE_PCT:
            feasibility = "Already at/under target"
            additional_clusters_needed = 0
        else:
            sample_needed = sample_needed_for_moe(TARGET_MOE_PCT, N_hh_accessible, m_used)
            if sample_needed is None:
                feasibility = "Not computable (accessible population too small)"
                additional_clusters_needed = None
            else:
                additional_samples = max(0, sample_needed - primary_ceiling_accessible)
                additional_clusters_needed = math.ceil(additional_samples / m_used) if additional_samples > 0 else 0
                if additional_clusters_needed == 0:
                    feasibility = "Already at/under target"
                elif pool <= 0:
                    feasibility = "Not closeable - no remaining pool left"
                elif additional_clusters_needed > pool:
                    feasibility = "Not closeable - exceeds remaining pool (recommend indicative)"
                elif additional_clusters_needed / pool > 0.5:
                    feasibility = "Closeable only via most of remaining pool (near-full-enumeration)"
                else:
                    feasibility = "Closeable with a modest top-up"

        summary_rows.append({
            "State": s["adm1_name"], "LGA": s["adm2_name"], "Pop type": "Non-IDP" if pop_type == "non_idp" else "IDP",
            "Strata ID": strata_id,
            "Partners covering": s["partners_covering"],
            "Total population (design, n_pop)": round(n_pop),
            "Updated population within accessible area": round(n_pop_accessible),
            "% of population remaining": round(pct_pop_accessible, 1),
            "Total clusters (achieved)": n_clusters_total,
            "Updated clusters within accessible area": n_clusters_accessible,
            "% of clusters remaining": round(100 * n_clusters_accessible / n_clusters_total, 1) if n_clusters_total else 0,
            "Total area km2 (LGA)": round(frac["total_area_km2"], 1),
            "Updated area km2 (accessible)": round(frac["accessible_area_km2"], 1),
            "% of area remaining": round(frac["pct_area_accessible"], 1),
            "[FULL FRAME] Target clusters": clusters_target,
            "[FULL FRAME] Target samples": target_sample,
            "[FULL FRAME] Collected samples (field, quality-checked)": collected_full,
            "[FULL FRAME] Achieved samples (design)": achieved_sample,
            "[UPDATED AREA] Target clusters": n_clusters_accessible,
            "[UPDATED AREA] Target samples": primaries_accessible,
            "[UPDATED AREA] Collected samples (field, quality-checked)": collected_accessible,
            "[UPDATED AREA] Achievable ceiling (primary only, decision basis)": primary_ceiling_accessible,
            "[UPDATED AREA] Achieved samples (real, post-deletion, progress-to-date)": real_achieved_accessible,
            "[UPDATED AREA] Achievable ceiling (primary+reserve, reference only - NOT the decision basis, see README)": capacity_ceiling_accessible,
            "Realized MoE % (full frame, existing)": s["realized_moe_pct"],
            "Realized MoE % (updated area, at full completion of currently-assigned PRIMARY slots)": round(moe_updated, 2) if moe_updated is not None else "N/A (sample >= N_hh or 0 accessible)",
            "Remaining eligible pool (accessible, unselected)": pool,
            f"Additional clusters needed for {TARGET_MOE_PCT:.0f}% MoE (at m={m_used})": additional_clusters_needed if additional_clusters_needed is not None else "N/A",
            "Feasibility": feasibility,
            "Reported by": strata_reported_by,
            "Last reported date": strata_last_date,
        })

    print(f"Built {len(summary_rows)} stratum-level rows.")
    reporting_stats = compute_reporting_stats()
    write_workbook(summary_rows, cluster_rows, ward_status, provenance_lookup, min_submission_date, reporting_stats)
    write_updated_frame(household_rows)


def write_updated_frame(household_rows):
    if not household_rows:
        return
    fieldnames = [k for k in household_rows[0].keys() if k != "_accessible_status"] + ["accessible_status"]
    with open(UPDATED_FRAME_CSV, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in household_rows:
            row = {k: r[k] for k in fieldnames if k != "accessible_status"}
            row["accessible_status"] = r["_accessible_status"]
            writer.writerow(row)
    print(f"Wrote updated sampling frame (with accessible_status column) to {UPDATED_FRAME_CSV}")


HEADER_FILL = PatternFill("solid", fgColor="1B2A4A")
SECTION_FILL = {"full": PatternFill("solid", fgColor="2C5F8A"), "updated": PatternFill("solid", fgColor="8B4A4A")}
WARNING_FILL = PatternFill("solid", fgColor="C9A227")
LIGHT_FULL_FILL = PatternFill("solid", fgColor="DCE8F2")
LIGHT_UPDATED_FILL = PatternFill("solid", fgColor="F2E0DC")
LIGHT_WARNING_FILL = PatternFill("solid", fgColor="FCF1CE")
THIN_BORDER = Border(*([Side(style="thin", color="B0B0B0")] * 4))


def write_sheet(wb, name, rows, header_groups=None):
    ws = wb.create_sheet(name)
    if not rows:
        return ws
    columns = list(rows[0].keys())
    ws.append(columns)
    for c, col in enumerate(columns, start=1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color="FFFFFF")
        fill = HEADER_FILL
        if col.startswith("[FULL FRAME]"):
            fill = SECTION_FILL["full"]
        elif col.startswith("[UPDATED AREA]"):
            fill = SECTION_FILL["updated"]
        cell.fill = fill
        cell.alignment = Alignment(wrap_text=True, vertical="center")
        ws.column_dimensions[get_column_letter(c)].width = max(14, min(30, len(col) // 1.3))
    for r in rows:
        ws.append([r.get(c, "") for c in columns])
    ws.freeze_panes = "A2"
    return ws


README_SECTIONS = [
    ("What this workbook is", "header", [
        "Built 2026-08-25 for the technical-team discussion on how to handle partner-reported "
        "inaccessible areas: drop the LGA, mixed-method (remote KII + continue HH collection where "
        "accessible), or remote-only. This workbook is DESCRIPTIVE, not a decision - it reports the "
        "current extent of the issue using data received so far; it does not set thresholds.",
    ]),
    ("Method note: standalone recompute, not a new sampling design", "header", [
        "Every figure here reclassifies the ALREADY-DELIVERED clusters/households (the ones partners "
        "are physically fielding right now) as inside/outside the currently-accessible geography, and "
        "re-sums population/area against that. It does NOT draw a new sample for a shrunken universe - "
        "that would be a different, not-yet-decided task (reallocating into the accessible remainder "
        "is the option currently being leaned against, for coverage/spatial-bias reasons).",
    ]),
    ("Data completeness caveat - read before presenting any number from this workbook", "reporting_stats", []),
    ("Population/area methodology", "split", [
        ("full", "'Total population' per stratum is the EXISTING, already-vetted n_pop from the sampling "
                  "frame (Stage 1's hex-clipped WorldPop aggregation) - unchanged, always matches the frame "
                  "you already know."),
        ("updated", "'Updated population within accessible area' = that same total x an accessible-population "
                     "FRACTION from a NEW, independent ward-clipped GIS layer (GRID3 wards x OCHA/COD LGA "
                     "boundaries, WorldPop zonal stats). The two layers clip on different boundaries (hex vs "
                     "ward) so absolute totals don't match exactly - only the fraction is used. Area has no "
                     "prior figure to reconcile against, so area numbers come directly from the new GIS layer."),
    ]),
    ("Target vs. achieved vs. collected samples - three different things, easy to conflate", "table", [
        ("Target samples", "The number of interviews the sampling design calls for in this stratum "
                             "(already includes the standard buffer for expected non-response)."),
        ("Achieved samples", "The number of interviews actually allocated once clusters were drawn - "
                               "this is the field plan partners are working from. Can land above OR below "
                               "the target for a given stratum, not just below - both directions are "
                               "normal outcomes of cluster selection, not an error."),
        ("Collected samples", "Interviews actually completed in the field SO FAR, from live submission "
                                "data, excluding any submission carrying a data-quality flag (GPS outlier, "
                                "LGA mismatch, etc.). The only one of the three that changes day to day."),
        ("Achieved samples (real, post-deletion, progress-to-date)", "Added 2026-08-29 - real submissions "
                                "passing the dashboard's own canonical is_achieved test (completed, not a "
                                "duplicate, matched to a real point), minus every uuid in 2_monitoring's "
                                "revised deletion log (duration<20min, fcs_zero, no_consent - see resampling/"
                                "RESAMPLING_DECISION_RULES.md for the full list and what's deliberately NOT in "
                                "it yet). Informational only - shows current fielding progress. NOT what drives "
                                "the resampling decision (see the next row) - a stratum simply mid-fieldwork "
                                "always looks short against progress-to-date, identical in shape to one that's "
                                "genuinely blocked."),
        ("Achievable ceiling (primary only, decision basis)", "What this stratum COULD reach if every "
                                "currently-assigned, accessible cluster's PRIMARY slots were fully completed - "
                                "not real data, a capacity figure from the design frame. THIS is what the "
                                "Realized MoE / Feasibility / Additional-clusters-needed columns below are "
                                "computed from: 'even at full completion of currently-assigned primaries, would "
                                "this stratum still fall short of 10% MoE?' Only a stratum that fails that test "
                                "genuinely needs brand-new resampled clusters. Deliberately PRIMARY ONLY, not "
                                "primary+reserve (see the next row and resampling/RESAMPLING_DECISION_RULES.md "
                                "§3 for why - reserve counting toward this would require exhausting reserves as "
                                "routine practice rather than a non-response backstop, which breaks PPS's "
                                "assumption that every selected cluster contributes the same target size)."),
        ("Achievable ceiling (primary+reserve, reference only)", "The SAME calculation but including reserve "
                                "slots too - shown for visibility only, NOT used for Feasibility/Additional-"
                                "clusters-needed. A stratum where this column reaches 10% MoE but the primary-"
                                "only column doesn't could in principle be closed by asking its partner to "
                                "fully work their reserve list instead of resampling - deliberately not treated "
                                "as a standard lever here, since doing so would make actual achieved sample size "
                                "depend on which clusters happen to still have reserve capacity, a real spatial/"
                                "coverage bias risk (Jack's call, 2026-08-29)."),
    ]),
    ("Clusters are hard counts, not estimates", "header", [
        "Each cluster's own primary households are individually checked against their real (State, LGA, "
        "Ward) location to decide whether that cluster sits inside or outside the accessible area - not "
        "an approximation.",
    ]),
    ("Feasibility columns (2026-08-25 addition, fixed three times 2026-08-29)", "split", [
        ("updated", "'Additional clusters needed' works out how many more same-size clusters would be needed "
                     "to bring the accessible-only sample down to 10% MoE, computed against the 'Achievable "
                     "ceiling (primary only, decision basis)' column above - NOT the design target, NOT real "
                     "achieved-to-date, and NOT primary+reserve capacity either (see the table above). Three "
                     "passes landed here 2026-08-29, each fixing a real problem with the last: (1) the design-"
                     "planned accessible-area sample (a target, not real data); (2) real achieved-to-date, "
                     "which conflated 'still mid-fieldwork' with 'genuinely can't reach representativity' (any "
                     "not-yet-finished stratum always looks short against progress-to-date); (3) primary+"
                     "reserve capacity together, rejected on a real methodological ground - see the "
                     "'Achievable ceiling (primary+reserve, reference only)' row above and resampling/"
                     "RESAMPLING_DECISION_RULES.md §3 for why counting reserves this way risks PPS spatial "
                     "bias. Primary-only is the actual, final basis: does this stratum still fall short of 10% "
                     "MoE even at full completion of currently-assigned PRIMARIES? Never add clusters just to "
                     "restore the original numeric target if that ceiling already projects to <=10% MoE. "
                     "Adding more clusters at the existing cluster size is used rather than making each "
                     "existing cluster bigger, because a bigger cluster adds households that are more similar "
                     "to each other (they're neighbours) - so each additional interview buys less real "
                     "precision than one from a brand new cluster would."),
        ("full", "'Remaining eligible pool' is how many more candidates actually exist to draw from in the "
                  "accessible area - Non-IDP is a HEXAGON count (an UPPER BOUND, not building-validated), IDP "
                  "is an exact DTM SITE count (every site individually geo-matched). 'Feasibility' compares "
                  "the two: closeable with a modest top-up vs. would require most/all of what's left (in "
                  "practice equivalent to trying to survey nearly everyone remaining, rather than sampling) "
                  "vs. not closeable within the remaining pool at all."),
    ]),
    ("'Reported by' and 'Last reported date' (2026-08-28 addition)", "table", [
        ("Partner", "This ward (or, at cluster/strata/LGA grain, at least one of the wards it covers) has been "
                     "reviewed by the assigned partner - either an explicit Accessible/Reason answer, or the "
                     "ward was present in their returned file and left blank on purpose (reviewed, nothing to "
                     "flag)."),
        ("Needs review", "The ward has an explicit answer, but who actually typed it - the partner directly, "
                           "or a coordinator transcribing from an email/WhatsApp report - hasn't been individually "
                           "confirmed yet. Not wrong, just not yet verified; see resampling/README.md's provenance "
                           "note for which partners this currently applies to."),
        ("Not yet reported", "No partner has said anything about this ward at all - it's on the default "
                               "Accessible status until someone does."),
    ]),
    ("Why 'Reported by' often shows more than one value at cluster/strata/LGA grain", "header", [
        "A cluster can span more than one ward (about 35% do), and a stratum/LGA obviously spans many - so "
        "above ward grain, 'Reported by' is the FULL SET of categories among everything it covers, joined "
        "with ';' (e.g. 'Not yet reported; Partner'). This is the normal, expected case for anything above "
        "ward level, not an inconsistency - it tells you the picture is mixed, not that something's wrong. "
        "'Last reported date' is the single most recent valid date among everything it covers (blank if "
        "nothing has a usable date yet).",
    ]),
    ("A note on dates - some are missing or show 'Unknown' on purpose", "header", [
        "Dates come from partners' own 'Date reported' entries, in whatever format they used - parsed "
        "automatically, not reformatted by hand. Two real data-quality issues mean a date can be genuinely "
        "unavailable even when a ward has been reported on: (1) about 450 of FACT's rows carry a corrupted, "
        "auto-incrementing date (an Excel drag-fill artifact - some run as far as the year 2261) - these are "
        "excluded rather than guessed at, showing as 'Unknown' rather than a fabricated real-looking date; "
        "(2) a 'present but blank' ward (see 'Partner' above) was never explicitly dated by the partner in "
        "the first place, so there's genuinely nothing to show. Neither case means the report itself is in "
        "doubt - only that a specific date isn't available for it.",
    ]),
]

README_SHEET_LIST = [
    "LGA Summary - one row per LGA, area/population/status rollup.",
    "Strata Level (main sheet) - one row per (LGA x pop type) stratum, the full metric set.",
    "Cluster Level - one row per delivered cluster, accessible/inaccessible classification detail.",
    "Inaccessibility Report Log - every ward-level 'Inaccessible' report currently active, by partner.",
]


def write_readme(wb, summary_rows, min_submission_date, reporting_stats):
    readme = wb.create_sheet("README")
    LAST_COL = 8  # A:H

    def banner(row, text, fill, size=11, height=None):
        readme.merge_cells(start_row=row, start_column=1, end_row=row, end_column=LAST_COL)
        cell = readme.cell(row=row, column=1, value=text)
        cell.font = Font(bold=True, color="FFFFFF" if fill != LIGHT_WARNING_FILL else "5C4A00", size=size)
        cell.fill = fill
        cell.alignment = Alignment(vertical="center", horizontal="left", indent=1)
        if height:
            readme.row_dimensions[row].height = height
        return row + 1

    def paragraph(row, text, fill=None, indent=1):
        readme.merge_cells(start_row=row, start_column=1, end_row=row, end_column=LAST_COL)
        cell = readme.cell(row=row, column=1, value=text)
        cell.alignment = Alignment(wrap_text=True, vertical="top", horizontal="left", indent=indent)
        if fill:
            cell.fill = fill
        readme.row_dimensions[row].height = 15 * max(1, math.ceil(len(text) / 148))
        return row + 1

    r = 1
    r = banner(r, "NGA MSNA 2026 - Accessibility Impact Workbook", HEADER_FILL, size=16, height=28)
    r += 1

    # --- Color key ---
    r = banner(r, "Color key used throughout this workbook", HEADER_FILL)
    key_row = r
    swatches = [
        (SECTION_FILL["full"], "[FULL FRAME]  -  original design figures (unchanged)"),
        (SECTION_FILL["updated"], "[UPDATED AREA]  -  accessible-only, recomputed figures"),
        (WARNING_FILL, "Caveat / read-before-using warning"),
    ]
    for i, (fill, label) in enumerate(swatches):
        readme.cell(row=key_row, column=1 + i * 3).fill = fill
        readme.merge_cells(start_row=key_row, start_column=2 + i * 3, end_row=key_row, end_column=3 + i * 3)
        lc = readme.cell(row=key_row, column=2 + i * 3, value=label)
        lc.alignment = Alignment(vertical="center", indent=1)
        lc.font = Font(size=10, italic=True)
    readme.row_dimensions[key_row].height = 20
    r = key_row + 2

    for title, kind, body in README_SECTIONS:
        if kind == "warning":
            r = banner(r, title, WARNING_FILL)
            r = paragraph(r, body[0], fill=LIGHT_WARNING_FILL)
        elif kind == "split":
            r = banner(r, title, HEADER_FILL)
            for tag, text in body:
                fill = LIGHT_FULL_FILL if tag == "full" else LIGHT_UPDATED_FILL
                r = paragraph(r, text, fill=fill)
        elif kind == "reporting_stats":
            r = banner(r, title, WARNING_FILL)
            rs = reporting_stats
            stat_row = r
            stats = [
                (f"{rs['n_partners_reported']} / {TOTAL_PARTNERS_IN_ASSESSMENT}", "partners have submitted a report"),
                (f"{rs['reported_wards']} / {rs['total_wards']}", "LGA-ward portions confirmed by a report"),
                (f"{rs['inaccessible_wards']}", "ward portions currently flagged Inaccessible"),
            ]
            for i, (big, small) in enumerate(stats):
                readme.merge_cells(start_row=stat_row, start_column=1 + i * 3, end_row=stat_row, end_column=2 + i * 3)
                c1 = readme.cell(row=stat_row, column=1 + i * 3, value=big)
                c1.font = Font(bold=True, size=15, color="1B2A4A")
                c1.alignment = Alignment(horizontal="center")
                readme.merge_cells(start_row=stat_row + 1, start_column=1 + i * 3, end_row=stat_row + 1, end_column=2 + i * 3)
                c2 = readme.cell(row=stat_row + 1, column=1 + i * 3, value=small)
                c2.font = Font(size=9, italic=True)
                c2.alignment = Alignment(horizontal="center")
            readme.row_dimensions[stat_row].height = 22
            r = stat_row + 2
            r = paragraph(
                r,
                f"Partners who have reported so far: {', '.join(rs['partner_names'])}. A ward/LGA-ward "
                f"portion counts as 'confirmed' here as soon as its covering partner has returned a report "
                f"at all - if that partner left a specific ward blank on their form, it's still counted as "
                f"confirmed (reviewed, nothing flagged), not treated the same as a ward whose partner hasn't "
                f"sent anything back yet. Only wards belonging to a partner who has not yet returned "
                f"anything remain on the plain default-Accessible status. A stratum showing 0% inaccessible "
                f"may still mean 'nobody has told us yet' if its partner hasn't reported at all - check the "
                f"partner list above. Ward names/locations are deliberately not listed here - see the "
                f"Inaccessibility Report Log sheet for that level of detail.",
                fill=LIGHT_WARNING_FILL,
            )
        elif kind == "table":
            r = banner(r, title, HEADER_FILL)
            for term, definition in body:
                readme.cell(row=r, column=1, value=term).font = Font(bold=True)
                readme.cell(row=r, column=1).alignment = Alignment(vertical="top", indent=1)
                readme.cell(row=r, column=1).border = THIN_BORDER
                readme.merge_cells(start_row=r, start_column=2, end_row=r, end_column=LAST_COL)
                dcell = readme.cell(row=r, column=2, value=definition)
                dcell.alignment = Alignment(wrap_text=True, vertical="top", indent=1)
                dcell.border = THIN_BORDER
                readme.row_dimensions[r].height = 15 * max(1, math.ceil(len(definition) / 128))
                r += 1
            if title.startswith("Target vs."):
                r = paragraph(
                    r,
                    f"Field data collection began {min_submission_date} - based on the earliest submission "
                    f"currently in real_submissions.csv, so 'Collected samples' coverage is still building "
                    f"up nationally and should be read as a live, in-progress figure, not a final one.",
                    fill=LIGHT_WARNING_FILL,
                )
        else:
            r = banner(r, title, HEADER_FILL)
            for line in body:
                if line == "":
                    r += 1
                else:
                    r = paragraph(r, line)
        r += 1

    # --- Sheets guide ---
    r = banner(r, "Sheets in this workbook", HEADER_FILL)
    for line in README_SHEET_LIST:
        r = paragraph(r, line)
    r += 1

    # --- Snapshot: worst affected strata ---
    r = banner(r, "Snapshot: worst-affected strata right now (based on partner reports received so far)",
               WARNING_FILL)
    affected = sorted(
        (row for row in summary_rows if row["% of population remaining"] < 100),
        key=lambda row: row["% of population remaining"],
    )[:15]
    snap_cols = ["State", "LGA", "Pop type", "% of population remaining", "% of area remaining",
                 "% of clusters remaining", "Realized MoE % (updated area, at full completion of currently-assigned PRIMARY slots)", "Feasibility"]
    header_row = r
    for c, col in enumerate(snap_cols, start=1):
        cell = readme.cell(row=header_row, column=c, value=col)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HEADER_FILL
        cell.alignment = Alignment(wrap_text=True, vertical="center")
        cell.border = THIN_BORDER
    r += 1
    for row in affected:
        for c, col in enumerate(snap_cols, start=1):
            cell = readme.cell(row=r, column=c, value=row.get(col, ""))
            cell.border = THIN_BORDER
            if col == "Feasibility":
                if "Not closeable" in str(row.get(col, "")):
                    cell.fill = LIGHT_UPDATED_FILL
                elif "near-full-enumeration" in str(row.get(col, "")):
                    cell.fill = LIGHT_WARNING_FILL
                elif "modest top-up" in str(row.get(col, "")):
                    cell.fill = LIGHT_FULL_FILL
        r += 1
    if not affected:
        readme.cell(row=r, column=1, value="No affected strata yet.")
        r += 1

    for c in range(1, LAST_COL + 1):
        readme.column_dimensions[get_column_letter(c)].width = 15 if c > 1 else 22
    readme.freeze_panes = None
    readme.sheet_view.showGridLines = False


def write_workbook(summary_rows, cluster_rows, ward_status, provenance_lookup, min_submission_date, reporting_stats):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)

    write_readme(wb, summary_rows, min_submission_date, reporting_stats)

    write_sheet(wb, "Strata Level", summary_rows)

    # Population and clusters are genuinely additive across pop_type (a
    # Non-IDP and an IDP person/cluster are different things - summing them
    # into one LGA total is correct). Area is NOT additive across pop_type
    # since 2026-08-27 (see analysis_accessible_area_layer.R's header): the
    # GIS layer now carries a separate eligible-area figure per pop_type
    # (e.g. IDP eligibility is a DTM-site-presence test, typically a much
    # smaller area than Non-IDP's hex-based eligibility, for the SAME LGA) -
    # summing or overwriting between the two would either double-count or
    # arbitrarily discard one, so area is kept as two separate column pairs
    # instead of one blended figure.
    lga_agg = defaultdict(lambda: {"state": "", "partners": set(), "n_pop": 0, "n_pop_acc": 0,
                                    "area": {}, "area_acc": {}, "clusters": 0, "clusters_acc": 0,
                                    "ward_keys": set()})
    for r in summary_rows:
        a = lga_agg[r["LGA"]]
        a["state"] = r["State"]
        a["partners"] |= {p.strip() for p in r["Partners covering"].split(",") if p.strip() and p.strip() != "NA"}
        a["n_pop"] += r["Total population (design, n_pop)"]
        a["n_pop_acc"] += r["Updated population within accessible area"]
        a["area"][r["Pop type"]] = r["Total area km2 (LGA)"]
        a["area_acc"][r["Pop type"]] = r["Updated area km2 (accessible)"]
        a["clusters"] += r["Total clusters (achieved)"]
        a["clusters_acc"] += r["Updated clusters within accessible area"]
    # Reported by/Last reported date rolled up from clusters directly
    # (their own ward_keys), not by re-parsing summary_rows' already-joined
    # strings - avoids any fragile round-tripping through a summarized value.
    for c in cluster_rows:
        lga_agg[c["lga"]]["ward_keys"] |= c["ward_keys"]
    lga_rows = []
    for lga, a in lga_agg.items():
        area_non_idp = a["area"].get("Non-IDP", 0)
        area_acc_non_idp = a["area_acc"].get("Non-IDP", 0)
        area_idp = a["area"].get("IDP", 0)
        area_acc_idp = a["area_acc"].get("IDP", 0)
        lga_reported_by, lga_last_date = aggregate_provenance(a["ward_keys"], provenance_lookup)
        lga_rows.append({
            "State": a["state"], "LGA": lga,
            "Partners covering": "; ".join(sorted(a["partners"])),
            "Total population (design)": round(a["n_pop"]),
            "Updated population (accessible)": round(a["n_pop_acc"]),
            "% population remaining": round(100 * a["n_pop_acc"] / a["n_pop"], 1) if a["n_pop"] else 0,
            "Non-IDP: total area km2": round(area_non_idp, 1),
            "Non-IDP: updated area km2 (accessible)": round(area_acc_non_idp, 1),
            "Non-IDP: % area remaining": round(100 * area_acc_non_idp / area_non_idp, 1) if area_non_idp else 0,
            "IDP: total area km2": round(area_idp, 1),
            "IDP: updated area km2 (accessible)": round(area_acc_idp, 1),
            "IDP: % area remaining": round(100 * area_acc_idp / area_idp, 1) if area_idp else 0,
            "Total clusters": a["clusters"],
            "Updated clusters (accessible)": a["clusters_acc"],
            "% clusters remaining": round(100 * a["clusters_acc"] / a["clusters"], 1) if a["clusters"] else 0,
            "Reported by": lga_reported_by,
            "Last reported date": lga_last_date,
        })
    lga_rows.sort(key=lambda r: r["Non-IDP: % area remaining"])
    write_sheet(wb, "LGA Summary", lga_rows)

    cluster_out = []
    for c in sorted(cluster_rows, key=lambda x: (x["state"], x["lga"], x["cluster_id"])):
        cluster_out.append({
            "Cluster ID": c["cluster_id"], "Strata ID": c["strata_id"],
            "Pop type": "Non-IDP" if c["pop_type"] == "non_idp" else "IDP",
            "State": c["state"], "LGA": c["lga"], "Ward(s)": c["wards"],
            "Primary HHs": c["n_primary"], "Primary HHs accessible": c["n_primary_accessible"],
            "Any part accessible": "Yes" if c["any_accessible"] else "No",
            "Fully accessible": "Yes" if c["all_accessible"] else "No",
            "Reported by": c["reported_by"], "Last reported date": c["last_reported_date"],
        })
    write_sheet(wb, "Cluster Level", cluster_out)

    log_rows = load_csv(SAMPLING_DIR + r"\resampling\output\resampling_requests_log.csv")
    # LATEST row only per (partner, state, lga, ward) - same latest-wins rule
    # as 02_ingest.latest_by_key()/04's latest_ward_reports(). Fixed
    # 2026-08-26 sanity check: the previous version included every 'No' row
    # ever logged regardless of supersession, which would show a
    # since-corrected ward as still-inaccessible the moment any partner
    # updates a prior report (not yet triggered by today's data, but a real
    # latent bug - this workbook needs to stay correct as more reports land).
    latest_ward_log = {}
    for r in log_rows:
        if r["report_level"] != "ward":
            continue
        key = (r["partner"], r["state"], r["lga"], r["ward_name"])
        if key not in latest_ward_log or int(r["request_id"]) > int(latest_ward_log[key]["request_id"]):
            latest_ward_log[key] = r
    inacc_log = [r for r in latest_ward_log.values() if r["accessible"].strip().lower() == "no"]
    log_out = []
    for r in inacc_log:
        log_out.append({
            "Partner": r["partner"], "State": r["state"], "LGA": r["lga"], "Ward": r["ward_name"],
            "Reason category": r["reason_category"], "Reason notes": r["reason_notes"],
            "Date reported": r["date_reported_by_partner"],
            "Reported by": r.get("reported_by") or "Needs review",
            "Request ID": r["request_id"],
        })
    write_sheet(wb, "Inaccessibility Report Log", log_out)

    wb.save(WORKBOOK_PATH)
    print(f"Wrote workbook to {WORKBOOK_PATH}")


if __name__ == "__main__":
    main()
