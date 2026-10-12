# ==============================================================================
# #39 (2026-10-13): archive the returned accessibility reports of the 4 partners that left on 4 Oct (FHI 360, IRC,
# Solidarites, Street Child of Nigeria - every LGA they covered went to FACT; IRC's only frame rows left are the
# floor-excluded Isa / Sabon Birni strata). Archive, never delete.
# Why: 02_ingest globs every *_accessibility_report.xlsx in accessibility_reports_returned/ and re-logs 10 stale rows
# from these 4 files on top of FACT's 4 Oct decisions (Dalori, Yandoton Daji, Gulak, Kekeno, ...). Moved into the
# folder's own flat _archive/ (same naming as the other pre-change copies there), 02 and 04 no longer read them.
# Staged effect (sandbox, 13 Oct): 02 logs 10 -> 0 rows; 04 changes NO accessible status - only the provenance of 36
# wards in 5 jointly covered LGAs (Anka, Gwandu, Tsafe, Jibia, Batagarawa): "confirmed_by_partner_report (blank row)"
# -> "default_unreported" / "Not yet reported". See resampling/output/stage_39_archive_exited_partner_reports_2026-10-13/.
# Dry run by default. --execute moves the files; --restore moves them back. md5-checked both ways.
# Run from 1_sampling/ (or anywhere): py resampling/scripts/one_off_analyses/archive_exited_partner_reports_2026-10-13.py
# ==============================================================================
import argparse, csv, glob, hashlib, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "scripts", "shared"))
import msna_paths  # noqa: E402

RET = os.path.join(msna_paths.sampling_dir(), "resampling", "input", "accessibility_reports_returned")
ARCH = os.path.join(RET, "_archive")
TAG = "exited_partner_archived_2026-10-13"
FILES = {  # partner -> md5 of the file as staged on 13 Oct
    "FHI 360": "4c526ba74a787ceb635e99e805b422e1",
    "IRC": "e1ef9d9803f42249a9c31357d32881d4",
    "Solidarités": "4558f4f13e9fede342d7f19f887c89cc",
    "Street Child of Nigeria": "92bc2d78ae90ddc657bacb6143116fb6",
}
md5 = lambda p: hashlib.md5(open(p, "rb").read()).hexdigest()


def active_coverage():
    out = {}
    for r in csv.DictReader(open(msna_paths.frame_file("strata_FULL"), encoding="utf-8-sig")):
        if r.get("coverage_status") == "covered" and (r.get("exclusion_reason") or "none") == "none":
            for p in re.split(r"[;,]", r.get("partners_covering") or ""):
                out.setdefault(p.strip(), []).append(r["strata_id"])
    return out


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--execute", action="store_true")
    g.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    plan = [(p, os.path.join(RET, f"{p}_accessibility_report.xlsx"), os.path.join(ARCH, f"{p}_accessibility_report_{TAG}.xlsx"), h)
            for p, h in FILES.items()]
    if a.restore:
        for p, live, arch, h in plan:
            assert os.path.isfile(arch) and not os.path.exists(live), f"{p}: nothing to restore, or {live} exists"
            assert md5(arch) == h, f"{p}: archived copy changed since staging"
        for p, live, arch, h in plan:
            shutil.move(arch, live)
            assert md5(live) == h
            print(f"restored {os.path.basename(live)}")
        return
    cov = active_coverage()
    still = {p: cov[p] for p in FILES if p in cov}
    if still:
        sys.exit(f"STOP: partner(s) still actively covering strata, nothing moved: {still}")
    for p, live, arch, h in plan:
        assert os.path.isfile(live), f"{p}: {live} not found"
        assert md5(live) == h, f"{p}: file changed since staging (md5 {md5(live)}), nothing moved - re-stage"
        assert not os.path.exists(arch), f"{p}: {arch} already exists"
        print(f"{'MOVE' if a.execute else 'would move'}: {os.path.basename(live)} -> _archive/{os.path.basename(arch)}")
    if not a.execute:
        print("dry run: nothing moved (add --execute)")
        return
    for p, live, arch, h in plan:
        shutil.move(live, arch)
        assert md5(arch) == h and not os.path.exists(live)
    left = {os.path.basename(f) for f in glob.glob(os.path.join(RET, "*_accessibility_report.xlsx"))}
    assert not left & {f"{p}_accessibility_report.xlsx" for p in FILES}
    print(f"moved 4 file(s); 02/04 now read {len(left)} returned report(s). Next routine refresh (02 -> 04 -> layer -> 05) "
          f"picks up the provenance relabel; no accessible status changes.")


if __name__ == "__main__":
    main()
