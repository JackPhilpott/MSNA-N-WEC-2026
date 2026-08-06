# Step 1: identify which admin2 LGAs can possibly differ across the 3
# border-buffer scenarios (current 20km Niger/5km others; 5km all; 0km/none).
# Any LGA whose polygon is entirely >20km from every relevant international
# border is scenario-invariant - safe to reuse straight from the existing
# cached hex_grid_non_idp.rds/hex_grid_idp.rds (scenario 1) for it, no rework
# needed. This scopes the (expensive) recomputation to only the LGAs that can
# actually change.
suppressMessages({ library(sf); library(dplyr); library(here) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
mycrs <- 31028
data_dir <- here("input_data")
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

admin0_wa_bnds <- st_read(here(boundaries_dir, "wca_admbnda_adm0_edgematched_942026", "wca_admbnda_adm0_edgematched.shp"), quiet = TRUE)
admin0_wa_proj <- st_transform(admin0_wa_bnds, mycrs)
admin0_cast <- st_cast(admin0_wa_proj, to = "MULTILINESTRING") %>%
  filter(adm0_name %in% c("Niger", "Chad", "Cameroon", "Benin"))

admin2_raw <- st_read(here(boundaries_dir, "nga_admin_boundaries", "nga_admin2.shp"), quiet = TRUE) %>% st_transform(mycrs)
admin2 <- process_spatial_layer(admin2_raw)

# Max buffer used anywhere across the 3 scenarios = 20km (Niger, scenario 1 only)
MAX_BUFFER_M <- 20000
border_buffer_max <- st_buffer(st_union(admin0_cast), MAX_BUFFER_M) %>% st_make_valid()

affected <- admin2 %>% filter(st_intersects(., border_buffer_max, sparse = FALSE)[,1])
cat("Admin2 LGAs within", MAX_BUFFER_M, "m of Niger/Chad/Cameroon/Benin border (potentially scenario-sensitive):", nrow(affected), "of", nrow(admin2), "\n")
print(st_drop_geometry(affected) %>% select(adm1_name, adm2_name, adm2_pcode, region) %>% arrange(adm1_name, adm2_name))

saveRDS(affected %>% st_drop_geometry() %>% pull(adm2_pcode),
        "C:/Users/JACKPH~1/AppData/Local/Temp/claude/affected_adm2_pcodes.rds")
saveRDS(admin0_cast, "C:/Users/JACKPH~1/AppData/Local/Temp/claude/admin0_cast_4countries.rds")
saveRDS(admin2, "C:/Users/JACKPH~1/AppData/Local/Temp/claude/admin2_focus.rds")
cat("\nSaved affected pcode list + reusable boundary layers.\n")
