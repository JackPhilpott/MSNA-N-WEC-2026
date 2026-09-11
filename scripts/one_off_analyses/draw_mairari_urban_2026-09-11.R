# ==============================================================================
# Draws the Mairari (Guzamala, Borno) "MSNA Light" sample - third and last of
# the 3 government-negotiated LGAs (Abadam/Malam Fatori and Nganzai/Gajiram
# done first - see draw_malam_fatori_urban_2026-09-11.R for full context).
#
# CORRECTION 2026-09-11: Jack initially had me check "Monguno"/"Wamiri" for
# Guzamala (the one ward FACT's written accessibility SHEET happened to mark
# Yes) - but Jack later confirmed via FACT's actual verbal/message
# communication that night that the real intended ward is Mairari, not
# Wamiri. Wamiri checked out as genuinely sparse/rural (41-building max
# cluster, 431 buildings across the whole 306km2 ward) and was never drawn.
# Mairari is a real, if smaller, settlement - checked directly, not assumed:
# self-contained (dense cluster doesn't touch any neighbouring ward), core
# of 243 buildings in 0.41km2 (597 bldg/km2 - same order of density as
# Malam Fatori's 640 and Gajiram's 891, just a smaller town overall).
#
# NOTE: as of this draw, FACT's WRITTEN accessibility sheet still shows
# Mairari as Inaccessible (confirmed_by_partner_report, unchanged) - this
# draw proceeds on Jack's direct authorization (FACT's verbal/message
# confirmation), not on the sheet, which has not yet been reconciled to
# match. Flagged to Jack directly, not silently overridden.
#
# Target size differs from the other two: build_sampling_plan()'s own
# formula on N_hh=243 (building-count proxy) gives target_sample=78,
# clusters=13 - NOT the saturated 102/17 the larger two hit, because
# Mairari's real population base is genuinely smaller. This is a real
# result of the formula, not a manually reduced figure.
#
# Mechanism: identical to the other two - fresh fine hex grid over the
# DBSCAN-derived dense-cluster hull (no existing Stage 1 hex infrastructure
# touches this area either), PPS selection of clusters by building-count
# MOS, 6 target + 6 reserve real buildings drawn per cell, real per-building
# ward attribution via point-in-polygon. "_light" cluster-ID prefix,
# sampling_method = "MSNA Light" throughout.
#
# STAGING ONLY - does not touch the live FULL/WORKING frame.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr); library(stringr) })
set.seed(80010)  # NG008010 = Guzamala's adm2_pcode

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
mycrs <- 31028
STAGING_DIR <- "resampling/output/resample_runs/FACT/2026-09-11_mairari_urban"
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

TARGET_HH <- 6L
RESERVE_HH <- 6L
N_CLUSTERS <- 13L  # different from the other two - see header note
STRATA_ID <- "non_idp_NG008010"
LGA_NAME <- "Guzamala"
WARD_NAME <- "Mairari"

# ---- Stage A: buildings inside the Mairari ward boundary ----
w_ocha <- st_transform(st_read("input_data/boundaries/nga_admin_boundaries/nga_admin3_em.shp", quiet = TRUE), 4326)
ward_poly <- w_ocha[w_ocha$adm2_name == LGA_NAME & w_ocha$adm3_name == WARD_NAME, ]
stopifnot(nrow(ward_poly) == 1)
bbox_wkt <- st_as_text(st_as_sfc(st_bbox(ward_poly)))

gdb_dir <- "input_data/boundaries/nga_buildingfootprints"
gdb_files <- list.dirs(gdb_dir, recursive = FALSE, full.names = TRUE) |> str_subset("\\.gdb$")
all_b <- list()
for (gdb_path in gdb_files) {
  layers <- sf::st_layers(gdb_path)$name
  building_layer <- layers[str_detect(tolower(layers), "build")][1]
  if (is.na(building_layer)) building_layer <- layers[1]
  sample_row <- st_read(gdb_path, query = paste0('SELECT * FROM "', building_layer, '" LIMIT 1'), quiet = TRUE)
  confidence_field <- names(sample_row)[str_detect(names(sample_row), regex("confidence", ignore_case = TRUE))][1]
  b <- tryCatch(st_read(gdb_path, layer = building_layer, wkt_filter = bbox_wkt, quiet = TRUE), error = function(e) NULL)
  if (is.null(b) || nrow(b) == 0) next
  if (!is.na(confidence_field) && confidence_field %in% names(b)) b <- b[b[[confidence_field]] >= 0.75, ]
  all_b[[basename(gdb_path)]] <- st_transform(b, 4326)
}
buildings_full <- do.call(rbind, lapply(all_b, function(b) {
  b_min <- b["geometry"]
  b_min$centroid <- st_centroid(st_geometry(b))
  b_min
}))
buildings_full <- buildings_full[st_within(st_as_sf(data.frame(geometry = buildings_full$centroid), crs = 4326), ward_poly, sparse = FALSE)[,1], ]
cat(sprintf("Buildings inside %s ward: %d\n", WARD_NAME, nrow(buildings_full)))

# ---- Stage B: DBSCAN to isolate the dense settlement core within the ward ----
centroids <- st_as_sf(data.frame(geometry = buildings_full$centroid), crs = 4326)
centroids_m <- st_transform(centroids, mycrs)
coords <- st_coordinates(centroids_m)
db <- dbscan::dbscan(coords, eps = 150, minPts = 15)
buildings_full$cluster <- db$cluster
tab <- table(buildings_full$cluster[buildings_full$cluster != 0])
top_cluster_id <- as.integer(names(tab)[which.max(tab)])
urban_buildings <- buildings_full[buildings_full$cluster == top_cluster_id, ]
cat(sprintf("Settlement core buildings: %d\n", nrow(urban_buildings)))
stopifnot(nrow(urban_buildings) > 200, nrow(urban_buildings) < 300)  # sanity vs. earlier finding (243)

urban_hull <- st_convex_hull(st_union(st_geometry(centroids_m)[buildings_full$cluster == top_cluster_id]))

# ---- Stage C/D/E: direct spatial partition into exactly N_CLUSTERS groups ----
# Mairari's settlement (243 buildings) is too small and unevenly distributed
# for the hex-grid-then-PPS-select approach used for Malam Fatori/Gajiram -
# tried cellsizes giving 20-25 candidate cells, only 8-9 ever cleared the
# 12-building floor (not enough for 13 clusters). Switched to k-means
# (k=N_CLUSTERS) directly on the building coordinates: guarantees exactly
# 13 spatially-compact groups, each with a real, checked building count -
# no PPS "selection from a larger candidate pool" step needed here since
# every group becomes a cluster (nothing to discard), unlike the other two
# settlements where more candidate cells existed than clusters needed.
urban_buildings_m <- st_transform(st_as_sf(data.frame(geometry = urban_buildings$centroid), crs = 4326), mycrs)
urban_buildings_m$building_idx <- seq_len(nrow(urban_buildings_m))
coords_km <- st_coordinates(urban_buildings_m)
km <- kmeans(coords_km, centers = N_CLUSTERS, nstart = 25)
group_id <- km$cluster  # plain integer vector, reassigned directly below (not stored on the sf object until final)

# Raw k-means optimizes compactness, not equal group size - with 243
# buildings across 13 groups (avg 18.7) it left 2 groups under the 12
# floor (8 and 11) on the first run. Rebalance directly: repeatedly find
# the single most poorly-sized group, and reassign it its nearest
# not-yet-taken neighbour point from whichever other group currently has
# the most spare capacity (has more than TARGET_HH+RESERVE_HH), until
# every group clears the floor. Preserves spatial compactness as much as
# possible (always pulls the geometrically nearest available point) while
# guaranteeing every cluster is drawable.
min_size <- TARGET_HH + RESERVE_HH
repeat {
  sizes <- table(factor(group_id, levels = seq_len(N_CLUSTERS)))
  under <- which(sizes < min_size)
  if (length(under) == 0) break
  needy <- under[1]
  donor_candidates <- which(sizes > min_size)
  stopifnot(length(donor_candidates) > 0)  # 243 total vs 13*12=156 floor guarantees this is always true
  needy_centroid <- colMeans(coords_km[group_id == needy, , drop = FALSE])
  donor_pt_idx <- which(group_id %in% donor_candidates)
  dists <- sqrt((coords_km[donor_pt_idx, 1] - needy_centroid[1])^2 + (coords_km[donor_pt_idx, 2] - needy_centroid[2])^2)
  move_idx <- donor_pt_idx[which.min(dists)]
  group_id[move_idx] <- needy
}
urban_buildings_m$hex_id <- paste0("hex_", group_id)
b_hex <- urban_buildings_m
group_sizes <- b_hex |> st_drop_geometry() |> count(hex_id, name = "mos")
cat("k-means group sizes after rebalancing:\n"); print(group_sizes$mos)
stopifnot(all(group_sizes$mos >= TARGET_HH + RESERVE_HH))  # every group must support a full cluster

selected_hexes <- group_sizes
cat(sprintf("All %d k-means groups used as clusters, size range %d-%d\n", nrow(selected_hexes), min(selected_hexes$mos), max(selected_hexes$mos)))

# ---- Stage F: within each selected hex, draw 6 target + 6 reserve real buildings ----
new_households <- list()
for (i in seq_len(nrow(selected_hexes))) {
  hx <- selected_hexes$hex_id[i]
  cluster_id <- sprintf("%s_light%d", STRATA_ID, i)
  cand_idx <- b_hex$building_idx[!is.na(b_hex$hex_id) & b_hex$hex_id == hx]
  draw_idx <- sample(cand_idx, size = TARGET_HH + RESERVE_HH)
  draw_buildings <- urban_buildings[draw_idx, ]
  coords_ll <- st_coordinates(draw_buildings$centroid)
  status_vec <- c(rep("primary", TARGET_HH), rep("reserve", RESERVE_HH))
  hh_num <- c(sprintf("HH%02d", seq_len(TARGET_HH)), sprintf("R%02d", seq_len(RESERVE_HH)))
  pts_ll <- st_as_sf(data.frame(longitude = coords_ll[, "X"], latitude = coords_ll[, "Y"]),
                      coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  ward_names <- st_join(pts_ll, w_ocha[w_ocha$adm2_name == LGA_NAME, "adm3_name"], join = st_within)$adm3_name
  stopifnot(sum(is.na(ward_names)) == 0)
  df <- data.frame(
    survey_id = paste0(cluster_id, "_", hh_num),
    cluster_id = cluster_id,
    strata_id = STRATA_ID,
    status = status_vec,
    pop_type = "non_idp",
    region = "NE",
    adm1_pcode = "NG008", adm1_name = "Borno",
    adm2_pcode = "NG008010", adm2_name = LGA_NAME,
    adm3_name = ward_names,
    latitude = coords_ll[, "Y"], longitude = coords_ll[, "X"],
    households_in_cluster = length(cand_idx),
    target_households = TARGET_HH, reserve_households = RESERVE_HH,
    selection_type = "pps", certainty_stratum = FALSE,
    coverage_status = "covered", exclusion_reason = "none",
    ward_accessible_status = "Accessible",
    partners_covering = "FACT",
    sampling_method = "MSNA Light",
    location_source = "google_open_buildings_footprint_centroid",
    stringsAsFactors = FALSE
  )
  new_households[[i]] <- df
}
new_households_df <- bind_rows(new_households)

new_clusters_df <- selected_hexes |>
  mutate(cluster_id = sprintf("%s_light%d", STRATA_ID, seq_len(n())),
         strata_id = STRATA_ID, pop_type = "non_idp",
         target_households = TARGET_HH, reserve_households = RESERVE_HH,
         sampling_method = "MSNA Light") |>
  select(cluster_id, strata_id, pop_type, mos, target_households, reserve_households, sampling_method)

write_csv(new_households_df, file.path(STAGING_DIR, "new_households_urban.csv"))
write_csv(new_clusters_df, file.path(STAGING_DIR, "new_clusters_urban.csv"))

# Cluster geometry for the gpkg (Coverage Map input) - convex hull of each
# k-means group's buildings, since these groups have no pre-existing hex
# polygon the way the other two settlements' grid cells did.
cluster_hulls <- lapply(seq_len(nrow(selected_hexes)), function(i) {
  hx <- selected_hexes$hex_id[i]
  grp_pts <- b_hex[b_hex$hex_id == hx, ]
  # 25m buffer + union + convex hull: always yields a valid POLYGON (unlike
  # a bare convex hull of points, which degenerates to a POINT/LINESTRING
  # sfg when points are too few/collinear, and can't share a geometry
  # column with the POLYGON hulls from other groups).
  st_convex_hull(st_union(st_buffer(st_geometry(grp_pts), 25)))
})
cluster_hulls_sfc <- do.call(c, cluster_hulls)
st_crs(cluster_hulls_sfc) <- mycrs
cluster_hulls_sf <- st_sf(
  cluster_id = sprintf("%s_light%d", STRATA_ID, seq_len(nrow(selected_hexes))),
  mos = selected_hexes$mos,
  geometry = cluster_hulls_sfc
)
st_write(st_transform(cluster_hulls_sf, 4326), file.path(STAGING_DIR, "new_clusters_urban.gpkg"), delete_dsn = TRUE, quiet = TRUE)

cat(sprintf("\n==== DONE. %d clusters, %d household rows (%d target + %d reserve each). ====\n",
            N_CLUSTERS, nrow(new_households_df), TARGET_HH, RESERVE_HH))
cat("Staged in:", STAGING_DIR, "- NOT merged into the live WORKING/FULL frame.\n")
