Prompt for Claude web — paste into the session working from the NGA MSNA 2026 ToR document
=============================================================================================

We've revised the international-border exclusion rule used in the NGA MSNA 2026 sampling
design and need the ToR updated to match. Please update the ToR's methodology section
(and any sample-size tables it carries) as follows.

## What changed

The border-buffer rule that defines the accessible sampling area has changed from a flat
national rule to a **region-differentiated** one, specifically for the Niger border:

- **Niger border**: previously a flat 20km exclusion buffer everywhere. Now **20km in
  North-East** (unchanged — reflects a more acute access-risk profile FACT identified
  specifically on that border segment) and **5km in North-Central and North-West**
  (reduced, after FACT confirmed the tighter access conditions behind the original 20km
  figure don't extend to the Niger border outside the North-East).
- **Chad / Cameroon / Benin borders**: unchanged, 5km nationally, everywhere.
- The other exclusion rule (FACT-assessed inaccessible Admin-3 areas, North-East only) is
  completely unchanged.

In practice this only affects a specific, small set of LGAs: **24 in North-West**
(Katsina: Batsari, Baure, Daura, Jibia, Kaita, Katsina, Mai'adua, Mashi, Sandamu, Zango;
Kebbi: Arewa-Dandi, Bagudo, Bunza, Dandi; Sokoto: Gada, Goronyo, Gudu, Gwadabawa, Illela,
Isa, Sabon Birni, Tangaza; Zamfara: Shinkafi, Zurmi). **North-Central has no LGA within
20km of the Niger border at all**, so the reduction has no practical effect there despite
nominally applying. North-East is completely unaffected (keeps 20km).

The mechanism used to apply this was a **targeted resample of just those 24 LGAs**, not a
full national re-draw — deliberately, so that every other LGA's already-planned specific
sample locations (already distributed to field partners for the pilot) stay exactly as
they were. This is a design-frame change, not a full-pipeline redo.

## Updated sample-size figures

All figures below are already updated in the internal methodology document
(`msna_methodology_summary_portable.md`, Sections 4/7/8) — please pull the ToR's
equivalent tables and text into line with these.

**National, design frame (before the coverage layer)**: 5,779 → **5,864** clusters,
33,010 → **33,020** Non-IDP interviews, 19,236 → **19,734** IDP interviews,
**52,246 → 52,754** total interviews.

**National, coverage-confirmed (WORKING — what's actually being fielded)**: 3,343 →
**3,428** clusters, 17,989 → **17,999** Non-IDP interviews, 13,062 → **13,560** IDP
interviews, **31,051 → 31,559** total interviews. Realized MoE range: 6.1%–9.3% →
**7.1%–9.3%**.

**All of the above change is concentrated entirely in North-West** — North-Central and
North-East's region-level totals are byte-identical to before this revision, for both the
design frame and the WORKING (coverage-confirmed) frame. North-West itself, design frame:
2,715 → **2,800** clusters, 16,218 → **16,228** Non-IDP, 8,418 → **8,916** IDP,
24,636 → **25,144** total. North-West, WORKING: 1,625 → **1,710** clusters, 9,588 →
**9,598** Non-IDP, 5,862 → **6,360** IDP, 15,450 → **15,958** total.

**Practical effect**: IDP reporting becomes possible for the first time in 5 LGAs that
previously had zero IDP sample — Sandamu (84 interviews), Illela (84), Baure (84), Jibia
(78), Mai'adua (60). Two other LGAs in the affected set (Zango; Mobbar in North-East,
unaffected by this specific change) remain unreportable — their recorded IDP sites happen
to sit within 5km of the border too, not just 20km, so this narrower reduction doesn't
reach them. None of the sampling design's 18 already-excluded small-population IDP LGAs
(Kano, Kaduna/Markafi, Kebbi/Gwandu, Niger/Katcha, Niger/Lapai) are affected by this
change at all — none border Niger within 20km.

## What to update in the ToR

1. Wherever the ToR describes the border-buffer exclusion rule (likely alongside the
   accessible-area/sampling-frame description), replace the flat "20km Niger / 5km
   Chad-Cameroon-Benin" language with the region-differentiated version above — 20km
   Niger buffer in North-East, 5km in North-Central and North-West; Chad/Cameroon/Benin
   unchanged at 5km nationally.
2. Update any sample-size summary table(s) in the ToR carrying the national and/or
   North-West totals above to the new figures. If the ToR only carries the
   coverage-confirmed (WORKING) national/regional table, that's the 31,051 → 31,559 /
   North-West 15,450 → 15,958 set above.
3. If the ToR's methodology narrative mentions the IDP-reporting coverage gap or lists
   which LGAs have no IDP sample, note that Sandamu, Illela, Baure, Jibia and Mai'adua
   (Katsina/Sokoto) now DO have IDP reporting where they previously didn't — remove them
   from any "no IDP data" list if one exists.
4. If the assessment-area map figure in the ToR is a copy of
   `output/maps/methodology_map_overview_legend_inset.png` or its caption text, the map
   image itself has NOT yet been regenerated for this revision — flag this to us rather
   than silently updating just the caption; we'll regenerate and send the updated image
   separately if needed.

## One more small update — the below-target-shortfall correction list

The ToR (and the internal methodology doc) separately describes a "28 of 323 Non-IDP
strata needed a below-target-shortfall correction" finding, listed by state and, in the
fuller technical version, by individual LGA. This border-buffer revision changed **which**
28 strata need it, though not the total count: **Sokoto's Tangaza** no longer needs a
supplementary cluster (the buffer relaxation freed enough additional building pool in
Sokoto generally that Tangaza's own gap closed on its own); **Kebbi's Arewa-Dandi** now
needs one it didn't before (one standard 6-household supplementary cluster; its achieved
sample went from 99 to 105, realized MoE from 9.41% to 9.13%). Net effect on the
already-published headline figures: total count stays at **28**, total additional
interviews stays at **254**, and the realized-MoE range across all 28 stays **9.03–9.27%**
— none of those need to change. The only edit needed is the **state list**: "Benue, Borno,
Kogi, Nasarawa, Niger, Plateau, Sokoto, Yobe, Zamfara" → "Benue, Borno, Kebbi, Kogi,
Nasarawa, Niger, Plateau, Yobe, Zamfara" (Sokoto out, Kebbi in), and if the ToR carries the
full per-LGA table, replace the Sokoto/Tangaza row with Kebbi/Arewa-Dandi (ICC 0.06, DEFF
1.30, sample before 99, MoE before 9.41%, sample after 105, MoE after 9.13%).
