# ==============================================================================
# 2026-10-14 (Jack's go, Resampling window): INTERSOS's Maru team reports the coordinates "still directing them to other wards
# outside Maru town". The KMLs and the 'Available to Collect' sheet are correct (every point inside Maru ward), but the Maru
# folder still held 9 cluster guides (factsheets) for clusters removed on 12 Oct - in Mayanchi, Ruwan Doruma, Morai, Kanoma
# and Bena - and the 27 Sep LGA overview map, which draws every hex ever selected in the LGA. This moves them into archive
# subfolders beside where they are (never deletes), plus the map's source in output/maps/lga_summary/ so the package build
# stops re-copying it (build_partner_dc_packages.py skips an LGA map whose source is missing). md5-checked; manifest written.
#   py archive_intersos_maru_stale_guides_2026-10-14.py            dry run
#   py archive_intersos_maru_stale_guides_2026-10-14.py --execute
#   py archive_intersos_maru_stale_guides_2026-10-14.py --restore
# ==============================================================================
import csv, hashlib, json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "scripts", "shared"))
import msna_paths  # noqa: E402

S1 = msna_paths.sampling_dir()
MARU = os.path.join(msna_paths.pkg_root(), "INTERSOS", "Zamfara", "Maru")
STALE = {"IDP": ["idp_NG037010_1", "idp_NG037010_14"],
         "Non_IDP": ["non_idp_NG037010_supp4", "non_idp_NG037010_supp15", "non_idp_NG037010_supp18", "non_idp_NG037010_supp25",
                     "non_idp_NG037010_supp26", "non_idp_NG037010_supp27", "non_idp_NG037010_supp28"]}
TAG = "2026-10-14"
MOVES = [(os.path.join(MARU, pt, "Cluster_guide", f"{c}_factsheet.docx"),
          os.path.join(MARU, pt, "Cluster_guide", f"_archived_dropped_clusters_{TAG}", f"{c}_factsheet.docx"))
         for pt, cs in STALE.items() for c in cs]
MOVES += [(os.path.join(MARU, "Maru_map.png"), os.path.join(MARU, f"_archived_lga_map_{TAG}", "Maru_map.png")),
          (os.path.join(S1, "output", "maps", "lga_summary", "NG037010_Maru.png"),
           os.path.join(S1, "output", "maps", "lga_summary", f"_archived_{TAG}", "NG037010_Maru.png"))]
MANIFEST = os.path.join(S1, "resampling", "output", f"intersos_maru_partner_cleanup_{TAG}", "archive_manifest.json")
md5 = lambda p: hashlib.md5(open(p, "rb").read()).hexdigest()


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--restore":
        man = json.load(open(MANIFEST, encoding="utf-8"))
        for m in man["moves"]:
            assert os.path.isfile(m["to"]) and not os.path.exists(m["from"]) and md5(m["to"]) == m["md5"], m
        for m in man["moves"]:
            shutil.move(m["to"], m["from"])
        print(f"restored {len(man['moves'])} file(s)")
        return
    # the stale clusters must really be off the live WORKING list, and the map really the old one
    wk = set()
    with open(msna_paths.frame_file("stage2_WORKING"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            wk.add(r["cluster_id"])
    on_wk = [c for cs in STALE.values() for c in cs if c in wk]
    assert not on_wk, f"STOP: still on WORKING: {on_wk}"
    plan = []
    for src, dst in MOVES:
        assert os.path.isfile(src), f"STOP: missing {src}"
        assert not os.path.exists(dst), f"STOP: already archived: {dst}"
        plan.append({"from": src, "to": dst, "md5": md5(src)})
        print(f"{'MOVE' if mode == '--execute' else 'would move'}: {os.path.relpath(src, os.path.dirname(MARU))} -> {os.path.basename(os.path.dirname(dst))}/")
    if mode != "--execute":
        print(f"dry run: {len(plan)} file(s), nothing moved")
        return
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    for m in plan:
        os.makedirs(os.path.dirname(m["to"]), exist_ok=True)
        shutil.move(m["from"], m["to"])
        assert md5(m["to"]) == m["md5"] and not os.path.exists(m["from"])
    json.dump({"tag": TAG, "why": "Jack 14 Oct: INTERSOS Maru teams directed outside Maru ward by stale guides/map", "moves": plan},
              open(MANIFEST, "w", encoding="utf-8"), indent=1)
    print(f"moved {len(plan)} file(s); manifest {MANIFEST}")


if __name__ == "__main__":
    main()
