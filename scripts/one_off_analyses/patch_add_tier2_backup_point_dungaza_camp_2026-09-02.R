# ==============================================================================
# Found during the 2026-09-02 comprehensive post-rollout review: the site-
# level IDP PSU redraw (draw_supplementary_idp_sites_batch.R) added one new
# IN-CAMP cluster - idp_NG021007_supp4, "Dungaza Idp Camp" (Dan Musa,
# Katsina, FACT, 62hh DTM-recorded, 6hh target) - among its 19 new clusters
# (18 of the other 19 are "idps in host", which never get a backup point at
# all). Every in-camp cluster needs a Tier-2 random-walk starting point per
# the 2026-08-05 blanket expansion (analysis_idp_camp_backup_points_part3.R)
# - this one didn't exist yet since it's brand new tonight. Applies the
# EXACT same fixed-radius-buffer-fallback method as every other standard-
# size camp (this one is nowhere near the >2,000hh individually-reviewed
# threshold) - same pattern as patch_add_tier2_backup_points_new_incamp_
# clusters_2026-09-01.R last night, just for this one additional cluster.
# ==============================================================================
suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
set.seed(1234)  # same seed convention as every prior backup-point generation pass

mycrs <- 31028
FALLBACK_RADIUS_M <- 300
PATH <- "output/data/data_collection/idp_camp_backup_points.csv"

full_v4 <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v4_FULL.csv",
                     show_col_types = FALSE, col_types = cols(.default = "c"))

new_ids <- c("idp_NG021007_supp4")
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
  new_rows$households_in_cluster, "hh, well under the 2,000hh individually-reviewed threshold), new from the ",
  "2026-09-02 site-level IDP PSU redraw (Option B). Same method as every other standard-size in-camp cluster ",
  "(analysis_idp_camp_backup_points_part3.R, 2026-08-05) - generated 2026-09-02, not individually imagery-reviewed."
)
new_rows$backup_point_method <- "fixed_radius_fallback_new_supplementary_cluster"

new_rows <- new_rows %>% select(names(df))
out <- bind_rows(df, new_rows)

write_csv(out, PATH)
cat("Added", nrow(new_rows), "row(s) to", PATH, "- now", nrow(out), "total rows.\n")
print(new_rows %>% select(site_id, iom_site_name, households_in_cluster, dtm_gps_lat, dtm_gps_lon, backup_gps_lat, backup_gps_lon))
