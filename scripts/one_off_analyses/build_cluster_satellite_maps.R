# ==============================================================================
# Per-cluster satellite maps - one real Esri World Imagery image per cluster,
# replacing the LGA-context PNG currently used in the cluster factsheets
# (build_cluster_factsheets.py). Per MSNA_Claude_Code_Implementation_Spec.md
# Section 8 / MSNA_Claude_Code_Batch_Generation_Prompt.md, and the user's
# 2026-08-07 request: this is an "exhaustive task" (each map needs a live
# tile fetch, ~15-20s), so this script is run first for a small EXAMPLES set
# for visual sign-off before any full-3,428-cluster batch commitment.
#
# Reuses the exact same basemap pipeline already proven in
# analysis_idp_tor_maps_part1.R/_part2.R and 08_render_methodology_maps.R
# (maptiles::get_tiles(provider="Esri.WorldImagery"), tidyterra for the
# raster layer, ggspatial for a real computed north arrow + scale bar) -
# not a second pipeline.
#
# Per-type visual language (spec Section 8, and the two approved reference
# maps methodology_map_non_idp_v2.png / methodology_map_idp_camp_v2.png):
#   - non_idp: hexagon boundary (navy) + single anchor point.
#   - idp / idps in camp: hexagon boundary (amber) + DTM point + Tier 2
#     backup point (if one exists for this cluster), both labelled.
#   - idp / idps in host: DTM point ONLY, no boundary of any kind (not even
#     the hexagon) - deliberate, matches the real field method (no GPS
#     radius or geometric bound behind host-community listing at all).
#   - all types: real north arrow + scale bar (ggspatial, not illustrative).
#   - wherever n_other_sites_in_hex > 0 (IDP only): grey marker(s) for the
#     other raw DTM site(s) in the same hexagon, re-derived directly from
#     iom_idp_df (deterministic spatial join, no RNG - safe to recompute
#     independently of the pipeline's own cached Stage 2 assignment).
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(maptiles)
  library(tidyterra)
  library(ggspatial)
})

mycrs <- 31028

output_dir <- here::here("output")
maps_out_dir <- here::here(output_dir, "maps", "cluster_satellite")
dir.create(maps_out_dir, recursive = TRUE, showWarnings = FALSE)

# plot.caption doesn't auto-wrap in base ggplot2 - a long caption silently
# overflows the left edge of a narrow (5.6in) canvas instead of wrapping,
# clipping its opening words. Wrap it manually at render time instead.
wrap_caption <- function(text, width = 88) {
  paste(strwrap(text, width = width), collapse = "\n")
}

get_tiles_retry <- function(..., max_attempts = 5, pause_s = 5) {
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(maptiles::get_tiles(...), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    message("get_tiles() attempt ", attempt, "/", max_attempts, " failed: ", conditionMessage(result))
    if (attempt < max_attempts) Sys.sleep(pause_s)
  }
  stop("get_tiles() failed after ", max_attempts, " attempts: ", conditionMessage(result))
}

# ---------------------------------------------------------------------------
# 1. Deterministic pipeline prefix (through hex_access, before any set.seed) -
#    same sourcing pattern as build_lga_summary_maps.R and
#    analysis_coverage_map2.R's 2026-08-06 fix. Gives us hex_access (for
#    canonical hex geometry) AND iom_idp_df (raw DTM site points, needed for
#    the "other site nearby" markers) in one pass, since iom_idp_df is built
#    earlier in the script (line ~410) than hex_access (line ~601).
# ---------------------------------------------------------------------------
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_satmaps.R")
source("temp_boundaries_satmaps.R")
file.remove("temp_boundaries_satmaps.R")

hex_polygons <- hex_access %>%
  st_make_valid() %>%
  st_transform(4326) %>%
  st_make_valid() %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

iom_idp_wgs84 <- st_transform(iom_idp_df, 4326)

# ---------------------------------------------------------------------------
# 2. Cluster attribute + hex-mapping sources (no pipeline re-run needed -
#    same merged archive / WORKING CSV every other partner-facing output
#    already reads from).
# ---------------------------------------------------------------------------
selected_clusters <- readRDS(here::here(
  "_archive", "2026-08-06_design_frame_post_nw_targeted_resample", "selected_clusters_final.rds"
))

stage2 <- read_csv(
  here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"),
  show_col_types = FALSE
)

backup_pts <- read_csv(
  here::here(output_dir, "data", "data_collection", "idp_camp_backup_points.csv"),
  show_col_types = FALSE
)

cluster_meta <- stage2 %>%
  filter(status == "primary") %>%
  group_by(cluster_id) %>%
  slice(1) %>%
  ungroup() %>%
  select(cluster_id, pop_type, idp_population_category, adm2_pcode, adm2_name,
         latitude, longitude, n_other_sites_in_hex, iom_site_id)

uuid_hex_lookup <- selected_clusters %>%
  st_drop_geometry() %>%
  distinct(cluster_id, uuid_hex)

# ---------------------------------------------------------------------------
# 3. Other-site-nearby helper - re-derives site_matches from
#    05_stage2_idp_site_assignment.R's own logic (st_within join of raw DTM
#    points to the selected hexagon), independently, since that script's
#    intermediate object isn't persisted anywhere. Deterministic, no RNG.
# ---------------------------------------------------------------------------
other_sites_in_hex <- function(hex_i, representative_site_id) {
  hex_proj <- st_transform(hex_i, mycrs)
  matches <- st_join(iom_idp_df, hex_proj, join = st_within, left = FALSE)
  matches <- matches %>% filter(as.character(site_id_ssid) != as.character(representative_site_id))
  if (nrow(matches) == 0) return(NULL)
  st_transform(matches, 4326) %>% select(site_id_ssid, site_name)
}

# ---------------------------------------------------------------------------
# 4. Per-cluster render
# ---------------------------------------------------------------------------
render_cluster_map <- function(cid) {
  meta <- cluster_meta %>% filter(cluster_id == cid)
  stopifnot(nrow(meta) == 1)

  uuid_hex_i <- uuid_hex_lookup %>% filter(cluster_id == cid) %>% pull(uuid_hex)
  stopifnot(length(uuid_hex_i) == 1)
  hex_i <- hex_polygons %>% filter(uuid_hex == uuid_hex_i)
  stopifnot(nrow(hex_i) == 1)

  pop_type <- meta$pop_type
  idp_cat <- meta$idp_population_category
  n_other <- suppressWarnings(as.integer(meta$n_other_sites_in_hex))
  n_other <- if (is.na(n_other)) 0L else n_other

  other_sites <- if (pop_type == "idp" && n_other > 0) other_sites_in_hex(hex_i, meta$iom_site_id) else NULL

  if (pop_type == "non_idp") {
    anchor_pt <- st_sf(geometry = st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326))

    bbox <- st_bbox(hex_i)
    pad <- 0.01
    bbox_p <- bbox + c(-pad, -pad, pad, pad)
    extent <- st_as_sfc(bbox_p, crs = 4326)

    basemap <- get_tiles_retry(extent, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

    p <- ggplot() +
      tidyterra::geom_spatraster_rgb(data = basemap, maxcell = 2e6) +
      geom_sf(data = hex_i, fill = NA, color = "#1F3864", linewidth = 1.2) +
      geom_sf(data = anchor_pt, shape = 21, size = 4.5, stroke = 1.3, color = "#1F3864", fill = "#00E5FF") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption("Basemap: Esri World Imagery. Blue outline = Stage 1 hexagon (PSU) boundary; blue point = cluster anchor (orientation only - use the KML points for exact navigation).")) +
      theme_void() +
      theme(plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4)), plot.margin = margin(3, 3, 3, 3))

  } else if (idp_cat == "idps in camp") {
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    backup_row <- backup_pts %>% filter(site_id == cid, !is.na(backup_gps_lat))
    has_backup <- nrow(backup_row) == 1

    point_labels <- c(dtm = "DTM point (Tier 1 listing)", backup = "Backup point (Tier 2 fallback only)")
    # Draw order = row order within a geom_sf layer, not factor level order.
    # The backup point is often only ~100-300m from the DTM point, so when
    # both fall in one layer, whichever is drawn last visually sits on top
    # and can nearly hide the other. DTM is the primary Tier 1 reference
    # point, so it goes LAST here (backup point first) to stay on top.
    if (has_backup) {
      backup_pt <- st_sfc(st_point(c(backup_row$backup_gps_lon, backup_row$backup_gps_lat)), crs = 4326)
      pts_sf <- st_sf(
        point_type = factor(c(point_labels[["backup"]], point_labels[["dtm"]]), levels = point_labels),
        geometry = c(backup_pt, dtm_pt)
      )
    } else {
      pts_sf <- st_sf(point_type = factor(point_labels[["dtm"]], levels = point_labels[["dtm"]]), geometry = dtm_pt)
    }
    marker_shape <- setNames(c(3, 17), point_labels)
    marker_color <- setNames(c("#FF3B30", "#FFA500"), point_labels)

    bbox_hex <- st_bbox(hex_i)
    bbox_pts <- st_bbox(pts_sf)
    bbox_all <- c(
      xmin = min(bbox_hex["xmin"], bbox_pts["xmin"]), ymin = min(bbox_hex["ymin"], bbox_pts["ymin"]),
      xmax = max(bbox_hex["xmax"], bbox_pts["xmax"]), ymax = max(bbox_hex["ymax"], bbox_pts["ymax"])
    )
    pad <- 0.006
    bbox_p <- bbox_all + c(-pad, -pad, pad, pad)
    extent <- st_as_sfc(st_bbox(bbox_p, crs = 4326))

    basemap <- get_tiles_retry(extent, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

    p <- ggplot() +
      tidyterra::geom_spatraster_rgb(data = basemap, maxcell = 2e6) +
      geom_sf(data = hex_i, fill = NA, color = "#B45309", linewidth = 1.2)

    if (!is.null(other_sites)) {
      p <- p + geom_sf(data = other_sites, shape = 4, size = 3.2, stroke = 1.3, color = "#555555")
    }

    marker_size <- setNames(c(4.5, 5.4), point_labels)  # dtm drawn slightly larger, matches reference map's convention

    p <- p +
      geom_sf(data = pts_sf, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6) +
      scale_shape_manual(values = marker_shape, name = NULL) +
      scale_color_manual(values = marker_color, name = NULL) +
      scale_size_manual(values = marker_size, name = NULL, guide = "none") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        "Basemap: Esri World Imagery. Amber outline = Stage 1 hexagon boundary.",
        if (!is.null(other_sites)) " Grey X = other IDP site(s) in this hex, not part of your sample." else ""
      ))) +
      theme_void() +
      theme(
        legend.position = "bottom", legend.text = element_text(size = 7),
        plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4)),
        plot.margin = margin(3, 3, 3, 3)
      )

  } else {
    # idps in host - DTM point ONLY, no boundary at all (intentional).
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    dtm_pt_sf <- st_sf(geometry = dtm_pt)
    dtm_proj <- st_transform(dtm_pt, mycrs)
    pad_m <- 220
    bbox_proj <- st_bbox(dtm_proj) + c(-pad_m, -pad_m, pad_m, pad_m)
    if (!is.null(other_sites)) {
      # Widen the tight default extent so a flagged other-site actually falls
      # within frame - a caption saying "grey X = other site nearby" with no
      # visible X anywhere on the map (as happened in testing, when the
      # other site sat just outside the fixed 220m box) is worse than no
      # caption at all.
      other_sites_proj <- st_transform(other_sites, mycrs)
      bbox_other_proj <- st_bbox(other_sites_proj) + c(-pad_m, -pad_m, pad_m, pad_m)
      bbox_proj <- c(
        xmin = min(bbox_proj["xmin"], bbox_other_proj["xmin"]), ymin = min(bbox_proj["ymin"], bbox_other_proj["ymin"]),
        xmax = max(bbox_proj["xmax"], bbox_other_proj["xmax"]), ymax = max(bbox_proj["ymax"], bbox_other_proj["ymax"])
      )
    }
    extent <- st_as_sfc(st_bbox(bbox_proj, crs = mycrs)) %>% st_transform(4326)
    bbox_p <- st_bbox(extent)

    basemap <- get_tiles_retry(extent, provider = "Esri.WorldImagery", zoom = 17, crop = TRUE)

    p <- ggplot() +
      tidyterra::geom_spatraster_rgb(data = basemap, maxcell = 2e6)

    if (!is.null(other_sites)) {
      p <- p + geom_sf(data = other_sites, shape = 4, size = 3.2, stroke = 1.3, color = "#555555")
    }

    p <- p +
      geom_sf(data = dtm_pt_sf, shape = 21, size = 5, stroke = 1.4, color = "#6A3D9A", fill = "#D9A9FF") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        "Basemap: Esri World Imagery. Purple point = DTM start point (no boundary shown - host-community listing is bounded by local social knowledge, not geography).",
        if (!is.null(other_sites)) " Grey X = other IDP site(s) nearby, not part of your sample." else ""
      ))) +
      theme_void() +
      theme(plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4)), plot.margin = margin(3, 3, 3, 3))
  }

  fname <- paste0(cid, ".png")
  ggsave(file.path(maps_out_dir, fname), p, width = 5.6, height = 5.1, dpi = 140, bg = "white")
  message("  Saved ", fname)
  invisible(fname)
}

# ---------------------------------------------------------------------------
# 5. EXAMPLES ONLY - 5 clusters spanning all 3 types + edge cases, for visual
#    sign-off before any full-batch commitment (per user request 2026-08-07).
# ---------------------------------------------------------------------------
example_ids <- c(
  "non_idp_NG022015_11",  # non-IDP, standard 6/6 - JS reference example
  "idp_NG002002_1",       # IDP in-camp, 5-draw combined, has backup point - JS reference example
  "idp_NG002001_5",       # IDP in-host, n_other_sites_in_hex=1 - JS reference example + other-site test
  "idp_NG008013_17",      # IDP in-camp, irregular admin2-clipped hex - approved ToR reference site
  "non_idp_NG008014_8"    # non-IDP, below-target (2 eligible buildings) - tiny-cluster edge case
)

cat("\nRendering", length(example_ids), "example satellite maps...\n")
t_start <- Sys.time()
for (cid in example_ids) {
  cat(cid, "... ")
  render_cluster_map(cid)
}
cat("\nDONE in", round(as.numeric(Sys.time() - t_start, units = "mins"), 1), "minutes.\n")
cat("Output:", maps_out_dir, "\n")
