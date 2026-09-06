# ==============================================================================
# LGA-level summary maps - zoomed-in versions of coverage_map2_alt2_popgroup_
# all_hexes.png (the main ToR assessment-design map), one per covered LGA,
# for inclusion in partner data-collection packages (2026-08-07).
#
# Same hex-level population-group colouring as the national map (Non-IDP
# only / IDP only / Both), same source data (selected_clusters_final.rds +
# hex_access), just cropped and re-rendered per LGA instead of nationally.
# Deliberately vector-only (no satellite basemap) to keep 176 renders fast
# and visually consistent with the main map partners have already seen -
# this is an orientation/overview map, not a navigation tool (Maps.me/
# Google Maps with the KML points already covers navigation).
#
# Output: output/maps/lga_summary/<adm2_pcode>_<LGA_name>.png - one file per
# covered LGA. build_partner_dc_packages.py places each LGA's map into every
# partner folder that covers it, same distribution pattern as the KML files.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(ggrepel)
})

output_dir <- here::here("output")
maps_out_dir <- here::here(output_dir, "maps", "lga_summary")
dir.create(maps_out_dir, recursive = TRUE, showWarnings = FALSE)

mycrs <- 31028

# ---------------------------------------------------------------------------
# 1. Deterministic boundary prefix (same as analysis_coverage_map2.R's fix -
#    stop before any set.seed/randomness; hex_access is the last thing we
#    need from the pipeline script itself).
# ---------------------------------------------------------------------------
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_lgamaps.R")
source("temp_boundaries_lgamaps.R")
file.remove("temp_boundaries_lgamaps.R")

admin2_all <- NGA_shapes_all_cleaned$nga_admin2

nga_wards <- sf::st_read(
  here::here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
) %>% st_transform(mycrs) %>% st_make_valid()

# ---------------------------------------------------------------------------
# 2. Hex geometry (canonical, from hex_access - same 2026-08-06 fix as
#    analysis_coverage_map2.R, not from selected_clusters_final's own mixed
#    point/polygon geometry column) + population-group classification.
# ---------------------------------------------------------------------------
# 2026-09-01 fix: same staleness issue as analysis_coverage_map2.R - see
# that script's own note near its selected_clusters assignment. This run
# was first done against the stale archive before the fix existed -
# rerun after this edit to pick up this week's new clusters' shading.
selected_clusters <- readRDS(here::here("output", "gis", "selected_clusters_v5_current.rds"))

hex_polygons <- hex_access %>%
  st_make_valid() %>%
  st_transform(4326) %>%
  st_make_valid() %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

full_strata <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_strata_level_sampling_frame_v5_FULL.csv"), show_col_types = FALSE)
working_pairs <- full_strata %>%
  filter(coverage_status == "covered", exclusion_reason == "none") %>%
  distinct(adm2_pcode, pop_type)

hex_popgroup_base <- selected_clusters %>%
  st_drop_geometry() %>%
  select(cluster_id, uuid_hex, uuid_hex_pop, adm2_pcode, pop_type) %>%
  inner_join(working_pairs, by = c("adm2_pcode", "pop_type"))

hex_popgroup <- hex_popgroup_base %>%
  distinct(uuid_hex, adm2_pcode, pop_type) %>%
  group_by(uuid_hex, adm2_pcode) %>%
  summarise(has_non_idp = any(pop_type == "non_idp"), has_idp = any(pop_type == "idp"), .groups = "drop") %>%
  mutate(popgroup_class = case_when(
    has_non_idp & has_idp ~ "Both Non-IDP and IDP",
    has_non_idp ~ "Non-IDP only",
    TRUE ~ "IDP only"
  ))

popgroup_levels <- c("Non-IDP only", "IDP only", "Both Non-IDP and IDP")
hex_popgroup <- hex_popgroup %>% mutate(popgroup_class = factor(popgroup_class, levels = popgroup_levels))
popgroup_colors <- setNames(c("#1B6FA8", "#E08214", "#6A3D9A"), popgroup_levels)

hexes_popgroup_sf <- hex_polygons %>%
  inner_join(hex_popgroup, by = "uuid_hex") %>%
  st_make_valid()

cat("Total selected hexes with popgroup classification:", nrow(hexes_popgroup_sf), "\n")

# ---------------------------------------------------------------------------
# 3. Render one map per covered LGA
# ---------------------------------------------------------------------------
covered_lgas <- working_pairs %>%
  distinct(adm2_pcode) %>%
  left_join(st_drop_geometry(admin2_all) %>% select(adm2_pcode, adm2_name, adm1_name), by = "adm2_pcode")

cat("Covered LGAs to map:", nrow(covered_lgas), "\n")

safe_name <- function(s) gsub("[^A-Za-z0-9]+", "_", s)

nga_wards_4326 <- nga_wards %>% st_transform(4326) %>% st_make_valid()
nga_wards_4326 <- nga_wards_4326[!st_is_empty(nga_wards_4326), ]

n_ok <- 0
n_skipped <- 0
failed_lgas <- character(0)

for (i in seq_len(nrow(covered_lgas))) {
  pcode <- covered_lgas$adm2_pcode[i]
  lga_name <- covered_lgas$adm2_name[i]
  state_name <- covered_lgas$adm1_name[i]

  result <- tryCatch({
    lga_boundary <- admin2_all %>% filter(adm2_pcode == pcode) %>% st_transform(4326) %>% st_make_valid()
    if (nrow(lga_boundary) == 0) stop("no boundary match")

    lga_hexes <- hexes_popgroup_sf %>% filter(adm2_pcode == pcode)

    bbox <- st_bbox(lga_boundary)
    margin_x <- unname((bbox["xmax"] - bbox["xmin"]) * 0.08 + 0.01)
    margin_y <- unname((bbox["ymax"] - bbox["ymin"]) * 0.08 + 0.01)
    # unname() is load-bearing here, not cosmetic: bbox["xmin"] keeps the
    # name "xmin" attached, and c(xmin = bbox["xmin"] - margin_x, ...) below
    # would otherwise double the name to "xmin.xmin" - st_bbox() then fails
    # to recognise it, silently returns an all-NA bbox, and st_as_sfc() on
    # that dies with the cryptic "!anyNA(x) is not TRUE" (found by isolating
    # this exact line after every LGA failed with the same error).
    xlim <- c(unname(bbox["xmin"]) - margin_x, unname(bbox["xmax"]) + margin_x)
    ylim <- c(unname(bbox["ymin"]) - margin_y, unname(bbox["ymax"]) + margin_y)

    # Bounding-box pre-filter (not st_crop, which chokes on some invalid
    # ward geometries) - geom_sf + coord_sf's own xlim/ylim clips the
    # display regardless, this just avoids handing ggplot thousands of
    # irrelevant national ward polygons per LGA.
    ward_bbox <- st_bbox(c(xmin = xlim[1], ymin = ylim[1], xmax = xlim[2], ymax = ylim[2]), crs = 4326) %>% st_as_sfc()
    ward_nearby <- nga_wards_4326[st_intersects(nga_wards_4326, ward_bbox, sparse = FALSE)[, 1], ]

    # Fix (2026-08-07): scale_fill_manual(drop = FALSE) keeps every legend
    # LABEL even when a category has zero rows in this LGA (as intended -
    # legend should read identically across all 176 maps), but geom_sf's
    # legend key glyph renders BLANK for a level with no underlying data at
    # all, regardless of drop=FALSE or guide_legend(override.aes=...) -
    # confirmed by isolating this exact case (a factor level present only in
    # the levels attribute, absent from every row, reproducibly blanks its
    # key). Fix: add one real, off-canvas dummy row per missing level so its
    # key glyph has actual data to derive its colour from - placed miles
    # outside every possible LGA's xlim/ylim (all of Nigeria sits within
    # roughly 2-15 lon / 4-14 lat) so it never appears on the rendered map.
    present_levels <- unique(as.character(lga_hexes$popgroup_class))
    missing_levels <- setdiff(popgroup_levels, present_levels)
    if (length(missing_levels) > 0) {
      dummy_legend_rows <- st_sf(
        popgroup_class = factor(missing_levels, levels = popgroup_levels),
        geometry = st_sfc(lapply(missing_levels, function(x) st_point(c(-999, -999))), crs = 4326)
      )
    } else {
      dummy_legend_rows <- NULL
    }

    p <- ggplot() +
      geom_sf(data = ward_nearby, fill = "grey97", color = "grey75", linewidth = 0.15) +
      geom_sf(data = lga_hexes, aes(fill = popgroup_class), color = "grey20", linewidth = 0.15, alpha = 0.9) +
      # shape = 22 (filled square) is load-bearing: geom_sf's default point
      # shape (19, solid circle) is drawn via the `colour` aesthetic, not
      # `fill` - so a plain point dummy shows as a black dot regardless of
      # the fill scale, matching neither the real hexes' style nor the
      # correct legend colour. Shape 22 uses both colour (outline) and fill
      # (interior), same as the polygons it's standing in for.
      {if (!is.null(dummy_legend_rows)) geom_sf(data = dummy_legend_rows, aes(fill = popgroup_class), shape = 22, size = 4, color = "grey20", linewidth = 0.15, alpha = 0.9)} +
      geom_sf(data = lga_boundary, fill = NA, color = "#1B2A4A", linewidth = 1.1) +
      scale_fill_manual(values = popgroup_colors, name = "Population group\ntargeted", drop = FALSE, na.translate = FALSE) +
      coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
      labs(title = paste0(lga_name, ", ", state_name), subtitle = paste0(nrow(lga_hexes), " selected hexagon(s) - see accompanying KML files for exact GPS points")) +
      theme_void(base_size = 12) +
      theme(
        plot.title = element_text(face = "bold", size = 15, hjust = 0.5, margin = margin(t = 6, b = 2)),
        plot.subtitle = element_text(size = 9.5, hjust = 0.5, color = "grey40", margin = margin(b = 8)),
        legend.position = "right",
        legend.title = element_text(face = "bold", size = 10),
        legend.text = element_text(size = 9),
        plot.background = element_rect(fill = "white", color = NA)
      )

    fname <- paste0(pcode, "_", safe_name(lga_name), ".png")
    ggsave(file.path(maps_out_dir, fname), p, width = 7.5, height = 6.5, dpi = 130, bg = "white")
    TRUE
  }, error = function(e) {
    message("  FAILED ", lga_name, " (", pcode, "): ", conditionMessage(e))
    FALSE
  })

  if (isTRUE(result)) {
    n_ok <- n_ok + 1
    if (n_ok %% 20 == 0) cat("  ...", n_ok, "maps rendered\n")
  } else {
    n_skipped <- n_skipped + 1
    failed_lgas <- c(failed_lgas, paste0(lga_name, " (", pcode, ")"))
  }
}

cat("\nDONE. Rendered:", n_ok, " Skipped/failed:", n_skipped, "\n")
if (length(failed_lgas) > 0) cat("Failed LGAs:", paste(failed_lgas, collapse = "; "), "\n")
cat("Output:", maps_out_dir, "\n")
