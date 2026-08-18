import csv
from collections import defaultdict

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo
from openpyxl.formatting.rule import ColorScaleRule

SRC = r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\c--Users-JackPHILPOTT-ACTED-IMPACT-NGA---02--MSNA-4--Data-MSNA-N-WEC-2026\f694c267-aafa-4c1b-a97c-9d8c132b0976\scratchpad\border_scenarios_strata_level.csv"
OUT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\data\supporting_analysis\border_buffer_scenarios\NGA_MSNA_2026_border_buffer_scenarios.xlsx"

import os
os.makedirs(os.path.dirname(OUT), exist_ok=True)

rows = list(csv.DictReader(open(SRC, encoding="utf-8")))
for r in rows:
    for k in ("n_pop", "N_hh", "n_hex", "hh_sample_raw", "hh_sample", "hh_sample_buffer",
              "clusters_raw", "clusters", "clusters_target_stage1", "target_sample", "m_used"):
        r[k] = float(r[k]) if r[k] not in ("", "NA") else 0.0
    r["certainty_stratum"] = r["certainty_stratum"] == "TRUE"
    r["excluded_infeasible"] = r["excluded_infeasible"] == "TRUE"

SCEN = ["S1_current", "S2_5km_all", "S3_no_buffer"]
SCEN_LABEL = {"S1_current": "S1: Current (Niger 20km / others 5km)", "S2_5km_all": "S2: 5km on all borders", "S3_no_buffer": "S3: No border buffer"}

NAVY, BLUE, GREEN, WHITE = "1B2A4A", "2C5F8A", "1F7A5C", "FFFFFF"
AMBER, RED, MINT = "FFF2CC", "F4CCCC", "D5F0E3"

wb = openpyxl.Workbook()
wb.remove(wb.active)


def style_header(ws, ncols, color):
    for c in range(1, ncols + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color=WHITE)
        cell.fill = PatternFill("solid", fgColor=color)
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    ws.freeze_panes = "A2"


def autosize(ws, widths):
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w


def add_table(ws, name, nrows, ncols):
    ref = f"A1:{get_column_letter(ncols)}{nrows}"
    tbl = Table(displayName=name, ref=ref)
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)


# ---------------------------------------------------------------------------
# README
# ---------------------------------------------------------------------------
ws = wb.create_sheet("README")
ws.column_dimensions["A"].width = 115
readme_lines = [
    ("NGA MSNA 2026 - International border-buffer scenario test-run", True, 15),
    ("", False, 11),
    ("Purpose:", True, 12),
    ("Compares the population and design sample-size impact of three different international-border exclusion", False, 11),
    ("buffer settings, to inform a decision on whether to adjust the current buffer. Produced 2026-08-05.", False, 11),
    ("", False, 11),
    ("Scenarios compared:", True, 12),
    ("  S1 (current design): 20km buffer from the Niger border, 5km from Chad/Cameroon/Benin.", False, 11),
    ("  S2: 5km buffer on all four international borders (Niger reduced from 20km to 5km, others unchanged).", False, 11),
    ("  S3: no international-border buffer at all (0km) - FACT admin3 inaccessibility exclusions still applied.", False, 11),
    ("", False, 11),
    ("The FACT-flagged inaccessible-area exclusion (separate from the border buffer) is held constant across all", False, 11),
    ("three scenarios - only the country-border buffer distance changes.", False, 11),
    ("", False, 11),
    ("Method:", True, 12),
    ("Only LGAs within 20km of the Niger/Chad/Cameroon/Benin border can possibly differ between scenarios (51 of", False, 11),
    ("323 LGAs, see 'Affected LGAs' sheet) - every other LGA's population and sample are identical across all three", False, 11),
    ("scenarios by construction and were reused directly from the live, current sampling frame rather than", False, 11),
    ("recomputed. For the 51 border-adjacent LGAs, the hexagon grid, WorldPop population extraction (Non-IDP) and", False, 11),
    ("IOM DTM site-to-hexagon join (IDP) were rerun for each scenario's accessible area. Sample-size figures use", False, 11),
    ("the sampling frame's own build_sampling_plan() formula and certainty-stratum small-population exclusion", False, 11),
    ("check (verbatim, same defaults), applied per stratum per scenario.", False, 11),
    ("", False, 11),
    ("Validation: the S1 (current) recomputation was checked against the live, currently-delivered sampling frame", False, 11),
    ("and matches it exactly for both population (N_hh) and hexagon counts in every affected LGA, and reproduces", False, 11),
    ("the officially documented achieved IDP sample (19,236) and excluded-strata count (18) exactly.", False, 11),
    ("", False, 11),
    ("Scope limitation - read before using these figures operationally:", True, 12),
    ("'Target sample' here is the STAGE 1 DESIGN target (clusters_target_stage1 x 6), not the final delivered", False, 11),
    ("sample. It does not include the separate below-target-shortfall correction (new supplementary clusters added", False, 11),
    ("where a stratum's actually-drawn buildings/sites fall short of its Stage-1 target - see CLAUDE.md Revision", False, 11),
    ("2026-07-22) or the partner-coverage exclusion layer (Section 8 of the methodology doc). That correction is", False, 11),
    ("Stage-2-execution-dependent (needs real building/site draws) and was not rerun three times for this", False, 11),
    ("comparison - reproducing it would need a full pipeline rerun per scenario, not a same-day test-run. This is", False, 11),
    ("why S1's Non-IDP national target here (32,928) is close to but not identical to the delivered design total", False, 11),
    ("(~33,010) - the ~82-interview gap is exactly that correction, consistently excluded from all three scenarios", False, 11),
    ("so the SCENARIO COMPARISON (S2-S1, S3-S1) remains a fair, apples-to-apples read even though the absolute S1", False, 11),
    ("baseline is not the final delivered figure.", False, 11),
    ("", False, 11),
    ("Sheets:", True, 12),
    ("  National Summary - headline totals by population group and scenario.", False, 11),
    ("  Region Summary - NC/NE/NW rollup.", False, 11),
    ("  State Summary - all 14 assessment states.", False, 11),
    ("  Affected LGAs (full detail) - the 51 border-adjacent LGAs only, every column, both population groups.", False, 11),
    ("  All LGAs (reference) - full 323-LGA table for completeness (269 rows are identical across all 3 scenarios).", False, 11),
]
r = 1
for text, bold, size in readme_lines:
    cell = ws.cell(row=r, column=1, value=text)
    cell.font = Font(bold=bold, size=size, color=NAVY if bold and size > 12 else "000000")
    r += 1

wb.save(OUT)
print("README written. Continuing with data sheets...")

# ---------------------------------------------------------------------------
# Build a pivot: key -> {scenario -> row}
# ---------------------------------------------------------------------------
by_key = defaultdict(dict)
for r in rows:
    key = (r["region"], r["adm1_name"], r["adm2_name"], r["adm2_pcode"], r["pop_type"])
    by_key[key][r["scenario"]] = r

affected_pcodes = set()
for key, scen_map in by_key.items():
    if "S1_current" not in scen_map:
        continue
    base = scen_map["S1_current"]
    for s in ("S2_5km_all", "S3_no_buffer"):
        if s in scen_map and scen_map[s]["N_hh"] != base["N_hh"]:
            affected_pcodes.add(key[3])


def lga_row(key, scen_map):
    region, adm1, adm2, pcode, pop_type = key
    s1 = scen_map.get("S1_current", {})
    s2 = scen_map.get("S2_5km_all", {})
    s3 = scen_map.get("S3_no_buffer", {})

    def g(d, f, default=0):
        return d.get(f, default) if d else default

    return {
        "region": region, "state": adm1, "lga": adm2, "adm2_pcode": pcode, "pop_type": pop_type,
        "N_hh_S1": g(s1, "N_hh"), "N_hh_S2": g(s2, "N_hh"), "N_hh_S3": g(s3, "N_hh"),
        "N_hh_delta_S2_vs_S1": g(s2, "N_hh") - g(s1, "N_hh"),
        "N_hh_delta_S3_vs_S1": g(s3, "N_hh") - g(s1, "N_hh"),
        "target_sample_S1": g(s1, "target_sample"), "target_sample_S2": g(s2, "target_sample"), "target_sample_S3": g(s3, "target_sample"),
        "target_sample_delta_S2_vs_S1": g(s2, "target_sample") - g(s1, "target_sample"),
        "target_sample_delta_S3_vs_S1": g(s3, "target_sample") - g(s1, "target_sample"),
        "n_hex_S1": g(s1, "n_hex"), "n_hex_S2": g(s2, "n_hex"), "n_hex_S3": g(s3, "n_hex"),
        "excluded_infeasible_S1": g(s1, "excluded_infeasible", False),
        "excluded_infeasible_S2": g(s2, "excluded_infeasible", False),
        "excluded_infeasible_S3": g(s3, "excluded_infeasible", False),
    }


all_lga_rows = [lga_row(k, v) for k, v in by_key.items()]
all_lga_rows.sort(key=lambda r: (r["region"], r["state"], r["lga"], r["pop_type"]))
affected_lga_rows = [r for r in all_lga_rows if r["adm2_pcode"] in affected_pcodes]

print(f"Total LGA x pop_type rows: {len(all_lga_rows)}, affected: {len(affected_lga_rows)}, affected LGAs: {len(affected_pcodes)}")

LGA_COLS = ["region", "state", "lga", "adm2_pcode", "pop_type",
            "N_hh_S1", "N_hh_S2", "N_hh_S3", "N_hh_delta_S2_vs_S1", "N_hh_delta_S3_vs_S1",
            "target_sample_S1", "target_sample_S2", "target_sample_S3",
            "target_sample_delta_S2_vs_S1", "target_sample_delta_S3_vs_S1",
            "n_hex_S1", "n_hex_S2", "n_hex_S3",
            "excluded_infeasible_S1", "excluded_infeasible_S2", "excluded_infeasible_S3"]
LGA_HEADERS = ["Region", "State", "LGA", "Adm2 Pcode", "Population group",
               "HHs (S1 current)", "HHs (S2 5km all)", "HHs (S3 no buffer)", "HH delta S2-S1", "HH delta S3-S1",
               "Target sample (S1)", "Target sample (S2)", "Target sample (S3)",
               "Sample delta S2-S1", "Sample delta S3-S1",
               "Hexes selected (S1)", "Hexes selected (S2)", "Hexes selected (S3)",
               "Excluded - small pop (S1)", "Excluded - small pop (S2)", "Excluded - small pop (S3)"]


def write_lga_sheet(name, data_rows, color):
    ws = wb.create_sheet(name)
    for c, h in enumerate(LGA_HEADERS, start=1):
        ws.cell(row=1, column=c, value=h)
    for i, row in enumerate(data_rows, start=2):
        for c, col in enumerate(LGA_COLS, start=1):
            ws.cell(row=i, column=c, value=row[col])
    style_header(ws, len(LGA_COLS), color)
    autosize(ws, [8, 12, 16, 12, 16] + [16] * 10 + [11, 11, 11] + [13, 13, 13])
    tname = name.replace(" ", "_").replace("(", "").replace(")", "")
    add_table(ws, tname, len(data_rows) + 1, len(LGA_COLS))
    for col_letter in ["I", "J", "N", "O"]:
        ws.conditional_formatting.add(
            f"{col_letter}2:{col_letter}{len(data_rows)+1}",
            ColorScaleRule(start_type="min", start_color="FFFFFF", end_type="max", end_color="F4B183")
        )
    return ws


write_lga_sheet("Affected LGAs (full detail)", affected_lga_rows, BLUE)
write_lga_sheet("All LGAs (reference)", all_lga_rows, "808080")


def build_rollup(group_fields, sheet_name, color):
    agg = defaultdict(lambda: {"N_hh_S1": 0, "N_hh_S2": 0, "N_hh_S3": 0,
                                "target_sample_S1": 0, "target_sample_S2": 0, "target_sample_S3": 0})
    seen_lgas = defaultdict(set)
    for r in all_lga_rows:
        key = tuple(r[f] for f in group_fields) + (r["pop_type"],)
        a = agg[key]
        a["N_hh_S1"] += r["N_hh_S1"]; a["N_hh_S2"] += r["N_hh_S2"]; a["N_hh_S3"] += r["N_hh_S3"]
        a["target_sample_S1"] += r["target_sample_S1"]; a["target_sample_S2"] += r["target_sample_S2"]; a["target_sample_S3"] += r["target_sample_S3"]
        seen_lgas[key].add(r["adm2_pcode"])

    out_rows = []
    for key, a in sorted(agg.items()):
        out_rows.append({
            **dict(zip(group_fields, key[:-1])),
            "pop_type": key[-1],
            "n_lgas": len(seen_lgas[key]),
            "N_hh_S1": a["N_hh_S1"], "N_hh_S2": a["N_hh_S2"], "N_hh_S3": a["N_hh_S3"],
            "N_hh_delta_S2_vs_S1": a["N_hh_S2"] - a["N_hh_S1"], "N_hh_delta_S3_vs_S1": a["N_hh_S3"] - a["N_hh_S1"],
            "target_sample_S1": a["target_sample_S1"], "target_sample_S2": a["target_sample_S2"], "target_sample_S3": a["target_sample_S3"],
            "target_sample_delta_S2_vs_S1": a["target_sample_S2"] - a["target_sample_S1"],
            "target_sample_delta_S3_vs_S1": a["target_sample_S3"] - a["target_sample_S1"],
        })

    headers = [f.replace("_", " ").title() for f in group_fields] + [
        "Population group", "# LGAs",
        "HHs (S1)", "HHs (S2)", "HHs (S3)", "HH delta S2-S1", "HH delta S3-S1",
        "Target sample (S1)", "Target sample (S2)", "Target sample (S3)", "Sample delta S2-S1", "Sample delta S3-S1"
    ]
    cols = group_fields + ["pop_type", "n_lgas", "N_hh_S1", "N_hh_S2", "N_hh_S3", "N_hh_delta_S2_vs_S1", "N_hh_delta_S3_vs_S1",
                            "target_sample_S1", "target_sample_S2", "target_sample_S3",
                            "target_sample_delta_S2_vs_S1", "target_sample_delta_S3_vs_S1"]

    ws = wb.create_sheet(sheet_name)
    for c, h in enumerate(headers, start=1):
        ws.cell(row=1, column=c, value=h)
    for i, row in enumerate(out_rows, start=2):
        for c, col in enumerate(cols, start=1):
            ws.cell(row=i, column=c, value=row[col])
    style_header(ws, len(cols), color)
    autosize(ws, [14] * len(group_fields) + [16, 8] + [14] * 10)
    add_table(ws, sheet_name.replace(" ", "_"), len(out_rows) + 1, len(cols))
    return out_rows


region_rows = build_rollup(["region"], "Region Summary", GREEN)
state_rows = build_rollup(["region", "state"], "State Summary", GREEN)

# National (both pop_type combined per scenario, and split)
ws = wb.create_sheet("National Summary")
ws.cell(row=1, column=1, value="Population group")
nat_headers = ["HHs (S1 current)", "HHs (S2 5km all)", "HHs (S3 no buffer)", "HH delta S2-S1", "HH delta S3-S1",
               "Target sample (S1)", "Target sample (S2)", "Target sample (S3)", "Sample delta S2-S1", "Sample delta S3-S1"]
for c, h in enumerate(nat_headers, start=2):
    ws.cell(row=1, column=c, value=h)

nat = defaultdict(lambda: {"N_hh_S1": 0, "N_hh_S2": 0, "N_hh_S3": 0, "target_sample_S1": 0, "target_sample_S2": 0, "target_sample_S3": 0})
for r in all_lga_rows:
    n = nat[r["pop_type"]]
    n["N_hh_S1"] += r["N_hh_S1"]; n["N_hh_S2"] += r["N_hh_S2"]; n["N_hh_S3"] += r["N_hh_S3"]
    n["target_sample_S1"] += r["target_sample_S1"]; n["target_sample_S2"] += r["target_sample_S2"]; n["target_sample_S3"] += r["target_sample_S3"]

row_i = 2
pop_labels = {"non_idp": "Non-IDP", "idp": "IDP"}
totals = {"N_hh_S1": 0, "N_hh_S2": 0, "N_hh_S3": 0, "target_sample_S1": 0, "target_sample_S2": 0, "target_sample_S3": 0}
for pt in ["non_idp", "idp"]:
    n = nat[pt]
    for k in totals:
        totals[k] += n[k]
    ws.cell(row=row_i, column=1, value=pop_labels[pt])
    vals = [n["N_hh_S1"], n["N_hh_S2"], n["N_hh_S3"], n["N_hh_S2"] - n["N_hh_S1"], n["N_hh_S3"] - n["N_hh_S1"],
            n["target_sample_S1"], n["target_sample_S2"], n["target_sample_S3"],
            n["target_sample_S2"] - n["target_sample_S1"], n["target_sample_S3"] - n["target_sample_S1"]]
    for c, v in enumerate(vals, start=2):
        ws.cell(row=row_i, column=c, value=v)
    row_i += 1

ws.cell(row=row_i, column=1, value="TOTAL (Non-IDP + IDP)")
vals = [totals["N_hh_S1"], totals["N_hh_S2"], totals["N_hh_S3"], totals["N_hh_S2"] - totals["N_hh_S1"], totals["N_hh_S3"] - totals["N_hh_S1"],
        totals["target_sample_S1"], totals["target_sample_S2"], totals["target_sample_S3"],
        totals["target_sample_S2"] - totals["target_sample_S1"], totals["target_sample_S3"] - totals["target_sample_S1"]]
for c, v in enumerate(vals, start=2):
    cell = ws.cell(row=row_i, column=c, value=v)
    cell.font = Font(bold=True)
for c in range(1, 12):
    ws.cell(row=row_i, column=c).fill = PatternFill("solid", fgColor=AMBER)

style_header(ws, 11, NAVY)
autosize(ws, [24] + [16] * 10)

wb.save(OUT)
print("Workbook complete:", OUT)
print(f"Affected LGAs: {len(affected_pcodes)}")
