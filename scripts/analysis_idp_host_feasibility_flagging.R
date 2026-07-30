# ==============================================================================
# IDP (host-community) site feasibility flagging
#
# Standalone pre-fieldwork analysis (NOT part of the numbered 00-08 pipeline,
# does not modify the frozen sampling frame) - flags "idps in host" sites
# where the planned Stage 2 method (a local site leader produces a full
# household listing on arrival, households then randomly selected from it)
# is at risk of breaking down, for two reasons:
#   1. Urban density - the site sits in a dense surrounding population where
#      no single informant can meaningfully enumerate the area.
#   2. Caseload size - the site's own DTM-recorded household count is too
#      large for one-person listing to be practical.
#
# Scope: the 1,099 "idps in host" sites actually selected into the delivered
# sample (output/stage2_sampling_frame_idp.csv), not the full raw DTM
# universe - these are the sites field teams will actually visit. "idps in
# camp" sites are out of scope (different, non-listing field method).
#
# Reuses the exact WorldPop population layer/CRS/extraction method already
# used to build the Non-IDP hexagon frame (build_population_by_hex(),
# 01_sampling_pipeline_main.R lines ~614-689): same cached projected raster,
# same mycrs (31028), same exactextractr::exact_extract(..., "sum") zonal
# sum, same hh_size=6 households-per-person-count conversion - just against
# a circular buffer per site instead of a hexagon.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(terra)
  library(here)
})

set.seed(1234)

mycrs   <- 31028   # WGS 84 / UTM zone 28N, metres - identical to main pipeline
hh_size <- 6        # average household size - identical to main pipeline

data_dir       <- here("input_data")
population_dir <- here(data_dir, "population")
output_dir     <- here("output")
analysis_dir   <- here(output_dir, "analysis_idp_host_feasibility")
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Buffer radius: task asked for something "consistent with the hexagon cell
# size already used elsewhere in the frame". The Stage 1 hex grid uses
# st_make_grid(cellsize = 5000) (~5km scale) - that's the right grain for
# spreading Non-IDP PSUs across a whole LGA, but far too coarse for "is this
# site inside a dense built-up area" (a 5km circle around a site would pull
# in an entire town). 750m sits in the task's own suggested 500m-1km range -
# roughly a 10-15 minute walk, a defensible proxy for "the area one
# informant could realistically be aware of" - and is kept as a single named
# parameter below so it's trivial to re-run at a different radius.
# ---------------------------------------------------------------------------
buffer_radius_m <- 750

# ---------------------------------------------------------------------------
# 1. Load host-community IDP sites actually in the delivered sample
# ---------------------------------------------------------------------------
idp_sites_raw <- read_csv(
  here(output_dir, "stage2_sampling_frame_idp.csv"),
  show_col_types = FALSE
)

host_sites <-
  idp_sites_raw %>%
  filter(idp_population_category == "idps in host") %>%
  distinct(
    cluster_id, iom_site_id, iom_site_name, iom_site_type, iom_site_ward,
    region, adm1_pcode, adm1_name, adm2_pcode, adm2_name,
    latitude, longitude,
    households_in_cluster, n_other_sites_in_hex, certainty_stratum
  )

stopifnot(
  "Expected exactly one row per site after distinct()" =
    nrow(host_sites) == n_distinct(host_sites$cluster_id)
)

message(nrow(host_sites), " host-community IDP sites in the delivered sample.")

host_sites_sf <-
  host_sites %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_transform(mycrs)

# ---------------------------------------------------------------------------
# 2. Load the exact same WorldPop layer used for the Non-IDP hex frame
#    (already projected to mycrs and cropped to the assessment states -
#    reusing the cached .rds directly, not re-deriving from the raw .tif)
# ---------------------------------------------------------------------------
worldpop_pop <- readRDS(
  here(population_dir, "worldpop", "worldpop_nga_2026_projected.rds")
)

# ---------------------------------------------------------------------------
# 3. Buffer + zonal sum - identical mechanism to build_population_by_hex()'s
#    Non-IDP path (exact_extract(..., "sum")), against a circular buffer
#    instead of a hexagon
# ---------------------------------------------------------------------------
site_buffers <- st_buffer(host_sites_sf, dist = buffer_radius_m)

surrounding_pop <- exactextractr::exact_extract(
  worldpop_pop,
  site_buffers,
  "sum"
)

buffer_area_km2 <- (pi * buffer_radius_m^2) / 1e6

host_sites_flagged <-
  host_sites_sf %>%
  st_drop_geometry() %>%
  mutate(
    buffer_radius_m       = buffer_radius_m,
    surrounding_pop       = as.numeric(surrounding_pop),
    surrounding_pop_hh    = surrounding_pop / hh_size,
    density_pop_per_km2   = surrounding_pop / buffer_area_km2,
    density_hh_per_km2    = surrounding_pop_hh / buffer_area_km2,
    caseload_hh           = households_in_cluster
  )

# ---------------------------------------------------------------------------
# 4. Percentile summaries (computed before any threshold is fixed, so the
#    threshold can be chosen against the real distribution)
# ---------------------------------------------------------------------------
density_percentiles <- quantile(
  host_sites_flagged$density_hh_per_km2,
  probs = c(0, .10, .25, .50, .75, .80, .85, .90, .95, .975, .99, 1),
  na.rm = TRUE
)

caseload_percentiles <- quantile(
  host_sites_flagged$caseload_hh,
  probs = c(0, .10, .25, .50, .75, .80, .85, .90, .95, .975, .99, 1),
  na.rm = TRUE
)

density_p90 <- density_percentiles[["90%"]]
density_p95 <- density_percentiles[["95%"]]

# ---------------------------------------------------------------------------
# 5. Flags - two named threshold options each, per the task, so both can be
#    reviewed side by side rather than committing to one number now
# ---------------------------------------------------------------------------
host_sites_flagged <-
  host_sites_flagged %>%
  mutate(
    density_flag_p90     = density_hh_per_km2 > density_p90,
    density_flag_p95     = density_hh_per_km2 > density_p95,
    caseload_flag_150    = caseload_hh > 150,
    caseload_flag_200    = caseload_hh > 200,
    # "Default" combined view used in the summary tables/charts below:
    # p90 density OR >150 households - the more inclusive (lower-threshold)
    # pairing, since under-flagging a site that turns out infeasible in the
    # field is more costly than over-flagging one for a closer look.
    density_flag_default  = density_flag_p90,
    caseload_flag_default = caseload_flag_150,
    combined_flag_default = density_flag_default | caseload_flag_default,
    combined_flag_both_p90_150  = density_flag_p90 & caseload_flag_150,
    combined_flag_either_p95_200 = density_flag_p95 | caseload_flag_200,
    combined_flag_both_p95_200   = density_flag_p95 & caseload_flag_200
  ) %>%
  arrange(desc(combined_flag_default), desc(density_hh_per_km2), desc(caseload_hh))

# ---------------------------------------------------------------------------
# 6. Write outputs
# ---------------------------------------------------------------------------
write_csv(
  host_sites_flagged %>%
    select(
      cluster_id, iom_site_id, iom_site_name, iom_site_type, iom_site_ward,
      region, adm1_name, adm2_name, latitude, longitude,
      caseload_hh, n_other_sites_in_hex, certainty_stratum,
      buffer_radius_m, surrounding_pop, surrounding_pop_hh,
      density_pop_per_km2, density_hh_per_km2,
      density_flag_p90, density_flag_p95,
      caseload_flag_150, caseload_flag_200,
      density_flag_default, caseload_flag_default, combined_flag_default,
      combined_flag_both_p90_150, combined_flag_either_p95_200, combined_flag_both_p95_200
    ),
  here(analysis_dir, "idp_host_community_feasibility_flags.csv")
)

saveRDS(
  list(
    sites = host_sites_flagged,
    density_percentiles = density_percentiles,
    caseload_percentiles = caseload_percentiles,
    buffer_radius_m = buffer_radius_m,
    buffer_area_km2 = buffer_area_km2
  ),
  here(analysis_dir, "idp_host_community_feasibility.rds")
)

# ---------------------------------------------------------------------------
# 7. Console summary
# ---------------------------------------------------------------------------
cat("\n=== DENSITY (households/km^2 within", buffer_radius_m, "m) PERCENTILES ===\n")
print(round(density_percentiles, 1))

cat("\n=== CASELOAD (households_in_cluster) PERCENTILES ===\n")
print(round(caseload_percentiles, 1))

cat("\n=== FLAG COUNTS ===\n")
n_total <- nrow(host_sites_flagged)
cat("Total host-community sites:", n_total, "\n\n")

summarise_flag <- function(flag_col, label) {
  n <- sum(host_sites_flagged[[flag_col]])
  cat(sprintf("%-45s %5d  (%.1f%%)\n", label, n, 100 * n / n_total))
}

summarise_flag("density_flag_p90", "Density > p90")
summarise_flag("density_flag_p95", "Density > p95")
summarise_flag("caseload_flag_150", "Caseload > 150 hh")
summarise_flag("caseload_flag_200", "Caseload > 200 hh")
summarise_flag("combined_flag_default", "Combined (p90 density OR >150 hh)")
summarise_flag("combined_flag_both_p90_150", "Combined (p90 density AND >150 hh)")
summarise_flag("combined_flag_either_p95_200", "Combined (p95 density OR >200 hh)")
summarise_flag("combined_flag_both_p95_200", "Combined (p95 density AND >200 hh)")

cat("\n=== STATE CONCENTRATION (combined_flag_default = TRUE) ===\n")
print(
  host_sites_flagged %>%
    filter(combined_flag_default) %>%
    count(adm1_name, sort = TRUE)
)

cat("\n=== LGA CONCENTRATION (combined_flag_default = TRUE), top 15 ===\n")
print(
  host_sites_flagged %>%
    filter(combined_flag_default) %>%
    count(adm1_name, adm2_name, sort = TRUE) %>%
    head(15)
)

message("\nWrote: ", here(analysis_dir, "idp_host_community_feasibility_flags.csv"))
message("Wrote: ", here(analysis_dir, "idp_host_community_feasibility.rds"))
