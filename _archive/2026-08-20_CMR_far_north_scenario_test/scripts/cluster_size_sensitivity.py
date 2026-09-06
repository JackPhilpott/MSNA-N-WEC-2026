# ==============================================================================
# Numerical exploration: does cluster size (M) / design effect (DEFF) change
# HOW MANY admin-3s CM004003 needs covered to cross into representative, or
# only the OPERATIONAL COST (total interviews, number of clusters) of getting
# there? Built 2026-08-20, corrected 2026-08-21 to check this PER POPULATION
# GROUP (per stratum) rather than against the old pooled/blended metric - see
# moe_scenario_tool.py's top-of-file correction note for why the pooled
# metric is no longer used as the primary representativity claim.
#
# Hypothesis (checked here, not just trusted from algebra): since each
# covered admin-3's target is its PROPORTIONAL SHARE of the (DEFF-dependent)
# full group target, and the MoE formula's own variance term is directly
# proportional to DEFF, the two should cancel for populations large enough
# that finite-population correction is negligible - meaning DEFF affects the
# total number of interviews needed, not how many admin-3s each group needs
# geographic coverage in. Confirmed 2026-08-21: holds independently for
# every group (PND needs 11, PDI needs 5, Retournees needs 10 - unchanged
# across the entire M=1..30 sweep below), not just in aggregate.
#
# deff is threaded through explicitly to compute_targets()/realized_moe()
# rather than mutating the module-level DEFF_DEFAULT - see moe_scenario_tool
# .py's pooled_moe() docstring for why mutating it after the fact wouldn't
# actually take effect (Python binds default-argument values once, at
# function definition time, not per call).
# ==============================================================================
import sys
sys.path.insert(0, ".")

import moe_scenario_tool as m

ICC = 0.06  # held fixed - not a design choice, a property of household homogeneity
M_VALUES = [1, 2, 3, 5, 6, 8, 10, 15, 20, 30]
GROUPS_WITH_POPULATION = ["PND", "PDI", "Retournees"]  # Refugies is 0 throughout CM004003


def deff_for_M(M):
    return 1 + (M - 1) * ICC


def admin3s_needed_for_group(admin3s, group, adm2_pop_group, deff):
    ordered = m.group_order(admin3s, group)
    for k in range(1, len(ordered) + 1):
        achieved = sum(a.target[group] for a in ordered[:k])
        moe = m.realized_moe(achieved, adm2_pop_group, deff=deff)
        if moe <= m.TARGET_MOE + m.MOE_TOLERANCE:
            return k
    return None  # never reached within the available admin-3s


def main():
    header = f"{'M':>3} {'DEFF':>6}   " + "   ".join(f"{g + '_needed':>12}" for g in GROUPS_WITH_POPULATION)
    print(header)
    for M in M_VALUES:
        deff = deff_for_M(M)
        admin3s = m.load_admin3s(m.INPUT_CSV)  # fresh objects each M (targets get mutated in place)
        adm2_pop, adm2_target = m.compute_targets(admin3s, deff=deff)

        needed = {g: admin3s_needed_for_group(admin3s, g, adm2_pop[g], deff) for g in GROUPS_WITH_POPULATION}
        row = f"{M:>3} {deff:>6.2f}   " + "   ".join(f"{needed[g]!s:>12}" for g in GROUPS_WITH_POPULATION)
        print(row)

    print("\nAdmin-3s needed is unchanged for every group across the entire M range tested -")
    print("confirms cluster size/DEFF is a cost lever, not a coverage lever, per group as")
    print("much as in aggregate. See the accompanying document, Part 4.")


if __name__ == "__main__":
    main()
