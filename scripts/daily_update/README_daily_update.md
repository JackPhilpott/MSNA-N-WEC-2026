# Daily frame + partner-folder update (Phase 2)

`run_frame_and_partner_update.py` refreshes the WORKING sampling frame from the
day's submissions and updates every partner folder's workbooks and KML maps. It
is **Phase 2** of the data officer's daily run. 2_monitoring's launcher calls it
after Phase 1 (data refresh + dashboard deploy) has finished cleanly. Nothing
here can affect the dashboard deploy.

The guiding rule: **partners only ever see a complete, checked set of files.**
If anything is doubtful, nothing is published and partners keep yesterday's
files. That is safe: their to-do lists are one day stale, never wrong.

## How to run it

The launcher runs this for you. To run it by hand, open a terminal anywhere:

```
<python> "<workspace>\1_sampling\scripts\daily_update\run_frame_and_partner_update.py"            # the real run
<python> "<workspace>\1_sampling\scripts\daily_update\run_frame_and_partner_update.py" --dry-run  # rehearsal, writes nothing live
<python> "<workspace>\1_sampling\scripts\daily_update\run_frame_and_partner_update.py" --no-publish  # frame only, partner folders untouched
<python> "<workspace>\1_sampling\scripts\daily_update\run_frame_and_partner_update.py" --check-env # can this laptop run it?
```

`<workspace>` is the `MSNA N-WEC 2026` folder. The script finds it itself, from
the `MSNA_WORKSPACE` environment variable if that is set, otherwise from its own
location. Optional variables are `MSNA_PYTHON`, `MSNA_RSCRIPT` and
`MSNA_PKG_ROOT` (the live `NGA MSNA 2026 Package` folder, if it is not beside
`4. Data` in the synced library).

The result is always in `1_sampling\output\daily_update_runs\LATEST_SUMMARY.json`,
with a full log and every check's detail in that run's folder.

| Exit | Status | What it means for partners |
|---|---|---|
| 0 | OK | Published, or there was nothing new. A dry run exits 0 when it would publish. With `--no-publish` the message says "publish held": frame refreshed, partners untouched. |
| 0 | NO_CHANGE | Every input the chain reads is byte-identical to the last published run's (submissions, deletions overlay, FULL/WORKING/strata frames, accessibility master, cluster exclusion lists, targets, partner coverage workbook, IDP backup points); nothing was touched. |
| 1 | BLOCKED | A hard check said no. Partners keep yesterday's files. If the block was in the frame, the frame was put back automatically. |
| 2 | ERROR | The run could not finish: a missing program, a crash, or another run still holding the lock. Same guarantee: partners keep yesterday's files. |

## What one run does

1. **Preflight**:
   - Python with openpyxl and R with dplyr/readr are present.
   - Every input file exists.
   - There are no OneDrive conflict copies (`NAME-COMPUTERNAME.csv`) beside the frame or the data.
   - The live partner folder is reachable.
   - The frame is exactly the one the last accepted run left behind.
2. **Archive the frame** (all 12 files in `output\data\data_collection`) to `_archive\<date>_daily_update_<run>\`, with MD5 sums.
3. **Refresh WORKING** (`refresh_working_frame_daily.R`, including its Step 0 accessibility resweep).
4. **Hard frame checks**; on any failure the archived frame is restored and verified:
   - FULL and strata-FULL are unchanged. No accessibility or design change is expected in a week without resampling.
   - Every WORKING row is an exact copy of its FULL row, with no duplicates.
   - **Every WORKING change is explained.** A Non-IDP household leaves the to-do list only if it is now achieved, and comes back only if it stopped being achieved (a confirmed deletion). An IDP slot leaves only if that cluster's achieved count for primary/reserve went up, and comes back only if it went down. This mirrors `compute_achieved_lookup()` exactly.
   - No achieved Non-IDP household is still on a to-do list.
   - Strata-WORKING and cluster_status keep the same rows; only `achieved_sample`, `achieved_clusters`, `realized_moe_pct`, `n_achieved` and `status` may move.
5. **Stamp + mirror sync** to 2_monitoring, with the mirror MD5-checked against the master.
6. **Partner packages into staging**: a temp folder, never the live one.
   - The builder writes KMLs and workbooks there. Its own UUID reconciliation must PASS, and there must be no stale folders.
   - The daily workbook refresh then runs on the same staging, plus the **MAP CHECK**: every to-do point in every staged workbook must be on that partner's staged map.
7. **Validity gate** (validity_checks `--gate`) on staging: package alignment, oversampling roll-up and three-way reconciliation against the dashboard. Any FAIL blocks; WARN is allowed.
8. **Publish** (real runs only):
   - Only files whose content changed are copied, each one backed up first to `resampling\output\_pkgbak\<run>_daily\` and MD5-verified after copying.
   - If any live file is open (e.g. in Excel), nothing is copied.
   - If anything fails part-way, every step is undone (all-or-nothing).
   - Files the build no longer produces (e.g. an LGA's KML once everything in it is collected) are moved into an `_archived_not_produced_<date>` folder beside them. A file someone else edited is never moved.
9. **05 representativity workbook**: informational only. If it fails, its previous outputs are put back and the run still exits 0, with a warning.

A **dry run** builds a sandbox copy (about 350 MB, under `%TEMP%\msna_daily`) of
everything the chain reads and runs steps 1-7 there. It then writes
`publish_plan.csv` (what would change live) and deletes the sandbox. It never
writes to the frame, the mirrors or a partner folder.

## When it blocks: what to do

| Failed check | Likely cause | Action |
|---|---|---|
| The frame is not the one the last accepted run left | Someone changed the frame outside this script, e.g. a resampling merge | Do not reseed blindly. Tell Jack / Resampling. After a deliberate merge they run `--reseed-baseline`. |
| FULL frame unchanged | The master accessibility file changed, so the resweep flipped wards | Accessibility work needs Jack. Partners keep yesterday's files. |
| Every WORKING change is explained | WORKING moved for a reason other than submissions (exclusion list, coverage, a bug) | `working_changes_UNEXPLAINED.csv` lists the rows. Send it to Jack / Resampling. |
| MAP CHECK | A workbook lists a to-do point its map lacks | Builder problem. Send the run folder. |
| Validity gate | The staged packages disagree with the frame or the dashboard | `gate_result.csv` says which module and check. Send it. |
| No live partner file is open/locked | A workbook is open in Excel somewhere | Close it and re-run. |
| No more no-longer-produced files than allowed | Many partner files would disappear at once | Structural change; send the run folder. |
| Lock held (ERROR) | Another run is still going, or one crashed | Wait. If no run is going, delete `daily_update_runs\.daily_update.lock`. |

## Options for Jack: how strict to be

Set `"guard_level"` in a JSON file passed with `--config`
(`daily_update_config.example.json` shows every setting).

| Level | WORKING changes | FULL may change | Gate | MAP CHECK | Mass disappearance cap |
|---|---|---|---|---|---|
| **strict** (default) | every change must be explained | no | required | required | 25 files |
| standard | up to 50 unexplained rows tolerated (still reported) | no | required | required | 60 files |
| lenient | reported only | yes (reported) | skipped if it can't run; a FAIL still blocks | reported only | 200 files |

**Recommendation: strict for the DO's week.** The checks are mechanical, and
every one has a concrete reason that only someone who can judge it should
override. A blocked day costs partners one day of staleness. A wrong day can put
an achieved household back on a to-do list, or drop a pending one. If strict
blocks repeatedly for a benign reason, switch that day to `standard`, never
`lenient`.

**Frame-only mode (`--no-publish`, built 4 Oct):** the real refresh, checks, stamp,
mirror sync, staged build and gate, but no partner file is touched. Use it when
OneDrive is not syncing (a publish would sit unsent on this laptop and can make
conflict copies when sync resumes), or on a night where one publish should go out at
the end. The frame is accepted as usual; the next normal run rebuilds and publishes
(it never reports NO_CHANGE because of a held publish).

**SharePoint-synced partner folders (5 Oct).** SharePoint writes its own library metadata
into Office files it stores (customXml parts, custom properties), and OneDrive syncs that
version back. So an Office file (`.xlsx`, `.docx`, `.pptx`) counts as unchanged when all of
its content parts match: sheets, strings, styles and media. Every other file must match
byte for byte. The final check after publishing runs inside the all-or-nothing block: a
real mismatch rolls the whole publish back, and partners keep yesterday's files.

**A structural night (e.g. a partner reallocation), built 4 Oct.** When partners lose
LGAs, their old files stop being produced, so the "no-longer-produced" guard blocks
(correctly). For that one run, pass a config with three settings:

- `archive_leftover_package_files: false`: the old folders stay in place.
- `max_leftover_files`: the exact count seen in the rehearsal.
- `allowed_leftover_prefixes`: the package-relative folders or files expected to stop.

Any other file that stops being produced still fails the run. The config loader now
rejects unknown keys, so a misspelt setting cannot be silently ignored.

Another softer variant (not built; say if you want it):
- **Workbooks-only publish:** publish the 17 summary workbooks even when only the KML gate fails, since workbooks carry the to-do lists.

## After a resampling round (e.g. the weekend top-up)

The baseline (`daily_update_runs\state\`) records which frame and submissions the
last accepted run used. A merge of new clusters changes WORKING in ways no
submission explains, so the next daily run would (correctly) block. After every
deliberate merge plus the usual post-merge refresh, Resampling runs once:

```
<python> run_frame_and_partner_update.py --reseed-baseline
```

It refuses if WORKING still lists an achieved household, i.e. if the frame was
not built from the current submissions.

## Files

- `state\frame_state.json` + `achieved_snapshot.csv`: the baseline WORKING changes are explained against.
- `state\last_published_manifest.csv`: every partner file the build produces, with its MD5 when last published.
- `state\publish_state.json`: inputs of the last published run (for NO_CHANGE).
- `<run>\run_log.txt`, `summary.json`, `step_*.log`, `working_changes.csv`, `publish_plan.csv`, `gate_result.csv`.
- Retention: **nothing is deleted by default** (run folders, frame archives and package backups are all kept; about 1 GB a week, mostly the 117 MB daily frame archive). Only temporary staging and dry-run sandbox copies under `%TEMP%\msna_daily` are cleaned up after a successful run. To prune, set `keep_runs` / `keep_frame_archives` / `keep_package_backups` to a number in the config.

Requirements: `requirements_python.txt` (Python 3.10+, openpyxl) and
`install_r_packages.R` (R 4.3+, dplyr, readr). The gate and the dashboard list
their own packages.
