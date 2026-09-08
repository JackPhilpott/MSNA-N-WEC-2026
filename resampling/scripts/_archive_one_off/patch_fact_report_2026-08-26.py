# ==============================================================================
# One-off, targeted patch of FACT_accessibility_report.xlsx (2026-08-26),
# same class of correction as IMC's 2026-08-22 in-place fix - applying the
# user's already-established precedent (Accessible=Yes + insecurity-
# describing notes = contradiction, flip to No) rather than a new judgment
# call, plus normalizing a comma-split Reason category value and fixing 7
# rows where a real reason was given but Accessible was left blank.
# Run once; not part of the numbered pipeline.
# ==============================================================================
import openpyxl

PATH = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\resampling\input\accessibility_reports_returned\FACT_accessibility_report.xlsx"

CONTRADICTION_KEYS = {
    ("Kebbi", "Augie", "Tiggi"), ("Sokoto", "Gada", "Gilbadi"), ("Sokoto", "Gudu", "Bachaka"),
    ("Sokoto", "Silame", "Jekanadu"), ("Sokoto", "Silame", "Kwaido"),
}
PARTIAL_KEYS = {
    ("Sokoto", "Gudu", "Chilas"), ("Sokoto", "Gudu", "Marake"), ("Sokoto", "Gudu", "Tullun Doya"),
    ("Sokoto", "Kebbe", "Bardoki"), ("Sokoto", "Silame", "Bakale"), ("Sokoto", "Tureta", "Kwarare"),
}


def main():
    wb = openpyxl.load_workbook(PATH)
    ws = wb["Ward Accessibility"]
    headers = [c.value for c in ws[1]]
    idx = {h: i for i, h in enumerate(headers)}

    n_contra = n_partial = n_reason_fix = 0
    for r in range(2, ws.max_row + 1):
        state = ws.cell(row=r, column=idx["State"] + 1).value
        lga = ws.cell(row=r, column=idx["LGA"] + 1).value
        ward = ws.cell(row=r, column=idx["Ward (GRID3)"] + 1).value
        key = (state, lga, ward)

        acc_cell = ws.cell(row=r, column=idx["Accessible (Y/N)"] + 1)
        notes_cell = ws.cell(row=r, column=idx["Reason notes"] + 1)
        reason_cell = ws.cell(row=r, column=idx["Reason category"] + 1)

        if key in CONTRADICTION_KEYS and acc_cell.value == "Yes":
            original_notes = notes_cell.value
            acc_cell.value = "No"
            notes_cell.value = (
                f"CORRECTED 2026-08-26: originally marked Accessible=Yes but notes described insecurity "
                f'("{original_notes}") - contradiction, flipped to No per established project precedent '
                f"(treat Yes+insecurity-notes as No). Original notes preserved above."
            )
            n_contra += 1

        if key in PARTIAL_KEYS and not acc_cell.value:
            acc_cell.value = "No"
            n_partial += 1

        if reason_cell.value in ("Physical access (terrain", "flooding"):
            reason_cell.value = "Physical access (terrain, flooding, roads)"
            n_reason_fix += 1

    print(f"Contradictions fixed: {n_contra}")
    print(f"Partial rows fixed: {n_partial}")
    print(f"Reason category normalized: {n_reason_fix}")
    wb.save(PATH)
    print("Saved.")


if __name__ == "__main__":
    main()
