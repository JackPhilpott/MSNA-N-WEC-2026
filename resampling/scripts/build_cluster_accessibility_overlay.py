# ==============================================================================
# Derives resampling/output/cluster_accessibility_overlay.csv from
# resampling/output/resampling_requests_log.csv - the set of cluster_ids a
# partner has explicitly reported inaccessible at CLUSTER level (the "Cluster
# Accessibility" sheet), as opposed to the ward-level status every other
# accessibility mechanism in this project already runs on.
#
# 2026-09-13 gap this closes: 02_ingest_accessibility_reports.py has always
# logged cluster-level rows (report_level="cluster", cluster_id, accessible)
# into the log - nothing downstream ever read them back out. Found via ACF's
# returned report: 4 Tambuwal IDP sites (idp_NG034018_1/13/14/3) reported
# inaccessible/relocated at cluster level while their wards stay accessible
# overall - the whole ward_accessible_status-driven chain (compute_cluster_
# status() -> shortfall calc -> redraw pool) had no pathway to notice. Same
# pattern found 1,863 times across the full log once checked, not an ACF-only
# issue.
#
# Precedence rule (Jack, 2026-09-13): a cluster-level report only ever ADDS
# an exclusion on top of ward-level status - never overrides it in either
# direction. A cluster-level "No" on an otherwise-accessible ward excludes
# just that cluster; a cluster-level "Yes" on an inaccessible ward does NOT
# make that cluster accessible again. This script therefore only ever
# outputs the "No" set - a positive exclusion list, not a status override -
# so every consumer's existing ward-level logic stays authoritative and this
# is purely additive.
#
# "Latest report wins" PER (cluster_id, ward_name) - not cluster_id alone.
# FIXED 2026-09-20: a straddling Non-IDP cluster (hexagon spanning two
# wards - see 1_sampling/CLAUDE.md's "genuine (non-bug) wrinkle" under
# Revision 2026-09-05) can be reported at cluster level separately per
# ward-portion. Keying "latest" by cluster_id alone let a later report for
# a DIFFERENT ward-portion of the same cluster silently overwrite an
# earlier portion's "No" - e.g. ward-portion A reports No, ward-portion B
# is reported Yes afterward, and the bare-cluster_id-latest logic dropped
# A's No entirely, even though the precedence rule below says a No should
# never be overridden this way. Verified against the real log before fixing
# (not assumed): 130 FACT clusters were missing from the exclusion overlay
# as a direct result. Now: latest is tracked per (cluster_id, ward_name)
# independently, then a cluster is excluded if ANY of its ward-portions'
# own latest report is "No" - a union across portions, matching the
# additive-only precedence rule for every ward-portion, not just whichever
# one happened to be reported on most recently. A later "Yes" for a GIVEN
# ward-portion still naturally drops that portion's own exclusion - re-
# verified directly, not assumed: as of today every logged row is still
# status="new" (no resolution workflow has actually been used yet), so
# "latest by request_id" is equivalent to "still outstanding" for now - if
# a resolution workflow gets built later, this script would need to also
# honor it, not just re-check status=="new".
#
# Consumed by (2026-09-13 wiring, see CLAUDE.md):
#   - scripts/shared/frame_status.R's compute_cluster_accessibility()
#   - resampling/scripts/05_build_accessibility_impact_workbook.py's
#     classify_households()
#
# Rerun safety: pure re-derivation from the log every time, safe to rerun
# after any accessibility-report ingest. Never edits the log itself.
#
# Usage: python build_cluster_accessibility_overlay.py
# ==============================================================================
import csv
import os

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"
OUT_CSV = PROJECT_DIR + r"\resampling\output\cluster_accessibility_overlay.csv"

OUT_FIELDS = ["cluster_id", "partner", "state", "lga", "ward_name", "pop_type",
              "reason_category", "reason_notes", "request_id", "date_added"]


def build():
    with open(LOG_CSV, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    cluster_rows = [r for r in rows if r["report_level"] == "cluster" and r["cluster_id"]]

    latest_by_cid_ward = {}
    for r in cluster_rows:
        key = (r["cluster_id"], r["ward_name"])
        if key not in latest_by_cid_ward or int(r["request_id"]) > int(latest_by_cid_ward[key]["request_id"]):
            latest_by_cid_ward[key] = r

    # Union across ward-portions: a cluster is excluded if ANY of its
    # portions' own latest report is "No". Where more than one portion says
    # No, keep the most-recently-reported one as the representative output
    # row - output stays one row per excluded cluster_id either way.
    by_cluster_no_row = {}
    for r in latest_by_cid_ward.values():
        if r["accessible"].strip().lower() != "no":
            continue
        cid = r["cluster_id"]
        prior = by_cluster_no_row.get(cid)
        if prior is None or int(r["request_id"]) > int(prior["request_id"]):
            by_cluster_no_row[cid] = r

    excluded = sorted(by_cluster_no_row.values(), key=lambda r: r["cluster_id"])

    os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)
    with open(OUT_CSV, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=OUT_FIELDS)
        writer.writeheader()
        for r in excluded:
            writer.writerow({k: r.get(k, "") for k in OUT_FIELDS})

    n_distinct_clusters = len(set(cid for cid, ward in latest_by_cid_ward))
    print(f"{len(cluster_rows)} cluster-level log rows -> {len(latest_by_cid_ward)} distinct (cluster, ward-portion) "
          f"combinations ever reported at cluster level ({n_distinct_clusters} distinct clusters) -> "
          f"{len(excluded)} currently excluded (any ward-portion's latest report = No) -> {OUT_CSV}")
    by_partner = {}
    for r in excluded:
        by_partner[r["partner"]] = by_partner.get(r["partner"], 0) + 1
    for p, n in sorted(by_partner.items(), key=lambda kv: -kv[1]):
        print(f"  {p}: {n}")


if __name__ == "__main__":
    build()
