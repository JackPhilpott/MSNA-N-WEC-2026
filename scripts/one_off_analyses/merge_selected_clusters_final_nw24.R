# ==============================================================================
# Merges selected_clusters_final.rds (hex-level Stage 1/2 cluster geometries,
# used by the coverage maps) for the 2026-08-06 targeted 24-LGA resample -
# same splice logic as merge_targeted_resample_nw24.py, but for the spatial
# object the map scripts actually need (household-level CSVs have no hex
# polygon geometry).
# ==============================================================================
suppressMessages({ library(sf); library(dplyr) })

TARGET_PCODES <- c(
  "NG021003", "NG021004", "NG021010", "NG021016", "NG021018",
  "NG021021", "NG021024", "NG021027", "NG021033", "NG021034",
  "NG022002", "NG022005", "NG022007", "NG022008",
  "NG034004", "NG034005", "NG034006", "NG034007",
  "NG034008", "NG034009", "NG034013", "NG034019",
  "NG037011", "NG037014"
)
stopifnot(length(TARGET_PCODES) == 24)

live <- readRDS("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling/_archive/2026-08-04_design_frame_pre_coverage/selected_clusters_final.rds")
new <- readRDS("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling_targeted_resample_nw24/output/selected_clusters_final.rds")

cat("Live columns:", paste(names(live), collapse=", "), "\n")
cat("New columns:", paste(names(new), collapse=", "), "\n")
cat("Same columns:", setequal(names(live), names(new)), "\n")
cat("Same CRS:", st_crs(live) == st_crs(new), "\n")

kept <- live %>% filter(!(adm2_pcode %in% TARGET_PCODES))
cat("\nLive rows:", nrow(live), " | kept (non-target LGAs):", nrow(kept), " | new (24 target LGAs):", nrow(new), "\n")

new <- new %>% select(all_of(names(kept)))
merged <- bind_rows(kept, new)
cat("Merged rows:", nrow(merged), "\n")

out_dir <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling/_archive/2026-08-06_design_frame_post_nw_targeted_resample"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(merged, file.path(out_dir, "selected_clusters_final.rds"))
cat("\nSaved:", file.path(out_dir, "selected_clusters_final.rds"), "\n")
