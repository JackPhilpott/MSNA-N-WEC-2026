# ==============================================================================
# Draws the Gajiram (Nganzai, Borno) "MSNA Light" sample - second of the 3
# government-negotiated LGAs (Abadam/Malam Fatori done first, see draw_malam_
# fatori_urban_2026-09-11.R for the full context/rationale). Same negotiated
# arrangement: government enumerators, no georeferencing/verification, never
# counted in state/regional/national aggregation - disclosed LGA-level
# findings only.
#
# Gajiram is FACT's one-confirmed-accessible ward for Nganzai (master_
# accessibility_status_ward_level.csv, confirmed_by_partner_report, "N/A -
# fully accessible", no contradictory note - clean, unlike Guzamala's
# GRID3/OCHA ward-name mismatch). Unlike Malam Fatori, the dense settlement
# here does NOT straddle a ward boundary - checked directly, the DBSCAN
# urban cluster only touches Gajiram, nothing else - so no multi-ward
# complexity to handle.
#
# Scale check against Malam Fatori (both via the same DBSCAN eps=150m/
# minPts=15 methodology, for a fair comparison): Gajiram's dense core is
# actually LARGER and denser - 3,199 buildings / 3.6km2 (891/km2) vs Malam
# Fatori's 1,985 buildings / 3.1km2 (640/km2). Same saturated target_sample
# result either way (102hh/17 clusters, build_sampling_plan()'s own formula).
#
# Mechanism: identical to draw_malam_fatori_urban_2026-09-11.R - fresh fine
# hex grid over the dense-cluster hull (no existing Stage 1 hex infra
# touches this specific dense patch either), PPS selection of 17 cells by
# building-count MOS, 6 target + 6 reserve real buildings drawn per cell,
# real per-building ward attribution via point-in-polygon (not needed here
# since it's single-ward, but done anyway for consistency/robustness).
# Cluster IDs use "_light" prefix, tagged sampling_method = "MSNA Light".
#
# STAGING ONLY - does not touch the live FULL/WORKING frame.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr); library(stringr) })
set.seed(80026)  # NG008026 = Nganzai's adm2_pcode

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
mycrs <- 31028
STAGING_DIR <- "resampling/output/resample_runs/FACT/2026-09-11_gajiram_urban"
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

TARGET_HH <- 6L
RESERVE_HH <- 6L
N_CLUSTERS <- 17L
STRATA_ID <- "non_idp_NG008026"
LGA_NAME <- "Nganzai"
WARD_NAME <- "Gajiram"

# ---- Stage A: buildings inside the Gajiram ward boundary ----
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

# ---- Stage B: DBSCAN to isolate the dense urban core within the ward ----
centroids <- st_as_sf(data.frame(geometry = buildings_full$centroid), crs = 4326)
centroids_m <- st_transform(centroids, mycrs)
coords <- st_coordinates(centroids_m)
db <- dbscan::dbscan(coords, eps = 150, minPts = 15)
buildings_full$cluster <- db$cluster
tab <- table(buildings_full$cluster[buildings_full$cluster != 0])
top_cluster_id <- as.integer(names(tab)[which.max(tab)])
urban_buildings <- buildings_full[buildings_full$cluster == top_cluster_id, ]
cat(sprintf("Urban core buildings: %d\n", nrow(urban_buildings)))
stopifnot(nrow(urban_buildings) > 3000, nrow(urban_buildings) < 3500)  # sanity vs. earlier finding (3,199)

urban_hull <- st_convex_hull(st_union(st_geometry(centroids_m)[buildings_full$cluster == top_cluster_id]))

# ---- Stage C: fine hex grid over the urban hull ----
hull_area_m2 <- as.numeric(st_area(urban_hull))
target_n_cells <- 28
cellsize <- sqrt(hull_area_m2 / target_n_cells / (3 * sqrt(3) / 2)) * 2
hex_grid <- st_make_grid(st_buffer(urban_hull, 100), cellsize = cellsize, square = FALSE) |> st_as_sf()
hex_grid <- hex_grid[st_intersects(hex_grid, urban_hull, sparse = FALSE)[,1], ]
hex_grid$hex_id <- paste0("hex_", seq_len(nrow(hex_grid)))
cat(sprintf("Fine hex grid: %d cells (cellsize=%.0fm)\n", nrow(hex_grid), cellsize))

# ---- Stage D: assign buildings to hex cells, compute MOS ----
urban_buildings_m <- st_transform(st_as_sf(data.frame(geometry = urban_buildings$centroid), crs = 4326), mycrs)
urban_buildings_m$building_idx <- seq_len(nrow(urban_buildings_m))
b_hex <- st_join(urban_buildings_m, hex_grid["hex_id"], join = st_within)
hex_mos <- b_hex |> st_drop_geometry() |> filter(!is.na(hex_id)) |> count(hex_id, name = "mos")
hex_grid <- hex_grid |> left_join(hex_mos, by = "hex_id") |> mutate(mos = coalesce(mos, 0))
eligible_hexes <- hex_grid |> filter(mos >= TARGET_HH + RESERVE_HH)
cat(sprintf("Hex cells with >=%d buildings: %d\n", TARGET_HH + RESERVE_HH, nrow(eligible_hexes)))
stopifnot(nrow(eligible_hexes) >= N_CLUSTERS)

# ---- Stage E: PPS selection of 17 clusters by building-count MOS ----
selected_idx <- sample(seq_len(nrow(eligible_hexes)), size = N_CLUSTERS, prob = eligible_hexes$mos)
selected_hexes <- eligible_hexes[selected_idx, ]
cat(sprintf("Selected %d hex clusters, MOS range %d-%d\n", nrow(selected_hexes), min(selected_hexes$mos), max(selected_hexes$mos)))

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
    adm2_pcode = "NG008026", adm2_name = LGA_NAME,
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

new_clusters_df <- selected_hexes |> st_drop_geometry() |>
  mutate(cluster_id = sprintf("%s_light%d", STRATA_ID, seq_len(n())),
         strata_id = STRATA_ID, pop_type = "non_idp",
         target_households = TARGET_HH, reserve_households = RESERVE_HH,
         sampling_method = "MSNA Light") |>
  select(cluster_id, strata_id, pop_type, mos, target_households, reserve_households, sampling_method)

write_csv(new_households_df, file.path(STAGING_DIR, "new_households_urban.csv"))
write_csv(new_clusters_df, file.path(STAGING_DIR, "new_clusters_urban.csv"))
st_write(selected_hexes, file.path(STAGING_DIR, "new_clusters_urban.gpkg"), delete_dsn = TRUE, quiet = TRUE)

cat(sprintf("\n==== DONE. %d clusters, %d household rows (%d target + %d reserve each). ====\n",
            N_CLUSTERS, nrow(new_households_df), TARGET_HH, RESERVE_HH))
cat("Staged in:", STAGING_DIR, "- NOT merged into the live WORKING/FULL frame.\n")
