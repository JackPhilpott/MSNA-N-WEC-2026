# -*- coding: utf-8 -*-
# One-off patch (not part of the batch pipeline, does not rerun any sampling
# stage) that adds a strata_id column to
# output/strata_level_sampling_frame.csv, matching the strata_id convention
# already used in output/stage2_sampling_frame.csv (pop_type + "_" +
# adm2_pcode, e.g. "host_NG007002") so the two tables can be joined.
#
# Operates on the CSV as text: every field is read and rewritten verbatim
# except for the new column, so no existing value's formatting (in
# particular full floating-point precision in n_pop/N_hh) is at risk of
# being altered by a numeric read/write round-trip.
import csv
import os

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ST_CSV = os.path.join(PROJECT_DIR, "output", "strata_level_sampling_frame.csv")

# Columns that are quoted in the existing file (character columns) - the new
# strata_id column follows the same rule since it's a character column too.
QUOTED_COLS = {
    "region", "adm1_pcode", "adm1_name", "adm2_pcode", "adm2_name",
    "pop_type", "selection_type", "strata_id",
}


def format_field(col_name, value, is_header):
    # The header row quotes every column name (they're always strings);
    # data rows only quote character-typed columns.
    if is_header or col_name in QUOTED_COLS:
        return '"' + value.replace('"', '""') + '"'
    return value


with open(ST_CSV, encoding="utf-8", newline="") as f:
    rows = list(csv.reader(f))

header = rows[0]
if "strata_id" in header:
    raise SystemExit("strata_id already present in strata_level_sampling_frame.csv - aborting.")

pop_type_idx = header.index("pop_type")
adm2_pcode_idx = header.index("adm2_pcode")

new_header = header[:pop_type_idx + 1] + ["strata_id"] + header[pop_type_idx + 1:]

new_rows = [new_header]
for row in rows[1:]:
    strata_id = f"{row[pop_type_idx]}_{row[adm2_pcode_idx]}"
    new_rows.append(row[:pop_type_idx + 1] + [strata_id] + row[pop_type_idx + 1:])

with open(ST_CSV, "w", encoding="utf-8", newline="") as f:
    for i, row in enumerate(new_rows):
        is_header = i == 0
        line = ",".join(
            format_field(c, v, is_header) for c, v in zip(new_header, row)
        )
        f.write(line + "\r\n")

print(f"strata_id added to {len(new_rows) - 1} rows in {ST_CSV}")
