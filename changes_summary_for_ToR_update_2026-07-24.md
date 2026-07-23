# Summary of sampling design changes — for ToR update

**Purpose of this document.** The MSNA N-WEC 2026 sampling frame was originally submitted 2026-07-15 and has since been revised three times (2026-07-22, 2026-07-23, 2026-07-24). This document summarizes *what changed and why*, so it can be used alongside the current `msna_methodology_summary_portable.md` to update the assessment's Terms of Reference (ToR). It does not restate the full methodology — for that, see the accompanying methodology document, whose section numbers are referenced throughout below. Use this document to find what needs updating; use the methodology document for the exact language/figures to update it with.

**How to use this alongside the methodology document:** for each change below, check whether the ToR contains matching language (sample size figures, population terminology, weighting description, coverage claims, etc.) and update it to match the current methodology document's corresponding section. A checklist of specific things to search the ToR for is at the end of this document.

---

## Current authoritative figures (as of 2026-07-24)

| Metric | Value |
|---|---|
| Total achieved sample (primary interviews) | 52,246 |
| — Non-IDP | 33,010 |
| — IDP | 19,236 |
| Total planned interview rows (primary + reserve) | 86,394 |
| Total clusters | 5,779 |
| Total strata | 565 (323 Non-IDP + 242 IDP) |
| Active IDP strata | 224 (242 minus 18 excluded — see "Certainty-stratum exclusion" below) |
| States / regions covered | 14 states across North-West, North-East, North-Central |
| Confidence level / target margin of error | 90% / 10% (per stratum, PPS strata only — see exclusion note) |
| Design effect (DEFF) | 1.30 (ICC = 0.06, cluster size m = 6 households — constant across the entire design) |

If the ToR currently states different totals (most likely stale, dating to the original 2026-07-15 submission or the 2026-07-22 revision), replace them with the figures above. The regional breakdown (North-Central / North-East / North-West) is in methodology doc §7.

---

## Change 1 — Population terminology: "Host" → "Non-IDP" (2026-07-22)

**What changed:** every use of "host" as a population-group label (data values, code, documentation, map labels) was renamed to "Non-IDP". The two population groups sampled are now consistently called **IDP** and **Non-IDP**.

**Why:** "host" is ambiguous in humanitarian usage — it also describes "a host community", one of the IDP sub-categories DTM records (see Change 3 below). Framing the two population groups as IDP/Non-IDP avoids that collision.

**ToR action:** search the ToR for "host population" / "host community" used to mean *the non-displaced comparison group* and replace with "Non-IDP". Where the ToR discusses IDPs living within host communities (a genuinely different, IDP-side concept — see Change 3), leave that language as-is; only the population-group label needs replacing, not every use of the word "host".

---

## Change 2 — MoE correction mechanism replaced (2026-07-22)

**What changed:** the mechanism used to fix Non-IDP strata whose delivered sample fell short of its calculated target.
- **Old:** a hardcoded list of 10 conflict-affected LGAs had their cluster size blanket-raised from 6 to 7 households (+421 interviews for those 10 alone).
- **New:** every Non-IDP stratum (not just a fixed list) is checked against the same rule — achieved sample below target — and each one that fails gets the minimum number of new supplementary clusters (still at 6 households/cluster) needed to close its own specific gap.
- **Result:** 28 strata corrected (not 10), for 254 total additional interviews, converging to a tight 9.03–9.27% realized margin of error.

**Why:** the old approach over-corrected — raising cluster size also raises the design effect, so part of every extra interview serviced worse precision rather than shrinking MoE. The new mechanism is minimal and generically defined (see methodology doc §4).

**ToR action:** if the ToR references the "10 boosted LGAs" or an m=7 cluster size anywhere, replace with: 28 Non-IDP strata received minimal supplementary clusters (still m=6) to reach target; see methodology doc §4 for the full list and rationale.

---

## Change 3 — IDP `idp_population_category` field added (2026-07-22) — prep work, NOT a field-methodology change yet

**What changed:** every IDP record now carries a category — **"idps in camp"** or **"idps in host"** (i.e. host community) — derived from IOM DTM's own "Population Category" field. Returnee-classified sites remain excluded from the frame, unchanged.

**Important — what did *not* change:** this is data preparation only. The actual field procedure is still identical for both categories today: every IDP cluster uses the same 150-metre single-radius, on-site household-listing method. A future decision to use different field methods for camp vs. host-community sites (e.g. a randomised walk for camps vs. a full listing for host-community sites) has **not been made or implemented** — see "Still pending" section below.

**ToR action:** if the ToR describes or implies IDP data collection is already split by camp/host-community methodology, correct this — it is not yet the case. If the ToR is silent on this, no action needed beyond being aware it's an open design question, not a settled one.

---

## Change 4 — Certainty-stratum exclusion (2026-07-23) — the most consequential change for coverage claims

**What changed:** certainty strata (IDP populations too small to sample — every eligible site is enumerated rather than probability-sampled) are now excluded from the sample **entirely** (zero clusters, zero interviews) if even full enumeration can't project to the assessment's 10% MoE target. Previously, such strata were still fielded and their findings reported as "indicative."

**Why:** unlike a probability (PPS) stratum falling short of target, a certainty stratum has no supplementary-cluster option — every eligible site is already included, so there's nowhere left to draw an additional cluster from. HQ judged the field effort of visiting these tiny-population sites wasn't worth data that could only ever be indicative.

**Result on current data — all 18 currently-eligible certainty strata fail this check and are excluded:**
- **Kebbi State loses IDP coverage entirely** — its only IDP stratum (Gwandu) is excluded, so no IDP estimate of any kind (LGA, state, or regional) is possible for Kebbi under this design.
- Kano retains 16 of 30 IDP LGAs (14 excluded).
- Niger retains 11 of 13 IDP LGAs (2 excluded).
- Kaduna retains 21 of 22 IDP LGAs (1 excluded).
- No North-East state is affected.
- Total: −362 DTM-recorded IDP households, −23 sites, −138 interviews removed from what would otherwise have been fielded.

**This is a genuine coverage gap, not a precision caveat** — for the 18 excluded LGAs, no IDP indicator of any kind can be reported (not even "indicative"), because no data will be collected there at all. See methodology doc §5 ("Excluded strata: the certainty-stratum coverage gap") for the full affected-LGA list and reporting guidance.

**ToR action — this is likely the single most important update:**
- If the ToR makes any claim about IDP coverage being complete/comprehensive across all assessed LGAs or states, this needs qualifying — **Kebbi State has no IDP coverage**, and 17 further LGAs across Kano/Niger/Kaduna have no IDP coverage specifically (their Non-IDP coverage is unaffected).
- If the ToR previously described small-population IDP strata as reported "with reduced precision" or "indicatively," update this — those strata are no longer fielded at all, not fielded-but-imprecise.
- Any total sample size or LGA-count figures in the ToR should reflect the reduced totals in the table above.

---

## Change 5 — Weighting methodology deferred, weighting columns removed from deliverables (2026-07-24)

**What changed:** the methodology document's weighting section, previously a detailed description of the exact design-weight formula (Stage 1 × Stage 2 selection probabilities), has been replaced with a brief, generic statement: a statistically sound design weight will be calculated once data collection is complete, taking into account the sampling methodology and the actual achieved samples. The design-weight columns (`psu_probability`, `ssu_probability`, `base_weight`) have also been removed from the delivered sampling frame files for the same reason.

**Why:** the IDP Stage 2 field-methodology decision referenced in Change 3 (camp vs. host-community; listing vs. randomised walk) is still unresolved, and will directly change the within-cluster selection-probability formula for IDP records specifically. Publishing exact weighting mechanics now would describe a formula that's about to change once that decision lands.

**ToR action:** if the ToR contains a detailed weighting-methodology section (formulas, specific probability calculations), **replace it with a brief, forward-looking statement** matching the language above — do not carry over old formula-level detail, since it may not hold once the IDP field methodology is finalised. A full weighting methodology will be issued as a follow-up once that decision is made and real data collection outcomes are available.

---

## Change 6 — Minor data-dictionary fixes (2026-07-23/24) — likely not ToR-relevant

Three small accuracy fixes to internal documentation/data-dictionary text, unlikely to affect ToR language but noted for completeness:
- A redundant, mislabeled `uuid` column was removed from the delivered files (it held a non-unique hexagon index, not a location identifier — the real identifiers were already in other columns).
- The "below-target cluster" flag's description was corrected to note it behaves differently for Non-IDP (caps the delivered sample) vs. IDP (doesn't cap — IDP always plans its full target; the flag is just a heads-up).
- None of these changed any sample composition, coverage, or figure — data-dictionary corrections only.

---

## Still pending — do not describe as finalised in the ToR

**IDP Stage 2 field-methodology split** (camp = randomised walk vs. host-community = household listing) is an **open design question, not yet decided or implemented**. `idp_population_category` (Change 3) is recorded and ready for this, but every IDP cluster today still uses one uniform 150m-radius, on-site-listing method regardless of category. This will also affect:
- The exact IDP household-selection description in methodology doc §3.
- The IDP weighting formula (Change 5), once decided.
- Two IDP example maps in the methodology document, which currently still depict the single uniform method.

If the ToR is being updated now, phrase anything touching IDP field procedure or IDP weighting as "to be finalised" rather than describing a specific split — describing it as settled would be premature and will need correcting again once the decision is made.

---

## Checklist: things to search the ToR for

- [ ] "host" used as a population-group label → "Non-IDP" (Change 1)
- [ ] Any specific total sample size, cluster count, or LGA count → update to current figures (table at top)
- [ ] "10 LGAs" / cluster size "7" / m=7 boosted-strata language → replace with 28-strata minimal-correction description (Change 2)
- [ ] Any claim of complete/comprehensive IDP coverage across all LGAs or states → must note Kebbi has none, 17 further LGAs across 3 states have none (Change 4)
- [ ] "indicative" reporting language for small IDP populations → these strata are now excluded, not fielded-but-flagged (Change 4)
- [ ] Detailed weighting formula/methodology text → replace with brief forward-looking statement (Change 5)
- [ ] Any description of a camp vs. host-community field-methodology split as already implemented → it is not; mark as pending (see "Still pending")
- [ ] Design parameters (90% CI, 10% MoE, ICC 0.06, m=6, DEFF 1.30) → unchanged, should still match if already correct
