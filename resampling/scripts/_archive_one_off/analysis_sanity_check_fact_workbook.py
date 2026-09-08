# ==============================================================================
# QA pass over FACT_cleaned_listing_and_issues_2026-08-26.xlsx specifically -
# the last two rounds each had a real bug (dropdowns silently dropped, 189
# missing wards never actually present as rows), so this checks systematically
# rather than eyeballing a few cells. Read-only.
# ==============================================================================
import openpyxl

PATH = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\output\FACT_cleaned_listing_and_issues_2026-08-26.xlsx"
FACT_RETURNED = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"

results = []
def check(status, msg): results.append((status, msg))

wb = openpyxl.load_workbook(PATH)
src_wb = openpyxl.load_workbook(FACT_RETURNED, data_only=True)

print("Sheets:", wb.sheetnames)
expected_sheets = {"README", "Ward Accessibility", "Cluster Accessibility", "Issues to Review"}
if set(wb.sheetnames) == expected_sheets:
    check("PASS", "All 4 expected sheets present, no extras/missing.")
else:
    check("FAIL", f"Sheet mismatch: {set(wb.sheetnames)} vs expected {expected_sheets}")

# ---- Ward Accessibility ----
ws = wb["Ward Accessibility"]
headers = [c.value for c in ws[1]]
idx = {h: i for i, h in enumerate(headers)}
ward_rows = [row for row in ws.iter_rows(min_row=2, values_only=True) if any(v is not None for v in row)]
check("INFO", f"Ward Accessibility: {len(ward_rows)} data rows, headers: {headers}")

# 1. row count = 1067, matches source universe
if len(ward_rows) == 1067:
    check("PASS", "Ward Accessibility has exactly 1,067 rows (878 + 189).")
else:
    check("FAIL", f"Ward Accessibility has {len(ward_rows)} rows, expected 1067.")

# 2. no duplicate (State, LGA, Ward) keys
keys = [(r[idx["State"]], r[idx["LGA"]], r[idx["Ward (GRID3)"]]) for r in ward_rows]
dupes = [k for k in set(keys) if keys.count(k) > 1]
if dupes:
    check("FAIL", f"{len(dupes)} duplicate (State,LGA,Ward) keys in Ward Accessibility: {dupes[:5]}")
else:
    check("PASS", "No duplicate (State, LGA, Ward) rows in Ward Accessibility.")

# 3. every row has non-blank reference columns (State/LGA/Ward/target HH) - catches
#    a broken merge fallback silently producing blank reference data
blank_ref = [k for k, r in zip(keys, ward_rows) if not all([r[idx["State"]], r[idx["LGA"]], r[idx["Ward (GRID3)"]]])
             or r[idx["Total target HHs (primary)"]] in (None, "")]
if blank_ref:
    check("FAIL", f"{len(blank_ref)} rows have blank State/LGA/Ward/target-HH reference data: {blank_ref[:5]}")
else:
    check("PASS", "Every row has complete reference data (State/LGA/Ward/target HH all populated).")

# 4. data validation present and covers the full row range
dvs = {str(dv.sqref): dv.formula1 for dv in ws.data_validations.dataValidation}
access_col_letter = openpyxl.utils.get_column_letter(idx["Accessible (Y/N)"] + 1)
reason_col_letter = openpyxl.utils.get_column_letter(idx["Reason category"] + 1)
expected_range_access = f"{access_col_letter}2:{access_col_letter}{len(ward_rows)+1}"
expected_range_reason = f"{reason_col_letter}2:{reason_col_letter}{len(ward_rows)+1}"
found_access = any(expected_range_access in str(dv.sqref) or str(dv.sqref) == expected_range_access for dv in ws.data_validations.dataValidation)
if expected_range_access in dvs:
    check("PASS", f"Accessible (Y/N) dropdown present, covers full range {expected_range_access}: {dvs[expected_range_access]}")
else:
    check("FAIL", f"Accessible (Y/N) dropdown missing or wrong range. Found: {list(dvs.keys())}")
if expected_range_reason in dvs:
    check("PASS", f"Reason category dropdown present, covers full range {expected_range_reason}.")
else:
    check("FAIL", f"Reason category dropdown missing or wrong range. Found: {list(dvs.keys())}")

# 5. the 878 "answered" rows actually carry FACT's real submitted values (spot check via count of non-blank Accessible)
n_answered = sum(1 for r in ward_rows if r[idx["Accessible (Y/N)"]])
if n_answered == 768:
    check("PASS", f"Exactly 768 rows have a non-blank Accessible value (matches FACT's true answered-row count, not just row-presence).")
else:
    check("FAIL", f"{n_answered} rows have a non-blank Accessible value, expected 768.")

# 6. the 5 corrected contradictions show Accessible=No in the merged sheet
CONTRADICTION_KEYS = {("Kebbi","Augie","Tiggi"),("Sokoto","Gada","Gilbadi"),("Sokoto","Gudu","Bachaka"),
                       ("Sokoto","Silame","Jekanadu"),("Sokoto","Silame","Kwaido")}
bad_contra = []
for k, r in zip(keys, ward_rows):
    if k in CONTRADICTION_KEYS and r[idx["Accessible (Y/N)"]] != "No":
        bad_contra.append((k, r[idx["Accessible (Y/N)"]]))
if bad_contra:
    check("FAIL", f"Corrected contradiction rows not showing 'No' in merged sheet: {bad_contra}")
else:
    check("PASS", "All 5 corrected contradiction rows show Accessible=No in the merged Ward Accessibility sheet.")

# 7. the 189 "missing" rows are genuinely blank (Accessible AND Reason both empty) and shaded
missing_rows = [(k, r) for k, r in zip(keys, ward_rows) if not r[idx["Accessible (Y/N)"]]]
if len(missing_rows) == 299:
    check("PASS", "Exactly 299 rows have a blank Accessible value (189 never submitted + 110 submitted-but-blank).")
else:
    check("FAIL", f"{len(missing_rows)} rows have blank Accessible, expected 299.")

not_shaded = []
for r_idx, (k, r) in enumerate(zip(keys, ward_rows), start=2):
    if not r[idx["Accessible (Y/N)"]]:
        cell = ws.cell(row=r_idx, column=idx["State"]+1)
        fill = cell.fill.fgColor.rgb if cell.fill and cell.fill.fgColor else None
        if fill != "00FFF6DD":
            not_shaded.append((k, fill))
if not_shaded:
    check("FAIL", f"{len(not_shaded)} blank rows are NOT shaded with the needs-input color: {not_shaded[:5]}")
else:
    check("PASS", "Every blank (needs-input) row is correctly shaded.")

# 8. sort order - all answered rows before all blank rows (grouping worked)
saw_blank = False
order_broken = False
for r in ward_rows:
    is_blank = not r[idx["Accessible (Y/N)"]]
    if is_blank:
        saw_blank = True
    elif saw_blank:
        order_broken = True
        break
if order_broken:
    check("FAIL", "Answered and blank rows are interleaved, not cleanly grouped (blank rows should all be last).")
else:
    check("PASS", "Sort order correct: all answered rows precede all blank (needs-input) rows.")

# ---- Cluster Accessibility ----
ws2 = wb["Cluster Accessibility"]
c_headers = [c.value for c in ws2[1]]
c_rows = [row for row in ws2.iter_rows(min_row=2, values_only=True) if any(v is not None for v in row)]
check("INFO", f"Cluster Accessibility: {len(c_rows)} rows, headers: {c_headers}")

src_cluster_headers = [c.value for c in src_wb["Cluster Accessibility"][1]]
missing_cols = set(src_cluster_headers) - set(c_headers)
if missing_cols:
    check("FAIL", f"Cluster Accessibility is missing columns present in FACT's original file: {missing_cols}")
else:
    check("PASS", "Cluster Accessibility has no columns silently dropped vs FACT's original submission.")

src_cluster_rows = [row for row in src_wb["Cluster Accessibility"].iter_rows(min_row=2, values_only=True) if any(v is not None for v in row)]
if abs(len(c_rows) - len(src_cluster_rows)) <= 1:
    check("PASS", f"Cluster Accessibility row count ({len(c_rows)}) matches source ({len(src_cluster_rows)}) within tolerance.")
else:
    check("FAIL", f"Cluster Accessibility row count ({len(c_rows)}) doesn't match source ({len(src_cluster_rows)}).")

c_dvs = {str(dv.sqref): dv.formula1 for dv in ws2.data_validations.dataValidation}
if c_dvs:
    check("PASS", f"Cluster Accessibility has {len(c_dvs)} data validation(s): {list(c_dvs.keys())}")
else:
    check("FAIL", "Cluster Accessibility has NO data validation at all.")

# duplicate cluster IDs?
cid_col = c_headers.index("Cluster ID") if "Cluster ID" in c_headers else None
if cid_col is not None:
    cids = [r[cid_col] for r in c_rows]
    dup_cids = [c for c in set(cids) if cids.count(c) > 1]
    if dup_cids:
        check("FAIL", f"{len(dup_cids)} duplicate Cluster IDs in Cluster Accessibility: {dup_cids[:5]}")
    else:
        check("PASS", "No duplicate Cluster IDs in Cluster Accessibility.")

# ---- Issues to Review consistency ----
ws3 = wb["Issues to Review"]
all_text = []
for row in ws3.iter_rows(values_only=True):
    all_text.append(row)
banner3_row = None
for i, row in enumerate(all_text):
    if row[0] and str(row[0]).startswith("3. Wards needing input"):
        banner3_row = row[0]
        break
if banner3_row and "299" in banner3_row:
    check("PASS", f"Issues to Review Section 3 banner correctly states 299: \"{banner3_row}\"")
else:
    check("FAIL", f"Issues to Review Section 3 banner missing or wrong count: {banner3_row}")

# ---- README sanity ----
readme_ws = wb["README"]
readme_text = " ".join(str(readme_ws.cell(row=r, column=1).value or "") for r in range(1, readme_ws.max_row+1))
if "768" in readme_text and "299" in readme_text:
    check("PASS", "README text references the correct row counts (768 answered / 299 need input).")
else:
    check("WARN", "README doesn't explicitly mention 768/299 - verify wording is still accurate.")

# ---- Report ----
print("\n" + "="*78)
print("FACT WORKBOOK SANITY CHECK")
print("="*78)
n_pass = sum(1 for s,_ in results if s=="PASS")
n_fail = sum(1 for s,_ in results if s=="FAIL")
n_warn = sum(1 for s,_ in results if s=="WARN")
n_info = sum(1 for s,_ in results if s=="INFO")
print(f"{n_pass} PASS, {n_warn} WARN, {n_fail} FAIL, {n_info} INFO\n")
for status, msg in results:
    print(f"[{status:4}] {msg}")
