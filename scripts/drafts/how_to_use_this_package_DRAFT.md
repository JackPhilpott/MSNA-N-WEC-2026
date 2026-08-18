# How to use this package — NGA MSNA 2026 data collection

*DRAFT for internal review — not yet finalised or distributed to partners.*

This folder contains everything you need to locate and conduct your assigned household
and IDP-site interviews for the NGA MSNA 2026. It's organised by **State → LGA**, matching
the areas your organisation has confirmed coverage for.

## What's in each LGA folder

Every LGA folder can contain up to five files, depending on what applies there:

| File | What it is |
|---|---|
| `non_idp_households_primary.kml` | Your primary Non-IDP household interview points — one GPS point per household. |
| `non_idp_households_reserve.kml` | Backup Non-IDP households, ranked in order. Use strictly in rank order if a primary household can't be reached or declines. |
| `idp_clusters_primary.kml` | Your primary IDP site(s) — one point per cluster (not per household). See that cluster's factsheet (below) for full instructions on building the household list on arrival. |
| `idp_clusters_tier2_backup.kml` | **In-camp clusters only.** A second point to use *only if* a full household listing proves infeasible on arrival at the primary point (Tier 2 fallback). Not an alternate or corrected location — always start at the primary point. |
| `[LGA_name]_map.png` | A zoomed-in map of this LGA showing where your assigned clusters fall, coloured by population group (Non-IDP / IDP / both). For orientation only — use the KML points above for exact navigation. |
| `[cluster_id]_factsheet.docx` | A one-page field sheet for that specific cluster — location, your task (building list / Tier 1-Tier 2 / chief listing as applicable), target and reserve counts, any relevant flags (below-target, multiple draws combined, priority supervision), and a household interview log grid. One per cluster, named by cluster ID. |

If a file type doesn't apply in a given LGA (e.g. no IDP presence there), it simply won't
be present — that's expected, not an error.

## Opening the KML files

**On a phone (Maps.me — recommended for fieldwork):**
1. Download the KML file(s) for your LGA to your phone (via email, WhatsApp, or a shared
   drive — whatever your team normally uses).
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
- **Host-community IDP clusters have no Tier 2** — if a listing isn't feasible there, the
  fallback is the chief/head-of-settlement approach described in the point's own
  description, not a backup GPS point.
- **The LGA map is for orientation, not navigation.** It shows roughly where your clusters
  sit relative to the LGA as a whole — always navigate using the exact KML points, not the
  map image.

## Your targeted sample numbers

Your organisation's Excel summary workbook (`[Partner]_sampling_points_summary.xlsx`, at
the top level of your folder) has two sheets:
- **README** — definitions of every point type, plus a table of your targeted primary/
  reserve sample by State and LGA.
- **Sampling Points** — every single point assigned to you, in one table, with full
  metadata (useful if you prefer a spreadsheet view over opening individual KML files).

## Questions or issues

If a GPS point looks wrong, a building doesn't exist, or a cluster needs to be flagged,
refer to your FACT Foundation / IMPACT Initiatives focal point.

---
*Version 0.1 draft — [date]. Feedback welcome before this goes out with tomorrow's package.*
