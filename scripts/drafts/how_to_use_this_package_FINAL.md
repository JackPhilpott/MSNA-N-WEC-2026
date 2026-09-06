This folder contains everything you need to locate and conduct your assigned household
and IDP-site interviews for the NGA MSNA 2026. It's organised by **State → LGA**, matching
the areas your organisation has confirmed coverage for.

## What's in each LGA folder

As of this version, each LGA folder is split by population group, so KML points and
cluster factsheets for Non-IDP and IDP work don't sit mixed together in one folder:

```
<Partner>/<State>/<LGA>/
  [LGA_name]_map.png                     - whole-LGA overview (see below)
  Non_IDP/
    KML/
      non_idp_households_primary.kml
      non_idp_households_reserve.kml
    Cluster_guide/
      [cluster_id]_factsheet.docx        - one per Non-IDP cluster in this LGA
  IDP/
    KML/
      idp_clusters_primary.kml
      idp_clusters_tier2_backup.kml
    Cluster_guide/
      [cluster_id]_factsheet.docx        - one per IDP cluster in this LGA
```

If a population group doesn't apply in a given LGA (e.g. no IDP presence there), that
whole `Non_IDP/` or `IDP/` branch simply won't be present — that's expected, not an error.

| File | What it is |
|---|---|
| `non_idp_households_primary.kml` (in `Non_IDP/KML/`) | Your primary Non-IDP household interview points — one GPS point per household. |
| `non_idp_households_reserve.kml` (in `Non_IDP/KML/`) | Backup Non-IDP households, ranked in order. Use strictly in rank order if a primary household can't be reached or declines. |
| `idp_clusters_primary.kml` (in `IDP/KML/`) | Your primary IDP site(s) — one point per cluster (not per household). See that cluster's factsheet (below) for full instructions on building the household list on arrival. |
| `idp_clusters_tier2_backup.kml` (in `IDP/KML/`) | **In-camp clusters only.** A second point to use *only if* a full household listing proves infeasible on arrival at the primary point (Tier 2 fallback). Not an alternate or corrected location — always start at the primary point. |
| `[LGA_name]_map.png` (at the plain `<LGA>/` level, not inside `Non_IDP/`/`IDP/`) | A zoomed-out map of the whole LGA showing every cluster assigned to you there, coloured by population group (Non-IDP / IDP / both). For orientation only — use the KML points above for exact navigation, or the closer-in maps inside each cluster's factsheet. |
| `[cluster_id]_factsheet.docx` (in `Non_IDP/Cluster_guide/` or `IDP/Cluster_guide/`) | A field sheet for that specific cluster: location, your task (building list / Tier 1–Tier 2 / chief listing as applicable), target and reserve counts, any relevant flags (below-target, multiple draws combined, priority supervision), a household interview log grid, and — at the end of the document — a large cluster-level map (hexagon/point layout, roads, buildings, and any known nearby points of interest) followed by an LGA-context map showing where this cluster sits within the wider LGA. One per cluster, named by cluster ID. The first two pages of every factsheet are a general field guide (replacement rules, the accepted GPS-offset range, who to contact) — the same content repeats in every cluster's document so each one is self-contained in the field.

**`LGA_boundaries_[Partner].kml`** (at the top level of your folder, not inside any State/LGA
subfolder) — every LGA boundary line across all 14 assessment states, in one file: **your
own assigned LGA(s) in thick red**, every other LGA in thinner blue for context. Load it
in Maps.me alongside your points to visually check that a sample point's GPS location
genuinely falls within the (red) LGA it's assigned to — a quick sanity check if a point
ever looks like it might be sitting near, or across, an LGA line, and the wider blue
context helps make sense of *which* neighbouring LGA it might actually be closer to. This
is the same official LGA boundary (OCHA/COD) used to assign every point in this package —
if a point looks like it's outside its red boundary line in Maps.me, treat that as worth
flagging to your focal point rather than resampling on your own (see "Ward is approximate"
above for a related, separate note about ward — not LGA — boundaries specifically).

## Pin colors

Each KML file's points now load with their own color, so if you load more than one file
into Maps.me at once you can tell them apart at a glance:

| File | Pin color |
|---|---|
| `non_idp_households_primary.kml` | Green |
| `non_idp_households_reserve.kml` | Yellow |
| `idp_clusters_primary.kml` | Blue |
| `idp_clusters_tier2_backup.kml` | Red |

If your phone has no signal the very first time you open a file, pins may briefly show as
a generic marker until the color loads — this resolves itself once the phone has any
internet connection, and doesn't affect the point's location or details.

## Opening the KML files

**For the full illustrated walkthrough — installing the app itself, then importing and
navigating to a KML point — see `MSNA_NGA_MapsMe_Guide.pdf`, at the top level of your
folder.** It covers installing Maps.me on Android and iOS, importing a cluster's KML file,
and getting a turn-by-turn route to a sample point, all with annotated phone screenshots.
The steps below are the quick-reference version.

**On a phone (Maps.me — recommended for fieldwork):**
1. Download the KML file(s) for your LGA — from its `Non_IDP/KML/` or `IDP/KML/`
   subfolder, depending which you need — to your phone (via email, WhatsApp, or a
   shared drive — whatever your team normally uses).
2. Open Maps.me, tap the bookmarks/menu icon, and choose "Import" or "Open file" — select
   the downloaded KML.
3. Each point will appear as a labelled pin. Tap a pin to see its full details (cluster ID,
   ward, status, and any other relevant information).

**On a computer (Google Earth or Google My Maps):**
1. Open [Google Earth](https://earth.google.com) or [Google My Maps](https://mymaps.google.com).
2. Choose "Import" and select the KML file.
3. All points load as a layer you can view, print, or export.

You can load more than one KML file at once (e.g. primary + reserve together) if it's
useful to see them side by side — just keep track of which pin belongs to which file so
you don't accidentally treat a reserve point as primary.

## Key things to know before you go

- **Primary before reserve, always.** Reserve households/sites are only used if a primary
  one can't be reached, refuses, or turns out ineligible — and always in the ranked order
  given, not whichever is most convenient.
- **Tier 1 before Tier 2, always** (in-camp IDP clusters only). Attempt the full household
  listing at the primary point first. Only use the Tier 2 backup point if that genuinely
  isn't feasible on arrival.
- **Full household listing is mandatory for every IDP cluster** — in-camp (Tier 1, or Tier 2
  fallback) and host-community alike. If it isn't done, that cluster's data cannot be
  accepted.
- **Host-community IDP clusters have no Tier 2** — if a listing isn't feasible there, the
  fallback is the chief/head-of-settlement approach described in the point's own
  description, not a backup GPS point.
- **Reserves are a backup only, not a free substitute list.** Using them beyond the
  replacement rules in the general Field Guide (inside each cluster's factsheet) requires
  prior approval from your FACT Foundation / IMPACT Initiatives focal point.
- **Ward is approximate, for orientation only.** Every point's GPS location is anchored to
  its LGA, not to the ward boundary shown — don't second-guess a point's location based on
  the ward name. See "A note on data sources" below for why ward and LGA sometimes come
  from different datasets.
- **Maps are for orientation, not navigation.** Both the whole-LGA overview map and the
  maps inside each cluster's factsheet show roughly where your clusters sit — always
  navigate using the exact KML points, not a map image.

## A note on data sources (LGA vs. Ward)

Every point's **LGA** comes from OCHA/COD, the officially-endorsed humanitarian boundary
dataset, and is authoritative throughout this assessment. **Ward** detail comes from GRID3
(the only ward-level product with national coverage; North-East clusters additionally show
OCHA/COD's own ward product for cross-reference — see the "Ward (GRID3)" / "Ward (OCHA/COD)"
columns in your summary workbook). These two datasets occasionally disagree by a few tens of
metres right at LGA borders — this is a known, expected discrepancy between two real
datasets, not a data error, and does not change which LGA a point belongs to. Full detail is
in your summary workbook's README sheet, under "A note on LGA vs Ward data sources." If your
team identifies more strongly with a different LGA in the field, flag it to your focal point
with the specific point(s) — don't resample based on your own read of the boundary.

## Your targeted sample numbers

Your organisation's Excel summary workbook (`[Partner]_sampling_points_summary.xlsx`, at
the top level of your folder) has two sheets:
- **README** — definitions of every point type, the LGA/Ward data-source note above in full,
  plus a table of your targeted primary/reserve sample by State and LGA.
- **Sampling Points** — every single point assigned to you, in one table, with full
  metadata (useful if you prefer a spreadsheet view over opening individual KML files).

## Reporting accessibility issues

Your folder also includes `[Partner]_accessibility_report.xlsx`. Use it to tell us about
any ward or cluster your team is unable to collect data in — for example due to insecurity,
physical access, or the population no longer being present — so we can respond
appropriately, including drawing a replacement sample where needed. See the file's own
README tab for how to fill it in.

## Questions or issues — who to contact, and how

Full detail (roles, contact list, and the daily data-cleaning workflow) is in
`NGA_MSNA_2026_Data_Collection_SOP.pdf`, also at the top level of your folder. In brief,
which channel to use depends on the urgency of the issue:

| Tier | Example issues | Channel | Response |
|---|---|---|---|
| **1 — Safety / Security** | Insecure area, incident, evacuation | Phone call **+** WhatsApp direct message, to your Regional FACT Coordinator **and** the IMPACT focal point, simultaneously | Immediate |
| **2 — Operational** | Reserve list exhausted, site/hexagon mismatch, population not found | WhatsApp regional group | Same day |
| **3 — Data quality / cleaning log** | Flagged records, cleaning log responses | Email (formal, tracked) | ~1 day |

A GPS point that looks wrong, a building that doesn't exist, or a cluster that needs
flagging is normally a Tier 2 (operational) issue — use the WhatsApp regional group unless
it's more urgent than that.

---
*Version 1.8 — 2026-08-20.*
