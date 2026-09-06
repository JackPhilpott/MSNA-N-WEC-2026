# ==============================================================================
# Adds Tier-2 (random-walk fallback) backup GPS points for the 2 new in-camp
# IDP clusters from this week's resampling round that idp_camp_backup_
# points.csv (last built 2026-08-06, predates all resampling) has no row
# for at all: idp_NG008007_supp2 (Unity Camp, Damboa/IMC, 575hh) and
# idp_NG021001_supp1 (Nadabo Primary School Camp, Bakori/FACT, 100hh).
#
# Both are well under the 2,000hh flagged-camp threshold (see analysis_idp_
# camp_backup_points_part1.R) - i.e. exactly the "standard-size camp" case
# Part 3 (2026-08-05) already established a method for: a uniform-random
# point within a fixed 300m radius of the DTM point, no individual imagery
# review needed or expected for camps this size. This script applies that
# SAME already-approved method to these 2 rows only - not a new judgment
# call, a direct extension of existing, already-signed-off methodology.
# Same FALLBACK_RADIUS_M, same uniform-over-circle-area sampling, same
# extent_source_note wording pattern as Part 3.
# ==============================================================================
suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
set.seed(1234)  # same seed convention as Part 2/Part 3

mycrs <- 31028
FALLBACK_RADIUS_M <- 300
PATH <- "output/data/data_collection/idp_camp_backup_points.csv"

full_v4 <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                     show_col_types = FALSE, col_types = cols(.default = "c"))

new_ids <- c("idp_NG008007_supp2", "idp_NG021001_supp1")
new_rows_src <- full_v4 %>%
  filter(cluster_id %in% new_ids) %>%
  distinct(cluster_id, .keep_all = TRUE)
stopifnot(nrow(new_rows_src) == length(new_ids))

df <- read_csv(PATH, show_col_types = FALSE)
already_present <- intersect(new_rows_src$cluster_id, df$site_id)
if (length(already_present) > 0) {
  stop("Refusing to run: already present in idp_camp_backup_points.csv: ", paste(already_present, collapse = ", "))
}

new_rows <- new_rows_src %>%
  transmute(
    site_id = cluster_id,
    iom_site_id = iom_site_id,
    iom_site_name = iom_site_name,
    iom_site_type = iom_site_type,
    iom_site_ward = adm3_name,
    region = region,
    adm1_name = adm1_name,
    adm2_name = adm2_name,
    households_in_cluster = as.numeric(households_in_cluster),
    dtm_gps_lat = as.numeric(latitude),
    dtm_gps_lon = as.numeric(longitude),
    flagged_camp = FALSE,
  )

pts_wgs84 <- st_as_sf(new_rows, coords = c("dtm_gps_lon", "dtm_gps_lat"), crs = 4326, remove = FALSE)
pts_proj <- st_transform(pts_wgs84, mycrs)
coords <- st_coordinates(pts_proj)

n <- nrow(new_rows)
theta <- runif(n, 0, 2 * pi)
u <- runif(n)
r <- FALLBACK_RADIUS_M * sqrt(u)  # uniform over the circle's area, not r = R*u

backup_x <- coords[, 1] + r * cos(theta)
backup_y <- coords[, 2] + r * sin(theta)
backup_wgs84 <- st_as_sf(data.frame(backup_x, backup_y), coords = c("backup_x", "backup_y"), crs = mycrs) %>%
  st_transform(4326)
backup_coords <- st_coordinates(backup_wgs84)

new_rows$backup_gps_lon <- backup_coords[, 1]
new_rows$backup_gps_lat <- backup_coords[, 2]
new_rows$extent_delineation_failed <- NA
new_rows$extent_source_note <- paste0(
  "Fixed-radius buffer fallback (", FALLBACK_RADIUS_M, "m around the DTM point) - standard-size camp (",
  new_rows$households_in_cluster, "hh, well under the 2,000hh individually-reviewed threshold), new from this ",
  "week's accessibility-driven resampling round. Same method as every other standard-size in-camp cluster ",
  "(analysis_idp_camp_backup_points_part3.R, 2026-08-05) - generated 2026-09-01, not individually imagery-reviewed."
)
new_rows$backup_point_method <- "fixed_radius_fallback_new_supplementary_cluster"

new_rows <- new_rows %>% select(names(df))
out <- bind_rows(df, new_rows)

write_csv(out, PATH)
cat("Added", nrow(new_rows), "row(s) to", PATH, "- now", nrow(out), "total rows.\n")
print(new_rows %>% select(site_id, iom_site_name, households_in_cluster, dtm_gps_lat, dtm_gps_lon, backup_gps_lat, backup_gps_lon))
