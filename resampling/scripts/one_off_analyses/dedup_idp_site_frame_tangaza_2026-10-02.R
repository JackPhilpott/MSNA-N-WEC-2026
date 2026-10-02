# ==============================================================================
# 2026-10-02 ONE-OFF (Coordinator instruction under Jack's 3-hour approval
# window, ~01:30-04:30 2 Oct): remove the compounding duplicate rows from
# idp_site_level_psu_frame_2026-09-02.rds.
#
# What happened: accessible_area_lga_ward_portions.shp carries exact-duplicate
# IDP polygons for Tangaza (NG034019). The standing
# refresh_idp_site_frame_accessibility.R did st_join(st_within) with no
# collapse, saved over its own input, and re-read it next run, so every run
# doubled the 10 Tangaza sites (64 copies after 6 runs; 3,581 rows for 2,951
# sites). Already seen on 26-27 Sep (refresh_idp_site_frame_accessibility_
# dedup_2026-09-27.R), but the standing script was left unpatched.
#
# This script: keeps the first row per uuid_site and writes ONLY if every
# check passes (each dropped row byte-identical to its kept row, incl.
# geometry; Tangaza ends at 10 sites; every other LGA's row count and pop_hh
# total unchanged; 2,951 rows = 2,951 distinct sites; same site set as the
# clean 21 Sep backup). The caller backs the file up first.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf) })
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
RDS_PATH <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02.rds"
CLEAN_0921 <- "input_data/population/sampling_frame/idp_site_level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-21.rds.bak"

orig <- readRDS(RDS_PATH)
stopifnot(inherits(orig, "sf"))
o_df <- st_drop_geometry(orig)
coords <- st_coordinates(orig)
cat("before: rows", nrow(orig), "| distinct uuid_site", n_distinct(orig$uuid_site), "\n")

keep <- !duplicated(orig$uuid_site)
first_idx <- match(orig$uuid_site, orig$uuid_site)          # row index of the kept copy for every row
dropped <- which(!keep)
# Compare value by value, per column (row names / tibble attributes are not data and must not enter the test).
cols <- names(o_df)
diff_cols <- character(0)
row_same <- vapply(dropped, function(i) {
  j <- first_idx[i]
  same <- vapply(cols, function(cn) identical(o_df[[cn]][i], o_df[[cn]][j]), logical(1))
  if (!all(same)) diff_cols <<- union(diff_cols, cols[!same])
  all(same) && identical(unname(coords[i, ]), unname(coords[j, ]))
}, logical(1))
cat("dropped rows:", length(dropped), "| byte-identical to kept copy:", sum(row_same),
    "| columns that ever differ:", if (length(diff_cols)) paste(diff_cols, collapse = ",") else "none", "\n")

deduped <- orig[keep, ]
d_df <- st_drop_geometry(deduped)

per_lga <- function(df) df %>% group_by(adm2_pcode) %>% summarise(rows = n(), pop_hh = sum(pop_hh, na.rm = TRUE), .groups = "drop")
b <- per_lga(o_df); a <- per_lga(d_df)
cmp <- full_join(b, a, by = "adm2_pcode", suffix = c("_before", "_after"))
others <- cmp %>% filter(adm2_pcode != "NG034019")
clean <- readRDS(CLEAN_0921)

chk <- c(
  dropped_rows_byte_identical = length(dropped) > 0 && all(row_same),
  n_dropped_is_630 = length(dropped) == 630,
  rows_now_2951 = nrow(deduped) == 2951,
  one_row_per_site = n_distinct(deduped$uuid_site) == nrow(deduped),
  tangaza_10_sites = sum(deduped$adm2_pcode == "NG034019") == 10,
  other_lgas_rows_unchanged = all(others$rows_before == others$rows_after),
  other_lgas_pop_hh_unchanged = all(others$pop_hh_before == others$pop_hh_after),
  same_site_set_as_clean_0921 = setequal(deduped$uuid_site, clean$uuid_site),
  columns_and_crs_kept = identical(names(deduped), names(orig)) && identical(st_crs(deduped), st_crs(orig))
)
print(chk)
cat("Tangaza after:", sum(deduped$adm2_pcode == "NG034019"), "sites, pop_hh",
    sum(deduped$pop_hh[deduped$adm2_pcode == "NG034019"]), "\n")
if (!all(chk)) stop("STOP: a check failed; nothing written")
saveRDS(deduped, RDS_PATH)
cat("written ->", RDS_PATH, "| rows", nrow(deduped), "\n")
