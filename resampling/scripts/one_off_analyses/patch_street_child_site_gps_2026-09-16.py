# ==============================================================================
# Street Child of Nigeria reported (raw comms, 2026-09-16) that two IDP sites
# they tried to visit had physically relocated but retain the same name and
# population per IOM DTM - they field-verified new GPS on the ground and
# provided it via a KoBo "Project Location and Coordinates" export
# (partner_raw_comms/Street Child of Nigeria/Monguno_Location_and_
# Coordinates_..._1609.xlsx).
#
# Two sites, both confirmed zero real submissions collected under the OLD
# coordinates (checked directly against 2_monitoring/data/real_submissions.csv
# before touching anything - see this session's own chat for the trace):
#   1. Dikwa "1000 IDP CAMP" -> DTM site BO_S256 "1000 Camp Dikwa Camp"
#      (only "1000"-named site in Dikwa LGA - unambiguous name match).
#      Tied to frame cluster idp_NG008008_6.
#   2. Monguno's moved site -> DTM site BO_S059 "Government Girls Secondary
#      School (GGSS)" - identified via Jack's field report naming the exact
#      cluster (idp_NG008024_10), not by name/proximity guessing (an initial
#      GDSS/BO_S098 guess based on "the field team called it a school" was
#      WRONG - confirmed by checking which of Monguno's 3 IDP clusters has
#      zero collected submissions: GGSS/idp_NG008024_10 is the only one of
#      the three with 0, the other two (Fulatari Camp/BO_S203, Water Board/
#      BO_S097) both have real submissions already).
#
# Patches BOTH the raw DTM source (so any future rebuild of the site-level
# candidate frame starts from the right point) and the already-built v9
# household-level frame's own latitude/longitude for these two clusters'
# rows (so KML/tool output is correct without waiting for a full site-frame
# rebuild). Original coordinates preserved in new columns in both files, per
# Jack's explicit instruction - nothing is silently overwritten without a
# trace of what it used to be.
# ==============================================================================
import csv
import shutil
from datetime import date

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"

DTM_CSV = PROJECT_DIR + r"\input_data\population\iom\IMPACT_IOM_NGA_R51_NE.csv"
STAGE2_FULL = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v9_FULL.csv"
STAGE2_WORKING = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v9_WORKING.csv"

TODAY = date.today().isoformat()

# (DTM Site ID, cluster_id, new_lat, new_lon)
UPDATES = [
    ("BO_S256", "idp_NG008008_6", 12.036651, 13.916215),
    ("BO_S059", "idp_NG008024_10", 12.688663, 13.589222),
]
SITE_TO_UPDATE = {sid: (cid, lat, lon) for sid, cid, lat, lon in UPDATES}
CLUSTER_TO_UPDATE = {cid: (sid, lat, lon) for sid, cid, lat, lon in UPDATES}


def backup(path):
    bak = path.replace(".csv", f"_PRE_street_child_gps_patch_{TODAY}.csv.bak")
    shutil.copy2(path, bak)
    print(f"  backed up -> {bak}")


def patch_dtm():
    print(f"Patching {DTM_CSV} ...")
    backup(DTM_CSV)
    with open(DTM_CSV, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    lat_i = header.index("Latitude N")
    lon_i = header.index("Longitude E")
    sid_i = header.index("Site ID (SSID)")
    header = header + ["Latitude N_original", "Longitude E_original", "gps_corrected_date", "gps_corrected_source"]
    n_patched = 0
    for r in rows[1:]:
        r += ["", "", "", ""]
        sid = r[sid_i]
        if sid in SITE_TO_UPDATE:
            _, lat, lon = SITE_TO_UPDATE[sid]
            r[-4] = r[lat_i]
            r[-3] = r[lon_i]
            r[-2] = TODAY
            r[-1] = "Street Child of Nigeria field verification (raw comms 2026-09-16)"
            r[lat_i] = str(lat)
            r[lon_i] = str(lon)
            n_patched += 1
    with open(DTM_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows[1:])
    print(f"  patched {n_patched} of {len(SITE_TO_UPDATE)} expected DTM rows.")


def patch_frame(path):
    print(f"Patching {path} ...")
    backup(path)
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    lat_i = header.index("latitude")
    lon_i = header.index("longitude")
    cid_i = header.index("cluster_id")
    has_orig_cols = "latitude_original" in header
    if not has_orig_cols:
        header = header + ["latitude_original", "longitude_original", "gps_corrected_date", "gps_corrected_source"]
    n_patched = 0
    touched_clusters = set()
    for r in rows[1:]:
        if not has_orig_cols:
            r += ["", "", "", ""]
        cid = r[cid_i]
        if cid in CLUSTER_TO_UPDATE:
            _, lat, lon = CLUSTER_TO_UPDATE[cid]
            r[-4] = r[lat_i]
            r[-3] = r[lon_i]
            r[-2] = TODAY
            r[-1] = "Street Child of Nigeria field verification (raw comms 2026-09-16)"
            r[lat_i] = str(lat)
            r[lon_i] = str(lon)
            n_patched += 1
            touched_clusters.add(cid)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows[1:])
    print(f"  patched {n_patched} row(s) across clusters {sorted(touched_clusters)}.")


if __name__ == "__main__":
    patch_dtm()
    patch_frame(STAGE2_FULL)
    patch_frame(STAGE2_WORKING)
    print("\nDone. Original coordinates preserved in *_original columns in all 3 files.")
