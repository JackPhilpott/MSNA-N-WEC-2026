"""
build_round1_candidate_aligned_to_DO_clean_2026-10-04.py  (CANDIDATE - for Jack's decision, nothing live)

The data officer's cleaned Round 1 dataset (IMPACT_NGA_Dataset_MSNA-UNHCR-2026-Round1_October-2026.xlsx, 3 Oct)
holds 23,206 MSNA households; our frozen Round 1 set (snapshot v2) has 25,447 achieved. Inside the Round 1
analysis coverage (NE + NW, Kebbi out) the difference is 277 weighted households:
  - 204 the DO deleted that our deletion log kept (185 "Duplicated survey" - near-identical copies of another
    interview or submitted twice - and 19 "Overall quality concerns"), 198 of them in coverage;
  - 79 submitted on 1 Oct, which the DO's pipeline treats as Round 2 (round_end_date = 2026-09-30).
(The other 1,958 are North-Central households absent from the DO's raw download - outside Round 1 coverage.)

This writes a CANDIDATE snapshot = snapshot v2 + those 283 households added to the deletions overlay, so the
verified representativity and weights scripts can be re-run unchanged on the DO's cleaned set. Run from the
workspace folder ("MSNA N-WEC 2026"):  python 1_sampling/resampling/scripts/one_off_analyses/build_round1_candidate_aligned_to_DO_clean_2026-10-04.py
"""
import csv, hashlib, os, re, shutil, zipfile
from xml.etree.ElementTree import iterparse

DO_FILE = "2_monitoring/cleaning/NGA2605_MSNA_UNHCR_Combined_Cleaning/output/final/IMPACT_NGA_Dataset_MSNA-UNHCR-2026-Round1_October-2026.xlsx"
SNAP_V2 = "1_sampling/resampling/output/round1_final_snapshot_v2_2026-10-02"
KEY = "2_monitoring/reports/round1_weighting_package_2026-10-02/01_weights/R1_household_status_all_28046.csv"
OUT = "1_sampling/resampling/output/round1_candidate_aligned_to_DO_clean_2026-10-04/snapshot"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def read_sheets(path, wanted):
    """Stream only the wanted columns of the wanted sheets (the workbook is 387 MB)."""
    z = zipfile.ZipFile(path)
    wb = z.read("xl/workbook.xml").decode()
    rels = z.read("xl/_rels/workbook.xml.rels").decode()
    rmap = {re.search(r'Id="([^"]+)"', m).group(1): re.search(r'Target="([^"]+)"', m).group(1)
            for m in re.findall(r"<Relationship [^>]*>", rels)}
    sheets = {n: (lambda t: t if t.startswith("xl/") else "xl/" + t)(rmap[r].lstrip("/"))
              for n, r in re.findall(r'<sheet [^>]*?name="([^"]+)"[^>]*?r:id="([^"]+)"', wb)}
    ss = []
    with z.open("xl/sharedStrings.xml") as f:
        for _, el in iterparse(f, events=("end",)):
            if el.tag == NS + "si":
                ss.append("".join(t.text or "" for t in el.iter(NS + "t")))
                el.clear()
    out = {}
    for sheet, cols in wanted.items():
        rows, hdr = [], None
        with z.open(sheets[sheet]) as f:
            for _, el in iterparse(f, events=("end",)):
                if el.tag != NS + "row":
                    continue
                vals = {}
                for c in el.findall(NS + "c"):
                    v, t = c.find(NS + "v"), c.get("t")
                    if t == "inlineStr":
                        val = "".join(x.text or "" for x in c.iter(NS + "t"))
                    elif v is None:
                        continue
                    else:
                        val = ss[int(v.text)] if t == "s" else v.text
                    vals[re.match(r"[A-Z]+", c.get("r")).group(0)] = val
                if hdr is None:
                    hdr = {k: n.strip() for k, n in vals.items()}
                else:
                    rows.append({hdr[k]: v for k, v in vals.items() if k in hdr and (not cols or hdr[k] in cols)})
                el.clear()
        out[sheet] = rows
    return out


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    do = read_sheets(DO_FILE, {"hh_clean_data": {"uuid", "assessment"}, "hh_raw_data": {"uuid", "assessment"},
                               "hh_deletion_log": set()})
    clean = {r["uuid"] for r in do["hh_clean_data"] if r.get("assessment") == "MSNA_R1"}
    raw = {r["uuid"] for r in do["hh_raw_data"] if r.get("assessment") == "MSNA_R1"}
    dlog = {r["uuid"]: r for r in do["hh_deletion_log"]}
    with open(os.path.join(SNAP_V2, "real_submissions.csv"), encoding="utf-8") as f:
        rs = {r["submission_uuid"]: r for r in csv.DictReader(f)}
    with open(KEY, encoding="utf-8") as f:
        key = {r["uuid"]: r for r in csv.DictReader(f)}
    achieved = {u for u, r in rs.items() if r["deletion_status"] == "NA"}

    assert not (clean - achieved), "DO clean data holds a household our Round 1 set removed or lacks - investigate"
    do_deleted = sorted(u for u in achieved - clean if u in dlog)
    late = sorted(u for u in achieved - clean - set(dlog) if key[u]["r1_in_analysis_coverage"] == "TRUE")
    absent_nc = achieved - clean - set(dlog) - set(late)
    assert len(do_deleted) == 204 and len(late) == 79, (len(do_deleted), len(late))
    assert all(rs[u]["submission_date"] == "2026-10-01" for u in late), "a 'late' household is not a 1 Oct submission"
    assert all(u not in raw for u in late) and all(u in raw for u in do_deleted)
    assert all(key[u]["r1_in_analysis_coverage"] == "FALSE" for u in absent_nc), "a household absent from the DO data is inside coverage"

    os.makedirs(OUT, exist_ok=True)
    for fn in ("real_submissions.csv", "ROUND1_MEMBERSHIP.csv"):
        shutil.copy2(os.path.join(SNAP_V2, fn), os.path.join(OUT, fn))
    with open(os.path.join(SNAP_V2, "CONFIRMED_DELETIONS_OVERLAY.csv"), encoding="utf-8", newline="") as f:
        rdr = csv.DictReader(f)
        fields, rows = rdr.fieldnames, list(rdr)
    for u in do_deleted:
        d = dlog[u]
        issue = next((v for k, v in d.items() if k.startswith("Type of Issue")), "")
        rows.append({"uuid": u, "reason": f"DO cleaning 3 Oct: {issue}", "status": "confirmed", "confirmed_by": "data officer",
                     "resolution": (d.get("reason_deletion") or "")[:300], "resolution_date": "2026-10-03"})
    for u in late:
        rows.append({"uuid": u, "reason": "submitted 1 Oct, after the DO's Round 1 cut-off (round_end_date 2026-09-30)",
                     "status": "confirmed", "confirmed_by": "data officer", "resolution": "Round 2 in the DO's cleaned dataset",
                     "resolution_date": "2026-10-03"})
    with open(os.path.join(OUT, "CONFIRMED_DELETIONS_OVERLAY.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(OUT, "NOTE.txt"), "w", encoding="utf-8") as f:
        f.write("CANDIDATE for Jack's decision (4 Oct): snapshot v2 + 204 DO-cleaning deletions + 79 households submitted "
                "1 Oct (Round 2 in the DO's cleaned dataset) added to the overlay. Round 1 achieved 25,447 -> "
                f"{len(achieved) - 283:,}; in coverage 21,705 -> 21,428 = the DO's cleaned MSNA households in coverage.\n")
    with open(os.path.join(OUT, "MD5.txt"), "w", encoding="utf-8", newline="\n") as f:
        for fn in sorted(os.listdir(OUT)):
            if fn != "MD5.txt":
                f.write(f"{md5(os.path.join(OUT, fn))}  {fn}\n")
    print(f"DO clean MSNA {len(clean):,} | our achieved {len(achieved):,} | DO-deleted {len(do_deleted)} | late {len(late)} | "
          f"absent North-Central etc. {len(absent_nc):,} | candidate achieved {len(achieved) - 283:,}")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
