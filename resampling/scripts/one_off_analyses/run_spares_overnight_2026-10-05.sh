#!/bin/bash
# ==============================================================================
# 2026-10-05 OVERNIGHT SPARES (Jack, in Resampling's window: "ok yes, we'll do the spares overnight once all is
# confirmed with coordinator that it's ready"; his overnight rule via the Coordinator, ~01:10: "some spares are better
# than none so don't let one fail for an LGA stop all the others going out (just report it to me) - and then make sure
# they're all pushed and updated to the partner folders as well"). Unattended.
#   0  pre-checks (frame = the recorded v15 state, no register, no run lock)
#   1  archive the frame (12 files) -> data_collection/_archive/2026-10-05_pre_spares/, and the orchestrator's state
#      (its frame/publish baseline) -> data_collection/_archive/2026-10-05_pre_spares_orchestrator_state/
#   1b routine refresh of WORKING (absorbs any submission newer than v15) + a snapshot of it: the baseline step 6
#      checks WORKING against, so a new submission cannot fail that check
#   2  plan (plan_spares_2026-10-05.py): 2 spares per stratum still collecting
#   3  draws per partner batch, staging only: Non-IDP with DRAW_TIER1_ONLY=1 (fresh areas only), IDP from unfielded
#      sites; each household file stamped with ward accessibility. A batch that fails is redrawn stratum by stratum, so
#      only the failing stratum is skipped (reported). An exhausted pool is a normal 0-cluster result (0-byte files)
#   4  register (buffer_cluster_register.csv) from the staged clusters, validated by spare_clusters.load_register
#   5  merge per partner (merge_partner_resample_batch.R: stratum partners + mismatch guard). A partner whose merge
#      fails is undone alone (frame files back to just before it) and its spares leave the register (reported)
#   6  per-stratum table; refresh WORKING, 05, stamp, mirror syncs; verify FULL/WORKING/register against the archive
#   7  re-baseline; final run with --config (archiving off, the 65 retired files allowed, as on 4 Oct) publishing into
#      the synced partner folder; the "frame v16 (post-spares)" hand-off only if that run really published
# SYSTEMIC failures restore v15 (frame, orchestrator state, mirrors, 05 if it ran; register removed), so frame, partner
# folders and DO hand-off stay exactly at v15 and the DO's morning run works as before: archive/refresh/plan/register/
# stamp/sync/verify failures, no spare merged at all, a failed re-baseline, a final run that did not publish (the
# orchestrator rolls a failed publish back itself). A final run that published but reported an error is left as is.
# ==============================================================================
set -u
S1="/c/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
cd "$S1" || exit 9
PKG="C:/Users/JackPHILPOTT/ACTED/IMPACT NGA - NGA MSNA 2026 Package"
CFG="scripts/daily_update/daily_update_config_reallocation_2026-10-04.json"
RS=$(python -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.rscript_exe())")
DC="output/data/data_collection"
WORKING="$DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv"
FULL="$DC/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv"
REG="$DC/buffer_cluster_register.csv"
FA="$DC/_archive/2026-10-05_pre_spares"
STATE="output/daily_update_runs/state"
FS="$DC/_archive/2026-10-05_pre_spares_orchestrator_state"
LABEL="2026-10-05_spares"
RR="resampling/output/resample_runs"
SP="resampling/output/spares_2026-10-05"
SNAP="$SP/WORKING_pre_spares_refreshed.csv"
FAILS="$SP/stratum_failures.csv"
PM="/tmp/msna_spares_premerge"
L="$SP/EXECUTE"
REPORT="$SP/MORNING_REPORT.md"
EXPECT_WORKING="${EXPECT_WORKING:?set EXPECT_WORKING to the recorded v15 WORKING md5 (first 8)}"
RAN05=0
m8() { md5sum "$1" | cut -c1-8; }
has_rows() { [ -s "$1" ] && [ "$(wc -l < "$1")" -gt 1 ]; }   # a header plus at least one data row
n_rows() { if has_rows "$1"; then echo $(( $(wc -l < "$1") - 1 )); else echo 0; fi; }
note() { echo "$*"; echo "$*" >> "$REPORT"; }
restore() {
  note "**RESTORING v15** - frame from $FA, orchestrator state from $FS, register removed (reason: $*)"
  for f in $(ls "$FA"); do cp -p "$FA/$f" "$DC/$f"; done
  for f in $(ls "$FS"); do cp -p "$FS/$f" "$STATE/$f"; done
  rm -f "$REG"
  "$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/restore_sync.log" 2>&1 || note "restore: frame mirror sync FAILED - see $L/restore_sync.log"
  if [ "$RAN05" = 1 ]; then
    (cd resampling/scripts && python 05_build_accessibility_impact_workbook.py) > "$L/restore_05.log" 2>&1 || note "restore: 05 re-run FAILED - see $L/restore_05.log"
  fi
  note "restored: WORKING $(m8 "$WORKING") (expected $EXPECT_WORKING)"
}
die() { note "STOPPED at $(date +%H:%M:%S): $*"; exit 1; }
die_restore() { note "FAILED at $(date +%H:%M:%S): $*"; restore "$*"; exit 1; }
fail_stratum() { echo "$1,$2,$3,\"$(echo "$4" | tr -d '"\r\n' | cut -c1-200)\"" >> "$FAILS"; }   # strata_id,pop_type,batch,reason
draw_one() {  # draw_one <pop> <shortfalls csv> <staging dir> <seed> <console log>: one draw + ward stamping; 0 = ok
  local h
  if [ "$1" = "non_idp" ]; then
    DRAW_TIER1_ONLY=1 "$RS" resampling/scripts/draw_supplementary_clusters_batch.R "$2" "$3" "$4" > "$5" 2>&1 || return 1
    h="$3/new_households.csv"
  else
    "$RS" resampling/scripts/draw_supplementary_idp_sites_batch.R "$2" "$3" "$4" > "$5" 2>&1 || return 1
    h="$3/new_households_idp_sitelevel.csv"
  fi
  if has_rows "$h"; then python resampling/scripts/stamp_ward_accessible_status.py "$h" >> "$5" 2>&1 || return 2; fi
  return 0
}
combine() {  # combine <dest csv> [<part csv>...]: the rows of every non-empty part under one header (0-byte if none)
  python - "$@" <<'PY'
import csv, sys
dest, parts = sys.argv[1], sys.argv[2:]
cols, rows = None, []
for p in parts:
    with open(p, encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        if not r.fieldnames:
            continue
        if cols is None:
            cols = list(r.fieldnames)
        elif list(r.fieldnames) != cols:
            sys.exit(f"combine: the columns of {p} differ from the first part's")
        rows += list(r)
with open(dest, "w", encoding="utf-8", newline="") as f:
    if cols:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
print(f"combine: {len(rows)} row(s) from {len(parts)} part(s) -> {dest}")
PY
}
drop_spares() {  # drop_spares <staging dir> <reason>: remove that batch's clusters from the register, log its strata
  python - "$REG" "$1" "$2" "$FAILS" <<'PY'
import csv, os, sys
reg, st, reason, fails = sys.argv[1:5]
ids, sids = set(), {}
for fn, pop in (("new_clusters.csv", "non_idp"), ("new_clusters_idp_sitelevel.csv", "idp")):
    p = os.path.join(st, fn)
    if os.path.isfile(p) and os.path.getsize(p) > 2:
        with open(p, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                ids.add(r["cluster_id"])
                sids[r["strata_id"]] = pop
with open(reg, encoding="utf-8-sig", newline="") as f:
    r = csv.DictReader(f)
    cols, rows = r.fieldnames, list(r)
keep = [x for x in rows if x["cluster_id"] not in ids]
with open(reg, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(keep)
with open(fails, "a", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    for sid, pop in sorted(sids.items()):
        w.writerow([sid, pop, os.path.basename(os.path.dirname(st)), reason[:200]])
print(f"register: dropped {len(rows) - len(keep)} spare(s) of {st} ({len(sids)} strata), {len(keep)} left")
PY
}
mkdir -p "$L" || exit 9
echo "# Overnight spares - morning report ($(date '+%Y-%m-%d %H:%M'))" > "$REPORT"

note "## 0. pre-checks ($(date +%H:%M:%S))"
[ "$(m8 "$WORKING")" = "$EXPECT_WORKING" ] || die "WORKING is not the recorded v15 state $EXPECT_WORKING"
[ ! -e "$REG" ] || die "a spare register already exists"
[ ! -e output/daily_update_runs/.daily_update.lock ] || die "an orchestrator run holds the lock"
{ [ ! -e "$FA" ] && [ ! -e "$FS" ]; } || die "an archive folder for tonight already exists"
[ -f "$CFG" ] || die "config $CFG is missing"
note "ok - frame v15 (WORKING $EXPECT_WORKING), no register, no lock"

note "## 1. archive ($(date +%H:%M:%S))"
mkdir -p "$FA" "$FS" || die "cannot create the archive folders"
for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$FA/" && [ "$(m8 "$DC/$f")" = "$(m8 "$FA/$f")" ] || die "archive $f"; done
for f in $(ls -p "$STATE" | grep -v /); do cp -p "$STATE/$f" "$FS/" && [ "$(m8 "$STATE/$f")" = "$(m8 "$FS/$f")" ] || die "archive state $f"; done
note "$(ls "$FA" | wc -l) frame files -> $FA; $(ls "$FS" | wc -l) orchestrator state files -> $FS"

note "## 1b. routine refresh before the spares ($(date +%H:%M:%S))"
"$RS" scripts/field_guide_production/refresh_working_frame_daily.R > "$L/refresh_pre.log" 2>&1 || die_restore "routine refresh before the spares failed"
cp -p "$WORKING" "$SNAP" || die_restore "WORKING snapshot failed"
note "WORKING after the routine refresh: $(m8 "$SNAP") (v15 $EXPECT_WORKING; the same = no submission newer than v15)"

note "## 2. plan ($(date +%H:%M:%S))"
rm -f "$SP"/shortfalls_*.csv
python resampling/scripts/one_off_analyses/plan_spares_2026-10-05.py > "$L/plan.log" 2>&1 || die_restore "plan failed"
tail -8 "$L/plan.log" >> "$REPORT"
echo "strata_id,pop_type,batch,reason" > "$FAILS"

note "## 3. draws, staging only ($(date +%H:%M:%S))"
i=0
for f in $(ls "$SP" | grep -E "^shortfalls_(non_idp|idp)_.*\.csv$"); do
  pop=$(echo "$f" | sed -E 's/^shortfalls_(non_idp|idp)_.*/\1/'); folder=$(echo "$f" | sed -E 's/^shortfalls_(non_idp|idp)_(.*)\.csv$/\2/' | tr '_' ' ')
  i=$((i+1)); seed=$((2026100500 + i)); ST="$RR/$folder/$LABEL"
  mkdir -p "$ST" || die_restore "cannot create $ST"
  if [ "$pop" = "non_idp" ]; then SF="$ST/shortfalls_nonidp.csv"; C="new_clusters.csv"; H="new_households.csv"
  else SF="$ST/shortfalls_idp.csv"; C="new_clusters_idp_sitelevel.csv"; H="new_households_idp_sitelevel.csv"; fi
  cp "$SP/$f" "$SF" || die_restore "cannot copy $f"
  nreq=$(n_rows "$SF")
  if draw_one "$pop" "$SF" "$ST" "$seed" "$ST/draw_${pop}_console.log"; then
    note "- $pop $folder: $(n_rows "$ST/$C") cluster(s) for $nreq stratum/strata (seed $seed, $(date +%H:%M:%S))"
    continue
  fi
  rm -f "$ST/$C" "$ST/$H"
  note "- **$pop $folder: batch FAILED** ($(tail -2 "$ST/draw_${pop}_console.log" | tr '\n' ' ' | cut -c1-200)) - redrawing its $nreq strata one by one"
  parts_c=(); parts_h=(); k=0
  for sid in $(tail -n +2 "$SF" | cut -d, -f1); do
    k=$((k+1)); RT="$RR/$folder/${LABEL}_retry_${pop}_$k"; rseed=$((2026105000 + i * 100 + k))
    rm -rf "$RT"; mkdir -p "$RT" || die_restore "cannot create $RT"
    head -1 "$SF" > "$RT/shortfalls.csv"; grep "^$sid," "$SF" >> "$RT/shortfalls.csv"
    if draw_one "$pop" "$RT/shortfalls.csv" "$RT" "$rseed" "$RT/draw_console.log"; then
      [ -f "$RT/$C" ] && parts_c+=("$RT/$C"); [ -f "$RT/$H" ] && parts_h+=("$RT/$H")
      note "  - $sid: $(n_rows "$RT/$C") cluster(s) (seed $rseed)"
    else
      fail_stratum "$sid" "$pop" "$folder" "draw failed: $(tail -1 "$RT/draw_console.log")"
      note "  - **$sid: FAILED** ($(tail -1 "$RT/draw_console.log" | cut -c1-160)) - no spares for this stratum"
    fi
  done
  if ! { combine "$ST/$C" "${parts_c[@]}" && combine "$ST/$H" "${parts_h[@]}"; } >> "$L/combine.log" 2>&1; then
    rm -f "$ST/$C" "$ST/$H"
    for sid in $(tail -n +2 "$SF" | cut -d, -f1); do fail_stratum "$sid" "$pop" "$folder" "redraws could not be combined"; done
    note "  - **combining the redraws failed** (see $L/combine.log) - no $pop spares from $folder"
  fi
done

note "## 4. register ($(date +%H:%M:%S))"
python resampling/scripts/one_off_analyses/write_spare_register_2026-10-05.py "$LABEL" > "$L/register.log" 2>&1 || die_restore "register failed: $(tail -2 "$L/register.log" | tr '\n' ' ')"
tail -3 "$L/register.log" >> "$REPORT"
has_rows "$REG" || die_restore "no spare cluster was drawn in any batch"

note "## 5. merges ($(date +%H:%M:%S))"
hdr="strata_id,adm2_pcode,pop_type,additional_clusters_needed,state,lga,partners"
for ST in "$RR"/*/"$LABEL"; do
  folder=$(basename "$(dirname "$ST")"); ml="$L/merge_${folder// /_}.log"
  has_rows "$ST/new_clusters.csv" || has_rows "$ST/new_clusters_idp_sitelevel.csv" || { note "- $folder: nothing drawn, no merge"; continue; }
  [ -f "$ST/shortfalls_nonidp.csv" ] || echo "$hdr" > "$ST/shortfalls_nonidp.csv"
  [ -f "$ST/shortfalls_idp.csv" ] || echo "$hdr" > "$ST/shortfalls_idp.csv"
  rm -rf "$PM"; mkdir -p "$PM" || die_restore "cannot create $PM"
  for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$PM/" || die_restore "pre-merge copy of $f failed"; done
  if "$RS" resampling/scripts/merge_partner_resample_batch.R "$folder" "$ST" "$ST/shortfalls_nonidp.csv" "$ST/shortfalls_idp.csv" > "$ml" 2>&1; then
    note "- merged $folder: $(grep -E 'Verified' "$ml" | cut -c1-140)"
  else
    why=$(grep -E "Error|STOP" "$ml" | tail -1 | tr -d '"' | cut -c1-200)
    for f in $(ls "$PM"); do cp -p "$PM/$f" "$DC/$f" || die_restore "could not undo the failed merge of $folder"; done
    drop_spares "$ST" "merge failed: $why" >> "$L/register.log" 2>&1 || die_restore "could not remove $folder's spares from the register"
    mv "$ST" "${ST}_MERGE_FAILED" || die_restore "could not set $folder's failed batch aside"
    note "- **merge $folder FAILED** ($why) - its merge undone, its spares removed from the register; the others continue"
  fi
done
rm -rf "$PM"
has_rows "$REG" || die_restore "no spare cluster could be merged"

note "## 6. per-stratum table, refresh + 05 + stamp + sync + verify ($(date +%H:%M:%S))"
python resampling/scripts/one_off_analyses/summarise_spares_2026-10-05.py > "$L/summary.log" 2>&1 || note "(per-stratum table failed - see $L/summary.log; not a frame problem, continuing)"
cat "$L/summary.log" >> "$REPORT"
"$RS" scripts/field_guide_production/refresh_working_frame_daily.R > "$L/refresh.log" 2>&1 || die_restore "refresh failed"
RAN05=1
(cd resampling/scripts && python 05_build_accessibility_impact_workbook.py) > "$L/05.log" 2>&1 || note "05 failed (non-fatal, as in the orchestrator; its final run re-runs 05) - see $L/05.log"
"$RS" scripts/stamp_frame_version.R > "$L/stamp.log" 2>&1 || die_restore "stamp failed"
"$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/sync_frame.log" 2>&1 || die_restore "frame mirror sync failed"
"$RS" resampling/scripts/sync_accessibility_mirrors.R > "$L/sync_access.log" 2>&1 || die_restore "accessibility mirror sync failed"
python resampling/scripts/one_off_analyses/verify_spares_merge_2026-10-05.py "$LABEL" "$FA" "$SNAP" > "$L/verify.log" 2>&1 || die_restore "verification failed: $(tail -3 "$L/verify.log" | tr '\n' ' ')"
cat "$L/verify.log" >> "$REPORT"
grep "^Representativity" "$L/05.log" | cut -c1-160 >> "$REPORT"
note "SPARES MERGED AND VERIFIED $(date +%H:%M:%S)"

note "## 7. baseline + final run + v16 hand-off ($(date +%H:%M:%S))"
python scripts/daily_update/run_frame_and_partner_update.py --reseed-baseline > "$L/reseed.log" 2>&1 || die_restore "re-baseline failed: $(tail -2 "$L/reseed.log" | tr '\n' ' ')"
ps0=$(m8 "$STATE/publish_state.json")
MSNA_PKG_ROOT="$PKG" python scripts/daily_update/run_frame_and_partner_update.py --config "$CFG" > "$L/final_run.log" 2>&1
rc=$?
ps1=$(m8 "$STATE/publish_state.json")
grep -E "staged [0-9]|\[FAIL\]|RESULT" "$L/final_run.log" | cut -c1-220 >> "$REPORT"
if [ $rc -eq 0 ] && [ "$ps0" != "$ps1" ] && grep -q "RESULT: OK" "$L/final_run.log"; then
  note "PUBLISHED $(date +%H:%M:%S) into $PKG"
  if python scripts/one_off_analyses/build_do_handoff_2026-10-04.py --out resampling/output/do_handoff_v16_post_spares_2026-10-05 \
       --dest-version v16 --label post-spares --changes "$SP/do_handoff_changes_v16.md" \
       --baseline-working "$FA/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv" > "$L/handoff.log" 2>&1; then
    note "V16 READY: resampling/output/do_handoff_v16_post_spares_2026-10-05 (+ .zip)"
  else
    note "**v16 hand-off build failed** - see $L/handoff.log"
  fi
  tail -3 "$L/handoff.log" >> "$REPORT"
elif [ "$ps0" != "$ps1" ]; then
  note "**final run exit $rc but it PUBLISHED (publish_state changed)** - nothing restored, v16 NOT built; frame and partner folders both hold the spares. Morning decision. See $L/final_run.log"
else
  die_restore "final run exit $rc, nothing published - v16 NOT built (see $L/final_run.log)"
fi
note "## done $(date '+%Y-%m-%d %H:%M:%S') | WORKING $(m8 "$WORKING") FULL $(m8 "$FULL")"
