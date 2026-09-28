# ==============================================================================
# Re-run of verify_monguno_ward_attribution_2026-09-28.R, from scratch,
# after the Coordinator reported 261 NA wardname values (exactly the
# non-IDP count) in the first run's output - a claim I could not reproduce
# on direct inspection of that file (zero NAs found, checked both empty-
# string and literal "NA" string, raw file bytes confirmed real values on
# every non-IDP row). Rebuilding independently, minimal columns only
# (avoids any risk of a status.x/status.y-style join collision confusing
# either of us), split output by pop_type explicitly so there is no room
# for ambiguity about which rows are which.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
sf::sf_use_s2(TRUE)

OUT <- "resampling/output/monguno_ward_attribution_check_2026-09-28"

wards <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>%
  st_transform(4326) %>%
  select(true_wardname = wardname, true_lganame = lganame)  # minimal, renamed to avoid ANY collision

working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)
mong <- working %>%
  filter(adm3_name == "Monguno") %>%
  select(survey_id, cluster_id, pop_type, adm3_name, admin3_cod_name, latitude, longitude)

cat("Input rows:", nrow(mong), "| by pop_type:\n"); print(table(mong$pop_type))
cat("NA latitude:", sum(is.na(mong$latitude)), "| NA longitude:", sum(is.na(mong$longitude)), "\n")
cat("By pop_type, NA lat/lon:\n")
print(mong %>% group_by(pop_type) %>% summarise(n = n(), na_lat = sum(is.na(latitude)), na_lon = sum(is.na(longitude))))

pts <- mong %>% st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
joined <- st_join(pts, wards, join = st_within) %>% st_drop_geometry()

cat("\n==== RESULT, by pop_type ====\n")
for (pt in unique(joined$pop_type)) {
  sub <- joined %>% filter(pop_type == pt)
  na_n <- sum(is.na(sub$true_wardname))
  cat(sprintf("%s: %d rows, %d with NA true_wardname (join failed), true_wardname values: %s\n",
              pt, nrow(sub), na_n, paste(names(table(sub$true_wardname, useNA = "ifany")), collapse = "; ")))
}

write_csv(joined, file.path(OUT, "monguno_points_spatial_join_result_v2_clean.csv"))
cat("\nWrote", file.path(OUT, "monguno_points_spatial_join_result_v2_clean.csv"), "\n")

agree_adm3 <- sum(joined$adm3_name == joined$true_wardname, na.rm = TRUE)
agree_cod <- sum(joined$admin3_cod_name == joined$true_wardname, na.rm = TRUE)
cat(sprintf("\nTOTAL: adm3_name matches true geometry: %d/%d | admin3_cod_name matches: %d/%d | NA (join failed): %d\n",
            agree_adm3, nrow(joined), agree_cod, nrow(joined), sum(is.na(joined$true_wardname))))
