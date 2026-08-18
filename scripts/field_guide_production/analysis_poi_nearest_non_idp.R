# Nearest curated point-of-interest per Non-IDP cluster (2026-08-12) - feeds
# the "GPS POINT OFFSET" style nearest-landmark line in the field guide
# (build_cluster_factsheets.py's location_block(), 5km cutoff) and was also
# used to find the densest-POI cluster for the map-overlap stress test
# (non_idp_NG036013_15, Nguru). Curated category list = output/
# poi_category_review.csv's suggested_action == "include" (53 of 402 raw
# HOTOSM tag values, user-approved 2026-08-12) - same filter
# build_cluster_map_examples.R's POI layer uses, kept in sync by hand since
# this is a one-off analysis script, not shared code.
suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

mycrs <- 31028

review <- read_csv("output/poi_category_review.csv", show_col_types = FALSE) %>%
  filter(suggested_action == "include")
include_by_field <- split(review$value, review$field)

poi_dir <- "input_data/boundaries/hotosm_nga_points_of_interest_osm_shp"
pts <- st_read(file.path(poi_dir, "points_of_interest_points.shp"), quiet = TRUE)
polys <- st_read(file.path(poi_dir, "points_of_interest_polygons.shp"), quiet = TRUE)

title_case <- function(s) {
  s <- gsub("_", " ", s)
  gsub("(^|\\s)([a-z])", "\\1\\U\\2", s, perl = TRUE)
}

filter_include <- function(df) {
  keep <- rep(FALSE, nrow(df))
  poi_type <- rep(NA_character_, nrow(df))
  for (fld in names(include_by_field)) {
    if (fld %in% names(df)) {
      m <- df[[fld]] %in% include_by_field[[fld]]
      keep <- keep | m
      poi_type[m] <- df[[fld]][m]
    }
  }
  df$poi_type <- poi_type
  df[keep, ]
}

pts_f <- filter_include(st_drop_geometry(pts) %>% mutate(.rn = row_number()))
pts_sf <- pts[pts_f$.rn, ] %>%
  mutate(poi_type = pts_f$poi_type, has_name = !is.na(name) & name != "",
         poi_name = ifelse(has_name, name, title_case(poi_type))) %>%
  select(poi_name, poi_type, has_name)

polys_f <- filter_include(st_drop_geometry(polys) %>% mutate(.rn = row_number()))
polys_sf <- polys[polys_f$.rn, ] %>%
  mutate(poi_type = polys_f$poi_type, has_name = !is.na(name) & name != "",
         poi_name = ifelse(has_name, name, title_case(poi_type))) %>%
  select(poi_name, poi_type, has_name) %>% st_centroid()

poi_all <- bind_rows(st_transform(pts_sf, 4326), st_transform(polys_sf, 4326))
cat("Curated POI count:", nrow(poi_all), "\n")
poi_m <- st_transform(poi_all, mycrs)

frame <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv", show_col_types = FALSE) %>%
  filter(pop_type == "non_idp", status == "primary") %>% distinct(cluster_id, .keep_all = TRUE) %>%
  select(cluster_id, adm2_name, adm1_name, latitude, longitude)

anchors <- st_as_sf(frame, coords = c("longitude", "latitude"), crs = 4326) %>% st_transform(mycrs)

nearest_idx <- st_nearest_feature(anchors, poi_m)
nearest_dist <- as.numeric(st_distance(anchors, poi_m[nearest_idx, ], by_element = TRUE))
frame$nearest_poi_name <- poi_m$poi_name[nearest_idx]
frame$nearest_poi_type <- poi_m$poi_type[nearest_idx]
frame$nearest_poi_has_name <- poi_m$has_name[nearest_idx]
frame$nearest_poi_dist_m <- round(nearest_dist, 1)

buf500 <- st_buffer(anchors, 500)
frame$poi_within_500m <- lengths(st_intersects(buf500, poi_m))

frame_sorted <- frame %>% arrange(desc(poi_within_500m))
cat("\nTop 10 densest Non-IDP clusters by POI count within 500m:\n")
print(frame_sorted %>% select(cluster_id, adm2_name, adm1_name, poi_within_500m, nearest_poi_dist_m) %>% head(10))

cat("\n% of clusters with a curated POI within 5km:", round(mean(frame$nearest_poi_dist_m <= 5000)*100, 1), "\n")
cat("Median nearest POI distance (m):", median(frame$nearest_poi_dist_m), "\n")

out_dir <- "output/data/supporting_analysis/poi"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(frame, file.path(out_dir, "poi_nearest_non_idp.csv"), row.names = FALSE)
cat("\nWritten:", file.path(out_dir, "poi_nearest_non_idp.csv"), "\n")
