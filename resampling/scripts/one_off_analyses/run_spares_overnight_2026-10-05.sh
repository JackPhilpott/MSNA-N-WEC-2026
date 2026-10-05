#!/bin/bash
# ==============================================================================
# 2026-10-05 OVERNIGHT SPARES (Jack, in Resampling's window: "ok yes, we'll do the spares overnight once all is
# confirmed with coordinator that it's ready"). Unattended; stops at the first failure.
#   0  pre-checks (frame = the recorded v15 state, no register, no run lock)
#   1  archive the frame (12 files)                       -> data_collection/_archive/2026-10-05_pre_spares/
#   2  plan (plan_spares_2026-10-05.py): 2 spares per stratum still collecting
#   3  draws per partner, staging only: Non-IDP with DRAW_TIER1_ONLY=1 (fresh areas only), IDP from unfielded sites
#   4  register (buffer_cluster_register.csv) from the staged clusters, validated by spare_clusters.load_register
#   5  stamp + merge per partner (merge_partner_resample_batch.R: stratum partners + mismatch guard)
#   6  refresh WORKING, 05, stamp, mirror syncs; verify the merged rows == the staged rows and the register
#   7  re-baseline, final run (publish into the synced partner folder), the "frame v16 (post-spares)" hand-off
#   8  morning report
# FAIL-SAFE: any failure in steps 4-6 restores the 12 archived frame files and removes the register, so the frame,
# the DO hand-off and the partner folders stay exactly at v15. A failure in step 7's run is handled by the
# orchestrator itself (frame restore before publish, all-or-nothing publish with rollback).
# ==============================================================================
set -u
S1="/c/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
cd "$S1" || exit 9
PKG="C:/Users/JackPHILPOTT/ACTED/IMPACT NGA - NGA MSNA 2026 Package"
RS=$(python -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.rscript_exe())")
DC="output/data/data_collection"
REG="$DC/buffer_cluster_register.csv"
FA="$DC/_archive/2026-10-05_pre_spares"
LABEL="2026-10-05_spares"
SP="resampling/output/spares_2026-10-05"
L="$SP/EXECUTE"
REPORT="$SP/MORNING_REPORT.md"
EXPECT_WORKING="${EXPECT_WORKING:?set EXPECT_WORKING to the recorded v15 WORKING md5 (first 8)}"
m8() { md5sum "$1" | cut -c1-8; }
note() { echo "$*"; echo "$*" >> "$REPORT"; }
restore() {
  note "**RESTORING the v15 frame** from $FA and removing the register (reason: $*)"
  for f in $(ls "$FA"); do cp -p "$FA/$f" "$DC/$f"; done
  rm -f "$REG"
  "$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/restore_sync.log" 2>&1
  note "restored: WORKING $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv) (expected $EXPECT_WORKING)"
}
die() { note "STOPPED at $(date +%H:%M:%S): $*"; exit 1; }
die_restore() { note "FAILED at $(date +%H:%M:%S): $*"; restore "$*"; exit 1; }
mkdir -p "$L" || exit 9
echo "# Overnight spares - morning report ($(date '+%Y-%m-%d %H:%M'))" > "$REPORT"

note "## 0. pre-checks ($(date +%H:%M:%S))"
[ "$(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv)" = "$EXPECT_WORKING" ] || die "WORKING is not the recorded v15 state $EXPECT_WORKING"
[ ! -e "$REG" ] || die "a spare register already exists"
[ ! -e output/daily_update_runs/.daily_update.lock ] || die "an orchestrator run holds the lock"
[ ! -e "$FA" ] || die "$FA exists"
note "ok - frame v15 (WORKING $EXPECT_WORKING), no register, no lock"

note "## 1. archive ($(date +%H:%M:%S))"
mkdir -p "$FA" && for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$FA/" && [ "$(m8 "$DC/$f")" = "$(m8 "$FA/$f")" ] || die "archive $f"; done
note "$(ls "$FA" | wc -l) frame files archived to $FA"

note "## 2. plan ($(date +%H:%M:%S))"
python resampling/scripts/one_off_analyses/plan_spares_2026-10-05.py > "$L/plan.log" 2>&1 || die "plan failed"
tail -8 "$L/plan.log" >> "$REPORT"

note "## 3. draws, staging only ($(date +%H:%M:%S))"
i=0
for f in $(ls "$SP" | grep -E "^shortfalls_(non_idp|idp)_.*\.csv$"); do
  pop=$(echo "$f" | sed -E 's/^shortfalls_(non_idp|idp)_.*/\1/'); folder=$(echo "$f" | sed -E 's/^shortfalls_(non_idp|idp)_(.*)\.csv$/\2/' | tr '_' ' ')
  ST="resampling/output/resample_runs/$folder/$LABEL"; mkdir -p "$ST"; i=$((i+1)); seed=$((2026100500 + i))
  if [ "$pop" = "non_idp" ]; then
    cp "$SP/$f" "$ST/shortfalls_nonidp.csv"
    DRAW_TIER1_ONLY=1 "$RS" resampling/scripts/draw_supplementary_clusters_batch.R "$ST/shortfalls_nonidp.csv" "$ST" "$seed" > "$ST/draw_nonidp_console.log" 2>&1 || die "Non-IDP draw $folder failed (staging only, frame untouched)"
  else
    cp "$SP/$f" "$ST/shortfalls_idp.csv"
    "$RS" resampling/scripts/draw_supplementary_idp_sites_batch.R "$ST/shortfalls_idp.csv" "$ST" "$seed" > "$ST/draw_idp_console.log" 2>&1 || die "IDP draw $folder failed (staging only, frame untouched)"
  fi
  note "- $pop $folder: seed $seed, done $(date +%H:%M:%S)"
done

note "## 4. register ($(date +%H:%M:%S))"
python resampling/scripts/one_off_analyses/write_spare_register_2026-10-05.py "$LABEL" > "$L/register.log" 2>&1 || die_restore "register failed"
tail -6 "$L/register.log" >> "$REPORT"

note "## 5. stamp + merges ($(date +%H:%M:%S))"
for ST in resampling/output/resample_runs/*/"$LABEL"; do
  folder=$(basename "$(dirname "$ST")")
  [ -f "$ST/new_clusters.csv" ] || [ -f "$ST/new_clusters_idp_sitelevel.csv" ] || { note "- $folder: nothing drawn"; continue; }
  for h in "$ST/new_households.csv" "$ST/new_households_idp_sitelevel.csv"; do
    [ -f "$h" ] && { python resampling/scripts/stamp_ward_accessible_status.py "$h" > "$L/stamp_${folder// /_}.log" 2>&1 || die_restore "stamping $h failed"; }
  done
  hdr="strata_id,adm2_pcode,pop_type,additional_clusters_needed,state,lga,partners"
  [ -f "$ST/shortfalls_nonidp.csv" ] || echo "$hdr" > "$ST/shortfalls_nonidp.csv"
  [ -f "$ST/shortfalls_idp.csv" ] || echo "$hdr" > "$ST/shortfalls_idp.csv"
  "$RS" resampling/scripts/merge_partner_resample_batch.R "$folder" "$ST" "$ST/shortfalls_nonidp.csv" "$ST/shortfalls_idp.csv" > "$L/merge_${folder// /_}.log" 2>&1 || die_restore "merge $folder failed: $(tail -3 "$L/merge_${folder// /_}.log" | tr '\n' ' ')"
  note "- merged $folder: $(grep -E 'Verified' "$L/merge_${folder// /_}.log" | cut -c1-120)"
done

note "## 6. refresh + 05 + stamp + sync + verify ($(date +%H:%M:%S))"
"$RS" scripts/field_guide_production/refresh_working_frame_daily.R > "$L/refresh.log" 2>&1 || die_restore "refresh failed"
(cd resampling/scripts && python 05_build_accessibility_impact_workbook.py) > "$L/05.log" 2>&1 || die_restore "05 failed"
"$RS" scripts/stamp_frame_version.R > "$L/stamp.log" 2>&1 || die_restore "stamp failed"
"$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/sync_frame.log" 2>&1 || die_restore "frame mirror sync failed"
"$RS" resampling/scripts/sync_accessibility_mirrors.R > "$L/sync_access.log" 2>&1 || die_restore "accessibility mirror sync failed"
python resampling/scripts/one_off_analyses/verify_spares_merge_2026-10-05.py "$LABEL" "$FA" > "$L/verify.log" 2>&1 || die_restore "verification failed: $(tail -3 "$L/verify.log" | tr '\n' ' ')"
cat "$L/verify.log" >> "$REPORT"
grep "^Representativity" "$L/05.log" | cut -c1-160 >> "$REPORT"

note "## 7. baseline + final run + v16 hand-off ($(date +%H:%M:%S))"
python scripts/daily_update/run_frame_and_partner_update.py --reseed-baseline > "$L/reseed.log" 2>&1 || die "reseed failed (frame v16 is in place and verified; partner folders still v15)"
MSNA_PKG_ROOT="$PKG" python scripts/daily_update/run_frame_and_partner_update.py > "$L/final_run.log" 2>&1
rc=$?
grep -E "staged [0-9]|RESULT" "$L/final_run.log" | cut -c1-200 >> "$REPORT"
if [ $rc -ne 0 ]; then
  # the DO must not get spare points the partners cannot see: no v16 hand-off unless the partner publish succeeded
  note "**final run exit $rc - v16 hand-off NOT built.** The frame holds the spares (verified above), partners still have v15. See $L/final_run.log; the orchestrator restores the frame on a frame-level failure and rolls back a failed publish."
else
  python scripts/one_off_analyses/build_do_handoff_2026-10-04.py --out resampling/output/do_handoff_v16_post_spares_2026-10-05 \
    --dest-version v16 --label post-spares --changes "$SP/do_handoff_changes_v16.md" \
    --baseline-working "$FA/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv" > "$L/handoff.log" 2>&1 || note "**hand-off build failed** - see $L/handoff.log"
  tail -3 "$L/handoff.log" >> "$REPORT"
fi
note "## done $(date '+%Y-%m-%d %H:%M:%S') | WORKING $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv) FULL $(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv)"
