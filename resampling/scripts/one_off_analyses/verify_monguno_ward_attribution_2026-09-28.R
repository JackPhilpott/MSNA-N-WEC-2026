# ==============================================================================
# URGENT (Jack flagged directly, safety angle - Kumalia is insecurity-
# excluded): definitive geometric check of the 518 WORKING rows currently
# carrying adm3_name="Monguno" (all admin3_source=GRID3), which disagree with
# their own admin3_cod_name field (splits into Monguno 107 / Kumalia 409 /
# Kaguram 2). Real lat/lon point-in-polygon against the actual GRID3 ward
# boundary shapefile - not a lossy/reduced layer, not documentation, not
# inference from field names. Whichever field the geometry agrees with is
# authoritative. Read-only, writes only to its own output folder.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
sf::sf_use_s2(TRUE)

OUT <- "resampling/output/monguno_ward_attribution_check_2026-09-28"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("Loading GRID3 ward boundary shapefile...\n")
wards <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE)
cat("  ", nrow(wards), "ward polygons loaded. Columns:", paste(names(wards), collapse=", "), "\n")

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
mong <- working %>% filter(adm3_name == "Monguno")
cat("\n", nrow(mong), "WORKING rows with adm3_name == 'Monguno'\n", sep = "")
cat("admin3_cod_name breakdown:\n"); print(table(mong$admin3_cod_name))

# Real point-in-polygon spatial join - every row, not just a sample, since we have real lat/lon for all 518
pts <- mong %>%
  filter(!is.na(latitude), !is.na(longitude)) %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
cat("\n", nrow(pts), "of", nrow(mong), "rows have usable lat/lon for the spatial join\n", sep = "")

wards_ll <- st_transform(wards, 4326)
joined <- st_join(pts, wards_ll, join = st_within)

# Find the ward-name column in the shapefile (GRID3 naming varies - print candidates)
name_cols <- names(wards_ll)[grepl("ward|name|WARD|NAME", names(wards_ll))]
cat("\nCandidate ward-name columns in the shapefile:", paste(name_cols, collapse = ", "), "\n")
print(st_drop_geometry(wards_ll[1, name_cols]))

write_csv(st_drop_geometry(joined), file.path(OUT, "monguno_points_spatial_join_result.csv"))
cat("\nWrote full result to", file.path(OUT, "monguno_points_spatial_join_result.csv"), "\n")
cat("\n==== DONE - inspect the ward-name column(s) above manually to confirm which frame field the true geometry agrees with. ====\n")
