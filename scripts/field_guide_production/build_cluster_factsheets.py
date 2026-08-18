# ==============================================================================
# Cluster-level field factsheets - one page per cluster, merged into the same
# partner_dc_files folder structure as the KML/LGA-map deliverables, named by
# cluster ID. Production implementation of the design approved in
# MSNA_Claude_Code_Implementation_Spec.md (2026-08-07) - that spec's reference
# implementation (build_combined.js) used Node.js + the docx npm package,
# which isn't installed in this environment; ported to python-docx instead
# (already available here), replicating the same layout/colour scheme/
# conditional logic, not a pixel-identical clone of the JS output.
#
# Several of the spec's "known data gaps" (Section 7) are already resolved by
# work done earlier this project:
#   - Backup GPS points (Tier 2 start) - idp_camp_backup_points.csv, all 83
#     in-camp clusters now have one (was "not in current CSV export" in spec).
#   - Real maps - output/maps/lga_summary/ (LGA-level, not per-cluster hex
#     polygons, but real basemap-adjacent context, not a schematic mockup).
#   - Host-community priority-supervision flag - idp_host_community_
#     feasibility_flags.csv, combined_flag_both_p95_200 (the 18-site list).
# Still genuinely unresolved (left as spec'd placeholders):
#   - Individual field-coordinator assignment (partner ORG is known and
#     filled in; no per-person roster exists).
# ==============================================================================
import csv
import os
import re
import shutil
from collections import defaultdict

from PIL import Image
from docx import Document
from docx.shared import Pt, RGBColor, Cm, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
STAGE2_CSV = PROJECT_DIR + r"\output\data\data_collection\NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"
BACKUP_POINTS_CSV = PROJECT_DIR + r"\output\data\data_collection\idp_camp_backup_points.csv"
HOST_FEASIBILITY_CSV = PROJECT_DIR + r"\output\data\supporting_analysis\idp_host_feasibility\idp_host_community_feasibility_flags.csv"
POI_NEAREST_CSV = PROJECT_DIR + r"\output\data\supporting_analysis\poi\poi_nearest_non_idp.csv"
POI_DISTANCE_CUTOFF_M = 5000
STRATA_CSV = PROJECT_DIR + r"\_archive\2026-08-06_design_frame_post_nw_targeted_resample\strata_level_sampling_frame.csv"
COVERAGE_XLSX = PROJECT_DIR + r"\input_data\boundaries\partner_coverage\Partnerscoverage.xlsx"
CLUSTER_VECTOR_MAPS_DIR = PROJECT_DIR + r"\output\maps\cluster_vector"
DIAGRAM_PATH = PROJECT_DIR + r"\output\maps\cluster_diagram_v2.png"
GPS_TOLERANCE_DIAGRAM_PATH = PROJECT_DIR + r"\output\maps\gps_tolerance_diagram.png"
# 2026-08-12 design-iteration map folders (see build_cluster_map_examples.R)
# - used only for the 4-example review build, not the production batch,
# until the new template is approved.
EXAMPLE_CLUSTER_MAPS_DIR = PROJECT_DIR + r"\output\maps\cluster_map_examples_v3"
LGA_CONTEXT_MAPS_DIR = PROJECT_DIR + r"\output\maps\cluster_lga_context_v1"
OUT_ROOT = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\3. External coordination\NGA MSNA 2026 Package"
TEMP_DIR = PROJECT_DIR + r"\output\cluster_factsheets_tmp"

if os.path.exists(r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"):
    COVERAGE_XLSX = r"C:\Users\JACKPH~1\AppData\Local\Temp\claude\Partnerscoverage_copy.xlsx"

NAVY = "1F3864"
GREY = "666666"
DARKGREY = "333333"
NONIDP = "1F3864"
CAMP = "B45309"
HOSTCOMM = "6B2FA3"
CAUTION_BG = "FDF2F2"
CAUTION_BORDER = "C00000"
INFO_BG = "EAF1F8"
INFO_BORDER = "2E75B6"
PLACEHOLDER_GREY = "8A8A8A"
WHITE = "FFFFFF"


# ---------------------------------------------------------------------------
# python-docx low-level helpers (shading/borders aren't exposed at the
# high-level API - same oxml pattern used throughout this kind of work)
# ---------------------------------------------------------------------------
def shade_cell(cell, hex_color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def border_cell(cell, color, sz=8):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), str(sz))
        el.set(qn("w:color"), color)
        borders.append(el)
    tcPr.append(borders)


def no_border_cell(cell):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "nil")
        borders.append(el)
    tcPr.append(borders)


def set_cell_margins(cell, top=60, bottom=60, left=100, right=100):
    tcPr = cell._tc.get_or_add_tcPr()
    mar = OxmlElement("w:tcMar")
    for edge, val in (("top", top), ("bottom", bottom), ("left", left), ("right", right)):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:w"), str(val))
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    tcPr.append(mar)


def add_run(p, text, size=11, color=DARKGREY, bold=False, italic=False):
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.font.color.rgb = RGBColor.from_string(color)
    r.font.bold = bold
    r.font.italic = italic
    return r


def box(doc, lines_fn, bg, border, margin=(60, 60, 100, 100)):
    """A single-cell full-width shaded/bordered box, content built by lines_fn(cell)."""
    tbl = doc.add_table(rows=1, cols=1)
    tbl.autofit = True
    cell = tbl.cell(0, 0)
    shade_cell(cell, bg)
    border_cell(cell, border)
    set_cell_margins(cell, *margin)
    cell.paragraphs[0].text = ""
    lines_fn(cell)
    # A python-docx table cell always starts with one empty paragraph; if
    # lines_fn's first call added a new paragraph (heading()/add_paragraph())
    # rather than writing into that existing one, the empty one is left
    # sitting above the real content as a stray blank line (2026-08-12
    # feedback, seen above the LOCATION/YOUR TASK headings).
    if len(cell.paragraphs) > 1 and cell.paragraphs[0].text == "":
        p0 = cell.paragraphs[0]._element
        p0.getparent().remove(p0)
    return tbl


def heading(cell_or_doc, text, color=NAVY, size=12):
    p = cell_or_doc.add_paragraph()
    add_run(p, text, size=size, color=color, bold=True)
    return p


def kv_line(cell, label, value, placeholder=False):
    p = cell.add_paragraph()
    add_run(p, f"{label}: ", size=10, color=DARKGREY, bold=True)
    add_run(p, value, size=10, color=PLACEHOLDER_GREY if placeholder else DARKGREY, italic=placeholder)
    return p


def kv_row(cell, pairs):
    """Multiple label/value pairs on a single line - pairs = [(label, value, placeholder), ...]."""
    p = cell.add_paragraph()
    for i, (label, value, placeholder) in enumerate(pairs):
        if i > 0:
            add_run(p, "     ", size=10)
        add_run(p, f"{label}: ", size=10, color=DARKGREY, bold=True)
        add_run(p, value, size=10, color=PLACEHOLDER_GREY if placeholder else DARKGREY, italic=placeholder)
    return p


def bullet(cell, text, size=9.5, color=DARKGREY):
    p = cell.add_paragraph(style="List Bullet")
    add_run(p, text, size=size, color=color)
    return p


def numbered(cell, items):
    for t in items:
        p = cell.add_paragraph(style="List Number")
        add_run(p, t, size=10, color=DARKGREY)


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
def norm(s):
    if s is None:
        return ""
    s = str(s).strip().lower()
    s = s.replace("/", " ").replace("-", " ")
    s = re.sub(r"[\'\u2018\u2019\u02bc\ufffd]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def load_partner_lga_map():
    with open(STRATA_CSV, encoding="utf-8") as f:
        strata_rows = list(csv.DictReader(f))
    master_lgas = {}
    for r in strata_rows:
        master_lgas[r["adm2_pcode"]] = {"adm1_name": r["adm1_name"], "adm2_name": r["adm2_name"]}
    lga_index = {}
    for pcode, v in master_lgas.items():
        lga_index[(norm(v["adm1_name"]), norm(v["adm2_name"]))] = pcode

    PROPOSED_RECONCILIATION = {
        ("Zamfara", "Birnin Magaji/Kiyaw"): "NG037003", ("Zamfara", "Kauran Namoda"): "NG037008",
        ("Kaduna", "Makarfi"): "NG019018", ("Kaduna", "Zangon-Kataf"): "NG019022",
        ("Kebbi", "Wasagu"): "NG022019", ("Benue", "Otukpo"): "NG007019",
        ("Kogi", "Olamaboro"): "NG023018", ("Nasarawa", "Eggon"): "NG026010",
        ("Niger", "Munya"): "NG027018", ("Plateau", "Barkin Ladi"): "NG032001",
    }
    # "IRC/LHI" is a single column in the source sheet, but IRC and LHI are
    # two separate organisations (confirmed with the user 2026-08-07) - see
    # the matching constant/comment in build_partner_dc_packages.py for the
    # full reasoning. Keep both scripts' partner-name handling in sync.
    COMBINED_PARTNER_SPLITS = {
        "IRC/LHI": ["IRC", "LHI"],
    }
    IN_SCOPE_STATES = {"Adamawa", "Borno", "Yobe", "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto",
                        "Zamfara", "Benue", "Kogi", "Nasarawa", "Niger", "Plateau"}

    import openpyxl
    wb = openpyxl.load_workbook(COVERAGE_XLSX, data_only=True)
    partners_by_pcode = defaultdict(set)
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        rows = list(ws.iter_rows(values_only=True))
        header = rows[0]
        count_idx = header.index("COUNT")
        partner_col_idx = list(range(3, count_idx))
        for r in rows[1:]:
            if r[2] is None:
                continue
            state = str(r[1]).strip() if r[1] else None
            lga = str(r[2]).strip() if r[2] else None
            if state not in IN_SCOPE_STATES:
                continue
            partners_here = [str(header[i]).strip() for i in partner_col_idx if r[i]]
            if not partners_here:
                continue
            key = (norm(state), norm(lga))
            pcode = lga_index.get(key) or PROPOSED_RECONCILIATION.get((state, lga))
            if pcode is None:
                continue
            for p in partners_here:
                for expanded in COMBINED_PARTNER_SPLITS.get(p, [p]):
                    partners_by_pcode[pcode].add(expanded)
    return partners_by_pcode, master_lgas


def safe_folder_name(s):
    return re.sub(r'[<>:"/\\|?*]', "-", s).strip()


print("Loading data...")
with open(STAGE2_CSV, encoding="utf-8") as f:
    frame_rows = list(csv.DictReader(f))
print(f"  {len(frame_rows)} household-level rows")

with open(BACKUP_POINTS_CSV, encoding="utf-8") as f:
    backup_rows = list(csv.DictReader(f))
backup_by_cluster = {r["site_id"]: r for r in backup_rows if r["backup_gps_lat"] not in (None, "", "NA")}
print(f"  {len(backup_by_cluster)} in-camp clusters with a Tier 2 backup point")

with open(HOST_FEASIBILITY_CSV, encoding="utf-8") as f:
    host_flag_rows = list(csv.DictReader(f))
priority_host_clusters = {r["cluster_id"] for r in host_flag_rows if r.get("combined_flag_both_p95_200") == "TRUE"}
print(f"  {len(priority_host_clusters)} host-community clusters flagged for priority supervision "
      f"(note: keyed to the original design's cluster_ids - the 2026-08-06 NW targeted resample changed "
      f"cluster_ids for 24 LGAs, so this flag may under-match there; not recomputed - low volume, host-community "
      f"only, flagged here for awareness)")

partners_by_pcode, master_lgas = load_partner_lga_map()
print(f"  Partner coverage resolved for {len(partners_by_pcode)} LGAs")

poi_by_cluster = {}
if os.path.exists(POI_NEAREST_CSV):
    with open(POI_NEAREST_CSV, encoding="utf-8") as f:
        poi_by_cluster = {r["cluster_id"]: r for r in csv.DictReader(f)}
print(f"  {len(poi_by_cluster)} Non-IDP clusters with a nearest-POI lookup")


def _load_poi_legend(maps_dir):
    """POI number/name/ward rows, grouped by cluster_id - written alongside
    the map PNGs by build_cluster_map_examples.R (_poi_legend.csv). One
    file per map type (cluster-level vs LGA-context) since each numbers
    its own POIs independently."""
    path = os.path.join(maps_dir, "_poi_legend.csv")
    out = defaultdict(list)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                out[r["cluster_id"]].append(r)
    return out


poi_legend_cluster_map = _load_poi_legend(EXAMPLE_CLUSTER_MAPS_DIR)
poi_legend_lga_map = _load_poi_legend(LGA_CONTEXT_MAPS_DIR)
print(f"  POI legend tables: {len(poi_legend_cluster_map)} cluster maps, {len(poi_legend_lga_map)} LGA maps")

clusters = defaultdict(list)
for r in frame_rows:
    clusters[r["cluster_id"]].append(r)
print(f"  {len(clusters)} distinct clusters")

os.makedirs(TEMP_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Per-cluster page builder
# ---------------------------------------------------------------------------
def badge_header(doc, badge_text, badge_color, cluster_id):
    tbl = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    shade_cell(cell, badge_color)
    no_border_cell(cell)
    set_cell_margins(cell, 100, 100, 150, 150)
    p = cell.paragraphs[0]
    add_run(p, badge_text, size=14, color=WHITE, bold=True)
    add_run(p, "      Cluster ID:  ", size=11, color=WHITE)
    add_run(p, cluster_id, size=11, color=WHITE, bold=True)


def assignment_line(doc, partner_names):
    p = doc.add_paragraph()
    add_run(p, "Partner organisation: ", size=10, color=DARKGREY, bold=True)
    add_run(p, ", ".join(partner_names) if partner_names else "[not assigned]", size=10,
            color=DARKGREY if partner_names else PLACEHOLDER_GREY, italic=not partner_names)


def two_col(doc, left_fn, right_fn, left_width=Cm(9.0), right_width=Cm(8.0)):
    tbl = doc.add_table(rows=1, cols=2)
    tbl.autofit = False
    left, right = tbl.cell(0, 0), tbl.cell(0, 1)
    left.width = left_width
    right.width = right_width
    for c in (left, right):
        no_border_cell(c)
        set_cell_margins(c, 0, 0, 0, 0)
    left_fn(left)
    right_fn(right)
    return tbl


def three_col(doc, col_fns, col_width=Cm(5.9)):
    tbl = doc.add_table(rows=1, cols=len(col_fns))
    tbl.autofit = False
    for i, fn in enumerate(col_fns):
        cell = tbl.cell(0, i)
        cell.width = col_width
        no_border_cell(cell)
        set_cell_margins(cell, 0, 0, 0 if i == 0 else 100, 0 if i == len(col_fns) - 1 else 100)
        fn(cell)
    return tbl


def col_header(cell, text, color):
    p = cell.add_paragraph()
    add_run(p, text, size=12, color=color, bold=True)
    return p


def location_block(cell, r, pop_type, idp_cat, backup_row, poi_row=None):
    heading(cell, "LOCATION")
    ward = r.get("iom_site_ward") if pop_type == "idp" and r.get("iom_site_ward") not in (None, "", "NA") else r.get("adm3_name", "")
    kv_row(cell, [
        ("Region", r.get("region", ""), False),
        ("State", r.get("adm1_name", ""), False),
        ("LGA", r.get("adm2_name", ""), False),
        ("Ward*", ward or "", False),
    ])
    p_ward_note = cell.add_paragraph()
    add_run(p_ward_note, "*Ward is approximate, for orientation only - your GPS point is anchored to the LGA, not the ward boundary. Don't second-guess your location based on the ward name.",
            size=8, color=GREY, italic=True)
    if pop_type == "idp":
        site_name = r.get("iom_site_name", "")
        site_id = r.get("iom_site_id", "")
        kv_line(cell, "Site name", f"{site_name} ({site_id})" if site_id and site_id != "NA" else site_name)
        gps_pairs = [("DTM GPS point (Tier 1 start)", f"{r['latitude']}, {r['longitude']}", False)]
        if idp_cat == "idps in camp":
            if backup_row is not None:
                gps_pairs.append(("Backup GPS point (Tier 2 start only)",
                                   f"{backup_row['backup_gps_lat']}, {backup_row['backup_gps_lon']}", False))
            else:
                gps_pairs.append(("Backup GPS point (Tier 2 start only)", "not available for this cluster", True))
        kv_row(cell, gps_pairs)
    else:
        kv_line(cell, "Anchor GPS point", f"{r['latitude']}, {r['longitude']}")
        p = cell.add_paragraph()
        add_run(p, "For orientation only - not a household location. Building pins are pre-loaded in your Maps.me app (Google Maps as backup).", size=8.5, color=GREY, italic=True)
        if poi_row is not None:
            try:
                dist_m = float(poi_row.get("nearest_poi_dist_m", ""))
            except (TypeError, ValueError):
                dist_m = None
            if dist_m is not None and dist_m <= POI_DISTANCE_CUTOFF_M:
                dist_txt = f"{dist_m/1000:.1f}km" if dist_m >= 1000 else f"{dist_m:.0f}m"
                name_note = "" if poi_row.get("nearest_poi_has_name") == "TRUE" else " (name not recorded - shown as the place type)"
                kv_line(cell, "Nearest known landmark", f"{poi_row.get('nearest_poi_name', '')}, about {dist_txt} away{name_note}")
            else:
                p_poi = cell.add_paragraph()
                add_run(p_poi, "No notable landmark on record within 5km of this cluster.", size=8.5, color=GREY, italic=True)


# Maps now come from build_cluster_map_examples.R's compute_panel_dims(),
# which sizes each PNG's own aspect ratio to fill the frame (fixing the
# 2026-08-12 letterboxing complaint) - but that means aspect ratio varies
# per cluster/LGA (a tall/narrow LGA like Ngaski renders a tall PNG). Fixing
# the docx embed width alone (as before) let a tall PNG's rendered height
# exceed a single page, which broke the heading/image/caption keep_with_next
# group anyway since the group no longer fit on one page at all (2026-08-12
# feedback). fit_picture() caps height too, trading width for height on
# tall images so every map's group reliably fits on one page.
def fit_picture(cell_or_doc, path, max_width_cm, max_height_cm):
    p = cell_or_doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if not os.path.exists(path):
        return p
    with Image.open(path) as im:
        w_px, h_px = im.size
    aspect = h_px / w_px
    width_cm, height_cm = max_width_cm, max_width_cm * aspect
    if height_cm > max_height_cm:
        height_cm = max_height_cm
        width_cm = height_cm / aspect
    p.add_run().add_picture(path, width=Cm(width_cm), height=Cm(height_cm))
    return p


def poi_legend_table(doc_or_cell, rows):
    """Numbered-marker -> name/category/ward lookup table, printed directly
    under a map whenever it has POIs on it (2026-08-13 - replaces the
    earlier on-map name labels, which competed with ward labels/each other
    and were mostly unreadable in busy areas). Row height tightened via
    both cell margins AND paragraph spacing - margins alone still left
    Word's default paragraph spacing padding every row out."""
    if not rows:
        return
    rows_sorted = sorted(rows, key=lambda r: int(r.get("poi_number") or 0))

    def _tight(paragraph):
        paragraph.paragraph_format.space_before = Pt(0)
        paragraph.paragraph_format.space_after = Pt(0)
        paragraph.paragraph_format.line_spacing = 1.0

    tbl = doc_or_cell.add_table(rows=1 + len(rows_sorted), cols=4)
    tbl.autofit = True
    for j, h in enumerate(["POI #", "POI Name (OSM)", "Category", "Ward (GRID3)"]):
        cell = tbl.cell(0, j)
        shade_cell(cell, "EFEFEF")
        border_cell(cell, "AAAAAA", sz=4)
        set_cell_margins(cell, 15, 15, 60, 60)
        _tight(cell.paragraphs[0])
        add_run(cell.paragraphs[0], h, size=8, color=DARKGREY, bold=True)
    for i, r in enumerate(rows_sorted, start=1):
        vals = [r.get("poi_number", ""), r.get("poi_name", ""), r.get("poi_category", ""), r.get("poi_ward", "")]
        for j, v in enumerate(vals):
            cell = tbl.cell(i, j)
            border_cell(cell, "CCCCCC", sz=4)
            set_cell_margins(cell, 10, 10, 60, 60)
            _tight(cell.paragraphs[0])
            add_run(cell.paragraphs[0], str(v), size=8, color=DARKGREY)
    note = doc_or_cell.add_paragraph()
    add_run(note, "Points of interest: OpenStreetMap/HOTOSM. Some names aren't recorded on OSM and are shown as the general place type instead.",
            size=8, color=GREY, italic=True)


def map_block(cell_or_doc, pcode, lga_name, cluster_id, maps_dir=CLUSTER_VECTOR_MAPS_DIR, max_width_cm=16.5, max_height_cm=21.0):
    path = os.path.join(maps_dir, f"{cluster_id}.png")
    p = fit_picture(cell_or_doc, path, max_width_cm, max_height_cm)
    p.paragraph_format.keep_with_next = True
    cap = cell_or_doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(cap, "Shows the hexagon/point layout, roads, and buildings for this cluster - your close-up, exact-navigation "
                 "reference. See the LGA map above for wider orientation. Use the KML points for exact navigation, not this image.",
            size=8, color=GREY, italic=True)
    poi_legend_table(cell_or_doc, poi_legend_cluster_map.get(cluster_id, []))


def lga_map_block(doc, cluster_id, adm2_name):
    h = heading(doc, f"LGA MAP - {adm2_name}", NAVY, size=14)
    h.paragraph_format.keep_with_next = True
    p_note = doc.add_paragraph()
    add_run(p_note, "For wider orientation only - not for exact navigation. Use the cluster map below for that.",
            size=9, color=GREY, italic=True)
    p_note.paragraph_format.keep_with_next = True
    path = os.path.join(LGA_CONTEXT_MAPS_DIR, f"{cluster_id}.png")
    fit_picture(doc, path, max_width_cm=15.5, max_height_cm=21.0)
    poi_legend_table(doc, poi_legend_lga_map.get(cluster_id, []))


def task_block(doc, pop_type, idp_cat, actual_primary_n, actual_reserve_n):
    def content(cell):
        heading(cell, "YOUR TASK")
        if pop_type == "non_idp":
            numbered(cell, [
                "Households were pre-selected from satellite building footprints at desk stage.",
                "Open Maps.me (Google Maps as backup) and navigate to each pre-loaded pin.",
                "Interview the household AT the pin - never substitute a different building.",
                "Primary unreachable? Use reserve pins in ranked order (see the general Field Guide for replacement rules).",
            ])
        elif idp_cat == "idps in camp":
            p = cell.add_paragraph(); add_run(p, "TIER 1 - do this first, always starting at the DTM point above:", size=10, bold=True)
            numbered(cell, [
                "Find the site's head of area (camp lead/warden).",
                "Ask for a full list of households they recognise as being at this site - bounded by their knowledge, not a fixed distance.",
                "Enter the list into Kobo - the tool auto-selects your primary + reserve households.",
            ])
            p2 = cell.add_paragraph(); add_run(p2, "TIER 2 - fallback, only if a full listing genuinely isn't feasible:", size=10, bold=True)
            numbered(cell, [
                "Start from the BACKUP GPS point above (not the DTM point) and use the random-walk method: pre-assigned bearing, every n-th household - see the general Field Guide for the full procedure.",
            ])
        else:  # idps in host
            numbered(cell, [
                "Find the site's head of area (chief or head of settlement).",
                "Ask for a full list of households they recognise as belonging to the displaced population of this settlement - bounded by their local knowledge, not a fixed distance.",
                "Multiple distinct named areas? Get a separate list from a contact in EACH area, then pool all lists together.",
                "Before selecting, explicitly ask whether any displaced households are missing from the list.",
                "Enter the pooled list into Kobo - the tool auto-selects your primary + reserve households.",
            ])
        kv_line(cell, "Target households (primary)", str(actual_primary_n))
        kv_line(cell, "Reserve households", str(actual_reserve_n))
    box(doc, content, WHITE, "D9D9D9")


def flag_boxes(doc, r, pop_type, idp_cat, selection_count, n_other_sites, below_target, is_priority_host,
               actual_primary_n, actual_reserve_n):
    if selection_count > 1:
        def content(cell):
            heading(cell, "MULTIPLE DRAWS COMBINED" + (" + OTHER SITE NEARBY" if n_other_sites > 0 else ""), color=INFO_BORDER, size=11)
            txt = (f"{selection_count} separate selections of the same grid cell combined into this one cluster - "
                   f"target is {actual_primary_n}, not the usual 6; build one combined list. Reserve list is "
                   f"also {actual_reserve_n} (matches target - reserve now scales 1:1 with target for combined-draw clusters).")
            if n_other_sites > 0:
                txt += f" {n_other_sites} other IDP site(s) also fall in this hex - not part of your sample unless your FO says otherwise."
            p = cell.add_paragraph(); add_run(p, txt, size=9.5)
        box(doc, content, INFO_BG, INFO_BORDER)
    elif n_other_sites > 0:
        def content(cell):
            heading(cell, "OTHER SITE NEARBY", color=INFO_BORDER, size=11)
            p = cell.add_paragraph()
            add_run(p, f"{n_other_sites} other IDP site(s) also fall in this hex - not part of your sample unless your FO says otherwise.", size=9.5)
        box(doc, content, INFO_BG, INFO_BORDER)

    if below_target and pop_type == "non_idp":
        def content(cell):
            heading(cell, "BELOW-TARGET CLUSTER", color=CAUTION_BORDER, size=11)
            p = cell.add_paragraph()
            # actual_primary_n (real achieved rows), not the CSV's nominal target_households
            # column, which stays at the standard m=6 even when capped - using that column
            # here previously printed "Only 6 eligible building(s)..." on clusters that only
            # actually had 1-5, directly contradicting the interview log grid on the same page.
            add_run(p, f"Only {actual_primary_n} eligible building(s) were identified here at desk stage - fewer than the "
                        f"standard target. This cluster's sample is capped at what's genuinely available. Do not add extra, "
                        f"unlisted households to reach a higher target - interview what's listed and move on.", size=9.5)
        box(doc, content, CAUTION_BG, CAUTION_BORDER)

    # A distinct case from BELOW-TARGET above: primary hit its full target, but the eligible
    # building pool ran out before reserve could scale 1:1 with it (Non-IDP reserve is capped
    # by pool availability same as primary; IDP reserve is never capped, so this is Non-IDP only
    # - see reserve_households capping rule). Without this box, a cluster with zero reserve but
    # a full primary list showed no warning anywhere on the page.
    if pop_type == "non_idp" and not below_target and actual_reserve_n < actual_primary_n:
        def content(cell):
            heading(cell, "REDUCED RESERVE LIST", color=CAUTION_BORDER, size=11)
            if actual_reserve_n == 0:
                msg = ("The eligible building pool for this cluster was fully used by the primary list - there are "
                       "NO reserve households. If a primary household is unreachable or declines, there is no "
                       "replacement; note it on the interview log and move on.")
            else:
                msg = (f"The eligible building pool for this cluster only supports {actual_reserve_n} reserve "
                       f"household(s), fewer than the usual {actual_primary_n}. Use them in rank order as normal - "
                       f"once exhausted, there is no further replacement.")
            p = cell.add_paragraph(); add_run(p, msg, size=9.5)
        box(doc, content, CAUTION_BG, CAUTION_BORDER)

    if is_priority_host:
        def content(cell):
            heading(cell, "PRIORITY SUPERVISION SITE", color=CAUTION_BORDER, size=11)
            p = cell.add_paragraph()
            add_run(p, "This host-community site is flagged for closer field-coordinator oversight (high population density "
                        "and caseload) - prepare a larger reserve list and check in with your FO more closely during this cluster.", size=9.5)
        box(doc, content, CAUTION_BG, CAUTION_BORDER)


def interview_log_grid(doc, primary_labels, reserve_labels, cluster_id):
    def content(cell):
        heading(cell, "HOUSEHOLD INTERVIEW LOG")
        example_short = (primary_labels[0] if primary_labels else (reserve_labels[0] if reserve_labels else "HH01"))
        p = cell.add_paragraph()
        add_run(p, "IDs below are short form. Full KoBo survey ID = ", size=8.5, italic=True, color=GREY)
        add_run(p, f"{cluster_id}_{example_short}", size=8.5, italic=True, bold=True)
        add_run(p, f'  (i.e. "{example_short}" in this log = the last part of that ID).', size=8.5, italic=True, color=GREY)
        p2 = cell.add_paragraph()
        add_run(p2, "Mark each: check=interviewed  R=replaced  X=refused  V=vacant/no household - write the code after the colon.", size=8.5, italic=True, color=GREY)

        def grid(labels, title):
            if not labels:
                p3 = cell.add_paragraph()
                add_run(p3, "No reserve households available for this cluster (see flag box above).", size=8.5, italic=True, color=GREY)
                return
            th = cell.add_paragraph()
            add_run(th, f"{title} ({len(labels)})", size=9, bold=True)
            per_row = 10
            n_rows = -(-len(labels) // per_row)
            tbl = cell.add_table(rows=n_rows, cols=per_row)
            tbl.autofit = True
            for i, lab in enumerate(labels):
                rr, cc = divmod(i, per_row)
                tc = tbl.cell(rr, cc)
                border_cell(tc, "CCCCCC", sz=4)
                set_cell_margins(tc, 40, 40, 40, 40)
                tp = tc.paragraphs[0]
                add_run(tp, f"[] {lab}: __", size=8)
            for i in range(len(labels), n_rows * per_row):
                rr, cc = divmod(i, per_row)
                border_cell(tbl.cell(rr, cc), "CCCCCC", sz=4)

        grid(primary_labels, "PRIMARY")
        grid(reserve_labels, "RESERVE - use in order")

    box(doc, content, WHITE, "BFBFBF")


def notes_box(doc):
    def content(cell):
        heading(cell, "CLUSTER NOTES")
        p1 = cell.add_paragraph(); add_run(p1, "Date visited: _______________     Team leader: _______________________________", size=9.5)
        p2 = cell.add_paragraph(); add_run(p2, "Access/safety issues: __________________________________________________________", size=9.5)
    box(doc, content, "F7F7F7", "AAAAAA")


def footer(doc, source_note):
    if not source_note:
        return
    p = doc.add_paragraph()
    add_run(p, source_note, size=8.5, italic=True, color=GREY)


def build_general_guide_page(doc):
    """Static general field guide - identical on every cluster's factsheet
    (page 1). Ported verbatim from build_combined.js's page0 content, per
    the user's 2026-08-07 instruction that every factsheet is 2+ standalone
    pages: page 1 = this shared overview, page 2(+) = the cluster-specific
    content."""
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(title, "MSNA 2026 - Field Guide: Finding Your Cluster & Selecting Households", size=16, color=NAVY, bold=True)

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(subtitle, "For enumerators & team leaders - keep with you during data collection", size=9.5, color="555555", italic=True)

    def before_you_start(cell):
        p = cell.add_paragraph()
        add_run(p, "BEFORE YOU START:  ", size=10, color=NAVY, bold=True)
        add_run(p, "Check your assignment sheet / Kobo form - every cluster is labelled NON-IDP, IDP - IN-CAMP, or "
                    "IDP - HOST-COMMUNITY. This decides everything below, so check it first.", size=10, color="222222")
        p2 = cell.add_paragraph()
        add_run(p2, "The Ward shown on your cluster page is approximate, for orientation only - your GPS point is anchored "
                     "to the LGA, not the ward boundary. Don't second-guess your location based on the ward name.",
                size=10, color="222222")
    box(doc, before_you_start, INFO_BG, INFO_BORDER)

    if os.path.exists(DIAGRAM_PATH):
        img_p = doc.add_paragraph()
        img_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        img_p.add_run().add_picture(DIAGRAM_PATH, width=Cm(17.5))

    def nonidp_col(cell):
        col_header(cell, "NON-IDP cluster", NONIDP)
        p = cell.add_paragraph(); add_run(p, "HH GPS already selected", size=8.5, color=GREY, italic=True)
        for t in [
            "Open Maps.me (Google Maps as backup) and navigate to primary pins H1-H6",
            "Household not exactly at the pin? See the GPS Point Offset rule below - within 150m, "
            "use the nearest building; never substitute a different one just because it's more convenient",
            "Unreachable? Move to reserve pins R1, R2... in order (see rules below)",
        ]:
            bullet(cell, t)

    def camp_col(cell):
        col_header(cell, "IDP - in-camp", CAMP)
        p = cell.add_paragraph(); add_run(p, "head of area, listing", size=8.5, color=GREY, italic=True)
        for t in [
            "Find the site's head of area (camp lead/warden)",
            "Ask for a full list of households they recognise as being at this site - bounded by their knowledge, not a fixed distance",
            "Enter the list into Kobo - it auto-selects primary + reserve",
            "Not possible? Fallback: random-walk from the backup GPS point, pre-assigned bearing, every n-th HH",
        ]:
            bullet(cell, t)
        warn_p = cell.add_paragraph()
        add_run(warn_p, "Full household listing is mandatory - if it isn't done (Tier 1 or Tier 2 fallback), this "
                         "cluster's data cannot be accepted.", size=9, color=CAUTION_BORDER, bold=True)

    def host_col(cell):
        col_header(cell, "IDP - host-community", HOSTCOMM)
        p = cell.add_paragraph(); add_run(p, "head of area, listing", size=8.5, color=GREY, italic=True)
        for t in [
            "Find the site's head of area (chief/head of settlement)",
            "Ask for a full list of displaced HHs they recognise - bounded by local knowledge, not distance",
            "Multiple named areas? List each separately, then pool together",
            "Enter pooled list into Kobo - auto-selects primary + reserve",
        ]:
            bullet(cell, t)
        warn_p = cell.add_paragraph()
        add_run(warn_p, "No Tier 2 fallback exists for host-community - if the listing isn't feasible, do NOT switch "
                         "to the in-camp random-walk method. Flag it to your FO instead.", size=9, color=CAUTION_BORDER, bold=True)
        warn_p2 = cell.add_paragraph()
        add_run(warn_p2, "Full household listing is mandatory - if it isn't done, this cluster's data cannot be accepted.",
                size=9, color=CAUTION_BORDER, bold=True)

    three_col(doc, [nonidp_col, camp_col, host_col])

    # Forced page break (2026-08-13 feedback) so the general guide reliably
    # spans exactly 2 pages - page 1 ends with the task columns above, page
    # 2 opens cleanly with GPS offset/replacement rules/call-FO, rather than
    # letting that content split wherever it happened to overflow.
    doc.add_page_break()

    def gps_offset_rule(cell):
        heading(cell, "ACCEPTED RANGE OF GPS OFFSET - NON-IDP CLUSTERS ONLY", NAVY)
        p = cell.add_paragraph()
        add_run(p, "Sometimes the household isn't exactly at the pin - this is normal (GPS drift, minor "
                     "mapping error). How far off it is decides what to do:", size=9.5, color="222222")

        def diagram_col(c):
            if os.path.exists(GPS_TOLERANCE_DIAGRAM_PATH):
                img_p = c.add_paragraph()
                img_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                img_p.add_run().add_picture(GPS_TOLERANCE_DIAGRAM_PATH, width=Cm(11.0))

        def text_col(c):
            for t in [
                "0-50m: interview the nearest building. No flag, nothing to report.",
                "50-150m: interview the nearest building. This is still your household, but it gets flagged "
                "and monitored - carry on, no action needed from you beyond that.",
                "Beyond 150m: this is no longer the same household sample point. Do not interview here - "
                "treat it exactly like “vacant / doesn't exist” and move to your next reserve household.",
            ]:
                bullet(c, t, color="222222")
            p2 = c.add_paragraph()
            add_run(p2, "In every case: always the SINGLE nearest building to the pin - never a different "
                         "one you'd rather visit, and never a household outside the ranked reserve list.",
                    size=9.5, color=CAUTION_BORDER, bold=True)

        two_col(cell, diagram_col, text_col, left_width=Cm(11.3), right_width=Cm(7.0))
    box(doc, gps_offset_rule, WHITE, "D9D9D9")

    def replacement_rules(cell):
        heading(cell, "REPLACEMENT RULES - applies to ALL cluster types", CAUTION_BORDER)
        for t in [
            "Visit each primary/reserve household up to 2 times (different times of day) before replacing it",
            "Replace immediately, no revisit needed, if: vacant / doesn't exist / refuses / unsafe to access",
            "Always move to the NEXT household on your ranked reserve list - never pick a nearby house yourself. "
            "Non-IDP: reserves are pre-loaded in your app. IDP: reserves are auto-ranked by Kobo once your list is entered.",
            "Report the reason for every replacement to your team leader/FO at your daily debrief",
        ]:
            bullet(cell, t, color="222222")
        p = cell.add_paragraph()
        add_run(p, "Reserve list exhausted before reaching target? STOP - do not sample outside the list. Flag it to your FO.",
                size=10, color=DARKGREY, bold=True)
        p2 = cell.add_paragraph()
        add_run(p2, "Reserves are a backup only, not a free substitute list - using them beyond the replacement rules above "
                     "requires prior approval from your FACT/IMPACT focal point.",
                size=10, color=DARKGREY, bold=True)
    box(doc, replacement_rules, CAUTION_BG, CAUTION_BORDER)

    def call_fo(cell):
        heading(cell, "CALL YOUR FIELD OFFICER IF:", NAVY)
        for t in [
            "Your reserve list runs out",
            "The site/hexagon looks very different from the map (site moved, area inaccessible, another site nearby that isn't yours, etc.)",
            "Target population not found within site/hexagon",
            "Any safety concern, at any point",
        ]:
            bullet(cell, t, color="222222")
    box(doc, call_fo, INFO_BG, INFO_BORDER)

    # Local-language-versions line removed 2026-08-13 - no translated
    # version of this guide is confirmed to exist, so the line was
    # misleading. "MSNA Nigeria 2026 - Field Guide..." line moved to a
    # real running page footer (set_page_setup()) - see same feedback.


def set_page_setup(doc):
    section = doc.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(1.0)
    section.bottom_margin = Cm(1.0)
    section.left_margin = Cm(1.2)
    section.right_margin = Cm(1.2)
    # Real running footer (2026-08-13 feedback) - was a floating paragraph
    # at the end of the general guide page, only visible once; a proper
    # section footer repeats it on every page instead.
    footer_p = section.footer.paragraphs[0]
    footer_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(footer_p, "MSNA Nigeria 2026 - Field Guide & Cluster Sheets - IMPACT Initiatives / FACT Foundation",
            size=8, color="666666", italic=True)


# ---------------------------------------------------------------------------
# Per-cluster document assembly
# ---------------------------------------------------------------------------
def build_cluster_doc(cluster_id, rows, maps_dir=CLUSTER_VECTOR_MAPS_DIR, include_lga_map=False):
    r0 = rows[0]
    pop_type = r0["pop_type"]
    idp_cat = r0.get("idp_population_category", "") if pop_type == "idp" else None
    pcode = r0["adm2_pcode"]
    lga_name = r0["adm2_name"]

    selection_count = int(r0["selection_count"])
    below_target = r0.get("below_target_cluster") == "TRUE"
    n_other_sites = 0
    try:
        n_other_sites = int(r0.get("n_other_sites_in_hex", "0"))
    except (TypeError, ValueError):
        n_other_sites = 0
    is_priority_host = cluster_id in priority_host_clusters

    def label_sort_key(s):
        digits = re.sub(r"\D", "", s)
        return int(digits) if digits else 0

    primary_labels = sorted(
        [r["survey_id"].rsplit("_", 1)[-1] for r in rows if r["status"] == "primary"],
        key=label_sort_key,
    )
    reserve_labels = sorted(
        [r["survey_id"].rsplit("_", 1)[-1] for r in rows if r["status"] == "reserve"],
        key=label_sort_key,
    )

    backup_row = backup_by_cluster.get(cluster_id) if (pop_type == "idp" and idp_cat == "idps in camp") else None
    poi_row = poi_by_cluster.get(cluster_id) if pop_type == "non_idp" else None
    partner_names = sorted(partners_by_pcode.get(pcode, []))

    if pop_type == "non_idp":
        badge_text, badge_color = "NON-IDP CLUSTER", NONIDP
    elif idp_cat == "idps in camp":
        badge_text, badge_color = "IDP CLUSTER - IN CAMP", CAMP
    else:
        badge_text, badge_color = "IDP CLUSTER - HOST COMMUNITY", HOSTCOMM

    doc = Document()
    set_page_setup(doc)
    build_general_guide_page(doc)
    doc.add_page_break()
    badge_header(doc, badge_text, badge_color, cluster_id)
    assignment_line(doc, partner_names)

    box(doc, lambda cell: location_block(cell, r0, pop_type, idp_cat, backup_row, poi_row), WHITE, "D9D9D9")

    task_block(doc, pop_type, idp_cat, len(primary_labels), len(reserve_labels))
    flag_boxes(doc, r0, pop_type, idp_cat, selection_count, n_other_sites, below_target, is_priority_host,
               len(primary_labels), len(reserve_labels))
    interview_log_grid(doc, primary_labels, reserve_labels, cluster_id)
    notes_box(doc)

    source_note = (
        "Backup GPS point method: " + backup_row["backup_point_method"] + "."
        if backup_row is not None and "backup_point_method" in backup_row
        else ""
    )
    footer(doc, source_note)

    # Maps ordered largest-extent-first (2026-08-12 feedback): LGA map, then
    # the tighter cluster map - reads as a natural size/extent hierarchy
    # (wide orientation -> exact navigation) rather than the reverse. Both
    # sit inline at the bottom of the doc, no page break between them.
    if include_lga_map:
        lga_map_block(doc, cluster_id, lga_name)

    map_heading = heading(doc, f"CLUSTER MAP - {cluster_id}", NAVY, size=14)
    map_heading.paragraph_format.keep_with_next = True
    map_block(doc, pcode, lga_name, cluster_id, maps_dir=maps_dir)

    return doc


def distribute_to_partner_folders(cluster_id, pcode, lga_name, pop_type, tmp_path):
    partner_names = partners_by_pcode.get(pcode, [])
    lga_info = master_lgas.get(pcode, {})
    state_name = lga_info.get("adm1_name", "")
    # LGA folder split by population group since 2026-08-13 - matches
    # build_partner_dc_packages.py's Non_IDP/IDP + KML/Cluster_guide split.
    pop_folder = "Non_IDP" if pop_type == "non_idp" else "IDP"
    n_copied = 0
    for partner in partner_names:
        lga_dir = os.path.join(OUT_ROOT, safe_folder_name(partner), safe_folder_name(state_name), safe_folder_name(lga_name))
        if not os.path.isdir(lga_dir):
            continue
        guide_dir = os.path.join(lga_dir, pop_folder, "Cluster_guide")
        os.makedirs(guide_dir, exist_ok=True)
        dest = os.path.join(guide_dir, f"{cluster_id}_factsheet.docx")
        shutil.copy2(tmp_path, dest)
        n_copied += 1
    return n_copied


# ---------------------------------------------------------------------------
# Main batch run
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print(f"\nBuilding {len(clusters)} cluster factsheets...")
    n_built = 0
    n_no_partner = 0
    n_copied_total = 0
    failed_clusters = []

    for i, (cluster_id, rows) in enumerate(clusters.items()):
        try:
            # Production template finalized 2026-08-12 (design-iterated via
            # the 4-example review in EXAMPLE_CLUSTER_MAPS_DIR/LGA_CONTEXT_MAPS_DIR
            # - see build_cluster_maps_production.R for the full-batch map render
            # these paths point at, now the production source for every cluster).
            doc = build_cluster_doc(cluster_id, rows, maps_dir=EXAMPLE_CLUSTER_MAPS_DIR, include_lga_map=True)
            tmp_path = os.path.join(TEMP_DIR, f"{cluster_id}_factsheet.docx")
            doc.save(tmp_path)

            pcode = rows[0]["adm2_pcode"]
            lga_name = rows[0]["adm2_name"]
            pop_type = rows[0]["pop_type"]
            n_copied = distribute_to_partner_folders(cluster_id, pcode, lga_name, pop_type, tmp_path)
            n_copied_total += n_copied
            if n_copied == 0:
                n_no_partner += 1
            n_built += 1
        except Exception as e:
            failed_clusters.append((cluster_id, str(e)))

        if (i + 1) % 200 == 0:
            print(f"  ... {i + 1}/{len(clusters)} clusters processed")

    print(f"\nDONE. Built: {n_built}  Copied into partner folders: {n_copied_total}  "
          f"Clusters with no matching partner folder: {n_no_partner}  Failed: {len(failed_clusters)}")
    if failed_clusters:
        print("Failed clusters (first 20):")
        for cid, err in failed_clusters[:20]:
            print(f"  {cid}: {err}")
