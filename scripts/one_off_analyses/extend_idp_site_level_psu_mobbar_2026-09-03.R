# ==============================================================================
# Extends idp_site_level_psu_frame_2026-09-02.rds with Mobbar's 10 real DTM
# IDP sites (Damasak + Zanna Umorti wards) - these were never in the
# candidate frame at all, since build_idp_site_level_psu_2026-09-02.R's own
# Step 3 restricts to Stage-1's accessible/border-buffer mask, and these two
# wards sit entirely inside the 20km Niger buffer (confirmed zero hex
# intersection). Per Jack's 2026-09-03 decision: FHI 360 (a willing,
# on-ground-confirmed partner) can now cover these two specific wards, so
# their real DTM population is added as genuine new candidate sites in the
# SAME canonical frame every future site-level IDP draw reads from - not a
# one-off side file - exactly matching "use the updated IDP cluster drawing
# mechanism" per Jack's own instruction.
#
# FACT's own ward-accessibility file independently rates both wards + the
# specific communities within them "Fully Accessible" (checked directly,
# 2026-09-03) - corroborates this was a blanket buffer exclusion, not a
# security judgement on these places specifically.
#
# Backs up the pre-extension frame before writing, since every future
# national IDP draw reads this file - see the existing IDP site-level PSU
# mechanism's own header comment for why (Option B, decided 2026-09-02).
# ==============================================================================
suppressMessages({
  library(dplyr); library(sf); library(readr); library(janitor)
})
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
sf::sf_use_s2(FALSE)
mycrs <- 31028

classify_idp_population_category <- function(x) {
  x_clean <- trimws(tolower(x))
  dplyr::case_when(
    x_clean == "idps in camps" ~ "idps in camp",
    x_clean %in% c(
      "idps dispersed in host communities", "idps in host communities",
      "idps integrated", "idps in integrated sites",
      "idps relocated", "idps in relocated sites"
    ) ~ "idps in host",
    TRUE ~ NA_character_
  )
}

# ---- 1. Load existing candidate frame + back it up ----
FRAME_PATH <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds"
BACKUP_PATH <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02_PRE_MOBBAR_backup_2026-09-03.rds"
site_frame <- readRDS(FRAME_PATH)
if (!file.exists(BACKUP_PATH)) {
  saveRDS(site_frame, BACKUP_PATH)
  cat("Backup written:", BACKUP_PATH, "\n")
}
cat("Existing candidate frame:", nrow(site_frame), "sites nationally.\n")
n_before_mobbar <- sum(site_frame$adm2_name == "Mobbar", na.rm = TRUE)
cat("Existing Mobbar sites in frame (should be 0):", n_before_mobbar, "\n")

# ---- 2. Rebuild Mobbar's 10 sites, EXACT same logic as build_idp_site_level_psu_2026-09-02.R ----
ne_file <- "input_data/population/iom/IMPACT_IOM_NGA_R51_NE.csv"
idp_NE_clean <- read.csv(ne_file) %>%
  clean_names() %>% remove_empty(which = c("rows", "cols")) %>% distinct() %>%
  mutate(region = "NE") %>%
  filter(location_type == "IDP Location") %>%
  mutate(idp_population_category = classify_idp_population_category(population_category)) %>%
  rename(adm1_pcode = state_pcode, adm1_name = state, adm2_name = lga, adm2_pcode = lga_pcode,
         pop = individuals, pop_hh = households, site_id_ssid = site_id_ssid, site_name = site_name,
         site_type = site_type, ward = ward, lat = latitude_n, lon = longitude_e)

mob_sites_raw <- idp_NE_clean %>%
  filter(adm2_name == "Mobbar", ward %in% c("Damasak", "Zanna Umorti")) %>%
  filter(!is.na(idp_population_category), !is.na(lat), !is.na(lon), !is.na(pop_hh), pop_hh > 0)

cat("\nMobbar candidate sites (Damasak + Zanna Umorti), pre-filter:", nrow(mob_sites_raw), "\n")

mob_sites_sf <- st_as_sf(mob_sites_raw, coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>%
  st_transform(mycrs)

# Dedup check (30m radius, same method/threshold as the national build) -
# verified directly 2026-09-03: min pairwise distance among these 10 sites
# is 386.7m, so no dedup collapsing occurs - kept as a real, fail-loud check
# rather than assumed, in case the source data changes on a future rerun.
d <- st_distance(mob_sites_sf); diag(d) <- NA
min_dist <- min(as.numeric(d), na.rm = TRUE)
cat("Min pairwise distance among Mobbar candidate sites (m):", round(min_dist, 1), "\n")
if (min_dist < 30) stop("Sites within 30m of each other found - dedup logic needed, do not proceed without it.")

mob_sites_final <- mob_sites_sf %>%
  mutate(
    uuid = paste0("site_mobbar_", row_number()),
    uuid_site = paste(region, adm1_name, adm2_name, uuid, sep = "_"),
    pop_type = "idp",
    uuid_site_pop = paste0(pop_type, "_", uuid_site),
    estimated_households = round(pop_hh / 6) * 6,
    adm0_name = "Nigeria",
    # The raw DTM file's own lga_pcode uses a 9-char "NGA..." convention
    # (e.g. "NGA008023") - this project's frame uses 8-char "NG..."
    # throughout (confirmed against the live strata/cluster_id CSVs:
    # Mobbar = "NG008023"). Every other site in this candidate frame gets
    # this from the hex_mask spatial join in build_idp_site_level_psu_
    # 2026-09-02.R (which silently overwrites the raw DTM pcode with the
    # canonical one) - these 10 rows skip that join (never intersected
    # hex_mask, being border-buffer-excluded), so it must be corrected
    # explicitly here instead. Caught 2026-09-03 on the first draw attempt:
    # the mismatch silently zeroed the candidate pool via the shortfalls
    # adm2_pcode join, not any real accessibility/distance problem.
    adm1_pcode = sub("^NGA", "NG", adm1_pcode),
    adm2_pcode = sub("^NGA", "NG", adm2_pcode)
  ) %>%
  filter(pop_hh > 5) %>%
  # FACT's own ward-accessibility file rates both wards + the named
  # communities within them "Fully Accessible" (checked directly,
  # 2026-09-03) - this is the source of the value, not the border-buffer
  # mechanism, which never evaluated these specific places on their merits.
  mutate(accessible_status = "Accessible") %>%
  select(uuid_site_pop, uuid_site, pop_type, adm0_name, region, adm1_name, adm1_pcode,
         adm2_name, adm2_pcode, site_id_ssid, site_name, site_type, ward,
         idp_population_category, pop, pop_hh, estimated_households, accessible_status, geometry)

cat("\nFinal Mobbar site-level PSU candidates:", nrow(mob_sites_final), "sites,",
    sum(mob_sites_final$pop_hh), "total households,", sum(mob_sites_final$pop), "total individuals.\n")
print(st_drop_geometry(mob_sites_final) %>% select(ward, site_name, pop, pop_hh, accessible_status))

# ---- 3. Schema check + append ----
missing_in_new <- setdiff(names(site_frame), names(mob_sites_final))
missing_in_old <- setdiff(names(mob_sites_final), names(site_frame))
if (length(missing_in_new) > 0) stop("New Mobbar rows missing column(s) present in the national frame: ", paste(missing_in_new, collapse = ", "))
if (length(missing_in_old) > 0) stop("National frame missing column(s) present in the new Mobbar rows: ", paste(missing_in_old, collapse = ", "))

site_frame_extended <- bind_rows(site_frame, mob_sites_final %>% select(names(site_frame)))
if (anyDuplicated(site_frame_extended$uuid_site_pop) > 0) stop("Duplicate uuid_site_pop after extension.")
cat("\nExtended candidate frame:", nrow(site_frame), "->", nrow(site_frame_extended), "rows.\n")

saveRDS(site_frame_extended, FRAME_PATH)
st_write(site_frame_extended, "resampling/output/gis/idp_site_level_psu_frame_2026-09-02.gpkg", delete_layer = TRUE, quiet = TRUE)
cat("Saved extended frame:", FRAME_PATH, "\n")
