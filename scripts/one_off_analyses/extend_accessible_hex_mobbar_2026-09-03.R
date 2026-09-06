# ==============================================================================
# Extends accessible_hex.rds (the national, Stage-1 border-buffer-filtered
# candidate hex grid) with the 16 Damasak/Zanna Umarti hexes drawn from
# tonight (2026-09-03) for the Mobbar/FHI 360 ward-level buffer override.
#
# Found while refreshing the accessibility layer (analysis_accessible_area_
# layer.R) for the dashboard: that script's Non-IDP eligibility test is a
# direct spatial query against accessible_hex.rds ("intersects Stage 1's
# accessible hex grid") - since the Mobbar draw injected its 16 new hexes
# into non_idp_sampling$sampling_frame IN MEMORY ONLY (deliberately, to keep
# the national buffer geometry untouched - see CLAUDE.md "Revision
# 2026-09-03"), accessible_hex.rds itself never got these hexes, so Damasak/
# Zanna Umarti's real Non-IDP clusters existed live in the frame while the
# accessibility layer still showed them as ineligible for Non-IDP entirely
# (IDP was fine - eligibility there is a DTM-site-presence test, unrelated
# to this file). This is the canonical, national file every OTHER downstream
# consumer of hex eligibility reads (this layer, analysis_remaining_
# eligible_pool.R, any future supplementary Non-IDP draw) - fixing it here,
# once, is more correct than re-deriving the same 16 hexes again in every
# consumer.
#
# Geometry is IDENTICAL to what the live frame's 15 new clusters were
# actually drawn from (recomputed by the same exact method, verified
# 2026-09-03 to produce the same 16-hex, 10,919-household result) - not a
# new/different construction.
#
# Does NOT touch hex_grid_non_idp.rds or non_idp_sampling (the cached,
# derived pop-by-hex objects) - those stay as they were tonight, since the
# live merge already correctly used an in-memory injection for the actual
# draw and doesn't depend on this file. A future FULL pipeline rerun (rare,
# deliberate, see CLAUDE.md's "don't rerun casually" rule) would pick these
# 16 hexes up automatically once it does, since they're now genuinely part
# of accessible_hex.rds's own candidate set.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(exactextractr); library(terra) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
sf::sf_use_s2(FALSE)
mycrs <- 31028

HEX_PATH <- "input_data/boundaries/nga_hexagons/accessible_hex.rds"
BACKUP_PATH <- "input_data/boundaries/nga_hexagons/accessible_hex_PRE_MOBBAR_backup_2026-09-03.rds"
accessible_hex <- readRDS(HEX_PATH)
if (!file.exists(BACKUP_PATH)) {
  saveRDS(accessible_hex, BACKUP_PATH)
  cat("Backup written:", BACKUP_PATH, "\n")
}
cat("Existing accessible_hex rows:", nrow(accessible_hex), "\n")
n_before <- accessible_hex %>% st_drop_geometry() %>%
  filter(adm2_name == "Mobbar") %>% nrow()
cat("Existing Mobbar rows (should be the original 8-ward set, unchanged):", n_before, "\n")

# ---- Rebuild the same 16 hexes, identical method to the live draw ----
bound_hex_clip <- readRDS("input_data/boundaries/nga_hexagons/hexa_by_admin2.rds")
mob_hex_all <- bound_hex_clip %>% filter(adm2_name == "Mobbar")

grid3 <- sf::st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>%
  st_transform(mycrs)
target_wards <- grid3 %>% filter(wardname %in% c("Damasak", "Zanna Umarti"))
stopifnot(nrow(target_wards) == 2)

new_hexes <- st_intersection(st_make_valid(mob_hex_all), st_make_valid(st_union(target_wards))) %>%
  st_collection_extract("POLYGON") %>% filter(!st_is_empty(geometry))

overlap_check <- st_intersects(new_hexes, accessible_hex, sparse = FALSE)
n_overlap <- sum(rowSums(overlap_check) > 0)
if (n_overlap > 0) stop("New hexes overlap an EXISTING accessible_hex row - would create a duplicate, investigate.")

worldpop_rds <- "input_data/population/worldpop/worldpop_nga_2026_projected.rds"
worldpop_pop <- readRDS(worldpop_rds)
new_hexes_pop <- new_hexes %>%
  mutate(pop_hh = exactextractr::exact_extract(worldpop_pop, new_hexes, "sum") / 6)
new_hexes_eligible <- new_hexes_pop %>% filter(pop_hh > 5)
cat("New eligible hexes (pop_hh > 5):", nrow(new_hexes_eligible), "(expect 16, matching tonight's live draw)\n")

# ---- Populate the columns downstream consumers actually use ----
# (.1/.2-suffixed columns and other admin-boundary metadata are join
# artifacts from the original st_intersection - confirmed unused by
# build_population_by_hex()'s own select() and by analysis_accessible_
# area_layer.R's purely-geometric st_intersects() test - left NA via
# bind_rows() rather than fabricated.)
mobbar_row_ref <- accessible_hex %>% st_drop_geometry() %>% filter(adm2_name == "Mobbar") %>% slice(1)
new_rows <- new_hexes_eligible %>%
  mutate(
    adm2_name = "Mobbar", adm2_pcode = "NG008023",
    adm1_name = "Borno", adm1_pcode = "NG008",
    adm0_name = "Nigeria", adm0_pcode = "NG",
    region = "NE",
    uuid = paste0("hex_mobbar_supp", row_number()),
    uuid_hex = paste0("NE_Borno_Mobbar_hex_mobbar_supp", row_number())
  ) %>%
  select(adm2_name, adm2_pcode, adm1_name, adm1_pcode, adm0_name, adm0_pcode, region, uuid, uuid_hex, geometry)

accessible_hex_extended <- bind_rows(accessible_hex, new_rows)
cat("\nExtended accessible_hex:", nrow(accessible_hex), "->", nrow(accessible_hex_extended), "rows.\n")
# NOTE: accessible_hex.rds already has 131 duplicate uuid_hex values
# nationally, pre-existing before tonight (checked directly against the
# backup - a known artifact of st_intersection/st_collection_extract
# producing multi-part boundary-clip slivers that were never fully
# dissolved; not something to fix here). The real check is that MY 16 new
# rows don't collide with anything ALREADY there, not that the whole file
# has zero duplicates overall (it never did).
collision <- intersect(new_rows$uuid_hex, accessible_hex$uuid_hex)
if (length(collision) > 0) stop("New uuid_hex collides with an EXISTING row: ", paste(collision, collapse = ", "))
if (anyDuplicated(new_rows$uuid_hex) > 0) stop("Duplicate uuid_hex WITHIN the 16 new rows themselves.")
cat("Verified: none of the 16 new uuid_hex values collide with the existing file, and none are duplicated among themselves.\n")

saveRDS(accessible_hex_extended, HEX_PATH)
cat("Saved:", HEX_PATH, "\n")
