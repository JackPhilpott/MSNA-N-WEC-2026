# ==============================================================================
# PRODUCTION cluster-level + LGA-context map batch - all WORKING-frame
# clusters, 2 maps each. Design finalized and approved via
# build_cluster_map_examples.R's iteration (2026-08-10 through 2026-08-13,
# 6 examples incl. POI numbered-marker system + GPS-offset polish round) -
# this script is that same rendering logic, generalized from the 6
# example_ids to every cluster, with a resumable progress log since the
# full batch takes several hours: reruns skip any cluster whose PNG pairs
# already exist, so an interrupted run just picks up where it left off
# rather than re-rendering from scratch. Writes into the SAME output
# folders the example script used (cluster_map_examples_v3/,
# cluster_lga_context_v1/) - the 6 already-approved example renders are
# left untouched (skipped, not overwritten) by the resume check below.
#
# Synced 2026-08-13 against build_cluster_map_examples.R's final state -
# ports the POI numbered-marker system (map markers + companion
# _poi_legend.csv per folder), the wrap_caption chars_per_inch retune
# (15 -> 19.5), and picks up every intervening fix already present in this
# script from the prior sync (ward-label/marker collision nudge, panel-
# aspect device sizing, missing-hex graceful degradation for resample edge
# cases - the example script's stopifnot(has_hex) is intentionally NOT
# ported here, since the full batch hits real resample-edge clusters the
# curated 6 examples don't).
#
# Progress log: output/maps/_production_build_log.csv, one row appended per
# cluster (both maps) as it completes - status ok/error, elapsed seconds,
# timestamp. Check this file to see exactly how far a run got if it stops.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
  library(ggplot2)
  library(ggspatial)
  library(ggrepel)
})

mycrs <- 31028

output_dir <- here::here("output")
maps_out_dir <- here::here(output_dir, "maps", "cluster_map_examples_v3")
dir.create(maps_out_dir, recursive = TRUE, showWarnings = FALSE)

ROADS_GPKG <- here::here("input_data", "boundaries", "nga_roads_hotosm", "roads_assessment_states.gpkg")
building_data_dir <- file.path("C:/Users/JackPHILPOTT/Personal - Documents/GIS", "Google_Open_Buildings")

# Roads: blue read as rivers (2026-08-10 feedback #2) - moved to a
# standard road red-orange instead. Picked to stay distinguishable from
# BOTH the amber camp-hexagon outline (#B45309, a darker/more muted
# brown-orange) and the bright red DTM cross marker (#FF3B30, more
# magenta-leaning) - this sits between them in hue/lightness.
ROAD_COLOR <- "#E8622C"
WARD_BORDER_COLOR <- "grey55"
WARD_LABEL_COLOR <- "grey35"
BUILDING_FILL <- "#FFC800"
BUILDING_BORDER <- "#8A6400"
BUILDING_BUFFER_M <- 3
# IDP building footprints (camp/host) are deliberately a muted neutral,
# NOT the bold Non-IDP yellow - that yellow specifically signals "these
# are your candidate sampling points" on Non-IDP maps, which would be
# actively misleading on an IDP map where buildings carry no sampling
# meaning at all. Muted grey reads as background/orientation context only.
IDP_BUILDING_FILL <- "#B0B0B0"
IDP_BUILDING_BORDER <- "#8A8A8A"

# width_in: the actual panel width (inches, from compute_panel_dims()) -
# wrapping at a FIXED character width regardless of panel width (the old
# behaviour) made the caption block visually mismatch narrower panels
# (2026-08-12 feedback, idp_NG002001_5). chars_per_inch bumped 15 -> 19.5
# (2026-08-13 feedback: captions were visibly narrower than the map again)
# - 15 was too conservative for the actual 6.3pt caption font, wrapping
# well short of the panel's real width on wider panels. Re-tuned
# empirically, not derived.
wrap_caption <- function(text, width_in = 6.2, chars_per_inch = 19.5) {
  width <- max(30, round(width_in * chars_per_inch))
  paste(strwrap(text, width = width), collapse = "\n")
}

# coord_sf(expand = FALSE) with a fixed xlim/ylim renders the panel at its
# true shape-correct aspect ratio (approximately correcting for longitude
# compression at this latitude via cos(lat)), NOT at whatever aspect the
# output device happens to be. A hardcoded ggsave(width=6.2, height=5.6)
# canvas almost never matches that panel aspect, so ggplot letterboxes the
# panel within the fixed canvas - visible as white bars either side of (or
# above/below) the actual map (2026-08-12 feedback). Fix: size the device
# to match each cluster/LGA's own bbox aspect, so the panel fills it.
# extra_in reserves fixed vertical space for whatever sits outside the
# panel itself (legend + caption for cluster maps, title + caption for LGA
# maps) - tuned empirically by rendering and inspecting output, not derived.
compute_panel_dims <- function(bbox_p, base_dim = 6.2, extra_in = 1.5, min_dim = 3.6, max_ratio = 2.2) {
  mean_lat <- mean(c(unname(bbox_p["ymin"]), unname(bbox_p["ymax"])))
  dx <- unname(bbox_p["xmax"] - bbox_p["xmin"])
  dy <- unname(bbox_p["ymax"] - bbox_p["ymin"])
  hw_ratio <- dy / (dx * cos(mean_lat * pi / 180))
  hw_ratio <- max(1 / max_ratio, min(max_ratio, hw_ratio))  # clamp extreme shapes (e.g. very elongated LGAs)
  if (hw_ratio >= 1) {
    panel_h <- base_dim
    panel_w <- max(base_dim / hw_ratio, min_dim)
  } else {
    panel_w <- base_dim
    panel_h <- max(base_dim * hw_ratio, min_dim)
  }
  list(width = panel_w, height = panel_h + extra_in)
}

# ---------------------------------------------------------------------------
# Deterministic pipeline prefix (through hex_access) - same pattern as
# build_cluster_vector_maps.R / build_lga_summary_maps.R.
# ---------------------------------------------------------------------------
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
stopifnot(length(stop_idx) == 1)
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_mapex.R")
source("temp_boundaries_mapex.R")
file.remove("temp_boundaries_mapex.R")

selected_clusters <- readRDS(here::here(
  "_archive", "2026-08-06_design_frame_post_nw_targeted_resample", "selected_clusters_final.rds"
))

# hex_polygons: canonical hex geometry, keyed by uuid_hex. Two known gaps in
# hex_access alone, found while running this batch (2026-08-12) - both
# trace to the 2026-08-06 targeted NW-24-LGA resample (see CLAUDE.md):
#   1. A handful of uuid_hex values (e.g. Jibia/Mashi hexes) exist in the
#      resample's spliced household rows but were never present in this
#      LIVE project's own hex_access cache at all - the isolated resample
#      copy built its own separate hex grid that only got merged back in at
#      the household-row level, not the full candidate-hex-grid level.
#   2. A couple of uuid_hex values (e.g. Zamfara/Bakura, /Maru) have TWO
#      rows in hex_access sharing the same id, one a degenerate zero-area
#      sliver - plain distinct() could silently keep the sliver.
# Fix: dedupe hex_access preferring the largest-area row per uuid_hex (fixes
# gap 2), then supplement any uuid_hex still missing using selected_clusters
# _final.rds's own Non-IDP geometry, which DOES carry the real hex polygon
# per cluster (confirmed 2026-08-06's coverage_map2 fix write-up) - this
# also incidentally resolves any IDP cluster sharing that same uuid_hex with
# a Non-IDP draw, since hex_polygons is keyed by uuid_hex, not cluster_id.
hex_access_valid <- hex_access %>% st_make_valid() %>% st_transform(4326) %>% st_make_valid()
hex_access_dedup <- hex_access_valid %>%
  mutate(.area = as.numeric(st_area(hex_access_valid))) %>%
  arrange(desc(.area)) %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

selected_clusters_hex <- selected_clusters %>%
  filter(pop_type == "non_idp") %>%
  st_transform(4326) %>% st_make_valid() %>%
  filter(!st_is_empty(.)) %>%
  distinct(uuid_hex, .keep_all = TRUE) %>%
  select(uuid_hex)

missing_uuid_hex <- setdiff(selected_clusters_hex$uuid_hex, hex_access_dedup$uuid_hex)
hex_polygons <- bind_rows(hex_access_dedup, selected_clusters_hex %>% filter(uuid_hex %in% missing_uuid_hex))
if (length(missing_uuid_hex) > 0) {
  cat(sprintf("hex_polygons: supplemented %d uuid_hex value(s) missing from hex_access, from selected_clusters_final.rds.\n", length(missing_uuid_hex)))
}

iom_idp_wgs84 <- st_transform(iom_idp_df, 4326)

admin2_all <- NGA_shapes_all_cleaned$nga_admin2

nga_wards <- sf::st_read(
  here::here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
) %>% st_transform(4326) %>% st_make_valid()
nga_wards <- nga_wards[!st_is_empty(nga_wards), ]
WARD_NAME_COL <- "wardname"
stopifnot(WARD_NAME_COL %in% names(nga_wards))

# fetch_cluster_buildings() - lifted from 08_render_methodology_maps.R (not
# sourced wholesale, that script has its own example-cluster side effects).
lines2 <- readLines("scripts/08_render_methodology_maps.R")
fn_start <- which(grepl("^fetch_cluster_buildings <- function", lines2))
fn_end <- fn_start - 1 + which(grepl("^\\}$", lines2[fn_start:length(lines2)]))[1]
eval(parse(text = paste(lines2[fn_start:fn_end], collapse = "\n")))

stage2 <- read_csv(
  here::here(output_dir, "data", "data_collection", "NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv"),
  show_col_types = FALSE
)
backup_pts <- read_csv(
  here::here(output_dir, "data", "data_collection", "idp_camp_backup_points.csv"),
  show_col_types = FALSE
)

cluster_meta <- stage2 %>%
  filter(status == "primary") %>% group_by(cluster_id) %>% slice(1) %>% ungroup() %>%
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

# CLUSTER_ROAD_CLASSES: full detail for the tight cluster-level map, where
# local streets/connectors are exactly what a field team navigates by.
# LGA_ROAD_CLASSES: restricted to the inter-town backbone for the LGA-
# context annex map (2026-08-11) - the full set was producing dense,
# unreadable tangles inside built-up areas at LGA zoom; tertiary kept in
# for a first look at whether that's enough connective detail without the
# residential/unclassified clutter, per user's request to test it first.
CLUSTER_ROAD_CLASSES <- c("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
                          "secondary", "secondary_link", "tertiary", "tertiary_link", "residential",
                          "unclassified", "living_street", "road")
LGA_ROAD_CLASSES <- c("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
                      "secondary", "secondary_link", "tertiary", "tertiary_link")

roads_in_bbox <- function(bbox_p, highway_classes = CLUSTER_ROAD_CLASSES) {
  bbox_wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326)))
  r <- tryCatch(st_read(ROADS_GPKG, wkt_filter = bbox_wkt, quiet = TRUE), error = function(e) NULL)
  if (is.null(r) || nrow(r) == 0) return(NULL)
  r <- r %>% filter(highway %in% highway_classes)
  if (nrow(r) == 0) return(NULL)
  r
}

# Returns list(boundaries=, labels=) - boundaries are wards CLIPPED to the
# visible extent (so a big ward that only clips a corner of the map still
# draws correctly); labels are placed at the point-on-surface of the
# CLIPPED shape specifically, so a label never lands outside the frame
# even when the ward's true centroid is off-screen.
wards_in_bbox <- function(bbox_p) {
  extent_sfc <- sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326))
  nearby <- nga_wards[sf::st_intersects(nga_wards, extent_sfc, sparse = FALSE)[, 1], ]
  if (nrow(nearby) == 0) return(NULL)
  clipped <- suppressWarnings(sf::st_intersection(nearby, extent_sfc))
  clipped <- clipped[!sf::st_is_empty(clipped), ]
  if (nrow(clipped) == 0) return(NULL)
  labels <- suppressWarnings(sf::st_point_on_surface(clipped))
  list(boundaries = clipped, labels = labels)
}

label_sort_key <- function(s) {
  digits <- gsub("\\D", "", s)
  if (nchar(digits) == 0) 0 else as.integer(digits)
}

# ---------------------------------------------------------------------------
# POI (points of interest) - HOTOSM/OSM export, filtered to the curated
# "include" category list the user approved 2026-08-12/13 (output/
# poi_category_review.csv, 50 of 402 raw category values after the
# Silo/Storage Tank/Fuel removal - health, school, worship, market, water
# point, bank, hotel, tower/mast etc; excludes individual shops, parking,
# benches, and the long noisy free-text tail). ~58% of even the curated
# subset has no `name` value - shown as the title-cased category instead,
# and flagged in the map caption whenever a POI actually appears, per the
# user's explicit "flag the name-completeness gap wherever this is used"
# instruction.
# ---------------------------------------------------------------------------
POI_DIR <- here::here("input_data", "boundaries", "hotosm_nga_points_of_interest_osm_shp")
poi_review <- read_csv(here::here(output_dir, "poi_category_review.csv"), show_col_types = FALSE) %>%
  filter(suggested_action == "include")
poi_include_by_field <- split(poi_review$value, poi_review$field)

.poi_filter_include <- function(df) {
  keep <- rep(FALSE, nrow(df))
  poi_type <- rep(NA_character_, nrow(df))
  for (fld in names(poi_include_by_field)) {
    if (fld %in% names(df)) {
      m <- df[[fld]] %in% poi_include_by_field[[fld]]
      keep <- keep | m
      poi_type[m] <- df[[fld]][m]
    }
  }
  df$poi_type <- poi_type
  df[keep, ]
}

.title_case <- function(s) {
  s <- gsub("_", " ", s)
  gsub("(^|\\s)([a-z])", "\\1\\U\\2", s, perl = TRUE)
}

poi_pts_raw <- sf::st_read(file.path(POI_DIR, "points_of_interest_points.shp"), quiet = TRUE)
poi_polys_raw <- sf::st_read(file.path(POI_DIR, "points_of_interest_polygons.shp"), quiet = TRUE)

poi_pts_f <- .poi_filter_include(sf::st_drop_geometry(poi_pts_raw))
poi_pts <- poi_pts_raw[as.integer(rownames(poi_pts_f)), ] %>%
  mutate(poi_type = poi_pts_f$poi_type, has_name = !is.na(name) & name != "",
         poi_name = ifelse(has_name, name, .title_case(poi_type))) %>%
  select(poi_name, poi_type, has_name) %>% st_transform(4326)

poi_polys_f <- .poi_filter_include(sf::st_drop_geometry(poi_polys_raw))
poi_polys <- poi_polys_raw[as.integer(rownames(poi_polys_f)), ] %>%
  mutate(poi_type = poi_polys_f$poi_type, has_name = !is.na(name) & name != "",
         poi_name = ifelse(has_name, name, .title_case(poi_type))) %>%
  select(poi_name, poi_type, has_name) %>% suppressWarnings(st_centroid(.)) %>% st_transform(4326)

# bind_rows() on two sf objects whose sfc columns are individually typed
# sfc_POINT can still produce a generic sfc_GEOMETRY supertype column even
# though every element really is a POINT - a known sf quirk. That breaks
# st_coordinates() later (nudge_pois_from_markers()), so cast explicitly.
poi_all <- bind_rows(poi_pts, poi_polys) %>% sf::st_cast("POINT")
cat("Curated POI loaded:", nrow(poi_all), "\n")

poi_in_bbox <- function(bbox_p, max_n = 25, named_only = FALSE) {
  extent_sfc <- sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326))
  nearby <- poi_all[sf::st_intersects(poi_all, extent_sfc, sparse = FALSE)[, 1], ]
  if (named_only) nearby <- nearby[nearby$has_name, ]
  if (nrow(nearby) == 0) return(NULL)
  if (nrow(nearby) > max_n) {
    # Cap to the max_n POIs closest to the bbox centre - even numbered
    # markers become meaningless past some count.
    centre <- sf::st_centroid(extent_sfc)
    d <- as.numeric(sf::st_distance(nearby, centre))
    nearby <- nearby[order(d)[seq_len(max_n)], ]
  }
  nearby
}

# LGA-context map variant (2026-08-13 feedback): clip to the actual LGA
# polygon, not the padded bbox - the bbox extends ~6% past the LGA border
# on every side for framing, and a POI just outside the real LGA isn't
# "in reference to the hex" the way one inside it is. Cuts the LGA map's
# POI count substantially (e.g. Ngaski) since the padding margin often
# clips a wide strip of neighbouring LGAs.
poi_in_polygon <- function(poly, max_n = 25) {
  nearby <- poi_all[sf::st_intersects(poi_all, poly, sparse = FALSE)[, 1], ]
  if (nrow(nearby) == 0) return(NULL)
  if (nrow(nearby) > max_n) {
    centre <- sf::st_centroid(poly)
    d <- as.numeric(sf::st_distance(nearby, centre))
    nearby <- nearby[order(d)[seq_len(max_n)], ]
  }
  nearby
}

# Numbers POIs 1..N by distance from `anchor` (closest = 1) - a stable,
# meaningful order rather than arbitrary. Ties are broken by original row
# order (stable sort).
number_pois <- function(pois, anchor) {
  d <- as.numeric(sf::st_distance(pois, anchor))
  ordered <- pois[order(d), ]
  ordered$poi_number <- seq_len(nrow(ordered))
  ordered
}

# Looks up each POI's own ward (GRID3) for the legend table - best-effort,
# NA -> "-" if a POI falls outside every ward polygon (can happen right at
# the edge of GRID3's coverage).
lookup_poi_ward <- function(pois) {
  if (nrow(pois) == 0) { pois$poi_ward <- character(0); return(pois) }
  joined <- suppressWarnings(sf::st_join(pois, nga_wards[WARD_NAME_COL], join = sf::st_within, left = TRUE))
  joined$poi_ward <- ifelse(is.na(joined[[WARD_NAME_COL]]) | joined[[WARD_NAME_COL]] == "", "-", joined[[WARD_NAME_COL]])
  joined[, setdiff(names(joined), WARD_NAME_COL)]
}

# Nudges any POI sitting within min_dist_m of a sampling-point marker
# (HH/DTM/backup) directly away from it, so the two symbols never fully
# overlap - 2026-08-13 feedback ("make sure POI points don't fall under
# sampling point symbols"). Done in metres (projected CRS) for an accurate
# real-world distance, not degrees. Paired with drawing POI BEFORE the
# sampling markers in z-order, so even an un-nudged near-miss still shows
# the sampling marker on top rather than hiding it.
nudge_pois_from_markers <- function(pois, avoid_points, min_dist_m = 15) {
  if (is.null(avoid_points) || nrow(avoid_points) == 0 || nrow(pois) == 0) return(pois)
  pois_m <- sf::st_transform(pois, mycrs) %>% sf::st_cast("POINT")
  avoid_m <- sf::st_transform(avoid_points, mycrs) %>% sf::st_cast("POINT")
  avoid_xy <- sf::st_coordinates(avoid_m)
  poi_xy <- sf::st_coordinates(pois_m)
  for (i in seq_len(nrow(poi_xy))) {
    d <- sqrt((avoid_xy[, 1] - poi_xy[i, 1])^2 + (avoid_xy[, 2] - poi_xy[i, 2])^2)
    j <- which.min(d)
    if (d[j] < min_dist_m) {
      dx <- poi_xy[i, 1] - avoid_xy[j, 1]
      dy <- poi_xy[i, 2] - avoid_xy[j, 2]
      if (dx == 0 && dy == 0) { dx <- 1; dy <- 0.3 }
      k <- min_dist_m / sqrt(dx^2 + dy^2)
      poi_xy[i, 1] <- avoid_xy[j, 1] + dx * k
      poi_xy[i, 2] <- avoid_xy[j, 2] + dy * k
    }
  }
  sf::st_geometry(pois_m) <- sf::st_sfc(
    lapply(seq_len(nrow(poi_xy)), function(i) sf::st_point(poi_xy[i, ])), crs = mycrs
  )
  sf::st_transform(pois_m, 4326)
}

# Nudges POIs away from EACH OTHER (mutual repulsion) - separate from
# nudge_pois_from_markers() above, which only pushes POIs away from
# sampling points. Needed because two curated POIs can sit closer to each
# other than to any sampling marker (e.g. a market and a nearby mosque,
# ~10-15m apart): without this, their numbered badges visually overlap
# into an unreadable blob, defeating the point of numbering them (found
# 2026-08-13 in a post-batch spot-check - idp_NG002002_7's POI 2/3/4 and
# 5/6 both overlapped). Distance threshold is bbox-relative (a fraction
# of the map's own extent), same technique already used for the ward-
# label/marker collision fix (compute_repelled_label_positions's
# avoid_frac) - a fixed-metres threshold would be right for a cluster map
# but far too large/small at LGA-map zoom, since LGA maps span a whole
# LGA rather than ~500m-1km. Simple iterative pairwise repulsion, run
# AFTER nudge_pois_from_markers() so a POI already pushed clear of a
# sampling marker doesn't get pulled back into another POI (and vice
# versa) - a handful of iterations is enough to settle small clusters of
# 2-5 nearby POIs, which is the realistic case here (max 25 POI total on
# any one map, spread over a much larger area).
nudge_pois_from_each_other <- function(pois, bbox_p, min_frac = 0.028, iterations = 8) {
  n <- nrow(pois)
  if (n < 2) return(pois)
  span <- max(unname(bbox_p["xmax"] - bbox_p["xmin"]), unname(bbox_p["ymax"] - bbox_p["ymin"]))
  min_dist <- span * min_frac
  xy <- sf::st_coordinates(sf::st_geometry(pois))
  for (iter in seq_len(iterations)) {
    moved <- FALSE
    for (i in seq_len(n - 1)) {
      for (j in (i + 1):n) {
        dx <- xy[i, 1] - xy[j, 1]
        dy <- xy[i, 2] - xy[j, 2]
        d <- sqrt(dx^2 + dy^2)
        if (d < min_dist) {
          moved <- TRUE
          if (d == 0) { dx <- 0.001; dy <- 0.0003; d <- sqrt(dx^2 + dy^2) }
          push <- (min_dist - d) / 2
          ux <- dx / d; uy <- dy / d
          xy[i, 1] <- xy[i, 1] + ux * push
          xy[i, 2] <- xy[i, 2] + uy * push
          xy[j, 1] <- xy[j, 1] - ux * push
          xy[j, 2] <- xy[j, 2] - uy * push
        }
      }
    }
    if (!moved) break
  }
  sf::st_geometry(pois) <- sf::st_sfc(
    lapply(seq_len(n), function(i) sf::st_point(xy[i, ])), crs = sf::st_crs(pois)
  )
  pois
}

# Numbered badge markers - replaces the earlier text-label approach
# entirely (2026-08-13 feedback: names competed with ward labels/each
# other and were mostly unreadable). The name/ward pairing now lives in a
# small table under the map instead (see build_cluster_factsheets.py).
poi_marker_layers <- function(p, pois, size = 2.3) {
  p +
    geom_sf(data = pois, shape = 21, size = 5.6, fill = "#0E7C7B", color = "white", stroke = 0.6) +
    geom_sf_text(data = pois, aes(label = poi_number), size = size, color = "white", fontface = "bold")
}

# Full pipeline: number, look up ward, nudge away from markers, nudge away
# from each other, draw, and return the legend rows (for the CSV export
# the docx builder reads).
prepare_and_draw_pois <- function(p, pois, anchor, avoid_points = NULL, bbox_p = NULL) {
  pois <- number_pois(pois, anchor)
  pois <- lookup_poi_ward(pois)
  pois <- nudge_pois_from_markers(pois, avoid_points)
  if (!is.null(bbox_p)) pois <- nudge_pois_from_each_other(pois, bbox_p)
  p2 <- poi_marker_layers(p, pois)
  legend <- sf::st_drop_geometry(pois)
  legend$poi_category <- .title_case(legend$poi_type)
  legend <- legend[, c("poi_number", "poi_name", "poi_category", "poi_ward")]
  list(plot = p2, legend = legend)
}

# Computes ggrepel's repelled label positions ONCE against the plot built
# so far (which must already have its final coord_sf set, since repel
# positioning depends on the panel extent/aspect), then returns them as a
# plain data.frame. Fixes a halo-misalignment bug (2026-08-12): drawing
# the white-halo and grey-text layers as two INDEPENDENT geom_text_repel()
# calls - even with the same seed - let them converge to different
# equilibrium positions in crowded areas, because ggrepel's force
# simulation accounts for each label's own bounding box, and the halo
# layer's slightly larger font size gave it a different box. Running the
# repel simulation exactly once and reusing its output for both a white
# and a grey plain geom_text() layer guarantees pixel-identical alignment.
# avoid_points/bbox_p (both optional): after ggrepel places the labels
# (avoiding only each other), any label still within avoid_frac * the
# map's own extent of a marker (DTM/backup/HH point) is nudged directly
# away from that marker until clear. Fixes 2026-08-12 feedback
# (idp_NG002001_5: ward label rendered directly under the DTM cross,
# unreadable). An earlier attempt fed the marker positions into ggrepel
# itself as unlabelled phantom rows, on the theory that ggrepel would then
# treat them as obstacles too - didn't work, because a single-character
# phantom label has a near-zero bounding box, far smaller than the marker's
# actual visual footprint, so ggrepel saw nothing worth avoiding. A direct
# geometric exclusion radius (scaled to the current map's own extent, since
# a fixed-degrees radius would be enormous on a tight cluster map and
# invisible on a wide LGA map) is simpler and actually guarantees clearance.
compute_repelled_label_positions <- function(p_so_far, labels_sf, label_col, size, seed, avoid_points = NULL, bbox_p = NULL, avoid_frac = 0.035) {
  temp_p <- p_so_far + ggrepel::geom_text_repel(
    data = labels_sf, aes(label = .data[[label_col]], geometry = geometry), stat = "sf_coordinates",
    size = size, min.segment.length = 0, segment.size = 0, max.overlaps = Inf, seed = seed
  )
  built <- ggplot2::ggplot_build(temp_p)
  layer_data <- built$data[[length(built$data)]]
  pos <- data.frame(x = layer_data$x, y = layer_data$y, label = layer_data$label)

  if (!is.null(avoid_points) && nrow(avoid_points) > 0 && !is.null(bbox_p)) {
    avoid_xy <- sf::st_coordinates(sf::st_geometry(avoid_points))
    span <- max(unname(bbox_p["xmax"] - bbox_p["xmin"]), unname(bbox_p["ymax"] - bbox_p["ymin"]))
    min_dist <- span * avoid_frac
    for (i in seq_len(nrow(pos))) {
      d <- sqrt((avoid_xy[, 1] - pos$x[i])^2 + (avoid_xy[, 2] - pos$y[i])^2)
      j <- which.min(d)
      if (d[j] < min_dist) {
        dx <- pos$x[i] - avoid_xy[j, 1]
        dy <- pos$y[i] - avoid_xy[j, 2]
        if (dx == 0 && dy == 0) { dx <- 1; dy <- 0.3 }
        k <- min_dist / sqrt(dx^2 + dy^2)
        pos$x[i] <- avoid_xy[j, 1] + dx * k
        pos$y[i] <- avoid_xy[j, 2] + dy * k
      }
    }
  }
  pos
}

ward_label_halo_layers <- function(p, wards, size = 2.6, seed = 1, avoid_points = NULL, bbox_p = NULL) {
  pos <- compute_repelled_label_positions(p, wards$labels, WARD_NAME_COL, size, seed, avoid_points = avoid_points, bbox_p = bbox_p)
  p +
    geom_text(data = pos, aes(x = x, y = y, label = label), size = size + 0.3, color = "white",
              fontface = "italic", inherit.aes = FALSE) +
    geom_text(data = pos, aes(x = x, y = y, label = label), size = size, color = WARD_LABEL_COLOR,
              fontface = "italic", inherit.aes = FALSE)
}

# A custom always-metres scale bar was attempted (to fix ggspatial's
# auto-unit-switching, km vs m, across different-sized cluster maps) but
# had to be abandoned 2026-08-11: adding its geom_sf()/geom_sf_text()
# layers - even spliced into the same unbroken `+` chain as everything
# else - unpredictably broke coord_sf()'s fixed xlim/ylim, causing the
# whole map to silently zoom out to the full data extent instead of the
# intended tight window. Reverted to ggspatial::annotation_scale() (proven
# reliable all session) rather than keep chasing a real but hard-to-pin-
# down ggplot2/sf interaction bug for a cosmetic unit-consistency issue.
# The km-vs-m inconsistency across map sizes remains a known limitation.

# ---------------------------------------------------------------------------
# POI legend accumulators - PRE-LOADED from any existing _poi_legend.csv so
# a resumed/incremental batch (which skips already-rendered clusters, see
# the main loop below) doesn't drop those clusters' POI rows when the CSV
# gets rewritten at the end. Only clusters actually (re)rendered in THIS
# run overwrite their own entry; every other cluster's previously-written
# rows pass through unchanged.
# ---------------------------------------------------------------------------
load_existing_poi_legend <- function(dir_path) {
  path <- file.path(dir_path, "_poi_legend.csv")
  out <- list()
  if (file.exists(path)) {
    df <- read_csv(path, show_col_types = FALSE)
    if (nrow(df) > 0) {
      for (cid in unique(df$cluster_id)) {
        out[[cid]] <- df[df$cluster_id == cid, setdiff(names(df), "cluster_id"), drop = FALSE]
      }
    }
  }
  out
}

poi_legend_rows_cluster <- load_existing_poi_legend(maps_out_dir)
poi_legend_rows_lga <- new.env()  # populated below once lga_out_dir is known

# ---------------------------------------------------------------------------
# Per-cluster render
# ---------------------------------------------------------------------------
render_example_map <- function(cid) {
  meta <- cluster_meta %>% filter(cluster_id == cid)
  stopifnot(nrow(meta) == 1)
  uuid_hex_i <- uuid_hex_lookup %>% filter(cluster_id == cid) %>% pull(uuid_hex)
  hex_i <- hex_polygons %>% filter(uuid_hex == uuid_hex_i)
  # has_hex: FALSE for a small number of resample-edge-case clusters even
  # after the hex_polygons supplement above (2026-08-12) - degrade
  # gracefully (skip the hex layer/use a points-only bbox) rather than
  # hard-fail and produce no map at all for that cluster.
  has_hex <- nrow(hex_i) == 1 && !any(st_is_empty(hex_i))

  pop_type <- meta$pop_type
  idp_cat <- meta$idp_population_category
  # "Other IDP site (not sampled)" marker removed 2026-08-12 per user
  # feedback - with multiple other sites in a hex it stretched the bbox
  # dramatically (see idp_NG008006_11, one far-flung other site turned a
  # ~500m-wide area of interest into a ~2km-tall mostly-empty map) and read
  # as confusing next to the actual sampled site. other_sites_in_hex()
  # kept below, just no longer called from the render path.
  other_sites <- NULL

  bg_theme <- theme_void() +
    theme(
      panel.background = element_rect(fill = "grey97", color = NA),
      # hjust=0.5 + legend.location="plot" (ggplot2 >=3.5): both the caption
      # and the bottom legend get centered against the FULL plot width, not
      # just their own shrink-wrapped content - fixes the legend/caption
      # block reading narrower than the map above it (2026-08-12 feedback).
      plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4), hjust = 0.5),
      legend.location = "plot",
      plot.margin = margin(3, 3, 3, 3)
    )

  if (pop_type == "non_idp") {
    hh_rows <- stage2 %>% filter(cluster_id == cid)
    hh_pts <- st_as_sf(hh_rows, coords = c("longitude", "latitude"), crs = 4326) %>%
      mutate(
        short_id = sapply(strsplit(survey_id, "_"), function(x) tail(x, 1)),
        status = factor(status, levels = c("primary", "reserve"))
      ) %>%
      arrange(status, sapply(short_id, label_sort_key))

    bbox_p <- if (has_hex) {
      st_bbox(hex_i) + c(-0.01, -0.01, 0.01, 0.01)
    } else {
      st_bbox(hh_pts) + c(-0.003, -0.003, 0.003, 0.003)
    }
    dims <- compute_panel_dims(bbox_p, extra_in = 1.5)
    roads <- roads_in_bbox(bbox_p)
    wards <- wards_in_bbox(bbox_p)
    pois <- poi_in_bbox(bbox_p)
    buildings <- if (has_hex) tryCatch(fetch_cluster_buildings(hex_i) %>% st_transform(4326), error = function(e) NULL) else NULL
    if (!is.null(buildings) && nrow(buildings) > 0) {
      # Buffer slightly so small footprints are still visible as a filled
      # shape at this zoom, rather than disappearing to a sub-pixel sliver.
      buildings <- st_buffer(st_transform(buildings, mycrs), BUILDING_BUFFER_M) %>% st_transform(4326)
    }

    marker_fill <- c(primary = "#1F3864", reserve = "#FFFFFF")
    marker_shape <- c(primary = 21, reserve = 21)

    p <- ggplot()
    if (!is.null(roads)) {
      p <- p + geom_sf(data = roads, color = ROAD_COLOR, linewidth = 0.5)
    }
    if (!is.null(wards)) {
      p <- p + geom_sf(data = wards$boundaries, fill = NA, color = WARD_BORDER_COLOR, linewidth = 0.35)
    }
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#1F386412", color = "#1F3864", linewidth = 1.2)
    if (!is.null(buildings) && nrow(buildings) > 0) {
      p <- p + geom_sf(data = buildings, fill = BUILDING_FILL, color = BUILDING_BORDER, linewidth = 0.2, alpha = 0.85)
    }
    if (!is.null(wards)) {
      p <- ward_label_halo_layers(p, wards, size = 2.6, seed = 1, avoid_points = hh_pts, bbox_p = bbox_p)
    }
    if (!is.null(pois)) {
      anchor <- sf::st_centroid(sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326)))
      res <- prepare_and_draw_pois(p, pois, anchor, avoid_points = hh_pts, bbox_p = bbox_p)
      p <- res$plot
      poi_legend_rows_cluster[[cid]] <<- res$legend
    }
    p <- p +
      geom_sf(data = hh_pts, aes(fill = status), shape = 21, size = 3.4, stroke = 1, color = "#1F3864") +
      ggrepel::geom_text_repel(
        data = hh_pts, aes(label = short_id, geometry = geometry), stat = "sf_coordinates",
        size = 2.3, color = "#1F3864", min.segment.length = 0, segment.size = 0.25,
        max.overlaps = 30, seed = 1
      ) +
      scale_fill_manual(values = marker_fill, name = NULL, labels = c(primary = "Primary HH", reserve = "Reserve HH")) +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        if (has_hex) "Blue outline = Stage 1 hexagon boundary. " else "",
        "Yellow = building footprints. Orange lines = roads (OpenStreetMap/HOTOSM). ",
        "Grey line/italic label = ward boundary/name (GRID3).",
        " Filled = primary HH, hollow = reserve HH. Labels are the short survey ID suffix (e.g. HH01, R01).",
        if (!is.null(pois)) " Numbered teal marker = known point of interest (OpenStreetMap/HOTOSM) - see the table below for name/ward, matched by number." else ""
      ), width_in = dims$width)) +
      bg_theme + theme(legend.position = "bottom", legend.text = element_text(size = 7))

  } else if (idp_cat == "idps in camp") {
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    backup_row <- backup_pts %>% filter(site_id == cid, !is.na(backup_gps_lat))
    has_backup <- nrow(backup_row) == 1
    point_labels <- c(dtm = "DTM point (Tier 1 listing)", backup = "Backup point (Tier 2 fallback only)")
    # Build oldest-drawn-first (backup, then DTM) so DTM - the point field
    # teams actually start at - always ends up on top when points sit close
    # together (see 2026-08-07 marker-overlap fix).
    pts_list <- list()
    if (has_backup) {
      backup_pt <- st_sfc(st_point(c(backup_row$backup_gps_lon, backup_row$backup_gps_lat)), crs = 4326)
      pts_list <- c(pts_list, list(st_sf(point_type = factor(point_labels[["backup"]], levels = point_labels), geometry = backup_pt)))
    }
    pts_list <- c(pts_list, list(st_sf(point_type = factor(point_labels[["dtm"]], levels = point_labels), geometry = dtm_pt)))
    pts_sf <- do.call(rbind, pts_list)

    marker_shape <- setNames(c(3, 17), point_labels)
    marker_color <- setNames(c("#FF3B30", "#FFA500"), point_labels)
    marker_size <- setNames(c(4.5, 5.4), point_labels)

    bbox_pts <- st_bbox(pts_sf)
    if (has_hex) {
      bbox_hex <- st_bbox(hex_i)
      bbox_p <- c(
        xmin = min(bbox_hex["xmin"], bbox_pts["xmin"]), ymin = min(bbox_hex["ymin"], bbox_pts["ymin"]),
        xmax = max(bbox_hex["xmax"], bbox_pts["xmax"]), ymax = max(bbox_hex["ymax"], bbox_pts["ymax"])
      ) + c(-0.006, -0.006, 0.006, 0.006)
    } else {
      bbox_p <- bbox_pts + c(-0.003, -0.003, 0.003, 0.003)
    }
    dims <- compute_panel_dims(bbox_p, extra_in = 1.5)
    roads <- roads_in_bbox(bbox_p)
    wards <- wards_in_bbox(bbox_p)
    pois <- poi_in_bbox(bbox_p)
    buildings <- if (has_hex) tryCatch(fetch_cluster_buildings(hex_i) %>% st_transform(4326), error = function(e) NULL) else NULL
    if (!is.null(buildings) && nrow(buildings) > 0) {
      buildings <- st_buffer(st_transform(buildings, mycrs), BUILDING_BUFFER_M) %>% st_transform(4326)
    }

    p <- ggplot()
    if (!is.null(roads)) p <- p + geom_sf(data = roads, color = ROAD_COLOR, linewidth = 0.5)
    if (!is.null(wards)) p <- p + geom_sf(data = wards$boundaries, fill = NA, color = WARD_BORDER_COLOR, linewidth = 0.35)
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#6A3D9A12", color = "#6A3D9A", linewidth = 1.2)
    if (!is.null(buildings) && nrow(buildings) > 0) {
      p <- p + geom_sf(data = buildings, fill = IDP_BUILDING_FILL, color = IDP_BUILDING_BORDER, linewidth = 0.15, alpha = 0.5)
    }
    if (!is.null(wards)) {
      p <- ward_label_halo_layers(p, wards, size = 2.6, seed = 1, avoid_points = pts_sf, bbox_p = bbox_p)
    }
    if (!is.null(pois)) {
      anchor <- sf::st_centroid(sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326)))
      res <- prepare_and_draw_pois(p, pois, anchor, avoid_points = pts_sf, bbox_p = bbox_p)
      p <- res$plot
      poi_legend_rows_cluster[[cid]] <<- res$legend
    }
    # White halos + markers interleaved per-point (not one halo layer then
    # one combined marker layer) so z-order is: backup halo, backup marker,
    # DTM halo, DTM marker - DTM (the point field teams actually start at)
    # ends up on top of everything, including backup's own marker, not just
    # on top of the halo layer as a whole (2026-08-12 fix - the previous
    # single pre-pass halo sat BELOW the backup marker when the two points
    # were close together). Both marker layers keep the shared aes mapping
    # so scale_shape_manual/scale_color_manual still produce one legend.
    dtm_row <- filter(pts_sf, point_type == point_labels[["dtm"]])
    if (has_backup) {
      backup_row_sf <- filter(pts_sf, point_type == point_labels[["backup"]])
      p <- p + geom_sf(data = backup_row_sf, shape = 17, size = 6.1, stroke = 2.6, color = "white")
      p <- p + geom_sf(data = backup_row_sf, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6)
    }
    p <- p + geom_sf(data = dtm_row, shape = 3, size = 5.2, stroke = 2.6, color = "white")
    p <- p +
      geom_sf(data = dtm_row, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6) +
      scale_shape_manual(values = marker_shape, name = NULL, drop = FALSE) +
      scale_color_manual(values = marker_color, name = NULL, drop = FALSE) +
      scale_size_manual(values = marker_size, name = NULL, guide = "none", drop = FALSE) +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        if (has_hex) "Purple outline = Stage 1 hexagon boundary. " else "",
        "Grey = building footprints (context only - not part of the IDP sampling method). ",
        "Orange lines = roads (OpenStreetMap/HOTOSM). Grey line/italic label = ward boundary/name (GRID3).",
        if (!is.null(pois)) " Numbered teal marker = known point of interest (OpenStreetMap/HOTOSM) - see the table below for name/ward, matched by number." else ""
      ), width_in = dims$width)) +
      bg_theme + theme(legend.position = "bottom", legend.text = element_text(size = 7))

  } else {
    # idps in host - Tier 1 listing itself is NOT geographically bounded
    # (chief/head-of-settlement social knowledge, not a radius or hexagon -
    # see methodology doc Section 3) - but the cluster's Stage 1 PSU IS
    # still a real hexagon, same as every other cluster type; showing NO
    # hexagon at all read as structurally inconsistent and confusing next
    # to Non-IDP/camp maps (2026-08-10 feedback). Shown dashed and
    # unfilled specifically to signal "context only, not a listing
    # boundary" - do not treat this edge as a stopping point.
    dtm_pt <- st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326)
    # DTM marker aligned to camp's exact symbology (2026-08-10 feedback -
    # both represent the same thing: an IOM DTM point marking the start of
    # the household-listing protocol) - same shape/colour/size as camp's
    # "DTM point (Tier 1 listing)", just re-labelled for the host context.
    point_labels <- c(dtm = "DTM point (start of listing)")
    pts_sf <- st_sf(point_type = factor(point_labels[["dtm"]], levels = point_labels), geometry = dtm_pt)
    marker_shape <- setNames(3, point_labels)
    marker_color <- setNames("#FF3B30", point_labels)
    marker_size <- setNames(4.5, point_labels)

    buildings <- if (has_hex) tryCatch(fetch_cluster_buildings(hex_i) %>% st_transform(4326), error = function(e) NULL) else NULL
    if (!is.null(buildings) && nrow(buildings) > 0) {
      buildings <- st_buffer(st_transform(buildings, mycrs), BUILDING_BUFFER_M) %>% st_transform(4326)
    }

    dtm_proj <- st_transform(dtm_pt, mycrs)
    pad_m <- 260
    bbox_proj <- st_bbox(dtm_proj) + c(-pad_m, -pad_m, pad_m, pad_m)
    extent_wgs84 <- st_as_sfc(st_bbox(bbox_proj, crs = mycrs)) %>% st_transform(4326)
    bbox_p <- st_bbox(extent_wgs84)
    dims <- compute_panel_dims(bbox_p, extra_in = 1.5)
    roads <- roads_in_bbox(bbox_p)
    wards <- wards_in_bbox(bbox_p)
    pois <- poi_in_bbox(bbox_p)

    p <- ggplot()
    if (!is.null(roads)) p <- p + geom_sf(data = roads, color = ROAD_COLOR, linewidth = 0.5)
    if (!is.null(wards)) p <- p + geom_sf(data = wards$boundaries, fill = NA, color = WARD_BORDER_COLOR, linewidth = 0.35)
    if (!is.null(buildings) && nrow(buildings) > 0) {
      p <- p + geom_sf(data = buildings, fill = IDP_BUILDING_FILL, color = IDP_BUILDING_BORDER, linewidth = 0.15, alpha = 0.5)
    }
    # coord_sf clips this to whatever portion of the hexagon falls within
    # the tight point-centred extent above - deliberately NOT widened to
    # fit the whole hexagon, to keep the useful close-up street-level zoom.
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = NA, color = "#6A3D9A", linewidth = 0.9, linetype = "dashed")
    if (!is.null(wards)) {
      p <- ward_label_halo_layers(p, wards, size = 2.6, seed = 1, avoid_points = pts_sf, bbox_p = bbox_p)
    }
    if (!is.null(pois)) {
      anchor <- sf::st_centroid(sf::st_as_sfc(sf::st_bbox(bbox_p, crs = 4326)))
      res <- prepare_and_draw_pois(p, pois, anchor, avoid_points = pts_sf, bbox_p = bbox_p)
      p <- res$plot
      poi_legend_rows_cluster[[cid]] <<- res$legend
    }
    # Thin white halo behind the DTM point (start of listing) - it could get
    # lost against the orange roads layer (2026-08-12 feedback). Fixed
    # aesthetics (not aes-mapped), so it doesn't add its own legend entry.
    p <- p + geom_sf(data = pts_sf, shape = 3, size = 5.2, stroke = 2.6, color = "white")
    p <- p +
      geom_sf(data = pts_sf, aes(shape = point_type, color = point_type, size = point_type), stroke = 1.6) +
      scale_shape_manual(values = marker_shape, name = NULL, drop = FALSE) +
      scale_color_manual(values = marker_color, name = NULL, drop = FALSE) +
      scale_size_manual(values = marker_size, name = NULL, guide = "none", drop = FALSE) +
      coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE) +
      annotation_scale(location = "br", text_cex = 0.8) +
      annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
      labs(caption = wrap_caption(paste0(
        if (has_hex) "Purple dashed = Stage 1 hexagon (PSU) boundary - shown for context only. Your household listing is NOT bounded by this hexagon; it is based on local social recognition of who belongs to this settlement, per your FO's guidance. " else "",
        "Grey = building footprints (context only). Orange lines = roads (OpenStreetMap/HOTOSM). Grey line/italic label = ward boundary/name (GRID3).",
        if (!is.null(pois)) " Numbered teal marker = known point of interest (OpenStreetMap/HOTOSM) - see the table below for name/ward, matched by number." else ""
      ), width_in = dims$width)) +
      bg_theme + theme(legend.position = "bottom", legend.text = element_text(size = 7))
  }

  fname <- paste0(cid, ".png")
  # dims already computed per-branch above (needed early for wrap_caption's
  # adaptive width) - reused here rather than recomputed.
  ggsave(file.path(maps_out_dir, fname), p, width = dims$width, height = dims$height, dpi = 150, bg = "white")
  invisible(fname)
}

all_cluster_ids <- cluster_meta$cluster_id
cat("\n", length(all_cluster_ids), "clusters total.\n")

# ==============================================================================
# LGA-context annex map - one per cluster, zoomed to the LGA extent the
# cluster falls within (not the tight ~500m-1km cluster view above), for a
# new annex page at the end of the field guide. Per user request
# (2026-08-11): "still cluster-specific" - i.e. this highlights THIS
# cluster's own hexagon/point within the wider LGA, not every cluster in
# the LGA. Reuses the exact same colour scheme as the tight cluster maps
# (navy Non-IDP hex, purple IDP hex/point, orange roads, grey wards) for a
# first draft - deliberately simplified content vs. the tight map (no
# individual HH point labels, no building footprints) since those aren't
# legible or useful at LGA scale; this map's job is orientation ("where in
# my LGA is this cluster"), not household-level navigation.
# ==============================================================================
lga_out_dir <- here::here(output_dir, "maps", "cluster_lga_context_v1")
dir.create(lga_out_dir, recursive = TRUE, showWarnings = FALSE)

# poi_legend_rows_lga pre-loaded now that lga_out_dir is known - see the
# poi_legend_rows_cluster comment above for why this is pre-loaded rather
# than started empty.
poi_legend_rows_lga_list <- load_existing_poi_legend(lga_out_dir)
for (nm in names(poi_legend_rows_lga_list)) assign(nm, poi_legend_rows_lga_list[[nm]], envir = poi_legend_rows_lga)

render_lga_context_map <- function(cid) {
  meta <- cluster_meta %>% filter(cluster_id == cid)
  stopifnot(nrow(meta) == 1)
  uuid_hex_i <- uuid_hex_lookup %>% filter(cluster_id == cid) %>% pull(uuid_hex)
  hex_i <- hex_polygons %>% filter(uuid_hex == uuid_hex_i)
  has_hex <- nrow(hex_i) == 1 && !any(st_is_empty(hex_i))  # see cluster-map render fn for why this can be FALSE

  lga_boundary <- admin2_all %>% filter(adm2_pcode == meta$adm2_pcode) %>% st_transform(4326) %>% st_make_valid()
  stopifnot(nrow(lga_boundary) == 1)

  pop_type <- meta$pop_type
  idp_cat <- meta$idp_population_category

  bbox <- st_bbox(lga_boundary)
  pad_x <- unname((bbox["xmax"] - bbox["xmin"]) * 0.06 + 0.005)
  pad_y <- unname((bbox["ymax"] - bbox["ymin"]) * 0.06 + 0.005)
  bbox_p <- c(
    xmin = unname(bbox["xmin"]) - pad_x, ymin = unname(bbox["ymin"]) - pad_y,
    xmax = unname(bbox["xmax"]) + pad_x, ymax = unname(bbox["ymax"]) + pad_y
  )
  dims <- compute_panel_dims(bbox_p, extra_in = 0.95)
  roads <- roads_in_bbox(bbox_p, highway_classes = LGA_ROAD_CLASSES)
  wards <- wards_in_bbox(bbox_p)
  # Clipped to the LGA polygon itself (not the padded bbox) - see
  # poi_in_polygon()'s comment for why.
  pois <- poi_in_polygon(lga_boundary, max_n = 25)

  bg_theme <- theme_void() +
    theme(
      panel.background = element_rect(fill = "grey97", color = NA),
      plot.caption = element_text(size = 6.3, color = "grey40", margin = margin(t = 4), hjust = 0.5),
      legend.location = "plot",
      plot.margin = margin(3, 3, 3, 3)
    )

  # Mask: dims everything outside the selected LGA (drawn after roads/wards,
  # before the LGA boundary + cluster marker) so the eye is drawn to the
  # LGA itself rather than the surrounding area, per 2026-08-11 feedback.
  mask_poly <- suppressWarnings(st_difference(st_as_sfc(st_bbox(bbox_p, crs = 4326)), st_union(st_geometry(lga_boundary))))

  p <- ggplot()
  if (!is.null(roads)) p <- p + geom_sf(data = roads, color = ROAD_COLOR, linewidth = 0.35, alpha = 0.85)
  if (!is.null(wards)) p <- p + geom_sf(data = wards$boundaries, fill = NA, color = WARD_BORDER_COLOR, linewidth = 0.3)
  if (length(mask_poly) > 0) p <- p + geom_sf(data = mask_poly, fill = "white", color = NA, alpha = 0.65)
  p <- p + geom_sf(data = lga_boundary, fill = NA, color = "#1A1A1A", linewidth = 1.1)

  avoid_pt <- st_sf(geometry = st_sfc(st_point(c(meta$longitude, meta$latitude)), crs = 4326))
  if (pop_type == "non_idp") {
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#1F3864", color = "#1F3864", linewidth = 0.8, alpha = 0.55)
    p <- p + geom_sf(data = avoid_pt, shape = 21, size = 2.6, stroke = 0.9, color = "#1F3864", fill = "#00E5FF")
    boundary_note <- if (has_hex) "Blue hexagon/point = your Non-IDP cluster." else "Blue point = your Non-IDP cluster (hexagon boundary unavailable for this cluster)."
  } else if (idp_cat == "idps in camp") {
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = "#6A3D9A", color = "#6A3D9A", linewidth = 0.8, alpha = 0.55)
    p <- p + geom_sf(data = avoid_pt, shape = 3, size = 3, stroke = 1.3, color = "#FF3B30")
    boundary_note <- if (has_hex) "Purple hexagon/red cross = your IDP in-camp cluster." else "Red cross = your IDP in-camp cluster (hexagon boundary unavailable for this cluster)."
  } else {
    if (has_hex) p <- p + geom_sf(data = hex_i, fill = NA, color = "#6A3D9A", linewidth = 0.7, linetype = "dashed")
    p <- p + geom_sf(data = avoid_pt, shape = 21, size = 3, stroke = 1, color = "#6A3D9A", fill = "#D9A9FF")
    boundary_note <- if (has_hex) "Purple dashed hexagon (context only) + point = your IDP host-community cluster." else "Point = your IDP host-community cluster (hexagon boundary unavailable for this cluster)."
  }

  if (!is.null(wards)) {
    p <- ward_label_halo_layers(p, wards, size = 2.2, seed = 1, avoid_points = avoid_pt, bbox_p = bbox_p)
  }
  if (!is.null(pois)) {
    res <- prepare_and_draw_pois(p, pois, avoid_pt, avoid_points = avoid_pt, bbox_p = bbox_p)
    p <- res$plot
    assign(cid, res$legend, envir = poi_legend_rows_lga)
  }

  p <- p +
    coord_sf(xlim = c(bbox_p["xmin"], bbox_p["xmax"]), ylim = c(bbox_p["ymin"], bbox_p["ymax"]), expand = FALSE) +
    annotation_scale(location = "br", text_cex = 0.8) +
    annotation_north_arrow(location = "tl", height = unit(0.7, "cm"), width = unit(0.7, "cm")) +
    labs(
      title = paste0(meta$adm2_name, " LGA"),
      caption = wrap_caption(paste0(
        "Black outline = LGA boundary (OCHA/COD). Orange lines = roads (OpenStreetMap/HOTOSM). ",
        "Grey line/italic label = ward boundary/name (GRID3). ",
        boundary_note, " For exact navigation, use the cluster-level map below (next page or same page), not this one.",
        if (!is.null(pois)) " Numbered teal marker = known point of interest (OpenStreetMap/HOTOSM) - see the table below for name/ward, matched by number." else ""
      ), width_in = dims$width)
    ) +
    bg_theme +
    theme(plot.title = element_text(size = 10, face = "bold", color = "#1A1A1A", hjust = 0.5, margin = margin(b = 4)))

  fname <- paste0(cid, ".png")
  # dims already computed above (needed early for wrap_caption's adaptive width)
  ggsave(file.path(lga_out_dir, fname), p, width = dims$width, height = dims$height, dpi = 150, bg = "white")
  invisible(fname)
}

# ==============================================================================
# Resumable production loop - both maps, every cluster. Skips a cluster
# entirely if both its PNGs already exist (preserves the approved example
# renders untouched, and makes an interrupted/rerun batch pick up cleanly).
# Each cluster wrapped in tryCatch so one bad cluster (missing geometry,
# transient file lock, etc.) doesn't kill the remaining batch. POI legend
# CSVs are written after every 200 clusters (not just at the very end) so
# an interrupted run still leaves a usable, up-to-date legend file.
# ==============================================================================
log_path <- here::here(output_dir, "maps", "_production_build_log.csv")
if (!file.exists(log_path)) {
  writeLines("cluster_id,map_type,status,elapsed_s,timestamp,error_message", log_path)
}

log_row <- function(cid, map_type, status, elapsed_s, error_message = "") {
  line <- paste(
    cid, map_type, status, sprintf("%.2f", elapsed_s),
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    gsub("[\r\n,]", " ", error_message),
    sep = ","
  )
  cat(line, "\n", file = log_path, append = TRUE)
}

write_poi_legends <- function() {
  if (length(poi_legend_rows_cluster) > 0) {
    legend_df <- dplyr::bind_rows(poi_legend_rows_cluster, .id = "cluster_id")
    write.csv(legend_df, file.path(maps_out_dir, "_poi_legend.csv"), row.names = FALSE)
  }
  lga_list <- as.list(poi_legend_rows_lga)
  if (length(lga_list) > 0) {
    legend_df2 <- dplyr::bind_rows(lga_list, .id = "cluster_id")
    write.csv(legend_df2, file.path(lga_out_dir, "_poi_legend.csv"), row.names = FALSE)
  }
}

t_batch_start <- Sys.time()
n_done <- 0
n_skipped <- 0
n_error <- 0

for (i in seq_along(all_cluster_ids)) {
  cid <- all_cluster_ids[i]
  cluster_png <- file.path(maps_out_dir, paste0(cid, ".png"))
  lga_png <- file.path(lga_out_dir, paste0(cid, ".png"))

  if (file.exists(cluster_png) && file.exists(lga_png)) {
    n_skipped <- n_skipped + 1
  } else {
    if (!file.exists(cluster_png)) {
      t0 <- Sys.time()
      res <- tryCatch({ render_example_map(cid); "ok" }, error = function(e) e)
      elapsed <- as.numeric(Sys.time() - t0, units = "secs")
      if (identical(res, "ok")) {
        log_row(cid, "cluster", "ok", elapsed)
      } else {
        n_error <- n_error + 1
        log_row(cid, "cluster", "error", elapsed, conditionMessage(res))
      }
    }
    if (!file.exists(lga_png)) {
      t0 <- Sys.time()
      res <- tryCatch({ render_lga_context_map(cid); "ok" }, error = function(e) e)
      elapsed <- as.numeric(Sys.time() - t0, units = "secs")
      if (identical(res, "ok")) {
        log_row(cid, "lga_context", "ok", elapsed)
      } else {
        n_error <- n_error + 1
        log_row(cid, "lga_context", "error", elapsed, conditionMessage(res))
      }
    }
    n_done <- n_done + 1
  }

  if (i %% 50 == 0 || i == length(all_cluster_ids)) {
    cat(sprintf(
      "  [%d/%d] rendered=%d skipped=%d errors=%d elapsed=%.1f min\n",
      i, length(all_cluster_ids), n_done, n_skipped, n_error,
      as.numeric(Sys.time() - t_batch_start, units = "mins")
    ))
  }
  if (i %% 200 == 0) write_poi_legends()
}

write_poi_legends()

cat(sprintf(
  "\nDONE in %.1f minutes. rendered=%d skipped(already done)=%d errors=%d\n",
  as.numeric(Sys.time() - t_batch_start, units = "mins"), n_done, n_skipped, n_error
))
cat("Cluster maps:", maps_out_dir, "\n")
cat("LGA-context maps:", lga_out_dir, "\n")
cat("Log:", log_path, "\n")
if (n_error > 0) {
  cat("\nNOTE:", n_error, "map(s) failed - see", log_path, "for cluster_id + error_message. Rerun this script to retry only the failed/missing ones.\n")
}
