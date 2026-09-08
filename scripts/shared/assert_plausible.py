"""
assert_plausible() - output-plausibility gate (2026-09-08 pipeline audit,
pass 4). Python counterpart to assert_plausible.R - same interface and
semantics deliberately, mirroring the assert_fresh.R/.py pairing (this
project's Python and R scripts don't share a module system across repos,
see the standalone-script convention). Keep the two in sync by hand.

See assert_plausible.R's header for the full rationale: assert_fresh()
checks an INPUT is current before a script reads it; this checks an OUTPUT
is sane before a script trusts/writes it. Deliberately narrow - checks one
named value against an expected numeric range, hard-stops if outside it.
Each call site states and justifies its own range explicitly - no shared
validation framework.
"""


def assert_plausible(label, value, expected_range, context=None):
    """
    label: short name for this check, used in messages.
    value: the number to check (already computed by the caller).
    expected_range: (low, high) - inclusive.
    context: optional extra string for the error message.
    """
    lo, hi = expected_range
    if value is None:
        raise RuntimeError(f"assert_plausible({label}): value is None - cannot check plausibility, don't proceed on an unknown.")
    if value < lo or value > hi:
        ctx = f" ({context})" if context else ""
        raise RuntimeError(
            f"assert_plausible({label}): IMPLAUSIBLE VALUE {value}, expected [{lo}, {hi}]{ctx}.\n"
            "This looks like a bug, not a real data change - stopping before this gets "
            "written/trusted. If this range is genuinely wrong (a real, understood shift), "
            "update the expected range explicitly at this call site - don't just remove or "
            "widen the check to make it pass."
        )
    print(f"assert_plausible({label}): {value} within expected [{lo}, {hi}].")
    return True
