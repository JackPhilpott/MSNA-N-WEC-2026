# Step 2: for the 51 border-sensitive LGAs, recompute accessible hex grid +
# population (Non-IDP WorldPop, IDP DTM) under 3 buffer scenarios:
#   S1 = current (Niger 20km, Chad/Cameroon/Benin 5km)
#   S2 = 5km on all 4 international borders
#   S3 = no international-border buffer at all (0km)
# FACT admin3 inaccessibility exclusion is held constant across all 3 -
# only the country-border buffer distance changes, per the user's ask.
suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr)
  library(janitor); library(here); library(purrr)
})
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

affected_pcodes <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/affected_adm2_pcodes.rds")
admin0_cast <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/admin0_cast_4countries.rds")
admin2 <- readRDS("C:/Users/JACKPH~1/AppData/Local/Temp/claude/admin2_focus.rds")

cat("Affected LGAs:", length(affected_pcodes), "\n")

## ---- admin1 (needed for accessible_area = admin1 - restricted) ----
admin1_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin1.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin1 <- process_spatial_layer(admin1_raw)

## ---- FACT inaccessibility (held constant across scenarios) ----
admin3_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin3.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin3 <- process_spatial_layer(admin3_raw) %>% mutate(uuid = paste(adm1_name, adm2_name, adm3_name, sep = "_"))
FACT_accessibility <- read.csv(here(boundaries_dir, "nga_accessibility", "NGA_Sampling_accessibility_FACT_admin3_NE.csv")) %>%
  clean_names() %>% remove_empty(which = c("rows","cols")) %>%
  mutate(uuid = paste(state, lga, ward_community, sep = "_")) %>% distinct()
FACT_noaccess <- FACT_accessibility %>% filter(accessibility_status %in% c("Not Existing", "Inaccessible"))
admin3_noaccess <- admin3 %>% filter(uuid %in% FACT_noaccess$uuid)
noaccess_union <- st_union(prep_geom(admin3_noaccess))

## ---- bound_hex_clip, subset to affected LGAs only ----
bound_hex_clip_all <- readRDS(here(boundaries_dir, "nga_hexagons", "hexa_by_admin2.rds"))
bound_hex_affected <- bound_hex_clip_all %>% filter(adm2_pcode %in% affected_pcodes)
cat("Hexes (pre-accessibility-clip) in affected LGAs:", nrow(bound_hex_affected), "\n")

admin1_affected <- admin1 %>% filter(adm1_pcode %in% unique(bound_hex_affected$adm1_pcode))

## ---- population sources ----
worldpop_pop <- readRDS(here(population_dir, "worldpop", "worldpop_nga_2026_projected.rds"))

iom_idp_files <- list.files(path = here(population_dir, "iom"), pattern = "\\.csv$", full.names = TRUE)
iom_idp_NE <- read.csv(iom_idp_files[grepl("NE", iom_idp_files)][1])
idp_NE_clean <- iom_idp_NE %>% clean_names() %>% remove_empty(which = c("rows","cols")) %>% distinct() %>%
  mutate(region = "NE") %>% filter(location_type == "IDP Location") %>%
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
idp_NE_joined <- st_join(idp_NE_sf %>% select(-any_of(c("adm2_pcode","adm2_name","region","adm1_pcode","adm1_name"))),
                          admin2, join = st_within) %>% filter(!is.na(region))
common_cols <- intersect(names(idp_NE_joined), names(idp_NCNW_joined))
iom_idp_df <- bind_rows(idp_NE_joined %>% select(all_of(common_cols)), idp_NCNW_joined %>% select(all_of(common_cols)))
if (!inherits(iom_idp_df, "sf")) iom_idp_df <- st_as_sf(iom_idp_df)
iom_idp_df <- iom_idp_df %>% mutate(individuals = suppressWarnings(as.numeric(pop)), households = suppressWarnings(as.numeric(pop_hh)))
iom_idp_df_affected <- iom_idp_df %>% filter(adm2_pcode %in% affected_pcodes)
cat("DTM IDP points (non-returnee) in affected LGAs:", nrow(iom_idp_df_affected), "\n")

## ---- build_population_by_hex (verbatim from 01_sampling_pipeline_main.R) ----
build_population_by_hex <- function(hex_access, source = c("non_idp","idp"), worldpop_pop = NULL, iom_idp_df = NULL, hh_size = 6, min_hh = 5) {
  source <- match.arg(source)
  hex_access |> group_split(region) |> purrr::map(function(region_df) {
    if (source == "non_idp") {
      out <- region_df |> group_split(adm2_pcode) |> purrr::map(function(adm_df) {
        adm_df |> mutate(pop = exactextractr::exact_extract(worldpop_pop, adm_df, "sum"), pop_hh = pop / hh_size)
      }) |> bind_rows()
    } else if (source == "idp") {
      hex_counts <- sf::st_join(iom_idp_df, region_df) |> sf::st_drop_geometry() |>
        group_by(uuid_hex) |> summarise(pop = sum(pop, na.rm = TRUE), pop_hh = sum(pop_hh, na.rm = TRUE), .groups = "drop")
      out <- region_df |> left_join(hex_counts, by = "uuid_hex") |> mutate(pop = coalesce(pop, 0), pop_hh = coalesce(pop_hh, 0))
    }
    out |> mutate(pop = as.numeric(pop), pop_hh = as.numeric(pop_hh),
                  estimated_households = round(pop_hh / hh_size) * hh_size,
                  pop_type = source, uuid_hex_pop = paste0(source, "_", uuid_hex)) |>
      filter(pop_hh > min_hh) |> arrange(uuid_hex) |>
      select(uuid_hex_pop, uuid_hex, pop_type, adm0_name, region, adm1_name, adm1_pcode, adm2_name, adm2_pcode, uuid, pop, pop_hh, estimated_households, geometry)
  }) |> bind_rows()
}

## ---- run all 3 scenarios for the affected-LGA subset ----
scenarios <- list(
  S1_current = c(Niger = 20000, Chad = 5000, Cameroon = 5000, Benin = 5000),
  S2_5km_all = c(Niger = 5000, Chad = 5000, Cameroon = 5000, Benin = 5000),
  S3_no_buffer = c(Niger = 0, Chad = 0, Cameroon = 0, Benin = 0)
)

results_non_idp <- list()
results_idp <- list()

for (scen_name in names(scenarios)) {
  bufs <- scenarios[[scen_name]]
  cat("\n=== Scenario:", scen_name, "===\n")

  admin0_wa_buff <- admin0_cast %>% mutate(buffer_m = bufs[adm0_name]) %>% filter(buffer_m > 0)
  if (nrow(admin0_wa_buff) > 0) {
    nga_buffered <- st_buffer(admin0_wa_buff, dist = admin0_wa_buff$buffer_m)
    buffered_union <- st_union(prep_geom(nga_buffered))
    restricted <- st_union(noaccess_union, buffered_union) %>% st_make_valid()
  } else {
    restricted <- noaccess_union %>% st_make_valid()
  }

  accessible_area <- st_difference(admin1_affected, restricted) %>% st_make_valid()

  hex_access_scen <- st_intersection(st_make_valid(bound_hex_affected), st_make_valid(accessible_area)) |>
    st_collection_extract("POLYGON") |> filter(!st_is_empty(geometry))
  cat("Accessible hexes in affected LGAs:", nrow(hex_access_scen), "\n")

  non_idp_scen <- build_population_by_hex(hex_access_scen, source = "non_idp", worldpop_pop = worldpop_pop)
  idp_scen <- build_population_by_hex(hex_access_scen, source = "idp", iom_idp_df = iom_idp_df_affected)

  cat("Non-IDP hexes w/ pop:", nrow(non_idp_scen), " | Total N_hh:", sum(non_idp_scen$pop_hh), "\n")
  cat("IDP hexes w/ pop:", nrow(idp_scen), " | Total N_hh:", sum(idp_scen$pop_hh), "\n")

  results_non_idp[[scen_name]] <- non_idp_scen %>% st_drop_geometry() %>% mutate(scenario = scen_name)
  results_idp[[scen_name]] <- idp_scen %>% st_drop_geometry() %>% mutate(scenario = scen_name)
}

saveRDS(results_non_idp, "C:/Users/JACKPH~1/AppData/Local/Temp/claude/scenario_non_idp_affected.rds")
saveRDS(results_idp, "C:/Users/JACKPH~1/AppData/Local/Temp/claude/scenario_idp_affected.rds")
cat("\n\nSaved per-scenario affected-LGA hex population results.\n")
