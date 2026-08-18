# ==============================================================================
# One-time preprocessing of the national HOTOSM roads export (500MB+ .shp /
# 3.4GB .dbf, ~6.9M+ features, NO spatial index) into a small, indexed
# GeoPackage clipped to the 14 assessment states. The raw file is unusable
# for per-cluster queries directly - a single tiny bbox test query against
# it took 42 minutes for 1 row (confirmed empirically 2026-08-10), because
# GDAL's shapefile driver has to linearly scan the whole file with no
# spatial index (.qix/.sbn) to accelerate it. This is a ONE-TIME cost;
# every per-cluster query afterward reads from the much smaller, properly
# indexed output instead.
# ==============================================================================
suppressMessages({library(sf); library(dplyr); library(here)})

RAW_ROADS <- here::here("input_data", "boundaries", "nga_roads_hotosm", "roads_lines.shp")
OUT_GPKG <- here::here("input_data", "boundaries", "nga_roads_hotosm", "roads_assessment_states.gpkg")

ASSESSMENT_STATES <- c("Adamawa", "Borno", "Yobe", "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto",
                        "Zamfara", "Benue", "Kogi", "Nasarawa", "Niger", "Plateau")

# Deterministic pipeline prefix, just for NGA_shapes_all_cleaned (admin1 boundaries)
lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_roads.R")
source("temp_boundaries_roads.R")
file.remove("temp_boundaries_roads.R")

admin1 <- NGA_shapes_all_cleaned$nga_admin1 %>% filter(adm1_name %in% ASSESSMENT_STATES)
stopifnot(nrow(admin1) == 14)
bbox <- st_bbox(st_transform(admin1, 4326))
cat("Clip bbox (WGS84):\n"); print(bbox)

t0 <- Sys.time()
sf::gdal_utils(
  "vectortranslate",
  source = RAW_ROADS,
  destination = OUT_GPKG,
  options = c(
    "-spat", as.character(bbox["xmin"]), as.character(bbox["ymin"]),
              as.character(bbox["xmax"]), as.character(bbox["ymax"]),
    "-select", "id,name,highway,surface,bridge,adm1_name,adm2_name",
    "-nln", "roads",
    "-f", "GPKG"
  )
)
cat("Clip+convert elapsed:", round(as.numeric(Sys.time() - t0, units = "mins"), 1), "minutes\n")

# Verify + build/confirm spatial index (GPKG auto-indexes, but double-check)
roads <- st_read(OUT_GPKG, quiet = TRUE)
cat("Rows in clipped output:", nrow(roads), "\n")
cat("Highway type breakdown:\n")
print(table(roads$highway, useNA = "ifany"))
