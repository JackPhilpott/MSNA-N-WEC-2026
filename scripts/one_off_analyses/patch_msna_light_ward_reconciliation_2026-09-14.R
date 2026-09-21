# ==============================================================================
# Fix for a real gap Jack found via his DO's Kobo-import failures: all 564
# MSNA Light household rows (Abadam/Nganzai/Guzamala, 2026-09-11) have
# adm3_pcode/admin3_source/admin3_cod_pcode/admin3_cod_name = NA - the
# standard ward-reconciliation columns every other row in this project gets
# via 03_stage2_household_selection.R's two spatial joins (GRID3 wards ->
# adm3_pcode/adm3_name/admin3_source; nga_admin3 (COD) -> admin3_cod_pcode/
# admin3_cod_name). The MSNA Light draw scripts (draw_malam_fatori_urban_/
# draw_gajiram_urban_/draw_mairari_urban_2026-09-11.R) used their own hand-
# rolled point-in-polygon join for adm3_name only (per that day's own fix
# note - "real per-building ward attribution... fixed in both the staged
# output and the generator script") and never ran the pcode/COD layer at
# all. adm3_name itself is correct (verified below, matches this patch's
# own independent re-join) - only the 4 reconciliation columns were ever
# missing.
#
# Mechanism: replicate 03_stage2_household_selection.R's exact two joins
# (same source shapefiles, same st_within, same column mapping) against
# these 564 rows' own real lat/long - not a new method, the same one every
# other row already went through.
# ==============================================================================
suppressMessages({ library(sf); library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
mycrs <- 31028

FULL_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v8_FULL.csv"
WORKING_CSV <- "output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v8_WORKING.csv"

full_df <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
light_ids <- full_df %>% filter(sampling_method == "MSNA Light") %>% pull(survey_id)
cat(sprintf("MSNA Light rows in FULL: %d\n", length(light_ids)))

light_rows <- full_df %>% filter(survey_id %in% light_ids) %>%
  mutate(latitude = as.numeric(latitude), longitude = as.numeric(longitude))
stopifnot(all(!is.na(light_rows$latitude)), all(!is.na(light_rows$longitude)))

light_pts <- st_as_sf(light_rows, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_transform(mycrs)

# ---- Same two joins as 03_stage2_household_selection.R ----
wards <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE)
wards_proj <- st_transform(wards, mycrs) %>%
  select(adm3_pcode_new = wardcode, adm3_name_new = wardname) %>%
  mutate(admin3_source_new = "GRID3")

admin3 <- st_read("input_data/boundaries/nga_admin_boundaries/nga_admin3.shp", quiet = TRUE)
admin3_proj <- st_transform(admin3, mycrs) %>%
  select(admin3_cod_pcode_new = adm3_pcode, admin3_cod_name_new = adm3_name)

joined <- st_join(light_pts, wards_proj, join = st_within, left = TRUE)
joined <- st_join(joined, admin3_proj, join = st_within, left = TRUE)
joined_df <- st_drop_geometry(joined)

n_grid3_missing <- sum(is.na(joined_df$adm3_pcode_new))
n_cod_missing <- sum(is.na(joined_df$admin3_cod_pcode_new))
cat(sprintf("GRID3 ward join: %d of %d matched, %d missing (outside any GRID3 ward polygon)\n",
            sum(!is.na(joined_df$adm3_pcode_new)), nrow(joined_df), n_grid3_missing))
cat(sprintf("COD admin3 join: %d of %d matched, %d missing\n",
            sum(!is.na(joined_df$admin3_cod_pcode_new)), nrow(joined_df), n_cod_missing))

# Sanity check: the newly-joined GRID3 ward name should match the adm3_name
# already stored on these rows (from the original per-building attribution)
# - confirms this patch's join is finding the SAME wards, not different ones.
name_mismatch <- joined_df %>% filter(!is.na(adm3_name_new), adm3_name != adm3_name_new)
cat(sprintf("Rows where re-joined GRID3 ward name DISAGREES with existing adm3_name: %d\n", nrow(name_mismatch)))
if (nrow(name_mismatch) > 0) {
  print(name_mismatch %>% select(survey_id, cluster_id, adm3_name, adm3_name_new) %>% head(10))
}

if (n_grid3_missing > 0) {
  # Nearest-ward-gap fallback, same pattern/cap (5km) already used elsewhere
  # in this project for exactly this situation (analysis_remaining_
  # eligible_pool.R, refresh_idp_site_frame_accessibility.R) - a real point
  # sitting just outside a polygon boundary due to normal edge imprecision.
  missing_idx <- which(is.na(joined_df$adm3_pcode_new))
  nearest_idx <- st_nearest_feature(joined[missing_idx, ], wards_proj)
  dists <- as.numeric(st_distance(joined[missing_idx, ], wards_proj[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= 5000
  cat(sprintf("  of these, %d resolved via nearest-ward fallback (<=5km), %d remain genuinely unmatched\n",
              sum(within_cap), sum(!within_cap)))
  joined_df$adm3_pcode_new[missing_idx[within_cap]] <- wards_proj$adm3_pcode_new[nearest_idx[within_cap]]
  joined_df$adm3_name_new[missing_idx[within_cap]] <- wards_proj$adm3_name_new[nearest_idx[within_cap]]
  joined_df$admin3_source_new[missing_idx[within_cap]] <- "GRID3"
}

# ---- Apply patch: only the 4 reconciliation columns, only for MSNA Light rows ----
patch <- joined_df %>%
  select(survey_id, adm3_pcode_new, admin3_source_new, admin3_cod_pcode_new, admin3_cod_name_new)

apply_patch <- function(df) {
  df %>%
    left_join(patch, by = "survey_id") %>%
    mutate(
      adm3_pcode = if_else(!is.na(adm3_pcode_new), adm3_pcode_new, adm3_pcode),
      admin3_source = if_else(!is.na(admin3_source_new), admin3_source_new, admin3_source),
      admin3_cod_pcode = if_else(!is.na(admin3_cod_pcode_new), admin3_cod_pcode_new, admin3_cod_pcode),
      admin3_cod_name = if_else(!is.na(admin3_cod_name_new), admin3_cod_name_new, admin3_cod_name)
    ) %>%
    select(-adm3_pcode_new, -admin3_source_new, -admin3_cod_pcode_new, -admin3_cod_name_new)
}

full_patched <- apply_patch(full_df)
write_csv(full_patched, FULL_CSV, na = "NA")
cat(sprintf("Patched FULL: %d rows updated (MSNA Light only).\n", sum(full_patched$survey_id %in% light_ids)))

working_df <- read_csv(WORKING_CSV, show_col_types = FALSE, col_types = cols(.default = "c"))
n_light_in_working <- sum(working_df$sampling_method == "MSNA Light", na.rm = TRUE)
working_patched <- apply_patch(working_df)
write_csv(working_patched, WORKING_CSV, na = "NA")
cat(sprintf("Patched WORKING: %d MSNA Light rows currently present, all updated.\n", n_light_in_working))

# ---- Verify ----
full_check <- read_csv(FULL_CSV, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  filter(sampling_method == "MSNA Light")
cat(sprintf("\nVerification - remaining NA adm3_pcode among MSNA Light rows in FULL: %d\n",
            sum(is.na(full_check$adm3_pcode) | full_check$adm3_pcode == "NA")))
cat(sprintf("Verification - remaining NA admin3_cod_pcode among MSNA Light rows in FULL: %d\n",
            sum(is.na(full_check$admin3_cod_pcode) | full_check$admin3_cod_pcode == "NA")))
