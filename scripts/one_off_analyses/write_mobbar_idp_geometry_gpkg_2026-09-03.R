# ==============================================================================
# Writes new_clusters_idp.gpkg for tonight's Mobbar site-level IDP batch, from
# the ALREADY-DRAWN new_clusters_idp_sitelevel.csv (no redraw - the real
# clusters are already live and merged; this only builds the geometry file
# 2_monitoring's prep_psu_geometries.R expects to find, which draw_
# supplementary_idp_sites_batch.R never wrote in the first place - see the
# companion fix in that script for future runs).
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
STAGING_DIR <- "resampling/output/resample_runs/FHI360_Mobbar/2026-09-03"

cl <- read_csv(file.path(STAGING_DIR, "new_clusters_idp_sitelevel.csv"), show_col_types = FALSE)
cat("Rows:", nrow(cl), "\n")

# selection_type = "pps" hardcoded (not coalesced from a maybe-missing
# column) - every Mobbar IDP cluster is PPS by construction, N_hh=15,913 is
# far above the certainty_threshold (m*6=36), verified 2026-09-03.
cl_sf <- st_as_sf(cl, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  mutate(pop_type = "idp", selection_type = "pps") %>%
  select(any_of(c("cluster_id", "strata_id", "pop_type", "region", "adm1_name", "adm1_pcode",
                   "adm2_name", "adm2_pcode", "selection_type", "iom_site_name", "iom_site_type",
                   "idp_population_category")), geometry)
cat("Columns written:", paste(names(cl_sf), collapse=", "), "\n")

st_write(cl_sf, file.path(STAGING_DIR, "new_clusters_idp.gpkg"), delete_layer = TRUE, quiet = TRUE)
cat("Wrote:", file.path(STAGING_DIR, "new_clusters_idp.gpkg"), "-", nrow(cl_sf), "rows\n")
