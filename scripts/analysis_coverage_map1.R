# ==============================================================================
# Coverage Map 1 (final) - plain partner-coverage map for the ToR's main
# methodology section. Binary sampled/excluded fill (the old "v2"),
# extended per user feedback 2026-07-31 with:
#   - a regional (NC/NE/NW) boundary layer, styled like the old state
#     layer (solid navy, medium weight)
#   - a state boundary layer, now thin grey (so it doesn't compete with
#     the region layer)
#   - a Nigeria national boundary, solid black, slightly thicker than the
#     regional layer
#   - all three boundary layers added to the legend
#   - tightened legend-panel whitespace
#
# Lightweight load: sources the main pipeline only up to
# NGA_shapes_all_cleaned (~line 294) - no Stage 1/hex/worldpop needed for
# this map.
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
  "^NGA_shapes_all_cleaned <- lapply\\(NGA_shapes_all\\[layers_to_process\\], process_spatial_layer\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_shapes_only1.R")
source("temp_shapes_only1.R")
file.remove("temp_shapes_only1.R")

coverage_summary <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_coverage_summary_v2.csv"), show_col_types = FALSE)

admin2_focus <- NGA_shapes_all_cleaned$nga_admin2 %>%
  filter(adm1_pcode %in% admin1_focus_areas) %>%
  left_join(coverage_summary %>% select(-region), by = "adm2_pcode") %>%
  mutate(binary_status = if_else(coverage_status == "covered", "Sampled", "Excluded"))

stopifnot(nrow(admin2_focus) == 323, sum(is.na(admin2_focus$coverage_status)) == 0)

# ---------------------------------------------------------------------------
# Context layers: state, region (dissolved from state via a hardcoded,
# already-verified 14-state lookup - simpler and safer than depending on
# a region column existing on the raw admin1 shapefile), Nigeria national
# boundary, neighbouring countries.
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

region_focus <- admin1_focus %>%
  group_by(region_label) %>%
  summarise(.groups = "drop") %>%
  st_make_valid()

nigeria_boundary <- admin0_wa_proj %>% filter(adm0_pcode == "NG") %>% st_make_valid()

nga_all_states <- NGA_shapes_all$nga_admin1

context_margin_m <- 60000
context_bbox <- sf::st_bbox(nga_all_states) + c(-context_margin_m, -context_margin_m, context_margin_m, context_margin_m)
context_extent <- sf::st_as_sfc(context_bbox, crs = sf::st_crs(nga_all_states))

neighbouring_countries <- admin0_wa_proj %>%
  filter(adm0_pcode != "NG") %>%
  st_make_valid() %>%
  st_intersection(context_extent)

neighbour_labels <- neighbouring_countries %>%
  group_by(adm0_name) %>%
  summarise(.groups = "drop") %>%
  st_point_on_surface()

cameroon_idx <- neighbour_labels$adm0_name == "Cameroon"
car_idx <- neighbour_labels$adm0_name == "Central African Republic"
st_geometry(neighbour_labels)[cameroon_idx] <- st_geometry(neighbour_labels)[cameroon_idx] + c(-20000, 150000)
st_geometry(neighbour_labels)[car_idx] <- st_geometry(neighbour_labels)[car_idx] + c(-180000, 70000)

state_labels_focus <- admin1_focus %>% st_point_on_surface()

extract_legend <- function(single_guide_plot) suppressWarnings(cowplot::get_legend(single_guide_plot))

# ---------------------------------------------------------------------------
# Boundary line styling - country thickest/black, region medium/navy
# (the old state style), state thin/grey (so all three read distinctly
# without competing).
# ---------------------------------------------------------------------------
boundary_labels <- c(
  country = "Nigeria national boundary",
  region  = "Regional boundary (NC / NE / NW)",
  state   = "State boundary"
)
boundary_colors    <- setNames(c("#0A0A0A", "#1B2A4A", "grey55"), boundary_labels)
boundary_linewidths <- setNames(c(1.0, 0.7, 0.3), boundary_labels)

boundary_layers <- function() {
  list(
    geom_sf(data = admin1_focus, aes(linetype = boundary_labels[["state"]]), fill = NA, color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]]),
    geom_sf(data = region_focus, aes(linetype = boundary_labels[["region"]]), fill = NA, color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
    geom_sf(data = nigeria_boundary, aes(linetype = boundary_labels[["country"]]), fill = NA, color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]]),
    scale_linetype_manual(
      name = NULL,
      values = setNames(rep("solid", 3), boundary_labels),
      guide = guide_legend(override.aes = list(color = unname(boundary_colors[boundary_labels]), linewidth = unname(boundary_linewidths[boundary_labels])), order = 10)
    )
  )
}

base_layers <- function() {
  list(
    geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25),
    geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2)
  )
}

country_region_state_no_legend <- function() {
  list(
    geom_sf(data = admin1_focus, fill = NA, color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]]),
    geom_sf(data = region_focus, fill = NA, color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
    geom_sf(data = nigeria_boundary, fill = NA, color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]])
  )
}

# ==============================================================================
# Map 1 - binary sampled/excluded
# ==============================================================================

fill_colors <- c("Sampled" = "#2E7D32", "Excluded" = "grey75")

legend_fill <- extract_legend(
  ggplot() + geom_sf(data = admin2_focus, aes(fill = binary_status)) +
    scale_fill_manual(values = fill_colors, name = NULL) + theme_void(base_size = 12) +
    theme(legend.text = element_text(size = 7.5), legend.key.size = unit(0.38, "cm"), legend.spacing.y = unit(0.04, "cm"),
          legend.margin = margin(0, 0, 0, 0))
)
legend_boundaries <- extract_legend(
  ggplot() + boundary_layers() + theme_void(base_size = 12) +
    theme(legend.text = element_text(size = 7.2), legend.key.size = unit(0.5, "cm"), legend.spacing.y = unit(0.02, "cm"),
          legend.margin = margin(0, 0, 0, 0))
)

legend_combined <- cowplot::plot_grid(legend_fill, legend_boundaries, ncol = 1, rel_heights = c(0.35, 0.65), align = "v")

p_no_legend <- ggplot() +
  base_layers() +
  geom_sf(data = admin2_focus, aes(fill = binary_status), color = "white", linewidth = 0.1) +
  scale_fill_manual(values = fill_colors, name = NULL, guide = "none") +
  country_region_state_no_legend() +
  ggrepel::geom_text_repel(
    data = neighbour_labels, aes(label = adm0_name, geometry = geometry), stat = "sf_coordinates",
    size = 4.0, color = "grey35", fontface = "italic", bg.color = "white", bg.r = 0.12, seed = 1,
    xlim = c(unname(context_bbox["xmin"]) + 20000, unname(context_bbox["xmax"]) - 140000)
  ) +
  ggrepel::geom_text_repel(
    data = state_labels_focus, aes(label = adm1_name, geometry = geometry), stat = "sf_coordinates",
    size = 2.8, color = "#1B2A4A", fontface = "bold", bg.color = "white", bg.r = 0.12, seed = 1
  ) +
  coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
  theme_void(base_size = 12) +
  theme(legend.position = "none")

legend_title <- cowplot::ggdraw() + cowplot::draw_label("Legend", fontface = "bold", size = 12, colour = "grey15", x = 0.04, hjust = 0)
legend_panel <- cowplot::plot_grid(legend_title, legend_combined, ncol = 1, rel_heights = c(0.11, 0.89)) +
  theme(plot.background = element_rect(fill = "white", color = "grey60", linewidth = 0.5), plot.margin = margin(3, 5, 3, 5))

p_titled <- cowplot::ggdraw(p_no_legend) +
  cowplot::draw_plot(legend_panel, x = 0.62, y = 0.02, width = 0.36, height = 0.20)

ggsave(here::here(analysis_dir, "coverage_map1_partner_coverage.png"), p_titled, width = 9, height = 8.5, dpi = 130, bg = "white")
message("Saved: coverage_map1_partner_coverage.png")

cat("\n=== MAP 1 COMPLETE ===\n")
