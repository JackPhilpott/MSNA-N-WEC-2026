# ==============================================================================
# IDP in-camp backup GPS point generation - PART 4: two new in-camp clusters
# introduced by the 2026-08-06 targeted 24-LGA resample (NW Niger-border
# buffer reduced 20km->5km), which weren't in the original 81-site national
# list Part 1-3 were built from.
#
# Context: the targeted resample (see CLAUDE.md "Revision 2026-08-06") drew
# a fresh Stage 1/2 sample for 24 NW LGAs only, producing 4 in-camp IDP
# clusters. Two (idp_NG034006_3 "Zangon Jema", idp_NG037014_8 "Arabic Camp
# Zurmi") are confirmed the SAME physical site as before the resample (same
# iom_site_id/name/coordinates) - their existing backup points are still
# valid, untouched here. The other two are genuinely new sites, selected
# only because the buffer shrink made them accessible for the first time:
#   - idp_NG034013_1, Tsamaye Primary School (Sabon Birni, Sokoto), 267 hh
#   - idp_NG034013_2, Unguwar Lalle Primary School (Sabon Birni, Sokoto), 781 hh
# Neither exceeds the original >2,000hh flagged-camp threshold, so both get
# the same fixed-radius-buffer fallback method Part 3 used to extend
# coverage to every standard-size camp (300m radius, uniform over the
# circle's area) - not manual imagery delineation.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
})

set.seed(4206)  # fresh, independent addition - not part of Part 3's original batch/stream

mycrs <- 31028
deliverable_dir <- here("output", "data", "data_collection")
path <- here(deliverable_dir, "idp_camp_backup_points.csv")

FALLBACK_RADIUS_M <- 300  # identical to Part 2/Part 3's fallback radius

new_sites <- tibble::tribble(
  ~site_id,          ~iom_site_id, ~iom_site_name,                  ~iom_site_type, ~iom_site_ward, ~region, ~adm1_name, ~adm2_name,    ~households_in_cluster, ~dtm_gps_lat,       ~dtm_gps_lon,
  "idp_NG034013_1",  "SO_S032",    "Tsamaye Primary School",        "Camp",         NA_character_,  "NW",    "Sokoto",   "Sabon Birni", 267,                     13.514980010327392, 5.9869599710097425,
  "idp_NG034013_2",  "SO_S037",    "Unguwar Lalle Primary School",  "Camp",         NA_character_,  "NW",    "Sokoto",   "Sabon Birni", 781,                     13.585490010488753, 6.109719970910671
)

pts_wgs84 <- st_as_sf(new_sites, coords = c("dtm_gps_lon", "dtm_gps_lat"), crs = 4326, remove = FALSE)
pts_proj <- st_transform(pts_wgs84, mycrs)
coords <- st_coordinates(pts_proj)

n <- nrow(new_sites)
theta <- runif(n, 0, 2 * pi)
u <- runif(n)
r <- FALLBACK_RADIUS_M * sqrt(u)

backup_x <- coords[, 1] + r * cos(theta)
backup_y <- coords[, 2] + r * sin(theta)

backup_wgs84 <- st_as_sf(data.frame(backup_x, backup_y), coords = c("backup_x", "backup_y"), crs = mycrs) %>%
  st_transform(4326)
backup_coords <- st_coordinates(backup_wgs84)

new_rows <- new_sites %>%
  mutate(
    flagged_camp = FALSE,
    backup_gps_lon = backup_coords[, 1],
    backup_gps_lat = backup_coords[, 2],
    extent_delineation_failed = NA,
    extent_source_note = paste0(
      "Fixed-radius buffer fallback (", FALLBACK_RADIUS_M, "m around the DTM point) - standard-size camp, ",
      "newly selected by the 2026-08-06 targeted 24-LGA resample (Niger buffer 20km->5km in NW), not part of ",
      "the original national draw. Generated using the identical method as Part 3's standard-camp extension."
    ),
    backup_point_method = "fixed_radius_fallback_standard_camp"
  )

existing <- read_csv(path, show_col_types = FALSE)
stopifnot("New site_ids must not already exist" = !any(new_rows$site_id %in% existing$site_id))

combined <- bind_rows(existing, new_rows %>% select(all_of(names(existing))))
write_csv(combined, path, na = "NA")

cat("Added", nrow(new_rows), "new in-camp backup points. Total in-camp rows now:", nrow(combined), "\n")
print(new_rows %>% select(site_id, iom_site_name, backup_gps_lat, backup_gps_lon))
