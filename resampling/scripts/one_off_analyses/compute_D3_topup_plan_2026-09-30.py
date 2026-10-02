# ==============================================================================
# Computes the exact per-cluster D3-style depth top-up allocation for the 4
# IDP strata Jack approved for real redraw tonight (30 Sep), at their
# BUFFERED targets (+10%, except Obi which uses his explicit override of 66
# directly). READ-ONLY - prints the plan, checks each touched cluster against
# the known selection_count/6L collision risk (found + held for Obi/Bassa on
# 2026-09-27's D3 run), writes nothing to the frame.
#
# Allocation method: same greedy, design-weighted (model B) engine as every
# other real topup tonight (topup_search()), but with a FIXED stopping count
# (buffered_target - achieved) rather than "until <=10% MoE" - topup_search()
# itself has no working cap_extra (checked: the parameter is declared but
# never referenced in the function body, so it can't be trusted as a cap) -
# so this is a small local variant of the same step logic, not a reuse of a
# broken parameter.
# ==============================================================================
import importlib.util
import math

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

RS = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling"
REV_DIR = RS + r"\output\representativity_review_2026-09-27"

m = load_module(RS + r"\scripts\05_build_accessibility_impact_workbook.py", "m05")
rev = load_module(REV_DIR + r"\build_representativity_review.py", "rev")

L = rev.load_state(m)
status_csv = rev.rd(RS + r"\output\strata_representativity_status.csv")
status_csv = [r for r in status_csv if r.get("Completion bucket") != "(d) Fully dropped / excluded"]
strata, bad, extra = rev.build_strata(m, L, status_csv)
print(f"reproduction check: {len(strata)} strata, {len(bad)} mismatches, {len(extra)} extras")
if bad or extra:
    raise SystemExit("STOP: not safe")

real_cluster = L["real_cluster"]

# strata_id -> buffered target (Obi = Jack's explicit override, not a buffer calc)
PLAN_TARGETS = {
    "idp_NG021006": ("Charanchi IDP", "CARE", math.ceil(75 * 1.10)),
    "idp_NG026011": ("Obi IDP", "CARE", 66),  # Jack's explicit override, use directly
    "idp_NG034021": ("Wamako IDP", "CRS", math.ceil(74 * 1.10)),
    "idp_NG037011": ("Shinkafi IDP", "FACT", math.ceil(185 * 1.10)),
}


def fixed_count_topup(m, st, clusters, N_acc, supply, needed_total, model="B"):
    """Same greedy step as topup_search() (always add the next interview to
    whichever cluster lowers MoE most), but stops once `needed_total`
    interviews have been allocated (or supply/population run out) rather
    than at the 10% MoE threshold - so it always returns an allocation that
    reaches the REQUESTED total, whether or not that total alone would have
    reached 10% (Jack's buffer is deliberately beyond the bare statistical
    minimum, so it should always be fully allocatable if physical headroom
    exists)."""
    live = [c for c in clusters if c["n_primary_ceiling_contribution"] > 0]
    base = [c["n_primary_ceiling_contribution"] for c in live]
    sup = [supply.get(c["cluster_id"], 0) if c["n_primary_accessible"] > 0 else 0 for c in live]
    alloc = [0] * len(live)

    def moe_of(al):
        cl = [dict(c, n_primary_ceiling_contribution=c["n_primary_ceiling_contribution"] + a) for c, a in zip(live, al)]
        v, _ = rev.moe_basis(m, st, cl, N_acc)
        if v is None:
            return None
        if model == "B":
            v *= math.sqrt(rev.deff_w_factor(base, [b + a for b, a in zip(base, al)]))
        return v

    total_cap = sum(sup)
    steps = 0
    cur = moe_of(alloc)
    while steps < needed_total and steps < total_cap and steps < 5000:
        best_i, best_v = None, None
        for i in range(len(live)):
            if alloc[i] >= sup[i]:
                continue
            alloc[i] += 1
            v = moe_of(alloc)
            alloc[i] -= 1
            if v is not None and (best_v is None or v < best_v):
                best_i, best_v = i, v
        if best_i is None:
            break
        alloc[best_i] += 1
        cur = best_v
        steps += 1
    return {"total": sum(alloc), "moe_after": cur, "alloc": alloc, "live": live, "requested": needed_total,
            "fully_allocated": sum(alloc) == needed_total}


for sid, (label, partner, buffered_target) in PLAN_TARGETS.items():
    st = strata[sid]
    achieved = sum(real_cluster.get(c["cluster_id"], 0) for c in st["clusters"])
    needed = buffered_target - achieved
    print(f"\n=== {label} ({sid}, {partner}) === achieved={achieved} buffered_target={buffered_target} needed_total={needed}")
    if needed <= 0:
        print("  Already at/above buffered target - nothing to add.")
        continue

    supply = {c["cluster_id"]: max(0, int((c.get("households_in_cluster") or 0) - c["n_primary_ceiling_contribution"]))
              for c in st["clusters"]}
    result = fixed_count_topup(m, st, st["clusters"], st["N_acc"], supply, needed)
    print(f"  Allocated {result['total']} of {needed} requested (fully_allocated={result['fully_allocated']}), moe_after={result['moe_after']}")

    for c, a in zip(result["live"], result["alloc"]):
        if a > 0:
            old_target = c.get("n_primary")  # design target_households equivalent at this level
            print(f"    {c['cluster_id']} ({c.get('site_name','')}): +{a}  "
                  f"[current n_primary_ceiling_contribution={c['n_primary_ceiling_contribution']}, "
                  f"households_in_cluster={c.get('households_in_cluster')}, "
                  f"is_certainty={c.get('is_certainty')}, selection_count={c.get('selection_count')}]"
                  + ("  <-- COLLISION RISK: selection_count==1 and +6 or more, would flip certainty status via merge script's increase_target/6L formula" if (c.get("selection_count") == 1 and a >= 6) else ""))
