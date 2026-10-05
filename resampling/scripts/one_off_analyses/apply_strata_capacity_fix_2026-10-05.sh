#!/bin/bash
# ==============================================================================
# 2026-10-05 LIVE apply of the strata capacity fix (Jack's go in Resampling's window ~06:25, "Strata capacity fix":
# staged + sandbox-tested first, "before" report posted ~08:40). Unused spare clusters stop counting as design
# capacity: the patched frame_status.R / refresh / merge (from the tested scratchpad copies), then the strata files
# back to their pre-spares values (sandbox: strata WORKING d0020472, strata FULL cc0682ee, nothing else changes).
# Any failure in steps 2-5 restores the archived frame, orchestrator state and the three scripts.
# Usage (from anywhere): FIX_DIR=<tested patched copies> bash apply_strata_capacity_fix_2026-10-05.sh
# ==============================================================================
set -u
S1="/c/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
cd "$S1" || exit 9
FX="${FIX_DIR:?set FIX_DIR to the folder with the tested patched copies}"
DC="output/data/data_collection"
STATE="output/daily_update_runs/state"
AR="$DC/_archive/2026-10-05_pre_strata_capacity_fix"
AS="${AR}_orchestrator_state"
V15="$DC/_archive/2026-10-05_pre_spares"
L="resampling/output/spares_2026-10-05/STRATA_FIX"
RS=$(python -c "import sys; sys.path.insert(0,'scripts/shared'); import msna_paths; print(msna_paths.rscript_exe())")
SCRIPTS="scripts/shared/frame_status.R scripts/field_guide_production/refresh_working_frame_daily.R resampling/scripts/merge_partner_resample_batch.R"
m8() { md5sum "$1" | cut -c1-8; }
say() { echo "$*"; echo "$*" >> "$L/APPLY_LOG.md"; }
restore() {
  say "**RESTORING** (reason: $*)"
  for f in $(ls -p "$AR" | grep -v /); do cp -p "$AR/$f" "$DC/$f"; done
  for f in $(ls "$AS"); do cp -p "$AS/$f" "$STATE/$f"; done
  for s in $SCRIPTS; do cp -p "$AR/scripts/$(basename "$s")" "$s"; done
  "$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/restore_sync.log" 2>&1 || say "restore: mirror sync FAILED"
  say "restored: strata W $(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv), strata F $(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv)"
  exit 1
}
mkdir -p "$L" || exit 9
say "# Strata capacity fix - live apply $(date '+%F %T')"
# 0. pre-checks: the live state the sandbox test was run on, and live scripts unchanged since the patched copies
[ "$(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv)" = 7268174a ] || { say "STOP: WORKING not 7268174a"; exit 1; }
[ "$(m8 $DC/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv)" = 749b6b1c ] || { say "STOP: FULL not 749b6b1c"; exit 1; }
[ "$(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv)" = 02393353 ] || { say "STOP: strata WORKING not 02393353"; exit 1; }
[ "$(m8 $DC/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv)" = 9b6e4c16 ] || { say "STOP: strata FULL not 9b6e4c16"; exit 1; }
[ ! -e output/daily_update_runs/.daily_update.lock ] || { say "STOP: an orchestrator run holds the lock"; exit 1; }
{ [ ! -e "$AR" ] && [ ! -e "$AS" ]; } || { say "STOP: $AR exists"; exit 1; }
for s in $SCRIPTS; do [ "$(m8 "$s")" = "$(m8 "$FX/orig/$(basename "$s")")" ] || { say "STOP: $s changed since the tested copy was made"; exit 1; }; done
[ -f scripts/shared/spare_clusters.R ] || { say "STOP: scripts/shared/spare_clusters.R missing"; exit 1; }
say "0. pre-checks OK"
# 1. archive
mkdir -p "$AR/scripts" "$AS" || exit 9
for f in $(ls -p "$DC" | grep -v /); do cp -p "$DC/$f" "$AR/" && [ "$(m8 "$DC/$f")" = "$(m8 "$AR/$f")" ] || { say "STOP: archive $f"; exit 1; }; done
for f in $(ls -p "$STATE" | grep -v /); do cp -p "$STATE/$f" "$AS/" || { say "STOP: archive state $f"; exit 1; }; done
for s in $SCRIPTS; do cp -p "$s" "$AR/scripts/" || { say "STOP: archive $s"; exit 1; }; done
say "1. archived $(ls -p "$AR" | grep -v / | wc -l) frame files, $(ls "$AS" | wc -l) state files, 3 scripts -> $AR"
# 2. install the tested scripts
for s in $SCRIPTS; do cp "$FX/$(basename "$s")" "$s" || restore "install $s"; done
say "2. installed: $(for s in $SCRIPTS; do echo -n "$(basename "$s") $(m8 "$s"); "; done)"
# 3. strata FULL back to v15 (verify-then-restore), then the patched refresh (strata WORKING; frame workbook)
"$RS" resampling/scripts/one_off_analyses/recompute_strata_full_capacity_unused_spares_2026-10-05.R "$V15" --write > "$L/oneoff.log" 2>&1 || restore "one-off failed: $(tail -2 "$L/oneoff.log" | tr '\n' ' ')"
tail -3 "$L/oneoff.log" >> "$L/APPLY_LOG.md"
"$RS" scripts/field_guide_production/refresh_working_frame_daily.R > "$L/refresh.log" 2>&1 || restore "refresh failed"
grep -E "Spare clusters" "$L/refresh.log" >> "$L/APPLY_LOG.md"
# 4. verify
for pair in "NGA_MSNA_2026_strata_level_sampling_frame_v14_WORKING.csv d0020472" "NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv cc0682ee" \
            "NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv 7268174a" "NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv 749b6b1c" \
            "NGA_MSNA_2026_cluster_status_v14.csv 1e325962" "buffer_cluster_register.csv 7721a420"; do
  set -- $pair; [ "$(m8 "$DC/$1")" = "$2" ] || restore "verify: $1 is $(m8 "$DC/$1"), expected $2"
done
say "4. verified: strata W d0020472, strata F cc0682ee (= v15); WORKING 7268174a, FULL 749b6b1c, cluster_status 1e325962, register 7721a420 unchanged"
# 5. stamp + mirrors (frame)
"$RS" scripts/stamp_frame_version.R > "$L/stamp.log" 2>&1 || restore "stamp failed"
"$RS" resampling/scripts/sync_sampling_frame_mirrors.R > "$L/sync.log" 2>&1 || restore "mirror sync failed"
say "5. stamped ($(m8 $DC/_frame_version.txt)) and mirrors synced"
# 6. 05 (non-fatal, as in the orchestrator) + re-baseline (harmless: stage2 md5s unchanged)
(cd resampling/scripts && python 05_build_accessibility_impact_workbook.py) > "$L/05.log" 2>&1 || say "05 FAILED (non-fatal) - see $L/05.log"
grep -E "^Representativity" "$L/05.log" | cut -c1-140 >> "$L/APPLY_LOG.md"
python scripts/daily_update/run_frame_and_partner_update.py --reseed-baseline > "$L/reseed.log" 2>&1 || say "reseed FAILED - see $L/reseed.log"
tail -1 "$L/reseed.log" >> "$L/APPLY_LOG.md"
say "## done $(date '+%F %T')"
