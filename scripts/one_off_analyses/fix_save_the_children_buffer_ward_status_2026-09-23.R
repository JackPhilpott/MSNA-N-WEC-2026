# ==============================================================================
# The 4 Non-IDP "excess buffer" clusters drawn for Save the Children
# (2026-09-23, resample_runs/Save the Children/2026-09-23_excess_buffer/)
# landed in household FULL with ward_accessible_status == "NA" (the literal
# string) and were correctly excluded from WORKING pending review by
# merge_partner_resample_batch.R's own documented safety default (see its
# NEEDS_REVIEW_unmatched_ward_status.csv output) - these rows' admin3_cod_
# pcode is genuinely blank (edge-of-boundary GRID3/COD crosswalk gap, same
# shape already hit and fixed once before, see 1_sampling/CLAUDE.md's
# "Update 2026-09-14" ~line 3670 entry for the identical precedent/fix).
#
# Checked directly (not assumed): all 6 distinct (State, LGA, Ward GRID3)
# combinations these 48 rows actually sit in - Benue/Kwande/Mbadura,
# Benue/Kwande/Liev L, Zamfara/Bungudu/Nahuche, Katsina/Mai'adua/Natsalle,
# Katsina/Mai'adua/Danyashe, Katsina/Zango/K Malamai - all resolve cleanly
# against master_accessibility_status_ward_level.csv as "Accessible". Fixed
# forward exactly like the 2026-09-14 precedent: re-run the same (State,
# LGA, Ward GRID3) lookup directly on these rows and patch ward_accessible_
# status, rather than touching the merge script's join logic itself.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)

DC_DIR <- "output/data/data_collection"
hh_path <- file.path(DC_DIR, "NGA_MSNA_2026_stage2_sampling_frame_v13_FULL.csv")
BUFFER_CLUSTERS <- c("non_idp_NG007011_supp3", "non_idp_NG037005_supp9",
                      "non_idp_NG021024_supp3", "non_idp_NG021034_supp3")

archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_save_the_children_buffer_ward_status_fix"))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))
master <- read_csv("resampling/output/master_accessibility_status_ward_level.csv", show_col_types = FALSE) %>%
  select(State, LGA, `Ward (GRID3)`, `Accessible status`) %>%
  distinct()

target_rows <- full_hh %>% filter(cluster_id %in% BUFFER_CLUSTERS)
stopifnot(nrow(target_rows) == 48, all(is.na(target_rows$ward_accessible_status)))
cat(sprintf("%d rows across %d buffer cluster(s) currently ward_accessible_status == NA.\n",
            nrow(target_rows), n_distinct(target_rows$cluster_id)))

lookup <- target_rows %>%
  distinct(adm1_name, adm2_name, adm3_name) %>%
  left_join(master, by = c("adm1_name" = "State", "adm2_name" = "LGA", "adm3_name" = "Ward (GRID3)"))
print(as.data.frame(lookup))
stopifnot(!any(is.na(lookup$`Accessible status`)))

full_hh <- full_hh %>%
  left_join(lookup %>% select(adm1_name, adm2_name, adm3_name, `Accessible status`),
            by = c("adm1_name", "adm2_name", "adm3_name")) %>%
  mutate(ward_accessible_status = if_else(
    cluster_id %in% BUFFER_CLUSTERS & !is.na(`Accessible status`),
    `Accessible status`, ward_accessible_status
  )) %>%
  select(-`Accessible status`)

after_rows <- full_hh %>% filter(cluster_id %in% BUFFER_CLUSTERS)
stopifnot(nrow(after_rows) == 48, all(after_rows$ward_accessible_status == "Accessible"))
cat(sprintf("\nAfter fix, %s (%d rows): ward_accessible_status = 'Accessible'\n",
            paste(BUFFER_CLUSTERS, collapse = ", "), nrow(after_rows)))

write_csv(full_hh, hh_path)
cat("\nWritten. Re-run refresh_working_frame_daily.R next to pull these into WORKING.\n")
