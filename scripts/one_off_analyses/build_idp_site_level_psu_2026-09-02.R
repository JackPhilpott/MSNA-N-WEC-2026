# ==============================================================================
# IDP site-level PSU frame — Option B from the 2026-09-02 IDP hex-mechanism
# review (see project memory "IDP site-level PSU redesign" / the published
# "The IDP Hex Problem" artifact for full background).
#
# Replaces build_population_by_hex(source="idp") for all NEW IDP draws going
# forward: the PSU (primary sampling unit) becomes the individual, deduped
# DTM site itself, PPS-weighted by its own household count — not a shared
# 5km hex that silently collapses several real sites down to whichever one
# happens to be largest. Non-IDP is completely untouched (still hex-based,
# which is correct there — WorldPop is a continuous raster, not discrete
# points, so a hex genuinely is the right PSU shape for it).
#
# Does NOT touch any already-fielded cluster. This produces a fresh
# candidate-site frame to draw NEW/replacement IDP clusters from, going
# forward from 2026-09-02 - the live v4 FULL/WORKING frame's existing IDP
# rows (all hex-based) are left exactly as they are.
# ==============================================================================
suppressMessages({
  library(dplyr); library(sf); library(readr); library(janitor)
})

PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
sf::sf_use_s2(FALSE)
mycrs <- 31028  # same as 01_sampling_pipeline_main.R line 215

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

# ---- 1. Load raw DTM sites, exactly as the pipeline does (01_sampling_pipeline_main.R lines ~349-414) ----
iom_idp_files <- list.files(path = file.path("input_data", "population", "iom"), pattern = "\\.csv$", full.names = TRUE)
ne_file <- grep("_NE\\.csv$", iom_idp_files, value = TRUE)
ncnw_file <- grep("NCNW", iom_idp_files, value = TRUE)

idp_NE_clean <- read.csv(ne_file) %>%
  clean_names() %>% remove_empty(which = c("rows", "cols")) %>% distinct() %>%
  mutate(region = "NE") %>%
  filter(location_type == "IDP Location") %>%
  mutate(idp_population_category = classify_idp_population_category(population_category)) %>%
  rename(adm1_pcode = state_pcode, adm1_name = state, adm2_name = lga, adm2_pcode = lga_pcode,
         pop = individuals, pop_hh = households, site_id_ssid = site_id_ssid, site_name = site_name,
         site_type = site_type, ward = ward, lat = latitude_n, lon = longitude_e)

idp_NCNW_clean <- read.csv(ncnw_file) %>%
  clean_names() %>% remove_empty(which = c("rows", "cols")) %>% distinct() %>%
  mutate(region = "NCNW") %>%
  mutate(idp_population_category = classify_idp_population_category(population_category)) %>%
  rename(adm2_name = lga, pop = individuals, pop_hh = households,
         site_id_ssid = site_id_ssid, site_name = site_name, site_type = site_type, ward = ward,
         lat = latitude_n, lon = longitude_e) %>%
  mutate(pop = suppressWarnings(as.numeric(pop)), pop_hh = suppressWarnings(as.numeric(pop_hh)))

common <- c("region", "adm2_name", "site_id_ssid", "site_name", "site_type", "ward",
            "idp_population_category", "pop", "pop_hh", "lat", "lon")
sites_raw <- bind_rows(
  idp_NE_clean %>% select(any_of(common)),
  idp_NCNW_clean %>% select(any_of(common))
) %>%
  filter(!is.na(idp_population_category), !is.na(lat), !is.na(lon), !is.na(pop_hh), pop_hh > 0)

cat("Eligible (non-returnee) DTM site records nationally:", nrow(sites_raw), "\n")

sites_sf <- st_as_sf(sites_raw, coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>% st_transform(mycrs)

# ---- 2. Dedup within 30m — identical method/radius to select_stage2_idp_sites() Step A ----
sites_buffered <- st_buffer(sites_sf, 15)
dedup_groups <- st_union(sites_buffered) %>% st_cast("POLYGON") %>% st_sf(dedup_group_id = seq_along(.), geometry = .)
sites_grouped <- st_join(sites_sf, dedup_groups, join = st_within)
sites_deduped <- sites_grouped %>%
  group_by(dedup_group_id) %>%
  mutate(group_pop_hh = sum(pop_hh, na.rm = TRUE), group_pop = sum(pop, na.rm = TRUE)) %>%
  slice_max(pop_hh, n = 1, with_ties = FALSE) %>% ungroup() %>%
  mutate(pop_hh = group_pop_hh, pop = group_pop) %>%
  select(-group_pop_hh, -group_pop)
cat(nrow(sites_sf) - nrow(sites_deduped), "duplicate record(s) merged within 30m.", nrow(sites_deduped), "distinct sites remain.\n")

# ---- 3. Restrict to Stage-1's accessible/border-buffer area, attach adm1/adm2 attribution ----
# Reuses the already-built, already-current national hex layer purely as a
# spatial mask (hex_access = hex ∩ accessible_area, so "falls inside some
# hex_access polygon" == "falls inside the accessible area") - avoids
# re-running the international-buffer/FACT-inaccessible-area construction
# (01_sampling_pipeline_main.R section 4) just to get a polygon this script
# only needs as a yes/no spatial filter. hex geometry itself is NOT used as
# a PSU here - purely a stand-in for "is this site in the eligible area,
# and which adm1/adm2 does it belong to."
hex_mask <- readRDS("input_data/boundaries/nga_hexagons/accessible_hex.rds") %>%
  st_transform(mycrs) %>%
  select(adm0_name, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode)

sites_attributed <- st_join(sites_deduped %>% select(-adm2_name, -region), hex_mask, join = st_within)
n_outside <- sum(is.na(sites_attributed$adm2_pcode))
cat(n_outside, "of", nrow(sites_attributed), "site(s) fall outside the Stage-1 accessible/border-buffer area - excluded (expected: e.g. Kano's already-excluded IDP strata, sites beyond the international buffer).\n")
sites_attributed <- sites_attributed %>% filter(!is.na(adm2_pcode))

# ---- 4. Build the final site-level PSU frame ----
idp_site_frame <- sites_attributed %>%
  mutate(
    uuid = paste0("site_", row_number()),
    uuid_site = paste(region, adm1_name, adm2_name, uuid, sep = "_"),
    pop_type = "idp",
    uuid_site_pop = paste0(pop_type, "_", uuid_site),
    estimated_households = round(pop_hh / 6) * 6
  ) %>%
  filter(pop_hh > 5) %>%  # same min_hh=5 threshold as build_population_by_hex()
  select(uuid_site_pop, uuid_site, pop_type, adm0_name, region, adm1_name, adm1_pcode,
         adm2_name, adm2_pcode, site_id_ssid, site_name, site_type, ward,
         idp_population_category, pop, pop_hh, estimated_households, geometry)

cat("\nFinal IDP site-level PSU candidate frame:", nrow(idp_site_frame), "rows (sites), across",
    n_distinct(idp_site_frame$adm2_pcode), "LGAs.\n")
cat("Total candidate population (individuals):", sum(idp_site_frame$pop), " | households:", sum(idp_site_frame$pop_hh), "\n")

# ---- 5. Attach ward accessibility status directly (so downstream draw scripts don't need a separate join) ----
ward_acc <- read_csv("resampling/output/gis/accessible_area_lga_ward_portions.csv", show_col_types = FALSE) %>%
  filter(pop_type == "IDP") %>%
  transmute(adm2_pcode, wardname, accessible_status)

# Match on (adm2_pcode, ward) - DTM's own ward field, same known caveat as
# everywhere else in this project (GRID3 vs DTM ward-name mismatches, e.g.
# Funtua's "Maska"/"Nasarawa") - matches on adm2_pcode + exact ward name;
# unmatched wards default to the same "Accessible" fallback the rest of the
# accessibility pipeline uses for a genuinely unreported/unmatched case.
idp_site_frame <- idp_site_frame %>%
  left_join(ward_acc, by = c("adm2_pcode", "ward" = "wardname")) %>%
  mutate(accessible_status = coalesce(accessible_status, "Accessible"))
n_unmatched_ward <- sum(is.na(idp_site_frame$accessible_status) | idp_site_frame$accessible_status == "Accessible" & !idp_site_frame$ward %in% ward_acc$wardname[ward_acc$adm2_pcode %in% idp_site_frame$adm2_pcode])

cat("Sites with a directly-matched ward-accessibility row:", sum(idp_site_frame$ward %in% ward_acc$wardname), "of", nrow(idp_site_frame), "\n")
cat("accessible_status breakdown:\n")
print(table(idp_site_frame$accessible_status, useNA = "ifany"))

saveRDS(idp_site_frame, "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds")
st_write(idp_site_frame, "resampling/output/gis/idp_site_level_psu_frame_2026-09-02.gpkg", delete_layer = TRUE, quiet = TRUE)
cat("\nSaved: input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds\n")
cat("Saved: resampling/output/gis/idp_site_level_psu_frame_2026-09-02.gpkg\n")
