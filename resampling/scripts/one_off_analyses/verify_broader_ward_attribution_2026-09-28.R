# ==============================================================================
# Follow-up to verify_monguno_ward_attribution_2026-09-28.R: the Monguno
# check found adm3_name geometrically correct (518/518) and admin3_cod_name
# wrong for 411/518. National scan found this is NOT isolated - 26,840 of
# 38,901 WORKING rows (69%) have adm3_name != admin3_cod_name, spanning 994
# (LGA, ward) pairs. This script geometrically spot-checks several more
# high-volume mismatched pairs (incl. Damboa, one of tonight's own draw
# targets) the SAME rigorous way - real point-in-polygon against the GRID3
# shapefile - to see whether the Monguno pattern (adm3_name correct) holds
# generally, or whether some pairs go the other direction.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
sf::sf_use_s2(TRUE)

wards <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>% st_transform(4326)
working <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_WORKING.csv", show_col_types = FALSE)

TARGETS <- list(
  c(lga = "Damboa", adm3 = "Damboa"),
  c(lga = "Kala/Balge", adm3 = "Rann"),
  c(lga = "Tangaza", adm3 = "Tangaza"),
  c(lga = "Bama", adm3 = "Shehuri")
)

for (t in TARGETS) {
  rows <- working %>% filter(adm2_name == t["lga"], adm3_name == t["adm3"]) %>%
    filter(!is.na(latitude), !is.na(longitude))
  cat(sprintf("\n==== %s / %s: %d rows ====\n", t["lga"], t["adm3"], nrow(rows)))
  if (nrow(rows) == 0) next
  pts <- rows %>% st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  joined <- st_join(pts, wards, join = st_within) %>% st_drop_geometry()
  cat("  TRUE geometric wardname distribution:\n")
  print(table(joined$wardname, useNA = "ifany"))
  agree_adm3 <- sum(joined$adm3_name == joined$wardname, na.rm = TRUE)
  agree_cod <- sum(joined$admin3_cod_name == joined$wardname, na.rm = TRUE)
  cat(sprintf("  adm3_name matches true geometry: %d/%d | admin3_cod_name matches true geometry: %d/%d\n",
              agree_adm3, nrow(joined), agree_cod, nrow(joined)))
}
cat("\n==== DONE ====\n")
