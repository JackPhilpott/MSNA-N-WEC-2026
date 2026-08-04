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
})

output_dir   <- here::here("output")
analysis_dir <- here::here(output_dir, "maps")
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(non_idp_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_map2.R")
source("temp_stage1_map2.R")
file.remove("temp_stage1_map2.R")

# ---------------------------------------------------------------------------
# LGA-level coverage/exclusion classification (2 categories only)
# ---------------------------------------------------------------------------
coverage_summary <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_coverage_summary_v2.csv"), show_col_types = FALSE)
full_strata <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv"), show_col_types = FALSE)

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

hex_geom <- selected_clusters %>%
  distinct(uuid_hex_pop, .keep_all = TRUE) %>%
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
# - same red as the LGA "design effect" category
# ---------------------------------------------------------------------------
restricted_focus <- sf::st_intersection(sf::st_make_valid(restricted), sf::st_union(sf::st_make_valid(NGA_shapes_all_cleaned$nga_admin1 %>% filter(adm1_pcode %in% admin1_focus_areas)))) %>%
  sf::st_make_valid()

# ---------------------------------------------------------------------------
# Context layers - identical to Map 1
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

context_margin_m <- 60000
context_bbox <- sf::st_bbox(nga_all_states) + c(-context_margin_m, -context_margin_m, context_margin_m, context_margin_m)
context_extent <- sf::st_as_sfc(context_bbox, crs = sf::st_crs(nga_all_states))

neighbouring_countries <- admin0_wa_proj %>% filter(adm0_pcode != "NG") %>% st_make_valid() %>% st_intersection(context_extent)
neighbour_labels <- neighbouring_countries %>% group_by(adm0_name) %>% summarise(.groups = "drop") %>% st_point_on_surface()
cameroon_idx <- neighbour_labels$adm0_name == "Cameroon"
car_idx <- neighbour_labels$adm0_name == "Central African Republic"
st_geometry(neighbour_labels)[cameroon_idx] <- st_geometry(neighbour_labels)[cameroon_idx] + c(-20000, 150000)
st_geometry(neighbour_labels)[car_idx] <- st_geometry(neighbour_labels)[car_idx] + c(-180000, 70000)

state_labels_focus <- admin1_focus %>% st_point_on_surface()

region_code_lookup <- c("North-Central" = "NC", "North-East" = "NE", "North-West" = "NW")
region_labels_focus <- region_focus %>%
  mutate(region_code = region_code_lookup[region_label]) %>%
  st_point_on_surface()
# NC's point_on_surface lands right on top of the "Nasarawa" state label -
# nudge it west into Niger State's open interior (same manual-offset
# technique as the Cameroon/CAR nudge in the Figure 1 overview map).
nc_idx <- region_labels_focus$region_code == "NC"
st_geometry(region_labels_focus)[nc_idx] <- st_geometry(region_labels_focus)[nc_idx] + c(-120000, 40000)

extract_legend <- function(single_guide_plot) suppressWarnings(cowplot::get_legend(single_guide_plot))

boundary_labels <- c(country = "Nigeria national boundary", region = "Regional boundary (NC / NE / NW)", state = "State boundary")
boundary_colors <- setNames(c("#0A0A0A", "#1B2A4A", "grey55"), boundary_labels)
boundary_linewidths <- setNames(c(1.0, 0.7, 0.3), boundary_labels)

boundary_layers <- function() {
  list(
    geom_sf(data = admin1_focus, aes(linetype = boundary_labels[["state"]]), fill = NA, color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]]),
    geom_sf(data = region_focus, aes(linetype = boundary_labels[["region"]]), fill = NA, color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
    geom_sf(data = nigeria_boundary, aes(linetype = boundary_labels[["country"]]), fill = NA, color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]]),
    scale_linetype_manual(
      name = NULL, values = setNames(rep("solid", 3), boundary_labels),
      guide = guide_legend(override.aes = list(color = unname(boundary_colors[boundary_labels]), linewidth = unname(boundary_linewidths[boundary_labels])), order = 10)
    )
  )
}
country_region_state_no_legend <- function() {
  list(
    geom_sf(data = admin1_focus, fill = NA, color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]]),
    geom_sf(data = region_focus, fill = NA, color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
    geom_sf(data = nigeria_boundary, fill = NA, color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]])
  )
}
base_layers <- function() {
  list(
    geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25),
    geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2)
  )
}

# Shared label layers (neighbouring countries, state names, region codes) -
# used identically across all three map variants below.
label_layers <- function() {
  list(
    ggrepel::geom_text_repel(
      data = neighbour_labels, aes(label = adm0_name, geometry = geometry), stat = "sf_coordinates",
      size = 4.0, color = "grey35", fontface = "italic", bg.color = "white", bg.r = 0.12, seed = 1,
      xlim = c(unname(context_bbox["xmin"]) + 20000, unname(context_bbox["xmax"]) - 140000)
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

# ==============================================================================
# Map 2
# ==============================================================================

excl_colors <- c("Excluded: no partner coverage" = "grey75", "Excluded: design effect" = "#8B4A4A")

legend_excl <- extract_legend(
  ggplot() + geom_sf(data = admin2_excluded, aes(fill = exclusion_class)) +
    scale_fill_manual(values = excl_colors, name = NULL, drop = FALSE) + theme_void(base_size = 12) +
    theme(legend.text = element_text(size = 7.2), legend.key.size = unit(0.35, "cm"), legend.spacing.y = unit(0.03, "cm"), legend.margin = margin(0,0,0,0))
)
legend_hex <- extract_legend(
  ggplot() + geom_sf(data = hexes_sf, aes(fill = hh_class)) +
    scale_fill_manual(values = hex_colors, name = "Planned interviews\nper hex", drop = FALSE) + theme_void(base_size = 12) +
    theme(legend.title = element_text(size = 8, face = "bold"), legend.text = element_text(size = 7.2), legend.key.size = unit(0.35, "cm"), legend.spacing.y = unit(0.03, "cm"), legend.margin = margin(0,0,0,0))
)
legend_boundaries <- extract_legend(
  ggplot() + boundary_layers() + theme_void(base_size = 12) +
    theme(legend.text = element_text(size = 7.0), legend.key.size = unit(0.45, "cm"), legend.spacing.y = unit(0.02, "cm"), legend.margin = margin(0,0,0,0))
)

legend_combined <- cowplot::plot_grid(legend_hex, legend_excl, legend_boundaries, ncol = 1, rel_heights = c(0.36, 0.28, 0.36), align = "v")

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
  geom_sf(data = restricted_focus, fill = "#8B4A4A", color = NA, alpha = 0.8) +
  geom_sf(data = hexes_sf, aes(fill = fill_hex), color = "grey20", linewidth = 0.08) +
  scale_fill_identity() +
  country_region_state_no_legend() +
  label_layers() +
  coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
  theme_void(base_size = 12) +
  theme(legend.position = "none")

legend_title <- cowplot::ggdraw() + cowplot::draw_label("Legend", fontface = "bold", size = 12, colour = "grey15", x = 0.04, hjust = 0)
legend_panel <- cowplot::plot_grid(legend_title, legend_combined, ncol = 1, rel_heights = c(0.08, 0.92)) +
  theme(plot.background = element_rect(fill = "white", color = "grey60", linewidth = 0.5), plot.margin = margin(3, 5, 3, 5))

# Anchored with a real bottom margin (y=0.06, not 0.02) - previously the
# legend box's bottom edge sat almost flush with the canvas edge and read
# as clipped/falling out of frame.
p_titled <- cowplot::ggdraw(p_no_legend) +
  cowplot::draw_plot(legend_panel, x = 0.62, y = 0.06, width = 0.36, height = 0.28)

ggsave(here::here(analysis_dir, "coverage_map2_full_design.png"), p_titled, width = 9, height = 8.5, dpi = 130, bg = "white")
message("Saved: coverage_map2_full_design.png")

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

hex_geom_by_uuid_hex <- selected_clusters %>% distinct(uuid_hex, .keep_all = TRUE) %>% select(uuid_hex)
hexes_popgroup_sf <- hex_geom_by_uuid_hex %>%
  inner_join(hex_popgroup, by = "uuid_hex") %>%
  st_transform(4326) %>%
  mutate(fill_hex = unname(popgroup_colors[as.character(popgroup_class)]))

legend_popgroup <- extract_legend(
  ggplot() + geom_sf(data = hexes_popgroup_sf, aes(fill = popgroup_class)) +
    scale_fill_manual(values = popgroup_colors, name = "Population group\ntargeted", drop = FALSE) + theme_void(base_size = 12) +
    theme(legend.title = element_text(size = 8, face = "bold"), legend.text = element_text(size = 7.2), legend.key.size = unit(0.35, "cm"), legend.spacing.y = unit(0.03, "cm"), legend.margin = margin(0,0,0,0))
)

build_popgroup_map <- function(unselected_layer, extra_legend, out_file, legend_rel_heights) {
  legend_combined_pg <- cowplot::plot_grid(plotlist = c(list(legend_popgroup), extra_legend, list(legend_excl, legend_boundaries)), ncol = 1, rel_heights = legend_rel_heights, align = "v")

  p <- ggplot() +
    base_layers() +
    unselected_layer +
    geom_sf(data = admin2_excluded, aes(fill = fill_hex), color = "white", linewidth = 0.1) +
    geom_sf(data = restricted_focus, fill = "#8B4A4A", color = NA, alpha = 0.8) +
    geom_sf(data = hexes_popgroup_sf, aes(fill = fill_hex), color = "grey20", linewidth = 0.08) +
    scale_fill_identity() +
    country_region_state_no_legend() +
    label_layers() +
    coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
    theme_void(base_size = 12) +
    theme(legend.position = "none")

  panel <- cowplot::plot_grid(legend_title, legend_combined_pg, ncol = 1, rel_heights = c(0.07, 0.93)) +
    theme(plot.background = element_rect(fill = "white", color = "grey60", linewidth = 0.5), plot.margin = margin(3, 5, 3, 5))

  p_final <- cowplot::ggdraw(p) + cowplot::draw_plot(panel, x = 0.62, y = 0.06, width = 0.36, height = 0.32)
  ggsave(here::here(analysis_dir, out_file), p_final, width = 9, height = 8.5, dpi = 130, bg = "white")
  message("Saved: ", out_file)
}

# ---- Alt 1: selected hexes only, coloured by population group ----
build_popgroup_map(
  unselected_layer = list(),
  extra_legend = list(),
  out_file = "coverage_map2_alt1_popgroup.png",
  legend_rel_heights = c(0.28, 0.24, 0.24)
)

# ---- Alt 2: same, plus every non-selected hex (within sampled LGAs only -
# excluded LGAs already show solid grey/red, so their hexes are omitted to
# avoid drawing outlines under an opaque fill) as a transparent outline ----
sampled_pcodes <- admin2_status %>% filter(exclusion_class == "Sampled") %>% pull(adm2_pcode)

hex_all_sf <- hex_access %>%
  filter(adm2_pcode %in% sampled_pcodes) %>%
  st_transform(4326) %>%
  select(uuid_hex)

label_unselected <- "Not selected (eligible hex)"
legend_unselected <- extract_legend(
  ggplot() + geom_sf(data = hex_all_sf, aes(color = label_unselected), fill = NA) +
    scale_color_manual(values = setNames("grey55", label_unselected), name = NULL) + theme_void(base_size = 12) +
    theme(legend.text = element_text(size = 7.2), legend.key.size = unit(0.35, "cm"), legend.margin = margin(0,0,0,0))
)

build_popgroup_map(
  unselected_layer = list(geom_sf(data = hex_all_sf, fill = NA, color = "grey70", linewidth = 0.06)),
  extra_legend = list(legend_unselected),
  out_file = "coverage_map2_alt2_popgroup_all_hexes.png",
  legend_rel_heights = c(0.26, 0.14, 0.20, 0.24)  # popgroup, unselected, excl, boundaries - 4 blocks
)

cat("\n=== MAP 2 + ALTERNATIVES COMPLETE ===\n")
