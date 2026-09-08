# One-off test build: 4 example cluster factsheets integrating the new
# cluster-level + LGA-context maps and the 3 field-guide emphasis edits,
# into a separate review folder. Does NOT touch _wip_cluster_factsheets/
# or the partner package (3. External coordination/NGA MSNA 2026 Package).
import os

from build_cluster_factsheets import clusters, build_cluster_doc, PROJECT_DIR, EXAMPLE_CLUSTER_MAPS_DIR

OUT_DIR = PROJECT_DIR + r"\output\cluster_factsheets_example_review"
os.makedirs(OUT_DIR, exist_ok=True)

example_ids = [
    "non_idp_NG022015_11",
    "non_idp_NG008014_8",
    "idp_NG002002_1",
    "idp_NG002001_5",
    "idp_NG008006_11",  # the "Other IDP site" bbox-stretch regression case
    "non_idp_NG036013_15",  # dense-POI stress test (Nguru, Yobe) - 2026-08-12
]

for cluster_id in example_ids:
    rows = clusters.get(cluster_id)
    if rows is None:
        print(f"  MISSING from WORKING frame: {cluster_id}")
        continue
    doc = build_cluster_doc(cluster_id, rows, maps_dir=EXAMPLE_CLUSTER_MAPS_DIR, include_lga_map=True)
    out_path = os.path.join(OUT_DIR, f"{cluster_id}_factsheet.docx")
    doc.save(out_path)
    print(f"  built: {out_path}")

print(f"\nDONE. Output: {OUT_DIR}")
