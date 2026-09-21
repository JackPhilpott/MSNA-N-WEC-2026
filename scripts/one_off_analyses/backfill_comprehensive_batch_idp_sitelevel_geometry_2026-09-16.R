# ==============================================================================
# Backfills new_clusters_idp.gpkg for the two partners in the 2026-09-14
# comprehensive batch that drew real IDP site-level clusters alongside their
# Non-IDP hex clusters: INTERSOS (7 sites, Magumeri) and IRC (1 site, Jibia).
# Same root cause, same fix pattern as backfill_fact_sitelevel_idp_geometry_
# 2026-09-04.R / write_mobbar_idp_geometry_gpkg_2026-09-03.R: the comprehensive
# batch's per-partner split only ever wrote new_clusters.gpkg (Non-IDP hex
# geometry, via split_combined_draw_by_partner_2026-09-14.R), never a separate
# new_clusters_idp.gpkg for the site-level IDP rows staged alongside it in
# new_clusters_idp_sitelevel.csv - no redraw, the clusters are already live and
# merged into the frame; this only builds the geometry file 2_monitoring's
# prep_psu_geometries.R expects to find alongside each batch's CSVs.
#
# Checked before writing this: of all 9 partners flagged by 2_monitoring as
# missing new_clusters.gpkg (CARE/FACT/FHI 360/IMC/INTERSOS/IRC/Malteser/NRC/
# Solidarités), 8 already have it - written correctly by the R-based
# split_combined_draw_by_partner_2026-09-14.R splitter used for the main
# comprehensive draw. Only Malteser's new_clusters.csv/new_households.csv are
# genuinely empty (Malteser drew zero real clusters that night - its one
# shortfall stratum's candidate pool was already exhausted at draw time, per
# Coordinator's independent verification the same night) - nothing to backfill
# there, not a real gap. The REAL gap, found while checking this, is the
# IDP-site-level file this script fixes - never covered by the flagged report,
# since new_clusters.gpkg existing at all made the directory look complete.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

BATCH_DIRS <- c(
  "resampling/output/resample_runs/INTERSOS/2026-09-14_comprehensive",
  "resampling/output/resample_runs/IRC/2026-09-14_comprehensive"
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
  if (nrow(cl) == 0) {
    cat("  Zero rows - nothing to write.\n")
    next
  }

  # selection_type = "pps" hardcoded, same basis as the Mobbar/FACT backfills:
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
