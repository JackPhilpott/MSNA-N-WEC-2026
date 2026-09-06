# Resampling decision rules — reference

Living document. This captures the *policy* decisions for how we decide
what happens to each stratum during the 2026-08 accessibility-driven
resample — as distinct from `README.md`, which documents how the scripts
work. Update this file whenever a new rule is decided; don't let a rule
only exist in chat history.

## 1. The unit of decision is the stratum (LGA x pop_type)

Every call below is made per `(State, LGA, Pop type)` — matching the
`Strata Level` sheet in `output/NGA_MSNA_2026_accessibility_impact_
workbook.xlsx` (one row per stratum, currently 324 rows). Not per-ward,
not per-partner — a partner's "case" is a *group* of strata decisions,
grouped for review/rollout convenience, not the decision unit itself.

## 2. Population-remaining threshold — decided 2026-08-29

- **< 10% of the stratum's original design population remains accessible
  → drop the stratum entirely.** No resampling, no partial coverage — same
  treatment as the 2026-07-23 certainty-stratum exclusion (see
  `../CLAUDE.md`), extended here to any stratum this severely affected by
  accessibility exclusions, not just small-population/certainty ones.
- **≥ 10% remains → attempt to cover it.** Aim first for full
  representativity (10% MoE, see §3); where the remaining eligible pool
  genuinely can't get there, settle for indicative rather than dropping
  the stratum.

This is a **revision** of the earlier 2026-07-23 rule ("a stratum that
can't reach 10% MoE gets excluded, never fielded as indicative"). That
rule still applies to a stratum's *original design-time* feasibility
check. It does **not** apply here: this is a stratum that already met
design-time feasibility and has since been degraded by fielding-time
accessibility loss — a different situation, and Jack's explicit call
(2026-08-29) was that "indicative" is an acceptable outcome for this
specific case, once the 10%-population floor is cleared.

Computed off the `Strata Level` sheet's `% of population remaining`
column — this is accessibility-exclusion-driven population loss, not a
submission/deletion count. See §4 for how data-quality deletions factor
in separately.

## 3. Representativity, not the original target — and not progress-to-date either

**Never add resampling clusters just to restore a stratum's original
numeric `target_sample`.** The only trigger for "this stratum needs more
clusters" is: **even if every currently-assigned, accessible cluster's
PRIMARY slots were fully completed, would this stratum still fall short
of 10% MoE?** Only a stratum that fails that test genuinely needs
brand-new resampled clusters — everything else just needs fieldwork to
continue on what's already assigned. Reserve does NOT count toward this
- see why below.

**This took three attempts to get right on 2026-08-29** (worth recording
in full, since each failure mode is easy to repeat): (1) compared against
a DESIGN-target count within the accessible area (`primaries_accessible`)
— not real data at all. (2) Switched to real achieved-to-date
(`load_real_achieved()`, canonical `is_achieved` formula + the deletion
log) — still wrong: comparing against progress-to-date conflates "this
stratum is simply mid-fieldwork" with "this stratum is genuinely
blocked," since any not-yet-finished stratum always looks short against
achieved-to-date. (3) Switched to a capacity ceiling counting BOTH
primary and reserve slots (`n_capacity_accessible`) — also wrong, caught
by Jack: reserve exists as a 1:1 non-response backstop, not routine bonus
sample, and `reserve_households == target_households` uniformly
(2026-07-22c/08-04 design decision, applies project-wide, not
concentrated in a few clusters). Treating reserve capacity as part of the
achievable ceiling would silently require exhausting reserves as standard
practice to avoid a resample — which makes actual achieved sample size
depend on which clusters happen to still have reserve capacity available,
breaking PPS's core assumption that every selected cluster contributes
the *same* target size. A real spatial/coverage bias risk, not a paperwork
concern.

**Final, settled basis**: the achievable ceiling is **PRIMARY ONLY** —
sum of every accessible cluster's `n_primary_accessible` (primary
household rows sitting in an accessible ward), fed into `realized_moe()`
as `primary_ceiling_accessible`. This is exactly the ceiling the original
design already assumed, just scoped to the currently-accessible portion —
reserve stays a backstop, never counted toward "do we need to resample."
Both real achieved-to-date and the primary+reserve figure are still
computed and kept as **reference-only** columns ("Achieved samples (real,
post-deletion, progress-to-date)" and "Achievable ceiling (primary+
reserve, reference only)") — useful context, neither drives the decision.
The primary+reserve column does surface one real, deliberately-unused
lever: a stratum where it reaches 10% MoE but the primary-only column
doesn't could in principle be closed by asking its partner to fully work
their reserve list instead of resampling — not adopted as a standard
practice here, for the PPS-bias reason above, but visible if a one-off
case ever needs it.

`Feasibility`/`Additional clusters needed for 10% MoE` in
`05_build_accessibility_impact_workbook.py` (~line 445 onward):
`additional_clusters_needed = 0` whenever `moe_updated <= TARGET_MOE_PCT`
(10%) computed against `primary_ceiling_accessible` — independent of
`target_sample`, progress-to-date, and reserve capacity. Don't build any
of those three into this decision again.

`Feasibility` values and what each means for the decision:
| Value | Meaning | Action |
|---|---|---|
| `Already at/under target` | Projected MoE already ≤10% | None — resample not needed |
| `Closeable with a modest top-up` | Needs ≤50% of the remaining eligible pool | Resample the needed clusters |
| `Closeable only via most of remaining pool (near-full-enumeration)` | Needs >50% of what's left | Resample, flag as tight |
| `Not closeable - exceeds remaining pool (recommend indicative)` | Even the full remaining pool doesn't reach 10% MoE | Resample the full remaining pool, report indicative |
| `Not closeable - no remaining pool left` | Zero eligible pool remains | Report indicative on current sample, no resample possible |

## 4. Data-quality deletions — wired in 2026-08-29

Accessibility exclusions and data-quality deletions are **two separate
inputs to the same per-stratum decision**, not the same thing:
- Accessibility: which *wards* are excluded (source: the accessibility
  reporting workflow, `master_accessibility_status_ward_level.csv`).
- Data quality: which *already-submitted interviews* get treated as not
  achieved (source: `2_monitoring/cleaning/real/handoff_for_resampling/
  revised_deletion_log_for_resampling_2026-08-29.csv`, 463 rows).

Ingested in `05_build_accessibility_impact_workbook.py`'s
`load_real_achieved()`: every uuid in the deletion log is treated as not
achieved regardless of what `real_submissions.csv` shows, on top of the
canonical `is_achieved` formula (§5). Categories in the 2026-08-29 file:
`duration_under_20` (402 + 13 already-flagged as `duration_under_30`),
`fcs_zero` (29), `no_consent` (17, already excluded via
`interview_outcome` anyway), `duplicate_point` (2, caught incidentally via
duration overlap only).

**Deliberately excluded from this file, not yet actionable** —
absence here does NOT mean confirmed fine:
- `duplicate_point` (446 rows) and `listing_missing` (225 rows, 29 IDP
  clusters) — under active recovery work in `2_monitoring` (GPS
  reassignment, listing fill-in); don't resample against these yet, a
  meaningful share is expected to come back.
- Duration 20–30min band (~1,000 rows) — still an open statistical
  question, weaker corroboration than the <20min floor.
- The ~880 newest submissions haven't been assessed against the duration
  floor at all yet (no extracted audit trail).

**This file is a floor, not final** — expect a revised version as the
above resolves. Note the deletion log only affects the *informational*
real-achieved-to-date column (§3) — it does **not** feed the primary-only
capacity ceiling that actually drives the resampling decision (the
ceiling is available PRIMARY slots, unaffected by whether a past
submission was later deemed invalid). A revised deletion log therefore
won't by itself change §6's numbers; what *would* change them is the
`duplicate_point`/`listing_missing` recovery work resolving (a recovered
GPS point or filled listing can change which clusters/wards count as
accessible) — rerun `run_accessibility_refresh.py` and re-check after
that lands, not after a deletion-log-only update.

## 5. Submission data is live — always refresh before deciding

`real_submissions.csv` (`2_monitoring/dashboard_app/data/real_
submissions.csv`, what `05_build_accessibility_impact_workbook.py`'s
"Collected samples" figures are built from) changes daily as fieldwork
continues. **Before computing or re-checking any stratum's feasibility,
run `2_monitoring/cleaning/real/prep_real_submissions.R` directly** (not
a full `deploy_dashboard.R` — that also redeploys the live dashboard,
which is being held off deliberately during this resampling push) to
pull current KoBo data, then rerun `1_sampling/resampling/scripts/run_
accessibility_refresh.py` so the impact workbook reflects it. A decision
made against stale submission data is exactly the kind of thing this
whole framework is trying to avoid.

## 6. Partner rollout order — set 2026-08-29, subject to change

Priority order once ready to start notifying field teams: **INTERSOS →
IMC → FACT**. FACT and FHI 360 are excluded from this round — both are
currently revising/re-evaluating their own coverage areas based on our
recommendations, so a standard resample-and-notify pass for them right
now would likely be immediately stale. Revisit their place in the order
once their revisions land.

This ranking is by total "additional clusters needed" (§3) across each
partner's strata. **Final, primary-only-ceiling-based figures, 2026-08-29**
(see §3 for the full three-attempt history): **INTERSOS 27 clusters/4
strata, IMC 24/6, FACT 341/51** (deferred per above). Of 312 attempt-
strata nationally, 65 genuinely need new clusters even at full completion
of currently-assigned primaries; 247 already reach 10% MoE once fully
fielded.

For reference, the two wrong intermediate figures (don't use these -
kept only so they're not accidentally recomputed and reported again):
real-achieved-to-date-based had INTERSOS 101/7, IMC 44/6, FACT 1,232/129;
primary+reserve-ceiling-based had INTERSOS 14/2, IMC 0/0, FACT 162/19.

## 7. Where this is actually computed

- Per-stratum population/area/MoE/feasibility: `resampling/scripts/05_
  build_accessibility_impact_workbook.py`, `Strata Level` sheet.
- Ward-level accessibility status feeding it: `resampling/scripts/04_
  build_master_accessibility_status.py` → `analysis_accessible_area_
  layer.R`.
- Full refresh, in order: `resampling/scripts/run_accessibility_
  refresh.py`.
- Real achieved / capacity ceiling / deletion-log ingestion:
  `load_real_achieved()` and `build_cluster_level()`'s
  `n_primary_accessible` (the decision-driving primary-only ceiling,
  summed as `primary_ceiling_accessible`) and `n_capacity_accessible`
  (the reference-only primary+reserve figure) in `05_build_accessibility_
  impact_workbook.py`.
- Live submission data refresh: `2_monitoring/cleaning/real/
  prep_real_submissions.R` (run before any of the above, per §5).
