# ==============================================================================
# LGA-level zoom inset for coverage_map2_alt2_popgroup_all_hexes.png -
# requested 2026-08-17 for a presentation: a small side panel zoomed into
# one compact LGA where all three "population group targeted" hex colours
# (Non-IDP only / IDP only / Both) are visible together, so a viewer can
# actually see what an individual hexagon looks like at this map's zoom
# level - the national map is far too dense to make that legible.
#
# Reuses the exact same data-prep logic as analysis_coverage_map2.R (same
# hex_popgroup classification, same colours, same hex_access/hex_polygons
# source) rather than sourcing that script wholesale, since this only needs
# a small subset of its objects and none of its national-map legend/context
# machinery. Colours are copy-identical to the main map so the two read as
# one system when placed side by side.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(ggrepel)
})

output_dir   <- here::here("output")
analysis_dir <- here::here(output_dir, "maps")

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_map2zoom.R")
source("temp_boundaries_map2zoom.R")
file.remove("temp_boundaries_map2zoom.R")

# 2026-09-01 fix: same staleness issue as analysis_coverage_map2.R - see
# that script's own note near its selected_clusters assignment.
selected_clusters <- readRDS(here::here("output", "gis", "selected_clusters_v6_current.rds"))

hex_polygons <- hex_access %>%
  st_make_valid() %>% st_transform(4326) %>% st_make_valid() %>%
  distinct(uuid_hex, .keep_all = TRUE) %>% select(uuid_hex)

coverage_summary <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_coverage_summary_v2.csv"), show_col_types = FALSE)
full_strata <- read_csv(here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_strata_level_sampling_frame_v7_FULL.csv"), show_col_types = FALSE)

working_pairs <- full_strata %>%
  filter(coverage_status == "covered", exclusion_reason == "none") %>%
  distinct(adm2_pcode, pop_type)

# Same population-group classification as analysis_coverage_map2.R's alt1/alt2.
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

popgroup_levels <- c("Non-IDP only", "IDP only", "Both Non-IDP and IDP")
hex_popgroup <- hex_popgroup %>% mutate(popgroup_class = factor(popgroup_class, levels = popgroup_levels))
popgroup_colors <- setNames(c("#1B6FA8", "#E08214", "#6A3D9A"), popgroup_levels)

hexes_popgroup_sf <- hex_polygons %>%
  inner_join(hex_popgroup, by = "uuid_hex") %>%
  st_transform(4326) %>%
  mutate(fill_hex = unname(popgroup_colors[as.character(popgroup_class)]))

# adm2_pcode per hex, for LGA-level candidate search (a hex's own adm2_pcode
# isn't on hex_popgroup - recover it via the same uuid_hex -> cluster join).
hex_adm2 <- hex_popgroup_base %>% distinct(uuid_hex, adm2_pcode)
hexes_popgroup_sf <- hexes_popgroup_sf %>% left_join(hex_adm2, by = "uuid_hex")

admin2_all <- NGA_shapes_all_cleaned$nga_admin2

# ---------------------------------------------------------------------------
# Candidate search: LGAs with all 3 popgroup classes present among their
# selected hexes, ranked by total selected-hex count (smaller = tighter,
# more legible zoom) - "small LGA" per the user's explicit request.
# ---------------------------------------------------------------------------
candidates <- hexes_popgroup_sf %>%
  st_drop_geometry() %>%
  group_by(adm2_pcode) %>%
  summarise(
    n_hex = n(),
    n_classes = n_distinct(popgroup_class),
    n_non_idp = sum(popgroup_class == "Non-IDP only"),
    n_idp = sum(popgroup_class == "IDP only"),
    n_both = sum(popgroup_class == "Both Non-IDP and IDP"),
    .groups = "drop"
  ) %>%
  filter(n_classes == 3) %>%
  left_join(admin2_all %>% st_drop_geometry() %>% select(adm2_pcode, adm2_name, adm1_name), by = "adm2_pcode") %>%
  arrange(n_hex)

cat("LGAs with all 3 population-group hex classes present, smallest first:\n")
print(candidates, n = 15)

# Pick the smallest qualifying LGA - tightest, most legible zoom, per the
# user's "small LGA level" request.
pick <- candidates[1, ]
cat(sprintf("\nSelected: %s, %s (%s) - %d hexes total (%d Non-IDP, %d IDP, %d Both)\n",
            pick$adm2_name, pick$adm1_name, pick$adm2_pcode, pick$n_hex, pick$n_non_idp, pick$n_idp, pick$n_both))

lga_boundary <- admin2_all %>% filter(adm2_pcode == pick$adm2_pcode) %>% st_transform(4326) %>% st_make_valid()
stopifnot(nrow(lga_boundary) == 1)

hex_all_lga <- hex_access %>%
  filter(adm2_pcode == pick$adm2_pcode) %>%
  st_transform(4326) %>%
  select(uuid_hex)

hexes_lga <- hexes_popgroup_sf %>% filter(adm2_pcode == pick$adm2_pcode)

bbox <- st_bbox(lga_boundary)
pad_x <- unname((bbox["xmax"] - bbox["xmin"]) * 0.08 + 0.004)
pad_y <- unname((bbox["ymax"] - bbox["ymin"]) * 0.08 + 0.004)
bbox_p <- c(
  xmin = unname(bbox["xmin"]) - pad_x, ymin = unname(bbox["ymin"]) - pad_y,
  xmax = unname(bbox["xmax"]) + pad_x, ymax = unname(bbox["ymax"]) + pad_y
)

p <- ggplot() +
  geom_sf(data = hex_all_lga, fill = "white", color = "grey70", linewidth = 0.35) +
  geom_sf(data = hexes_lga, aes(fill = fill_hex), color = "grey20", linewidth = 0.35) +
  geom_sf(data = lga_boundary, fill = NA, color = "#0A0A0A", linewidth = 1.1) +
  scale_fill_identity(
    name = "Population group targeted",
    breaks = unname(popgroup_colors[popgroup_levels]),
    labels = popgroup_levels,
    guide = guide_legend(override.aes = list(color = "grey20", linewidth = 0.35))
  ) +
  coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE) +
  labs(
    title = paste0(pick$adm2_name, " LGA, ", pick$adm1_name),
    subtitle = "Close-up of an individual hexagon (Stage 1 PSU) - not selected (white) vs. selected, by population group targeted"
  ) +
  theme_void(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", color = "#1A1A1A", hjust = 0.5, margin = margin(b = 2)),
    plot.subtitle = element_text(color = "grey35", hjust = 0.5, size = 10, margin = margin(b = 8)),
    legend.position = "bottom",
    legend.title = element_text(face = "bold", size = 11),
    legend.text = element_text(size = 10),
    plot.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(10, 10, 10, 10)
  )

out_file <- here::here(analysis_dir, paste0("coverage_map2_zoom_inset_", pick$adm2_name |> gsub("[^A-Za-z0-9]+", "_", x = _), ".png"))
ggsave(out_file, p, width = 7, height = 7.2, dpi = 200, bg = "white")
cat("\nSaved:", out_file, "\n")
