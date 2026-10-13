# ==============================================================================
# 2026-10-13 re-render (#40 touch-ups, Jack via the Coordinator), otherwise identical to render_tor_maps_2026-10-12.R:
#   - an LGA no partner was ever assigned to (30 Jul coverage list: not_covered) is 'Excluded: no partner coverage',
#     whatever its design-time certainty flag - the 17 Kano/Niger/Kaduna LGAs the 12 Oct maps drew as 'certainty stratum
#     (precision)'; with that, no LGA is left in the certainty class, so a legend class with nothing drawn is left out
#   - the NC region label sits in southern Niger State (6.4 E, 9.35 N), off the FCT
#   - writes into output/maps/tor_final_2026-10-13/ (the 12 Oct set is left as it was)
# 2026-10-12 (#40; Jack via the Coordinator, for Claude Web's final ToR, B1 + B2): re-renders
#   ToR Figure 1      - design map, in the population-group style of analysis_coverage_map2.R "alt2"
#   ToR Annex A1.1    - frame map (Figure 6), in the style of 08_render_methodology_maps.R's overview
# on the post-6 Aug DESIGN basis (initial draw + July correction + 6 Aug NW targeted resample + 30 Jul coverage list,
# no fieldwork supplementary/spare/top-up clusters: 3,428 clusters / 31,559 interviews), with Mobbar IDP (3 Sep)
# drawn, and the exclusion legend split into: border buffer | inaccessible Admin-3 | certainty stratum (precision) |
# no partner coverage. Two variants each:
#   (a) design-time exclusions: the post-6 Aug buffer (Niger 20 km in Borno/Yobe, 5 km on every other segment) and the
#       Admin-3 layer that existed at the design (FACT's North-East file, matched by name exactly as the pipeline did)
#   (b) today's partner-reported Admin-3 (all regions: resampling/output/gis/accessible_area_lga_ward_portions.shp),
#       with planned clusters whose centroid now falls in an excluded area drawn with a heavy black outline
# Damasak and Zanna Umarti (Mobbar) are re-admitted inside the 20 km buffer (3 Sep decision) in both variants.
# READ-ONLY on every project file: sources 01_sampling_pipeline_main.R up to the IOM IDP table (boundaries, the
# WorldPop cache, IOM sites; every cache it touches exists and every opt_list$rebuild_* is FALSE, so it writes
# nothing), builds the buffer/Admin-3 layers itself (never touches accessible_hex.rds or any cache), and writes ONLY
# into output/maps/tor_final_2026-10-12/ (4 PNGs, counts_by_legend_class.csv, verification_log.txt).
# Usage (from 1_sampling): Rscript scripts/methodology_maps/render_tor_maps_2026-10-12.R
# ==============================================================================
OUT <- file.path("output", "maps", "tor_final_2026-10-13")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
LOG <- file(file.path(OUT, "verification_log.txt"), open = "wt")
say <- function(...) { m <- paste0(...); cat(m, "\n"); cat(m, "\n", file = LOG) }
saytab <- function(df) { txt <- capture.output(print(as.data.frame(df), row.names = FALSE)); cat(txt, sep = "\n"); cat(txt, sep = "\n", file = LOG) }
say("==== ToR maps #40 - run ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ====")

# ---- 0. the pipeline's own boundaries, WorldPop cache and IOM sites (read-only prefix) ----
lines <- readLines("scripts/01_sampling_pipeline_main.R")
i_iom <- grep("^iom_idp_df <- idp_combined_df", lines)
stopifnot(length(i_iom) == 1, grepl("^\\s*\\)\\s*$", lines[i_iom + 4]))
prefix <- file.path(tempdir(), "tor_pipeline_prefix.R")
writeLines(lines[1:(i_iom + 4)], prefix)
source(prefix)
stopifnot(!any(unlist(opt_list)))
suppressPackageStartupMessages({ library(ggplot2); library(terra); library(tidyterra); library(ggrepel); library(cowplot); library(grid); library(readr) })
sf::sf_use_s2(TRUE)
EQA <- 6933   # equal-area CRS for every area figure (WGS 84 / NSIDC EASE-Grid 2.0 Global)
say("pipeline prefix sourced: lines 1-", i_iom + 4, " | working CRS EPSG:", mycrs, " (", sf::st_crs(mycrs)$Name, ")")

admin1 <- NGA_shapes_all_cleaned$nga_admin1
admin2 <- NGA_shapes_all_cleaned$nga_admin2
admin3 <- NGA_shapes_all_cleaned$nga_admin3 %>% mutate(uuid = paste(adm1_name, adm2_name, adm3_name, sep = "_"))
focus_union <- st_union(st_make_valid(admin1))
reg_of <- function(p) ifelse(p %in% nga_admin1_pcodes_ne, "NE", ifelse(p %in% nga_admin1_pcodes_nw, "NW", ifelse(p %in% nga_admin1_pcodes_nc, "NC", NA)))
region_union <- lapply(c(NC = "NC", NE = "NE", NW = "NW"), function(r) st_union(st_make_valid(admin1[reg_of(admin1$adm1_pcode) == r, ])))
km2 <- function(g) if (length(g) == 0 || all(st_is_empty(g))) 0 else as.numeric(sum(st_area(st_transform(st_make_valid(g), EQA)))) / 1e6

# ---- 1. border buffer: the post-6 Aug rule exactly as 01_sampling_pipeline_main.R lines 480-502, in EPSG:31028 ----
admin0_cast <- st_cast(admin0_wa_proj, to = "MULTILINESTRING")
niger_line <- admin0_cast %>% filter(adm0_name == "Niger")
other_lines <- admin0_cast %>% filter(adm0_name %in% c("Chad", "Cameroon", "Benin"))
ne_union <- admin1 %>% filter(adm1_pcode %in% nga_admin1_pcodes_ne) %>% st_make_valid() %>% st_union()
ncnw_union <- admin1 %>% filter(adm1_pcode %in% c(nga_admin1_pcodes_nc, nga_admin1_pcodes_nw)) %>% st_make_valid() %>% st_union()
niger20 <- st_buffer(niger_line, 20000) %>% st_union() %>% st_make_valid()
niger5 <- st_buffer(niger_line, 5000) %>% st_union() %>% st_make_valid()
other5 <- st_buffer(other_lines, 5000) %>% st_union() %>% st_make_valid()
buffer_new <- st_union(st_union(st_intersection(niger20, ne_union), st_intersection(niger5, ncnw_union)), other5) %>% st_make_valid()
buffer_old <- st_union(niger20, other5) %>% st_make_valid()   # pre-6 Aug rule: Niger 20 km on every segment
grid3 <- st_read("input_data/boundaries/GRID3_NGA_Ward_Boundaries_v1/grid3_nga_boundary_vaccwards.shp", quiet = TRUE) %>% st_transform(mycrs)
mobbar_wards <- grid3 %>% filter(wardname %in% c("Damasak", "Zanna Umarti"))
stopifnot(nrow(mobbar_wards) == 2)
readmit <- st_union(st_make_valid(mobbar_wards))
buffer_focus <- st_intersection(buffer_new, focus_union) %>% st_make_valid()
buffer_layer <- st_difference(buffer_focus, readmit) %>% st_make_valid()

# ---- 2. Admin-3 layers ----
# (a) design time: FACT's North-East file, filtered and name-matched exactly as the pipeline (lines 513-537)
fact <- read.csv(here::here(boundaries_dir, "nga_accessibility", "NGA_Sampling_accessibility_FACT_admin3_NE.csv")) %>%
  janitor::clean_names() %>% janitor::remove_empty(which = c("rows", "cols")) %>%
  mutate(uuid = paste(state, lga, ward_community, sep = "_")) %>% distinct()
fact_no <- fact %>% filter(accessibility_status %in% c("Not Existing", "Inaccessible"))
admin3_a <- admin3 %>% filter(uuid %in% fact_no$uuid)
admin3_a_only <- st_difference(st_intersection(st_union(st_make_valid(admin3_a)), focus_union), buffer_layer) %>% st_make_valid()
# (b) today: every LGA-ward portion a partner reports Inaccessible (all regions), clipped to the 14 states
portions <- st_read("resampling/output/gis/accessible_area_lga_ward_portions.shp", quiet = TRUE) %>% st_transform(mycrs) %>% st_make_valid()
stopifnot("accssb_" %in% names(portions))
inacc_b <- portions %>% filter(accssb_ == "Inaccessible")
admin3_b_only <- st_difference(st_intersection(st_union(inacc_b), focus_union), buffer_layer) %>% st_make_valid()
restricted <- list(a = st_union(buffer_layer, admin3_a_only) %>% st_make_valid(), b = st_union(buffer_layer, admin3_b_only) %>% st_make_valid())
admin3_only <- list(a = admin3_a_only, b = admin3_b_only)

# ---- 3. the design clusters (3,428) + Mobbar IDP (10 sites) and their hexes ----
W <- read.csv("_archive/2026-08-30_pre_intersos_resample_merge/NGA_MSNA_2026_stage2_sampling_frame_v2_WORKING.csv", colClasses = "character")
# interviews = the primary household rows actually drawn (A3's basis): a below-target Non-IDP cluster carries fewer
# primaries than its 6 x selection_count target_households
n_prim <- W %>% filter(status == "primary") %>% count(cluster_id, name = "n_primary")
cl <- W[!duplicated(W$cluster_id), ] %>%
  transmute(cluster_id, uuid_hex, pop_type, strata_id, adm1_pcode, adm2_pcode, adm2_name, region = reg_of(adm1_pcode),
            target_hh = as.numeric(target_households), sel = as.numeric(selection_count)) %>%
  left_join(n_prim, by = "cluster_id") %>% mutate(target = coalesce(n_primary, 0L))
mob <- read.csv("resampling/output/resample_runs/FHI360/2026-09-03_mobbar/new_clusters_idp_sitelevel.csv", colClasses = "character") %>%
  mutate(lat = as.numeric(latitude), lon = as.numeric(longitude), sel = as.numeric(selection_count), target = as.numeric(target_households))
mob_sf <- st_as_sf(mob, coords = c("lon", "lat"), crs = 4326) %>% st_transform(mycrs)
hex_access <- readRDS("input_data/boundaries/nga_hexagons/accessible_hex.rds")   # read only
hex_poly <- hex_access %>% group_by(uuid_hex, adm2_pcode) %>% summarise(.groups = "drop") %>% st_make_valid()
design_sc <- readRDS("_archive/2026-08-06_design_frame_post_nw_targeted_resample/selected_clusters_final.rds")
miss <- setdiff(unique(cl$uuid_hex), hex_poly$uuid_hex)
fill_in <- design_sc %>% filter(uuid_hex %in% miss, st_geometry_type(.) %in% c("POLYGON", "MULTIPOLYGON")) %>%
  group_by(uuid_hex, adm2_pcode) %>% summarise(.groups = "drop") %>% st_make_valid()
still <- setdiff(miss, fill_in$uuid_hex)
pt_fix <- design_sc %>% filter(uuid_hex %in% still) %>% st_join(hex_poly %>% select(uuid_hex_grid = uuid_hex), join = st_within)
say("\n## Design clusters: ", nrow(cl), " clusters on ", length(unique(cl$uuid_hex)), " physical hexes; Mobbar IDP: ", nrow(mob), " sites (selection_count sum ", sum(mob$sel), ", interviews ", sum(mob$target), ")")
say("hex geometry: ", sum(unique(cl$uuid_hex) %in% hex_poly$uuid_hex), " from accessible_hex.rds; ", length(miss), " missing there (Jibia/Mashi 6 Aug NW resample grid): ",
    nrow(fill_in), " taken as polygons from the 6 Aug design archive (selected_clusters_final.rds); ", length(still), " IDP-only hex(es) placed by their site point: ",
    paste(pt_fix$uuid_hex, "->", pt_fix$uuid_hex_grid, collapse = "; "))
norm <- function(x, id = x$uuid_hex) st_sf(uuid_hex = id, adm2_pcode = x$adm2_pcode, geometry = st_geometry(x))   # one schema for every source
pt_poly <- hex_poly[match(pt_fix$uuid_hex_grid, hex_poly$uuid_hex), ]
stopifnot(!anyNA(pt_fix$uuid_hex_grid))
hex_geom <- rbind(norm(hex_poly), norm(fill_in), norm(pt_poly, id = pt_fix$uuid_hex))
mob_hex <- st_join(mob_sf, hex_poly %>% select(uuid_hex_grid = uuid_hex), join = st_within)
say("Mobbar IDP sites inside an eligible hex: ", sum(!is.na(mob_hex$uuid_hex_grid)), " of ", nrow(mob_hex), " (", length(unique(na.omit(mob_hex$uuid_hex_grid))), " distinct hexes)")
if (anyNA(mob_hex$uuid_hex_grid)) {   # a site outside every eligible hex: take its hex from the full (unclipped) grid, read only
  grid_all <- readRDS(here::here(boundaries_dir, "nga_hexagons", "hexa_by_admin2.rds"))
  extra <- st_join(mob_hex[is.na(mob_hex$uuid_hex_grid), ] %>% select(site = uuid_site), grid_all %>% select(uuid_hex_full = uuid_hex, adm2_pcode), join = st_within)
  say("  ", nrow(extra), " Mobbar site(s) outside the eligible hexes, placed in the full grid's hex: ", paste(extra$site, "->", extra$uuid_hex_full, collapse = "; "))
  stopifnot(!anyNA(extra$uuid_hex_full))
  add <- grid_all[match(unique(extra$uuid_hex_full), grid_all$uuid_hex), ]
  hex_geom <- rbind(hex_geom, norm(add))
  mob_hex$uuid_hex_grid[is.na(mob_hex$uuid_hex_grid)] <- extra$uuid_hex_full[match(mob_hex$uuid_site[is.na(mob_hex$uuid_hex_grid)], extra$site)]
}
pg <- bind_rows(cl %>% distinct(uuid_hex, pop_type), tibble(uuid_hex = na.omit(mob_hex$uuid_hex_grid), pop_type = "idp")) %>%
  distinct() %>% group_by(uuid_hex) %>%
  summarise(has_ni = any(pop_type == "non_idp"), has_idp = any(pop_type == "idp"), .groups = "drop") %>%
  mutate(cls = case_when(has_ni & has_idp ~ "Both Non-IDP and IDP", has_ni ~ "Non-IDP only", TRUE ~ "IDP only"))
hexes_sel <- hex_geom %>% inner_join(pg, by = "uuid_hex") %>% mutate(region = reg_of(substr(adm2_pcode, 1, 5)))
stopifnot(!anyNA(hexes_sel$region), length(unique(hexes_sel$uuid_hex)) == nrow(pg))

# ---- 4. LGA classes on the design basis (30 Jul coverage list + design certainty exclusions), map2's precedence ----
cov <- read.csv("output/data/data_collection/NGA_MSNA_2026_coverage_summary_v2.csv", colClasses = "character")
st27 <- read.csv("_archive/2026-08-30_pre_intersos_resample_merge/NGA_MSNA_2026_strata_level_sampling_frame_v2_FULL.csv", colClasses = "character")
cert <- st27 %>% group_by(adm2_pcode) %>% summarise(cert_any = any(excluded_infeasible %in% c("TRUE", "True", "true")), .groups = "drop")
LGA_CLASS <- c("Sampled", "Excluded: certainty stratum (precision)", "Excluded: no partner coverage")
lga <- admin2 %>% left_join(cov %>% select(adm2_pcode, coverage_status), by = "adm2_pcode") %>% left_join(cert, by = "adm2_pcode") %>%
  mutate(cls = case_when(coverage_status == "covered" ~ LGA_CLASS[1],
                         coverage_status == "not_covered" ~ LGA_CLASS[3],   # 13 Oct: never assigned -> no partner coverage, whatever the flag
                         coalesce(cert_any, FALSE) ~ LGA_CLASS[2], TRUE ~ LGA_CLASS[3]),
         region = reg_of(adm1_pcode))
stopifnot(nrow(lga) == 323, !anyNA(lga$cls))
sampled_pcodes <- lga$adm2_pcode[lga$cls == "Sampled"]
hex_unsel <- hex_poly %>% filter(adm2_pcode %in% sampled_pcodes)

# ---- 5. verification ----
say("\n## V1. Buffer CRS: EPSG:", mycrs, " = ", sf::st_crs(mycrs)$Name, " (the design's own CRS; central meridian -15 deg, far west of Nigeria).")
say("Distances below: 'projected' = metres in EPSG:31028 (what the rule used); 'ground' = geodesic metres on the WGS 84 ellipsoid (s2).")
seg <- list(
  list(name = "Niger - NE (Borno/Yobe), rule 20 km", line = niger_line, d = 20000, clip = ne_union),
  list(name = "Niger - NC/NW, rule 5 km", line = niger_line, d = 5000, clip = ncnw_union),
  list(name = "Benin, rule 5 km", line = admin0_cast %>% filter(adm0_name == "Benin"), d = 5000, clip = focus_union),
  list(name = "Chad, rule 5 km", line = admin0_cast %>% filter(adm0_name == "Chad"), d = 5000, clip = focus_union),
  list(name = "Cameroon, rule 5 km", line = admin0_cast %>% filter(adm0_name == "Cameroon"), d = 5000, clip = focus_union))
spot <- list()
for (s in seg) {
  ln <- st_union(s$line)
  poly <- st_intersection(st_buffer(ln, s$d), s$clip) %>% st_make_valid() %>% st_collection_extract("POLYGON") %>% st_union()
  # vertices of the strip's boundary, densified to <= 250 m (st_line_sample(density=) under-fills one long ring)
  pts <- st_sf(geometry = st_cast(st_cast(st_segmentize(st_boundary(poly), 250), "MULTIPOINT"), "POINT"))
  pd <- as.numeric(st_distance(pts, ln))
  inner <- pts[abs(pd - s$d) < 5, ]   # the buffer's own offset edge (its arcs are chords, so a few metres short at most)
  if (nrow(inner) < 5) { say("  ", s$name, ": fewer than 5 inner-edge points found (", nrow(inner), ")"); next }
  xy <- st_coordinates(inner)
  ax <- if (diff(range(xy[, 1])) >= diff(range(xy[, 2]))) 1 else 2   # spread the 5 points along the border's main axis
  ord <- order(xy[, ax])
  pick <- inner[ord[round(quantile(seq_along(ord), c(0.1, 0.3, 0.5, 0.7, 0.9)))], ]
  g <- as.numeric(st_distance(st_transform(pick, 4326), st_transform(st_sf(geometry = ln), 4326)))
  p <- as.numeric(st_distance(pick, ln))
  ll <- st_coordinates(st_transform(pick, 4326))
  spot[[s$name]] <- tibble(segment = s$name, lon = round(ll[, 1], 3), lat = round(ll[, 2], 3), projected_m = round(p), ground_m = round(g), ground_over_rule = round(g / s$d, 3))
}
spot <- bind_rows(spot)
saytab(spot)

say("\n## V2. Area removed by the buffer (km2, equal-area EPSG:", EQA, "), within the 14 assessment states")
area_tab <- bind_rows(lapply(names(region_union), function(r) tibble(
  region = r,
  old_rule_pre_6Aug = km2(st_intersection(buffer_old, region_union[[r]])),
  new_rule_post_6Aug = km2(st_intersection(buffer_new, region_union[[r]])),
  new_rule_with_Mobbar_readmitted = km2(st_intersection(buffer_layer, region_union[[r]])))))
area_tab <- bind_rows(area_tab, tibble(region = "Total", old_rule_pre_6Aug = sum(area_tab$old_rule_pre_6Aug), new_rule_post_6Aug = sum(area_tab$new_rule_post_6Aug),
                                       new_rule_with_Mobbar_readmitted = sum(area_tab$new_rule_with_Mobbar_readmitted))) %>% mutate(across(-region, ~ round(.x, 1)))
saytab(area_tab)
say("Mobbar re-admission: Damasak + Zanna Umarti = ", round(km2(readmit), 1), " km2, of which inside the 20 km Niger buffer: ", round(km2(st_intersection(readmit, buffer_focus)), 1), " km2")

say("\n## V3. North-West LGAs touched by the old 20 km Niger buffer (the LGAs whose buffer changed on 6 Aug)")
nw_aff <- admin2 %>% filter(adm1_pcode %in% nga_admin1_pcodes_nw) %>% filter(lengths(st_intersects(., niger20)) > 0)
say("count: ", nrow(nw_aff), " (expect 24) | ", paste(sort(paste0(nw_aff$adm1_name, "/", nw_aff$adm2_name)), collapse = ", "))
ne_aff <- admin2 %>% filter(adm1_pcode %in% nga_admin1_pcodes_ne) %>% filter(lengths(st_intersects(., niger20)) > 0)
say("(NE LGAs within 20 km of Niger: ", nrow(ne_aff), "; NC: ", nrow(admin2 %>% filter(adm1_pcode %in% nga_admin1_pcodes_nc) %>% filter(lengths(st_intersects(., niger20)) > 0)), ")")

say("\n## V4. Admin-3 layers")
say("(a) design time - FACT NE file: ", nrow(fact), " rows, ", nrow(fact_no), " marked Not Existing/Inaccessible: ", paste(fact_no$uuid, collapse = "; "))
say("    name-matched to the COD admin-3 layer (as the pipeline did): ", nrow(admin3_a), " -> ", paste(admin3_a$uuid, admin3_a$adm3_pcode, collapse = "; "),
    " | unmatched (so NOT excluded at the design): ", paste(setdiff(fact_no$uuid, admin3$uuid), collapse = "; "))
say("    area outside the buffer: ", round(km2(admin3_a_only), 1), " km2")
say("(b) today - accessible_area_lga_ward_portions.shp (", format(file.info("resampling/output/gis/accessible_area_lga_ward_portions.shp")$mtime, "%Y-%m-%d %H:%M"), "): ",
    nrow(inacc_b), " Inaccessible portion rows (", length(unique(paste(inacc_b$adm2_pc, inacc_b$wardnam))), " distinct LGA-ward portions); area outside the buffer by region (km2): ",
    paste(sapply(names(region_union), function(r) paste0(r, " ", round(km2(st_intersection(admin3_b_only, region_union[[r]])), 1))), collapse = ", "))

say("\n## V5. Planned-cluster centroids inside an excluded area")
cent <- hexes_sel %>% mutate(geometry = st_centroid(geometry))
mob_pts <- mob_sf %>% mutate(region = "NE")
for (v in c("a", "b")) {
  inb <- lengths(st_intersects(cent, buffer_layer)) > 0
  ina <- lengths(st_intersects(cent, admin3_only[[v]])) > 0
  mb <- lengths(st_intersects(mob_pts, restricted[[v]])) > 0
  say("(", v, ") selected hexes: ", nrow(cent), " | centroid in the buffer: ", sum(inb), " | centroid in excluded Admin-3: ", sum(ina), " | Mobbar IDP site points in an excluded area: ", sum(mb))
  if (v == "b" && sum(ina) > 0) {
    flag <- cent[ina, ] %>% st_drop_geometry() %>% left_join(lga %>% st_drop_geometry() %>% select(adm2_pcode, adm1_name, adm2_name), by = "adm2_pcode")
    flag_w <- st_join(cent[ina, ] %>% select(uuid_hex), inacc_b %>% select(wardnam, rprtng_) %>% distinct(), join = st_intersects) %>% st_drop_geometry() %>% distinct(uuid_hex, .keep_all = TRUE)
    flag <- flag %>% left_join(flag_w, by = "uuid_hex") %>% arrange(region, adm1_name, adm2_name)
    saytab(flag %>% count(region, adm1_name, adm2_name, cls, name = "hexes"))
    write_csv(flag %>% select(region, adm1_name, adm2_name, ward = wardnam, reported_by = rprtng_, uuid_hex, population_group = cls), file.path(OUT, "variant_b_planned_hexes_in_partner_inaccessible_areas.csv"))
  }
}
flagged_b <- hexes_sel[lengths(st_intersects(cent, admin3_only$b)) > 0, ]

say("\n## V6. Cluster counts (design basis) by region and population group, against the A3 tables")
a3 <- tribble(~region, ~a3_clusters, ~a3_non_idp, ~a3_idp, ~a3_total,
              "NC", 392, 1839, 1602, 3441, "NE", 1326, 6562, 5598, 12160, "NW", 1710, 9598, 6360, 15958)
got <- cl %>% group_by(region) %>% summarise(clusters = n(), non_idp = sum(target[pop_type == "non_idp"]), idp = sum(target[pop_type == "idp"]), total = sum(target), .groups = "drop")
rec <- a3 %>% left_join(got, by = "region") %>% mutate(match = clusters == a3_clusters & non_idp == a3_non_idp & idp == a3_idp & total == a3_total)
rec <- bind_rows(rec, tibble(region = "Total", a3_clusters = 3428, a3_non_idp = 17999, a3_idp = 13560, a3_total = 31559,
                             clusters = sum(got$clusters), non_idp = sum(got$non_idp), idp = sum(got$idp), total = sum(got$total)) %>%
                   mutate(match = clusters == a3_clusters & non_idp == a3_non_idp & idp == a3_idp & total == a3_total))
saytab(rec)
say("Mobbar IDP: ", nrow(mob), " site clusters (rows), selection_count sum ", sum(mob$sel), ", ", sum(mob$target), " interviews. Mobbar-inclusive: ",
    sum(got$clusters) + nrow(mob), " cluster rows (A3 says 3,445 = 3,428 + 17, i.e. it counts Mobbar by selection_count, not rows) / ",
    sum(got$total) + sum(mob$target), " interviews (A3: 31,661) / IDP ", sum(got$idp) + sum(mob$target), " (A3: 13,662)")
hex_tab <- hexes_sel %>% st_drop_geometry() %>% count(region, cls, name = "hexes") %>% tidyr::pivot_wider(names_from = cls, values_from = hexes, values_fill = 0)
say("Map hexes by population group (design 2,970 hexes + the Mobbar IDP hexes):")
saytab(hex_tab)

say("\n## V7. Mobbar's re-admitted wards")
say("Damasak + Zanna Umarti found in GRID3: ", nrow(mobbar_wards), " | area inside the drawn buffer layer: ", round(km2(st_intersection(readmit, buffer_layer)), 3),
    " km2 (expect 0) | inside (a) Admin-3: ", round(km2(st_intersection(readmit, admin3_a_only)), 3), " km2 | inside (b) Admin-3: ", round(km2(st_intersection(readmit, admin3_b_only)), 3), " km2")
say("Mobbar hexes drawn as selected (IDP): ", sum(hexes_sel$uuid_hex %in% mob_hex$uuid_hex_grid), " | eligible not-selected hexes in the two wards: ",
    sum(lengths(st_intersects(hex_unsel %>% filter(!uuid_hex %in% hexes_sel$uuid_hex), readmit)) > 0))

# ---- 6. Figure 1 (map2 alt2 style) ----
state_region_lookup <- c(Benue = "North-Central", Kogi = "North-Central", Nasarawa = "North-Central", Niger = "North-Central", Plateau = "North-Central",
                         Adamawa = "North-East", Borno = "North-East", Yobe = "North-East", Kaduna = "North-West", Kano = "North-West",
                         Katsina = "North-West", Kebbi = "North-West", Sokoto = "North-West", Zamfara = "North-West")
admin1_focus <- admin1 %>% mutate(region_label = state_region_lookup[adm1_name])
stopifnot(!anyNA(admin1_focus$region_label))
region_focus <- admin1_focus %>% group_by(region_label) %>% summarise(.groups = "drop") %>% st_make_valid()
nigeria_boundary <- admin0_wa_proj %>% filter(adm0_pcode == "NG") %>% st_make_valid()
nga_all_states <- NGA_shapes_all$nga_admin1
context_margin_m <- 60000
context_bbox <- st_bbox(nga_all_states) + c(-context_margin_m, -context_margin_m, context_margin_m, context_margin_m)
context_extent <- st_as_sfc(context_bbox, crs = st_crs(nga_all_states))
neighbouring_countries <- admin0_wa_proj %>% filter(adm0_pcode != "NG") %>% st_make_valid() %>% st_intersection(context_extent)
neighbour_labels <- neighbouring_countries %>% group_by(adm0_name) %>% summarise(.groups = "drop") %>% st_point_on_surface() %>%
  filter(!adm0_name %in% c("Burkina Faso", "Mali", "Central African Republic"))
st_geometry(neighbour_labels)[neighbour_labels$adm0_name == "Cameroon"] <- st_geometry(neighbour_labels)[neighbour_labels$adm0_name == "Cameroon"] + c(60000, 30000)
st_geometry(neighbour_labels)[neighbour_labels$adm0_name == "Chad"] <- st_geometry(neighbour_labels)[neighbour_labels$adm0_name == "Chad"] + c(15000, 40000)
state_labels_focus <- admin1_focus %>% st_point_on_surface()
region_labels_focus <- region_focus %>% mutate(region_code = c("North-Central" = "NC", "North-East" = "NE", "North-West" = "NW")[region_label]) %>% st_point_on_surface()
# 13 Oct: a fixed spot in southern Niger State (6.4 E, 9.35 N), off the FCT (the 12 Oct offset put "NC" on top of it)
st_geometry(region_labels_focus)[region_labels_focus$region_code == "NC"] <- st_geometry(st_transform(st_sfc(st_point(c(6.4, 9.35)), crs = 4326), st_crs(region_labels_focus)))
boundary_colors <- c("Nigeria national boundary" = "#0A0A0A", "Regional boundary (NC / NE / NW)" = "#1B2A4A", "State boundary" = "grey55")
boundary_lw <- c("Nigeria national boundary" = 1.0, "Regional boundary (NC / NE / NW)" = 0.7, "State boundary" = 0.3)
base_layers <- function() list(geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25),
                               geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2))
boundary_layers <- function() list(geom_sf(data = admin1_focus, fill = NA, color = boundary_colors[[3]], linewidth = boundary_lw[[3]]),
                                   geom_sf(data = region_focus, fill = NA, color = boundary_colors[[2]], linewidth = boundary_lw[[2]]),
                                   geom_sf(data = nigeria_boundary, fill = NA, color = boundary_colors[[1]], linewidth = boundary_lw[[1]]))
label_layers <- function() list(
  geom_text_repel(data = neighbour_labels, aes(label = adm0_name, geometry = geometry), stat = "sf_coordinates", size = 4.0, color = "grey35",
                  fontface = "italic", bg.color = "white", bg.r = 0.12, seed = 1, max.overlaps = Inf, force = 0.4,
                  xlim = c(unname(context_bbox["xmin"]) + 5000, unname(context_bbox["xmax"]) - 5000),
                  ylim = c(unname(context_bbox["ymin"]) + 5000, unname(context_bbox["ymax"]) - 5000)),
  geom_text_repel(data = state_labels_focus, aes(label = adm1_name, geometry = geometry), stat = "sf_coordinates", size = 2.8, color = "#1B2A4A",
                  fontface = "bold", bg.color = "white", bg.r = 0.12, seed = 1),
  geom_text_repel(data = region_labels_focus, aes(label = region_code, geometry = geometry), stat = "sf_coordinates", size = 6.5, color = "#1B2A4A",
                  fontface = "bold", bg.color = "white", bg.r = 0.18, seed = 2, alpha = 0.85))

# map2's hand-built legend panel (absolute-cm rows), plus an "outline" swatch for variant (b)'s flagged hexes
# sizes a notch smaller than map2's (4 exclusion rows now, not 2), so the panel stays clear of the North-Central states
build_manual_legend_panel <- function(sections, swatch_cm = 0.4, title_size = 15, section_title_size = 10, item_size = 9, row_gap_cm = 0.12,
                                      section_gap_cm = 0.24, title_gap_cm = 0.2, swatch_label_gap_cm = 0.18, fig_width_in = 9, fig_height_in = 8.5,
                                      margin_cm = c(t = 0.4, r = 0.5, b = 0.35, l = 0.45)) {
  all_labels <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) s$title, sapply(s$rows, `[[`, "label"))))
  fs <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) section_title_size, rep(item_size, length(s$rows)))))
  bold <- unlist(lapply(sections, function(s) c(if (!is.null(s$title)) TRUE, rep(FALSE, length(s$rows)))))
  label_w <- mapply(function(t, f, b) as.numeric(convertWidth(grobWidth(textGrob(t, gp = gpar(fontsize = f, fontface = if (b) "bold" else "plain"))), "cm")), all_labels, fs, bold)
  title_w <- as.numeric(convertWidth(grobWidth(textGrob("Legend", gp = gpar(fontsize = title_size, fontface = "bold"))), "cm"))
  total_w <- max(title_w, swatch_cm + swatch_label_gap_cm + max(label_w)) + margin_cm[["l"]] + margin_cm[["r"]]
  row_h <- max(swatch_cm, 0.42)
  rows <- list(list(kind = "title", h = 0.6))
  for (s in sections) {
    rows[[length(rows) + 1]] <- list(kind = "gap", h = if (length(rows) == 1) title_gap_cm else section_gap_cm)
    if (!is.null(s$title)) { rows[[length(rows) + 1]] <- list(kind = "section_title", h = 0.48, label = s$title); rows[[length(rows) + 1]] <- list(kind = "gap", h = row_gap_cm * 0.6) }
    for (i in seq_along(s$rows)) {
      rows[[length(rows) + 1]] <- list(kind = "item", h = row_h, row = s$rows[[i]])
      if (i < length(s$rows)) rows[[length(rows) + 1]] <- list(kind = "gap", h = row_gap_cm)
    }
  }
  total_h <- sum(sapply(rows, `[[`, "h")) + margin_cm[["t"]] + margin_cm[["b"]]
  swatch <- function(row, x, y) {
    vp <- viewport(x = unit(x, "cm"), y = unit(y, "cm"), width = unit(swatch_cm, "cm"), height = unit(swatch_cm, "cm"), just = c("left", "center"))
    if (row$type == "fill") grobTree(rectGrob(gp = gpar(fill = row$color, col = "grey30", lwd = 0.6)), vp = vp)
    else if (row$type == "outline") grobTree(rectGrob(gp = gpar(fill = row$fill, col = row$color, lwd = 2.4)), vp = vp)
    else grobTree(linesGrob(x = unit(c(0, 1), "npc"), y = unit(0.5, "npc"), gp = gpar(col = row$color, lwd = max(row$linewidth * 2.2, 1.8))), vp = vp)
  }
  lab <- function(t, x, y, size, b = FALSE) textGrob(t, x = unit(x, "cm"), y = unit(y, "cm"), just = c("left", "center"),
                                                    gp = gpar(fontsize = size, fontface = if (b) "bold" else "plain", col = if (b) "grey15" else "black"))
  g <- gList(); y <- total_h - margin_cm[["t"]]
  for (r in rows) {
    if (r$kind == "gap") { y <- y - r$h; next }
    cy <- y - r$h / 2
    if (r$kind == "title") g <- gList(g, lab("Legend", margin_cm[["l"]], cy, title_size, TRUE))
    else if (r$kind == "section_title") g <- gList(g, lab(r$label, margin_cm[["l"]], cy, section_title_size, TRUE))
    else g <- gList(g, swatch(r$row, margin_cm[["l"]], cy), lab(r$row$label, margin_cm[["l"]] + swatch_cm + swatch_label_gap_cm, cy, item_size))
    y <- y - r$h
  }
  list(grob = grobTree(rectGrob(gp = gpar(fill = "white", col = "grey60", lwd = 1)), gTree(children = g, vp = viewport(width = unit(total_w, "cm"), height = unit(total_h, "cm")))),
       width_npc = (total_w / 2.54) / fig_width_in, height_npc = (total_h / 2.54) / fig_height_in)
}

POP_COL <- c("Non-IDP only" = "#1B6FA8", "IDP only" = "#E08214", "Both Non-IDP and IDP" = "#6A3D9A")
EXCL_COL <- c(buffer = "#8B4A4A", admin3 = "#C9787D", cert = "#E2C9A0", nocov = "grey75")
ADMIN3_LABEL <- c(a = "Excluded: inaccessible Admin-3 (FACT, at design)", b = "Excluded: inaccessible Admin-3 (partners, 12 Oct)")
FLAG_LABEL <- "Planned cluster now in an inaccessible area"
counts <- list()
render_fig1 <- function(v) {
  lga_ex <- lga %>% filter(cls != "Sampled") %>% mutate(fill_hex = ifelse(cls == LGA_CLASS[2], EXCL_COL[["cert"]], EXCL_COL[["nocov"]]))
  hx <- hexes_sel %>% mutate(fill_hex = unname(POP_COL[cls]))
  drawn <- list(`Non-IDP only` = sum(hx$cls == "Non-IDP only"), `IDP only` = sum(hx$cls == "IDP only"), `Both Non-IDP and IDP` = sum(hx$cls == "Both Non-IDP and IDP"),
                `Not selected (eligible hex)` = length(unique(setdiff(hex_unsel$uuid_hex, hx$uuid_hex))),
                `Excluded: border buffer` = round(km2(buffer_layer)), adm = round(km2(admin3_only[[v]])),
                `Excluded: certainty stratum (precision)` = sum(lga_ex$cls == LGA_CLASS[2]), `Excluded: no partner coverage` = sum(lga_ex$cls == LGA_CLASS[3]))
  names(drawn)[names(drawn) == "adm"] <- ADMIN3_LABEL[[v]]
  drop_cls <- character(0)
  if (drawn[["Excluded: certainty stratum (precision)"]] == 0) {   # 13 Oct: no LGA left in this class -> not in the legend
    drop_cls <- "Excluded: certainty stratum (precision)"
    drawn[[drop_cls]] <- NULL
  }
  if (v == "b") drawn[[FLAG_LABEL]] <- nrow(flagged_b)
  rows_pop <- lapply(names(POP_COL), function(k) list(label = k, type = "fill", color = unname(POP_COL[[k]])))
  sec <- list(list(title = "Population group targeted", rows = rows_pop),
              list(title = NULL, rows = c(list(list(label = "Not selected (eligible hex)", type = "fill", color = "white")),
                                           if (v == "b") list(list(label = FLAG_LABEL, type = "outline", color = "black", fill = "white")))),
              list(title = NULL, rows = list(list(label = "Excluded: border buffer", type = "fill", color = EXCL_COL[["buffer"]]),
                                             list(label = ADMIN3_LABEL[[v]], type = "fill", color = EXCL_COL[["admin3"]]),
                                             list(label = "Excluded: certainty stratum (precision)", type = "fill", color = EXCL_COL[["cert"]]),
                                             list(label = "Excluded: no partner coverage", type = "fill", color = EXCL_COL[["nocov"]]))),
              list(title = NULL, rows = lapply(names(boundary_colors), function(k) list(label = k, type = "line", color = boundary_colors[[k]], linewidth = boundary_lw[[k]]))))
  sec[[3]]$rows <- Filter(function(r) !r$label %in% drop_cls, sec[[3]]$rows)
  legend_labels <- unlist(lapply(sec[1:3], function(s) sapply(s$rows, `[[`, "label")))
  stopifnot(setequal(legend_labels, names(drawn)))
  say("Figure 1 (", v, ") legend class -> drawn features: ", paste(names(drawn), unlist(drawn), sep = " = ", collapse = " | "))
  if (any(unlist(drawn) == 0)) say("  WARNING: a legend class has nothing drawn: ", paste(names(drawn)[unlist(drawn) == 0], collapse = ", "))
  p <- ggplot() + base_layers() +
    geom_sf(data = hex_unsel, fill = NA, color = "grey70", linewidth = 0.06) +
    geom_sf(data = lga_ex, aes(fill = fill_hex), color = "white", linewidth = 0.1) +
    geom_sf(data = st_sf(geometry = st_sfc(buffer_layer)), fill = EXCL_COL[["buffer"]], color = NA) +
    geom_sf(data = st_sf(geometry = st_sfc(admin3_only[[v]])), fill = EXCL_COL[["admin3"]], color = NA) +
    geom_sf(data = hx, aes(fill = fill_hex), color = "grey20", linewidth = 0.08) +
    (if (v == "b") geom_sf(data = flagged_b, fill = NA, color = "black", linewidth = 0.45) else NULL) +
    scale_fill_identity() + boundary_layers() + label_layers() +
    coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
    theme_void(base_size = 12) + theme(legend.position = "none")
  leg <- build_manual_legend_panel(sec)
  p_final <- ggdraw(p) + draw_grob(leg$grob, x = 0.015, y = 0.02, width = leg$width_npc, height = leg$height_npc)
  f <- file.path(OUT, sprintf("tor_figure1_design_map_%s.png", c(a = "a_design_time_exclusions", b = "b_partner_admin3_12oct")[[v]]))
  ggsave(f, p_final, width = 9, height = 8.5, dpi = 130, bg = "white")
  say("saved ", f)
  counts[[paste0("fig1_", v)]] <<- tibble(map = "Figure 1", variant = v, legend_class = names(drawn), drawn = unlist(drawn),
                                          unit = ifelse(grepl("^Excluded: (border|inaccessible)", names(drawn)), "km2",
                                                        ifelse(grepl("^Excluded", names(drawn)), "LGAs", "hexes")))
}
say("\n## V8. Legends vs what is drawn")
render_fig1("a")
render_fig1("b")

# ---- 7. Annex A1.1 frame map (08 overview style), exclusions split ----
worldpop_focus0 <- terra::mask(terra::crop(worldpop_pop, terra::vect(admin1)), terra::vect(admin1))
render_annex <- function(v) {
  acc <- st_difference(focus_union, restricted[[v]]) %>% st_make_valid()
  wp <- terra::mask(worldpop_focus0, terra::vect(st_sf(geometry = st_sfc(acc))))
  idp <- iom_idp_df %>% filter(!is.na(individuals), individuals > 0) %>% st_transform(mycrs) %>% st_filter(st_sf(geometry = st_sfc(acc)), .predicate = st_within)
  lab_buf <- "Excluded: border buffer"
  lab_adm <- ADMIN3_LABEL[[v]]
  ex <- rbind(st_sf(cls = lab_buf, geometry = st_sfc(buffer_layer)), st_sf(cls = lab_adm, geometry = st_sfc(admin3_only[[v]])))
  ex_fill <- setNames(c("grey25", "#7A5C8C"), c(lab_buf, lab_adm))
  nl <- neighbouring_countries %>% group_by(adm0_name) %>% summarise(.groups = "drop") %>% st_point_on_surface()
  st_geometry(nl)[nl$adm0_name == "Cameroon"] <- st_geometry(nl)[nl$adm0_name == "Cameroon"] + c(-20000, 150000)
  st_geometry(nl)[nl$adm0_name == "Central African Republic"] <- st_geometry(nl)[nl$adm0_name == "Central African Republic"] + c(-180000, 70000)
  pop_scale <- scale_fill_gradientn(colors = c("#FFFFFF00", "#FFF2AE", "#FDB863", "#E08214", "#B2182B"), na.value = "transparent", trans = "log1p",
                                    breaks = c(0, 50, 300), name = "Non-IDP population\nper grid cell")
  ex_layer <- function() list(geom_sf(data = ex, aes(color = cls), fill = unname(ex_fill[ex$cls]), alpha = 0.65, linewidth = 0.3),
                              scale_color_manual(name = NULL, values = ex_fill, breaks = c(lab_buf, lab_adm),
                                                 guide = guide_legend(override.aes = list(fill = unname(ex_fill[c(lab_buf, lab_adm)]), alpha = 0.65, linewidth = 0), order = 2)))
  st_layer <- function() list(geom_sf(data = admin1, aes(linetype = "Assessment states (14)"), fill = NA, color = "#1B2A4A", linewidth = 0.7),
                              scale_linetype_manual(name = NULL, values = c("Assessment states (14)" = "solid"),
                                                    guide = guide_legend(override.aes = list(color = "#1B2A4A", linewidth = 0.7), order = 1)))
  p <- ggplot() +
    geom_sf(data = neighbouring_countries, fill = "grey88", color = "grey65", linewidth = 0.25) +
    geom_sf(data = nga_all_states, fill = "grey95", color = "grey60", linewidth = 0.2) +
    tidyterra::geom_spatraster(data = wp, maxcell = 3e6) + pop_scale + ex_layer() + st_layer() +
    geom_sf(data = idp, aes(size = individuals), color = "#1B6FA8", alpha = 0.8, shape = 16) +
    scale_size_continuous(range = c(0.4, 5), name = "IDP site\npopulation") +
    geom_text_repel(data = state_labels_focus, aes(label = adm1_name, geometry = geometry), stat = "sf_coordinates", size = 2.8, color = "#1B2A4A",
                    fontface = "bold", bg.color = "white", bg.r = 0.12, seed = 1) +
    geom_text_repel(data = nl, aes(label = adm0_name, geometry = geometry), stat = "sf_coordinates", size = 4.0, color = "grey35", fontface = "italic",
                    bg.color = "white", bg.r = 0.12, seed = 1, xlim = c(unname(context_bbox["xmin"]) + 20000, unname(context_bbox["xmax"]) - 140000)) +
    coord_sf(xlim = c(context_bbox["xmin"], context_bbox["xmax"]), ylim = c(context_bbox["ymin"], context_bbox["ymax"]), expand = FALSE) +
    theme_void(base_size = 12) + theme(legend.position = "none")
  leg <- suppressWarnings(cowplot::get_legend(
    ggplot() + st_layer() + ex_layer() + tidyterra::geom_spatraster(data = wp, maxcell = 3e5) + pop_scale +
      geom_sf(data = idp, aes(size = individuals), color = "#1B6FA8", alpha = 0.8, shape = 16) + scale_size_continuous(range = c(0.4, 5), name = "IDP site\npopulation") +
      guides(fill = guide_colorbar(direction = "vertical", barwidth = unit(0.3, "cm"), barheight = unit(2.2, "cm"), order = 3), size = guide_legend(order = 4)) +
      theme_void(base_size = 12) + theme(legend.position = "right", legend.box = "vertical", legend.title = element_text(size = 8, face = "bold"),
                                         legend.text = element_text(size = 7), legend.key.size = unit(0.38, "cm"), legend.spacing.y = unit(0.12, "cm"),
                                         legend.background = element_blank())))
  panel <- plot_grid(ggdraw() + draw_label("Legend", fontface = "bold", size = 12, colour = "grey15", x = 0.04, hjust = 0), leg, ncol = 1, rel_heights = c(0.09, 0.91)) +
    theme(plot.background = element_rect(fill = "white", color = "grey60", linewidth = 0.5), plot.margin = margin(4, 6, 4, 6))
  p_final <- ggdraw(p) + draw_plot(panel, x = 0.62, y = 0.01, width = 0.36, height = 0.38)
  f <- file.path(OUT, sprintf("tor_annex_a1_1_frame_map_%s.png", c(a = "a_design_time_exclusions", b = "b_partner_admin3_12oct")[[v]]))
  ggsave(f, p_final, width = 9, height = 8.5, dpi = 130, bg = "white")
  say("saved ", f, " | IDP sites drawn: ", nrow(idp), " (", round(sum(idp$individuals)), " individuals) | excluded area: buffer ", round(km2(buffer_layer)), " km2, Admin-3 ", round(km2(admin3_only[[v]])), " km2")
  counts[[paste0("annex_", v)]] <<- tibble(map = "Annex A1.1", variant = v, legend_class = c(lab_buf, lab_adm, "IDP sites (accessible area)", "IDP site individuals"),
                                           drawn = c(round(km2(buffer_layer)), round(km2(admin3_only[[v]])), nrow(idp), round(sum(idp$individuals))),
                                           unit = c("km2", "km2", "sites", "individuals"))
}
render_annex("a")
render_annex("b")

# ---- 8. counts per legend class, by region where it applies ----
reg_rows <- bind_rows(lapply(c("a", "b"), function(v) bind_rows(
  hexes_sel %>% st_drop_geometry() %>% count(region, legend_class = cls, name = "drawn") %>% mutate(unit = "hexes"),
  lga %>% st_drop_geometry() %>% filter(cls != "Sampled") %>% count(region, legend_class = cls, name = "drawn") %>% mutate(unit = "LGAs"),
  bind_rows(lapply(names(region_union), function(r) tibble(region = r, legend_class = c("Excluded: border buffer", ADMIN3_LABEL[[v]]),
                                                             drawn = round(c(km2(st_intersection(buffer_layer, region_union[[r]])), km2(st_intersection(admin3_only[[v]], region_union[[r]]))), 1),
                                                             unit = "km2")))) %>%
    mutate(map = "Figure 1", variant = v)))
write_csv(bind_rows(bind_rows(counts) %>% mutate(region = "All"), reg_rows) %>% select(map, variant, region, legend_class, drawn, unit) %>% arrange(map, variant, legend_class, region),
          file.path(OUT, "counts_by_legend_class.csv"))
write_csv(rec, file.path(OUT, "design_cluster_counts_vs_A3.csv"))
write_csv(spot, file.path(OUT, "buffer_spot_checks.csv"))
write_csv(area_tab, file.path(OUT, "buffer_area_by_region.csv"))
say("\n==== done ", format(Sys.time(), "%H:%M:%S"), " ====")
close(LOG)
