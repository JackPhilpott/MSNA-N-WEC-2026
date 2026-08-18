# ==============================================================================
# Per-cluster schematic maps - vector-only variant of
# build_cluster_satellite_maps.R (satellite version paused 2026-08-07: full
# batch would have needed ~20-24hrs for 3,428 clusters at ~15-20s/tile-fetch
# each). This version has no basemap tile fetch at all, so it's the
# dominant cost removed - a 5-example timing test measured 0.33s/cluster
# mean render time, ~19 minutes projected for the full batch, confirmed
# below. Same hexagon/point geometry, conditional logic (Non-IDP hexagon +
# anchor; IDP-camp hexagon + DTM + backup point; IDP-host DTM point only,
# no boundary), and other-site markers as the satellite version - just a
# plain light-grey background instead of Esri World Imagery.
#
# Output: output/maps/cluster_vector/{cluster_id}.png - one per cluster,
# referenced by build_cluster_factsheets.py's map_block().
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(ggspatial)
})

mycrs <- 31028

output_dir <- here::here("output")
maps_out_dir <- here::here(output_dir, "maps", "cluster_vector")
dir.create(maps_out_dir, recursive = TRUE, showWarnings = FALSE)

wrap_caption <- function(text, width = 88) {
  paste(strwrap(text, width = width), collapse = "\n")
}

# ---------------------------------------------------------------------------
# 1. Deterministic pipeline prefix (through hex_access) - same as the
#    satellite-map script and build_lga_summary_maps.R.
# ---------------------------------------------------------------------------
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_vecmaps.R")
source("temp_boundaries_vecmaps.R")
file.remove("temp_boundaries_vecmaps.R")

hex_polygons <- hex_access %>%
  st_make_valid() %>%
  st_transform(4326) %>%
  st_make_valid() %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

iom_idp_wgs84 <- st_transform(iom_idp_df, 4326)

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

uuid_hex_lookup <- selected_clusters %>% st_drop_geometry() %>% distinct(cluster_id, uuid_hex)

other_sites_in_hex <- function(hex_i, representative_site_id) {
  hex_proj <- st_transform(hex_i, mycrs)
  matches <- st_join(iom_idp_df, hex_proj, join = st_within, left = FALSE)
  matches <- matches %>% filter(as.character(site_id_ssid) != as.character(representative_site_id))
  if (nrow(matches) == 0) return(NULL)
  st_transform(matches, 4326) %>% select(site_id_ssid, site_name)
}

# ---------------------------------------------------------------------------
# Per-cluster render - NO basemap tile fetch, plain background instead.
# ---------------------------------------------------------------------------
render_cluster_map_vector <- function(cid) {
  meta <- cluster_meta %>% filter(cluster_id == cid)
  stopifnot(nrow(meta) == 1)
  uuid_hex_i <- uuid_hex_lookup %>% filter(cluster_id == cid) %>% pull(uuid_hex)
  hex_i <- hex_polygons %>% filter(uuid_hex == uuid_hex_i)
  # Graceful degrade, not a hard stop: for the 24 NW LGAs from the
  # 2026-08-06 targeted border-buffer resample, some hex_ids exist only in
  # that isolated run's own hex-grid construction, not in "hex_access" as
  # freshly sourced here (built with today's national buffer logic, not the
  # isolated resample's own 5km-uniform version for just those 24 LGAs) -
  # so the lookup can return 0 rows, or (rarer) 1 row whose geometry
  # collapsed to empty under st_make_valid(). Either way the cluster's own
  # anchor/DTM point (from the WORKING CSV, unaffected by this) is still
  # correct - draw point-only rather than fail the whole cluster.
  has_hex <- nrow(hex_i) == 1 && !any(st_is_empty(hex_i))

  pop_type <- meta$pop_type
  idp_cat <- meta$idp_population_category
  n_other <- suppressWarnings(as.integer(meta$n_other_sites_in_hex))
  n_other <- if (is.na(n_other)) 0L else n_other
  other_sites <- if (pop_type == "idp" && n_other > 0 && has_hex) other_sites_in_hex(hex_i, meta$iom_site_id) else NULL

  bg_theme <- theme_void() +
    theme(
      panel.background = element_rect(fill = "grey96", color = NA),
      plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4)),
      plot.margin = margin(3, 3, 3, 3)
    )

  if (pop_type == "non_idp") {
    anchor_pt <- st_sf(geometry = st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326))
    if (has_hex) {
      bbox <- st_bbox(hex_i)
      pad <- 0.01
      bbox_p <- bbox + c(-pad, -pad, pad, pad)
    } else {
      anchor_proj <- st_transform(anchor_pt, mycrs)
      pad_m <- 550
      bbox_p <- st_bbox(st_as_sfc(st_bbox(anchor_proj) + c(-pad_m, -pad_m, pad_m, pad_m), crs = mycrs) %>% st_transform(4326))
    }
    p <- ggplot()
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#1F386415", color = "#1F3864", linewidth = 1.2)
    p <- p +
      geom_sf(data = anchor_pt, shape = 21, size = 4.5, stroke = 1.3, color = "#1F3864", fill = "#00E5FF") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(if (has_hex)
        "No satellite imagery - vector-only. Blue outline = Stage 1 hexagon (PSU) boundary; blue point = cluster anchor (orientation only - use the KML points for exact navigation)."
        else
        "No satellite imagery - vector-only. Hexagon boundary unavailable for this cluster; blue point = cluster anchor (orientation only - use the KML points for exact navigation).")) +
      bg_theme

  } else if (idp_cat == "idps in camp") {
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    backup_row <- backup_pts %>% filter(site_id == cid, !is.na(backup_gps_lat))
    has_backup <- nrow(backup_row) == 1
    point_labels <- c(dtm = "DTM point (Tier 1 listing)", backup = "Backup point (Tier 2 fallback only)")
    if (has_backup) {
      backup_pt <- st_sfc(st_point(c(backup_row$backup_gps_lon, backup_row$backup_gps_lat)), crs = 4326)
      pts_sf <- st_sf(point_type = factor(c(point_labels[["backup"]], point_labels[["dtm"]]), levels = point_labels), geometry = c(backup_pt, dtm_pt))
    } else {
      pts_sf <- st_sf(point_type = factor(point_labels[["dtm"]], levels = point_labels[["dtm"]]), geometry = dtm_pt)
    }
    marker_shape <- setNames(c(3, 17), point_labels)
    marker_color <- setNames(c("#FF3B30", "#FFA500"), point_labels)
    marker_size <- setNames(c(4.5, 5.4), point_labels)

    bbox_pts <- st_bbox(pts_sf)
    if (has_hex) {
      bbox_hex <- st_bbox(hex_i)
      bbox_all <- c(
        xmin = min(bbox_hex["xmin"], bbox_pts["xmin"]), ymin = min(bbox_hex["ymin"], bbox_pts["ymin"]),
        xmax = max(bbox_hex["xmax"], bbox_pts["xmax"]), ymax = max(bbox_hex["ymax"], bbox_pts["ymax"])
      )
    } else {
      bbox_all <- bbox_pts
    }
    pad <- 0.006
    bbox_p <- bbox_all + c(-pad, -pad, pad, pad)

    p <- ggplot()
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#B4530915", color = "#B45309", linewidth = 1.2)
    if (!is.null(other_sites)) p <- p + geom_sf(data = other_sites, shape = 4, size = 3.2, stroke = 1.3, color = "#555555")
    p <- p +
      geom_sf(data = pts_sf, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6) +
      scale_shape_manual(values = marker_shape, name = NULL) +
      scale_color_manual(values = marker_color, name = NULL) +
      scale_size_manual(values = marker_size, name = NULL, guide = "none") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        "No satellite imagery - vector-only.",
        if (has_hex) " Amber outline = Stage 1 hexagon boundary." else " Hexagon boundary unavailable for this cluster.",
        if (!is.null(other_sites)) " Grey X = other IDP site(s) in this hex, not part of your sample." else ""
      ))) +
      bg_theme + theme(legend.position = "bottom", legend.text = element_text(size = 7))

  } else {
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    dtm_pt_sf <- st_sf(geometry = dtm_pt)
    dtm_proj <- st_transform(dtm_pt, mycrs)
    pad_m <- 220
    bbox_proj <- st_bbox(dtm_proj) + c(-pad_m, -pad_m, pad_m, pad_m)
    if (!is.null(other_sites)) {
      other_sites_proj <- st_transform(other_sites, mycrs)
      bbox_other_proj <- st_bbox(other_sites_proj) + c(-pad_m, -pad_m, pad_m, pad_m)
      bbox_proj <- c(
        xmin = min(bbox_proj["xmin"], bbox_other_proj["xmin"]), ymin = min(bbox_proj["ymin"], bbox_other_proj["ymin"]),
        xmax = max(bbox_proj["xmax"], bbox_other_proj["xmax"]), ymax = max(bbox_proj["ymax"], bbox_other_proj["ymax"])
      )
    }
    extent_wgs84 <- st_as_sfc(st_bbox(bbox_proj, crs = mycrs)) %>% st_transform(4326)
    bbox_p <- st_bbox(extent_wgs84)

    p <- ggplot()
    if (!is.null(other_sites)) p <- p + geom_sf(data = other_sites, shape = 4, size = 3.2, stroke = 1.3, color = "#555555")
    p <- p +
      geom_sf(data = dtm_pt_sf, shape = 21, size = 5, stroke = 1.4, color = "#6A3D9A", fill = "#D9A9FF") +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE, crs = 4326) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        "No satellite imagery - vector-only. Purple point = DTM start point (no boundary shown - host-community listing is bounded by local social knowledge, not geography).",
        if (!is.null(other_sites)) " Grey X = other IDP site(s) nearby, not part of your sample." else ""
      ))) +
      bg_theme
  }

  fname <- paste0(cid, ".png")
  ggsave(file.path(maps_out_dir, fname), p, width = 5.6, height = 5.1, dpi = 140, bg = "white")
  invisible(fname)
}

# ---------------------------------------------------------------------------
# Full batch - every distinct cluster_id in the WORKING frame.
# ---------------------------------------------------------------------------
all_cluster_ids <- cluster_meta$cluster_id
cat("\nRendering", length(all_cluster_ids), "vector-only cluster maps...\n")
t_start <- Sys.time()
n_ok <- 0
failed_clusters <- character(0)
for (i in seq_along(all_cluster_ids)) {
  cid <- all_cluster_ids[i]
  result <- tryCatch({ render_cluster_map_vector(cid); TRUE }, error = function(e) {
    message("  FAILED ", cid, ": ", conditionMessage(e))
    FALSE
  })
  if (isTRUE(result)) {
    n_ok <- n_ok + 1
  } else {
    failed_clusters <- c(failed_clusters, cid)
  }
  if (i %% 200 == 0) cat("  ...", i, "/", length(all_cluster_ids), "processed\n")
}
cat(sprintf("\nDONE. Rendered: %d  Failed: %d  in %.1f minutes\n",
            n_ok, length(failed_clusters), as.numeric(Sys.time() - t_start, units = "mins")))
if (length(failed_clusters) > 0) cat("Failed clusters:", paste(failed_clusters, collapse = ", "), "\n")
cat("Output:", maps_out_dir, "\n")
