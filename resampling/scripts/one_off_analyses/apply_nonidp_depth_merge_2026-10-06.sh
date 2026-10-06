#!/bin/bash
# ==============================================================================
# 2026-10-06 LIVE merge of the staged Non-IDP depth top-up (build_nonidp_depth_topup_2026-10-05.R, seed 2026100701;
# sandbox-tested 5 Oct). Run ONLY on Jack's "depth merge go" (go #1) in Resampling's window. Partner folders and the
# DO hand-off are NOT touched here (that is go #2: orchestrator publish + v17).
# Expected, from the sandbox test: FULL and WORKING +1,296 rows exactly (the staged additions); existing rows change only
# target_households / reserve_households / selection_count, in exactly the 40 planned clusters (+increase, +increase/6);
# strata WORKING realized_moe_pct equal to depth_plan_by_stratum.csv's moe_after (2 dp) in the 6 strata, no other
# stratum changed; 05: 277 Representative.
# Any failure after the archive restores the frame (13 files), the orchestrator state and the mirrors.
# ==============================================================================
set -u
S1="/c/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
cd "$S1" || exit 9
DC="output/data/data_collection"; STATE="output/daily_update_runs/state"
AR="$DC/_archive/2026-10-06_pre_nonidp_depth"; AS="${AR}_orchestrator_state"
LABEL="2026-10-05_nonidp_depth"; PLAN="resampling/output/nonidp_depth_2026-10-05"
L="$PLAN/APPLY_2026-10-06"
RS=$(python -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.rscript_exe())")
m8() { md5sum "$1" | cut -c1-8; }
say() { echo "$*"; echo "$*" >> "$L/APPLY_LOG.md"; }
restore() {
  say "**RESTORING** (reason: $*)"
  for f in $(ls -p "$AR" | grep -v /); do cp -p "$AR/$f" "$DC/$f"; done
  for f in $(ls "$AS"); do cp -p "$AS/$f" "$STATE/$f"; done
  "$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/restore_sync.log" 2>&1 || say "restore: mirror sync FAILED"
  say "restored: WORKING $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv), FULL $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv)"
  exit 1
}
mkdir -p "$L" || exit 9
say "# Non-IDP depth merge - live apply $(date '+%F %T')"
# 0. pre-checks: the frame and the staged files are the sandbox-tested ones; no run lock; no archive yet
for pair in "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv 7268174a" "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv 749b6b1c" \
            "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv d0020472" "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv cc0682ee"; do
  set -- $pair; [ "$(m8 "$DC/$1")" = "$2" ] || { say "STOP: $1 is $(m8 "$DC/$1"), expected $2"; exit 1; }
done
for pair in "FACT/$LABEL/existing_cluster_household_additions_non_idp.csv 27b1a166" "FACT/$LABEL/existing_cluster_target_increases_non_idp.csv 2f53ab9a" \
            "INTERSOS/$LABEL/existing_cluster_household_additions_non_idp.csv b923a7b8" "INTERSOS/$LABEL/existing_cluster_target_increases_non_idp.csv 3b091425"; do
  set -- $pair; [ "$(m8 "resampling/output/resample_runs/$1")" = "$2" ] || { say "STOP: staged $1 changed"; exit 1; }
done
[ ! -e output/daily_update_runs/.daily_update.lock ] || { say "STOP: an orchestrator run holds the lock"; exit 1; }
{ [ ! -e "$AR" ] && [ ! -e "$AS" ]; } || { say "STOP: $AR exists"; exit 1; }
say "0. pre-checks OK"
# 1. archive
mkdir -p "$AR" "$AS" || exit 9
for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$AR/" && [ "$(m8 "$DC/$f")" = "$(m8 "$AR/$f")" ] || { say "STOP: archive $f"; exit 1; }; done
for f in $(ls -p "$STATE" | grep -v /); do cp -p "$STATE/$f" "$AS/" || { say "STOP: archive state $f"; exit 1; }; done
say "1. archived $(ls -p "$AR" | grep -v / | wc -l) frame files + $(ls "$AS" | wc -l) state files -> $AR"
# 2. stamp + live merge per partner
for p in FACT INTERSOS; do
  ST="resampling/output/resample_runs/$p/$LABEL"
  python resampling/scripts/stamp_ward_accessible_status.py "$ST/existing_cluster_household_additions_non_idp.csv" > "$L/stamp_$p.log" 2>&1 || restore "stamp $p"
  grep -q "'Inaccessible': 0, 'unmatched_left_blank': 0" "$L/stamp_$p.log" || restore "stamp $p: not every row Accessible ($(tail -1 "$L/stamp_$p.log"))"
  "$RS" resampling/scripts/merge_partner_resample_batch.R "$p" "$ST" "$ST/shortfalls_nonidp.csv" "$ST/shortfalls_idp.csv" > "$L/merge_$p.log" 2>&1 \
    || restore "merge $p: $(tail -3 "$L/merge_$p.log" | tr '\n' ' ')"
  say "2. merged $p: $(grep -E 'Verified' "$L/merge_$p.log" | cut -c1-140)"
done
# 3. refresh, then verify against the plan
"$RS" scripts/field_guide_production/refresh_working_frame_daily.R > "$L/refresh.log" 2>&1 || restore "refresh"
python - "$AR" "$PLAN" > "$L/verify.log" 2>&1 <<'PY' || restore "verify: $(tail -3 "$L/verify.log" | tr '\n' ' ')"
import csv, glob, sys
AR, PLAN = sys.argv[1], sys.argv[2]
DC = "output/data/data_collection"
rd = lambda p: list(csv.DictReader(open(p, encoding="utf-8-sig")))
inc = {r["cluster_id"]: int(r["increase_target"]) for r in rd(f"{PLAN}/depth_plan_by_cluster.csv")}
plan_s = {r["strata_id"]: r for r in rd(f"{PLAN}/depth_plan_by_stratum.csv")}
staged = set()
for p in glob.glob("resampling/output/resample_runs/*/2026-10-05_nonidp_depth/existing_cluster_household_additions_non_idp.csv"):
    staged |= {r["survey_id"] for r in rd(p)}
ok = len(staged) == 1296
for name in ("FULL", "WORKING"):
    f = f"NGA_MSNA_2026_stage2_sampling_frame_v14_{name}.csv"
    old = {r["survey_id"]: r for r in rd(f"{AR}/{f}")}; new = {r["survey_id"]: r for r in rd(f"{DC}/{f}")}
    added, removed = set(new) - set(old), set(old) - set(new)
    bad = sum(1 for k in set(old) & set(new) if (d := [c for c in new[k] if old[k].get(c) != new[k][c]])
              and (new[k]["cluster_id"] not in inc or set(d) - {"target_households", "reserve_households", "selection_count"}))
    good = added == staged and not removed and bad == 0
    ok &= good
    print(f"{name}: +{len(added)} (staged {len(staged)}) -{len(removed)}, rows changed outside the plan {bad} -> {'PASS' if good else 'FAIL'}")
sw = {r["strata_id"]: r for r in rd(f"{DC}/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv")}
sw0 = {r["strata_id"]: r for r in rd(f"{AR}/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv")}
for sid, p in plan_s.items():
    if not p["moe_after"] or p["moe_after"] == "NA":
        continue
    got = round(float(sw[sid]["realized_moe_pct"]), 2)
    good = abs(got - float(p["moe_after"])) < 0.005
    ok &= good
    print(f"  {p['lga']:10} MoE {float(sw0[sid]['realized_moe_pct']):.2f} -> {got:.2f} (plan {p['moe_after']}) {'PASS' if good else 'FAIL'}")
others = [s for s in sw if s not in plan_s and sw[s] != sw0.get(s)]
ok &= not others
print(f"other strata changed: {len(others)}")
print("VERIFY: ALL PASS" if ok else "VERIFY: FAILED")
sys.exit(0 if ok else 1)
PY
cat "$L/verify.log" >> "$L/APPLY_LOG.md"
# 4. stamp + mirrors, 05, re-baseline (stage2 md5s changed: needed)
"$RS" scripts/stamp_frame_version.R > "$L/stamp.log" 2>&1 || restore "stamp"
"$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/sync.log" 2>&1 || restore "mirror sync"
(cd resampling/scripts && python 05_build_accessibility_impact_workbook.py) > "$L/05.log" 2>&1 || say "05 FAILED (non-fatal) - see $L/05.log"
grep -E "^Representativity" "$L/05.log" | cut -c1-140 >> "$L/APPLY_LOG.md"
python scripts/daily_update/run_frame_and_partner_update.py --reseed-baseline > "$L/reseed.log" 2>&1 || restore "reseed: $(tail -2 "$L/reseed.log" | tr '\n' ' ')"
tail -1 "$L/reseed.log" >> "$L/APPLY_LOG.md"
say "## done $(date '+%F %T') | WORKING $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv) FULL $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv) strata W $(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv) F $(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv) stamp $(m8 $DC/_frame_version.txt)"
