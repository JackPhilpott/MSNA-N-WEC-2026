# ==============================================================================
# 2026-09-27 ONE-OFF (Coordinator-approved 2026-09-27, option (b)): the same accessible_status refresh as the standing
# resampling/scripts/refresh_idp_site_frame_accessibility.R, but ONE ROW PER SITE.
#
# Why a variant and not an edit of the standing script: the standing script's st_join(join = st_within) returns a site TWICE when it
# lies in two overlapping ward polygons (the layer holds one row per LGA-ward portion, and some ward polygons overlap). On 2026-09-26
# that turned 2,981 rows into 3,021 (40 sites, all Tangaza, Sokoto; every duplicate pair carried the SAME status). The standing script
# is deliberately left unchanged tonight; this file records the latent behaviour so it can be fixed later.
#
# What this does differently: after the join, collapse to one row per original row (rule: Inaccessible if ANY match is Inaccessible,
# else Accessible if any match is Accessible, else NA - a conservative rule that never fires when duplicates agree, and the run reports
# whether any pair disagreed). Everything else (st_within, nearest-ward fallback within 5 km, NA left NA) is copied from the standing script.
# Then verifies before writing: same row count and order, every column except accessible_status identical, geometry identical, column
# order restored. Writes nothing unless every check passes.
#
# Usage: Rscript refresh_idp_site_frame_accessibility_dedup_2026-09-27.R [out_rds]
#   out_rds omitted -> overwrites input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds (BACK IT UP FIRST)
#   out_rds given   -> writes there instead (dry run on scratch)
# Also writes idp_site_status_changes_by_lga.csv next to the script's result folder when RESULT_DIR env var is set.
# ==============================================================================
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(sf) })
sf::sf_use_s2(FALSE)
mycrs <- 31028
GAP_FALLBACK_MAX_DIST_M <- 5000

args <- commandArgs(trailingOnly = TRUE)
RDS_PATH <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds"
OUT_PATH <- if (length(args) >= 1) args[1] else RDS_PATH
WARD_LAYER_SHP <- "resampling/output/gis/accessible_area_lga_ward_portions.shp"
RESULT_DIR <- Sys.getenv("RESULT_DIR", "")

orig <- readRDS(RDS_PATH)
stopifnot(inherits(orig, "sf"), isTRUE(st_crs(orig)$epsg == mycrs))
n0 <- nrow(orig)
site_frame <- orig
site_frame$.rid <- seq_len(n0)
site_frame <- site_frame %>% select(-any_of("accessible_status"))

ward_layer_raw <- st_read(WARD_LAYER_SHP, quiet = TRUE) %>% st_transform(mycrs) %>%
  rename(adm2_pcode = adm2_pc, accessible_status = accssb_, pop_type = pop_typ)
ward_layer_idp <- ward_layer_raw %>% filter(pop_type == "IDP")

joined <- st_join(site_frame, ward_layer_idp["accessible_status"], join = st_within)
cat("rows after join:", nrow(joined), "(frame had", n0, ")\n")

# collapse to one row per site
per_site <- joined %>% st_drop_geometry() %>% group_by(.rid) %>%
  summarise(n_match = n(),
            n_distinct_status = n_distinct(accessible_status, na.rm = TRUE),
            status = if (any(accessible_status == "Inaccessible", na.rm = TRUE)) "Inaccessible"
                     else if (any(accessible_status == "Accessible", na.rm = TRUE)) "Accessible"
                     else NA_character_,
            .groups = "drop")
cat(sprintf("sites matched by >1 ward polygon: %d | of which the matches DISAGREE on status: %d\n",
            sum(per_site$n_match > 1), sum(per_site$n_distinct_status > 1)))
joined <- joined[!duplicated(joined$.rid), ]
joined <- joined[order(joined$.rid), ]
joined$accessible_status <- per_site$status[match(joined$.rid, per_site$.rid)]
stopifnot(nrow(joined) == n0, identical(joined$.rid, seq_len(n0)))

na_idx <- which(is.na(joined$accessible_status))
if (length(na_idx) > 0) {
  nearest_idx <- st_nearest_feature(joined[na_idx, ], ward_layer_idp)
  dists <- as.numeric(st_distance(joined[na_idx, ], ward_layer_idp[nearest_idx, ], by_element = TRUE))
  within_cap <- dists <= GAP_FALLBACK_MAX_DIST_M
  joined$accessible_status[na_idx[within_cap]] <- ward_layer_idp$accessible_status[nearest_idx[within_cap]]
  cat(sprintf("%d site(s) outside any ward polygon - %d resolved via nearest ward (max %.0fm away), %d beyond %dm left NA (excluded pending review, NOT defaulted to Accessible).\n",
              length(na_idx), sum(within_cap), if (any(within_cap)) max(dists[within_cap]) else 0,
              sum(!within_cap), GAP_FALLBACK_MAX_DIST_M))
}

final <- joined %>% select(-.rid)
final <- final[, names(orig)]   # restore the original column order (sf keeps geometry)

# ---- verification: everything except accessible_status must be identical to the frame we read
o_df <- st_drop_geometry(orig); f_df <- st_drop_geometry(final)
other_cols <- setdiff(names(o_df), "accessible_status")
col_ok <- vapply(other_cols, function(cn) identical(o_df[[cn]], f_df[[cn]]), logical(1))
geom_ok <- isTRUE(all.equal(st_coordinates(orig), st_coordinates(final)))
chk <- c(rows_equal = nrow(final) == n0, columns_equal = identical(names(final), names(orig)),
         non_status_columns_identical = all(col_ok), geometry_identical = geom_ok, crs_same = identical(st_crs(final), st_crs(orig)),
         site_ids_identical = identical(orig$uuid_site_pop, final$uuid_site_pop))
print(chk)
if (!all(chk)) { print(names(col_ok)[!col_ok]); stop("STOP: verification failed; nothing written") }

before <- table(orig$accessible_status, useNA = "always"); after <- table(final$accessible_status, useNA = "always")
cat("Before:\n"); print(before); cat("After:\n"); print(after)
chg <- tibble::tibble(adm1_name = orig$adm1_name, adm2_name = orig$adm2_name, old = orig$accessible_status, new = final$accessible_status) %>%
  filter(!(is.na(old) & is.na(new)), is.na(old) != is.na(new) | (!is.na(old) & old != new)) %>%
  count(adm1_name, adm2_name, old, new, name = "n_sites") %>% arrange(desc(n_sites))
cat("status changes by LGA:\n"); print(as.data.frame(chg), row.names = FALSE)
if (nzchar(RESULT_DIR)) write.csv(chg, file.path(RESULT_DIR, "idp_site_status_changes_by_lga.csv"), row.names = FALSE)

saveRDS(final, OUT_PATH)
cat("written ->", OUT_PATH, "\n")
