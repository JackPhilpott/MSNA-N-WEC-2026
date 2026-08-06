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
# Revision 2026-08-05 - same legend/label formatting established on
# coverage_map2 applied here for consistency across both ToR maps:
#   1. Legend rebuilt as a hand-positioned grid layout
#      (build_manual_legend_panel()) instead of stacked cowplot::
#      get_legend() guides - guarantees every swatch/label shares the same
#      left edge (different guide types have different internal padding,
#      so stacking extracted guides never actually aligned), sized to its
#      own content (no dead whitespace), text/swatches enlarged for
#      readability, boundary rows drawn as plain line samples (no bordered
#      box - an earlier attempt on map2 wrapped lines in a box and it read
#      as a broken icon).
#   2. Legend anchored bottom-left (was bottom-right) - more unused map
#      space there.
#   3. Country labels: dropped Burkina Faso/Mali/Central African Republic
#      (grey landmass still shows, just unlabelled) - kept Niger, Chad,
#      Benin, Cameroon, Equatorial Guinea. Fixed the xlim asymmetry
#      (xmax-140000 on the right only) that dragged Chad/CAR's label into
#      Nigeria, to a small symmetric inset instead, plus small manual
#      nudges for Cameroon/Chad to settle in their own open space.
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
  library(grid)
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

# Kept at 60km - same "as zoomed to Nigeria as possible" reasoning as
# coverage_map2.
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

# Drop 3 country labels the map doesn't need (grey landmass still shows) -
# kept: Niger, Chad, Benin, Cameroon, Equatorial Guinea.
neighbour_labels <- neighbour_labels %>%
  filter(!adm0_name %in% c("Burkina Faso", "Mali", "Central African Republic"))

# Small manual nudges for the 2 neighbours whose clipped-to-context
# centroid lands somewhere unhelpful at this tight margin - same offsets
# as coverage_map2 (identical geometry/margin).
cameroon_idx <- neighbour_labels$adm0_name == "Cameroon"
chad_idx <- neighbour_labels$adm0_name == "Chad"
st_geometry(neighbour_labels)[cameroon_idx] <- st_geometry(neighbour_labels)[cameroon_idx] + c(60000, 30000)
st_geometry(neighbour_labels)[chad_idx] <- st_geometry(neighbour_labels)[chad_idx] + c(15000, 40000)

state_labels_focus <- admin1_focus %>% st_point_on_surface()

# Region-code (NC/NE/NW) labels - added 2026-08-06 to match coverage_map2's
# treatment. Same technique: point_on_surface per dissolved region, with
# NC nudged off the "Nasarawa" state label into Niger State's open interior
# (identical offset to coverage_map2, same geometry/margin).
region_code_lookup <- c("North-Central" = "NC", "North-East" = "NE", "North-West" = "NW")
region_labels_focus <- region_focus %>%
  mutate(region_code = region_code_lookup[region_label]) %>%
  st_point_on_surface()
nc_idx <- region_labels_focus$region_code == "NC"
st_geometry(region_labels_focus)[nc_idx] <- st_geometry(region_labels_focus)[nc_idx] + c(-120000, 40000)

# ---------------------------------------------------------------------------
# Boundary line styling - country thickest/black, region medium/navy
# (the old state style), state thin/grey (so all three read distinctly
# without competing). No ggplot legend guide needed - the legend rows are
# hand-drawn by build_manual_legend_panel() below.
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
# Hand-positioned legend panel - identical implementation to
# coverage_map2.R's build_manual_legend_panel()/draw_legend_bottom_left();
# duplicated here rather than shared, matching this project's existing
# convention of each analysis_coverage_map*.R script being fully
# standalone (see either script's own header comment).
# ---------------------------------------------------------------------------
build_manual_legend_panel <- function(sections, swatch_cm = 0.45, title_size = 17,
                                        section_title_size = 11, item_size = 10,
                                        row_gap_cm = 0.16, section_gap_cm = 0.30,
                                        title_gap_cm = 0.22, swatch_label_gap_cm = 0.18,
                                        fig_width_in = 9, fig_height_in = 8.5,
                                        margin_cm = c(t = 0.4, r = 0.5, b = 0.35, l = 0.45)) {

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

  make_swatch_grob <- function(row, x_cm, y_cm) {
    vp <- grid::viewport(x = unit(x_cm, "cm"), y = unit(y_cm, "cm"), width = unit(swatch_cm, "cm"), height = unit(swatch_cm, "cm"), just = c("left", "center"))
    if (row$type == "fill") {
      grid::grobTree(grid::rectGrob(gp = grid::gpar(fill = row$color, col = "grey30", lwd = 0.6)), vp = vp)
    } else {
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
  y_cursor_cm <- total_height_cm - margin_cm[["t"]]

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

draw_legend_bottom_left <- function(base_plot, legend_result, margin_npc_x = 0.015, margin_npc_y = 0.02) {
  cowplot::ggdraw(base_plot) +
    cowplot::draw_grob(
      legend_result$grob,
      x = margin_npc_x, y = margin_npc_y,
      width = legend_result$width_npc, height = legend_result$height_npc
    )
}

# ==============================================================================
# Map 1 - binary sampled/excluded
# ==============================================================================

fill_colors <- c("Sampled" = "#2E7D32", "Excluded" = "grey75")

fill_section <- list(title = NULL, rows = list(
  list(label = "Sampled", type = "fill", color = unname(fill_colors[["Sampled"]])),
  list(label = "Excluded", type = "fill", color = unname(fill_colors[["Excluded"]]))
))
boundary_section <- list(title = NULL, rows = list(
  list(label = "Nigeria national boundary", type = "line", color = boundary_colors[["Nigeria national boundary"]], linewidth = boundary_linewidths[["Nigeria national boundary"]]),
  list(label = "Regional boundary (NC / NE / NW)", type = "line", color = boundary_colors[["Regional boundary (NC / NE / NW)"]], linewidth = boundary_linewidths[["Regional boundary (NC / NE / NW)"]]),
  list(label = "State boundary", type = "line", color = boundary_colors[["State boundary"]], linewidth = boundary_linewidths[["State boundary"]])
))

legend_result <- build_manual_legend_panel(list(fill_section, boundary_section))

p_no_legend <- ggplot() +
  base_layers() +
  geom_sf(data = admin2_focus, aes(fill = binary_status), color = "white", linewidth = 0.1) +
  scale_fill_manual(values = fill_colors, name = NULL, guide = "none") +
  country_region_state_no_legend() +
  label_layers() +
  coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
  theme_void(base_size = 12) +
  theme(legend.position = "none")

p_titled <- draw_legend_bottom_left(p_no_legend, legend_result)

ggsave(here::here(analysis_dir, "coverage_map1_partner_coverage.png"), p_titled, width = 9, height = 8.5, dpi = 130, bg = "white")
message("Saved: coverage_map1_partner_coverage.png")

cat("\n=== MAP 1 COMPLETE ===\n")
