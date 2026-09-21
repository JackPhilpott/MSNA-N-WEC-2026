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
# accessible-only achieved_sample/N_hh figures computed here. Still used by
# sample_needed_for_moe()/target_sample_representativity() - a forward-
# looking "how many households would a uniform future draw need" question,
# where there's no real achieved distribution yet to measure unevenness in.
# realized_moe_unequal() (2026-09-14 port of scripts/shared/frame_status.R's
# Task 4 formula - see its own docstring) replaces realized_moe() wherever
# this script measures MoE against the REAL, already-uneven achieved
# distribution (the Feasibility column's moe_updated/moe_if_half_cluster_
# more) - the R pipeline switched 2026-09-13; this script had been left
# behind on the uniform formula until the overnight audit caught it.
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

import sys

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
sys.path.insert(0, PROJECT_DIR + r"\1_sampling\scripts\shared")
from assert_plausible import assert_plausible  # noqa: E402
from assert_fresh import assert_fresh  # noqa: E402
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
STRATA_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_strata_level_sampling_frame_v12_FULL.csv"
HOUSEHOLD_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v12_FULL.csv"
# 2026-09-13 (Task 1, target-inflation-fix batch): the single source of truth
# for "how many of this cluster's primary rows are actually accessible" -
# written by frame_status.R's compute_cluster_status(), which applies the
# FULL chain (ward-accessible, below-4-threshold, cluster-overlay-excluded).
# build_cluster_level() below used to recompute its own raw per-row count,
# which disagreed with this file for every straddling/below-threshold
# cluster - see project memory project_resampling_target_inflation_fix_
# 2026-09-13 for the before/after.
CLUSTER_STATUS_CSV = SAMPLING_DIR + r"\output\data\data_collection\NGA_MSNA_2026_cluster_status_v12.csv"
# Task 4 (2026-09-13): the STOP-mode gate's own baseline - each run's
# target_sample_representativity per stratum, compared against THIS run's.
# Not part of the workbook itself (an .xlsx is for humans to read/annotate,
# not a reliable round-trip source for a plausibility gate) - a small,
# dedicated, single-purpose tracking file, same pattern as _frame_
# version.txt/NGA_MSNA_2026_cluster_status_v12.csv elsewhere in this project.
TARGET_REPR_LAST_RUN_CSV = SAMPLING_DIR + r"\resampling\output\target_sample_representativity_last_run.csv"
MASTER_WARD_CSV = SAMPLING_DIR + r"\resampling\output\master_accessibility_status_ward_level.csv"
GIS_WARD_CSV = SAMPLING_DIR + r"\resampling\output\gis\accessible_area_lga_ward_portions.csv"
POOL_NON_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_non_idp.csv"
POOL_IDP_CSV = SAMPLING_DIR + r"\resampling\output\gis\remaining_eligible_pool_idp.csv"
# 2026-09-08 audit fix: was the dashboard_app/data/ bundled mirror, only
# refreshed as a side effect of a full dashboard deploy - same bug class
# already fixed in refresh_working_frame_daily.R/build_partner_dc_packages.py/
# merge_partner_resample_batch.R, missed here despite this script sizing
# every supplementary draw this week. Byte-identical to canonical at fix
# time (md5-verified) - a live landmine, not a wrong number yet.
REAL_SUBMISSIONS_CSV = PROJECT_DIR + r"\2_monitoring\data\real_submissions.csv"

# 2026-09-06: repointed from the abandoned revised_deletion_log_for_resampling_
# *.csv handoff (2_monitoring/cleaning/real/handoff_for_resampling/ - last fed
# 2026-08-30_v2, 8 days stale by the time this was caught) to
# CONFIRMED_DELETIONS_OVERLAY.csv - its deliberate, version-stamped
# replacement, built from 2_monitoring's recovery_issue_tracker.csv. Verified
# before repointing (not just per the orchestrator's word): join key is
# "uuid" on both sides, same as the old log; row counts/status breakdown
# checked directly against the file on disk. status in ("confirmed",
# "contested") both count as deletions (2026-09-13 fix - see
# load_real_achieved()'s own docstring for why "contested" changed from
# excluded to included), per Jack's explicit policy: deletion confirmation
# requires a genuine, deliberate decision (partner recovery-workbook
# response or a reviewed internal call, never an automatic default) - both
# statuses meet that bar once resolved, "contested" just means it was
# appealed first.
CONFIRMED_DELETIONS_OVERLAY_CSV = PROJECT_DIR + r"\2_monitoring\data\CONFIRMED_DELETIONS_OVERLAY.csv"
if not os.path.exists(CONFIRMED_DELETIONS_OVERLAY_CSV):
    raise FileNotFoundError(f"CONFIRMED_DELETIONS_OVERLAY.csv not found at {CONFIRMED_DELETIONS_OVERLAY_CSV}")
print(f"Using confirmed-deletions overlay: {os.path.basename(CONFIRMED_DELETIONS_OVERLAY_CSV)}")

# 2026-09-13 fix: the whole accessibility chain in this script (classify_
# households() below) was ward-level only - a partner reporting a SPECIFIC
# cluster inaccessible via the "Cluster Accessibility" sheet (while its ward
# stays accessible overall - found via ACF's returned report, 4 Tambuwal IDP
# sites reported relocated/inaccessible) had no pathway into this workbook at
# all, which is what extract_partner_shortfalls.R reads to size every
# redraw. resampling/scripts/build_cluster_accessibility_overlay.py derives
# this from resampling_requests_log.csv's cluster-level rows (already logged
# by 02_ingest_accessibility_reports.py, never read back out before now).
# Precedence rule (Jack, 2026-09-13, same as scripts/shared/frame_status.R's
# load_cluster_accessibility_overlay()): additive only - a cluster-level
# "No" excludes just that cluster on top of whatever the ward already says;
# it never overrides a ward-level status in either direction. Missing file
# is not an error (unlike the deletions overlay above) - this overlay is
# optional/additive, and build_cluster_accessibility_overlay.py may not have
# been run yet in a fresh checkout.
CLUSTER_ACCESSIBILITY_OVERLAY_CSV = SAMPLING_DIR + r"\resampling\output\cluster_accessibility_overlay.csv"


def load_cluster_accessibility_overlay():
    if not os.path.exists(CLUSTER_ACCESSIBILITY_OVERLAY_CSV):
        return set()
    return {r["cluster_id"] for r in load_csv(CLUSTER_ACCESSIBILITY_OVERLAY_CSV)}

TARGET_MOE_PCT = 10.0

OUT_DIR = SAMPLING_DIR + r"\resampling\output"
WORKBOOK_PATH = OUT_DIR + r"\NGA_MSNA_2026_accessibility_impact_workbook.xlsx"
UPDATED_FRAME_CSV = OUT_DIR + r"\NGA_MSNA_2026_stage2_sampling_frame_v12_WORKING_with_accessibility.csv"


def _to_int(v):
    """CSV cell -> int, or None for blank/'NA'/unparseable (frame exports
    write 'NA' for missing numerics)."""
    try:
        return int(float(v)) if v not in (None, "", "NA") else None
    except (TypeError, ValueError):
        return None


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


def realized_moe_unequal(achieved_sample, N_hh, cluster_sizes, ICC, Z=1.6448536269514722, p=0.5):
    """2026-09-14 port of scripts/shared/frame_status.R's realized_moe_
    unequal() (Task 4, built and verified there 2026-09-13) - this script
    had been left on the old realized_moe()'s simple deff = 1 + (m-1)*ICC,
    blind to how unevenly achieved sample is actually distributed across
    full vs. partial clusters (same "fixed in one place, not propagated"
    pattern as the achieved-counting bug from the night before - flagged in
    the overnight audit, Jack confirmed porting it here too).

    Kish's (1965) approximate design effect for unequal cluster sizes:
        deff = 1 + [(cv^2 + 1) * m_bar - 1] * ICC
    where m_bar = mean achieved cluster size, cv = coefficient of variation
    (sd/mean) of achieved cluster sizes. Reduces EXACTLY to the old
    1 + (m_bar - 1) * ICC when cv = 0 (uniform cluster sizes) - same
    algebraic identity already verified on the R side, not re-derived here:
    (0^2+1)*m_bar - 1 = m_bar - 1.

    @param cluster_sizes: achieved-primary-count per cluster in this
    stratum (i.e. n_primary_ceiling_contribution values, mirroring
    compute_strata_achieved()'s cluster_sizes output on the R side) - not
    required to pre-filter zeros/None, matches R's own defensive filter.
    Uses the sample standard deviation (n-1 divisor, matching R's sd())."""
    sizes = [s for s in cluster_sizes if s is not None and s > 0]
    if not sizes:
        return None
    if achieved_sample <= 0 or N_hh <= achieved_sample:
        return None
    m_bar = sum(sizes) / len(sizes)
    if len(sizes) > 1 and m_bar > 0:
        variance = sum((s - m_bar) ** 2 for s in sizes) / (len(sizes) - 1)
        cv = math.sqrt(variance) / m_bar
    else:
        cv = 0.0
    deff = 1 + ((cv ** 2 + 1) * m_bar - 1) * ICC
    ndeff = achieved_sample * (N_hh - 1) / (N_hh - achieved_sample)
    n0 = ndeff / deff
    if n0 <= 0:
        return None
    return math.sqrt(Z ** 2 * p * (1 - p) / n0) * 100


CERTAINTY_MIN_COVERAGE = 0.90  # see realized_moe_certainty_aware() condition (ii)


def realized_moe_certainty_aware(clusters, N_hh, m_used, pop_type, ICC=0.06, Z=1.6448536269514722, p=0.5):
    """2026-09-21, Jack-approved as a PARALLEL column (not yet driving any
    verdict): realized MoE under the variance model this design actually
    implies once certainty PSUs are recognised.

    realized_moe_unequal() treats every cluster as a sampled PSU and charges
    the Kish cluster penalty across all of them. But a PSU whose measure of
    size meets the sampling interval is selected with probability 1 - in
    this frame that is every cluster drawn more than once (selection_count
    > 1, i.e. target_households > m). A certainty PSU contributes NO
    between-PSU variance: its sample is a simple random sample of n_i
    households from its own N_i (households_in_cluster), with finite-
    population correction. Charging it a cluster penalty over-states MoE -
    Mafa IDP (idp_NG008019), where one camp holds 98.6% of the accessible
    population and every site is in the sample, reads 14.3% under the Kish
    formula and ~7.2% under this one; the same 162 interviews spread as
    uniform 6-hh clusters would read 7.3%, so the gap is entirely the
    penalty for the population living in one site. Same certainty concept
    the original design already uses at stratum level (Revision 2026-07-23).

    Model: stratified estimator, population-weighted.
      certainty PSUs (each):  W_i^2 * p(1-p)/n_i * (1 - n_i/N_i)
      sampled PSUs (pooled):  W_s^2 * p(1-p)/n0_s, n0_s from the existing
                              Kish formula over the sampled clusters only,
                              against the remaining population N_s.
    W_i = N_i/N_total, W_s = N_s/N_total, N_total = max(N_hh, sum N_i) -
    N_hh here is the ward-area-fraction accessible population, which can
    sit below the DTM household count of the sites actually sampled
    (Mafa: 6,743 vs 8,276), so the certainty sites' own N_i is never
    truncated. Boundary cases (MOS just above the interval but drawn once)
    are treated as sampled - the conservative direction; resolving them
    needs psu_probability, which the pipeline computes but does not export.

    The analysis-stage design declaration must mark the same PSUs as
    certainty units for the survey variance estimator to agree with this -
    that is part of the Task 2 weights/design work, not this script.

    RESTRICTED 2026-09-21 (same night, after my own checks found two flaws
    in the unrestricted version and Coordinator independently confirmed
    both): the treatment only applies when ALL of
      (i)   pop_type is IDP - Non-IDP households_in_cluster is a hex
            BUILDING count (source "building_footprint_count"), not on the
            same scale as the ward-fraction WorldPop N_hh nor the PPS MOS
            (non_idp_NG021010_4: 15,315 buildings vs a whole-stratum N_hh of
            59,450), which made 65 Non-IDP strata read WORSE than the
            rigorous formula - an artefact;
      (ii)  the certainty sites' summed N_i covers >= CERTAINTY_MIN_COVERAGE
            of N_total - the treatment is for strata whose population IS
            those sites (Mafa: 98.6%);
      (iii) if coverage < 100%, the remainder must have real interviews
            (sampled set non-empty) - otherwise population inside N_hh with
            no sampled PSU silently contributed ZERO variance (Talata Mafara
            IDP: 1 of 6 sites live, 526 of 1,561 hh, read 3.34%; Binji IDP
            0.0%). Coordinator's refinement: (ii) bounds that damage, (iii)
            prevents it structurally.
    Any condition failing -> returns None and the caller falls back to the
    rigorous realized_moe_unequal() figure, flagged as such in the output.
    selection_count > 1 as the certainty proxy is sufficient-not-necessary
    (misses MOS in [I, 2I) drawn once), so any residual error UNDERcounts
    certainty PSUs - i.e. overstates the Kish penalty, the conservative
    direction. Task 2 must use the same rule or the two MoEs diverge by a
    small, known, conservative-direction amount.

    ADOPTED 2026-09-21 (same night, Jack's decision) to drive Feasibility/
    Representativity verdicts, no longer parallel-only. Before switching,
    a full national run surfaced 4 strata reading WORSE under this formula
    than under realized_moe_unequal() - not one mechanism: idp_NG034021
    (Wamako, CRS) and idp_NG032001 (CRS) are a single near-empty certainty
    site's own SRS term dominating the stratum (n_i of 1 and 2 respectively
    - Wamako's is an access-lost site stranding one interview; idp_NG032001
    is its only cluster, period) - an artefact of trusting a tiny raw
    sample's own SRS variance in isolation. idp_NG008023 (Mobbar, FHI 360)
    and idp_NG034016 (DRC) are genuine: population concentrated in
    certainty sites that weren't drawn proportionally to their size (Gsss
    Camp Damasak is ~77% of Mobbar's stratum on a selection_count that
    under-samples it) - Kish's pooled penalty was masking a real precision
    problem there, not overstating one. CERTAINTY_MIN_N_I below fixes the
    first shape (a certainty site needs a real minimum sample before its
    own isolated SRS term is trusted; below it, the site is folded into the
    pooled "sampled" bucket instead, same treatment a non-certainty cluster
    of that size would get) without touching the second - a real
    non-proportional-allocation problem should read as worse, not be
    smoothed away. Confirmed both shapes empirically before choosing 3:
    Wamako/idp_NG032001 (n_i 1, 2) needed demoting; Mobbar/idp_NG034016
    (n_i 14, 12 per site) are nowhere near it and are unaffected."""
    CERTAINTY_MIN_N_I = 3
    live = [c for c in clusters if c["n_primary_ceiling_contribution"] > 0]
    if not live or pop_type != "idp":
        return None
    cert_all = [c for c in live if c.get("is_certainty") and c.get("households_in_cluster")]
    cert = [c for c in cert_all if c["n_primary_ceiling_contribution"] >= CERTAINTY_MIN_N_I]
    demoted = [c for c in cert_all if c["n_primary_ceiling_contribution"] < CERTAINTY_MIN_N_I]
    samp = [c for c in live if c not in cert_all] + demoted
    N_cert = sum(c["households_in_cluster"] for c in cert)
    N_total = max(float(N_hh or 0), N_cert)
    if N_total <= 0 or not cert:
        return None
    if N_cert / N_total < CERTAINTY_MIN_COVERAGE:
        return None
    if N_cert < N_total and not samp:
        return None
    var = 0.0
    for c in cert:
        n_i, N_i = c["n_primary_ceiling_contribution"], c["households_in_cluster"]
        fpc = max(0.0, 1 - n_i / N_i)
        var += (N_i / N_total) ** 2 * p * (1 - p) / n_i * fpc
    if samp:
        N_s = max(N_total - N_cert, 0.0)
        n_s = sum(c["n_primary_ceiling_contribution"] for c in samp)
        if N_s > n_s:
            sizes = [c["n_primary_ceiling_contribution"] for c in samp]
            m_bar = sum(sizes) / len(sizes)
            cv = (math.sqrt(sum((s - m_bar) ** 2 for s in sizes) / (len(sizes) - 1)) / m_bar) if len(sizes) > 1 else 0.0
            deff = 1 + ((cv ** 2 + 1) * m_bar - 1) * ICC
            ndeff = n_s * (N_s - 1) / (N_s - n_s)
            n0 = ndeff / deff
            if n0 > 0:
                var += (N_s / N_total) ** 2 * p * (1 - p) / n0
    return Z * math.sqrt(var) * 100


def certainty_site_topup_needed(clusters, N_hh, m_used, pop_type, target_moe_pct):
    """2026-09-21 (Jack, Task 3 review - route accepted): the smallest number
    of extra interviews at ONE existing certainty site that brings the
    certainty-PSU-aware MoE to <= target_moe_pct, everything else held.
    Returns (k, cluster) or None.

    A certainty site is its own stratum under realized_moe_certainty_aware(),
    so extra interviews there cut its SRS term directly, with no cluster
    penalty. The Feasibility search below only projects NEW pool clusters
    under the rigorous formula, which can't move a certainty verdict - it
    labelled Mobbar/Dan Musa/Safana/Kafur IDP "NOT recoverable" when +29/+2/
    +5/+1 interviews at their biggest site would each reach 10%. Only sites
    already treated as certainty units qualify (n_i >= the same floor of 3),
    and only ones still ACCESSIBLE (n_primary_accessible > 0): the first
    version of this search picked Kafur's Arewaci site, which is
    partially_completed_access_lost - its completed interviews still count
    in the ceiling, but nobody can go back. k is bounded by the site's own
    headroom (N_i - n_i)."""
    best = None
    for c in clusters:
        if not (c.get("is_certainty") and c.get("households_in_cluster") and c["n_primary_ceiling_contribution"] >= 3
                and c["n_primary_accessible"] > 0):
            continue
        headroom = int(c["households_in_cluster"] - c["n_primary_ceiling_contribution"])
        for k in range(1, headroom + 1):
            if best is not None and k >= best[0]:
                break
            trial = [dict(x, n_primary_ceiling_contribution=x["n_primary_ceiling_contribution"] + k) if x is c else x
                     for x in clusters]
            moe = realized_moe_certainty_aware(trial, N_hh, m_used, pop_type)
            if moe is not None and moe <= target_moe_pct:
                best = (k, c)
                break
    return best


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


# Task 2 (2026-09-13, target-inflation-fix batch, AMENDED per Jack's 2026-09-13
# night decision): replaces target_sample_current (2_monitoring's own copy,
# which sums target_households from FULL and never subtracts a cluster once
# it goes inaccessible - only ever grows) with a freshly-computed TRUE
# requirement, persisted every run, for every stratum, applied against the
# CURRENT accessible frame - this IS the retroactive correction, not just a
# prospective one.
#
# Jack's explicit scope decisions, don't relitigate without his sign-off:
# - ICC stays fixed at 0.06 everywhere - no empirical estimation, no
#   per-stratum calibration. Too risky to change a core design assumption
#   mid-survey without full confidence in it.
# - No disaggregation logic of any kind - fully out of scope, not deferred.
# - MARGIN = 1.05, a flat 5% operational margin applied UNIFORMLY to every
#   stratum (deliberately not per-stratum-empirical, to avoid the same
#   small-sample-noise/results-driven-adjustment risk Jack rejected for both
#   ICC and disaggregation above). Grounded in the real national confirmed-
#   deletion rate verified directly against CONFIRMED_DELETIONS_OVERLAY.csv
#   vs real_submissions.csv the night this was decided: 6.53% of all
#   submissions, 94.7% of that specifically duration_under_20. This is NOT
#   the same thing as the existing 10% non-response reserve buffer (which
#   backstops a household never reached) - this margin protects against a
#   real, ALREADY-COMPLETED interview later getting invalidated. The two
#   apply independently; never conflate or compound them.
MARGIN_OPERATIONAL = 1.05


def target_sample_representativity(N_hh_accessible, m, target_moe_pct=TARGET_MOE_PCT, ICC=0.06, margin=MARGIN_OPERATIONAL):
    """target_sample_representativity = min(N_hh_accessible,
    sample_needed_for_moe(target_moe_pct, N_hh_accessible, m, ICC) * margin).
    The outer min() re-caps AFTER the margin is applied - sample_needed_for_
    moe() already caps at N_hh internally, but the *margin multiplied on top
    can push back above it, and a stratum can never need to survey more
    households than are actually accessible, margin or not. Returns None if
    the accessible population is too small for the underlying formula to be
    meaningful (mirrors sample_needed_for_moe()'s own None case)."""
    raw = sample_needed_for_moe(target_moe_pct, N_hh_accessible, m, ICC)
    if raw is None:
        return None
    return min(N_hh_accessible, raw * margin)


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


def classify_households(ward_status, cluster_overlay_excluded=None):
    """Loads the household-level WORKING frame and tags every row with
    accessible_status, using its own (adm1_name, adm2_name, adm3_name) - the
    exact same per-household ward attribution used everywhere else in this
    project (Stage 2's own point-in-polygon join). Rows whose ward has no
    entry in the master status (no partner's clusters ever touched it,
    vanishingly rare given the master file is itself built from this same
    frame) default Accessible.

    2026-09-13: cluster_overlay_excluded (from load_cluster_accessibility_
    overlay() above) then additionally forces Inaccessible for any row whose
    cluster_id was explicitly reported inaccessible at CLUSTER level - on
    top of the ward-level result, never overriding it back to Accessible
    (a cluster-level "No" only ever adds an exclusion, per Jack's 2026-09-13
    precedence rule - this overlay never contains a "Yes" to override with)."""
    if cluster_overlay_excluded is None:
        cluster_overlay_excluded = load_cluster_accessibility_overlay()
    rows = load_csv(HOUSEHOLD_CSV)
    # FULL includes population-floor/certainty-excluded strata (correctly
    # dropped from the sampling universe altogether, e.g. Dandume/Faskari) -
    # excluded here so they don't reappear in the accessibility picture,
    # same scope WORKING used to give this script before the FULL switch.
    rows = [r for r in rows if r.get("coverage_status") == "covered" and r.get("exclusion_reason") in ("none", "", None)]
    for r in rows:
        key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
        status = ward_status.get(key, "Accessible")
        if r["cluster_id"] in cluster_overlay_excluded:
            status = "Inaccessible"
        r["_accessible_status"] = status
    return rows


def load_cluster_status():
    """cluster_id -> {n_accessible_primary_post_threshold, status, n_achieved}
    (all from CLUSTER_STATUS_CSV, frame_status.R's compute_cluster_status()).
    Missing entirely (script never run) is a hard error, not a silent
    0-default - this is now the sizing basis for the whole workbook's
    MoE/target/feasibility columns, too consequential to quietly treat an
    absent file as "everything is 0 accessible everywhere."

    2026-09-14 (post-Task-5 audit finding, Jack confirmed the fix): status/
    n_achieved added alongside the post-threshold count so build_cluster_
    level() can correct for real over-collection at COMPLETED clusters -
    see that function's own docstring for the full mechanism."""
    if not os.path.exists(CLUSTER_STATUS_CSV):
        raise FileNotFoundError(
            f"{CLUSTER_STATUS_CSV} not found - run refresh_working_frame_daily.R "
            f"(or merge_partner_resample_batch.R) first to generate it."
        )
    rows = load_csv(CLUSTER_STATUS_CSV)
    return {
        r["cluster_id"]: {
            "n_accessible_primary_post_threshold": int(r["n_accessible_primary_post_threshold"]),
            "status": r["status"],
            "n_achieved": int(r["n_achieved"]),
        }
        for r in rows
    }


def load_last_run_targets():
    """strata_id -> (target_sample_representativity, N_hh_accessible) as of
    the LAST run (Task 4's STOP-gate baseline). Empty dict if the file
    doesn't exist yet - that's the legitimate first-run case (no baseline to
    compare against yet), not an error.

    2026-09-14 (per Jack, after the gate correctly caught a real INTERSOS
    accessibility gain in Maru and stopped to ask about it): N_hh_accessible
    is now persisted alongside the target so the gate below can tell WHY a
    target moved, not just THAT it moved - see that gate's own updated
    comment for the corrected rule. Reading an old-format file (no
    N_hh_accessible column, from before this change) defaults it to None,
    which the gate treats as "can't confirm an accessibility gain" - i.e.
    still flags an increase, same as the original behaviour, rather than
    silently passing every stratum once on the format upgrade."""
    if not os.path.exists(TARGET_REPR_LAST_RUN_CSV):
        return {}
    rows = load_csv(TARGET_REPR_LAST_RUN_CSV)
    return {
        r["strata_id"]: {
            "target_sample_representativity": float(r["target_sample_representativity"]),
            "N_hh_accessible": float(r["N_hh_accessible"]) if r.get("N_hh_accessible") not in (None, "") else None,
        }
        for r in rows
    }


def write_last_run_targets(new_targets):
    """Persist this run's target_sample_representativity + N_hh_accessible
    per stratum, for the NEXT run's Task 4 comparison. Only called after
    that comparison has already passed for THIS run - a failed run must not
    silently become the new baseline. new_targets: strata_id -> {"target_
    sample_representativity": float, "N_hh_accessible": float}."""
    with open(TARGET_REPR_LAST_RUN_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["strata_id", "target_sample_representativity", "N_hh_accessible"])
        w.writeheader()
        for strata_id, vals in sorted(new_targets.items()):
            w.writerow({"strata_id": strata_id, **vals})


def build_cluster_level(household_rows, provenance_lookup, cluster_status_lookup):
    """One row per cluster_id: strata_id, pop_type, any_accessible (bool -
    at least one PRIMARY household accessible), all_accessible (bool - every
    primary household accessible), primary/reserve counts, state/lga/wards
    touched, and (2026-08-28) reported_by/last_reported_date - aggregated
    across every ward this cluster's households actually touch (clusters
    spanning >1 ward are real, ~35% nationally - see 01_generate_
    accessibility_reports.py's known ward-splitting fix), not just one
    representative ward, via the same aggregate_provenance() used at
    strata/LGA grain below - so a multi-ward cluster correctly shows
    'Mixed'-style provenance rather than silently picking one ward's.

    2026-09-13 (Task 1): n_primary_accessible now comes from
    cluster_status_lookup (frame_status.R's compute_cluster_status(), the
    same post-threshold/cluster-overlay-aware figure the real WORKING frame
    uses) instead of a raw per-row count computed here - the two disagreed
    for every straddling or below-threshold-dropped cluster before this.
    any_accessible/all_accessible derive from the SAME corrected count now,
    for the same reason. n_capacity_accessible (primary+reserve, reference-
    only ceiling - see its own comment at the call site below) is
    deliberately UNCHANGED/still raw per-row - out of this task's stated
    scope, and it's explicitly not the resampling decision basis.

    2026-09-14 (post-Task-5 audit finding, Jack confirmed the fix): a NEW,
    separate field, n_primary_ceiling_contribution, for the Achievable-
    Ceiling/Feasibility calculation specifically - deliberately NOT the same
    as n_primary_accessible above, which stays a precise "real accessible
    primary ROW count" (Task 1's own stated purpose, unchanged). For a
    COMPLETED cluster, uses max(n_primary_accessible, n_achieved) instead of
    just n_primary_accessible - real over-collection at a completed cluster
    (achieved > nominal target_households, confirmed common: idp_NG002001
    alone had one cluster with target=6/achieved=20) was silently
    undercounted by the ceiling before this, masked as long as there was
    leftover not-yet-achieved nominal capacity elsewhere in the stratum to
    compensate - Task 5's drop-rule correctly removed that unneeded
    capacity, which is what exposed the gap (3 strata read "exceeds
    remaining pool" when they'd already genuinely met target - see project
    memory project_resampling_target_inflation_fix_2026-09-13 for the full
    trace).

    2026-09-14b (same night, second real gap in this same fix - found by
    Coordinator tracing a ZOA "target/achieved/still needed don't add up"
    question, independently re-verified here before applying): the
    docstring above originally claimed "for any non-completed cluster this
    is always a no-op, since status != completed implies n_achieved <
    n_primary_accessible" - true only while a cluster is still accessible.
    For status == "partially_completed_access_lost" specifically,
    n_primary_accessible (== n_accessible_primary_post_threshold) correctly
    reads 0 the moment access is lost, while n_achieved can still be > 0
    (real work done before access was lost) - so the same undercounting
    this fix was built to close was still happening for every partially-
    completed-then-access-lost cluster. Confirmed on ZOA's own live data:
    non_idp_NG...{_11,_12,_17,_2} carry 5+4+3+4=16 real achieved households
    that were contributing 0 to the ceiling. Quantified nationally before
    applying: 197 clusters, 1,187 households of ceiling credit, across 36
    strata - a real, non-trivial undercount, not an edge case. Fixed by
    extending the status check to also cover partially_completed_access_
    lost - same justification as the completed case (real achieved credit
    must never vanish from the ceiling just because the cluster later lost
    access, whether it finished first or not). not_started_access_lost and
    not_started_other are correctly left alone - by definition n_achieved
    is 0 for a genuinely not-started cluster, so max() has nothing to
    correct there regardless."""
    by_cluster = defaultdict(list)
    for r in household_rows:
        by_cluster[r["cluster_id"]].append(r)

    out = []
    for cid, rows in by_cluster.items():
        primaries = [r for r in rows if r["status"] == "primary"]
        any_row = rows[0]
        cs = cluster_status_lookup.get(cid, {"n_accessible_primary_post_threshold": 0, "status": None, "n_achieved": 0})
        n_primary_accessible = cs["n_accessible_primary_post_threshold"]
        n_primary_ceiling_contribution = (
            max(n_primary_accessible, cs["n_achieved"])
            if cs["status"] in ("completed", "partially_completed_access_lost")
            else n_primary_accessible
        )
        # 2026-08-29: capacity ceiling for the resampling decision - EVERY
        # household row (primary + reserve) in an accessible ward, not just
        # primary. Same per-household accessible-ward filter n_primary_
        # accessible used to use (a multi-ward cluster's inaccessible-ward
        # rows still don't count), just extended to include reserve slots -
        # this is "if every currently-assigned, accessible slot in this
        # cluster were completed," the actual ceiling the resampling
        # decision needs (see load_real_achieved()'s caller). Left as a raw
        # per-row count (not threshold-corrected) - see docstring above.
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
            "n_primary_accessible": n_primary_accessible,
            "n_primary_ceiling_contribution": n_primary_ceiling_contribution,
            "n_capacity_accessible": len(acc_capacity),
            # 2026-09-21, for realized_moe_certainty_aware(): a cluster drawn
            # more than once (selection_count > 1 <=> target_households > m)
            # was selected with probability 1 - a certainty PSU. N_i is the
            # cluster's own household universe (DTM site households for IDP,
            # building count for a Non-IDP hex).
            "households_in_cluster": _to_int(any_row.get("households_in_cluster")),
            "site_name": any_row.get("iom_site_name") or "",
            "selection_count": _to_int(any_row.get("selection_count")) or 1,
            "is_certainty": (_to_int(any_row.get("selection_count")) or 1) > 1,
            "any_accessible": n_primary_accessible > 0,
            "all_accessible": n_primary_accessible == len(primaries) and len(primaries) > 0,
            "reported_by": reported_by,
            "last_reported_date": last_date,
        })
    return out


def load_collected_samples(exclude_cluster_ids=frozenset()):
    """matched_strata_id -> collected count (completed, not quality-flagged).
    Also matched_cluster_id -> collected count, for the accessible-area-only
    figure. Also returns the earliest submission_date in the file, for the
    README's data-recency note - computed from the real data every run
    rather than hardcoded, so it can't go stale.
    2026-09-21: exclude_cluster_ids = MSNA Light clusters. They share their
    design stratum's strata_id, so without this their interviews counted
    toward the Full Design stratum - against Jack's 2026-09-11 rule. See
    main()'s MSNA Light note."""
    rows = load_csv(REAL_SUBMISSIONS_CSV)
    clean = [r for r in rows if r["interview_outcome"] == "completed" and r["any_quality_flag"] == "FALSE"
             and r.get("matched_cluster_id") not in exclude_cluster_ids]
    by_strata = defaultdict(int)
    by_cluster = defaultdict(int)
    for r in clean:
        by_strata[r["matched_strata_id"]] += 1
        if r["matched_cluster_id"]:
            by_cluster[r["matched_cluster_id"]] += 1
    min_date = min((r["submission_date"] for r in rows if r["submission_date"]), default="N/A")
    return by_strata, by_cluster, min_date


def load_real_achieved(exclude_cluster_ids=frozenset()):
    """2026-09-21: exclude_cluster_ids = MSNA Light clusters, same reason as
    load_collected_samples() - see main()'s MSNA Light note.

    TRUE achieved sample per matched_cluster_id/matched_strata_id - the
    resampling-decision figure, added 2026-08-29 per Jack's own explicit
    formula (2_monitoring is the single source of truth for this, don't
    re-derive it differently):
        is_collected = interview_outcome == "completed"
        is_achieved  = is_collected & !is.na(matched_survey_id)
    2026-09-14 fix (Coordinator cross-check): dropped an independent
    is_duplicate=="TRUE" exclusion that was never part of this formula -
    a raw/pending signal, not a confirmed deletion decision, silently
    reimposing the pre-2026-09-11 pessimistic policy. 1,323 real completed
    interviews nationally were wrongly excluded this way - see frame_
    status.R's compute_achieved_lookup() for the full trace.
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
    FIX 2026-09-13: "contested" rows used to be explicitly EXCLUDED from
    deletion_uuids here, on the reasoning that a contested-but-unresolved
    issue isn't a genuine deliberate deletion decision - true when this was
    written (2026-09-06, all 10 contested rows then were genuinely still
    open, "none finalized either way"). Found stale while consolidating the
    R-side equivalent (scripts/shared/frame_status.R): those exact 10 rows
    were resolved by 2026-09-11 (checked directly - every one's resolution
    text now reads "contest reviewed and rejected - deletion stands"),
    making "contested" here mean "appealed AND upheld", equally terminal as
    "confirmed" - matches 2_monitoring's own TERMINAL_STATUSES = {"confirmed",
    "contested"} (issue_tracker.R) and refresh_partner_workbooks_daily.py's
    2026-09-11 fix, which this script had been missed by until now.

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
    deletion_uuids = {r["uuid"] for r in load_csv(CONFIRMED_DELETIONS_OVERLAY_CSV) if r["status"] in ("confirmed", "contested")}

    def is_achieved(r):
        return (
            r["interview_outcome"] == "completed"
            and r["matched_survey_id"] not in (None, "", "NA")
            and r["submission_uuid"] not in deletion_uuids
            and r.get("matched_cluster_id") not in exclude_cluster_ids
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
    print("Loading per-cluster status (post-threshold accessible-primary counts)...")
    cluster_status_lookup = load_cluster_status()
    cluster_rows = build_cluster_level(household_rows, provenance_lookup, cluster_status_lookup)
    cluster_by_id = {c["cluster_id"]: c for c in cluster_rows}

    # 2026-09-21 (Jack): MSNA Light never counts toward a Full Design stratum.
    # MSNA Light clusters (the government-negotiated, disclosed-only sample in
    # Abadam, Nganzai and Guzamala, 2026-09-11) share their design stratum's
    # strata_id, and until now this script had no MSNA Light handling at all -
    # so their clusters sat in the Full Design ceiling and MoE, and their
    # interviews in collected/achieved. That was the whole of Abadam Non-IDP's
    # "Representative 8.79%" (it has no Full Design cluster with sample) and
    # took Nganzai Non-IDP from 12.45% to 7.37%. Found by the fixed drop
    # rule's safety check, which recomputes every stratum's MoE the
    # frame_status.R way (MSNA Light already excluded there and in both
    # partner-workbook generators) and refused to run on a mismatch. MSNA
    # Light clusters stay in the row-level outputs; they're only kept out of
    # per-stratum figures.
    msna_light_cluster_ids = frozenset(
        r["cluster_id"] for r in household_rows if r.get("sampling_method") == "MSNA Light")
    print(f"Excluding {len(msna_light_cluster_ids)} MSNA Light cluster(s) from every Full Design stratum figure.")

    print("Loading real submissions (collected samples)...")
    collected_by_strata, collected_by_cluster, min_submission_date = load_collected_samples(msna_light_cluster_ids)
    print("Loading real achieved samples for resampling decisions (canonical formula + deletion log)...")
    real_achieved_by_strata, real_achieved_by_cluster = load_real_achieved(msna_light_cluster_ids)

    # 2026-09-14 gap found via a Jack question, not an audit: this pool CSV
    # (analysis_remaining_eligible_pool.R's own output) had gone stale
    # 2026-09-11 -> 2026-09-14 (three days, several accessibility batches)
    # with nothing catching it - unlike the ward shapefile just above, which
    # draw_supplementary_clusters_batch.R/draw_supplementary_idp_sites_
    # batch.R already gate on via assert_fresh(mode="stop"). No draw was
    # ever mis-sized by this (the real draw scripts compute their own
    # candidate pool fresh, never read this CSV) - but this script's own
    # "Remaining eligible pool"/Feasibility columns, which DECIDE which
    # strata get a draw at all, were reading a stale figure. Same mode/
    # source-of-truth pattern as the shapefile's own gate below: this pool
    # is directly derived from the shapefile, so that's what it must not
    # predate.
    print("Loading remaining eligible pool (non-IDP hexes, IDP DTM sites)...")
    for pool_csv in (POOL_NON_IDP_CSV, POOL_IDP_CSV):
        assert_fresh(
            artifact_path=pool_csv,
            source_paths=[GIS_WARD_CSV],
            mode="stop",
            fix_hint='Rscript "resampling/scripts/analysis_remaining_eligible_pool.R"',
            label=os.path.basename(pool_csv),
        )
    pool_non_idp = load_pool_lookup(POOL_NON_IDP_CSV, "accessible_unselected_hexes")
    pool_idp = load_pool_lookup(POOL_IDP_CSV, "accessible_unselected_sites")

    print("Loading strata frame and computing stratum-level summary...")
    strata_rows = load_csv(STRATA_CSV)
    strata_rows = [s for s in strata_rows if s.get("coverage_status") == "covered" and s.get("exclusion_reason") in ("none", "", None)]

    strata_clusters = defaultdict(list)
    for c in cluster_rows:
        if c["cluster_id"] in msna_light_cluster_ids:  # see the MSNA Light note above
            continue
        strata_clusters[c["strata_id"]].append(c)

    last_run_targets = load_last_run_targets()
    new_run_targets = {}

    summary_rows = []
    partner_reference_rows = []  # Task 6
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
        #
        # 2026-09-14 (post-Task-5 audit finding, Jack confirmed the fix):
        # summed from n_primary_ceiling_contribution, NOT primaries_
        # accessible - a completed cluster's contribution here is max(its
        # own row count, its real n_achieved), so genuine over-collection
        # correctly counts toward the ceiling instead of being invisibly
        # capped at the nominal target. primaries_accessible itself (used
        # for "[UPDATED AREA] Target samples" below) is deliberately left
        # as the precise row-count figure Task 1 built it to be - this
        # correction is scoped to the ceiling/Feasibility calculation only.
        primary_ceiling_accessible = sum(c["n_primary_ceiling_contribution"] for c in clusters)
        # Reference only, NOT used for the decision - what the ceiling WOULD
        # be if reserves were also fully exhausted. Kept visible so the
        # tradeoff (a specific stratum's gap could technically be closed by
        # asking a partner to fully work their reserve list instead of
        # resampling) stays visible, even though it's not being used as a
        # standard lever - see resampling/RESAMPLING_DECISION_RULES.md §3.
        capacity_ceiling_accessible = sum(
            c["n_capacity_accessible"] for c in clusters if c["any_accessible"]
        )

        # 2026-09-14: realized_moe() -> realized_moe_unequal() (Task 4 port,
        # see that function's own docstring) - this workbook's own Feasibility
        # column had been left on the simple uniform-cluster-size formula
        # while the R pipeline (refresh_working_frame_daily.R, merge_
        # partner_resample_batch.R) already switched 2026-09-13. cluster_
        # sizes = each cluster's n_primary_ceiling_contribution (mirrors
        # compute_strata_achieved()'s cluster_sizes on the R side; zeros are
        # dropped internally by realized_moe_unequal(), same as R's own
        # defensive filter) - sums to exactly primary_ceiling_accessible.
        ceiling_cluster_sizes = [c["n_primary_ceiling_contribution"] for c in clusters]
        moe_updated = (
            realized_moe_unequal(primary_ceiling_accessible, N_hh_accessible, ceiling_cluster_sizes, ICC=0.06)
            if N_hh_accessible > 0 else None
        )
        # 2026-09-21: parallel certainty-PSU-aware figure. Reported alongside
        # moe_updated, NOT used by Feasibility/Representativity below until
        # Jack switches the verdict over explicitly (Coordinator-verified first).
        moe_certainty_raw = realized_moe_certainty_aware(clusters, N_hh_accessible, m_used, pop_type, ICC=0.06) if N_hh_accessible > 0 else None
        certainty_applied = moe_certainty_raw is not None
        # Where the restricted treatment doesn't apply, the parallel column
        # carries the rigorous figure so it is never blank or misleading.
        moe_certainty = moe_certainty_raw if certainty_applied else moe_updated

        # Task 2 (2026-09-13, AMENDED): the true, margined, capped
        # requirement - see target_sample_representativity()'s own
        # docstring for the formula and Jack's scope decisions (ICC fixed,
        # no disaggregation, flat 5% margin). Computed for EVERY stratum,
        # every run, regardless of current shortfall status - this is the
        # persisted, retroactive-correction figure 2_monitoring reads in
        # place of target_sample_current.
        target_repr = target_sample_representativity(N_hh_accessible, m_used) if N_hh_accessible > 0 else None
        if target_repr is not None:
            new_run_targets[strata_id] = {
                "target_sample_representativity": target_repr,
                "N_hh_accessible": N_hh_accessible,
            }
        # 2026-09-14, per Jack: a household count is a whole unit - display
        # it as one. target_repr itself stays a precise float internally
        # (Feasibility/additional-clusters-needed math and the Task 4 gate
        # above both want full precision to catch small real changes), but
        # every place this figure is actually shown as "the target sample"
        # rounds UP to a whole household, never down - this is a minimum
        # requirement, so ceil() is the only direction that doesn't
        # understate it. Previously round(target_repr, 1) - a stray decimal
        # place on a household count that was never a deliberate display
        # choice, just never caught until now.
        target_repr_display = math.ceil(target_repr) if target_repr is not None else None

        # --- Feasibility: additional clusters needed to reach TARGET_MOE_PCT, and
        # whether the remaining accessible-unselected pool can actually supply them.
        # Driven by the primary-only achievable ceiling - see above.
        #
        # 2026-09-21: initial gate switched from moe_updated (rigorous only)
        # to moe_certainty (certainty-PSU-aware where the restricted
        # conditions apply, rigorous otherwise - see realized_moe_certainty_
        # aware()'s docstring for the adoption decision and the n_i floor
        # that fixed its two artefact cases). The half-cluster/additional-
        # clusters-needed SEARCH below stays on the rigorous realized_moe_
        # unequal() deliberately, not switched: a hypothetical future
        # cluster is drawn from the remaining pool as an ordinary sampled
        # PSU, never a certainty unit, so projecting it forward under the
        # rigorous model is the methodologically correct choice, not an
        # oversight. A stratum whose moe_certainty already clears the gate
        # never reaches this search at all.
        pool = pool_non_idp.get(adm2_pcode, 0) if pop_type == "non_idp" else pool_idp.get(adm2_pcode, 0)
        if moe_certainty is not None and moe_certainty <= TARGET_MOE_PCT:
            feasibility = "Already at/under target"
            additional_clusters_needed = 0
        elif target_repr is None:
            feasibility = "Not computable (accessible population too small)"
            additional_clusters_needed = None
        else:
            # Task 3 (2026-09-13, pinned down directly with Jack - single
            # MoE-based check, no household-count proxy): would half a
            # cluster more (m_used/2 households) bring realized MoE to
            # <=TARGET_MOE_PCT? If so - whether because we're effectively
            # already there or just within reach - the gap is smaller than
            # cluster granularity can usefully close; skip the draw rather
            # than round up to a whole new cluster. This single check
            # subsumes "already at target" (handled above) and "gap too
            # small to bother with" - MoE only ever shrinks as achieved
            # grows, so no separate condition is needed for the two cases.
            half_cluster = m_used / 2
            hypothetical_ceiling = primary_ceiling_accessible + half_cluster
            if hypothetical_ceiling >= N_hh_accessible:
                moe_if_half_cluster_more = 0.0  # would meet/exceed the whole accessible population
            else:
                # 2026-09-14: same realized_moe_unequal() port as above -
                # the hypothetical half-cluster top-up is modelled as one
                # extra synthetic cluster of size half_cluster added to the
                # stratum's real achieved-cluster-size distribution (not
                # just bumping the total), so its effect on cv/deff is
                # accounted for consistently with the real calculation
                # above rather than silently reverting to the uniform
                # formula for this one branch.
                moe_if_half_cluster_more = realized_moe_unequal(
                    hypothetical_ceiling, N_hh_accessible, ceiling_cluster_sizes + [half_cluster], ICC=0.06
                )

            if moe_if_half_cluster_more is not None and moe_if_half_cluster_more <= TARGET_MOE_PCT:
                feasibility = "Negligible gap - not worth a supplementary draw"
                additional_clusters_needed = 0
            else:
                # FIXED 2026-09-21 - CRITICAL, see 1_sampling/CLAUDE.md and
                # project memory project_feasibility_moe_override_bug_2026-
                # 09-21 for the full incident. This branch previously used
                # `additional_samples = max(0, target_repr - primary_
                # ceiling_accessible)` to size the gap - target_repr's own
                # formula (sample_needed_for_moe()) assumes UNIFORM cluster
                # sizes and is blind to real cluster-size unevenness, unlike
                # moe_updated/moe_if_half_cluster_more above (both already
                # rigorously Kish-DEFF-corrected). Whenever the ceiling
                # already covered target_repr's cruder number, this branch
                # silently set additional_clusters_needed=0 and labelled
                # the stratum "Already at/under target" - directly
                # contradicting the rigorous moe_updated/moe_if_half_
                # cluster_more checks that had JUST established a real gap
                # exists (that's exactly how we got here). Found to affect
                # 155 of 307 strata nationally, just over half the frame.
                #
                # Fix: find the TRUE minimum number of additional m_used-
                # sized clusters by iterating the SAME rigorous
                # realized_moe_unequal() formula used above - not a
                # different, cruder one. Searches independently of the
                # remaining pool size (pool only decides the FEASIBILITY
                # LABEL afterward, never how many are genuinely needed) so
                # a pool-exhausted stratum still reports its true
                # requirement, not a number capped to look achievable.
                max_search = math.ceil(max(0, N_hh_accessible - primary_ceiling_accessible) / m_used) + 1
                additional_clusters_needed = max_search
                for n_extra in range(1, max_search + 1):
                    trial_ceiling = primary_ceiling_accessible + n_extra * m_used
                    if trial_ceiling >= N_hh_accessible:
                        additional_clusters_needed = n_extra
                        break
                    trial_moe = realized_moe_unequal(
                        trial_ceiling, N_hh_accessible, ceiling_cluster_sizes + [m_used] * n_extra, ICC=0.06
                    )
                    if trial_moe is not None and trial_moe <= TARGET_MOE_PCT:
                        additional_clusters_needed = n_extra
                        break

                if pool <= 0:
                    feasibility = "Not closeable - no remaining pool left"
                elif additional_clusters_needed > pool:
                    feasibility = "Not closeable - exceeds remaining pool (recommend indicative)"
                elif additional_clusters_needed / pool > 0.5:
                    feasibility = "Closeable only via most of remaining pool (near-full-enumeration)"
                else:
                    feasibility = "Closeable with a modest top-up"

                # 2026-09-21 (Jack, Task 3 review): a certainty stratum the
                # new-cluster search can't close may still close with extra
                # interviews at one of its certainty sites - see
                # certainty_site_topup_needed(). additional_clusters_needed
                # goes to 0 because this route adds no clusters (and keeps
                # these strata out of extract_partner_shortfalls.R's
                # cluster-draw requests); the interview count is in the label.
                if certainty_applied and feasibility.startswith("Not closeable"):
                    topup = certainty_site_topup_needed(clusters, N_hh_accessible, m_used, pop_type, TARGET_MOE_PCT)
                    if topup is not None:
                        k, site = topup
                        where = f"{site['site_name']}, {site['cluster_id']}" if site["site_name"] else site["cluster_id"]
                        feasibility = f"Closeable via extra interviews at a certainty site (+{k} at {where})"
                        additional_clusters_needed = 0

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
            "Realized MoE % (updated area, rigorous Kish formula, reference only since 2026-09-21)": round(moe_updated, 2) if moe_updated is not None else "N/A (sample >= N_hh or 0 accessible)",
            "Realized MoE % (certainty-PSU-aware, DRIVES Feasibility/Representativity since 2026-09-21)": round(moe_certainty, 2) if moe_certainty is not None else "N/A",
            "Target sample (representativity, incl. 5% operational margin)": target_repr_display if target_repr_display is not None else "N/A",
            "Remaining eligible pool (accessible, unselected)": pool,
            f"Additional clusters needed for {TARGET_MOE_PCT:.0f}% MoE (at m={m_used})": additional_clusters_needed if additional_clusters_needed is not None else "N/A",
            "Feasibility": feasibility,
            "Reported by": strata_reported_by,
            "Last reported date": strata_last_date,
        })

        # Task 6 (2026-09-13, NEW): a single consolidated reference sheet for
        # Jack's own use in partner conversations - not an automated partner
        # distribution, one sheet he filters himself. "Achieved" here is the
        # REAL, field-collected count (not the design-capacity ceiling used
        # for the Feasibility logic above) - what matters for a live
        # conversation with a partner is real progress against the true
        # requirement, not an abstract capacity figure.
        remaining_needed = max(0, target_repr_display - real_achieved_accessible) if target_repr_display is not None else "N/A"
        if target_repr is None:
            status_label = "Not computable (accessible population too small)"
        elif remaining_needed == 0:
            status_label = "Complete - no further collection needed here"
        else:
            status_label = f"{remaining_needed} more still needed"
        # 2026-09-21 (Jack, same night the Feasibility override bug was
        # fixed; ADOPTED same day to switch the driving formula - see
        # realized_moe_certainty_aware()'s docstring): an explicit
        # Representative/Indicative verdict per stratum, driven by
        # moe_certainty (certainty-PSU-aware where the restricted
        # conditions apply - IDP-only, >=90% certainty coverage, non-empty
        # sampled remainder, each certainty site's own realized n_i >= 3 -
        # rigorous Kish figure otherwise), never the crude uniform-cluster
        # target_repr. The 10% MoE threshold is the authoritative
        # representativity bar for this assessment: anything above it has to
        # be actively justified to donors as indicative. This sheet is the
        # live per-stratum record of that, regenerated every run, and is
        # what partner prioritisation (target the still-representative
        # strata first) should read from. Also persisted as a CSV - see
        # main(). "Rigorous-only verdict (reference)" below shows what this
        # would have read before the 2026-09-21 switch, for audit/comparison
        # - never itself the authoritative figure.
        # 2026-09-21 (Jack, Task 3 review): a stratum with NO Full Design
        # sample in the accessible area (primary ceiling 0 - e.g. Abadam
        # Non-IDP, whose only interviews are MSNA Light, which never counts
        # toward Full Design figures) is not computable for that reason, not
        # because its population is small - label it as such so the record
        # and the donor note give the same reason. Still starts with "Not
        # computable" so every existing startswith() read keeps working.
        not_computable_label = (
            "Not computable (no Full Design sample in the accessible area)"
            if primary_ceiling_accessible == 0
            else "Not computable (accessible population too small)"
        )
        if moe_certainty is None:
            representativity = not_computable_label
        elif moe_certainty <= TARGET_MOE_PCT:
            representativity = "Representative (<= 10% MoE at full completion)"
        elif feasibility.startswith("Closeable via extra interviews at a certainty site"):
            representativity = "Indicative now - RECOVERABLE via extra interviews at a certainty site"
        elif feasibility.startswith("Closeable"):
            representativity = "Indicative now - RECOVERABLE via supplementary draw"
        elif feasibility.startswith("Not closeable"):
            representativity = "Indicative - NOT recoverable (pool insufficient), justify to donors"
        else:
            representativity = "Indicative now - gap negligible"
        if moe_updated is None:
            representativity_rigorous_only = not_computable_label
        elif moe_updated <= TARGET_MOE_PCT:
            representativity_rigorous_only = "Representative (<= 10% MoE at full completion)"
        else:
            representativity_rigorous_only = "Indicative (rigorous formula alone)"
        partner_reference_rows.append({
            "State": s["adm1_name"], "LGA": s["adm2_name"], "Pop type": "Non-IDP" if pop_type == "non_idp" else "IDP",
            "Strata ID": strata_id,
            "Partners covering": s["partners_covering"],
            "Representativity (10% MoE threshold)": representativity,
            "Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)": round(moe_certainty, 2) if moe_certainty is not None else "N/A",
            "Projected MoE % (rigorous Kish formula, reference only since 2026-09-21)": round(moe_updated, 2) if moe_updated is not None else "N/A",
            "Certainty-PSU treatment applied": "Yes" if certainty_applied else "No - rigorous figure carried (IDP-only, >=90% certainty coverage, remainder must have interviews, each certainty site's own n_i >= 3)",
            "Rigorous-only verdict (reference, pre-2026-09-21 basis)": representativity_rigorous_only,
            "Feasibility": feasibility,
            "Additional clusters needed": additional_clusters_needed if additional_clusters_needed is not None else "N/A",
            "Remaining eligible pool": pool,
            "Current accessible N_hh": round(N_hh_accessible) if N_hh_accessible else 0,
            "Target sample (true requirement, incl. 5% margin)": target_repr_display if target_repr_display is not None else "N/A",
            "Achieved (real, field-collected)": real_achieved_accessible,
            "Remaining needed": remaining_needed,
            "Status": status_label,
        })

    print(f"Built {len(summary_rows)} stratum-level rows.")

    # ---- Output-plausibility gate (2026-09-08 audit, pass 4) ----
    # Bulletproof, data-independent invariants - a percentage is always in
    # [0, 100], full stop, regardless of any legitimate real-world change
    # (unlike achieved-vs-target, which can legitimately swing widely from
    # real oversampling/exhaustion). A formula bug (swapped numerator/
    # denominator, double-counted area/population) would violate this
    # immediately - exactly the class of bug this audit found repeatedly
    # this week, just in a different script each time.
    n_pop_pct_out_of_range = sum(1 for r in summary_rows if not (0 <= r["% of population remaining"] <= 100))
    assert_plausible("strata with %% of population remaining outside [0,100]", n_pop_pct_out_of_range, (0, 0),
                      context="a percentage can never legitimately fall outside this range - a formula bug, not a real data change")
    n_cluster_pct_out_of_range = sum(1 for r in summary_rows if not (0 <= r["% of clusters remaining"] <= 100))
    assert_plausible("strata with %% of clusters remaining outside [0,100]", n_cluster_pct_out_of_range, (0, 0),
                      context="a percentage can never legitimately fall outside this range - a formula bug, not a real data change")

    # Task 4 (2026-09-13, target-inflation-fix batch): standing STOP-mode
    # gate - a stratum's target_sample_representativity must never increase
    # run-to-run UNLESS that stratum's own accessible population
    # (N_hh_accessible) genuinely increased too.
    #
    # CORRECTED 2026-09-14, per Jack: the original version treated ANY
    # increase as suspicious, full stop - that was the right instinct at the
    # time this gate was built (this project had spent days chasing
    # accessibility-only-ever-shrinks bugs), but it was never actually the
    # right invariant. The true rule is directional: while a stratum's
    # accessible population is flat or shrinking, its target can only stay
    # flat or shrink too (the original gate's own logic, still enforced
    # below) - but once a partner reports a real accessibility GAIN
    # (exactly what happened the same night this was found: INTERSOS's
    # _1409 return flipped Mayanchi ward, Maru, back to Accessible), the
    # target is legitimately free to move either way, since it's now being
    # computed against a larger accessible population. Gating on the target
    # figure alone couldn't tell these two cases apart; gating on the
    # DIRECTION of N_hh_accessible's own change can.
    #
    # Still no silent bypass for the case that actually matters: a target
    # increase with NO accompanying accessible-population increase (or where
    # last run's N_hh_accessible wasn't persisted at all - an old-format
    # baseline, treated as "can't confirm a gain") is exactly the target-
    # inflation-bug pattern this batch was built to close, and still hard-
    # stops with no override. First-ever run has no baseline (last_run_
    # targets empty) and passes trivially - every run after checks against
    # the PRIOR run's own persisted value, not the original design-time
    # target_sample.
    TARGET_REPR_INCREASE_TOLERANCE = 1e-6  # float noise guard, not a real allowance
    all_increased = [
        sid for sid in new_run_targets
        if sid in last_run_targets
        and new_run_targets[sid]["target_sample_representativity"]
            > last_run_targets[sid]["target_sample_representativity"] + TARGET_REPR_INCREASE_TOLERANCE
    ]

    def accessibility_genuinely_increased(sid):
        prior_n_hh = last_run_targets[sid]["N_hh_accessible"]
        if prior_n_hh is None:
            return False  # old-format baseline, no accessible-population figure to compare against - don't trust it
        return new_run_targets[sid]["N_hh_accessible"] > prior_n_hh + TARGET_REPR_INCREASE_TOLERANCE

    explained_by_accessibility_gain = [sid for sid in all_increased if accessibility_genuinely_increased(sid)]
    unexplained_increase = [sid for sid in all_increased if sid not in explained_by_accessibility_gain]

    if explained_by_accessibility_gain:
        detail = "; ".join(
            f"{sid}: target {last_run_targets[sid]['target_sample_representativity']:.2f} -> "
            f"{new_run_targets[sid]['target_sample_representativity']:.2f} (N_hh_accessible "
            f"{last_run_targets[sid]['N_hh_accessible']:.1f} -> {new_run_targets[sid]['N_hh_accessible']:.1f})"
            for sid in explained_by_accessibility_gain[:20]
        )
        print(f"  {len(explained_by_accessibility_gain)} stratum/strata with target_sample_representativity "
              f"increased, explained by a real accessible-population gain (allowed): {detail}"
              + (" ..." if len(explained_by_accessibility_gain) > 20 else ""))
    if unexplained_increase:
        detail = "; ".join(
            f"{sid}: {last_run_targets[sid]['target_sample_representativity']:.2f} -> "
            f"{new_run_targets[sid]['target_sample_representativity']:.2f}"
            for sid in unexplained_increase[:20]
        )
        print(f"  {len(unexplained_increase)} stratum/strata with target_sample_representativity INCREASED "
              f"since last run with NO matching accessible-population gain: {detail}"
              + (" ..." if len(unexplained_increase) > 20 else ""))
    assert_plausible("strata with target_sample_representativity increased since last run with no matching "
                      "accessible-population gain", len(unexplained_increase), (0, 0),
                      context="a target may legitimately increase when that stratum's own accessible population "
                              "(N_hh_accessible) genuinely grew too (a border-buffer reopening, a partner reporting a "
                              "ward newly accessible) - that case is checked and allowed above. An increase with NO "
                              "matching accessible-population gain has no legitimate explanation and means a bug "
                              "reintroducing the exact target-inflation pattern this batch was built to close - stop "
                              "and look, don't reflexively comment this out")
    write_last_run_targets(new_run_targets)

    reporting_stats = compute_reporting_stats()
    write_workbook(summary_rows, cluster_rows, ward_status, provenance_lookup, min_submission_date, reporting_stats, partner_reference_rows)

    # 2026-09-21: the per-stratum Representative/Indicative verdict, also as
    # a flat CSV so 2_monitoring / partner-prioritisation work can read it
    # without opening the workbook. Same rows as the Partner Reference sheet.
    repr_csv = os.path.join(OUT_DIR, "strata_representativity_status.csv")
    with open(repr_csv, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(partner_reference_rows[0].keys()))
        writer.writeheader()
        writer.writerows(partner_reference_rows)
    n_repr = sum(1 for r in partner_reference_rows if r["Representativity (10% MoE threshold)"].startswith("Representative"))
    n_recov = sum(1 for r in partner_reference_rows if "RECOVERABLE" in r["Representativity (10% MoE threshold)"])
    n_not = sum(1 for r in partner_reference_rows if "NOT recoverable" in r["Representativity (10% MoE threshold)"])
    print(f"Representativity (10% MoE, certainty-PSU-aware where applicable): {n_repr} representative | "
          f"{n_recov} indicative-but-recoverable | {n_not} indicative-not-recoverable | "
          f"{len(partner_reference_rows) - n_repr - n_recov - n_not} other -> {repr_csv}")
    # 2026-09-21: certainty treatment now DRIVES the verdict above (Jack's
    # go-ahead, same day) - this block reports the effect of that switch,
    # not a "would be" hypothetical any more.
    n_applied = sum(1 for r in partner_reference_rows if r["Certainty-PSU treatment applied"] == "Yes")
    n_reclassified_up = sum(1 for r in partner_reference_rows
                             if r["Certainty-PSU treatment applied"] == "Yes"
                             and r["Representativity (10% MoE threshold)"].startswith("Representative")
                             and not r["Rigorous-only verdict (reference, pre-2026-09-21 basis)"].startswith("Representative"))
    n_worse = sum(1 for r in partner_reference_rows
                  if r["Certainty-PSU treatment applied"] == "Yes"
                  and r["Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)"] != "N/A"
                  and r["Projected MoE % (rigorous Kish formula, reference only since 2026-09-21)"] != "N/A"
                  and r["Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)"]
                      > r["Projected MoE % (rigorous Kish formula, reference only since 2026-09-21)"])
    print(f"Certainty-PSU-aware treatment applied to {n_applied} strata (ADOPTED 2026-09-21, now drives Feasibility/"
          f"Representativity): {n_reclassified_up} reclassified Indicative -> Representative this run; "
          f"{n_worse} read worse than the rigorous-only figure (expected - see realized_moe_certainty_aware()'s "
          f"docstring for which of those are genuine non-proportional-allocation findings, e.g. Mobbar, vs already-"
          f"fixed tiny-sample artefacts).")
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
    ("Target-inflation fix, 2026-09-13 (Tasks 2/3/4/6)", "header", [
        "'Target sample (representativity, incl. 5% operational margin)' replaces the ever-growing "
        "target_sample_current (2_monitoring's own figure, which summed every cluster ever drawn and never "
        "subtracted one once it went inaccessible) with a freshly-computed TRUE requirement: "
        "min(N_hh_accessible, sample_needed_for_moe(10%, N_hh_accessible, m, ICC=0.06) x 1.05). ICC stays "
        "fixed at 0.06 (no empirical/per-stratum estimation - Jack's call, too risky mid-survey); no "
        "disaggregation logic exists anywhere in this figure (out of scope, not deferred). The x1.05 is a "
        "flat 5% margin applied uniformly to every stratum, grounded in the real national confirmed-deletion "
        "rate (6.53% of submissions, 94.7% of that duration_under_20) - NOT the same thing as the existing "
        "10% non-response reserve buffer (that backstops a household never reached; this margin protects "
        "against an already-completed interview later getting invalidated). Computed fresh every run for "
        "EVERY stratum and applied against the CURRENT accessible frame - this is a retroactive correction "
        "for every already-resampled stratum, not just a prospective one going forward. Displayed rounded UP "
        "to a whole household (a household is not a divisible unit) - internally the figure is a precise "
        "float, used unrounded for the Feasibility/additional-clusters-needed math and the STOP-mode check "
        "below, which both want full precision to catch small real changes.",
        "'Negligible gap - not worth a supplementary draw' (new Feasibility category): would half a cluster "
        "more (m/2 households) bring this stratum's realized MoE to <=10%? If so, the shortfall is smaller "
        "than cluster granularity can usefully close - skip the draw rather than round up to a whole new "
        "6-household cluster for a 1-3 household gap.",
        "'Closeable via extra interviews at a certainty site (+k at <site>)' (2026-09-21, Jack's decision): "
        "only for certainty-treated IDP strata that the new-cluster search can't close. A certainty site is "
        "its own stratum under the verdict formula, so k more interviews at that one existing site, "
        "everything else held, bring the MoE to <=10%. Additional clusters needed reads 0 for these, "
        "because the route adds interviews, not clusters. Verdict: 'RECOVERABLE via extra interviews at a "
        "certainty site'.",
        "'Not computable (no Full Design sample in the accessible area)' (2026-09-21): the stratum's "
        "Full Design achievable ceiling is 0 - e.g. its only interviews are MSNA Light, which never count "
        "toward Full Design figures. Distinct from 'accessible population too small'.",
        "A standing STOP-mode check runs every time this script runs: a stratum's target_sample_"
        "representativity must never increase from the previous run UNLESS that stratum's own accessible "
        "population (N_hh_accessible) increased too (see target_sample_representativity_last_run.csv, which "
        "now persists both figures). A target increase with a matching accessible-population gain is a real, "
        "understood expansion (a border-buffer reopening, a partner reporting a ward newly accessible) and "
        "passes automatically - one first surfaced this exact case, 2026-09-14, when INTERSOS reported "
        "Mayanchi ward (Maru) newly accessible. A target increase with NO matching accessible-population "
        "gain has no legitimate explanation and still hard-stops with no override - that's a bug "
        "reintroducing the exact target-inflation pattern this whole fix was built to close.",
    ]),
    ("Partner Reference sheet (new, 2026-09-13) - read this before using it in a partner conversation", "header", [
        "2026-09-21: this sheet now carries the per-stratum REPRESENTATIVITY VERDICT - 'Representativity "
        "(10% MoE threshold)' - and the projected MoE behind it. The 10% MoE threshold is the "
        "authoritative representativity bar for this assessment: 'Representative' means the stratum "
        "reaches <= 10% MoE at full completion of its currently-assigned, currently-accessible primary "
        "slots; anything else is 'Indicative', split into RECOVERABLE (a supplementary draw can bring "
        "it under 10%) vs NOT recoverable (candidate pool insufficient - this is the set to actively "
        "justify to donors). Use it for partner prioritisation: target the still-representative and "
        "recoverable strata first. Regenerated every run; the same rows are also written to "
        "strata_representativity_status.csv next to this workbook. Added the night the Feasibility "
        "column was found to have been silently overriding this very check on 155 of 307 strata - "
        "see 1_sampling/CLAUDE.md, Update 2026-09-20/21.",
        "SAME DAY, LATER: the driving MoE formula switched from the rigorous Kish cluster-size-aware "
        "figure alone to a certainty-PSU-aware model (Jack's decision, evidence: 38 of 307 strata "
        "affected, 28 reclassify Indicative -> Representative, 4 read worse - 2 tiny-sample artefacts "
        "now fixed via an n_i floor, 2 genuine non-proportional-allocation findings left standing on "
        "purpose, e.g. Mobbar). 'Projected MoE % (certainty-PSU-aware, DRIVES the verdict above)' is "
        "now the authoritative figure; the plain Kish figure is kept alongside as 'reference only', and "
        "'Rigorous-only verdict (reference, pre-2026-09-21 basis)' shows what this sheet would have said "
        "before the switch, for audit. See realized_moe_certainty_aware()'s own docstring (this script) "
        "for the full model, its restrictions, and why a hypothetical future cluster is still projected "
        "under the rigorous formula even though the current-state verdict uses the certainty-aware one.",
        "One row per stratum: partner(s), current accessible household population, the true target "
        "(representativity, with margin), REAL field-collected achieved count, remaining needed, and a "
        "plain-language status. Built for Jack's own use filtering this sheet himself in partner "
        "conversations - not an automated partner distribution.",
        "IMPORTANT DISTINCTION: 'no new resampling triggered' (this workbook's own internal signal - the "
        "Feasibility column above) is NOT the same thing as 'this partner can stop pursuing new households "
        "in this stratum' (this sheet's own Status column). A stratum can show zero additional clusters "
        "needed while its currently-assigned clusters still have real, incomplete work outstanding - 'no new "
        "clusters' only means the CLUSTER ROSTER is correctly sized, not that fieldwork there is finished. "
        "Always read the Remaining needed / Status columns for what to actually tell a partner, never infer "
        "it from the Strata Level sheet's Feasibility column alone.",
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
                 "% of clusters remaining", "Realized MoE % (certainty-PSU-aware, DRIVES Feasibility/Representativity since 2026-09-21)", "Feasibility"]
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


def write_workbook(summary_rows, cluster_rows, ward_status, provenance_lookup, min_submission_date, reporting_stats, partner_reference_rows):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)

    write_readme(wb, summary_rows, min_submission_date, reporting_stats)

    write_sheet(wb, "Strata Level", summary_rows)

    # Task 6 (2026-09-13, NEW) - see the README's own section above for the
    # "no new resampling" vs "partner can stop" distinction this sheet
    # exists to make explicit. Sorted by Remaining needed descending so the
    # biggest live gaps surface first when Jack opens it.
    partner_reference_sorted = sorted(
        partner_reference_rows,
        key=lambda r: r["Remaining needed"] if isinstance(r["Remaining needed"], (int, float)) else -1,
        reverse=True,
    )
    write_sheet(wb, "Partner Reference", partner_reference_sorted)

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
