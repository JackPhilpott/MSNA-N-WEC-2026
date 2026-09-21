# Shared dominant-ward picker for a cluster that straddles more than one
# GRID3 ward. A Non-IDP hexagon can genuinely have primary households split
# across two (State, LGA, Ward) keys - this picks ONE to display as "the"
# cluster's ward, deterministically, so every script showing a cluster's
# ward agrees with every other.
#
# Extracted 2026-09-21 from 01_generate_accessibility_reports.py's own
# cluster_repr_by_partner logic (built 2026-08-21 to replace a non-
# deterministic dict.setdefault/"first row in file" pick - see that
# script's load_cluster_rows_by_partner() docstring for the full history).
# build_partner_dc_packages.py and refresh_partner_workbooks_daily.py were
# both found 2026-09-21 to still use their own "first primary row" pick for
# the partner-facing Cluster Summary sheet's Ward column - the exact old
# method the accessibility report moved away from a month earlier - which
# is why a straddling cluster could show a genuinely different ward on a
# partner's own file than on their accessibility report for the same
# cluster (Jack's non_idp_NG036003_17 example). Same shape as every other
# entry in feedback_cross_session_mistake_pattern_tracking.md: a rule fixed
# in the place it was found, not in its structural sibling.
from collections import defaultdict


def dominant_ward_key(rows, primary_status="primary"):
    """rows: list of frame dict-rows for ONE cluster_id (any mix of primary/
    reserve). Returns (state, lga, ward, ward_cod) for the ward with the
    most PRIMARY households in this cluster; ties broken by taking the
    lexicographically-largest (state, lga, ward) key (matches the
    accessibility report's existing, already-live tie-break exactly - not
    changed here, just reused, so a tied cluster doesn't flip which ward it
    shows depending on which script produced the file).
    """
    by_ward = defaultdict(lambda: {"primary": 0, "reserve": 0, "ward_cod": ""})
    for r in rows:
        key = (r["adm1_name"], r["adm2_name"], r["adm3_name"])
        w = by_ward[key]
        w[r["status"]] += 1
        ward_cod = r.get("admin3_cod_name")
        if ward_cod and ward_cod != "NA":
            w["ward_cod"] = ward_cod

    dominant_key = max(by_ward, key=lambda k: (by_ward[k][primary_status], k))
    state, lga, ward = dominant_key
    return state, lga, ward, by_ward[dominant_key]["ward_cod"]
