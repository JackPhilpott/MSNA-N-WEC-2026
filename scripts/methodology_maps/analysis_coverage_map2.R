# ==============================================================================
# Coverage Map 2 (final) - the main, comprehensive sampling-design map for
# the ToR (the old "v5 combined"), rebuilt per user feedback 2026-07-31:
#   - same boundary treatment as Map 1 (country/region/state, all in legend)
#   - legend fill title "Achieved sample per LGA (WORKING)" -> "Planned
#     interviews per hex" (renamed twice: first to plain "Planned sample",
#     then the whole metric moved from LGA-level to hex-level per the next
#     point, so the label follows the granularity change)
#   - LGA-level colouring per sample REPLACED by the actual selected Stage
#     1 hexagons (one per planned cluster), shaded by planned households
#     per hex (6 = standard stratum, 7 = boosted stratum; a hex drawn more
#     than once by the systematic PPS draw sums its per-draw target)
#   - excluded areas simplified to exactly two categories: "Excluded: no
#     partner coverage" (grey, LGA-level - whole LGA has zero working
#     hexes because its Non-IDP stratum isn't covered) and "Excluded:
#     design effect" (red) - covers BOTH (a) LGAs whose exclusion is
#     structural rather than operational (not_covered AND its IDP stratum
#     was already certainty-excluded under Annex 1.5, so it would have
#     been excluded regardless of partner coverage) and (b) the
#     geographic border-buffer/FACT-inaccessible zone, drawn as an
#     overlay in the same red, mirroring how methodology_map_overview
#     shows it
#
# Revision 2026-08-04 (alt2 refinements, per user feedback - alt2 is now the
# main ToR design/extent map): four fixes, applied to the SHARED context/
# label/legend-building code below so all three map variants stay
# consistent, though only alt2 was actually re-rendered this pass (ask
# before regenerating full_design/alt1 too, since they're each their own
# ToR deliverable):
#   1. Legend alignment/whitespace/size - guides were originally built with
#      cowplot::get_legend() and stacked with guessed rel_heights, leaving
#      uneven indentation and dead space. A first pass (build_measured_
#      legend_panel()) fixed the whitespace by measuring each guide's real
#      grob size, but different guide TYPES (fill-box legends vs. the
#      boundary linetype legend) turned out to each carry their own
#      internal padding before the key even starts - stacking them via
#      plot_grid()'s align="v" never actually shares a left edge, since
#      that argument aligns ggplot PANEL grobs, not raw legend grobs. Fully
#      replaced with build_manual_legend_panel(): every swatch and every
#      label is hand-positioned at an identical x offset via absolute-cm
#      grid viewports, so alignment is guaranteed by construction rather
#      than dependent on any guide's own layout. Also sized up per
#      follow-up feedback ("too small") - larger swatches/text throughout.
#   2. Red-shading mismatch - restricted_focus (the border-buffer/FACT-
#      inaccessible overlay) was drawn at alpha=0.8 over the grey basemap,
#      lightening the same #8B4A4A used opaque for admin2_excluded's LGA
#      fill. Dropped the alpha so both render identically.
#   3. Country label placement - Chad's (and CAR's) point_on_surface anchor
#      sat past the old ASYMMETRIC xlim upper bound (xmax - 140000), so
#      ggrepel clamped/dragged the label back into Nigeria. First attempt
#      widened context_margin_m 60km->130km to give more real territory to
#      label within - worked, but zoomed the whole map out further than
#      wanted ("too far zoomed out... need it as zoomed to Nigeria as
#      possible"), so reverted to the original 60km margin. The real fix
#      that survived: a small SYMMETRIC xlim/ylim inset (5km every side,
#      was xmax-140000 on the right only) plus small per-country manual
#      nudges (Cameroon/CAR/Chad) sized for this tight margin - just enough
#      to settle each label in its own thin sliver of territory just
#      outside Nigeria, without needing extra map real estate.
#   4. (kept from the first pass, unaffected by later feedback) full_design/
#      alt1 share this same code but were deliberately left un-regenerated -
#      ask before refreshing those two.
#
# Heavy load: sources the main pipeline up to `selected_clusters` (~line
# 1236) - needed for the actual hexagon geometries. This also picks up
# `restricted`/`accessible_area` (built earlier in the same script) for
# the geographic-exclusion overlay, at no extra cost.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(ggrepel)
  library(cowplot)
  library(grid)
})

output_dir   <- here::here("output")
analysis_dir <- here::here(output_dir, "maps")
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

# Revision 2026-08-06: previously sourced the main pipeline all the way
# through Stage 1 cluster selection (past its set.seed(1234) call) to get
# selected_clusters - safe only because that reproduced the exact same
# national draw every time (same seed + same national input data). Since
# the 2026-08-06 targeted 24-LGA resample, the delivered design is a SPLICE
# (299 LGAs from the original national draw + 24 NW LGAs from an isolated,
# separately-seeded resample) - re-sourcing the full national pipeline here
# would silently regenerate a DIFFERENT, purely-national draw that no longer
# matches the delivered design at all. Fixed: source only the deterministic
# boundary/buffer prefix (through `accessible_area`, no randomness involved
# at any point in this range - safe to re-run any number of times), and load
# the actual delivered hex geometries directly from the merged design-frame
# archive instead of re-deriving them.
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^hex_access <- cache_rds\\(",
  lines
))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_map2.R")
source("temp_boundaries_map2.R")
file.remove("temp_boundaries_map2.R")
# accessible_hex.rds cache was deleted 2026-08-06 so this recomputes fresh
# against the new region-differentiated buffer instead of loading the stale
# pre-2026-08-06 cache (same class of gotcha CLAUDE.md already documents for
# the buildings/idp_sites caches - see "Revision 2026-08-06").

# 2026-09-01 fix: the Aug-6 archive predates this week's entire resampling
# round (~356 new clusters absent, 39 reverted FACT clusters still present
# as if selected). Replaced with a consolidated, current geometry source -
# see scripts/one_off_analyses/build_consolidated_selected_clusters_
# 2026-09-01.R's header for how it's built (unions the archive with every
# partner batch's new-cluster files via uuid_hex, not cluster_id label).
selected_clusters <- readRDS(here::here("output", "gis", "selected_clusters_v6_current.rds"))

# Fix (2026-08-06): selected_clusters_final's own `geometry` column is NOT
# uniformly a hex polygon - Non-IDP rows carry the hex polygon, but IDP rows
# (idp_sites$clusters_final, from 05_stage2_idp_site_assignment.R) carry the
# DTM site's own POINT geometry instead, since that's what Stage 2 actually
# needs for IDP. The old Stage-1-only `selected_clusters` this script used
# to re-derive via sourcing didn't have this problem (Stage 1 hex selection
# assigns proper hex-grid geometry to every cluster regardless of pop_type),
# which is why this only surfaced now that selected_clusters comes from the
# post-Stage-2 merged archive instead. Any hex with ONLY an IDP cluster (no
# Non-IDP cluster in the same hex) rendered as a point rather than a filled
# hexagon as a result. Fixed generically: always look up hex polygon
# geometry from hex_access (the canonical hex grid, keyed by uuid_hex),
# never from selected_clusters' own geometry column.
hex_polygons <- hex_access %>%
  st_make_valid() %>%
  st_transform(4326) %>%
  st_make_valid() %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

# ---------------------------------------------------------------------------
# LGA-level coverage/exclusion classification (2 categories only)
# ---------------------------------------------------------------------------
coverage_summary <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_coverage_summary_v2.csv"), show_col_types = FALSE)
full_strata <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)

lga_certainty_excluded <- full_strata %>%
  group_by(adm2_pcode) %>%
  summarise(certainty_excluded = any(excluded_infeasible == "TRUE"), .groups = "drop")

admin2_status <- coverage_summary %>%
  left_join(lga_certainty_excluded, by = "adm2_pcode") %>%
  mutate(
    certainty_excluded = coalesce(certainty_excluded, FALSE),
    exclusion_class = case_when(
      coverage_status == "covered" ~ "Sampled",
      certainty_excluded ~ "Excluded: design effect",
      TRUE ~ "Excluded: no partner coverage"
    )
  )

cat("LGA-level exclusion_class counts:\n")
print(table(admin2_status$exclusion_class))

admin2_focus <- NGA_shapes_all_cleaned$nga_admin2 %>%
  filter(adm1_pcode %in% admin1_focus_areas) %>%
  left_join(admin2_status %>% select(-region), by = "adm2_pcode")
stopifnot(nrow(admin2_focus) == 323, sum(is.na(admin2_focus$exclusion_class)) == 0)

admin2_excluded <- admin2_focus %>% filter(exclusion_class != "Sampled")

# ---------------------------------------------------------------------------
# Hexagon layer - actual selected Stage 1 clusters, restricted to the
# WORKING (covered + not excluded) (adm2_pcode, pop_type) pairs, shaded by
# total planned households at that hex (m_used, summed if the systematic
# PPS draw selected the same hex more than once).
# ---------------------------------------------------------------------------
working_pairs <- full_strata %>%
  filter(coverage_status == "covered", exclusion_reason == "none") %>%
  distinct(adm2_pcode, pop_type)

m_used_lookup <- full_strata %>% distinct(adm2_pcode, pop_type, m_used)

selected_clusters_working <- selected_clusters %>%
  st_drop_geometry() %>%
  select(cluster_id, uuid_hex_pop, adm2_pcode, pop_type) %>%
  inner_join(working_pairs, by = c("adm2_pcode", "pop_type")) %>%
  left_join(m_used_lookup, by = c("adm2_pcode", "pop_type"))

n_multi_draw <- selected_clusters_working %>% count(uuid_hex_pop) %>% filter(n > 1) %>% nrow()
cat("\nHexes drawn more than once (systematic PPS repeat):", n_multi_draw, "\n")

hex_planned <- selected_clusters_working %>%
  group_by(uuid_hex_pop) %>%
  summarise(planned_hh = sum(m_used), n_draws = dplyr::n(), .groups = "drop")

# Attribute-only mapping (uuid_hex_pop -> uuid_hex) from selected_clusters,
# geometry always taken from hex_polygons (the canonical hex grid) - see the
# 2026-08-06 fix note near the top of this script for why.
hex_geom <- selected_clusters %>%
  st_drop_geometry() %>%
  distinct(uuid_hex_pop, uuid_hex) %>%
  left_join(hex_polygons, by = "uuid_hex") %>%
  st_as_sf() %>%
  select(uuid_hex_pop)

hexes_sf <- hex_geom %>%
  inner_join(hex_planned, by = "uuid_hex_pop") %>%
  st_transform(4326)

cat("Selected working hexes:", nrow(hexes_sf), "| planned_hh distribution:\n")
print(table(hexes_sf$planned_hh))

# n_draws > 1 turns out to be common (676 of 3,302 hexes, ~20%) - almost
# entirely in very-small-population strata where the systematic PPS draw
# has few hexes to choose from and picks the same one repeatedly, up to
# 17x (102 households) in the most extreme case. One legend swatch per
# distinct value would mean 16+ near-identical dark-green rows - collapse
# all repeats into a single second category instead. NOTE: every single
# selected hex has m_used == 6 - no hex anywhere in the WORKING frame has
# m_used == 7, so the "boosted stratum" (m=7) case the map was originally
# going to distinguish turns out not to occur in the current live design
# at all (flagged to the user; not otherwise investigated here).
hh_class_levels <- c("6 households (single draw)", "12+ households (hex selected more than once)")
hexes_sf <- hexes_sf %>%
  mutate(hh_class = factor(if_else(planned_hh <= 6, hh_class_levels[1], hh_class_levels[2]), levels = hh_class_levels))

cat("\nHex household-class counts:\n")
print(table(hexes_sf$hh_class))

hex_colors <- setNames(c("#A6D96A", "#0D3D12"), hh_class_levels)

# ---------------------------------------------------------------------------
# Geographic exclusion overlay (border buffer + FACT-inaccessible admin3s)
# - same red as the LGA "design effect" category, fully opaque (see fix #2
# in the header comment - previously alpha=0.8, which visibly lightened
# this layer relative to admin2_excluded's identical-colour opaque fill).
# ---------------------------------------------------------------------------
restricted_focus <- sf::st_intersection(sf::st_make_valid(restricted), sf::st_union(sf::st_make_valid(NGA_shapes_all_cleaned$nga_admin1 %>% filter(adm1_pcode %in% admin1_focus_areas)))) %>%
  sf::st_make_valid()

# ---------------------------------------------------------------------------
# Context layers - identical to Map 1, except context_margin_m widened (see
# fix #3 in the header comment).
# ---------------------------------------------------------------------------
state_region_lookup <- tibble::tribble(
  ~adm1_name, ~region_label,
  "Benue", "North-Central", "Kogi", "North-Central", "Nasarawa", "North-Central",
  "Niger", "North-Central", "Plateau", "North-Central",
  "Adamawa", "North-East", "Borno", "North-East", "Yobe", "North-East",
  "Kaduna", "North-West", "Kano", "North-West", "Katsina", "North-West",
  "Kebbi", "North-West", "Sokoto", "North-West", "Zamfara", "North-West"
)

admin1_focus <- NGA_shapes_all_cleaned$nga_admin1 %>%
  filter(adm1_pcode %in% admin1_focus_areas) %>%
  left_join(state_region_lookup, by = "adm1_name")
stopifnot(sum(is.na(admin1_focus$region_label)) == 0)

region_focus <- admin1_focus %>% group_by(region_label) %>% summarise(.groups = "drop") %>% st_make_valid()
nigeria_boundary <- admin0_wa_proj %>% filter(adm0_pcode == "NG") %>% st_make_valid()
nga_all_states <- NGA_shapes_all$nga_admin1

# Kept at the original 60km (2026-08-04: briefly widened to 130km to fix
# Chad/CAR's mislabeling, then reverted per user feedback - the wider
# margin zoomed out too far for a map whose whole point is to read as
# "zoomed to Nigeria." The real fix for the mislabeling turned out to be
# the xlim symmetry below plus per-country nudges sized for THIS tight
# margin, not extra map real estate.
context_margin_m <- 60000
context_bbox <- sf::st_bbox(nga_all_states) + c(-context_margin_m, -context_margin_m, context_margin_m, context_margin_m)
context_extent <- sf::st_as_sfc(context_bbox, crs = sf::st_crs(nga_all_states))

neighbouring_countries <- admin0_wa_proj %>% filter(adm0_pcode != "NG") %>% st_make_valid() %>% st_intersection(context_extent)
neighbour_labels <- neighbouring_countries %>% group_by(adm0_name) %>% summarise(.groups = "drop") %>% st_point_on_surface()

# Per user feedback 2026-08-05: drop 3 country labels the map doesn't need
# (Burkina Faso, Mali, Central African Republic) - their grey landmass
# still shows via neighbouring_countries/base_layers(), only the text
# label is removed. Kept: Niger, Chad, Benin, Cameroon, Equatorial Guinea.
neighbour_labels <- neighbour_labels %>%
  filter(!adm0_name %in% c("Burkina Faso", "Mali", "Central African Republic"))

# Manual nudges for the 2 remaining neighbours whose clipped-to-context
# centroid lands somewhere unhelpful (too close to the border / in a
# cramped sliver) - same established technique as the NC-region-label
# nudge below. Small on purpose - at this tight margin there's very little
# real territory to work with (Chad's visible sliver is only ~45km wide),
# just enough to settle the label just outside Nigeria rather than being
# dragged across the border by repel. Re-derive if context_margin_m or the
# focus-state list ever changes.
cameroon_idx <- neighbour_labels$adm0_name == "Cameroon"
chad_idx <- neighbour_labels$adm0_name == "Chad"
st_geometry(neighbour_labels)[cameroon_idx] <- st_geometry(neighbour_labels)[cameroon_idx] + c(60000, 30000)
st_geometry(neighbour_labels)[chad_idx] <- st_geometry(neighbour_labels)[chad_idx] + c(15000, 40000)

state_labels_focus <- admin1_focus %>% st_point_on_surface()

region_code_lookup <- c("North-Central" = "NC", "North-East" = "NE", "North-West" = "NW")
region_labels_focus <- region_focus %>%
  mutate(region_code = region_code_lookup[region_label]) %>%
  st_point_on_surface()
# NC's point_on_surface lands right on top of the "Nasarawa" state label -
# nudge it west into Niger State's open interior (same manual-offset
# technique as the Cameroon/CAR/Chad nudges above).
nc_idx <- region_labels_focus$region_code == "NC"
st_geometry(region_labels_focus)[nc_idx] <- st_geometry(region_labels_focus)[nc_idx] + c(-120000, 40000)

boundary_labels <- c(country = "Nigeria national boundary", region = "Regional boundary (NC / NE / NW)", state = "State boundary")
boundary_colors <- setNames(c("#0A0A0A", "#1B2A4A", "grey55"), boundary_labels)
boundary_linewidths <- setNames(c(1.0, 0.7, 0.3), boundary_labels)

# No ggplot legend guide needed any more (2026-08-04) - the boundary legend
# rows are hand-drawn by build_manual_legend_panel() below, so this only
# needs to draw the lines on the map itself.
boundary_layers <- function() {
  list(
    geom_sf(data = admin1_focus, fill = NA, color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]]),
    geom_sf(data = region_focus, fill = NA, color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
    geom_sf(data = nigeria_boundary, fill = NA, color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]])
  )
}
country_region_state_no_legend <- boundary_layers
base_layers <- function() {
  list(
    geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25),
    geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2)
  )
}

# Shared label layers (neighbouring countries, state names, region codes) -
# used identically across all three map variants below. xlim/ylim loosened
# to a small, symmetric inset (5km every side, tightened from 15km to match
# the reverted-to-60km context margin) - the old asymmetric xmax-140000
# right-side cut was the root cause of Chad/CAR's mislabeling (see fix #3
# above); the per-country nudges above do the rest of the work at this
# tight margin. force/max.overlaps loosened so a label isn't fought back
# toward the panel centre when its own nudged position is already good.
label_layers <- function() {
  list(
    ggrepel::geom_text_repel(
      data = neighbour_labels, aes(label = adm0_name, geometry = geometry), stat = "sf_coordinates",
      size = 4.0, color = "grey35", fontface = "italic", bg.color = "white", bg.r = 0.12, seed = 1,
      max.overlaps = Inf, force = 0.4,
      xlim = c(unname(context_bbox["xmin"]) + 5000, unname(context_bbox["xmax"]) - 5000),
      ylim = c(unname(context_bbox["ymin"]) + 5000, unname(context_bbox["ymax"]) - 5000)
    ),
    ggrepel::geom_text_repel(
      data = state_labels_focus, aes(label = adm1_name, geometry = geometry), stat = "sf_coordinates",
      size = 2.8, color = "#1B2A4A", fontface = "bold", bg.color = "white", bg.r = 0.12, seed = 1
    ),
    ggrepel::geom_text_repel(
      data = region_labels_focus, aes(label = region_code, geometry = geometry), stat = "sf_coordinates",
      size = 6.5, color = "#1B2A4A", fontface = "bold", bg.color = "white", bg.r = 0.18, seed = 2,
      alpha = 0.85
    )
  )
}

# ---------------------------------------------------------------------------
# Hand-positioned legend panel (fix #1, second pass - see header comment).
# A first attempt used cowplot::get_legend() to extract each ggplot guide
# and stacked them with measured heights (no more guessed whitespace), but
# different guide TYPES (fill-box legends vs. a linetype/line-sample
# legend) each carry their own internal padding before the key starts, so
# stacking them never actually shared a left edge - cowplot::plot_grid()'s
# align="v" aligns ggplot PANEL grobs, not raw legend grobs, so it did
# nothing useful here. This version draws every swatch and every label
# itself via absolute-cm grid viewports (a fixed left margin for swatches,
# swatch width + gap for labels) - alignment is guaranteed by construction,
# not dependent on any guide's own layout.
#
# `sections`: list of list(title = NULL or "Section title", rows = list(
#   list(label = "...", type = "fill", color = "#RRGGBB") |
#   list(label = "...", type = "line", color = "#RRGGBB", linewidth = n)
# )).
# ---------------------------------------------------------------------------
build_manual_legend_panel <- function(sections, swatch_cm = 0.45, title_size = 17,
                                        section_title_size = 11, item_size = 10,
                                        row_gap_cm = 0.16, section_gap_cm = 0.30,
                                        title_gap_cm = 0.22, swatch_label_gap_cm = 0.18,
                                        fig_width_in = 9, fig_height_in = 8.5,
                                        margin_cm = c(t = 0.4, r = 0.5, b = 0.35, l = 0.45)) {

  # -- pass 1: measure label widths (cm) to size the panel --
  all_labels <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) s$title, sapply(s$rows, `[[`, "label"))))
  label_fontsizes <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) section_title_size, rep(item_size, length(s$rows)))))
  label_bold <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) TRUE, rep(FALSE, length(s$rows)))))

  label_w_cm <- mapply(function(txt, fs, bold) {
    g <- grid::textGrob(txt, gp = grid::gpar(fontsize = fs, fontface = if (bold) "bold" else "plain"))
    as.numeric(grid::convertWidth(grid::grobWidth(g), "cm"))
  }, all_labels, label_fontsizes, label_bold)

  title_w_cm <- as.numeric(grid::convertWidth(grid::grobWidth(grid::textGrob("Legend", gp = grid::gpar(fontsize = title_size, fontface = "bold"))), "cm"))

  content_w_cm <- max(title_w_cm, swatch_cm + swatch_label_gap_cm + max(label_w_cm))
  total_width_cm <- content_w_cm + margin_cm[["l"]] + margin_cm[["r"]]

  # -- pass 2: build a flat row list with explicit heights --
  row_h_cm <- max(swatch_cm, 0.42)
  section_title_h_cm <- 0.48
  title_h_cm <- 0.6

  rows <- list()
  rows[[length(rows) + 1]] <- list(kind = "title", h = title_h_cm)
  for (s in sections) {
    rows[[length(rows) + 1]] <- list(kind = "gap", h = if (length(rows) == 1) title_gap_cm else section_gap_cm)
    if (!is.null(s$title)) {
      rows[[length(rows) + 1]] <- list(kind = "section_title", h = section_title_h_cm, label = s$title)
      rows[[length(rows) + 1]] <- list(kind = "gap", h = row_gap_cm * 0.6)
    }
    for (i in seq_along(s$rows)) {
      rows[[length(rows) + 1]] <- list(kind = "item", h = row_h_cm, row = s$rows[[i]])
      if (i < length(s$rows)) rows[[length(rows) + 1]] <- list(kind = "gap", h = row_gap_cm)
    }
  }

  total_height_cm <- sum(sapply(rows, `[[`, "h")) + margin_cm[["t"]] + margin_cm[["b"]]

  # -- pass 3: place every row via absolute cm viewports inside one gTree --
  make_swatch_grob <- function(row, x_cm, y_cm) {
    vp <- grid::viewport(x = unit(x_cm, "cm"), y = unit(y_cm, "cm"), width = unit(swatch_cm, "cm"), height = unit(swatch_cm, "cm"), just = c("left", "center"))
    if (row$type == "fill") {
      grid::grobTree(grid::rectGrob(gp = grid::gpar(fill = row$color, col = "grey30", lwd = 0.6)), vp = vp)
    } else {
      # Plain line sample, no bordered box around it - an earlier version
      # wrapped the line in a bordered rect to match the fill swatches'
      # footprint, but that read as a broken/doubled icon (a box AND a
      # line inside it) rather than the clean single-line key a linetype
      # legend normally shows. min lwd of 1.8 keeps "State boundary"
      # (linewidth 0.3 on the actual map) visible at legend scale.
      grid::grobTree(
        grid::linesGrob(x = unit(c(0, 1), "npc"), y = unit(0.5, "npc"), gp = grid::gpar(col = row$color, lwd = max(row$linewidth * 2.2, 1.8))),
        vp = vp
      )
    }
  }
  make_label_grob <- function(text, x_cm, y_cm, size, bold = FALSE) {
    grid::textGrob(text, x = unit(x_cm, "cm"), y = unit(y_cm, "cm"), just = c("left", "center"),
                    gp = grid::gpar(fontsize = size, fontface = if (bold) "bold" else "plain", col = if (bold) "grey15" else "black"))
  }

  grobs <- grid::gList()
  y_cursor_cm <- total_height_cm - margin_cm[["t"]]  # from bottom, starting at top

  for (r in rows) {
    if (r$kind == "gap") {
      y_cursor_cm <- y_cursor_cm - r$h
      next
    }
    row_center_y <- y_cursor_cm - r$h / 2
    if (r$kind == "title") {
      grobs <- grid::gList(grobs, make_label_grob("Legend", margin_cm[["l"]], row_center_y, title_size, bold = TRUE))
    } else if (r$kind == "section_title") {
      grobs <- grid::gList(grobs, make_label_grob(r$label, margin_cm[["l"]], row_center_y, section_title_size, bold = TRUE))
    } else if (r$kind == "item") {
      grobs <- grid::gList(grobs, make_swatch_grob(r$row, margin_cm[["l"]], row_center_y))
      grobs <- grid::gList(grobs, make_label_grob(r$row$label, margin_cm[["l"]] + swatch_cm + swatch_label_gap_cm, row_center_y, item_size))
    }
    y_cursor_cm <- y_cursor_cm - r$h
  }

  content_vp <- grid::viewport(width = unit(total_width_cm, "cm"), height = unit(total_height_cm, "cm"))
  content_tree <- grid::gTree(children = grobs, vp = content_vp)

  bg <- grid::rectGrob(gp = grid::gpar(fill = "white", col = "grey60", lwd = 1))
  panel_grob <- grid::grobTree(bg, content_tree)

  list(
    grob = panel_grob,
    width_npc = (total_width_cm / 2.54) / fig_width_in,
    height_npc = (total_height_cm / 2.54) / fig_height_in
  )
}

# Anchors a legend panel bottom-left with a small fixed margin, sized to
# the panel's own content (no dead space). Moved from bottom-right to
# bottom-left 2026-08-05 per user feedback - the map's own geography
# leaves more unused space in the bottom-left (south-west, below Benin/
# Togo) than the bottom-right (which sits right against Cameroon/the NE
# hex cloud).
draw_legend_bottom_left <- function(base_plot, legend_result, margin_npc_x = 0.015, margin_npc_y = 0.02) {
  cowplot::ggdraw(base_plot) +
    cowplot::draw_grob(
      legend_result$grob,
      x = margin_npc_x, y = margin_npc_y,
      width = legend_result$width_npc, height = legend_result$height_npc
    )
}

# ==============================================================================
# Map 2
# ==============================================================================

excl_colors <- c("Excluded: no partner coverage" = "grey75", "Excluded: design effect" = "#8B4A4A")

excl_section <- list(title = NULL, rows = list(
  list(label = "Excluded: design effect", type = "fill", color = unname(excl_colors[["Excluded: design effect"]])),
  list(label = "Excluded: no partner coverage", type = "fill", color = unname(excl_colors[["Excluded: no partner coverage"]]))
))
boundary_section <- list(title = NULL, rows = list(
  list(label = "Nigeria national boundary", type = "line", color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]]),
  list(label = "Regional boundary (NC / NE / NW)", type = "line", color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
  list(label = "State boundary", type = "line", color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]])
))
hex_section <- list(title = "Planned interviews per hex", rows = list(
  list(label = hh_class_levels[1], type = "fill", color = unname(hex_colors[hh_class_levels[1]])),
  list(label = hh_class_levels[2], type = "fill", color = unname(hex_colors[hh_class_levels[2]]))
))

legend_result_map2 <- build_manual_legend_panel(list(hex_section, excl_section, boundary_section))

# Single unified fill column (excluded-LGA colours + hex colours, as hex
# strings) so the main map only needs ONE scale_fill_identity() call -
# ggnewscale isn't installed. The small legend-extraction plots above each
# keep their own natural scale (separate single-scale ggplot objects), so
# legends still render with proper labels.
admin2_excluded <- admin2_excluded %>% mutate(fill_hex = unname(excl_colors[exclusion_class]))
hexes_sf <- hexes_sf %>% mutate(fill_hex = unname(hex_colors[as.character(hh_class)]))

p_no_legend <- ggplot() +
  base_layers() +
  geom_sf(data = admin2_excluded, aes(fill = fill_hex), color = "white", linewidth = 0.1) +
  geom_sf(data = restricted_focus, fill = "#8B4A4A", color = NA) +
  geom_sf(data = hexes_sf, aes(fill = fill_hex), color = "grey20", linewidth = 0.08) +
  scale_fill_identity() +
  country_region_state_no_legend() +
  label_layers() +
  coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
  theme_void(base_size = 12) +
  theme(legend.position = "none")

p_titled <- draw_legend_bottom_left(p_no_legend, legend_result_map2)

# NOTE (2026-08-04): the fixes above (context margin/label nudges, shading
# alpha, measured legend) apply here too, but this file was NOT
# regenerated this pass - alt2 (below) is the map the user is actually
# using in the ToR now. Uncomment to refresh full_design.png with the same
# fixes:
# ggsave(here::here(analysis_dir, "coverage_map2_full_design.png"), p_titled, width = 9, height = 8.5, dpi = 130, bg = "white")
# message("Saved: coverage_map2_full_design.png")

# ==============================================================================
# Map 2 alternatives (2026-08-03) - colour hexes by which population group(s)
# are targeted there, instead of planned households. A physical hex
# (uuid_hex) can have a selected Non-IDP cluster, a selected IDP cluster, or
# both (they're sampled independently and can co-locate) - grouping by
# uuid_hex rather than uuid_hex_pop (which is pop_type-namespaced) is what
# makes "both" detectable at all.
# ==============================================================================

hex_popgroup_base <- selected_clusters %>%
  st_drop_geometry() %>%
  select(cluster_id, uuid_hex, uuid_hex_pop, adm2_pcode, pop_type) %>%
  inner_join(working_pairs, by = c("adm2_pcode", "pop_type"))

hex_popgroup <- hex_popgroup_base %>%
  distinct(uuid_hex, pop_type) %>%
  group_by(uuid_hex) %>%
  summarise(has_non_idp = any(pop_type == "non_idp"), has_idp = any(pop_type == "idp"), .groups = "drop") %>%
  mutate(popgroup_class = case_when(
    has_non_idp & has_idp ~ "Both Non-IDP and IDP",
    has_non_idp ~ "Non-IDP only",
    TRUE ~ "IDP only"
  ))

cat("\nSelected hexes by population group targeted:\n")
print(table(hex_popgroup$popgroup_class))

popgroup_levels <- c("Non-IDP only", "IDP only", "Both Non-IDP and IDP")
hex_popgroup <- hex_popgroup %>% mutate(popgroup_class = factor(popgroup_class, levels = popgroup_levels))
popgroup_colors <- setNames(c("#1B6FA8", "#E08214", "#6A3D9A"), popgroup_levels)

hex_geom_by_uuid_hex <- hex_polygons
hexes_popgroup_sf <- hex_geom_by_uuid_hex %>%
  inner_join(hex_popgroup, by = "uuid_hex") %>%
  st_transform(4326) %>%
  mutate(fill_hex = unname(popgroup_colors[as.character(popgroup_class)]))

popgroup_section <- list(title = "Population group targeted", rows = list(
  list(label = "Non-IDP only", type = "fill", color = unname(popgroup_colors[["Non-IDP only"]])),
  list(label = "IDP only", type = "fill", color = unname(popgroup_colors[["IDP only"]])),
  list(label = "Both Non-IDP and IDP", type = "fill", color = unname(popgroup_colors[["Both Non-IDP and IDP"]]))
))

build_popgroup_map <- function(unselected_section, out_file, save = TRUE, unselected_layer = list()) {

  legend_result <- build_manual_legend_panel(c(list(popgroup_section), unselected_section, list(excl_section, boundary_section)))

  p <- ggplot() +
    base_layers() +
    unselected_layer +
    geom_sf(data = admin2_excluded, aes(fill = fill_hex), color = "white", linewidth = 0.1) +
    geom_sf(data = restricted_focus, fill = "#8B4A4A", color = NA) +
    geom_sf(data = hexes_popgroup_sf, aes(fill = fill_hex), color = "grey20", linewidth = 0.08) +
    scale_fill_identity() +
    country_region_state_no_legend() +
    label_layers() +
    coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
    theme_void(base_size = 12) +
    theme(legend.position = "none")

  p_final <- draw_legend_bottom_left(p, legend_result)

  if (save) {
    ggsave(here::here(analysis_dir, out_file), p_final, width = 9, height = 8.5, dpi = 130, bg = "white")
    message("Saved: ", out_file)
  }

  p_final
}

# ---- Alt 1: selected hexes only, coloured by population group ----
# NOTE (2026-08-04): not regenerated this pass, same reasoning as
# full_design.png above - flag to the user before refreshing.
build_popgroup_map(
  unselected_section = list(),
  out_file = "coverage_map2_alt1_popgroup.png",
  save = FALSE
)

# ---- Alt 2: same, plus every non-selected hex (within sampled LGAs only -
# excluded LGAs already show solid grey/red, so their hexes are omitted to
# avoid drawing outlines under an opaque fill) as a transparent outline ----
# This is now the user's main ToR design/extent map - the one actually
# re-rendered with all three 2026-08-04 fixes.
sampled_pcodes <- admin2_status %>% filter(exclusion_class == "Sampled") %>% pull(adm2_pcode)

hex_all_sf <- hex_access %>%
  filter(adm2_pcode %in% sampled_pcodes) %>%
  st_transform(4326) %>%
  select(uuid_hex)

unselected_section <- list(title = NULL, rows = list(
  list(label = "Not selected (eligible hex)", type = "fill", color = "white")
))

build_popgroup_map(
  unselected_layer = list(geom_sf(data = hex_all_sf, fill = NA, color = "grey70", linewidth = 0.06)),
  unselected_section = list(unselected_section),
  out_file = "coverage_map2_alt2_popgroup_all_hexes.png",
  save = TRUE
)

cat("\n=== MAP 2 + ALTERNATIVES COMPLETE ===\n")
