# ==============================================================================
# Adds a Tier 2 backup GPS point for Gsss Camp Damasak (idp_NG008023_supp2,
# Mobbar/FHI 360) - the one in-camp cluster among tonight's 10 new Mobbar IDP
# sites (the other 9 are "idps in host", no radius/backup-point concept
# applies to those per the methodology). At 12,243 households this is one of
# the largest camps in the whole dataset - well above the 2,000hh flagged-
# camp threshold - so it would have gotten this treatment automatically had
# it existed at original design time.
#
# Uses the SAME fixed-radius-buffer fallback method as analysis_idp_camp_
# backup_points_part2.R/_part3.R (300m radius, uniform over the circle's
# area, r = 300*sqrt(u)) - this session has no satellite-imagery review
# capability, so the more careful imagery-delineated method used for 9 of
# the original 15 flagged camps isn't available here. This is not a lesser-
# quality outcome by this project's own standard: 6 of the original 15
# flagged camps ALSO ended up on this exact fallback ("delineation wasn't
# confident") - fixed_radius_fallback_flagged_camp is an established,
# already-used category, not new.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr); library(sf) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
set.seed(1234)
mycrs <- 31028
FALLBACK_RADIUS_M <- 300
DC_DIR <- "output/data/data_collection"

# ---- Step 1: append to idp_camp_backup_points.csv ----
BACKUP_CSV <- file.path(DC_DIR, "idp_camp_backup_points.csv")
BACKUP_CSV_ARCHIVE <- file.path(DC_DIR, "idp_camp_backup_points_PRE_GSSS_DAMASAK_backup_2026-09-03.csv")
df <- read_csv(BACKUP_CSV, show_col_types = FALSE)
if (!file.exists(BACKUP_CSV_ARCHIVE)) write_csv(df, BACKUP_CSV_ARCHIVE)
cat("Existing rows:", nrow(df), "\n")
stopifnot(!("BO_S355" %in% df$iom_site_id))

dtm_lat <- 13.112261012582024
dtm_lon <- 12.51781596501906
pt_wgs84 <- st_as_sf(data.frame(lon = dtm_lon, lat = dtm_lat), coords = c("lon", "lat"), crs = 4326)
pt_proj <- st_transform(pt_wgs84, mycrs)
coords <- st_coordinates(pt_proj)

theta <- runif(1, 0, 2 * pi)
u <- runif(1)
r <- FALLBACK_RADIUS_M * sqrt(u)
backup_x <- coords[1, 1] + r * cos(theta)
backup_y <- coords[1, 2] + r * sin(theta)
backup_wgs84 <- st_as_sf(data.frame(x = backup_x, y = backup_y), coords = c("x", "y"), crs = mycrs) %>% st_transform(4326)
backup_coords <- st_coordinates(backup_wgs84)

new_row <- tibble::tibble(
  site_id = "idp_NG008023_supp2", iom_site_id = "BO_S355", iom_site_name = "Gsss Camp Damasak Camp",
  iom_site_type = "Camp", iom_site_ward = "Damasak", region = "NE", adm1_name = "Borno", adm2_name = "Mobbar",
  households_in_cluster = 12243, dtm_gps_lat = dtm_lat, dtm_gps_lon = dtm_lon,
  flagged_camp = TRUE, backup_gps_lat = backup_coords[1, 2], backup_gps_lon = backup_coords[1, 1],
  extent_delineation_failed = TRUE,
  extent_source_note = paste0(
    "Fixed-radius buffer fallback (", FALLBACK_RADIUS_M, "m around the DTM point) - genuinely a flagged-size ",
    "camp (12,243 households, well above the 2,000hh threshold) but added 2026-09-03 as part of the Mobbar/",
    "FHI 360 border-buffer override, outside the original design-time imagery review pass. No satellite-",
    "imagery delineation capability available for this addition; same fallback method used for 6 of the ",
    "original 15 flagged camps where delineation wasn't confident, not a new/lesser method."
  ),
  backup_point_method = "fixed_radius_fallback_flagged_camp"
)
stopifnot(setequal(names(new_row), names(df)))
df_new <- bind_rows(df, new_row %>% select(names(df)))
write_csv(df_new, BACKUP_CSV, na = "NA")
cat("Wrote", BACKUP_CSV, "-", nrow(df), "->", nrow(df_new), "rows.\n")
cat(sprintf("New backup point: lat=%.6f, lon=%.6f (%.0fm from DTM point)\n", backup_coords[1,2], backup_coords[1,1], r))

# ---- Step 2: patch site_radius_m/tier2_fallback_used on the live frame (FULL+WORKING) ----
patch_frame <- function(path) {
  d <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c"))
  idx <- which(d$cluster_id == "idp_NG008023_supp2")
  cat(basename(path), "- rows matched:", length(idx), "\n")
  d$site_radius_m[idx] <- as.character(FALLBACK_RADIUS_M)
  d$tier2_fallback_used[idx] <- "FALSE"
  write_csv(d, path)
}
patch_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v5_FULL.csv"))
patch_frame(file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v5_WORKING.csv"))

cat("\nDONE.\n")
