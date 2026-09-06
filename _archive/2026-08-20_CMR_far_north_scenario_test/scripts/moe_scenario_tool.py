# ==============================================================================
# CM004003 (Mayo-Danay) partner-coverage scenario tool - "how many of the 11
# admin-3s do we need covered to call CM004003 representative at 90% CL /
# 10% MoE, vs indicative" - built 2026-08-20 for a colleague's Cameroon Far
# North assessment, reusing patterns already established in this repo's own
# NGA sampling design (see ../../../CLAUDE.md's certainty-stratum MoE check).
#
# CORRECTED 2026-08-21 - representativity is now assessed PER STRATUM
# (admin-2 x population-group), not as one pooled admin-2-wide number.
# The original 2026-08-20 version's headline "8/11 admin-3s needed" answer
# came from pooled_moe(), which computes the precision of a hypothetical
# population-weighted BLENDED estimate across all four groups combined
# (Var = sum((N_g/N_total)^2 * Var_g) - note the SQUARED weights, the
# textbook-correct formula for that specific quantity). That is a real, but
# different and less useful, question than "is each population group
# adequately represented" - MSNA indicators are reported BY population
# group (host/IDP/returnee/refugee need different things), which is exactly
# why the source workbook computes separate targets per group in the first
# place. Checked numerically: at the old "8/11 = representative" point, NONE
# of PND/PDI/Retournees had individually crossed 10% MoE - PND itself sat at
# 10.7%. The pooled figure crossed early specifically because squaring a
# dominant group's ~92% population weight shrinks its variance contribution
# by ~15%, letting a blended number dip under 10% while the group that
# weight represents (PND) has not. A pooled/blended metric can look like a
# pass when the group that matters most for targeting purposes isn't there
# yet - see the "Don't" list in the accompanying document.
#
# Per-stratum (per population group) representativity is now the PRIMARY
# analysis (see per_group_scenarios()/group_order() below). The pooled
# metric is kept ONLY as a clearly-labelled secondary "aggregate blended
# effort" figure (pooled_moe()/run_scenario()) - never presented as
# equivalent to per-group representativity.
#
# ------------------------------------------------------------------------
# Why this file needs POPULATION, not the sample-size figures already in
# "CMR - Far north - Preperatory Excel v2.xlsb":
# Every PND/PDI/Refugies/Retournees figure in that workbook (Coverage
# Assignment, Sample FN, Analysis Tab, Surveys sheets) is already a
# COMPUTED SAMPLE SIZE, not population - confirmed three independent ways:
# (1) a recurring ~102 ceiling value across unrelated admin-3s (the
# signature of an asymptotic MoE formula, not real population), (2) the
# "Budget NWSW" sheet's column literally named "Nb surveys" holding the
# same kind of figures, (3) the "Costing"/"Costing (2)" sheets' column
# literally named "Sample size" for the exact same Bogo=37 value. Values at
# the saturating ceiling are NOT invertible back to population, so the
# original file's numbers cannot be used to rebuild this at a different
# design effect - raw population (from Sampling_MSNA_2026_Extreme-Nord
# Admin 3.xlsx's host/IDP/ret/ref sheets) is used instead.
#
# ------------------------------------------------------------------------
# Methodology (mirrors ../../CLAUDE.md's realized_moe()/certainty-stratum
# pattern, generalised to this use case):
#   1. required_sample_size(N, ...) - standard finite-population-corrected
#      MoE sample-size formula, giving each population group's FULL
#      ADM2-representative target.
#   2. Each admin-3's TARGET contribution, PER GROUP = its share of that
#      group's ADM2 population, applied to the group's ADM2-level target
#      (proportional allocation).
#   3. For a given SCENARIO and a given GROUP, ACHIEVED sample = sum of the
#      covered admin-3s' target contributions FOR THAT GROUP.
#   4. realized_moe(n=achieved, N=that group's full ADM2 population, ...)
#      - projects the MoE for THAT GROUP, evaluated against its own full
#      ADM2 population (covered + uncovered), not just the covered slice -
#      same reasoning as the NGA project's certainty-stratum check.
#   5. representative (for that group) if its own MoE <= target MoE, else
#      indicative. Each group is assessed independently - CM004003 can
#      legitimately be representative for one group and indicative for
#      another at the same coverage level.
#
# DEFF is a named, adjustable parameter (currently 1.3, per the team's
# 2026-08-20 call) - change DEFF_DEFAULT below and rerun, nothing else to
# edit.
# ==============================================================================
import math
from dataclasses import dataclass, field

import pandas as pd

# ---------------------------------------------------------------------------
# Parameters (all adjustable - rerun after changing any of these)
# ---------------------------------------------------------------------------
CONFIDENCE_LEVEL = 0.90
Z_SCORE = 1.645          # two-tailed critical value for 90% CL
TARGET_MOE = 0.10        # 10%
MOE_TOLERANCE = 1e-9     # required_sample_size() and realized_moe() are exact algebraic inverses,
                          # but achieved sample is summed from per-admin3 float shares rather than
                          # recomputed directly - a group that has delivered its own full target
                          # via all its population-carrying admin-3s can land a few ULPs above
                          # TARGET_MOE (observed: ~1e-14 relative) and get wrongly marked
                          # indicative on a strict <= check. This tolerance absorbs float noise
                          # only - it does not mask any real precision gap.
P_CONSERVATIVE = 0.5     # maximum-variance assumption (no prior estimate of the true proportion)
DEFF_DEFAULT = 1.3       # = 1 + (M-1)*ICC = 1 + 5*0.06, confirmed via "Parametres" sheet in
                          # Sampling_MSNA_2026_Extreme-Nord Admin 3.xlsx (M=6 cluster size, ICC=0.06)
BUFFER_DEFAULT = 0.10    # non-response buffer, per the same "Parametres" sheet. Reported as a
                          # separate planning figure only (reserve capacity) - NOT added into the
                          # achieved sample used for the MoE/representativeness determination.

POP_GROUPS = ["PND", "PDI", "Refugies", "Retournees"]
GROUP_LABELS = {"PND": "Host (PND)", "PDI": "IDP (PDI)", "Refugies": "Refugees", "Retournees": "Returnees"}

INPUT_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\_archive\2026-08-20_CMR_far_north_scenario_test\input\population_by_admin3_CM004003_REAL.csv"
OUTPUT_CSV = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\_archive\2026-08-20_CMR_far_north_scenario_test\output\CM004003_coverage_scenarios.csv"


# ---------------------------------------------------------------------------
# Core formulas
# ---------------------------------------------------------------------------
def required_sample_size(N, z=Z_SCORE, p=P_CONSERVATIVE, moe=TARGET_MOE, deff=DEFF_DEFAULT):
    """Finite-population-corrected sample size needed to achieve `moe` at
    confidence `z`, for a population of size N. Returns 0 if N <= 0."""
    if N <= 0:
        return 0.0
    n0 = (z ** 2) * p * (1 - p) * deff / (moe ** 2)
    n_fpc = n0 / (1 + (n0 - 1) / N)
    return min(n_fpc, N)  # never require more than the full population


def with_buffer(n, buffer=BUFFER_DEFAULT):
    """Buffer-inclusive planning figure (reserve capacity on top of the
    statistically-required core n) - informational only."""
    return n / (1 - buffer) if n > 0 else 0.0


def realized_moe(n, N, z=Z_SCORE, p=P_CONSERVATIVE, deff=DEFF_DEFAULT):
    """Achievable MoE given an achieved sample `n` against population `N` -
    the inverse direction of required_sample_size(). Returns inf if there's
    no population to represent (N<=0) or no interviews (n<=0); 0.0 (perfect
    precision) if n >= N (full enumeration)."""
    if N <= 0 or n <= 0:
        return float("inf")
    n = min(n, N)
    if n >= N:
        return 0.0
    variance = (p * (1 - p) * deff / n) * ((N - n) / (N - 1))
    return z * math.sqrt(variance)


def pooled_moe(group_n_and_N, z=Z_SCORE, p=P_CONSERVATIVE, deff=DEFF_DEFAULT):
    """SECONDARY METRIC ONLY - population-weighted stratified-variance
    pooling across population groups into one blended admin-2-wide MoE.
    This is the precision of a hypothetical combined estimate across all
    groups, NOT a substitute for per-group representativity - see the
    2026-08-21 correction note at the top of this file for why pooling
    with squared population weights can show "representative" while every
    individual group is still indicative. Kept only as a secondary,
    clearly-labelled "aggregate effort" figure."""
    total_N = sum(N for _, N in group_n_and_N if N > 0)
    if total_N == 0:
        return float("inf")
    pooled_variance = 0.0
    for n, N in group_n_and_N:
        if N <= 0:
            continue
        weight = N / total_N
        n_eff = min(max(n, 0), N)
        if n_eff >= N:
            group_variance = 0.0
        elif n_eff <= 0:
            group_variance = float("inf")
        else:
            group_variance = (p * (1 - p) * deff / n_eff) * ((N - n_eff) / (N - 1))
        pooled_variance += (weight ** 2) * group_variance
    if math.isinf(pooled_variance):
        return float("inf")
    return z * math.sqrt(pooled_variance)


# ---------------------------------------------------------------------------
# Scenario engine
# ---------------------------------------------------------------------------
@dataclass
class Admin3:
    pcode: str
    name: str
    population: dict = field(default_factory=dict)     # {group: N}
    target: dict = field(default_factory=dict)          # {group: allocated target sample}
    covered_today: bool = False
    confirmed_partner: str = ""


def load_admin3s(csv_path):
    df = pd.read_csv(csv_path, encoding="utf-8-sig")
    admin3s = []
    for _, r in df.iterrows():
        pop = {g: (float(r[g]) if pd.notna(r[g]) and str(r[g]).strip() != "" else 0.0) for g in POP_GROUPS}
        confirmed = str(r.get("confirmed", "")).strip()
        is_confirmed_partner = confirmed not in ("", "nan", "No surveys", "Partner to find")
        admin3s.append(Admin3(
            pcode=r["ADM3_PCODE"], name=r["ADM3_FR"], population=pop,
            covered_today=is_confirmed_partner, confirmed_partner=confirmed,
        ))
    return admin3s


def compute_targets(admin3s, deff=DEFF_DEFAULT):
    """Each admin-3's proportional share of the full ADM2-level target, per
    population group."""
    adm2_pop = {g: sum(a.population[g] for a in admin3s) for g in POP_GROUPS}
    adm2_target = {g: required_sample_size(adm2_pop[g], deff=deff) for g in POP_GROUPS}
    for a in admin3s:
        for g in POP_GROUPS:
            share = (a.population[g] / adm2_pop[g]) if adm2_pop[g] > 0 else 0.0
            a.target[g] = share * adm2_target[g]
    return adm2_pop, adm2_target


def group_order(admin3s, group):
    """Admin-3s ordered for a SPECIFIC group: today's confirmed first
    (locked in), then the rest by THAT group's own target contribution
    descending. Different groups can - and here, do - have different
    priority orders, since e.g. PDI (IDP) population is concentrated in
    only 5 of the 11 admin-3s while PND (host) is present in all 11."""
    confirmed = [a for a in admin3s if a.covered_today]
    rest = sorted((a for a in admin3s if not a.covered_today),
                  key=lambda a: a.target[group], reverse=True)
    return confirmed + rest


def group_scenarios(admin3s, group, adm2_pop_group):
    """Per-group coverage curve: for k=1..N admin-3s (that group's own
    operational order), achieved sample, projected MoE, and representative
    flag - all evaluated for THIS GROUP ONLY. Returns a list of dicts plus
    the crossing k (or None if never reached within available admin-3s)."""
    if adm2_pop_group <= 0:
        return [], None  # group not present in this admin-2 at all
    ordered = group_order(admin3s, group)
    rows = []
    crossing_k = None
    for k in range(1, len(ordered) + 1):
        subset = ordered[:k]
        achieved = sum(a.target[group] for a in subset)
        moe = realized_moe(achieved, adm2_pop_group)
        is_rep = moe <= TARGET_MOE + MOE_TOLERANCE
        rows.append({"k": k, "admin3": ordered[k - 1].name, "achieved": achieved, "moe": moe, "representative": is_rep})
        if is_rep and crossing_k is None:
            crossing_k = k
    return rows, crossing_k


def run_scenario(admin3s_covered, adm2_pop, deff=DEFF_DEFAULT):
    """SECONDARY/aggregate scenario only - see pooled_moe() docstring."""
    achieved = {g: sum(a.target[g] for a in admin3s_covered) for g in POP_GROUPS}
    group_pairs = [(achieved[g], adm2_pop[g]) for g in POP_GROUPS]
    moe = pooled_moe(group_pairs, deff=deff)
    return achieved, moe, moe <= TARGET_MOE + MOE_TOLERANCE


def operational_order(admin3s):
    """Aggregate/pooled ordering only (today's confirmed first, then by
    TOTAL target contribution across all groups combined) - kept for the
    secondary pooled metric. Per-group analysis uses group_order() instead."""
    confirmed = [a for a in admin3s if a.covered_today]
    rest = sorted((a for a in admin3s if not a.covered_today),
                  key=lambda a: sum(a.target.values()), reverse=True)
    return confirmed + rest


def main():
    admin3s = load_admin3s(INPUT_CSV)
    adm2_pop, adm2_target = compute_targets(admin3s)
    today_covered = [a for a in admin3s if a.covered_today]

    print(f"Parameters: CL={CONFIDENCE_LEVEL:.0%}, target MoE={TARGET_MOE:.0%}, DEFF={DEFF_DEFAULT}")
    print(f"Today's confirmed: {len(today_covered)}/{len(admin3s)} - {[a.name for a in today_covered]}\n")

    rows = []

    # ---- PRIMARY: per-group (per-stratum) representativity ----
    print("=" * 78)
    print("PRIMARY ANALYSIS - representativity PER POPULATION GROUP")
    print("=" * 78)
    for g in POP_GROUPS:
        pop_g = adm2_pop[g]
        print(f"\n--- {GROUP_LABELS[g]} --- population={pop_g:,.0f}, full ADM2 target={adm2_target[g]:.1f}")
        if pop_g <= 0:
            print("    No population in this group for CM004003 - not applicable, no claim needed.")
            continue

        scen, crossing_k = group_scenarios(admin3s, g, pop_g)
        n_with_pop = sum(1 for a in admin3s if a.population[g] > 0)

        # today's standalone position for this group
        today_achieved = sum(a.target[g] for a in today_covered)
        today_moe = realized_moe(today_achieved, pop_g)
        print(f"    Today ({len(today_covered)}/{len(admin3s)} confirmed): achieved={today_achieved:.1f}, "
              f"MoE={today_moe:.1%}, {'REPRESENTATIVE' if today_moe <= TARGET_MOE + MOE_TOLERANCE else 'indicative'}")

        for r in scen:
            flag = "REPRESENTATIVE" if r["representative"] else "indicative"
            marker = "  <-- crosses here" if r["k"] == crossing_k else ""
            print(f"    {r['k']:>2}/{len(admin3s)}: achieved={r['achieved']:>6.1f}  MoE={r['moe']:>6.1%}  {flag}  (+{r['admin3']}){marker}")
            rows.append({"analysis": "per_group", "group": g, "k": r["k"], "admin3": r["admin3"],
                         "achieved": r["achieved"], "moe": r["moe"], "representative": r["representative"]})

        if crossing_k is not None:
            print(f"    => {GROUP_LABELS[g]} reaches representative at {crossing_k}/{len(admin3s)} admin-3s "
                  f"({n_with_pop} admin-3s actually carry {g} population).")
        else:
            print(f"    => {GROUP_LABELS[g]} does NOT reach representative even at full coverage under current parameters.")

    # ---- SECONDARY: pooled/aggregate metric, clearly caveated ----
    print("\n" + "=" * 78)
    print("SECONDARY METRIC - pooled/blended admin-2-wide MoE (aggregate effort only)")
    print("CAUTION: this is NOT equivalent to per-group representativity above - see")
    print("the correction note at the top of this script before using this number.")
    print("=" * 78)
    op_ordered = operational_order(admin3s)
    for k in range(1, len(op_ordered) + 1):
        subset = op_ordered[:k]
        achieved, moe, is_rep = run_scenario(subset, adm2_pop)
        core_n = sum(achieved.values())
        flag = "REPRESENTATIVE" if is_rep else "indicative"
        print(f"  {k:>2}/{len(admin3s)}: achieved (pooled)={core_n:>6.1f}  pooled MoE={moe:>6.1%}  {flag}   (+{op_ordered[k-1].name})")
        rows.append({"analysis": "pooled_secondary", "group": "ALL_BLENDED", "k": k, "admin3": op_ordered[k - 1].name,
                     "achieved": core_n, "moe": moe, "representative": is_rep})

    pd.DataFrame(rows).to_csv(OUTPUT_CSV, index=False)
    print(f"\nWritten: {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
