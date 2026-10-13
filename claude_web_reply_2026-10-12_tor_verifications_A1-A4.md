Reply for Claude web: ToR verifications A1–A4, and the status of maps B1–B2 (NGA2605 MSNA, 12 Oct 2026)
==================================================================================================

Design facts only, taken from the sampling files and code. Figures are copied exactly. Where something isn't in the files, it says so.

---

## A1. Backup GPS points (IDP in-camp clusters)

**Every in-camp IDP cluster in the design has a backup point.**
- File: `idp_camp_backup_points.csv` (sampling frame folder; the same data is on the "IDP Camp Backup Points" sheet of the sampling-frame workbook).
- 86 rows; `backup_gps_lat` / `backup_gps_lon` are filled on all 86 (0 missing).
- In the frame, all 83 in-camp clusters selected by the July design method have one.
- (Not design: in-camp sites drawn during fieldwork under the site-level method, from 2 Sep, have no backup point. The July design method is the hexagon-based selection described in the ToR.)

**Fields:**
- `dtm_gps_lat`, `dtm_gps_lon`: the DTM-recorded point;
- `backup_gps_lat`, `backup_gps_lon`: the backup point;
- `backup_point_method`;
- `flagged_camp`: TRUE = in the original review of the largest camps, over 2,000 households;
- `extent_delineation_failed`;
- `extent_source_note`.

**Method, by count (`backup_point_method`):**

| Method | Rows | Distance from DTM point (min–median–max) |
|---|---|---|
| `imagery_delineated`: random point inside a camp extent delineated from satellite imagery (flagged camps only) | 9 | 46 – 128 – 376 m |
| `fixed_radius_fallback_flagged_camp`: flagged camps where imagery delineation was not confident | 7 | 59 – 142 – 242 m |
| `fixed_radius_fallback_standard_camp`: all other in-camp clusters (extension of 5 Aug) | 68 | 33 – 159 – 276 m |
| `fixed_radius_fallback_new_supplementary_cluster` (Damboa Unity Camp; Dan Musa Dungaza IDP Camp) | 2 | 208 – 214 – 220 m |

- **Fixed-radius fallback:** a random point uniform over the area of a **300 m radius circle** around the DTM point (radius drawn as r = 300·√u), with a fixed random seed (1234).
- **Points sharing the DTM point: 0.** All 86 backup points are distinct from the DTM point; none is within 1 m.
- **Same method as the original flagged camps?** Partly.
  - The 5 Aug extension (the 66 non-flagged camps then without a point) used the **fixed-radius fallback**: the same method already used for the flagged camps whose imagery delineation was not confident.
  - It did **not** use the imagery-delineation method, which was applied to 9 flagged camps only.
  - "Flagged camp" still means "in the original largest-camp review", not "has a backup point".
- **Timeline:**
  - 28 Jul: 15 largest camps reviewed (9 imagery-delineated, 6 fallback).
  - 5 Aug: extended to all 81 in-camp clusters, so 66 more points.
  - 6 Aug: the two new in-camp sites from the North-West border-buffer resample got points (labelled `standard_camp`, hence 68 = 66 + 2).
  - 3 Sep: Mobbar's Gsss Camp Damasak was added as a flagged camp, using the fallback; that's why the file now shows 16 flagged, 7 of them by fallback.
  - During fieldwork: two supplementary in-camp clusters (Damboa Unity Camp, Dan Musa Dungaza IDP Camp) also got points (labelled `new_supplementary_cluster`). These are not part of the design.
  - The file doesn't record per row which of these steps added it, beyond the method column.

---

## A2. Weights (as built and verified for the first analysis dataset)

| Point | Confirmed? | Detail |
|---|---|---|
| (i) Second stage = interviews / households in the unit | **Yes** (capped at 1) | **Non-IDP:** households = eligible building footprints in the hexagon (all draws of that hexagon in the stratum pooled).<br>**IDP, hexagon-based (July design) clusters:** in strata with only July clusters, households = the DTM household total of the whole hexagon (the surveyed site stands in for its hexagon); in strata that also have site-based clusters, households = the surveyed site's DTM households.<br>**IDP, site-based clusters:** households = the site's DTM households. |
| (ii) Repeat draws pooled | **Yes for Non-IDP; partly for IDP** | **Non-IDP:** every draw record of the same physical hexagon in a stratum is one weighting unit (112 such groups, all checked co-located).<br>**IDP:** repeat selections within the July design are one cluster by construction, and the weighting unit is the cluster. |
| (iii) Hexagon- and site-based IDP draws combined (Option 3) | **Yes** | Strata with both kinds: two-phase site-level probability, π = π_July + (1 − π_July) × π_site. Site-based clusters: π_site, per draw batch where the batch pool could be reconstructed exactly or reliably (96 strata), and a single-pool approximation otherwise (26 strata). July-only strata: the site stands in for its hexagon. |
| (iv) Trimmed at 4× the stratum median, then calibrated to accessible households per stratum | **Yes** | Cap and recalibration repeat until both hold (each stratum sums exactly to its accessible households; no weight above 4× its stratum median). |

**Flags (where the build differs from what the ToR text says or implies):**
1. **The IDP second-stage denominator is the DTM-recorded household estimate, not a field listing count.** The current ToR (3.8, A1.4) says IDP design weights "will be recalculated once field teams confirm actual household numbers at each site". The built weights do not use listing counts.
2. **Two IDP sites selected once in the July design and again in a later site-based draw** (Dikwa, DTM site BO_S256; Monguno, BO_S059) are weighted as separate units, not pooled.
3. **Not weighted:** MSNA Light interviews (no probability design), and strata with fewer than 20 interviews.
4. For strata whose accessible area shrank after collection, the calibration total is the accessible households recorded during collection.

---

## A3. One design figure set after the 6 Aug border-buffer revision

**Basis:**
- the initial design draw, including the July correction of 28 Non-IDP strata, which is part of the design;
- the 6 Aug targeted resample of 24 North-West LGAs;
- the 30 Jul partner-coverage list;
- no fieldwork supplementary, spare or top-up clusters.

**Figure 2 layout (coverage-confirmed sample):**

| Region | LGAs | CI | Target MoE | MoE range | Clusters | Sample: Non-IDP | Sample: IDP | Total |
|---|---|---|---|---|---|---|---|---|
| North Central | 18 | 90% | 10% | 8.3%–9.3% | 392 | 1,839 | 1,602 | 3,441 |
| North East | 64 | 90% | 10% | 8.3%–9.3% | 1,326 | 6,562 | 5,598 | 12,160 |
| North West | 94 | 90% | 10% | 7.1%–9.3% | 1,710 | 9,598 | 6,360 | 15,958 |
| **Total** | **176** | 90% | 10% | 7.1%–9.3% | **3,428** | **17,999** | **13,560** | **31,559** |

**The same basis before the coverage layer (design frame):**

| Region | LGAs | MoE range | Clusters | Non-IDP | IDP | Total |
|---|---|---|---|---|---|---|
| North Central | 99 | 2.6%–9.3% | 1,719 | 10,123 | 5,220 | 15,343 |
| North East | 65 | 8.2%–9.3% | 1,345 | 6,669 | 5,598 | 12,267 |
| North West | 159 | 2.6%–9.3% | 2,800 | 16,228 | 8,916 | 25,144 |
| **National** | **323** | — | **5,864** | **33,020** | **19,734** | **52,754** |

- "LGAs" counts Non-IDP strata (one per LGA), as in the ToR.
- MoE ranges exclude the 18 certainty-excluded IDP strata (A1.5).
- Source: the sampling team's design summary, updated 6 Aug (`msna_methodology_summary_portable.md`, sections 7 and 8).

**What these totals include:**
- **The 5 North-West IDP strata created by the 6 Aug revision: YES.** Baure 84, Jibia 78, Mai'adua 60, Sandamu 84, Illela 84 = 390 interviews in 65 clusters.
  - The whole 6 Aug change: design frame +85 clusters; IDP 19,236 → 19,734; Non-IDP 33,010 → 33,020.
  - Coverage-confirmed: IDP 13,062 → 13,560; Non-IDP 17,989 → 17,999.
  - So the rest of the change (+20 clusters, +108 IDP and +10 Non-IDP interviews) is in other North-West strata whose accessible area grew. The files don't split those 20 clusters by population group.
- **The Mobbar IDP stratum (3 Sep): NO.**

**The Mobbar-inclusive set** (adds Mobbar IDP: 10 site clusters, drawn 17 times in total, so 17 × 6 = 102 interviews; 15,913 DTM households across 10 sites):
- Cluster counts below count cluster records, the same unit as 3,428. A site drawn more than once counts once, with a larger quota.
- **Coverage-confirmed:** North East 1,336 clusters, IDP 5,700, total 12,262. National **3,438** clusters, Non-IDP 17,999, IDP 13,662, total **31,661**. LGA counts are unchanged.
  - Mobbar's Non-IDP stratum was already in the design and covered on 30 Jul. Borno's single uncovered LGA on 30 Jul was Marte.
- **Design frame:** North East 1,355 clusters, IDP 5,700, total 12,369. National **5,874** clusters, IDP 19,836, total **52,856**.
- Correction to an earlier draft of this reply, which gave 3,445 / 5,881 by counting Mobbar's 17 draws instead of its 10 cluster records. The interview totals were right.
- **Not in our files:** a projected MoE for Mobbar IDP. The frame doesn't store one, so the MoE ranges above are unchanged and not recomputed.

**Figure 3 (design vs final LGAs):**
- **Non-IDP:** unchanged from the ToR (99 → 18, 65 → 64, 159 → 94; 323 → 176).
- **IDP design strata:** 242 (ToR) → **247** after 6 Aug (+5, all in North-West, all in partner-covered LGAs) → **248** with Mobbar.
- **IDP final (coverage-confirmed) strata:** 143 (ToR) → **148** after 6 Aug (North-West 66 → 71) → **149** with Mobbar (North-East 59 → 60).

---

## A4. Population threshold for dropping a stratum for accessibility loss

**Rule:** a stratum is dropped when **less than 10%** of its population lives in areas reported accessible.
- Constant `POP_FLOOR_PCT = 10`, introduced 31 Aug 2026.

**Definition:**

  % accessible = 100 × (population in the ward portions reported Accessible) / (population in all ward portions of the LGA, for that population group)

- It's computed per LGA × population group on the GIS layer of LGA-by-ward portions:
  - **population = WorldPop gridded population for BOTH groups.** For IDP strata the share is the WorldPop population of the ward portions that contain at least one DTM site. It is **not** weighted by DTM site households;
  - accessibility = the partner-reported ward status.
  - *Correction (12 Oct evening):* an earlier version of this reply said "DTM for IDP". The code uses WorldPop for IDP too (`analysis_accessible_area_layer.R`, line 200).
  - A fix that weights IDP strata by DTM site households is being tested. Whether it is applied, and how the ToR should describe this, is **[Jack to confirm]**. Until then, describe the rule as implemented.
- A standing recheck (from 8 Sep) applies the same 10% floor to every covered stratum and every stratum dropped for this reason. It flags "new exclusion candidates" and "reinstatement candidates" for a decision by the MSNA lead; nothing is applied automatically.

---

## B1–B2. Maps: DONE (12 Oct 2026)

**Files:** in the sampling team's folder `1_sampling/output/maps/tor_final_2026-10-12/` (read its `README.md` first). They're 1170×1105 PNGs in the existing ToR style:
- `tor_figure1_design_map_a_design_time_exclusions.png`: **recommended** for Figure 1;
- `tor_figure1_design_map_b_partner_admin3_12oct.png`: same, with today's partner-reported Admin-3 exclusions; planned clusters inside them are outlined;
- `tor_annex_a1_1_frame_map_a_design_time_exclusions.png`: **recommended** for the Annex 1.1 frame map (Figure 6);
- `tor_annex_a1_1_frame_map_b_partner_admin3_12oct.png`.
- Counts behind every legend class: `counts_by_legend_class.csv`. Verification: `verification_log.txt`.

**Verification results:**
- **Buffer CRS:** the design's own projected CRS, EPSG:31028 (Yoff / UTM zone 28N).
- **Area removed by the buffer within the 14 states** (km², equal-area):

  | Region | Old rule (before 6 Aug) | New rule | New rule with Mobbar re-admitted |
  |---|---|---|---|
  | North Central | 775.8 | 775.8 | 775.8 |
  | North East | 13,405.1 | 13,405.1 | 13,264.2 |
  | North West | 16,037.7 | 4,378.3 | 4,378.3 |
  | **Total** | **30,218.6** | **18,559.2** | **18,418.3** |

- **North-West LGAs affected by the change:** 24, as expected.
- **Planned-cluster centroids inside an excluded area:** (a) **0** in the buffer, **0** in an excluded Admin-3, Mobbar sites 0. (b) 0 in the buffer, **1,272 of 2,972** selected hexagons inside today's partner-reported inaccessible areas.
- **Map cluster counts reconcile exactly** with the A3 table by region (3,428 / 17,999 / 13,560 / 31,559).
- Mobbar's two re-admitted wards are visible and not excluded. The legends match what's drawn.

**Two design facts the ToR text should reflect (verified from the design geometry).** Jack's decision (12 Oct): describe both **as applied** (option a). Use the suggested wording below, and describe the Admin-3 exclusion as the one ward actually excluded.
1. **The buffer distances were applied in EPSG:31028**, a projection whose zone lies far west of Nigeria, so on the ground they are shorter than stated. Geodesic spot checks, 5 per segment:
   - Niger border, North East: 17.75–18.27 km (rule 20 km);
   - Niger border, North-West: 4.62–4.76 km (rule 5 km);
   - Benin: 4.74–4.77 km;
   - Chad: 4.41–4.42 km;
   - Cameroon: 4.40–4.46 km.
   
   Suggested wording: "…within 20 km of the Niger border in Borno and Yobe, and within 5 km of every other international border (including Niger in the North-West). The distances were applied in the projected coordinate system used for the design (EPSG:31028), which shortens them over Nigeria: on the ground the excluded strips are about 18 km and 4.4–4.8 km wide."
2. **At design, the FACT Admin-3 inaccessibility exclusion removed one ward: Goduram (Tarmua LGA, Yobe).** Three other listed areas (Shinwa, Korori, Fulatari) did not match the ward boundary names and were therefore **not** excluded. The ToR should describe the exclusion as applied, not as listed. **[Jack to confirm the wording.]**

**Minor, cosmetic:** on Figure 1 the "NC" region label sits on the Federal Capital Territory, which isn't an assessment state. It can be moved if wanted.

## B1–B2. Maps: original status note (superseded by the section above)

- **Owner:** the sampling team's resampling session, after its current live frame update (about 1.5–2 hours).
- **The existing scripts are reused, not rebuilt:**
  - ToR Figure 1 comes from `analysis_coverage_map2.R` (+ `analysis_coverage_map2_lga_zoom_inset.R`). Its legend has "Excluded: no partner coverage" and "Excluded: design effect" (the latter includes the buffer/Admin-3 zone).
  - The Annex 1.1 frame map comes from `08_render_methodology_maps.R`, with a single "Excluded from sampling universe" class.
  - The population-group styling you describe (Non-IDP only / IDP only / both / eligible hexagon not selected) will be matched to the version embedded in the ToR.
- **One constraint to resolve before rendering B1.** Our records indicate that at the post-6 Aug design, the only Admin-3 exclusion was FACT's North-East layer. Partner-reported ward accessibility in all three regions began during fieldwork, from late August. So "Admin-3 exclusions reported by ANY partner in all regions" and "the layer as it stood at the post-6 Aug design, so no planned cluster lies in an excluded area" probably can't both hold. The map owner will confirm with data and propose one of:
  - **(a)** design-time exclusions only (FACT North-East), consistent with the planned clusters;
  - **(b)** today's partner-reported exclusions, with planned clusters that fell in later-excluded areas drawn in a distinct style;
  - **(c)** both maps.
