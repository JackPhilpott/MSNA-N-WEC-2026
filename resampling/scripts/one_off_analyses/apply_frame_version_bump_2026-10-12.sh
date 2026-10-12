#!/bin/bash
# ==============================================================================
# 2026-10-12 frame version bump OLD -> NEW (default v17 -> v18), so the main frame folder carries the version the DO
# received (the v18 hand-off placed today). Jack, in Resampling's window: "make sure to push to V18 for the DO, I approve
# thia action so no need to wait for me" + "is it here ...\data_collection? I dont have it updated".
# The 9 Oct v14 -> v17 script (apply_v17_frame_bump_2026-10-09.sh, rehearsed T1-T3b and run live) with only the dated
# folder names and labels generalised; every step and check is the same.
# Runs against MSNA_WORKSPACE when set (the sandbox test), else the live workspace.
# Steps: 0 pre-checks -> 1 archive copies (frame folder, orchestrator state, OLD RDS, 05's OLD output) -> 2 the five
# family files copied to their _NEW_ names (md5-checked), _OLD_ originals removed from data_collection -> 3 stamp ->
# 4 mirror sync -> 5 selected_clusters_NEW RDS rebuilt -> 6 05 -> 7 verify -> 8 re-seed the orchestrator baseline
# (LAST) -> 9 orchestrator dry run. No frame refresh: the frame content stays exactly what the last accepted run left.
# Any failure restores the frame folder, the orchestrator state, the RDS, 05's output and the mirrors.
# Usage: bash apply_frame_version_bump_2026-10-12.sh [OLD NEW]     (python via PY, default `py`; FAIL_AT=<n> test hook;
#        SKIP_RDS=1 skips step 5, for a sandbox without the GIS inputs)
# ==============================================================================
set -u
WS="${MSNA_WORKSPACE:-/c/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026}"
S1="$WS/1_sampling"
cd "$S1" || exit 9
PY="${PY:-py}"
OLD="${1:-v17}"; NEW="${2:-v18}"
DAY=$(date +%F)
DC="output/data/data_collection"; STATE="output/daily_update_runs/state"
AR="$DC/_archive/${DAY}_pre_${NEW}_bump"; AS="${AR}_orchestrator_state"; AD="$AR/derived"
L="resampling/output/${NEW}_bump_${DAY}/APPLY_$(date +%H%M%S)"
RS=$("$PY" -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.rscript_exe())")
FAM=("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv" "NGA_MSNA_2026_stage2_sampling_frame_%s_WORKING.csv"
     "NGA_MSNA_2026_strata_level_sampling_frame_%s_FULL.csv" "NGA_MSNA_2026_strata_level_sampling_frame_%s_WORKING.csv"
     "NGA_MSNA_2026_cluster_status_%s.csv")
RDS_OLD="output/gis/selected_clusters_${OLD}_current.rds"; RDS_NEW="output/gis/selected_clusters_${NEW}_current.rds"
W05_OLD="resampling/output/NGA_MSNA_2026_stage2_sampling_frame_${OLD}_WORKING_with_accessibility.csv"
W05_NEW="resampling/output/NGA_MSNA_2026_stage2_sampling_frame_${NEW}_WORKING_with_accessibility.csv"
# the other files steps 6 and 9 rewrite (versionless): restored too, so a restore is byte-identical
EXTRA=("resampling/output/strata_representativity_status.csv" "resampling/output/target_sample_representativity_last_run.csv"
       "resampling/output/NGA_MSNA_2026_accessibility_impact_workbook.xlsx" "output/daily_update_runs/LATEST_SUMMARY.json")
# both frame mirrors, archived in step 1 and put back exactly by restore() (12 Oct: the sync writes the whole family into
# dashboard_app too, whose allowlisted copy holds only 4 files - re-running the sync on restore left 3 extra files there)
MIRS=("../2_monitoring/input_data/sampling_frame" "../2_monitoring/dashboard_app/input_data/sampling_frame")
MIRKEY=("mirror_input_data" "mirror_dashboard_app")
m5() { md5sum "$1" | cut -d' ' -f1; }
say() { echo "$*"; echo "$*" >> "$L/APPLY_LOG.md"; }
fv() { "$PY" -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.frame_version())" 2>&1 | tail -1; }
restore() {
  say "**RESTORING** (reason: $*)"
  for f in "${FAM[@]}"; do rm -f "$DC/$(printf "$f" "$NEW")"; done
  for f in $(ls -p "$AR" | grep -v /); do cp -p "$AR/$f" "$DC/$f"; done
  for f in $(ls "$AS"); do cp -p "$AS/$f" "$STATE/$f"; done
  rm -f "$RDS_NEW" "$W05_NEW" "output/gis/_consolidated_clusters_build_log_${DAY}_${NEW}.txt"
  [ -f "$AD/$(basename "$RDS_OLD")" ] && cp -p "$AD/$(basename "$RDS_OLD")" "$RDS_OLD"
  [ -f "$AD/$(basename "$W05_OLD")" ] && cp -p "$AD/$(basename "$W05_OLD")" "$W05_OLD"
  # backed up in step 1 = existed before the bump: put it back; not backed up = the bump created it: remove it
  for f in "${EXTRA[@]}"; do if [ -f "$AD/$(basename "$f")" ]; then cp -p "$AD/$(basename "$f")" "$f"; else rm -f "$f"; fi; done
  for i in 0 1; do   # mirrors back exactly: top-level files the bump created go, the archived ones come back
    m="${MIRS[$i]}"; k="$AD/${MIRKEY[$i]}"; [ -d "$k" ] && [ -d "$m" ] || continue
    for f in $(ls -p "$m" | grep -v /); do [ -f "$k/$f" ] || rm -f "$m/$f"; done
    for f in $(ls "$k"); do cp -p "$k/$f" "$m/$f"; done
  done
  say "restored: version $(fv); WORKING $(m5 "$DC/$(printf "${FAM[1]}" "$OLD")" | cut -c1-8)"
  exit 1
}
# test hook: FAIL_AT=<n> forces a failure (and so a restore) at the start of step n
failat() { [ "${FAIL_AT:-0}" = "$1" ] && restore "forced failure at the start of step $1 (FAIL_AT test)"; return 0; }
mkdir -p "$L" || exit 9
say "# ${OLD} -> ${NEW} frame bump - $(date '+%F %T') - workspace $WS"

# 0. pre-checks
[ "$(fv)" = "$OLD" ] || { say "STOP: frame version is '$(fv)', expected $OLD"; exit 1; }
for f in "${FAM[@]}"; do [ ! -e "$DC/$(printf "$f" "$NEW")" ] || { say "STOP: $(printf "$f" "$NEW") already exists"; exit 1; }; done
[ ! -e output/daily_update_runs/.daily_update.lock ] || { say "STOP: a run holds the lock: $(cat output/daily_update_runs/.daily_update.lock)"; exit 1; }
{ [ ! -e "$AR" ] && [ ! -e "$AS" ]; } || { say "STOP: $AR exists"; exit 1; }
BASE=$("$PY" -c "import json; s=json.load(open('$STATE/frame_state.json')); print(s['working_md5'], s['full_md5'])")
[ "$BASE" = "$(m5 "$DC/$(printf "${FAM[1]}" "$OLD")") $(m5 "$DC/$(printf "${FAM[0]}" "$OLD")")" ] || { say "STOP: the frame is not the baseline ($BASE)"; exit 1; }
CONFL=$(ls -p "$DC" | grep -v / | grep -E -- "-IMPNGA-|-${COMPUTERNAME:-NOHOST}" || true)
[ -z "$CONFL" ] || { say "STOP: OneDrive conflict copies in $DC: $CONFL"; exit 1; }
say "0. pre-checks OK: version $OLD, no $NEW files, no lock, frame = baseline ($BASE), no conflict copies"

# 1. archive (copies; nothing is deleted)
mkdir -p "$AR" "$AS" "$AD" || exit 9
for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$AR/" && [ "$(m5 "$DC/$f")" = "$(m5 "$AR/$f")" ] || { say "STOP: archive $f"; exit 1; }; done
for f in $(ls -p "$STATE" | grep -v /); do cp -p "$STATE/$f" "$AS/" || { say "STOP: archive state $f"; exit 1; }; done
[ -f "$RDS_OLD" ] && { cp -p "$RDS_OLD" "$AD/" || { say "STOP: archive RDS"; exit 1; }; }
[ -f "$W05_OLD" ] && { cp -p "$W05_OLD" "$AD/" || { say "STOP: archive 05 output"; exit 1; }; }
for f in "${EXTRA[@]}"; do [ -f "$f" ] && { cp -p "$f" "$AD/" || { say "STOP: archive $f"; exit 1; }; }; done
for i in 0 1; do
  m="${MIRS[$i]}"; k="$AD/${MIRKEY[$i]}"; [ -d "$m" ] || continue
  mkdir -p "$k" || exit 9
  for f in $(ls -p "$m" | grep -v /); do cp -p "$m/$f" "$k/" || { say "STOP: archive mirror $m/$f"; exit 1; }; done
done
say "1. archived $(ls -p "$AR" | grep -v / | wc -l) frame files + $(ls "$AS" | wc -l) state files + $(ls "$AD" | wc -l) derived -> $AR"

failat 2
# 2. the five family files under the new names, md5-checked; the old names leave data_collection (they are in $AR)
for f in "${FAM[@]}"; do
  o="$DC/$(printf "$f" "$OLD")"; n="$DC/$(printf "$f" "$NEW")"
  cp -p "$o" "$n" && [ "$(m5 "$o")" = "$(m5 "$n")" ] && [ "$(m5 "$n")" = "$(m5 "$AR/$(basename "$o")")" ] || restore "copy $(basename "$o")"
done
for f in "${FAM[@]}"; do rm -f "$DC/$(printf "$f" "$OLD")" || restore "remove $(printf "$f" "$OLD")"; done
[ "$(fv)" = "$NEW" ] || restore "version after the copy is '$(fv)'"
say "2. family copied to _${NEW}_ (md5 = the archived _${OLD}_ files), _${OLD}_ removed from $DC; version now $(fv)"
for f in "${FAM[@]}"; do say "   $(m5 "$DC/$(printf "$f" "$NEW")")  $(printf "$f" "$NEW")"; done

# 3. stamp, 4. mirrors
failat 3
"$RS" scripts/stamp_frame_version.R > "$L/stamp.log" 2>&1 || restore "stamp: $(tail -2 "$L/stamp.log" | tr '\n' ' ')"
grep -q "$(m5 "$DC/$(printf "${FAM[1]}" "$NEW")")" "$DC/_frame_version.txt" || restore "stamp does not carry the ${NEW} WORKING md5"
failat 4
"$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/sync.log" 2>&1 || restore "mirror sync: $(tail -2 "$L/sync.log" | tr '\n' ' ')"
MIR="../2_monitoring/input_data/sampling_frame"
for f in "${FAM[@]:0:4}" _frame_version.txt; do
  n=$(printf "$f" "$NEW"); [ "$(m5 "$MIR/$n")" = "$(m5 "$DC/$n")" ] || restore "mirror $n differs"
done
[ -z "$(ls -p "$MIR" | grep -v / | grep "_${OLD}_" || true)" ] || restore "a _${OLD}_ file is still at the top of $MIR"
say "3-4. stamp $(m5 "$DC/_frame_version.txt" | cut -c1-8); mirrors = master ($(ls -p "$MIR" | grep -v / | grep -c "_${NEW}_") _${NEW}_ files, no _${OLD}_ left at top level)"

failat 5
# 5. RDS (rebuild, never rename)
if [ "${SKIP_RDS:-0}" = "1" ]; then say "5. RDS: SKIPPED (SKIP_RDS=1)"; else
  "$RS" scripts/one_off_analyses/build_consolidated_selected_clusters_2026-10-09_v17.R > "$L/rds.log" 2>&1 || restore "RDS build: $(tail -3 "$L/rds.log" | tr '\n' ' ')"
  [ -s "$RDS_NEW" ] || restore "RDS not written"
  grep -E "DONE\.|Spare register" "$L/rds.log" | while read -r ln; do say "   $ln"; done
  rm -f "$RDS_OLD"
  say "5. $RDS_NEW rebuilt ($(m5 "$RDS_NEW" | cut -c1-8)); $RDS_OLD moved to $AD"
fi

failat 6
# 6. 05 (informational, but its output carries the version in its name)
(cd resampling/scripts && "$PY" 05_build_accessibility_impact_workbook.py) > "$L/05.log" 2>&1 || restore "05: $(tail -3 "$L/05.log" | tr '\n' ' ')"
[ -s "$W05_NEW" ] || restore "05 did not write $W05_NEW"
rm -f "$W05_OLD"
say "6. 05 OK: $(grep -E 'Real achieved \(canonical' "$L/05.log" | head -1 | sed 's/^ *//'); $(grep -E '^Representativity' "$L/05.log" | head -1 | cut -c1-120)"

failat 7
# 7. verify
LEFT=$(ls -p "$DC" | grep -v / | grep "_${OLD}" || true)
[ -z "$LEFT" ] || restore "_${OLD}_ files still at the top of $DC: $LEFT"
NOW="$(m5 "$DC/$(printf "${FAM[1]}" "$NEW")") $(m5 "$DC/$(printf "${FAM[0]}" "$NEW")")"
[ "$NOW" = "$BASE" ] || restore "the ${NEW} WORKING/FULL md5 ($NOW) is not the baseline ($BASE)"
say "7. verify OK: one version ($(fv)), WORKING/FULL = baseline content ($NOW), no _${OLD}_ at top level"

# 8. re-seed the orchestrator baseline (LAST), 9. dry run
failat 8
"$PY" scripts/daily_update/run_frame_and_partner_update.py --reseed-baseline > "$L/reseed.log" 2>&1 || restore "reseed: $(tail -2 "$L/reseed.log" | tr '\n' ' ')"
say "8. baseline re-seeded: $(tail -1 "$L/reseed.log" | cut -c1-160)"
failat 9
"$PY" scripts/daily_update/run_frame_and_partner_update.py --dry-run > "$L/dryrun.log" 2>&1
grep -q "RESULT: OK" "$L/dryrun.log" || restore "dry run: $(grep RESULT "$L/dryrun.log" | tail -1 | cut -c1-200)"
say "9. dry run: $(grep RESULT "$L/dryrun.log" | tail -1 | cut -c1-200)"
say "## done $(date '+%F %T') | version $(fv) | WORKING $(m5 "$DC/$(printf "${FAM[1]}" "$NEW")" | cut -c1-8) FULL $(m5 "$DC/$(printf "${FAM[0]}" "$NEW")" | cut -c1-8) stamp $(m5 "$DC/_frame_version.txt" | cut -c1-8)"
