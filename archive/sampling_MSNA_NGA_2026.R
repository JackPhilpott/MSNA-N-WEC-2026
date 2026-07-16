## NIGERIA SAMPLING FOR MSNA NORTH-WEST/EAST/CENTRAL 2026 ## 
# this script is developed to the sampling framework for the 2026 MSNA project in the North-West/East/Central of Nigeria
# the script is following the IMPACT global research design guidelines (Annex 5) for GIS sampling guidance
# produced by Jack Philpott (NGA MSNA SAO) - 24/06/2026

# library(ggthemes)
# library(leaflet)
# library(plotly)
# library(shapefiles)

library(sf)
library(terra)
library(stars)
library(dplyr)
library(ggplot2)
library(ggrepel)
library(tidyterra)
library(janitor)
library(exactextractr)
library(patchwork)
library(uuid)

## ---- 1. set global environment ---- 

# set the project crs for the geoprocessing :
mycrs <- 31028 #WGS 84 / UTM zone 28N. unit in meters
newcrs <- st_crs(sprintf('epsg:%s', mycrs))

# set an optio to overwrite the files already produced - this helps with processing
raster_toload           = F
hexa_tocreate           = F
# access_tocomputer       = T
hexa_intersect_tocreate = T
raster_toaggregate      = T

# focused admin1s by region as defined by IMPACT and FACT - this is an alternative to use the refsheet above

refsheet_admin1 <- read.csv("input_data/Refsheet_admin1.csv")

# NW: Kanuda, Kano, Katsina, Sokoto, Zamfara (priority are Katsina, Sokoto, Zamfara)
# NG019, NG020, NG021, NG034, NG037

# NC: Benue, Kogi, Nasarawa, Niger, Plateau
# NG007, NG023, NG026, NG027, NG032

# NE: Adamawa, Borno, Yobe
# NG002, NG008, NG036

# create lists of relevant admin1 pcodes - separately by region in case want to run regional sampling
nga_admin1_pcodes_nw <- c("NG019", "NG020", "NG021", "NG034", "NG037")
nga_admin1_pcodes_ne <- c("NG002", "NG008", "NG036")
nga_admin1_pcodes_nc <- c("NG007", "NG023", "NG026", "NG027", "NG032")

# joining the 3 region lists for whole assessment sampling
admin1_focus_areas <- c(nga_admin1_pcodes_nc, nga_admin1_pcodes_ne, nga_admin1_pcodes_nw)


## ---- 2 bring in GIS data ----
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
# ---- 2.1 admin boundaries ----

# ---- 2.1.1 west african admin0 ----

# bring in west african admin0 boundaries to be used with buffers later 
admin0_wa_bnds <- st_read("input_data/boundaries/wca_admbnda_adm0_edgematched_942026/wca_admbnda_adm0_edgematched.shp")
admin0_wa_proj <- safe_transform(admin0_wa_bnds, mycrs)


# visualise hex data - only running to check, don't run and save memory if not needed
# ggplot() +
#   geom_sf(data=admin0_wa_bnds, color = "white", lwd=0.01, aes(fill = adm0_pcode)) +
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tl")

# ---- 2.1.2 nigeria all admins ----

# set paths
admin_bnds_path <- file.path("input_data/boundaries/nga_admin_boundaries/")

# 1. List of shapefile paths
shapefiles <- list.files(
  path = admin_bnds_path,          # folder containing .shp files
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
NGA_shapes_all <- lapply(sf_list, function(x) safe_transform(x, mycrs))

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
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tr",which_north = "grid")


## ---- 2.2. population ----
population_data_path <- file.path("input_data/population")

# ---- 2.2.1 Host - GRID3 ----
if(!file.exists(paste0(population_data_path, "/grid3/grid3_nga_100m_projected.rds")) | raster_toload){
  
# call in raster dataset
grid3_load <- rast(paste0(population_data_path, "/grid3/NGA_population_v3_0_gridded.tif"))

# project first in order to match admin boundaries
grid3_proj <- project(grid3_load, y=sprintf('epsg:%s', mycrs))

# then crop to the area of focus
grid3_crop <- crop(grid3_proj, y=st_bbox(NGA_shapes_all_cleaned$nga_admin1))

# view the raster to check the extent (have to do it here before converted to stars object as not compatible with ggplot)
ggplot() +
  geom_spatraster(data = grid3_crop) +
  scale_fill_viridis_c(name = "Value") +
  geom_sf(data = NGA_shapes_all_cleaned$nga_admin1, fill = NA, color = "white", size = 0.2) +
  geom_text_repel(data = NGA_shapes_all_cleaned$nga_admin1, aes(label = adm1_name, geometry = geometry),stat = "sf_coordinates", size = 3)

# convert to stars object as it's a clean way to manage spatial data and works well with the sf package
grid3_stars <- st_as_stars(grid3_crop)

# save the new projected/cropped file so then can be reread easily later
saveRDS(grid3_stars, paste0(population_data_path, "/grid3/grid3_nga_100m_projected.rds"))

} else {
  grid3_stars<-readRDS(paste0(population_data_path, "/grid3/grid3_nga_100m_projected.rds"))
}

# ---- 2.2.2 Host - WorldPop ----
if(!file.exists(paste0(population_data_path, "/worldpop/worldpop_nga_2026_projected.rds")) | raster_toload){

# call in raster dataset
worldpop_load <- rast(paste0(population_data_path, "/worldpop/worldpop_nga_pop_2026_CN_100m_R2025A_v1.tif"))

# project first in order to match admin boundaries
worldpop_proj <- project(worldpop_load, y=sprintf('epsg:%s', mycrs))

# then crop to the area of focus
worldpop_crop <- crop(worldpop_proj, y=st_bbox(NGA_shapes_all_cleaned$nga_admin1))

# view the raster to check the extent (have to do it here before converted to stars object as not compatible with ggplot)
ggplot() +
  geom_spatraster(data = worldpop_crop) +
  scale_fill_viridis_c(name = "Value") +
  geom_sf(data = NGA_shapes_all_cleaned$nga_admin1, fill = NA, color = "white", size = 0.2) +
  geom_text_repel(data = NGA_shapes_all_cleaned$nga_admin1, aes(label = adm1_name, geometry = geometry),stat = "sf_coordinates", size = 3)

# convert to stars object as it's a clean way to manage spatial data and works well with the sf package
worldpop_stars <- st_as_stars(worldpop_crop)

# save the new projected/cropped file so then can be reread easily later
saveRDS(worldpop_stars, paste0(population_data_path, "/worldpop/worldpop_nga_2026_projected.rds"))

} else {
  worldpop_stars<-readRDS(paste0(population_data_path, "/worldpop/worldpop_nga_2026_projected.rds"))
}

# ---- 2.2.3 IDP - IOM ----
# if(!file.exists("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds") | hexa_tocreate){

iom_idp_NE <- read.csv("input_data/population/iom/IMPACT_IOM_NGA_R51_NE.csv")

iom_idp_NE <- iom_idp_NE %>% 
  clean_names() %>% 
  remove_empty(which = c("rows", "cols")) %>% 
  distinct() %>% 
  mutate(region = "NE") 

iom_idp_NCNW <- read.csv("input_data/population/iom/IMPACT_IOM_NGA_R18_NCNW.csv")

iom_idp_NCNW <- iom_idp_NCNW %>% 
  clean_names() %>% 
  remove_empty(which = c("rows", "cols")) %>% 
  distinct() %>% 
  mutate(location_type = case_when(
    population_category == "Returnees" ~ "Returnee Location",
    TRUE ~ "IDP Location"),
    region = "NCNW",
    join_name = paste(state, lga, ward, sep = "_")) 
 
# need to get coordinates for NCNW IDP results - do this using the GRID3 ward 

admin3_allnga      <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp")
admin3_allnga_proj <- safe_transform(admin3_allnga, mycrs)

admin3_allnga_proj <- admin3_allnga_proj %>% 
  mutate(
  join_name = paste(statename, lganame, wardname, sep = "_"))






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

# join the two idp tables
iom_combined_df <- safe_bind_rows_allow_extra(iom_idp_NE, iom_idp_NCNW)

iom_idp_df <- iom_combined_df %>% 
  filter(location_type == "IDP Location") %>% 
  mutate(
    individuals = suppressWarnings(as.numeric(individuals)), # convert, suppress warnings for NAs
    households = suppressWarnings(as.numeric(households)) # convert, suppress warnings for NAs
  )

# write.csv(iom_idp_df, "ite.csv")
# 

# saveRDS(bound_hex_clip,"input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
# }else{
#   bound_hex_clip<-readRDS("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
# }


#temporarily writing it out and going to sample at the lga level, but next step is to get gps for all and go to hex
idp_2agg <- iom_idp_df %>% 
  group_by(region, state_pcode, state, lga) %>% 
  summarise(
    tot_pop = sum(individuals, na.rm = TRUE),
    tot_hh = sum(households, na.rm = TRUE),
    .groups = "drop") 

write.csv(idp_2agg, "impact_iom_idp_tosample.csv")












#










## ---- 3. Create hexagon grid ---- 
if(!file.exists("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds") | hexa_tocreate){
# create hexagon grid
bound_hex_create <- st_make_grid(NGA_shapes_all_cleaned$nga_admin2, cellsize = 5000, square = FALSE)

# convert to sf object
bound_hex_sf <- st_sf(geometry = bound_hex_create)

#intersect the results to the focus area. attributes and value are also transferred. it isn't necessary to a spatial join after this
bound_hex_clip <- st_intersection(NGA_shapes_all_cleaned$nga_admin2, bound_hex_sf) # might be quite slow to run on a large area.

bound_hex_clip <- bound_hex_clip %>% 
  mutate(uuid = paste0("hex_", row_number()),
         uuid_hex = paste(region, adm1_name, adm2_name, uuid, sep = "_"))

saveRDS(bound_hex_clip,"input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
}else{
  bound_hex_clip<-readRDS("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
}

# visualise hex data - only running to check, don't run and save memory if not needed
# ggplot() +
#   geom_sf(data=bound_hex_clip, color = "white", lwd=0.01, aes(fill = adm1_pcode)) +
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tl")


## ---- 4. Defining accessible areas ----
# focused admin1s by region as defined by IMPACT and FACT

# ---- 4.1.1 international buffer ----
# create a buffer 20km from the Niger country border, and 5km from the Chad and Cameroon border
admin0_cast <- st_cast(admin0_wa_proj, to = "MULTILINESTRING")

admin0_wa_buff <- admin0_cast %>%
  mutate(
    buffer_m = case_when(
      adm0_name %in% c("Chad", "Cameroon") ~ 5000,
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
#   theme_minimal()



# 4.1.2 insecure areas from FACT ----
FACT_accessibility <- read.csv("input_data/boundaries/nga_accessibility/NGA_Sampling_accessibility_FACT_admin3_NE.csv")

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

# test <- st_drop_geometry(NGA_shapes_all_cleaned$nga_admin3)
# 
# library(sfheaders)
# write.csv(test, "NGA_Admin3_lostgeom.csv")
# write.csv(FACT_noaccess, "FACT_noaccess.csv")

# visualise excluded no access area - only running to check, don't run and save memory if not needed
# ggplot() + 
#   geom_sf(data=admin3_noaccess)+
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tl")

# ---- 4.2 clip non coverage areas ----

## the reason for doing this clip kinda excessive way of clipping is because the geometries weren't aligning properly for the clip...
## which basically meant the admin3 restricted areas would cut but the buffered areas wouldn't

# Ensure all layers have the same CRS
# target_crs <- st_crs(NGA_shapes_all_cleaned$nga_admin1)

clip_admin1 <- NGA_shapes_all_cleaned$nga_admin1 %>%
  st_make_valid() %>%
  st_transform(mycrs)

clip_noaccess <- admin3_noaccess %>%
  st_make_valid() %>%
  st_transform(mycrs)

clip_buffered <- nga_buffered %>%
  st_make_valid() %>%
  st_transform(mycrs)

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
  geom_sf(data = admin1, fill = "lightblue", color = "grey40", size = 0.3) +
  geom_sf(data = noaccess, fill = "red", alpha = 0.4, color = NA) +
  geom_sf(data = buffered, fill = "orange", alpha = 0.4, color = NA) +
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


# crop out the inaccessible hexagons by intersecting roads and hexagons

if(!file.exists("input_data/boundaries/nga_hexagons/accessible_hex.rds") | hexa_intersect_tocreate){
  hexgrid<-st_intersection(bound_hex_clip,accessible_area)
  saveRDS(hexgrid,"input_data/boundaries/nga_hexagons/accessible_hex.rds")
} else {
  hexgrid<-readRDS("input_data/boundaries/nga_hexagons/accessible_hex.rds")
}

# visualise hexgrid - only running to check, don't run and save memory if not needed

# ggplot() +
#   geom_sf(data=hexgrid, color = "white", lwd=0.01, aes(fill = adm2_pcode),) +
#   # geom_text_repel(data = NGA_shapes_all_cleaned$nga_admin2, aes(label = adm2_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tl")
# # 
# ggplot() +
#   geom_sf(data=hexgrid)+
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tl")









## ---- loops??  ----
## maybe want to do some big nested loops here
## ideally would be able to chunk up the code and loop through both pop type and region


## ---- 6. population by hex ----

## ---- 6.1 host hex ---- 

# list all the cells
# Extract info, with the exact method. 
# if(!file.exists(paste0(population_data_path, "/sampling_frame/sampling_frame.rds")) | raster_toaggregate){
#   sampling_fr<-aggregate(worldpop_stars,hexgrid,FUN=sum,na.rm=T,exact=T)
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
#     write.csv(split_data[[i]], file_name, row.names = FALSE)
#   }
#   
#   
# }else {
#   hexgrid<-readRDS(paste0(population_data_path, "/sampling_frame/sampling_frame.rds"))
# }



sampling_fr<-aggregate(worldpop_stars,hexgrid,FUN=sum,na.rm=T,exact=T)

names(sampling_fr)<-"pop"
sampling_poly<-st_as_sf(sampling_fr)

  # add population number
hexgrid$pop<-sampling_poly$pop

  # add unique id since it was missing.
hexgrid$uuid<-ids::uuid(n=nrow(hexgrid))
saveRDS(hexgrid, paste0(population_data_path, "/sampling_frame/sampling_frame.rds"))

  # write sampling frame
writexl::write_xlsx(hexgrid,"output/sampling_frame_nondisp_v1.xlsx")

# Split dataframe by 'group' column
split_data <- hexgrid %>%
  group_by(region) %>%
  group_split()

# Get the unique group names in the same order as split_data
group_names <- hexgrid %>%
  group_by(region) %>%
  group_keys() %>%
  pull(region)

# Write each subset to a separate CSV
for (i in seq_along(split_data)) {
  file_name <- paste0("output/sampling_frame_nondisp_v1_", group_names[i], ".csv")
  write.csv(split_data[[i]], file_name, row.names = FALSE)
}



ggplot() +  
  geom_sf(data=nga_admin1_filtered) +
  geom_sf(data=hexgrid, color = "white", lwd=0.01, aes(fill = pop),) +
  geom_text_repel(data = nga_admin1_filtered, aes(label = adm1_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
  theme_void()+
  annotation_scale(location="br")+
  annotation_north_arrow(location="tl")

# 
# source("functions/sampling.R")
# #
# 
# 
# 
# devtools::install_github("oliviercecchi/Probability-sampling-tool")






## ---- 6.2 idp hex ---- 






#### ---- __Archive__ ####

# admin1_path <- file.path(admin_bnds_path, "nga_admin1.shp")
# 
# # get the admin1 and project
# admin1_shp <- read.shapefile(admin1_path)

# admin1_proj <- admin1_shp |>  st_transform(crs = mycrs)
# 
# xx <- st_transform(admin1_shp$shp, crs = mycrs)
# 
# yy <- st_read(admin1_path)
# yyy <- st_transform(yy, crs = mycrs)
# 
# 
# # Function to safely read and transform a single shapefile
# safe_read_transform <- function(path, target_crs) {
#   tryCatch({
#     if (!file.exists(path)) {
#       stop(paste("File does not exist:", path))
#     }
#     
#     # Read shapefile (sf automatically detects CRS)
#     shp <- st_read(path, quiet = TRUE)
#     
#     # Validate CRS
#     if (is.null(st_crs(shp))) {
#       stop(paste("Shapefile has no defined CRS:", path))
#     }
#     
#     # Transform
#     transformed <- st_transform(shp, crs = target_crs)
#     return(transformed)
#     
#   }, error = function(e) {
#     message("Error processing ", path, ": ", e$message)
#     return(NULL)
#   })
# }
# 
# 
# # ==========================================
# # Example: transform a list of shapefile paths
# # ==========================================
# 
# # Example list of shapefile paths
# shp_list <- c(
#   paste0(admin_bnds_path, "/nga_admin0.shp"),
#   paste0(admin_bnds_path, "/nga_admin1.shp"),
#   paste0(admin_bnds_path, "/nga_admin2.shp"),
#   paste0(admin_bnds_path, "/nga_admin3.shp")
# )
# 
# # Apply transformation to each
# result_list <- lapply(shp_list, function(x) safe_read_transform(x, mycrs))
# 
# # Remove failures (NULL entries)
# result_list <- Filter(Negate(is.null), result_list)
# 
# # Print results
# print(result_list)

# NW: Kanuda, Kano, Katsina, Sokoto, Zamfara (priority are Katsina, Sokoto, Zamfara)
# NG019, NG020, NG021, NG034, NG037

# NC: Benue, Kogi, Nasarawa, Niger, Plateau
# NG007, NG023, NG026, NG027, NG032

# NE: Adamawa, Borno, Yobe
# NG002, NG008, NG036

# create lists of relevant admin1 pcodes - separately by region in case want to run regional sampling
# nga_admin1_pcodes_nw <- c("NG019", "NG020", "NG021", "NG034", "NG037")
# nga_admin1_pcodes_ne <- c("NG002", "NG008", "NG036")
# nga_admin1_pcodes_nc <- c("NG007", "NG023", "NG026", "NG027", "NG032")
# 
# # joining the 3 region lists for whole assessment sampling
# admin1_focus_areas <- c(nga_admin1_pcodes_nc, nga_admin1_pcodes_ne, nga_admin1_pcodes_nw)
# 
# # filter admin1 and 2 boundaries by the study area ... at some point maybe turn it in a function to apply to all necessary layers
# nga_admin1_filtered <- NGA_shapes_all$nga_admin1 %>% 
#   filter(adm1_pcode %in% admin1_focus_areas) %>% 
#   mutate(region = case_when(
#     adm1_pcode %in% nga_admin1_pcodes_nc ~ "NC",
#     adm1_pcode %in% nga_admin1_pcodes_ne ~ "NE",
#     adm1_pcode %in% nga_admin1_pcodes_nw ~ "NW",
#     TRUE ~ "not included area"
#   )) %>% 
#   select(where(~ !all(is.na(.))))
# 
# nga_admin2_filtered <- NGA_shapes_all$nga_admin2 %>% 
#   filter(adm1_pcode %in% admin1_focus_areas) %>% 
#   mutate(region = case_when(
#     adm1_pcode %in% nga_admin1_pcodes_nc ~ "NC",
#     adm1_pcode %in% nga_admin1_pcodes_ne ~ "NE",
#     adm1_pcode %in% nga_admin1_pcodes_nw ~ "NW",
#     TRUE ~ "not included area"
#   )) %>% 
#   select(where(~ !all(is.na(.))))


# visualise new filtered area - only running to check, don't run and save memory if not needed
# ggplot() + 
#   geom_sf(data=nga_admin1_filtered,fill="white") +
#   geom_text_repel(data = Nnga_admin1_filtered, aes(label = adm1_pcode, geometry = geometry),stat = "sf_coordinates", size = 3)+
#   theme_void()+
#   annotation_scale(location="br")+
#   annotation_north_arrow(location="tr",which_north = "grid")

# unique(admin0_wa_proj$adm0_name)
# 
# admin0_buffer_rules <- data.frame(
#   neighbour = c("Chad", "Cameroon", "Niger"),
#   buffer_m = c(5000, 5000, 20000)
# )
# 
# neighbours_list <- st_touches(admin0_wa_proj)
# 
# # 2. Create a column for buffer distance
# admin0_wa_proj$buffer_m <- 10000  # default 10 km
# 
# for (i in seq_len(nrow(admin0_wa_proj))) {
#   neighbor_names <- admin0_wa_proj$name_long[neighbours_list[[i]]]
#   
#   # Check if any neighbor matches our rules
#   match_rule <- admin0_buffer_rules %>%
#     filter(neighbour %in% neighbor_names) %>%
#     arrange(desc(buffer_km)) %>%  # pick largest if multiple
#     slice_head(n = 1)
#   
#   if (nrow(match_rule) > 0) {
#     admin0_wa_proj$buffer_m[i] <- match_rule$buffer_km * 1000
#   }
# }


# admin0_wa_buff <- admin0_wa_proj %>%
#   mutate(
#     buffer_m = case_when(
#       adm0_name %in% c("Chad", "Cameroon") ~ 5000,
#       adm0_name == "Niger" ~ 20000,
#         TRUE ~ NA_real_
#       )) %>% 
#   filter(!is.na(buffer_m))
# 
# # 3. Apply st_buffer with per-feature distances
# nga_buffered <- st_buffer(admin0_wa_buff, dist = admin0_wa_buff$buffer_m)
# 
# # 4. Example: plot original vs buffered for a subset
# ggplot() +
#   geom_sf(data = admin0_wa_proj, fill = "lightblue") +
#   geom_sf(data = world_buffered, fill = NA, color = "red") +
#   theme_minimal()

# # Example: Target country = "Niger"
# target_country <- "Nigeria"
# 
# # Define buffer sizes for each bordering country
# border_buffer_map <- tibble::tibble(
#   border_country = c("Chad", "Cameroon", "Niger"),
#   buffer_m       = c(5000,   5000,  20000)  # in meters
# )
# 
# # Filter for target country and its borders, then join buffer sizes
# test <- admin0_cast %>%
#   filter(adm0_name == target_country | adm0_name %in% border_buffer_map$border_country) %>%
#   left_join(border_buffer_map, by = c("adm0_name" = "border_country")) %>%
#   mutate(
#     buffer_m = as.double(buffer_m)  # ensure numeric double
#   ) %>%
#   filter(!is.na(buffer_m))  # keep only rows with buffer values
# 
# # Check type
# typeof(test$buffer_m)  # should return "double"
# 
# 
# # 4. Example: plot original vs buffered for a subset
# ggplot() +
#   # geom_sf(data = admin0_wa_proj, fill = "lightblue") +
#   geom_sf(data = test, fill = NA, color = "red") +
#   theme_minimal()

