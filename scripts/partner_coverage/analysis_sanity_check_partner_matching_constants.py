# ==============================================================================
# Added 2026-08-28 (comprehensive-sweep item 7, Option B - see ../../
# resampling/README.md and Jack's own call: keep the duplication as-is for
# now given the resampling push today, but stop it from drifting silently).
#
# IN_SCOPE_STATES, PROPOSED_RECONCILIATION, and COMBINED_PARTNER_SPLITS are
# hand-copied into 5 separate files (4 Python, 1 R) rather than imported from
# one shared module - a deliberate project convention (every script here is
# meant to be runnable standalone, see build_partner_lga_boundary_kml.R's own
# header comment: "duplicated rather than imported, per this project's
# standalone-script convention"). That's fine as long as all 5 copies stay
# identical; this script is the thing that actually checks that, instead of
# relying on someone remembering to update all 5 by hand. Run it any time one
# of the 5 files below is touched, or just periodically.
#
# PROPOSED_RECONCILIATION needs a normalization step before comparing across
# languages: the Python copies key it by the raw (state, lga) tuple as typed
# in the coverage workbook (e.g. ("Zamfara", "Birnin Magaji/Kiyaw")), while
# build_partner_lga_boundary_kml.R's copy pre-normalizes to a single
# "state|lga" string key (e.g. "zamfara|birnin magaji kiyaw") using the same
# norm() every script here applies before matching. Both are semantically the
# same mapping - just written differently - so the Python side is normalized
# the identical way before comparing, rather than treating a representation
# difference as a real mismatch.
# ==============================================================================
import ast
import re
from pathlib import Path

PROJECT_DIR = Path(r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling")

PYTHON_FILES = [
    PROJECT_DIR / "scripts/field_guide_production/build_partner_dc_packages.py",
    PROJECT_DIR / "scripts/field_guide_production/build_cluster_factsheets.py",
    PROJECT_DIR / "scripts/field_guide_production/qa_cluster_factsheets_batch.py",
    PROJECT_DIR / "scripts/partner_coverage/analysis_partner_coverage.py",
]
R_FILE = PROJECT_DIR / "scripts/field_guide_production/build_partner_lga_boundary_kml.R"

CONST_NAMES = ("IN_SCOPE_STATES", "PROPOSED_RECONCILIATION", "COMBINED_PARTNER_SPLITS")


def norm(s):
    if s is None:
        return ""
    s = str(s).strip().lower()
    s = s.replace("/", " ").replace("-", " ")
    s = re.sub(r"[\'\u2018\u2019\u02bc\ufffd]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def extract_python_constants(path):
    """Walks the WHOLE module (not just top-level statements) since some
    files define these constants inside a function, not at module scope -
    ast.literal_eval only needs the source text, not execution, so scope
    doesn't matter here."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in CONST_NAMES:
                found[name] = ast.literal_eval(node.value)
    return found


def extract_r_constants(path):
    src = path.read_text(encoding="utf-8")
    found = {}

    m = re.search(r"IN_SCOPE_STATES\s*<-\s*c\((.*?)\)\s*\n", src, re.DOTALL)
    if m:
        found["IN_SCOPE_STATES"] = set(re.findall(r'"([^"]*)"', m.group(1)))

    m = re.search(r"PROPOSED_RECONCILIATION\s*<-\s*list\((.*?)\)\s*\n", src, re.DOTALL)
    if m:
        found["PROPOSED_RECONCILIATION"] = dict(re.findall(r'"([^"]*)"\s*=\s*"([^"]*)"', m.group(1)))

    m = re.search(r"COMBINED_PARTNER_SPLITS\s*<-\s*list\((.*?)\)\s*\n", src, re.DOTALL)
    if m:
        found["COMBINED_PARTNER_SPLITS"] = {
            key: [v.strip() for v in vals.split(",")]
            for key, vals in re.findall(r'"([^"]*)"\s*=\s*c\(([^)]*)\)', m.group(1))
        }
        found["COMBINED_PARTNER_SPLITS"] = {
            k: [re.sub(r'^"|"$', "", v) for v in vs] for k, vs in found["COMBINED_PARTNER_SPLITS"].items()
        }

    return found


def normalize_reconciliation(d):
    """Python side: {(state, lga): pcode} with raw casing/slashes. R side is
    already {"norm(state)|norm(lga)": pcode}. Converts the Python form to
    the same normalized-string-key form so the two are directly comparable."""
    return {f"{norm(state)}|{norm(lga)}": pcode for (state, lga), pcode in d.items()}


def main():
    py_constants = {f: extract_python_constants(f) for f in PYTHON_FILES}
    r_constants = extract_r_constants(R_FILE)

    fails = []
    all_files = PYTHON_FILES + [R_FILE]

    for const_name in CONST_NAMES:
        print(f"\n--- {const_name} ---")
        values = {}
        for f in PYTHON_FILES:
            v = py_constants[f].get(const_name)
            if v is None:
                fails.append(f"{f.name}: {const_name} not found")
                continue
            values[f.name] = normalize_reconciliation(v) if const_name == "PROPOSED_RECONCILIATION" else v
        r_v = r_constants.get(const_name)
        if r_v is None:
            fails.append(f"{R_FILE.name}: {const_name} not found")
        else:
            values[R_FILE.name] = r_v

        if len(values) < len(all_files):
            print(f"  FAIL: only found in {len(values)} of {len(all_files)} files")
            continue

        reference_name, reference_val = next(iter(values.items()))
        mismatched = [name for name, v in values.items() if v != reference_val]
        if mismatched:
            fails.append(f"{const_name}: {mismatched} differ from {reference_name}")
            print(f"  FAIL: {mismatched} differ from {reference_name}")
            for name in mismatched:
                print(f"    {name}: {values[name]}")
            print(f"    {reference_name} (reference): {reference_val}")
        else:
            print(f"  PASS: identical across all {len(values)} files")

    print(f"\n{'='*60}")
    if fails:
        print(f"FAIL: {len(fails)} issue(s) found:")
        for f in fails:
            print(f"  - {f}")
        raise SystemExit(1)
    print("PASS: all partner-matching constants are identical across all 5 files.")


if __name__ == "__main__":
    main()
