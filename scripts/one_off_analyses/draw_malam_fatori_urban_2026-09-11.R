# ==============================================================================
# Draws the Malam Fatori (Abadam, Katsina... no, Borno) urban-core "MSNA
# Light" sample - Jack's negotiated arrangement with government enumerators
# (no georeferencing/verification possible, so this will never count toward
# state/regional/national aggregation or cross-LGA comparison - see CLAUDE.md
# for the full discussion). Explicitly scoped to ONLY the urban core (Jack's
# call: government collectors will realistically only go where the town
# actually is, not scattered rural points they'd ignore).
#
# Urban extent: derived algorithmically, not by hand-picking wards -
# DBSCAN (eps=150m, minPts=15) on real Google Open Buildings footprint
# centroids (confidence>=0.75, same threshold Stage 2 uses everywhere)
# across the whole Abadam LGA. The largest cluster (1,985 buildings, 3.1km2)
# spans Kessa'A/Busuna/Kudokurgo - matches Jack's own visual read of the
# dashboard's OSM basemap exactly, and its centroid lands within ~10m of
# two independent external gazetteers (mapcarta, savvytime) and a named OSM
# POI ("119TFBN malam fatori" camp_site). See scratchpad work this session.
#
# No existing Stage 1 hex infrastructure touches this area at all (checked
# directly - 0 of Abadam's existing 279 household rows / 29 clusters fall
# within the urban hull or even a 1km buffer of it - they're all in
# Arege/Banowa/Bogum/Doro/Foguwa/Gudumbali East/West, nowhere near Malam
# Fatori). So this builds a fresh, purpose-built fine hex grid over just
# the urban hull rather than filtering/reusing the LGA's existing 91 hexes
# (which are ~15-20km2 each - too coarse; the whole urban area would be one
# hex, not 17 distinct clusters).
#
# Target size: build_sampling_plan()'s own formula (Z=qnorm(0.95), p=0.5,
# e=0.10, m=6, ICC=0.06, buffer=0.10), same as everywhere else in this
# design. Using building count (1,985) as the N_hh proxy (no WorldPop
# household estimate scoped this precisely) - result saturates at
# target_sample=102 / 17 clusters across a wide range of plausible true N_hh
# (800-2,900), so the exact population figure barely matters here, same
# saturation pattern already seen for Mobbar/Dandume/Matazu at this scale.
#
# Mechanism, built fresh but reusing this project's established conventions
# rather than inventing new ones: PPS selection of 17 hex cells by
# building-count MOS (same logic as Stage 1's own hex-level PPS), then a
# simple random draw of 6 target + 6 reserve real buildings within each
# selected hex (same target/reserve structure as every other non-IDP
# cluster nationally). Cluster IDs use a distinct "_light" prefix (not
# "_supp") specifically so these are never mistaken for a normal verified
# supplementary draw at a glance.
#
# Output tagged sampling_method = "MSNA Light" throughout (the column
# add_sampling_method_column_2026-09-11.R added). STAGING ONLY - does not
# touch the live FULL/WORKING frame; a separate, explicit merge step (after
# Jack's review) does that.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr); library(stringr) })
set.seed(80011)  # NG008001 = Abadam's adm2_pcode, fixed seed for reproducibility

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
mycrs <- 31028
STAGING_DIR <- "resampling/output/resample_runs/FACT/2026-09-11_malam_fatori_urban"
dir.create(STAGING_DIR, recursive = TRUE, showWarnings = FALSE)

TARGET_HH <- 6L
RESERVE_HH <- 6L
N_CLUSTERS <- 17L
STRATA_ID <- "non_idp_NG008001"

# ---- Stage A: rebuild the urban building set (same DBSCAN cluster as before) ----
w_ocha <- st_transform(st_read("input_data/boundaries/nga_admin_boundaries/nga_admin3_em.shp", quiet = TRUE), 4326)
abadam_all <- w_ocha[w_ocha$adm2_name == "Abadam", ]
bbox_wkt <- st_as_text(st_as_sfc(st_bbox(abadam_all)))

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
# Keep full building geometry (not just centroid) - we need real footprints for lat/lon + building_id
buildings_full <- do.call(rbind, lapply(all_b, function(b) {
  b_min <- b["geometry"]
  b_min$centroid <- st_centroid(st_geometry(b))
  b_min
}))
buildings_full <- buildings_full[st_within(st_as_sf(data.frame(geometry = buildings_full$centroid), crs = 4326), st_union(abadam_all), sparse = FALSE)[,1], ]

centroids <- st_as_sf(data.frame(geometry = buildings_full$centroid), crs = 4326)
centroids_m <- st_transform(centroids, mycrs)
coords <- st_coordinates(centroids_m)
db <- dbscan::dbscan(coords, eps = 150, minPts = 15)
buildings_full$cluster <- db$cluster
tab <- table(buildings_full$cluster[buildings_full$cluster != 0])
top_cluster_id <- as.integer(names(tab)[which.max(tab)])
urban_buildings <- buildings_full[buildings_full$cluster == top_cluster_id, ]
cat(sprintf("Urban core buildings: %d\n", nrow(urban_buildings)))
stopifnot(nrow(urban_buildings) > 1500, nrow(urban_buildings) < 2500)  # sanity check vs. earlier finding

urban_hull <- st_convex_hull(st_union(st_geometry(centroids_m)[buildings_full$cluster == top_cluster_id]))

# ---- Stage B: fine hex grid over the urban hull ----
# Target ~25-30 candidate cells so PPS has real cells to choose among for 17
# clusters (not just exactly 17, which would make "selection" meaningless).
hull_area_m2 <- as.numeric(st_area(urban_hull))
target_n_cells <- 28
cellsize <- sqrt(hull_area_m2 / target_n_cells / (3 * sqrt(3) / 2)) * 2  # hex width approx
hex_grid <- st_make_grid(st_buffer(urban_hull, 100), cellsize = cellsize, square = FALSE) |> st_as_sf()
hex_grid <- hex_grid[st_intersects(hex_grid, urban_hull, sparse = FALSE)[,1], ]
hex_grid$hex_id <- paste0("hex_", seq_len(nrow(hex_grid)))
cat(sprintf("Fine hex grid: %d cells (cellsize=%.0fm)\n", nrow(hex_grid), cellsize))

# ---- Stage C: assign buildings to hex cells, compute MOS ----
urban_buildings_m <- st_transform(st_as_sf(data.frame(geometry = urban_buildings$centroid), crs = 4326), mycrs)
urban_buildings_m$building_idx <- seq_len(nrow(urban_buildings_m))
b_hex <- st_join(urban_buildings_m, hex_grid["hex_id"], join = st_within)
hex_mos <- b_hex |> st_drop_geometry() |> filter(!is.na(hex_id)) |> count(hex_id, name = "mos")
hex_grid <- hex_grid |> left_join(hex_mos, by = "hex_id") |> mutate(mos = coalesce(mos, 0))
eligible_hexes <- hex_grid |> filter(mos >= TARGET_HH + RESERVE_HH)
cat(sprintf("Hex cells with >=%d buildings (eligible to host a full cluster): %d\n", TARGET_HH + RESERVE_HH, nrow(eligible_hexes)))
stopifnot(nrow(eligible_hexes) >= N_CLUSTERS)

# ---- Stage D: PPS selection of 17 clusters by building-count MOS ----
selected_idx <- sample(seq_len(nrow(eligible_hexes)), size = N_CLUSTERS, prob = eligible_hexes$mos)
selected_hexes <- eligible_hexes[selected_idx, ]
cat(sprintf("Selected %d hex clusters, MOS range %d-%d\n", nrow(selected_hexes), min(selected_hexes$mos), max(selected_hexes$mos)))

# ---- Stage E: within each selected hex, draw 6 target + 6 reserve real buildings ----
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
  # Real per-building ward attribution (point-in-polygon against the official
  # OCHA Abadam ward boundaries), NOT a composite placeholder string - a
  # single hex can (and here, does) straddle more than one ward, same as
  # everywhere else in this project's Stage 2 methodology. Caught and fixed
  # 2026-09-11: an earlier draft wrote one fixed "Kessa'A/Busuna/Kudokurgo
  # (...)" string for every row, which would have silently broken every
  # downstream (adm1_name, adm2_name, adm3_name) ward lookup (stamp_ward_
  # accessible_status.py, classify_households(), etc. - none of them would
  # ever match a real master ward CSV entry against that composite string).
  pts_ll <- st_as_sf(data.frame(longitude = coords_ll[, "X"], latitude = coords_ll[, "Y"]),
                      coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  ward_names <- st_join(pts_ll, abadam_all["adm3_name"], join = st_within)$adm3_name
  stopifnot(sum(is.na(ward_names)) == 0)
  df <- data.frame(
    survey_id = paste0(cluster_id, "_", hh_num),
    cluster_id = cluster_id,
    strata_id = STRATA_ID,
    status = status_vec,
    pop_type = "non_idp",
    region = "NE",
    adm1_pcode = "NG008", adm1_name = "Borno",
    adm2_pcode = "NG008001", adm2_name = "Abadam",
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
