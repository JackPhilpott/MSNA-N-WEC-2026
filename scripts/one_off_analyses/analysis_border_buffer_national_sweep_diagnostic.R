# National sweep: which LGAs lose their ENTIRE IDP stratum to the
# international-border buffer (or FACT inaccessibility), same mechanism
# diagnosed for Sandamu (Katsina) - 2026-08-05 follow-up.
suppressMessages({ library(sf); library(dplyr); library(janitor); library(here) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
mycrs <- 31028
data_dir <- here("input_data")
population_dir <- here(data_dir, "population")
boundaries_dir <- here(data_dir, "boundaries")

nga_admin1_pcodes_nw <- c("NG019", "NG020", "NG021", "NG022", "NG034", "NG037")
nga_admin1_pcodes_ne <- c("NG002", "NG008", "NG036")
nga_admin1_pcodes_nc <- c("NG007", "NG023", "NG026", "NG027", "NG032")
admin1_focus_areas <- c(nga_admin1_pcodes_nc, nga_admin1_pcodes_ne, nga_admin1_pcodes_nw)

process_spatial_layer <- function(df) {
  df %>% filter(adm1_pcode %in% admin1_focus_areas) %>%
    mutate(region = case_when(
      adm1_pcode %in% nga_admin1_pcodes_nc ~ "NC", adm1_pcode %in% nga_admin1_pcodes_ne ~ "NE",
      adm1_pcode %in% nga_admin1_pcodes_nw ~ "NW", TRUE ~ "not included area")) %>%
    select(where(~ !all(is.na(.))))
}
prep_geom <- function(x) x |> st_transform(mycrs) |> st_make_valid()
classify_idp_population_category <- function(x) {
  x_clean <- trimws(tolower(x))
  dplyr::case_when(
    x_clean == "idps in camps" ~ "idps in camp",
    x_clean %in% c("idps dispersed in host communities", "idps in host communities",
                   "idps integrated", "idps in integrated sites",
                   "idps relocated", "idps in relocated sites") ~ "idps in host",
    TRUE ~ NA_character_
  )
}

## ---- boundaries ----
admin0_wa_bnds <- st_read(here(boundaries_dir, "wca_admbnda_adm0_edgematched_942026", "wca_admbnda_adm0_edgematched.shp"), quiet = TRUE)
admin0_wa_proj <- st_transform(admin0_wa_bnds, mycrs)

admin1_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin1.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin1 <- process_spatial_layer(admin1_raw)
admin2_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin2.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin2 <- process_spatial_layer(admin2_raw)
admin3_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin3.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin3 <- process_spatial_layer(admin3_raw) %>% mutate(uuid = paste(adm1_name, adm2_name, adm3_name, sep = "_"))

FACT_accessibility <- read.csv(here(boundaries_dir, "nga_accessibility", "NGA_Sampling_accessibility_FACT_admin3_NE.csv")) %>%
  clean_names() %>% remove_empty(which = c("rows","cols")) %>%
  mutate(uuid = paste(state, lga, ward_community, sep = "_")) %>% distinct()
FACT_noaccess <- FACT_accessibility %>% filter(accessibility_status %in% c("Not Existing", "Inaccessible"))
admin3_noaccess <- admin3 %>% filter(uuid %in% FACT_noaccess$uuid)

admin0_cast <- st_cast(admin0_wa_proj, to = "MULTILINESTRING")
admin0_wa_buff <- admin0_cast %>%
  mutate(buffer_m = case_when(adm0_name %in% c("Chad","Cameroon","Benin") ~ 5000, adm0_name == "Niger" ~ 20000, TRUE ~ NA_real_)) %>%
  filter(!is.na(buffer_m))
nga_buffered <- st_buffer(admin0_wa_buff, dist = admin0_wa_buff$buffer_m)

clip_noaccess <- prep_geom(admin3_noaccess)
clip_buffered <- prep_geom(nga_buffered)
noaccess_union <- st_union(clip_noaccess)
buffered_union <- st_union(clip_buffered)
cat("Boundary/buffer layers built.\n")

## ---- raw DTM points, all regions, non-returnee IDP only ----
iom_dir <- here(population_dir, "iom")
iom_idp_files <- list.files(path = iom_dir, pattern = "\\.csv$", full.names = TRUE)

iom_idp_NE <- read.csv(iom_idp_files[grepl("NE", iom_idp_files)][1])
idp_NE_clean <- iom_idp_NE %>% clean_names() %>% remove_empty(which = c("rows","cols")) %>% distinct() %>%
  filter(location_type == "IDP Location") %>%
  mutate(idp_population_category = classify_idp_population_category(population_category)) %>%
  rename(adm1_pcode = state_pcode, adm1_name = state, adm2_name = lga, adm2_pcode = lga_pcode,
         pop = individuals, pop_hh = households)
idp_NE_sf <- st_as_sf(idp_NE_clean, coords = c("longitude_e","latitude_n"), crs = 4326, remove = FALSE) %>% st_transform(mycrs)

iom_idp_NCNW <- read.csv(iom_idp_files[grepl("NCNW", iom_idp_files)][1])
idp_NCNW_clean <- iom_idp_NCNW %>% clean_names() %>% remove_empty(which = c("rows","cols")) %>% distinct() %>%
  mutate(location_type = case_when(population_category == "Returnees" ~ "Returnee Location", TRUE ~ "IDP Location")) %>%
  filter(location_type == "IDP Location") %>%
  mutate(idp_population_category = classify_idp_population_category(population_category))
idp_NCNW_sf <- st_as_sf(idp_NCNW_clean, coords = c("longitude_e","latitude_n"), crs = 4326, remove = FALSE) %>% st_transform(mycrs)
idp_NCNW_joined <- st_join(idp_NCNW_sf, admin2, join = st_within) %>% filter(!is.na(region)) %>%
  rename(pop = individuals, pop_hh = households)

# NE file already carries its own adm2_pcode/name/region from source - drop all
# of admin2's own attribute names before the join so there's no .x/.y suffixing,
# then re-derive adm2_pcode/name/region purely from the spatial join (same
# authoritative source as the NCNW path) for a clean, consistent comparison.
idp_NE_joined <- st_join(
  idp_NE_sf %>% select(-any_of(c("adm2_pcode", "adm2_name", "region", "adm1_pcode", "adm1_name"))),
  admin2,
  join = st_within
) %>% filter(!is.na(region))

cat("NE joined cols:", paste(names(idp_NE_joined), collapse=", "), "\n")
cat("NCNW joined cols:", paste(names(idp_NCNW_joined), collapse=", "), "\n")

common_cols <- intersect(names(idp_NE_joined), names(idp_NCNW_joined))
all_idp_pts <- bind_rows(
  idp_NE_joined %>% select(all_of(common_cols)),
  idp_NCNW_joined %>% select(all_of(common_cols))
)
if (!inherits(all_idp_pts, "sf")) all_idp_pts <- st_as_sf(all_idp_pts)

all_idp_pts <- all_idp_pts %>%
  mutate(pop_hh = suppressWarnings(as.numeric(pop_hh)))

cat("\nTotal non-returnee IDP DTM points nationally (in-scope states):", nrow(all_idp_pts), "\n")

## ---- per-LGA: is EVERY point inside the restricted zone? ----
restricted <- st_union(noaccess_union, buffered_union) %>% st_make_valid()
in_border_buffer <- st_intersects(all_idp_pts, buffered_union, sparse = FALSE)[,1]
in_fact_noaccess <- st_intersects(all_idp_pts, noaccess_union, sparse = FALSE)[,1]
in_restricted <- in_border_buffer | in_fact_noaccess

all_idp_pts <- all_idp_pts %>%
  mutate(in_border_buffer = in_border_buffer, in_fact_noaccess = in_fact_noaccess, in_restricted = in_restricted)

lga_summary <- all_idp_pts %>%
  st_drop_geometry() %>%
  group_by(adm1_name, adm2_name, adm2_pcode, region) %>%
  summarise(
    n_sites = n(),
    n_households = sum(pop_hh, na.rm = TRUE),
    n_in_restricted = sum(in_restricted),
    n_in_border_buffer = sum(in_border_buffer),
    n_in_fact_noaccess = sum(in_fact_noaccess),
    all_sites_restricted = all(in_restricted),
    .groups = "drop"
  ) %>%
  arrange(desc(all_sites_restricted), desc(n_households))

cat("\nLGAs where EVERY recorded non-returnee IDP site falls inside the restricted zone (border buffer and/or FACT-inaccessible):\n")
fully_lost <- lga_summary %>% filter(all_sites_restricted)
print(as.data.frame(fully_lost))
cat("\nCount:", nrow(fully_lost), "LGAs, total sites:", sum(fully_lost$n_sites), "total DTM households:", sum(fully_lost$n_households), "\n")

cat("\nBreakdown by cause (LGAs may be in both if some points hit one cause, some the other, but all points restricted overall):\n")
cat("  All-restricted purely via border buffer:", sum(fully_lost$n_in_border_buffer == fully_lost$n_sites), "\n")
cat("  All-restricted purely via FACT inaccessible:", sum(fully_lost$n_in_fact_noaccess == fully_lost$n_sites), "\n")
cat("  Mixed (some via buffer, some via FACT, all restricted):",
    sum(fully_lost$n_in_border_buffer < fully_lost$n_sites & fully_lost$n_in_fact_noaccess < fully_lost$n_sites), "\n")

## ---- cross-check against the actual delivered strata frame: which of these LGAs genuinely have 0 IDP rows? ----
strata <- read.csv(here("_archive", "2026-08-04_design_frame_pre_coverage", "strata_level_sampling_frame.csv"))
idp_strata_pcodes <- strata %>% filter(pop_type == "idp") %>% pull(adm2_pcode)

fully_lost <- fully_lost %>% mutate(confirmed_zero_idp_stratum_in_frame = !(adm2_pcode %in% idp_strata_pcodes))
cat("\nOf these, how many are confirmed to have ZERO idp stratum row in the actual delivered strata_level_sampling_frame.csv:\n")
print(table(fully_lost$confirmed_zero_idp_stratum_in_frame))

cat("\nFull detail:\n")
print(as.data.frame(fully_lost %>% select(adm1_name, adm2_name, region, n_sites, n_households, n_in_border_buffer, n_in_fact_noaccess, confirmed_zero_idp_stratum_in_frame)))

## ---- also: LGAs with SOME but not all sites restricted (partial loss, worth knowing but not total loss) ----
partial <- lga_summary %>% filter(!all_sites_restricted, n_in_restricted > 0)
cat("\n\nLGAs with PARTIAL restriction (some sites lost, some survive) - not the main ask but noted:\n")
print(as.data.frame(partial %>% select(adm1_name, adm2_name, region, n_sites, n_in_restricted, n_households)))
