"""
msna_paths.py - where things live, on any machine (written 4 Oct 2026 for the
data officer's week; same convention as msna_paths.R and as
2_monitoring/scripts/shared/project_root.R).

The WORKSPACE is the folder holding both 1_sampling/ and 2_monitoring/.
Resolution order:
  1. env MSNA_WORKSPACE. It must hold both folders, otherwise stop. Never fall
     back silently: a sandbox run must not write into the live workspace.
  2. walk up from this file's own folder;
  3. walk up from the working directory;
  4. Jack's original path, so his machine keeps working unchanged.

Also:
  python_exe()   env MSNA_PYTHON (a python.exe, or a command such as "py -3",
                 resolved to that interpreter's own path), else the interpreter
                 running this code.
  rscript_exe()  env MSNA_RSCRIPT, else Rscript on PATH, else the newest
                 Rscript.exe in the standard R install folders.
  pkg_root()     env MSNA_PKG_ROOT, else the partner package folder that sits
                 beside "4. Data" in the same synced library.

Scripts find this module with the short bootstrap block at their top.
"""
import glob
import os
import re
import shutil
import subprocess
import sys

_LEGACY_WORKSPACE = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026"
_HERE = os.path.dirname(os.path.abspath(__file__))


def is_workspace(d):
    return bool(d) and os.path.isdir(os.path.join(d, "1_sampling")) and os.path.isdir(os.path.join(d, "2_monitoring"))


def _walk_up(start):
    if not start:
        return None
    d = os.path.abspath(start)
    while True:
        if is_workspace(d):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def workspace():
    env = os.environ.get("MSNA_WORKSPACE", "").strip()
    if env:
        if not is_workspace(env):
            raise SystemExit(f"MSNA_WORKSPACE='{env}' does not hold both 1_sampling and 2_monitoring.")
        return os.path.abspath(env)
    for start in (_HERE, os.getcwd()):
        ws = _walk_up(start)
        if ws:
            return ws
    if is_workspace(_LEGACY_WORKSPACE):
        return _LEGACY_WORKSPACE
    raise SystemExit("Cannot find the MSNA workspace (the folder holding 1_sampling and 2_monitoring). Set MSNA_WORKSPACE.")


def sampling_dir():
    return os.path.join(workspace(), "1_sampling")


def monitoring_dir():
    return os.path.join(workspace(), "2_monitoring")


def pkg_root():
    env = os.environ.get("MSNA_PKG_ROOT", "").strip()
    if env:
        return os.path.abspath(env)
    return os.path.abspath(os.path.join(os.path.dirname(os.path.dirname(workspace())),
                                        "3. External coordination", "NGA MSNA 2026 Package"))


def python_exe():
    env = os.environ.get("MSNA_PYTHON", "").strip()
    if not env:
        return sys.executable
    if os.path.isfile(env):
        return os.path.abspath(env)
    parts = env.split()
    exe = shutil.which(parts[0])
    if exe:
        out = subprocess.run([exe, *parts[1:], "-c", "import sys; print(sys.executable)"],
                             capture_output=True, text=True, timeout=60)
        path = out.stdout.strip().splitlines()[-1] if out.returncode == 0 and out.stdout.strip() else ""
        if path and os.path.isfile(path):
            return path
    raise SystemExit(f"MSNA_PYTHON='{env}' does not run a Python interpreter.")


def _version_key(path):
    m = re.search(r"R-(\d+)\.(\d+)\.(\d+)", path)
    return tuple(int(x) for x in m.groups()) if m else (0, 0, 0)


def rscript_exe():
    env = os.environ.get("MSNA_RSCRIPT", "").strip()
    if env:
        if os.path.isfile(env):
            return os.path.abspath(env)
        raise SystemExit(f"MSNA_RSCRIPT='{env}' is not a file.")
    found = shutil.which("Rscript")
    if found:
        return found
    pats = [r"C:\Program Files\R\R-*\bin\Rscript.exe",
            os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "R", "R-*", "bin", "Rscript.exe")]
    cands = [p for pat in pats for p in glob.glob(pat)]
    if cands:
        return max(cands, key=_version_key)
    raise SystemExit("Rscript not found. Install R or set MSNA_RSCRIPT to Rscript.exe.")


# ------------------------------------------------------------------ frame version (proposal #25, 9 Oct)
# The frame version is not a setting: it is read off the files in output/data/data_collection. Exactly one version
# of the stage2 WORKING frame may be there, and every file of that version's family must be next to it. Anything
# else (a half-done bump, an OneDrive sync caught midway with v14 and v17 side by side) stops the reader loudly
# instead of letting it pick one. So the code can land before the files are bumped, and follows the bump by itself.
FRAME_FAMILY = {
    "stage2_FULL": "NGA_MSNA_2026_stage2_sampling_frame_{v}_FULL.csv",
    "stage2_WORKING": "NGA_MSNA_2026_stage2_sampling_frame_{v}_WORKING.csv",
    "strata_FULL": "NGA_MSNA_2026_strata_level_sampling_frame_{v}_FULL.csv",
    "strata_WORKING": "NGA_MSNA_2026_strata_level_sampling_frame_{v}_WORKING.csv",
    "cluster_status": "NGA_MSNA_2026_cluster_status_{v}.csv",
}


def data_collection_dir():
    return os.path.join(sampling_dir(), "output", "data", "data_collection")


def frame_version(dc=None):
    """'v14', 'v17', ... - the one version present in data_collection (or dc)."""
    dc = dc or data_collection_dir()
    found = sorted({m.group(1) for f in os.listdir(dc)
                    for m in [re.fullmatch(r"NGA_MSNA_2026_stage2_sampling_frame_(v\d+)_WORKING\.csv", f)] if m})
    if len(found) != 1:
        raise SystemExit(f"frame version: expected exactly one stage2 WORKING frame in {dc}, found {found or 'none'} "
                         f"- a version bump is half done or still syncing; wait, or finish/roll back the bump.")
    v = found[0]
    missing = [t.format(v=v) for t in FRAME_FAMILY.values() if not os.path.isfile(os.path.join(dc, t.format(v=v)))]
    if missing:
        raise SystemExit(f"frame version {v}: missing {missing} in {dc}")
    return v


def frame_file(kind, dc=None):
    """Full path of one frame-family file, e.g. frame_file('stage2_WORKING')."""
    dc = dc or data_collection_dir()
    return os.path.join(dc, FRAME_FAMILY[kind].format(v=frame_version(dc)))
