# ==============================================================================
# 2026-10-05 READ-ONLY, (B) building vs WorldPop: wards of the Non-IDP hexes the building check dropped (fewer than 6
# accessible, unclaimed buildings) in the strata the 4 Oct top-ups / 5 Oct spares left short. One row per UNIQUE hex
# (the two batches re-check the same pool; a hex dropped in either counts once - the Coordinator's de-duplication).
# Ward = the GRID3 ward (the draws' own layer) covering the largest share of the hex. Also WorldPop people, estimated
# households, unclaimed accessible buildings (latest check) and a scale tag: "smear" under 200 WorldPop people per
# hex, "settlement" from 200 (the Coordinator's framing for the partner question).
# Usage (from 1_sampling): Rscript resampling/scripts/one_off_analyses/ward_mapping_dropped_hexes_2026-10-05.R
# ==============================================================================
suppressPackageStartupMessages({ library(sf); library(dplyr); library(readr) })
sf_use_s2(FALSE)
OUT <- file.path("resampling", "output", "analysis_building_vs_worldpop_2026-10-05")
by_stratum <- read_csv(file.path(OUT, "building_vs_worldpop_by_stratum.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
short <- by_stratum %>% filter(as.integer(delivered) < as.integer(requested)) %>% distinct(strata_id, lga, state, partners_covering)

pv_files <- c(Sys.glob("resampling/output/resample_runs/*/2026-10-04_nonidp_topup_150rule/pool_validation_by_hex.csv"),
              Sys.glob("resampling/output/resample_runs/*/2026-10-05_spares/pool_validation_by_hex.csv"))
pv <- bind_rows(lapply(pv_files, function(p) {
  x <- read_csv(p, col_types = cols(.default = "c"), show_col_types = FALSE)
  if (nrow(x) == 0) return(NULL)
  x %>% mutate(batch_rank = if (grepl("2026-10-05_spares", p)) 2L else 1L)
}))
dropped_ids <- unique(pv$uuid_hex_pop[pv$eligible != "TRUE"])
latest <- pv %>% group_by(uuid_hex_pop) %>% slice_max(batch_rank, n = 1, with_ties = FALSE) %>% ungroup() %>%
  transmute(uuid_hex_pop, n_acc_latest = as.integer(n_acc))

hexes <- readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds") %>%
  filter(uuid_hex_pop %in% dropped_ids) %>% mutate(strata_id = paste0("non_idp_", adm2_pcode)) %>%
  filter(strata_id %in% short$strata_id)
wards <- st_read(file.path("input_data", "boundaries", "GRID3_NGA_Ward_Boundaries_v1", "grid3_nga_boundary_vaccwards.shp"), quiet = TRUE)
wards <- st_transform(wards, st_crs(hexes))
ward_name_col <- intersect(c("wardname", "ward_name", "WardName", "ward"), names(wards))[1]
ward_code_col <- intersect(c("wardcode", "ward_code", "WardCode", "wardcode_1"), names(wards))[1]
hexes$hex_area <- as.numeric(st_area(hexes))
parts <- suppressWarnings(st_intersection(hexes %>% select(uuid_hex_pop, hex_area),
                                          wards %>% select(ward = all_of(ward_name_col), ward_code = all_of(ward_code_col))))
parts$share <- as.numeric(st_area(parts)) / parts$hex_area
dominant <- parts %>% st_drop_geometry() %>% group_by(uuid_hex_pop) %>% arrange(desc(share)) %>%
  summarise(ward = first(ward), ward_code = first(ward_code), ward_share = round(first(share), 2),
            other_wards = paste(ward[-1], collapse = "; "), .groups = "drop")
tab <- hexes %>% st_drop_geometry() %>%
  select(uuid_hex_pop, strata_id, state = adm1_name, lga = adm2_name, pop, estimated_households) %>%
  left_join(short %>% select(strata_id, partners_covering), by = "strata_id") %>%
  left_join(dominant, by = "uuid_hex_pop") %>% left_join(latest, by = "uuid_hex_pop") %>%
  mutate(worldpop_people = round(pop), est_households = round(estimated_households),
         scale = if_else(worldpop_people >= 200, "settlement", "smear")) %>%
  select(state, lga, strata_id, partners_covering, ward, ward_code, ward_share, other_wards, uuid_hex_pop,
         worldpop_people, est_households, n_acc_latest, scale) %>% arrange(state, lga, desc(worldpop_people))
write_csv(tab, file.path(OUT, "dropped_hexes_by_ward.csv"))
by_ward <- tab %>% group_by(state, lga, partners_covering, ward, scale) %>%
  summarise(hexes = n(), worldpop_people = sum(worldpop_people), zero_building_hexes = sum(n_acc_latest == 0, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(worldpop_people))
write_csv(by_ward, file.path(OUT, "dropped_hexes_by_ward_summary.csv"))
cat(sprintf("unique dropped hexes in short strata: %d (%d settlement-scale, %d smear); wards: %d; WorldPop people %s\n",
            nrow(tab), sum(tab$scale == "settlement"), sum(tab$scale == "smear"), n_distinct(paste(tab$lga, tab$ward)),
            format(sum(tab$worldpop_people), big.mark = ",")))
print(as.data.frame(head(by_ward %>% filter(scale == "settlement"), 25)), row.names = FALSE)
