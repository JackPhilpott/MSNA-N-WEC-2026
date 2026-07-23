# ==============================================================================
# Round 2 of methodology maps:
#   1. National assessment-area overview: Non-IDP population raster (gradient),
#      IOM DTM IDP sites (population-scaled points), and excluded
#      (inaccessible) areas overlaid.
#   2. Revised Non-IDP example cluster - denser building footprints, bordered/
#      fillable markers with transparency so buildings show through.
#   3. New Non-IDP close-up (mirrors the IDP close-up) - ground-level look at
#      the selected households against nearby buildings.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
  library(terra)
  library(ggrepel)
  library(cowplot)
})

# Tile downloads from the basemap provider have been intermittently flaky
# in this environment (transient DNS/HTTP failures, not a code issue) -
# retry a few times with a short pause before giving up, rather than
# forcing a full script rerun (which redoes every earlier, already-
# successful step) for what's usually a transient failure.
get_tiles_retry <- function(..., max_attempts = 5, pause_s = 5) {
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(maptiles::get_tiles(...), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    message("get_tiles() attempt ", attempt, "/", max_attempts, " failed: ", conditionMessage(result))
    if (attempt < max_attempts) Sys.sleep(pause_s)
  }
  stop("get_tiles() failed after ", max_attempts, " attempts: ", conditionMessage(result))
}

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(non_idp_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_only.R")
source("temp_stage1_only.R")

dir.create("output/images", showWarnings = FALSE)

households_all <- sf::st_read("output/stage2_sampling_frame.gpkg", quiet = TRUE)

# ---------------------------------------------------------------------------
# Map 1: national overview - population raster + IDP sites + excluded areas
# (unaffected by the Stage 2 building-consolidation fix - skip re-render if
# already produced)
# ---------------------------------------------------------------------------

admin1_focus <- NGA_shapes_all_cleaned$nga_admin1 %>%
  dplyr::filter(adm1_pcode %in% admin1_focus_areas)

admin1_focus_union <- sf::st_union(sf::st_make_valid(admin1_focus))

worldpop_focus <- terra::crop(worldpop_pop, terra::vect(admin1_focus))
worldpop_focus <- terra::mask(worldpop_focus, terra::vect(admin1_focus))
# Also mask out the excluded zone itself (border buffer + FACT inaccessible
# admin-3s) - accessible_area already = admin1 minus restricted, so this
# leaves population showing only within the actual sampling universe rather
# than bleeding through under the grey excluded-area overlay.
worldpop_focus <- terra::mask(worldpop_focus, terra::vect(sf::st_make_valid(accessible_area)))

restricted_focus <- sf::st_intersection(sf::st_make_valid(restricted), admin1_focus_union) %>%
  sf::st_make_valid()

accessible_area_focus <- sf::st_intersection(sf::st_make_valid(accessible_area), admin1_focus_union) %>%
  sf::st_make_valid()

# IDP sites are kept only if they fall INSIDE the accessible area - a
# positive inclusion test against accessible_area_focus, matching how the
# Non-IDP population raster is now masked, rather than a "disjoint from the
# excluded zone" test (which would incorrectly keep a site that's outside
# the excluded zone but also outside the accessible area entirely).
idp_sites_focus <- iom_idp_df %>%
  dplyr::filter(!is.na(individuals), individuals > 0) %>%
  sf::st_transform(sf::st_crs(accessible_area_focus)) %>%
  sf::st_filter(accessible_area_focus, .predicate = sf::st_within)

# ---------------------------------------------------------------------------
# National/regional context layers: every Nigerian state (not just the 14
# assessment states), a thin margin of neighbouring countries so a reader
# can place Nigeria regionally, and labels for both the assessment states
# and the neighbouring countries.
# ---------------------------------------------------------------------------

# NGA_shapes_all_cleaned$nga_admin1 is already filtered to the 14 focus
# states (process_spatial_layer() applies admin1_focus_areas to every
# layer) - the pre-filter object with all 37 Nigerian states is
# NGA_shapes_all$nga_admin1 instead.
nga_all_states <- NGA_shapes_all$nga_admin1

context_margin_m <- 60000  # 60km - just enough for neighbouring-country
                            # labels to sit comfortably, not a wide margin
                            # of surrounding-country territory
context_bbox <- sf::st_bbox(nga_all_states) + c(-context_margin_m, -context_margin_m, context_margin_m, context_margin_m)
context_extent <- sf::st_as_sfc(context_bbox, crs = sf::st_crs(nga_all_states))

neighbouring_countries <- admin0_wa_proj %>%
  dplyr::filter(adm0_pcode != "NG") %>%
  sf::st_make_valid() %>%
  sf::st_intersection(context_extent)

neighbour_labels <- neighbouring_countries %>%
  dplyr::group_by(adm0_name) %>%
  dplyr::summarise(.groups = "drop") %>%
  sf::st_point_on_surface()

state_labels_focus <- admin1_focus %>%
  sf::st_point_on_surface()

# Shared building blocks so the population fill scale and excluded-zone
# label can't drift out of sync between the map layers and the various
# legend-extraction mini-plots below.
#
# breaks are chosen explicitly (not left to default) because log1p
# compresses the high end of the scale - evenly-spaced raw values like
# 0/100/200/300 end up bunched together visually however long the bar is,
# since log1p(100)->log1p(200) is a much smaller step than
# log1p(0)->log1p(100). Fewer, wider-spaced breaks read cleanly instead.
population_fill_scale <- function() {
  scale_fill_gradientn(
    colors = c("#FFFFFF00", "#FFF2AE", "#FDB863", "#E08214", "#B2182B"),
    na.value = "transparent",
    trans = "log1p",
    breaks = c(0, 50, 300),
    name = "Non-IDP population\nper grid cell"
  )
}
excluded_zone_label <- "Excluded from sampling universe"  # full border-buffer/admin-3 detail now lives in the doc caption, not this key

# No title/subtitle/caption text on the image itself - all of that moves
# into a figure caption in the methodology doc instead (see the doc's
# placeholder for this map). The legend is the only in-image text.
p_overview_base <- ggplot() +
  geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25) +
  geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2) +
  tidyterra::geom_spatraster(data = worldpop_focus, maxcell = 3e6) +
  population_fill_scale() +
  geom_sf(data = restricted_focus, aes(color = excluded_zone_label), fill = "grey25", alpha = 0.65, linewidth = 0.3) +
  scale_color_manual(
    values = setNames("grey25", excluded_zone_label),
    name = NULL,
    guide = guide_legend(override.aes = list(fill = "grey25", alpha = 0.65, linewidth = 0), order = 2)
  ) +
  # Assessment-state boundary gets its own (line-style) legend entry, kept
  # as a separate aesthetic (linetype, not color) so it doesn't merge into
  # the excluded-zone swatch legend above.
  geom_sf(data = admin1_focus, aes(linetype = "Assessment states (14)"), fill = NA, color = "#1B2A4A", linewidth = 0.7) +
  scale_linetype_manual(
    name = NULL,
    values = c("Assessment states (14)" = "solid"),
    guide = guide_legend(override.aes = list(color = "#1B2A4A", linewidth = 0.7), order = 1)
  ) +
  geom_sf(data = idp_sites_focus, aes(size = individuals), color = "#1B6FA8", alpha = 0.8, shape = 16) +
  scale_size_continuous(range = c(0.4, 5), name = "IDP site\npopulation") +
  ggrepel::geom_text_repel(
    data = state_labels_focus,
    aes(label = adm1_name, geometry = geometry),
    stat = "sf_coordinates",
    size = 2.8, color = "#1B2A4A", fontface = "bold",
    bg.color = "white", bg.r = 0.12, seed = 1
  ) +
  coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
  theme_void(base_size = 12)

extract_legend <- function(single_guide_plot) {
  suppressWarnings(cowplot::get_legend(single_guide_plot))
}

# ---- Legend inset in the map's bottom-right corner (over the Cameroon/CAR
# area, clear of Nigeria's own territory) ----
# A "legend below the map" layout was also tried and works, but the inset
# was preferred (2026-07-23) - kept as the only version going forward.
#
# Built as a fully separate, fixed-size composite (title + legend + border
# all baked into one grob together, via cowplot) rather than relying on
# ggplot's own legend.position="inside" auto-sizing - that approach kept
# growing toward the plot centre as content changed and needed constant
# manual re-guessing of where its edges landed. draw_plot()'s explicit
# width/height instead *forces* the whole panel into a fixed corner
# footprint regardless of content size.

# Nudge Cameroon and Central African Republic's labels up and left, away
# from the corner the legend panel will occupy - a manual fix since
# ggrepel's collision-avoidance has no visibility into a grob composited
# on afterward. Indexed geometry assignment (rather than case_when on the
# sfc column) keeps the sfc class/CRS intact.
neighbour_labels_inset <- neighbour_labels
cameroon_idx <- neighbour_labels_inset$adm0_name == "Cameroon"
car_idx <- neighbour_labels_inset$adm0_name == "Central African Republic"
sf::st_geometry(neighbour_labels_inset)[cameroon_idx] <-
  sf::st_geometry(neighbour_labels_inset)[cameroon_idx] + c(-20000, 150000)
sf::st_geometry(neighbour_labels_inset)[car_idx] <-
  sf::st_geometry(neighbour_labels_inset)[car_idx] + c(-180000, 70000)

p_map_inset_no_legend <- p_overview_base +
  ggrepel::geom_text_repel(
    data = neighbour_labels_inset,
    aes(label = adm0_name, geometry = geometry),
    stat = "sf_coordinates",
    size = 4.0, color = "grey35", fontface = "italic",
    bg.color = "white", bg.r = 0.12, seed = 1,
    xlim = c(unname(context_bbox["xmin"]) + 20000, unname(context_bbox["xmax"]) - 140000)
  ) +
  theme(legend.position = "none")

legend_combined_inset <- extract_legend(
  ggplot() +
    geom_sf(data = admin1_focus, aes(linetype = "Assessment states (14)"), fill = NA, color = "#1B2A4A", linewidth = 0.7) +
    scale_linetype_manual(name = NULL, values = c("Assessment states (14)" = "solid"),
                           guide = guide_legend(override.aes = list(color = "#1B2A4A", linewidth = 0.7), order = 1)) +
    geom_sf(data = restricted_focus, aes(color = excluded_zone_label), fill = "grey25", alpha = 0.65, linewidth = 0.3) +
    scale_color_manual(name = NULL, values = setNames("grey25", excluded_zone_label),
                        guide = guide_legend(override.aes = list(fill = "grey25", alpha = 0.65, linewidth = 0), order = 2)) +
    tidyterra::geom_spatraster(data = worldpop_focus, maxcell = 3e5) +
    population_fill_scale() +
    geom_sf(data = idp_sites_focus, aes(size = individuals), color = "#1B6FA8", alpha = 0.8, shape = 16) +
    scale_size_continuous(range = c(0.4, 5), name = "IDP site\npopulation") +
    guides(
      fill = guide_colorbar(direction = "vertical", barwidth = unit(0.3, "cm"), barheight = unit(2.2, "cm"), order = 3),
      size = guide_legend(order = 4)
    ) +
    theme_void(base_size = 12) +
    theme(
      legend.position = "right",
      legend.box = "vertical",
      legend.title = element_text(size = 8, face = "bold"),
      legend.text = element_text(size = 7),
      legend.key.size = unit(0.38, "cm"),
      legend.spacing.y = unit(0.12, "cm"),
      legend.background = element_blank()
    )
)

legend_title_inset <- cowplot::ggdraw() +
  cowplot::draw_label("Legend", fontface = "bold", size = 12, colour = "grey15", x = 0.04, hjust = 0)

legend_panel_inset <- cowplot::plot_grid(legend_title_inset, legend_combined_inset, ncol = 1, rel_heights = c(0.09, 0.91)) +
  theme(
    plot.background = element_rect(fill = "white", color = "grey60", linewidth = 0.5),
    plot.margin = margin(4, 6, 4, 6)
  )

p_overview_inset_titled <- cowplot::ggdraw(p_map_inset_no_legend) +
  # Fixed footprint anchored at the true bottom-right corner - genuinely
  # corner-fixed regardless of legend content size, rather than an
  # auto-sized box anchored at one point that can visually sprawl toward
  # the centre. width/height are sized close to the panel's actual content
  # (not an oversized box) to avoid dead white space inside the border.
  cowplot::draw_plot(legend_panel_inset, x = 0.65, y = 0.01, width = 0.33, height = 0.35)

ggsave("output/images/methodology_map_overview_legend_inset.png", p_overview_inset_titled, width = 9, height = 8.5, dpi = 130, bg = "white")
cat("Saved overview map (legend inset)\n")

cat(
  "Overview map stats for the doc caption: ", nrow(admin1_focus), " assessment states, ",
  nrow(nga_all_states), " total Nigerian states, ", nrow(idp_sites_focus), " IOM DTM sites\n",
  sep = ""
)

# ---------------------------------------------------------------------------
# Shared: fetch fresh building POLYGONS for a single cluster (mirrors
# archive/render_example_maps.R's approach - the main pipeline only keeps
# centroids)
# ---------------------------------------------------------------------------

source("scripts/02_stage2_building_ingestion.R")

fetch_cluster_buildings <- function(hex_row) {

  hex_wgs84 <- sf::st_transform(hex_row, 4326)
  bbox_wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(hex_wgs84)))

  gdb_files <- list.dirs(building_data_dir, recursive = TRUE, full.names = TRUE) |>
    stringr::str_subset("\\.gdb$")

  poly_list <- purrr::map(gdb_files, function(gdb_path) {

    layers <- sf::st_layers(gdb_path)$name
    building_layer <- layers[stringr::str_detect(tolower(layers), "build")][1]

    sample_row <- sf::st_read(gdb_path, query = paste0('SELECT * FROM "', building_layer, '" LIMIT 1'), quiet = TRUE)

    confidence_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("confidence", ignore_case = TRUE))][1]
    area_field <- names(sample_row)[stringr::str_detect(names(sample_row), regex("^area", ignore_case = TRUE))]
    has_area_field <- length(area_field) > 0
    area_field <- if(has_area_field) area_field[1] else NA_character_

    where_parts <- paste0('"', confidence_field, '" >= 0.75')
    if(has_area_field) {
      where_parts <- c(where_parts, paste0('"', area_field, '" >= 12'), paste0('"', area_field, '" <= 1000'))
    }
    where_clause <- paste(where_parts, collapse = " AND ")

    tryCatch({
      result <- sf::st_read(
        gdb_path,
        query = paste0('SELECT * FROM "', building_layer, '" WHERE ', where_clause),
        wkt_filter = bbox_wkt,
        quiet = TRUE
      ) %>%
        sf::st_transform(mycrs) %>%
        sf::st_filter(sf::st_transform(hex_row, mycrs), .predicate = sf::st_intersects)

      if(!has_area_field) {
        result <- result %>%
          dplyr::mutate(building_area_m2 = as.numeric(sf::st_area(geometry))) %>%
          dplyr::filter(building_area_m2 <= 1000, building_area_m2 >= 12)
      }

      result
    }, error = function(e) NULL)

  })

  dplyr::bind_rows(poly_list)

}

# ---------------------------------------------------------------------------
# Map 2 + 3: revised Non-IDP example - denser cluster, improved marker
# styling, plus a new close-up.
# ---------------------------------------------------------------------------

non_idp_example_id <- "non_idp_NG023010_1"

hh <- households_all %>% dplyr::filter(cluster_id == non_idp_example_id)

hex <- selected_clusters %>%
  dplyr::filter(cluster_id == non_idp_example_id) %>%
  dplyr::distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  dplyr::slice(1)

stopifnot(nrow(hex) == 1, nrow(hh) > 0)

buildings_full <- fetch_cluster_buildings(hex)

cat("Non-IDP example:", non_idp_example_id, "-", nrow(buildings_full), "eligible buildings,", nrow(hh), "households\n")

hex_wgs84 <- sf::st_transform(hex, 4326)
buildings_wgs84 <- sf::st_transform(buildings_full, 4326)
hh_wgs84 <- sf::st_transform(hh, 4326)

marker_fill  <- c(primary = "#00E5FF", reserve = "#FFFFFF")
marker_color <- c(primary = "#0A3A46", reserve = "#111111")
marker_shape <- c(primary = 21, reserve = 24)

# ---- Map 2: full hexagon context, revised markers ----

bbox_hex <- sf::st_bbox(hex_wgs84)
pad_hex <- 0.01
bbox_hex <- bbox_hex + c(-pad_hex, -pad_hex, pad_hex, pad_hex)

map_extent_hex <- sf::st_as_sfc(bbox_hex, crs = 4326)

basemap_hex <- get_tiles_retry(map_extent_hex, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_non_idp2 <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_hex, maxcell = 2e6) +
  geom_sf(data = buildings_wgs84, fill = NA, color = "#FFD700", linewidth = 0.3, alpha = 0.85) +
  geom_sf(data = hex_wgs84, fill = NA, color = "#FF3B30", linewidth = 1.1) +
  geom_sf(data = hh_wgs84, aes(fill = status, color = status, shape = status), size = 3.3, stroke = 1, alpha = 0.8) +
  scale_fill_manual(values = marker_fill, name = "Household") +
  scale_color_manual(values = marker_color, name = "Household") +
  scale_shape_manual(values = marker_shape, name = "Household") +
  coord_sf(xlim = c(bbox_hex["xmin"], bbox_hex["xmax"]), ylim = c(bbox_hex["ymin"], bbox_hex["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Example Non-IDP cluster",
    subtitle = paste0(non_idp_example_id, " | ", nrow(buildings_full), " eligible buildings | red = hexagon boundary, yellow = building footprints"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom"
  )

ggsave("output/images/methodology_map_non_idp_v2.png", p_non_idp2, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved Non-IDP v2 map\n")

# ---- Map 3: close-up around the drawn households, buildings visible nearby ----

hh_proj <- sf::st_transform(hh, mycrs)
hh_bbox_proj <- sf::st_bbox(hh_proj)
pad_m <- 80

closeup_bbox_proj <- hh_bbox_proj + c(-pad_m, -pad_m, pad_m, pad_m)
closeup_extent_wgs84 <- sf::st_as_sfc(closeup_bbox_proj, crs = mycrs) %>% sf::st_transform(4326)
bbox_closeup_non_idp <- sf::st_bbox(closeup_extent_wgs84)

basemap_closeup_non_idp <- get_tiles_retry(closeup_extent_wgs84, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

p_non_idp_closeup <- ggplot() +
  tidyterra::geom_spatraster_rgb(data = basemap_closeup_non_idp, maxcell = 2e6) +
  geom_sf(data = buildings_wgs84, fill = NA, color = "#FFD700", linewidth = 0.45, alpha = 0.9) +
  geom_sf(data = hh_wgs84, aes(fill = status, color = status, shape = status), size = 4.5, stroke = 1.2, alpha = 0.8) +
  scale_fill_manual(values = marker_fill, name = "Household") +
  scale_color_manual(values = marker_color, name = "Household") +
  scale_shape_manual(values = marker_shape, name = "Household") +
  coord_sf(xlim = c(bbox_closeup_non_idp["xmin"], bbox_closeup_non_idp["xmax"]), ylim = c(bbox_closeup_non_idp["ymin"], bbox_closeup_non_idp["ymax"]), expand = FALSE, crs = 4326) +
  labs(
    title = "Close-up: selected households and nearby buildings",
    subtitle = paste0(non_idp_example_id, " | yellow = eligible building footprints"),
    caption = "Basemap: Esri World Imagery"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 8.5, color = "grey30", margin = margin(b = 8)),
    plot.caption = element_text(size = 7, color = "grey50"),
    legend.position = "bottom"
  )

ggsave("output/images/methodology_map_non_idp_closeup.png", p_non_idp_closeup, width = 7, height = 7, dpi = 130, bg = "white")
cat("Saved Non-IDP close-up map\n")

cat("ALL DONE\n")
