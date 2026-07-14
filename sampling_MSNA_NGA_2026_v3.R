## NIGERIA SAMPLING FOR MSNA NORTH-WEST/EAST/CENTRAL 2026 ## 
# this script is developed to the sampling framework for the 2026 MSNA project in the North-West/East/Central of Nigeria
# the script is following the IMPACT global research design guidelines (Annex 5) for GIS sampling guidance
# produced by Jack Philpott (NGA MSNA SAO) - 24/06/2026

# library(ggthemes)
# library(leaflet)
# library(plotly)
# library(shapefiles)
# library(stars)

library(sf)
library(terra)
library(dplyr)
library(ggplot2)
library(ggrepel)
library(tidyterra)
library(janitor)
library(exactextractr)
library(patchwork)
library(uuid)
library(here)
library(readr)
library(purrr)
library(ggspatial)
library(sampling)

source("global_sampling_source.R") #sampling methods from Olivier Cecchi

## ---- 1. set global environment ---- 

# set a few standard directories to use later
data_dir       <- here("input_data")
population_dir <- here(data_dir, "population")
boundaries_dir <- here(data_dir, "boundaries")
output_dir     <- here("output")

# set an optio to overwrite the files already produced - this helps with processing
opt_list <- list(
  rebuild_population = FALSE,
  rebuild_hex = FALSE,
  rebuild_hex_intersection = FALSE,
  rebuild_sampling = FALSE,
  rebuild_pophex_host = FALSE,
  rebuild_pophex_idp = FALSE
)

# create a few functions to be repeated throughout 

cache_rds <- function(file, expr, rebuild = FALSE) {
  
  # Return cached object if it already exists
  if (file.exists(file) && !isTRUE(rebuild)) {
    message("Loading cached object: ", basename(file))
    return(readRDS(file))
  }
  
  # Evaluate processing pipeline
  obj <- expr()
  
  # Ensure output directory exists
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  
  saveRDS(obj, file)
  
  message("Saved cache: ", basename(file))
  
  obj
}

# Function to safely load one shapefile
safe_load <- function(path) {
  tryCatch({
    if (!file.exists(path)) {
      stop(paste("File not found:", path))
    }
    
    shp <- st_read(path, quiet = TRUE)
    
    if (is.null(st_crs(shp))) {
      stop(paste("CRS is missing for:", path))
    }
    
    return(shp)
    
  }, error = function(e) {
    message("Error loading ", path, ": ", e$message)
    return(NULL)
  })
}

# Function to safely transform an sf object
safe_transform <- function(sf_obj, target_crs) {
  tryCatch({
    st_transform(sf_obj, target_crs)
  }, error = function(e) {
    message("Error transforming layer: ", e$message)
    return(NULL)
  })
}

# Function to clean and attribute spatial layers
process_spatial_layer <- function(df) {
  df %>%
    filter(adm1_pcode %in% admin1_focus_areas) %>%
    mutate(
      region = case_when(
        adm1_pcode %in% nga_admin1_pcodes_nc ~ "NC",
        adm1_pcode %in% nga_admin1_pcodes_ne ~ "NE",
        adm1_pcode %in% nga_admin1_pcodes_nw ~ "NW",
        TRUE ~ "not included area"
      )
    ) %>%
    select(where(~ !all(is.na(.)))) # remove columns that are all NA
}

prep_geom <- function(x){
  
  x |>
    st_transform(mycrs) |>
    st_make_valid()
}

load_population <- function(tif, outfile, boundary,crs){
  
  if(file.exists(outfile) && !opt_list$rebuild_population){
    return(readRDS(outfile))
  }
  
  rast(tif) |>
    project(sprintf("epsg:%s", crs)) |>
    crop(st_bbox(boundary)) |>
    # st_as_stars() |>
    (\(x){
      saveRDS(x, outfile)
      x
    })()
}

map_theme <- function(){
  list(
    theme_void(),
    annotation_scale(location="br"),
    annotation_north_arrow(location="tl")
  )
}

convert_idp_sf <- function(data, lon_col, lat_col, target_crs, remove_coords = FALSE) {
  # Input validation
  if (!all(c(lon_col, lat_col) %in% names(data))) {
    stop("Longitude and/or latitude columns not found in data.")
  }
  
  if (!inherits(target_crs, "crs") && !is.numeric(target_crs)) {
    stop("target_crs must be an EPSG code (numeric) or an sf CRS object.")
  }
  
  # Convert to sf
  sf_obj <- st_as_sf(
    data,
    coords = c(lon_col, lat_col),
    crs = 4326,
    remove = remove_coords
  )
  
  # Transform CRS
  sf_obj <- safe_transform(sf_obj, target_crs)
  
  return(sf_obj)
}

# Function to safely bind and allow non-matching columns
safe_bind_rows_allow_extra <- function(df_a, df_b) {
  cols_a <- names(df_a)
  cols_b <- names(df_b)
  
  # Warn if columns differ
  if (!setequal(cols_a, cols_b)) {
    warning("Column names differ between data frames.\n",
            "Extra in DF1: ", paste(setdiff(cols_a, cols_b), collapse = ", "), "\n",
            "Extra in DF2: ", paste(setdiff(cols_b, cols_a), collapse = ", "))
  }
  
  # bind_rows automatically fills missing columns with NA
  bind_rows(df_a, df_b)
}

# building_sampling_frame <- cache_rds(
#   file = file.path(output_dir, "cache", "building_sampling_frame.rds"),
#   rebuild = FALSE,
#   expr = function() {
#     
#     message("Loading Google Open Buildings...")
#     
#     buildings <- load_building_footprints_raw(boundaries_dir)
#     
#     buildings <-
#       buildings |>
#       st_transform(mycrs) |>
#       filter(confidence >= 0.75)
#     
#     buildings <- clip_to_accessible(buildings, accessible_area)
#     
#     buildings <- calculate_building_attributes(buildings)
#     
#     buildings
#   }
# )



# set some GIS parameters such as projection and focus area etc

# set the project crs for the geoprocessing :
mycrs <- 31028 #WGS 84 / UTM zone 28N. unit in meters
newcrs <- st_crs(sprintf('epsg:%s', mycrs))


# focused admin1s by region as defined by IMPACT and FACT - this is an alternative to use the refsheet above
refsheet_admin1 <- read.csv(here(data_dir, "Refsheet_admin1.csv"))

# NW: Kaduna, Kano, Katsina, Kebbi, Sokoto, Zamfara (priority are Katsina, Sokoto, Zamfara)
# NG019, NG020, NG021, NG022 NG034, NG037

# NC: Benue, Kogi, Nasarawa, Niger, Plateau
# NG007, NG023, NG026, NG027, NG032

# NE: Adamawa, Borno, Yobe
# NG002, NG008, NG036


# create lists of relevant admin1 pcodes - separately by region in case want to run regional sampling
nga_admin1_pcodes_nw <- c("NG019", "NG020", "NG021", "NG022", "NG034", "NG037")
nga_admin1_pcodes_ne <- c("NG002", "NG008", "NG036")
nga_admin1_pcodes_nc <- c("NG007", "NG023", "NG026", "NG027", "NG032")

# joining the 3 region lists for whole assessment sampling
admin1_focus_areas <- c(nga_admin1_pcodes_nc, nga_admin1_pcodes_ne, nga_admin1_pcodes_nw)

# unique(NGA_shapes_all$nga_admin1$adm1_name)
# 
# xx <- NGA_shapes_all$nga_admin1 %>% 
#   filter(adm1_name == "Kebbi") %>% 
#   pull(adm1_pcode)

## ---- 2 bring in GIS data ----

# ---- 2.1 admin boundaries ----

# ---- 2.1.1 west african admin0 ----

# bring in west african admin0 boundaries to be used with buffers later 
admin0_wa_bnds <- st_read(here(boundaries_dir,  
                               "wca_admbnda_adm0_edgematched_942026",
                               "wca_admbnda_adm0_edgematched.shp"))
admin0_wa_proj <- safe_transform(admin0_wa_bnds, mycrs)


# visualise hex data - only running to check, don't run and save memory if not needed
# ggplot() +
#   geom_sf(data=admin0_wa_bnds, color = "white", lwd=0.01, aes(fill = adm0_pcode)) +
#   map_theme()

# ---- 2.1.2 nigeria all admins ----

# 1. List of shapefile paths
shapefiles <- list.files(
  path = here(boundaries_dir, "nga_admin_boundaries"), # folder containing .shp files
  pattern = "\\.shp$", 
  full.names = TRUE
)

# 2. Create clean names: remove folder and extension
layer_names <- tools::file_path_sans_ext(basename(shapefiles))

# 2. Load all shapefiles into a list
sf_list <- lapply(shapefiles, safe_load)
names(sf_list) <- layer_names

# Remove failed loads
sf_list <- sf_list[!vapply(sf_list, is.null, logical(1))]

# 3. Transform all loaded layers to target CRS
# NGA_shapes_all <- lapply(sf_list, function(x) safe_transform(x, mycrs))
NGA_shapes_all <- lapply(sf_list, st_transform, crs = mycrs)

# Remove failed transforms
NGA_shapes_all <- Filter(Negate(is.null), NGA_shapes_all)

# Layers to process (by name)
layers_to_process <- c("nga_admin1","nga_admin2", "nga_admin3")

# Create new list of relevant and cleaned shapefiles from selected layers
NGA_shapes_all_cleaned <- lapply(NGA_shapes_all[layers_to_process], process_spatial_layer)


# visualise admin1 data - only running to check, don't run and save memory if not needed
# ggplot() +
#   geom_sf(data=NGA_shapes_all_cleaned$nga_admin1,fill="white") +
#   geom_text_repel(data = NGA_shapes_all_cleaned$nga_admin1, aes(label = adm1_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
#   map_theme()


## 2.2 new pop ----

## 2.2.1 new grid3 ----

# grid3_pop <- load_population(
#   tif= here(population_dir, "grid3", "NGA_population_v3_0_gridded.tif"),
#   outfile= here(population_dir, "grid3", "grid3_nga_100m_projected.rds"),
#   boundary=NGA_shapes_all_cleaned$nga_admin1,
#   crs=mycrs
# )

## 2.2.2 new worldpop ----
worldpop_pop <- load_population(
  tif= here(population_dir, "worldpop", "worldpop_nga_pop_2026_CN_100m_R2025A_v1.tif"),
  outfile= here(population_dir, "worldpop", "worldpop_nga_2026_projected.rds"),
  boundary=NGA_shapes_all_cleaned$nga_admin1,
  crs=mycrs
)


# ---- 2.2.3 IDP - IOM ----
# if(!file.exists("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds") | opt_list$rebuild_hex ){

iom_idp_files <- list.files(path = here(population_dir, "iom"), pattern = "\\.csv$", full.names = TRUE)

# run IOM DTM for the NE
iom_idp_NE <- read.csv(iom_idp_files[2])

idp_NE_clean <- iom_idp_NE %>% 
  clean_names() %>% 
  remove_empty(which = c("rows", "cols")) %>% 
  distinct() %>% 
  mutate(region = "NE") %>% 
  filter(location_type == "IDP Location") %>% 
  rename(
    adm1_pcode = state_pcode,
    adm1_name = state,
    adm2_name = lga,
    adm2_pcode = lga_pcode,
    pop = individuals,
    pop_hh = households
  )

# convert iom idp data to sf object and project coordinates in order to be joinable with other data
idp_NE_sf <- convert_idp_sf(idp_NE_clean, "longitude_e", "latitude_n", mycrs, remove_coords = FALSE)


# run IOM DTM for the NW and NC
iom_idp_NCNW <- read.csv(iom_idp_files[1])

idp_NCNW_clean <- iom_idp_NCNW %>% 
  clean_names() %>% 
  remove_empty(which = c("rows", "cols")) %>% 
  distinct() %>% 
  mutate(location_type = case_when(
    population_category == "Returnees" ~ "Returnee Location",
    TRUE ~ "IDP Location")) %>% 
  filter(location_type == "IDP Location")  
 
# convert iom idp data to sf object and project coordinates in order to be joinable with other data
idp_NCNW_sf <- convert_idp_sf(idp_NCNW_clean, "longitude_e", "latitude_n", mycrs, remove_coords = FALSE)

idp_NCNW_joined_sf <- st_join(idp_NCNW_sf, NGA_shapes_all_cleaned$nga_admin2, join = st_within)

idp_NCNW_2join <- idp_NCNW_joined_sf %>%
  filter(!is.na(region)) %>%
  rename(
    pop = individuals,
    pop_hh = households
  )

# join the two idp tables
idp_combined_df <- safe_bind_rows_allow_extra(idp_NE_sf, idp_NCNW_2join)

iom_idp_df <- idp_combined_df %>%
  mutate(
    individuals = suppressWarnings(as.numeric(pop)), # convert, suppress warnings for NAs
    households = suppressWarnings(as.numeric(pop_hh)) # convert, suppress warnings for NAs
  )


## ---- 3. Create hexagon grid ---- 

bound_hex_clip <- cache_rds(
  here(boundaries_dir, "nga_hexagons", "hexa_by_admin2.rds"),

  function(){
    
    split_admins <- split(
      NGA_shapes_all_cleaned$nga_admin2,
      NGA_shapes_all_cleaned$nga_admin2$adm2_pcode
    )
    
    hexes <- purrr::map(
      split_admins,
      \(x) {
        
        hex <- st_sf(
          geometry = st_make_grid(
            x,
            cellsize = 5000,
            square = FALSE
          )
        )
        
        st_intersection(x, hex) |>
          st_make_valid() |>
          st_intersection(st_make_valid(NGA_shapes_all_cleaned$nga_admin2)) |>
          st_collection_extract("POLYGON") |>
          filter(!st_is_empty(geometry)) |>
          mutate(
            uuid = paste0("hex_", row_number()),
            uuid_hex = paste(region, adm1_name, adm2_name, uuid, sep = "_")
          )
        
      }
    )
    
    bound_hex_clip <- bind_rows(hexes)

  },

  rebuild = opt_list$rebuild_hex_intersection
)

# visualise hex data - only running to check, don't run and save memory if not needed
# ggplot()+
#   geom_sf(data=bound_hex_clip, color = "white", lwd=0.01, aes(fill = adm1_pcode)) +
#   map_theme()


## ---- 4. Defining accessible areas ----
# focused admin1s by region as defined by IMPACT and FACT

# ---- 4.1.1 international buffer ----
# create a buffer 20km from the Niger country border, and 5km from the Chad, Cameroon and Benin border
admin0_cast <- st_cast(admin0_wa_proj, to = "MULTILINESTRING")

admin0_wa_buff <- admin0_cast %>%
  mutate(
    buffer_m = case_when(
      adm0_name %in% c("Chad", "Cameroon", "Benin") ~ 5000,
      adm0_name == "Niger" ~ 20000,
      TRUE ~ NA_real_
    )) %>%
  filter(!is.na(buffer_m))

# 3. Apply st_buffer with per-feature distances
nga_buffered <- st_buffer(admin0_wa_buff, dist = admin0_wa_buff$buffer_m)

# 4. Example: plot original vs buffered for a subset
# ggplot() +
#   geom_sf(data = admin0_cast, fill = "lightblue") +
#   geom_sf(data = nga_buffered, fill = NA, color = "red") +
#   map_theme()



# 4.1.2 insecure areas from FACT ----
FACT_accessibility <- read.csv(here(boundaries_dir, "nga_accessibility", "NGA_Sampling_accessibility_FACT_admin3_NE.csv"))

# clean column names and remove empty rows/cols
FACT_accessibility <- FACT_accessibility %>%
  clean_names() %>%              
  remove_empty(which = c("rows", "cols")) %>% 
  mutate(uuid = paste(state, lga, ward_community, sep = "_")) %>% 
  distinct()
  
# filter for only inaccessible areas - will use this to filter the admin3 poly
FACT_noaccess <- FACT_accessibility %>% 
  filter(accessibility_status %in% c("Not Existing", "Inaccessible"))

# add concatenated uuid to shapefile
NGA_shapes_all_cleaned$nga_admin3 <- NGA_shapes_all_cleaned$nga_admin3 %>% 
  mutate(uuid = paste(adm1_name, adm2_name, adm3_name, sep = "_"))

# check if admin3 names from FACT are in shapefile
not_in_shp <- setdiff(FACT_noaccess$uuid, NGA_shapes_all_cleaned$nga_admin3$uuid)

admin3_yesaccess <- NGA_shapes_all_cleaned$nga_admin3 %>% 
  filter(!uuid %in% FACT_noaccess$uuid)

admin3_noaccess <- NGA_shapes_all_cleaned$nga_admin3 %>% 
  filter(uuid %in% FACT_noaccess$uuid)


# visualise excluded no access area - only running to check, don't run and save memory if not needed
# ggplot() +
#   geom_sf(data=admin3_noaccess)+
#   map_theme()

# ---- 4.2 clip non coverage areas ----

## the reason for doing this clip kinda excessive way of clipping is because the geometries weren't aligning properly for the clip...
## which basically meant the admin3 restricted areas would cut but the buffered areas wouldn't

# Ensure all layers are prepped for clipping (same CRS etc.)
clip_admin1 <- NGA_shapes_all_cleaned$nga_admin1 %>%
  prep_geom()

clip_noaccess <- admin3_noaccess %>%
  prep_geom()

clip_buffered <- nga_buffered %>%
  prep_geom()


# Dissolve each restricted layer into a single geometry
noaccess_union <- st_union(clip_noaccess)
buffered_union <- st_union(clip_buffered)

# Combine both restricted areas into one
restricted <- st_union(noaccess_union, buffered_union) %>%
  st_make_valid()

# Subtract restricted areas from admin1
accessible_area <- st_difference(clip_admin1, restricted) %>%
  st_make_valid()


# BEFORE: Original admin1 with restricted overlays
p_before <- ggplot() +
  geom_sf(data = clip_admin1, fill = "lightblue", color = "grey40", size = 0.3) +
  geom_sf(data = clip_noaccess, fill = "red", alpha = 0.4, color = NA) +
  geom_sf(data = clip_buffered, fill = "orange", alpha = 0.4, color = NA) +
  theme_minimal() +
  labs(
    title = "Before",
    subtitle = "Admin1 with Restricted Areas Highlighted",
    caption = "Red = admin3_noaccess | Orange = nga_buffered"
  )

# AFTER: Accessible area only
p_after <- ggplot() +
  geom_sf(data = accessible_area, fill = "lightgreen", color = "darkgreen", size = 0.3) +
  theme_minimal() +
  labs(
    title = "After",
    subtitle = "Accessible Area (Restricted Zones Removed)"
  )

# Combine side-by-side
p_before + p_after


## ---- 5. Intersect hex and accessible areas ----

hex_access <- cache_rds(

  here(boundaries_dir, "nga_hexagons", "accessible_hex.rds"),

  function(){
    st_intersection(
      st_make_valid(bound_hex_clip),
      st_make_valid(accessible_area)
    ) |>
      st_collection_extract("POLYGON") |>
      filter(!st_is_empty(geometry))
    },

  rebuild = opt_list$rebuild_hex_intersection
)

# visualise hexgrid - only running to check, don't run and save memory if not needed

# ggplot() +
#   geom_sf(data=hex_access, color = "white", lwd=0.01, aes(fill = adm2_pcode),) +
#   geom_text_repel(data = NGA_shapes_all_cleaned$nga_admin2, aes(label = adm2_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
#   map_theme()

# ggplot() +
#   geom_sf(data=hex_access)+
#   map_theme()


## ---- 6. population by hex ----


build_population_by_hex <- function(
    hex_access,
    source = c("host", "idp"),
    worldpop_pop = NULL,
    iom_idp_df = NULL,
    hh_size = 6,
    min_hh = 5
) {
  
  source <- match.arg(source)
  
  if (source == "host" && is.null(worldpop_pop)) {
    stop("worldpop_pop must be supplied when source = 'host'")
  }
  
  if (source == "idp" && is.null(iom_idp_df)) {
    stop("iom_idp_df must be supplied when source = 'idp'")
  }
  
  hex_access |>
    group_split(region) |>
    purrr::map(function(region_df) {
      
      if (source == "host") {
        
        out <-
          region_df |>
          group_split(adm2_pcode) |>
          purrr::map(function(adm_df) {
            
            adm_df |>
              mutate(
                pop = exactextractr::exact_extract(
                  worldpop_pop,
                  adm_df,
                  "sum"
                ),
                pop_hh = pop / hh_size
              )
            
          }) |>
          bind_rows()
        
      } else if (source == "idp") {
        
        hex_counts <-
          sf::st_join(iom_idp_df, region_df) |>
          sf::st_drop_geometry() |>
          group_by(uuid_hex) |>
          summarise(
            pop = sum(pop, na.rm = TRUE),
            pop_hh = sum(pop_hh, na.rm = TRUE),
            .groups = "drop"
          )
        
        out <-
          region_df |>
          left_join(hex_counts, by = "uuid_hex") |>
          mutate(
            pop = coalesce(pop, 0),
            pop_hh = coalesce(pop_hh, 0)
          )
        
      }
      
      out |>
        mutate(
          pop = as.numeric(pop),
          pop_hh = as.numeric(pop_hh),
          estimated_households = round(pop_hh / hh_size) * hh_size,
          pop_type = source,
          uuid_hex_pop = paste0(source, "_", uuid_hex)
          )|>
        filter(pop_hh > min_hh) |>
        arrange(uuid_hex) |>
        select(
          uuid_hex_pop,
          uuid_hex,
          pop_type,
          adm0_name,
          region,
          adm1_name,
          adm1_pcode,
          adm2_name,
          adm2_pcode,
          uuid,
          pop,
          pop_hh,
          estimated_households,
          geometry
        )
      
    }) |>
    bind_rows()
  
}


hex_grid_host <- cache_rds(

  here(population_dir, "sampling_frame", "hex_grid_host.rds"),

  function() {

    build_population_by_hex(
      hex_access = hex_access,
      source = "host",
      worldpop_pop = worldpop_pop
    )

  },

  rebuild = opt_list$rebuild_pophex_host
  )


hex_grid_idp <- cache_rds(

  here(population_dir, "sampling_frame", "hex_grid_idp.rds"),

  function() {

    build_population_by_hex(
      hex_access = hex_access,
      source = "idp",
      iom_idp_df = iom_idp_df
    )

  },

  rebuild = opt_list$rebuild_pophex_idp
)



## ----  7 sampling implementation ----

##  chosen parameters
# input_host <-list(
#   strata="adm2_pcode",
#   samp_type="Cluster sampling",
#   stratified="Stratified",
#   topup="Based on population",
#   cls=5,
#   conf_level=0.90,
#   e_marg=0.10,
#   pror=0.5,
#   ICC=0.06,
#   buf=0.1,
#   col_psu="uuid_hex",
#   colpop="pop_hh"
# )


build_sampling_plan <- function(
    hex_grid,
    Z = qnorm(0.95),
    p = 0.5,
    e = 0.10,
    m = 6,
    ICC = 0.06,
    buffer = 0.10,
    certainty_threshold = NULL
){
  
  #---------------------------- Sample size calculations
  
  deff <- 1 + (m - 1) * ICC
  
  n0 <- Z^2 * p * (1 - p) / e^2
  
  ndeff <- n0 * deff
  
  
  if(is.null(certainty_threshold)){
    certainty_threshold <- m * 6
  }
  
  
  round_up_multiple <- function(x, multiple){
    ceiling(x / multiple) * multiple
  }
  
  
  #---------------------------- Admin-2 sample allocation
  
  sample_plan <-
    
    hex_grid %>%
    sf::st_drop_geometry() %>%
    group_by(
      pop_type,
      adm2_pcode,
      adm2_name,
      adm1_pcode,
      adm1_name,
      region
    ) %>%
    summarise(
      
      n_pop = sum(pop, na.rm = TRUE),
      
      N_hh = sum(pop_hh, na.rm = TRUE),
      
      n_hex = n(),
      
      .groups = "drop"
      
    ) %>%
    mutate(
      
      # FPC adjusted household sample
      hh_sample_raw =
        N_hh * ndeff /
        (N_hh + ndeff - 1),
      
      # Round to complete clusters
      hh_sample =
        round_up_multiple(
          hh_sample_raw,
          m
        ),
      
      # Add reserve
      hh_sample_buffer =
        round_up_multiple(
          hh_sample * (1 + buffer),
          m
        ),
      
      # Initial cluster requirement
      clusters_raw =
        ceiling(
          hh_sample_buffer / m
        ),
      
      # Small population certainty enumeration
      certainty_stratum =
        N_hh < certainty_threshold,
      
      # Sampling type label
      selection_type =
        ifelse(
          certainty_stratum,
          "certainty",
          "pps"
        ),
      
      # Number of PSU selections
      clusters =
        case_when(
          
          certainty_stratum ~ 1,
          
          TRUE ~ pmin(
            clusters_raw,
            ceiling(N_hh / m)
          )
          
        ),
      
      # Final achievable household target
      expected_households =
        case_when(
          
          certainty_stratum ~ N_hh,
          
          TRUE ~ clusters * m
          
        )
      
    )
  
  
  #---------------------------- Sampling frame
  
  sampling_frame <-
    
    hex_grid %>%
    
    left_join(
      sample_plan %>%
        select(
          pop_type,
          adm2_pcode,
          clusters,
          certainty_stratum,
          selection_type,
          expected_households
        ),
      by = c(
        "pop_type",
        "adm2_pcode"
      )
    ) %>%
    
    mutate(
      
      # PPS measure of size
      MOS = pop_hh
      
    ) %>%
    
    group_by(
      pop_type,
      adm2_pcode
    ) %>%
    
    mutate(
      
      total_MOS = sum(MOS),
      
      psu_probability =
        case_when(
          
          first(certainty_stratum) ~ 1,
          
          TRUE ~ pmin(
            1,
            clusters * MOS / total_MOS
          )
          
        )
      
    ) %>%
    
    ungroup()
  
  
  #---------------------------- Summary table
  
  sampling_summary <-
    
    sample_plan %>%
    mutate(
      households_per_cluster = m
    )
  
  
  list(
    
    sample_plan = sample_plan,
    
    sampling_frame = sampling_frame,
    
    sampling_summary = sampling_summary
    
  )
  
}

host_sampling <- build_sampling_plan(hex_grid_host)
idp_sampling  <- build_sampling_plan(hex_grid_idp)

combined_sampling_summary <- bind_rows(host_sampling$sampling_summary,idp_sampling$sampling_summary)
write_csv(combined_sampling_summary, "testing.csv")


select_pps_clusters <- function(
    sampling_frame
){
  
  
  hex_geometry <-
    sampling_frame %>%
    select(
      uuid_hex_pop,
      geometry
    )
  
  
  sampling_frame <-
    sampling_frame %>%
    sf::st_drop_geometry()
  
  
  #---------------------------------- Certainty enumeration strata

  
  certainty_clusters <-
    
    sampling_frame %>%
    filter(
      certainty_stratum
    ) %>%
    group_by(
      pop_type,
      adm2_pcode
    ) %>%
    mutate(
      
      # unique cluster ID within Admin-2
      cluster_number =
        row_number(),
      
      selection_count = 1,
      
      psu_probability = 1
      
    ) %>%
    ungroup()
  
  
  #---------------------------------- PPS strata

  pps_frame <-
    sampling_frame %>%
    filter(
      !certainty_stratum
    )
  
  
  pps_clusters <-
    
    pps_frame %>%
    group_by(
      pop_type,
      adm2_pcode
    ) %>%
    group_modify(function(df, key){
      
      n_clusters <-
        first(df$clusters)
      
      df <-
        df %>%
        filter(
          MOS > 0
        )
      
      total_MOS <-
        sum(df$MOS)
      
      interval <-
        total_MOS / n_clusters
      
      start <-
        runif(
          1,
          0,
          interval
        )
      
      draws <-
        start +
        (0:(n_clusters - 1)) * interval
      
      df <-
        df %>%
        arrange(uuid_hex_pop) %>%
        mutate(
          cum_MOS = cumsum(MOS)
        )
      
      # selected_index <-
      #   findInterval(
      #     draws,
      #     df$cum_MOS
      #   ) + 1
      
      selected_index <- pmin(
        findInterval(draws, df$cum_MOS) + 1,
        nrow(df)
      )
      
      selected_hex <-
        df[selected_index, ] %>%
        mutate(
          cluster_number =
            seq_len(n_clusters)
        )
      
      selection_counts <-
        selected_hex %>%
        count(
          uuid_hex_pop,
          name = "selection_count"
        )
      
      selected_hex %>%
        left_join(
          selection_counts,
          by = "uuid_hex_pop"
        )
      
    }) %>%
    ungroup()
  
  
  #---------------------------------- Combine certainty and PPS samples

  selected_clusters <-
    bind_rows(
      certainty_clusters,
      pps_clusters
    ) %>%
    left_join(
      hex_geometry,
      by = "uuid_hex_pop"
    ) %>%
    sf::st_as_sf()
  
  
  selected_clusters
  
}

# Fixed seed so the PPS systematic draw (host + IDP) is reproducible on
# rerun - required for audit trail on a humanitarian assessment. Stage 2
# household selection sets its own seed independently in
# 03_household_selection.R.
set.seed(1234)

host_clusters <- select_pps_clusters(host_sampling$sampling_frame)

host_clusters <- host_clusters %>%
  mutate(
    cluster_id =
      paste(
        pop_type,
        adm2_pcode,
        cluster_number,
        sep="_"
      )
  )

idp_clusters  <- select_pps_clusters(idp_sampling$sampling_frame)

idp_clusters <- idp_clusters %>%
  mutate(
    cluster_id =
      paste(
        pop_type,
        adm2_pcode,
        cluster_number,
        sep="_"
      )
  )

## the size needs to be done this way because selection_count can be greater than one (because PPS 
##systematic sampling can select the same hex more than once), then the number of points should reflect that:
start_points <-
  sf::st_sample(
    idp_clusters,
    size = rep(1, nrow(idp_clusters)), # (equivalently just 1)
    type = "random"
  )






## ---- stage 2 sampling ----

# 01 building ingestion
source("02_building_ingestion.R")

reference_data_dir <- "C:/Users/JackPHILPOTT/Personal - Documents/GIS"

building_data_dir <- file.path(
  reference_data_dir,
  "Google_Open_Buildings"
)

# Buildings are only needed for Stage 2 household selection within the
# already-selected Stage-1 HOST clusters - IDP clusters use their IOM DTM
# site's own GPS point instead (05_idp_site_assignment.R), never querying
# Google Open Buildings at all. Even scoped to host-only, the GDBs are
# country-scale (tens of millions of features each) and querying the full
# accessible area would exhaust memory on a normal machine.
selected_clusters <- dplyr::bind_rows(host_clusters, idp_clusters)

# Character vector of per-GDB-part cache file paths, NOT a combined object -
# see load_building_footprints() roxygen docs for why (13M+ rows at full
# scale, geographically disjoint parts, no correctness need to combine).
building_files <- load_building_footprints(
  gdb_directory = building_data_dir,
  accessible_area = host_clusters,
  mycrs = mycrs,
  cache_directory = file.path(
    output_dir,
    "cache",
    "buildings"
  ),
  rebuild = FALSE
)

# 02 stage 2 household selection
source("03_household_selection.R")

# GRID3 ward boundaries: the only Admin-3-equivalent layer with national
# (NW/NE/NC) coverage - the official COD Admin-3 layer only covers the 3 NE
# states, so it's used as a secondary reference instead (see
# 03_household_selection.R roxygen docs).
nga_wards <- sf::st_read(
  here(boundaries_dir, "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"),
  quiet = TRUE
)

# Diagnostic: how much memory is already committed by Stage 1 + supporting
# data (worldpop raster, admin boundaries, ward boundaries) before Stage 2
# even starts, and how much the R session itself is holding onto.
gc_summary <- gc(full = TRUE)
message("R memory in use (Mb): ", round(sum(gc_summary[, 2]), 1))
tryCatch({
  free_mem_kb <- as.numeric(
    system("wmic OS get FreePhysicalMemory /value", intern = TRUE) |>
      grep("FreePhysicalMemory=", x = _, value = TRUE) |>
      sub("FreePhysicalMemory=", "", x = _)
  )
  message("System free memory (Mb): ", round(free_mem_kb / 1024, 1))
}, error = function(e) message("Could not check system free memory: ", e$message))

stage2_households_host <- select_stage2_households(
  clusters = host_clusters,
  building_files = building_files,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(
    output_dir,
    "cache",
    "stage2"
  ),
  rebuild = FALSE
)

# 03 host zero-building cluster reallocation
#
# A selected HOST hexagon with zero eligible buildings can't be visited by
# a field team - substitute a different hexagon from the same adm2_pcode
# stratum, drawn with the same PPS-by-population mechanism as the original
# Stage 1 draw. See 04_cluster_reallocation.R roxygen docs. Understaffed
# clusters (some buildings, fewer than target) are untouched - this only
# replaces clusters with NO eligible buildings at all. Host-only: IDP
# clusters never have a zero-building problem in the first place, since
# IDP Stage 2 (05_idp_site_assignment.R, below) doesn't use buildings.
source("04_cluster_reallocation.R")

reallocation <- reallocate_zero_building_clusters(
  clusters = host_clusters,
  host_sampling = host_sampling,
  idp_sampling = idp_sampling,
  stage2_households = stage2_households_host,
  building_data_dir = building_data_dir,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(
    output_dir,
    "cache",
    "reallocation"
  ),
  rebuild = FALSE
)

if(nrow(reallocation$unresolved) > 0) {

  message(
    nrow(reallocation$unresolved),
    " host zero-building cluster(s) remain unresolved after reallocation - ",
    "see output/reallocation_unresolved.csv"
  )

  readr::write_csv(
    reallocation$unresolved,
    here(output_dir, "reallocation_unresolved.csv")
  )

}

stage2_households_host <- dplyr::bind_rows(stage2_households_host, reallocation$new_households)

# 04 IDP site assignment
#
# IDP Stage 2 uses the IOM DTM site's own GPS point rather than a building
# footprint draw - see 05_idp_site_assignment.R roxygen docs for why (every
# selected IDP hexagon has DTM-reported population by construction, so this
# never hits a "zero eligible locations" problem the way buildings did).
source("05_idp_site_assignment.R")

idp_sites <- select_stage2_idp_sites(
  clusters = idp_clusters,
  iom_idp_df = iom_idp_df,
  wards = nga_wards,
  admin3 = NGA_shapes_all_cleaned$nga_admin3,
  mycrs = mycrs,
  cache_directory = file.path(
    output_dir,
    "cache",
    "idp_sites"
  ),
  rebuild = FALSE
)

stage2_households <- dplyr::bind_rows(stage2_households_host, idp_sites$households)

# Authoritative final cluster-hexagon/site table (Stage 1 draws with
# reallocated host clusters' hexagon, and IDP clusters' site point, swapped
# in) - the raw Stage 1 selected_clusters object above is now stale for any
# reallocated or IDP cluster_id and should not be used for mapping/QC going
# forward; use this instead.
selected_clusters_final <- dplyr::bind_rows(reallocation$clusters_final, idp_sites$clusters_final)

saveRDS(
  selected_clusters_final,
  here(output_dir, "selected_clusters_final.rds")
)

host_surveys <- stage2_households %>% dplyr::filter(pop_type == "host")
idp_surveys  <- stage2_households %>% dplyr::filter(pop_type == "idp")

sf::st_write(
  stage2_households,
  here(output_dir, "stage2_sampling_frame.gpkg"),
  delete_dsn = TRUE,
  quiet = TRUE
)

readr::write_csv(
  stage2_households %>% sf::st_drop_geometry(),
  here(output_dir, "stage2_sampling_frame.csv")
)

readr::write_csv(
  host_surveys %>% sf::st_drop_geometry(),
  here(output_dir, "stage2_sampling_frame_host.csv")
)

readr::write_csv(
  idp_surveys %>% sf::st_drop_geometry(),
  here(output_dir, "stage2_sampling_frame_idp.csv")
)

message("Pipeline complete through Stage 2 household selection.")

# Everything below this point is ad hoc interactive exploration/plotting
# (some blocks reference objects from older script versions that no longer
# exist, e.g. clip_admin1) - safe to run line-by-line in RStudio, but not
# part of the batch pipeline, so a non-interactive Rscript run stops here
# rather than erroring out on stale exploration code after the real outputs
# are already saved.
if(!interactive()) {

  quit(save = "no")

}

# ## ----  7 test impact sampling implementation ----
# 
# source("global_sampling_source.R") #sampling methods from Olivier Cecchi
# 
# set.seed(1234)
# 
# #  chosen parameters
# input <-list(
#   strata="adm2_pcode",
#   samp_type="Cluster sampling",
#   stratified="Stratified",
#   topup="Based on population",
#   cls=5,
#   conf_level=0.90,
#   e_marg=0.10,
#   pror=0.5,
#   ICC=0.06,
#   buf=0.1,
#   col_psu="uuid_hex_pop",
#   colpop="pop_hh"
# )
# 
# ## IDP
# # create a version without the geometry
# hexgriddata_idp <-hex_grid_idp |> st_drop_geometry()
# 
# sample_topup_idp <-make_sample(hexgriddata_idp,input)
# rmarkdown::paged_table(sample_topup_idp$summary_sample)
# # join back to original sample frame. 
# hex_sampl_topup_idp <-right_join(hex_grid_idp,sample_topup_idp$sample,join_by(uuid_hex_pop==uuid_hex_pop)) 
# 
# hex_sampl_topup_idp |> head()
# 
# ## host
# # create a version without the geometry
# hexgriddata_host<-hex_grid_host |> st_drop_geometry()
# 
# sample_topup_host <-make_sample(hexgriddata_host,input)
# rmarkdown::paged_table(sample_topup_host$summary_sample)
# # join back to original sample frame. 
# hex_sampl_topup_host <-right_join(hex_grid_host,sample_topup_host$sample,join_by(uuid_hex_pop==uuid_hex_pop)) 
# 
# hex_sampl_topup_host |> head()


#### ---- Visuals -sampling_summary#### ---- Visuals ----

library(ggplot2)

ne_admin1 <- clip_admin1 %>%
  filter(region == "NE")

ne_access <- accessible_area %>%
  filter(region == "NE")

ne_noaccess <- clip_noaccess %>%
  filter(region == "NE")

ggplot() +
  geom_sf(data = ne_admin1,
          fill = "grey95",
          colour = "grey60") +
  
  geom_sf(data = ne_access,
          fill = "#56B4E9",
          colour = NA) +
  
  geom_sf(data = ne_noaccess,
          fill = "#D55E00",
          alpha = .7,
          colour = NA) +
  
  theme_void()




#####
hex_ne <- hex_grid_host %>%
  filter(region == "NE")

ggplot() +
  geom_sf(
    data = hex_ne,
    aes(fill = pop),
    colour = "white",
    linewidth = 0.15
  ) +
  scale_fill_viridis_c(
    option = "C",
    trans = "sqrt",
    name = "Estimated\npopulation"
  ) +
  theme_void()


example_admin2 <- "Jere"

zoom_hex <-
  hex_grid_host %>%
  filter(adm2_name == example_admin2)

zoom_boundary <-
  NGA_shapes_all_cleaned$nga_admin2 %>%
  filter(adm2_name == example_admin2)

ggplot() +
  
  geom_sf(
    data = zoom_hex,
    aes(fill = pop),
    colour = "white",
    linewidth = .35
  ) +
  
  geom_sf(
    data = zoom_boundary,
    fill = NA,
    colour = "black",
    linewidth = 1
  ) +
  
  scale_fill_viridis_c(
    option = "C",
    trans = "sqrt",
    name = "Estimated\npopulation"
  ) +
  
  coord_sf(expand = FALSE) +
  theme_void()



# ggplot() +
#   
#   geom_sf(
#     data = zoom_hex,
#     aes(fill = pop),
#     colour = "white",
#     linewidth = .35
#   ) +
#   
#   geom_sf(
#     data = sample_points,
#     colour = "#0072B2",
#     fill = "#0072B2",
#     shape = 21,
#     size = 2
#   ) +
#   
#   scale_fill_viridis_c(
#     option = "C",
#     trans = "sqrt",
#     name = "Estimated\npopulation"
#   ) +
#   
#   coord_sf(expand = FALSE) +
#   theme_void()




#####
hex_ne <- hex_access %>%
  filter(region == "NE") %>%
  mutate(id = row_number())

ggplot() +
  geom_sf(data = hex_ne,
          aes(fill = factor(id)),
          colour = "white",
          linewidth = .1) +
  scale_fill_viridis_d(guide = "none") +
  theme_void()

####
example_admin2 <- "Jere"

zoom_hex <-
  hex_access %>%
  filter(adm2_name == example_admin2)

zoom_boundary <-
  NGA_shapes_all_cleaned$nga_admin2 %>%
  filter(adm2_name == example_admin2)

ggplot() +
  
  geom_sf(data = zoom_hex,
          aes(fill = factor(uuid)),
          colour = "white",
          linewidth = .3) +
  
  geom_sf(data = zoom_boundary,
          fill = NA,
          colour = "black",
          linewidth = 1) +
  
  scale_fill_viridis_d(guide="none") +
  
  coord_sf(expand = FALSE) +
  theme_void()

####
# ggplot() +
#   
#   geom_sf(data = zoom_hex,
#           fill = "grey90",
#           colour = "grey60") +
#   
#   geom_sf(data = sample_points,
#           colour = "#0072B2",
#           size = 2) +
#   
#   coord_sf(expand = FALSE) +
#   theme_void()




# ggplot() +  
#   geom_sf(data=hex_access_NE) +
#   geom_sf(data=hex_grid_host_NE, color = "white", lwd=0.01, aes(fill = pop),) +
#   geom_text_repel(data = hex_access_NE, aes(label = adm1_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
#   map_theme()
# 
# 
# ggplot() +
#   geom_sf(
#     data = hex_access_NE,
#     fill = "grey98",
#     color = "grey50",
#     linewidth = 0.4
#   ) +
#   geom_sf(
#     data = hex_grid_host_NE,
#     aes(fill = pop_hh),
#     color = "white",
#     linewidth = 0.05
#   ) +
#   scale_fill_viridis_c(
#     option = "C",
#     trans = "log1p"
#   ) +
#   coord_sf() +
#   theme_minimal() +
#   labs(
#     title = "Hex-based Population Distribution (NE Region)",
#     fill = "Households"
#   )



# hex_zoom <- hex_grid_host_NE %>%
#   filter(adm2_name == "Karasuwa")
# 
# adm2_zoom <- NGA_shapes_all_cleaned$nga_admin2 %>%
#   filter(adm2_name == "Karasuwa")


# base_map <- ggplot() +
#   
#   # ADM2 boundaries
#   geom_sf(
#     data = hex_access_NE,
#     fill = NA,
#     color = "grey50",
#     linewidth = 0.4
#   ) +
#   
#   # hex grid
#   geom_sf(
#     data = hex_grid_host_NE,
#     aes(fill = pop_hh),
#     color = NA,
#     alpha = 0.85
#   ) +
#   
#   scale_fill_viridis_c(
#     option = "C",
#     trans = "log1p"
#   ) +
#   
#   coord_sf() +
#   
#   theme_minimal() +
#   labs(
#     title = "NE Region - Population Distribution",
#     fill = "Households"
#   )
# 
# 
# 
# zoom_map <- ggplot() +
#   
#   # ADM2 boundary (highlighted)
#   geom_sf(
#     data = adm2_zoom,
#     fill = NA,
#     color = "red",
#     linewidth = 1
#   ) +
#   
#   # hexes inside ADM2
#   geom_sf(
#     data = hex_zoom,
#     aes(fill = pop_hh),
#     color = "white",
#     linewidth = 0.1
#   ) +
#   
#   scale_fill_viridis_c(
#     option = "C",
#     trans = "log1p"
#   ) +
#   
#   coord_sf() +
#   
#   theme_minimal() +
#   
#   labs(
#     title = paste("Zoomed View:"),
#     fill = "Households"
#   )
# 
# library(patchwork)
# 
# base_map + zoom_map +
#   plot_layout(ncol = 2)
# 
# 
# zoom_map







#### ---- *ARCHIVE ----

# strata_pop_host <- hex_grid_host %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     N_hh = sum(pop_hh),
#     n_clusters = n(),
#     .groups = "drop"
#   )
# 
# Z <- qnorm(0.95)     # 90% confidence
# p <- 0.5
# e <- 0.10
# m <- 6
# ICC <- 0.06
# buffer <- 0.10
# 
# deff <- 1 + (m - 1) * ICC
# n0 <- Z^2 * p * (1 - p) / e^2
# ndeff <- n0 * deff
# 
# strata_pop_host <- strata_pop_host %>%
#   mutate(
#     hh_sample = N_hh * ndeff / (N_hh + ndeff - 1),
#     hh_sample = ceiling(hh_sample * (1 + buffer)),
#     clusters_needed = ceiling(hh_sample / m)
#   )
# 
# sum(strata_pop_host$hh_sample)
# 
# library(dplyr)

# Z <- qnorm(0.95)      # 90% confidence
# p <- 0.5
# e <- 0.10
# m <- 6
# ICC <- 0.06
# buffer <- 0.10
# 
# deff <- 1 + (m - 1) * ICC
# n0 <- Z^2 * p * (1 - p) / e^2
# ndeff <- n0 * deff
# 
# sample_plan <- hex_grid_host %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     N_hh = sum(pop_hh),
#     n_psu = n(),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     # Household sample after FPC (no buffer)
#     hh_sample = N_hh * ndeff / (N_hh + ndeff - 1),
#     hh_sample = ceiling(hh_sample),
#     
#     # Household sample with 10% buffer
#     hh_sample_buffer = ceiling(hh_sample * (1 + buffer)),
#     
#     buffer_added = hh_sample_buffer - hh_sample,
#     
#     
#     # Clusters required
#     clusters = pmax(2, ceiling(hh_sample_buffer / m))
#   )

# bound_hex_clip <- cache_rds(
#   here(boundaries_dir, "nga_hexagons", "hexa_by_admin2.rds"),
# 
#   opt_list$rebuild_hex_intersection,
# 
#   function(){
# 
#     bound_hex_create <- st_make_grid(NGA_shapes_all_cleaned$nga_admin2, cellsize = 5000, square = FALSE)
# 
#     # convert to sf object
#     bound_hex_sf <- st_sf(geometry = bound_hex_create)
# 
#     #intersect the results to the focus area. attributes and value are also transferred. it isn't necessary to a spatial join after this
#     bound_hex_clip <- st_intersection(NGA_shapes_all_cleaned$nga_admin2, bound_hex_sf) # might be quite slow to run on a large area.
# 
#     bound_hex_clip <- bound_hex_clip %>%
#       mutate(uuid = paste0("hex_", row_number()),
#              uuid_hex = paste(region, adm1_name, adm2_name, uuid, sep = "_"))
#   }
# )


# bound_hex_clip <- cache_rds(
#   here(boundaries_dir, "nga_hexagons", "hexa_by_admin2.rds"),
#   
#   opt_list$rebuild_hex_intersection,
#   
#   function(){
# 
#     split_admins <- split(
#         NGA_shapes_all_cleaned$nga_admin2,
#         NGA_shapes_all_cleaned$nga_admin2$adm1_pcode)
#     
#     hexes <-
#       purrr::map(
#         split_admins,
#         \(x){
#           
#           st_intersection(
#             
#             x,
#             
#             st_make_grid(
#               
#               x,
#               
#               cellsize=5000,
#               
#               square=FALSE
#               
#             )
#             
#           )
#           
#         }
#       )
#     
#     bound_hex_clip <- bind_rows(hexes)
#     
#     bound_hex_clip <- bound_hex_clip %>% 
#       mutate(uuid = paste0("hex_", row_number()),
#              uuid_hex = paste(region, adm1_name, adm2_name, uuid, sep = "_"))    
#   }
# )

# list all the cells
# Extract info, with the exact method. 
# if(!file.exists(paste0(population_data_path, "/sampling_frame/sampling_frame.rds")) | opt_list$rebuild_sampling){
#   sampling_fr<-aggregate(worldpop_pop,hexgrid,FUN=sum,na.rm=T,exact=T)
# 
#   names(sampling_fr)<-"pop"
#   sampling_poly<-st_as_sf(sampling_fr)
# 
#   # add population number
#   hexgrid$pop<-sampling_poly$pop
# 
#   # add unique id since it was missing.
#   hexgrid$uuid<-ids::uuid(n=nrow(hexgrid))
#   saveRDS(hexgrid, paste0(population_data_path, "/sampling_frame/sampling_frame.rds"))
# 
#   # write sampling frame
#   writexl::write_xlsx(hexgrid,"output/sampling_frame_nondisp_v1.xlsx")
#   
#   # Split dataframe by 'group' column
#   split_data <- hexgrid %>%
#     group_by(region) %>%
#     group_split()
#   
#   # Get the unique group names in the same order as split_data
#   group_names <- hexgrid %>%
#     group_by(region) %>%
#     group_keys() %>%
#     pull(region)
#   
#   # Write each subset to a separate CSV
#   for (i in seq_along(split_data)) {
#     file_name <- paste0(output_dir, "/", group_names[i], ".csv")
#     write_csv(split_data[[i]], file_name, row.names = FALSE)
#   }
#   
#   
# }else {
#   hexgrid<-readRDS(paste0(population_data_path, "/sampling_frame/sampling_frame.rds"))
# }


## one line below replaces
# sampling_fr<-aggregate(worldpop_pop, hexgrid, FUN=sum, na.rm=T, exact=T)

# names(sampling_fr)<-"pop"
# sampling_poly<-st_as_sf(sampling_fr)
# 
# # add population number
# hexgrid$pop<-sampling_poly$pop

# hexgrid$pop <- exact_extract(
#   worldpop_pop,
#   hexgrid,
#   "sum"
# )

# groups <- hexgrid |> group_split(adm2_pcode)
# 
# st_geometry_type(groups[[4]]) 
# 
# table(st_geometry_type(hexgrid))


# sampling_fr_host <-
#   hexgrid |>
#   group_split(adm2_pcode) |>
#   map(\(x) {
#     x$pop <- exact_extract(
#       worldpop_pop,
#       x,
#       "sum"
#     )
#     x
#   }) |>
#   bind_rows() |>
#   arrange(uuid_hex)
# 
# saveRDS(sampling_fr_host, here(population_dir, "sampling_frame", "sampling_frame.rds"))
# 
# sampling_fr_host <- sampling_fr_host %>% 
#   mutate(pop_hh = pop / 6,
#          cluster_hh_size = round(pop_hh / 6) * 6)
# 
# sampling_host_filt <- sampling_fr_host %>% 
#   filter(pop_hh > 5)
# 
#   # write sampling frame
# writexl::write_xlsx(sampling_host_filt, here(output_dir, "sampling_frame_nondisp_v1.xlsx"))
# 
# sampling_host_filt |>
#   
#   split(.$region) |>
#   
#   iwalk(
#     
#     ~ readr::write_csv(.x,
#       
#       here(output_dir,paste0("sampling_frame_",.y,".csv"))))
# 

# hex_grid_idp_NE <- hex_grid_idp %>% 
#   filter(region == "NE")

# write_csv(hex_grid_idp_NE, here(output_dir, "sampling_frame_idp_NE.csv"))


# iom_idp_NCNW <- iom_idp_NCNW %>% 
#   filter(households > 5)
# 
# iom_idp_NCNW_join <- left_join(iom_idp_NCNW, refsheet_admin1, by = c("adm1_pcode" = "admin1_pcode"))
# 
# iom_idp_NC <- iom_idp_NCNW_join %>% 
#   filter(region.y == "NC")
# 
# # write_csv(iom_idp_NC, here(output_dir, "sampling_frame_idp_NC.csv"))
# 
# 
# iom_idp_NW <- iom_idp_NCNW_join %>% 
#   filter(region.y == "NW")

# write_csv(iom_idp_NW, here(output_dir, "sampling_frame_idp_NW.csv"))

# hex_grid_host <-
#   hex_access |>
#   group_split(region) |>
#   map(\(region_df) {
#     
#     region_name <- first(region_df$region)
#     
#     out <-
#       region_df |>
#       group_split(adm2_pcode) |>
#       map(\(adm_df) {
#         adm_df |>
#           mutate(
#             pop = exact_extract(worldpop_pop, adm_df, "sum")
#           )
#       }) |>
#       bind_rows() |>
#       mutate(
#         pop_hh = pop / 6,
#         cluster_hh_size = round(pop_hh / 6) * 6
#       ) |>
#       filter(pop_hh > 5) |>
#       arrange(uuid_hex) |>
#       select(
#         uuid_hex,
#         adm0_name,
#         region,
#         adm1_name,
#         adm1_pcode,
#         adm2_name,
#         adm2_pcode,
#         uuid,
#         pop,
#         pop_hh,
#         cluster_hh_size,
#         geometry
#       ) |>
#     mutate(
#       pop = parse_number(as.character(pop)),
#       pop_hh = parse_number(as.character(pop_hh))
#     )
#     
#     ## write it out here if I'm going to use the sampling tool/app, unless carry on as one file and sample here
#     readr::write_csv(
#       out,
#       here(output_dir, paste0("sampling_frame_host_", region_name, ".csv"))
#     )
#     
#     out
#   }) |>
#   bind_rows()
# 
# saveRDS(
#   hex_grid_host,
#   here(population_dir, "sampling_frame", "hex_grid_host.rds")
# )


# 
# hex_grid_host <- cache_rds(
#   
#   here(population_dir, "sampling_frame", "hex_grid_host.rds"),
#   
#   opt_list$rebuild_pophex_host,
#   
#   function(){
#     hex_access |>
#       group_split(region) |>
#       map(\(region_df) {
#         
#         region_name <- first(region_df$region)
#         
#         out <-
#           region_df |>
#           group_split(adm2_pcode) |>
#           map(\(adm_df) {
#             adm_df |>
#               mutate(
#                 pop = exact_extract(worldpop_pop, adm_df, "sum")
#               )
#           }) |>
#           bind_rows() |>
#           mutate(
#             pop_hh = pop / 6,
#             cluster_hh_size = round(pop_hh / 6) * 6
#           ) |>
#           filter(pop_hh > 5) |>
#           arrange(uuid_hex) |>
#           select(
#             uuid_hex,
#             adm0_name,
#             region,
#             adm1_name,
#             adm1_pcode,
#             adm2_name,
#             adm2_pcode,
#             uuid,
#             pop,
#             pop_hh,
#             cluster_hh_size,
#             geometry
#           ) |>
#           mutate(
#             pop = parse_number(as.character(pop)),
#             pop_hh = parse_number(as.character(pop_hh))
#           )
#         
#         ## write it out here if I'm going to use the sampling tool/app, unless carry on as one file and sample here
#         # readr::write_csv(
#         #   out,
#         #   here(output_dir, paste0("sampling_frame_host_", region_name, ".csv"))
#         # )
#         
#         out
#       }) |>
#       bind_rows()
#   }
# )
# 
# 
# 
# hex_grid_idp <- cache_rds(
#   
#   here(population_dir, "sampling_frame", "hex_grid_idp.rds"),
#   
#   opt_list$rebuild_pophex_idp,
#   
#   function(){
#     hex_access |>
#       group_split(region) |>
#       map(\(region_df) {
#         
#         region_name <- first(region_df$region)
#         
#         # spatial join (points → polygons)
#         joined <- st_join(iom_idp_df, region_df)
#         
#         # aggregate per hex
#         hex_counts <- joined |>
#           st_drop_geometry() |>
#           group_by(uuid_hex) |>
#           summarise(
#             pop = sum(pop, na.rm = TRUE),
#             pop_hh = sum(pop_hh, na.rm = TRUE),
#             .groups = "drop"
#           )
#         
#         # attach back
#         out <-
#           region_df |>
#           left_join(hex_counts, by = "uuid_hex") |>
#           mutate(
#             pop = coalesce(pop, 0),
#             pop_hh = coalesce(pop_hh, 0),
#             cluster_hh_size = round(pop_hh / 6) * 6
#           ) |>
#           filter(pop_hh > 5) |>
#           arrange(uuid_hex) |>
#           select(
#             uuid_hex,
#             region,
#             adm1_name,
#             adm1_pcode,
#             adm2_name,
#             adm2_pcode,
#             uuid,
#             pop,
#             pop_hh,
#             cluster_hh_size,
#             geometry
#           ) |>
#           mutate(
#             pop = parse_number(as.character(pop)),
#             pop_hh = parse_number(as.character(pop_hh))
#           )
#         
#         out
#       }) |>
#       bind_rows()
#   }
# )

# Z <- qnorm(0.95)      # 90% confidence
# p <- 0.5
# e <- 0.10
# m <- 6
# ICC <- 0.06
# buffer <- 0.10
# 
# deff  <- 1 + (m - 1) * ICC
# n0    <- Z^2 * p * (1 - p) / e^2
# ndeff <- n0 * deff
# 
# round_up_multiple <- function(x, multiple) {
#   ceiling(x / multiple) * multiple
# }
# 
# sampleplan_host <- hex_grid_host %>%
#   st_drop_geometry() %>% 
#   group_by(adm2_pcode) %>%
#   summarise(
#     n_pop = sum(pop, na.rm = TRUE),
#     N_hh = sum(pop_hh, na.rm = TRUE),
#     n_psu = n(),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     # Household sample after FPC (before buffer)
#     hh_sample_raw = N_hh * ndeff / (N_hh + ndeff - 1),
#     
#     # Rounded to a whole number of clusters
#     hh_sample = round_up_multiple(hh_sample_raw, m),
#     
#     # Add the 10% buffer and again round to a whole number of clusters
#     hh_sample_buffer = round_up_multiple(hh_sample * (1 + buffer), m),
#     
#     # Optional: number of extra interviews due to the buffer
#     buffer_added = hh_sample_buffer - hh_sample,
#     
#     # Number of clusters to select
#     clusters = as.integer(hh_sample_buffer / m)
#     
#   )
# 
# sampleplan_host_join <- sampleplan_host %>%
#   left_join(
#     hex_grid_host %>%
#       distinct(
#         adm2_pcode,
#         adm1_pcode,
#         adm1_name,
#         adm2_name,
#         region,
#         adm0_name
#       ),
#     by = "adm2_pcode"
#   )
# 
# sampleplan_host_join <- sampleplan_host_join %>%
#   select(
#     adm0_name,
#     region,
#     adm1_pcode,
#     adm1_name,
#     adm2_pcode,
#     adm2_name,
#     everything()
#   ) %>% 
#   st_drop_geometry() %>% 
#   mutate(pop_type = "host")
# 
# write_csv(sampleplan_host_join, here(output_dir, "sampling_summary_host_07072026.csv"))
# 
# 
# 
# # 3. Sampling frame
# 
# # The next object should be one row per hexagon, containing everything needed for PPS selection.
# sampling_frame_host <-
#   hex_grid_host %>%
#   left_join(
#     sampleplan_host %>%
#       select(
#         adm2_pcode,
#         hh_sample_buffer,
#         clusters
#       ),
#     by = "adm2_pcode"
#   ) %>%
#   mutate(
#     measure_size = pop_hh
#   )
# 
# # Step 4: Allocate clusters proportionally
# sampling_frame_host <-
#   sampling_frame_host %>%
#   group_by(adm2_pcode) %>%
#   mutate(
#     total_hh = sum(pop_hh),
#     prop_pop = pop_hh / total_hh,
#     clusters_raw = prop_pop * first(clusters)
#   ) %>%
#   ungroup()
# 
# 
# 
# # Step 5: Largest remainder allocation
# # 
# # This ensures the allocated clusters sum exactly to the required number in each Admin-2.
# sampling_frame_host <-
#   sampling_frame_host %>%
#   group_by(adm2_pcode) %>%
#   mutate(
#     clusters_floor = floor(clusters_raw),
#     remainder = clusters_raw - clusters_floor
#   ) %>%
#   mutate(
#     extra_cluster =
#       rank(-remainder, ties.method = "first") <=
#       first(clusters) - sum(clusters_floor),
#     
#     clusters_alloc =
#       clusters_floor + as.integer(extra_cluster)
#   ) %>%
#   ungroup()
# 
# # checking all the required and allocated match for admin-2
# sampling_frame_host %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     required = first(clusters),
#     allocated = sum(clusters_alloc)
#   )
# 
# 
# # Step 6: Calculate household sample per hexagon
# sampling_frame_host <-
#   sampling_frame_host %>%
#   mutate(
#     hh_sample_hex = clusters_alloc * 6
#   )
# 
# 
# ## bonus - sanity checks
# 
# # Total households by stratum
# sampling_frame_host %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     hh_required = first(hh_sample_buffer),
#     hh_allocated = sum(hh_sample_hex)
#   )
# 
# # Number of clusters by stratum
# sampling_frame_host %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     clusters_required = first(clusters),
#     clusters_allocated = sum(clusters_alloc)
#   )
# 
# 
# ### important to keep this for the next prompt when doing the random selection
# # After this, the next stage is to randomly select the actual sampling locations within the selected hexagons (or multiple locations within hexagons assigned more than one cluster). That step is where the randomisation enters the design, and it's worth implementing carefully to preserve the inclusion probabilities.
# 
# 
# # summary_region <- sampleplan_host_join %>%
# #   group_by(region) %>%
# #   summarise(
# #     n_states = n_distinct(adm1_name),
# #     n_adm2 = n(),
# #     total_households = sum(N_hh, na.rm = TRUE),
# #     hh_sample = sum(hh_sample, na.rm = TRUE),
# #     hh_sample_buffer = sum(hh_sample_buffer, na.rm = TRUE),
# #     buffer_added = sum(buffer_added, na.rm = TRUE),
# #     clusters = sum(clusters, na.rm = TRUE),
# #     .groups = "drop"
# #   ) %>%
# #   arrange(region)
# 
# 
# 
# 
# Z <- qnorm(0.95)      # 90% confidence
# p <- 0.5
# e <- 0.10
# m <- 6
# ICC <- 0.06
# buffer <- 0.10
# 
# deff  <- 1 + (m - 1) * ICC
# n0    <- Z^2 * p * (1 - p) / e^2
# ndeff <- n0 * deff
# 
# 
# 
# sampleplan_idp_NE <- hex_grid_idp %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     n_pop = sum(pop, na.rm = TRUE),
#     N_hh = sum(pop_hh, na.rm = TRUE),
#     n_psu = n(),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     # Household sample after FPC (before buffer)
#     hh_sample_raw = N_hh * ndeff / (N_hh + ndeff - 1),
#     
#     # Rounded to a whole number of clusters
#     hh_sample = round_up_multiple(hh_sample_raw, m),
#     
#     # Add the 10% buffer and again round to a whole number of clusters
#     hh_sample_buffer = round_up_multiple(hh_sample * (1 + buffer), m),
#     
#     # Optional: number of extra interviews due to the buffer
#     buffer_added = hh_sample_buffer - hh_sample,
#     
#     # Number of clusters to select
#     clusters = pmax(2, hh_sample_buffer / m)
#     
#   )
# 
# sampleplan_idp_join_NE <- sampleplan_idp_NE %>%
#   left_join(
#     hex_grid_idp %>%
#       distinct(
#         adm2_pcode,
#         adm1_pcode,
#         adm1_name,
#         adm2_name,
#         region
#       ),
#     by = "adm2_pcode"
#   ) %>% 
#   mutate(adm0_name = "Nigeria",
#          pop_type = "idp") %>% 
#   st_drop_geometry()
# 
# 
# 
# 
# sampleplan_idp_NCNW <- iom_idp_NCNW_join %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     n_pop = sum(pop, na.rm = TRUE),
#     N_hh = sum(pop_hh, na.rm = TRUE),
#     n_psu = n(),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     # Household sample after FPC (before buffer)
#     hh_sample_raw = N_hh * ndeff / (N_hh + ndeff - 1),
#     
#     # Rounded to a whole number of clusters
#     hh_sample = round_up_multiple(hh_sample_raw, m),
#     
#     # Add the 10% buffer and again round to a whole number of clusters
#     hh_sample_buffer = round_up_multiple(hh_sample * (1 + buffer), m),
#     
#     # Optional: number of extra interviews due to the buffer
#     buffer_added = hh_sample_buffer - hh_sample,
#     
#     # Number of clusters to select
#     clusters = pmax(2, hh_sample_buffer / m)
#     
#   )
# 
# ### *** temp fix
# adm_lookup <- iom_idp_NCNW_join %>%
#   group_by(adm2_pcode) %>%
#   summarise(
#     adm1_pcode = names(sort(table(adm1_pcode), decreasing = TRUE))[1],
#     adm1_name  = names(sort(table(adm1_name), decreasing = TRUE))[1],
#     adm2_name  = names(sort(table(adm2_name), decreasing = TRUE))[1],
#     region.y   = names(sort(table(region.y), decreasing = TRUE))[1],
#     .groups = "drop"
#   )
# 
# 
# 
# sampleplan_idp_join_NCNW <- sampleplan_idp_NCNW %>%
#   left_join(
#     adm_lookup %>%
#       distinct(
#         adm2_pcode,
#         adm1_pcode,
#         adm1_name,
#         adm2_name,
#         region.y
#       ),
#     by = "adm2_pcode"
#   ) %>% 
#   mutate(adm0_name = "Nigeria",
#          pop_type = "idp") %>% 
#   rename("region" = "region.y")
# 
# 
# #
# write_csv(sampleplan_idp_join, here(output_dir, "sampling_frame_idp_06072026.csv"))
# 
# 
# 
# sampleplan_all <- bind_rows(
#   sampleplan_host_join,
#   sampleplan_idp_join_NE,
#   sampleplan_idp_join_NCNW
# )
# 
# write_csv(sampleplan_all, here(output_dir, "sampling_frame_combo_06072026.csv"))

#












# source("functions/sampling.R")
# set.seed(1234)
# 
# input<-list(
#   strata="adm1_pcode",
#   samp_type="Cluster sampling",
#   stratified="Stratified",
#   topup="Based on population",
#   cls=5,
#   conf_level=0.95,
#   e_marg=0.05,
#   pror=0.5,
#   ICC=0.06,
#   buf=0.1,
#   col_psu="uuid",
#   colpop="pop"
# )

# files <- list.files(
#   path = here(output_dir, "impactoutputs_v1"),
#   pattern = "\\.csv$",
#   full.names = TRUE
# )
# 
# combined <- files %>%
#   map_dfr(\(f) {
#     
#     nm <- basename(f) |> str_remove("\\.csv$")
#     
#     parts <- str_split(nm, "_")[[1]]
#     ids <- tail(parts, 2)
#     
#     readr::read_csv(f) %>%
#       mutate(
#         pop_type = ids[1],
#         region  = ids[2],
#         source_file = nm
#       )
#     
#   })
# 
# joined <- combined %>%
#   left_join(
#     NGA_shapes_all_cleaned$nga_admin2,
#     by = c(Stratification = "adm2_pcode")
#   )

# write_csv(joined, here(output_dir, "sampling_frame_combined.csv"))

# #
# 
# build_sample_plan <- function(
    #     hex_grid,
#     Z = qnorm(0.95),
#     p = 0.5,
#     e = 0.10,
#     m = 6,
#     ICC = 0.06,
#     buffer = 0.10
# ){
#   
#   deff <- 1 + (m - 1) * ICC
#   
#   n0 <- Z^2 * p * (1 - p) / e^2
#   
#   ndeff <- n0 * deff
#   
#   round_up_multiple <- function(x, multiple){
#     ceiling(x / multiple) * multiple
#   }
#   
#   sampleplan <-
#     
#     hex_grid %>%
#     st_drop_geometry() %>%
#     group_by(pop_type, adm2_pcode) %>%
#     summarise(
#       
#       n_pop = sum(pop),
#       
#       N_hh = sum(pop_hh),
#       
#       n_hex = n(),
#       
#       .groups="drop"
#       
#     ) %>%
#     
#     mutate(
#       
#       hh_sample_raw =
#         N_hh * ndeff /
#         (N_hh + ndeff - 1),
#       
#       hh_sample =
#         round_up_multiple(hh_sample_raw, m),
#       
#       hh_sample_buffer =
#         round_up_multiple(
#           hh_sample * (1 + buffer),
#           m
#         ),
#       
#       clusters =
#         as.integer(hh_sample_buffer / m)
#       
#     )
#   
#   sampleplan
#   
# }
# 
# build_sampling_frame <- function(
    #     hex_grid,
#     sampleplan
# ){
#   
#   hex_grid %>%
#     
#     left_join(
#       
#       sampleplan %>%
#         
#         select(
#           pop_type,
#           adm2_pcode,
#           clusters
#         ),
#       
#       by=c(
#         "pop_type",
#         "adm2_pcode"
#       )
#       
#     ) %>%
#     
#     mutate(
#       
#       MOS = pop_hh
#       
#     )
#   
# }
# 
# select_pps_hexagons <- function(
    #     sampling_frame
# ){
#   
#   sampling_frame %>%
#     
#     group_by(
#       pop_type,
#       adm2_pcode
#     ) %>%
#     
#     group_modify(function(df, key){
#       
#       n <- first(df$clusters)
#       
#       pik <-
#         
#         inclusionprobabilities(
#           df$MOS,
#           n
#         )
#       
#       selected <-
#         
#         UPsystematic(
#           pik
#         )
#       
#       df %>%
#         
#         mutate(
#           
#           inclusion_prob = pik,
#           
#           selected =
#             selected == 1
#           
#         )
#       
#     }) %>%
#     
#     ungroup()
#   
# }
# 
# 
# host_plan <- build_sample_plan(hex_grid_host)
# 
# host_frame <- build_sampling_frame(hex_grid_host, host_plan)
# 
# host_sample <- select_pps_hexagons(host_frame)
# 
# 
# 
# idp_plan <- build_sample_plan(hex_grid_idp)
# 
# idp_frame <- build_sampling_frame(hex_grid_idp, idp_plan)
# 
# idp_sample <- select_pps_hexagons(idp_frame)