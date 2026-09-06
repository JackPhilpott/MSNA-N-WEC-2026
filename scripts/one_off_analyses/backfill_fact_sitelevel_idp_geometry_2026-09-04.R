# ==============================================================================
# Backfills new_clusters_idp.gpkg for FACT's two site-level IDP batches, which
# both predate the 2026-09-03 fix to draw_supplementary_idp_sites_batch.R
# (which now writes this file automatically for future batches). Same
# situation, same fix pattern as write_mobbar_idp_geometry_gpkg_2026-09-03.R:
# no redraw - the clusters are already live and merged into the frame; this
# only builds the geometry file 2_monitoring's prep_psu_geometries.R expects
# to find alongside each batch's CSVs.
#
# Flagged by 2_monitoring 2026-09-04: 29 covered FACT IDP clusters had no
# geometry at all (a 30th, idp_NG021001_supp1, already had geometry from
# elsewhere and is correctly excluded here - verified directly against
# psu_sites_idp.gpkg before writing this script).
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

BATCH_DIRS <- c(
  "resampling/output/resample_runs/FACT/2026-09-02_sitelevel",
  "resampling/output/resample_runs/FACT/2026-09-03"
)

for (STAGING_DIR in BATCH_DIRS) {
  cat("\n==", STAGING_DIR, "==\n")
  csv_path <- file.path(STAGING_DIR, "new_clusters_idp_sitelevel.csv")
  gpkg_path <- file.path(STAGING_DIR, "new_clusters_idp.gpkg")
  if (file.exists(gpkg_path)) {
    cat("  Already has new_clusters_idp.gpkg - skipping.\n")
    next
  }

  cl <- read_csv(csv_path, show_col_types = FALSE)
  cat("  Rows in CSV:", nrow(cl), "\n")

  # selection_type = "pps" hardcoded, same basis as the Mobbar backfill:
  # every site-level IDP cluster in this project is drawn PPS by construction.
  cl_sf <- st_as_sf(cl, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
    mutate(pop_type = "idp", selection_type = "pps") %>%
    select(any_of(c("cluster_id", "strata_id", "pop_type", "region", "adm1_name", "adm1_pcode",
                     "adm2_name", "adm2_pcode", "selection_type", "iom_site_name", "iom_site_type",
                     "idp_population_category")), geometry)
  cat("  Columns written:", paste(names(cl_sf), collapse = ", "), "\n")

  st_write(cl_sf, gpkg_path, delete_layer = TRUE, quiet = TRUE)
  cat("  Wrote:", gpkg_path, "-", nrow(cl_sf), "rows\n")
}

cat("\nDONE.\n")
