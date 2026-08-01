# ==============================================================================
# GIS colleague training pack - one example cluster per Stage 2 field
# scenario, for a practical run-through (2026-07-31 request). Reuses the
# same vetted example sites already used in the methodology maps, so the
# training matches what colleagues will have already seen:
#   - Non-IDP: non_idp_NG023010_1 (Kabba/Bunu, Kogi) - Figure 4's own example
#   - IDP in-camp: idp_NG008011_8, Reception/Transit Camp (Gwoza, Borno)
#   - IDP host-community, small pop: idp_NG021005_2, Rugar Tsara (Bindawa, Katsina - 49hh)
#   - IDP host-community, large pop: idp_NG008021_5, Ngarannam (Maiduguri, Borno - 3,239hh)
#
# Two shapefiles (points can't share a layer with polygons in ESRI format):
#   - training_example_points.shp - one row per reference GPS point
#     (cluster/DTM/backup locations), all 4 scenarios
#   - training_example_hexagons.shp - the real Stage 1 hexagon boundaries
#     for the Non-IDP and IDP-camp scenarios (host-community sites have no
#     hexagon-shaped field boundary by design, so nothing to show there)
#
# Standalone, not part of the numbered 00-08 pipeline. Sources the main
# pipeline up to `selected_clusters` (~line 1236) for the real hexagon
# geometries.
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(here)
})

output_dir <- here::here("output")
out_dir    <- here::here(output_dir, "gis", "training_examples")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl(
  "^selected_clusters <- dplyr::bind_rows\\(non_idp_clusters, idp_clusters\\)",
  lines
))
stopifnot(length(stop_idx) == 1)
writeLines(lines[1:stop_idx], "temp_stage1_training.R")
source("temp_stage1_training.R")
file.remove("temp_stage1_training.R")

# ---------------------------------------------------------------------------
# Points
# ---------------------------------------------------------------------------
non_idp_hh <- read_csv(here::here("_archive", "2026-07-23_design_frame_pre_coverage", "stage2_sampling_frame.csv"), show_col_types = FALSE) %>%
  filter(cluster_id == "non_idp_NG023010_1", status == "primary") %>%
  slice(1)

camp <- read_csv(here::here(output_dir, "data", "data_collection", "idp_camp_backup_points.csv"), show_col_types = FALSE) %>%
  filter(site_id == "idp_NG008011_8")

host <- read_csv(here::here(output_dir, "data", "supporting_analysis", "idp_host_feasibility", "idp_host_community_feasibility_flags.csv"), show_col_types = FALSE)
host_small <- host %>% filter(cluster_id == "idp_NG021005_2")
host_large <- host %>% filter(cluster_id == "idp_NG008021_5")

stopifnot(nrow(non_idp_hh) == 1, nrow(camp) == 1, nrow(host_small) == 1, nrow(host_large) == 1)

pts <- tibble::tribble(
  ~scenario,      ~pt_type,  ~site_name,                  ~lga,            ~state,   ~region, ~pop_val, ~lon, ~lat,
  "1_non_idp",    "cluster", "Example Non-IDP cluster",   non_idp_hh$adm2_name, non_idp_hh$adm1_name, non_idp_hh$region, as.numeric(non_idp_hh$households_in_cluster), as.numeric(non_idp_hh$longitude), as.numeric(non_idp_hh$latitude),
  "2_idp_camp",   "dtm",     camp$iom_site_name,          camp$adm2_name,  camp$adm1_name, camp$region, as.numeric(camp$households_in_cluster), as.numeric(camp$dtm_gps_lon), as.numeric(camp$dtm_gps_lat),
  "2_idp_camp",   "backup",  camp$iom_site_name,          camp$adm2_name,  camp$adm1_name, camp$region, as.numeric(camp$households_in_cluster), as.numeric(camp$backup_gps_lon), as.numeric(camp$backup_gps_lat),
  "3_idp_host_sm","dtm",     host_small$iom_site_name,    host_small$adm2_name, host_small$adm1_name, host_small$region, as.numeric(host_small$caseload_hh), as.numeric(host_small$longitude), as.numeric(host_small$latitude),
  "4_idp_host_lg","dtm",     host_large$iom_site_name,    host_large$adm2_name, host_large$adm1_name, host_large$region, as.numeric(host_large$caseload_hh), as.numeric(host_large$longitude), as.numeric(host_large$latitude)
)

pts <- pts %>%
  mutate(notes = case_when(
    scenario == "1_non_idp" ~ "Household selected from building-footprint pool within the hexagon - no DTM point, no fixed anchor. See training_example_hexagons.shp for the cluster boundary.",
    scenario == "2_idp_camp" & pt_type == "dtm" ~ "Tier 1 (default): full household listing from this DTM point, bounded by visible camp extent.",
    scenario == "2_idp_camp" & pt_type == "backup" ~ "Tier 2 fallback ONLY (used if on-arrival listing isn't feasible): random walk starting here instead.",
    scenario == "3_idp_host_sm" ~ "Small host-community caseload (49hh). Chief/head-of-settlement listing, bounded by local social recognition - no GPS radius. Isolated settlement, edge usually visible in imagery.",
    scenario == "4_idp_host_lg" ~ "Large host-community caseload (3,239hh) embedded in dense urban Maiduguri fabric. Same listing method as any host site - no boundary visible in imagery; a good example of why the method can't rely on a fixed radius."
  ))

pts_sf <- st_as_sf(pts, coords = c("lon", "lat"), crs = 4326)

st_write(pts_sf, here::here(out_dir, "training_example_points.shp"), delete_layer = TRUE, quiet = TRUE)
message("Wrote training_example_points.shp (", nrow(pts_sf), " points)")

# ---------------------------------------------------------------------------
# Hexagons (real Stage 1 PSU boundaries - Non-IDP and IDP-camp only)
# ---------------------------------------------------------------------------
hex_non_idp <- selected_clusters %>%
  filter(cluster_id == "non_idp_NG023010_1") %>%
  distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  slice(1) %>%
  transmute(scenario = "1_non_idp", site_name = "Example Non-IDP cluster hexagon", cluster_id = cluster_id)

hex_camp <- selected_clusters %>%
  filter(cluster_id == "idp_NG008011_8") %>%
  distinct(uuid_hex_pop, .keep_all = TRUE) %>%
  slice(1) %>%
  transmute(scenario = "2_idp_camp", site_name = "Reception/Transit Camp hexagon (Gwoza)", cluster_id = cluster_id)

hexes_sf <- bind_rows(hex_non_idp, hex_camp) %>% st_transform(4326)

st_write(hexes_sf, here::here(out_dir, "training_example_hexagons.shp"), delete_layer = TRUE, quiet = TRUE)
message("Wrote training_example_hexagons.shp (", nrow(hexes_sf), " polygons)")

cat("\n=== TRAINING SHAPEFILES COMPLETE ===\n")
print(st_drop_geometry(pts_sf))
