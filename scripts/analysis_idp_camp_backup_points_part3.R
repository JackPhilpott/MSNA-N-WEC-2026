# ==============================================================================
# IDP in-camp backup GPS point generation - PART 3: extend backup points to
# every in-camp cluster, not just the 15 originally flagged (>2,000hh) camps.
#
# Context (2026-08-05, day before pilot data collection starts): partners at
# the ToT raised concern about Tier 1 (full household listing) feasibility
# more broadly than the original >2,000hh flag anticipated, and asked for a
# Tier-2 (random walk) starting point to exist everywhere as a just-in-case
# backup, not only at the 15 largest camps. User decision: extend using the
# SAME fixed-radius-buffer fallback method Part 2 already uses for camps
# where imagery delineation wasn't confident, rather than attempting manual
# imagery delineation for 66 more camps overnight (not feasible before
# tomorrow's pilot start, and the buffer fallback is already an accepted,
# documented method in this same dataset).
#
# Does NOT touch the 15 already-flagged camps' rows (9 delineated + 6
# already-fallback, from Part 2) - only fills in backup_gps_lat/lon for the
# remaining 66 rows where it was previously NA. flagged_camp is left exactly
# as-is (it still means "was in the original >2,000hh review subset"); a new
# backup_point_method column distinguishes how each row's backup point was
# produced, since "has a backup point" and "was individually reviewed" are no
# longer the same thing after this script runs.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(here)
})

set.seed(1234)  # same seed convention as Part 2 (kept separate stream below)

mycrs <- 31028
deliverable_dir <- here("output", "data", "data_collection")
path <- here(deliverable_dir, "idp_camp_backup_points.csv")

FALLBACK_RADIUS_M <- 300  # identical to Part 2's fallback radius

df <- read_csv(path, show_col_types = FALSE)

n_before <- sum(!is.na(df$backup_gps_lat))
cat("Rows with a backup point already (flagged camps, Part 2):", n_before, "of", nrow(df), "\n")

df <- df %>%
  mutate(backup_point_method = case_when(
    flagged_camp & !extent_delineation_failed ~ "imagery_delineated",
    flagged_camp & extent_delineation_failed ~ "fixed_radius_fallback_flagged_camp",
    TRUE ~ NA_character_
  ))

to_fill <- which(is.na(df$backup_gps_lat))
cat("Rows needing a new backup point (standard-size camps):", length(to_fill), "\n")

if (length(to_fill) > 0) {
  pts_wgs84 <- st_as_sf(df[to_fill, ], coords = c("dtm_gps_lon", "dtm_gps_lat"), crs = 4326, remove = FALSE)
  pts_proj <- st_transform(pts_wgs84, mycrs)
  coords <- st_coordinates(pts_proj)

  n <- length(to_fill)
  theta <- runif(n, 0, 2 * pi)
  u <- runif(n)
  r <- FALLBACK_RADIUS_M * sqrt(u)  # uniform over the circle's area, not r = R*u

  backup_x <- coords[, 1] + r * cos(theta)
  backup_y <- coords[, 2] + r * sin(theta)

  backup_wgs84 <- st_as_sf(data.frame(backup_x, backup_y), coords = c("backup_x", "backup_y"), crs = mycrs) %>%
    st_transform(4326)
  backup_coords <- st_coordinates(backup_wgs84)

  df$backup_gps_lon[to_fill] <- backup_coords[, 1]
  df$backup_gps_lat[to_fill] <- backup_coords[, 2]
  df$extent_delineation_failed[to_fill] <- NA  # concept doesn't apply - never reviewed, not a failed review
  df$extent_source_note[to_fill] <- paste0(
    "Fixed-radius buffer fallback (", FALLBACK_RADIUS_M, "m around the DTM point) - standard-size camp, ",
    "not part of the original >2,000hh flagged/individually-reviewed subset. Generated 2026-08-05 so every ",
    "in-camp cluster has a Tier-2 random-walk starting point available, per partner feedback at the ToT ",
    "that Tier 1 listing feasibility is a broader concern than the original flagging anticipated."
  )
  df$backup_point_method[to_fill] <- "fixed_radius_fallback_standard_camp"
}

stopifnot(
  "Every in-camp row must have a backup point now" = all(!is.na(df$backup_gps_lat)),
  "Every in-camp row must have a backup point now" = all(!is.na(df$backup_gps_lon))
)

write_csv(df, path, na = "NA")

cat("\n=== PART 3 COMPLETE ===\n")
cat("Total in-camp rows:", nrow(df), "- all now have a backup GPS point.\n")
print(df %>% count(backup_point_method))
cat("\nWrote:", path, "\n")
