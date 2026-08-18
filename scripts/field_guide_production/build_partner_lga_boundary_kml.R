# ==============================================================================
# LGA boundary KML - one file per partner, written at the partner's ROOT
# folder (not nested per-LGA like the point KMLs), covering every LGA that
# partner is assigned. Added 2026-08-17 per user request, after a field
# example session (Save the Children) revealed field teams have no easy way
# to visually cross-check a sample point's GPS location against its LGA
# boundary in Maps.me itself - this closes that gap directly, without
# needing a separate GIS tool.
#
# Styled as an outline only (no fill) so it never visually hides the
# points/hexagons already on the map - LineStyle uses the same navy
# (#1F3864) already used throughout this project's maps/diagrams for
# "official design boundary" elements, at a width visible on a phone
# screen. Reuses the exact same LGA-name matching/reconciliation logic as
# build_partner_dc_packages.py (duplicated rather than imported, per this
# project's standalone-script convention).
# ==============================================================================

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
})

lines <- readLines("scripts/01_sampling_pipeline_main.R")
stop_idx <- which(grepl("^hex_access <- cache_rds\\(", lines))
end_idx <- stop_idx - 1 + which(grepl("^\\)$", lines[stop_idx:length(lines)]))[1]
writeLines(lines[1:end_idx], "temp_boundaries_lga_kml.R")
source("temp_boundaries_lga_kml.R")
file.remove("temp_boundaries_lga_kml.R")

OUT_ROOT <- "C:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/3. External coordination/NGA MSNA 2026 Package"
STRATA_CSV <- here::here("_archive", "2026-08-06_design_frame_post_nw_targeted_resample", "strata_level_sampling_frame.csv")
COVERAGE_XLSX <- here::here("input_data", "boundaries", "partner_coverage", "Partnerscoverage.xlsx")

IN_SCOPE_STATES <- c(
  "Adamawa", "Borno", "Yobe",
  "Kaduna", "Kano", "Katsina", "Kebbi", "Sokoto", "Zamfara",
  "Benue", "Kogi", "Nasarawa", "Niger", "Plateau"
)

norm <- function(s) {
  s <- ifelse(is.na(s), "", tolower(trimws(s)))
  s <- gsub("[/-]", " ", s)
  s <- gsub("['\u2018\u2019\u02bc\ufffd]", "", s)
  trimws(gsub("\\s+", " ", s))
}

safe_folder_name <- function(s) gsub('[<>:"/\\\\|?*]', "-", s)

# Same reconciliation dict as build_partner_dc_packages.py/analysis_partner_coverage.py.
PROPOSED_RECONCILIATION <- list(
  "zamfara|birnin magaji kiyaw" = "NG037003", "zamfara|kauran namoda" = "NG037008",
  "kaduna|makarfi" = "NG019018", "kaduna|zangon kataf" = "NG019022",
  "kebbi|wasagu" = "NG022019", "benue|otukpo" = "NG007019",
  "kogi|olamaboro" = "NG023018", "nasarawa|eggon" = "NG026010",
  "niger|munya" = "NG027018", "plateau|barkin ladi" = "NG032001"
)
COMBINED_PARTNER_SPLITS <- list("IRC/LHI" = c("IRC", "LHI"))

# ---------------------------------------------------------------------------
# 1. Master LGA list + partner coverage (same source/logic as the KML/
#    factsheet distribution scripts)
# ---------------------------------------------------------------------------
strata_rows <- read_csv(STRATA_CSV, show_col_types = FALSE)
master_lgas <- strata_rows %>% distinct(adm2_pcode, adm2_name, adm1_name)
lga_index <- setNames(master_lgas$adm2_pcode, paste(norm(master_lgas$adm1_name), norm(master_lgas$adm2_name)))

partners_by_pcode <- new.env()
add_partner <- function(pcode, partner) {
  cur <- get0(pcode, envir = partners_by_pcode, ifnotfound = character(0))
  assign(pcode, union(cur, partner), envir = partners_by_pcode)
}

sheets <- readxl::excel_sheets(COVERAGE_XLSX)
for (sh in sheets) {
  df <- readxl::read_excel(COVERAGE_XLSX, sheet = sh, col_names = TRUE)
  header <- names(df)
  count_idx <- which(header == "COUNT")
  partner_cols <- header[4:(count_idx - 1)]
  for (i in seq_len(nrow(df))) {
    r <- df[i, ]
    if (is.na(r[[3]])) next
    state <- as.character(r[[2]]); lga <- as.character(r[[3]])
    if (!(state %in% IN_SCOPE_STATES)) next
    partners_here <- partner_cols[!is.na(unlist(r[1, partner_cols])) & unlist(r[1, partner_cols]) != FALSE]
    if (length(partners_here) == 0) next
    key <- paste(norm(state), norm(lga))
    pcode <- unname(lga_index[key])
    if (is.na(pcode)) pcode <- PROPOSED_RECONCILIATION[[paste0(norm(state), "|", norm(lga))]]
    if (is.null(pcode) || is.na(pcode)) next
    for (p in partners_here) {
      expanded <- COMBINED_PARTNER_SPLITS[[p]]
      if (is.null(expanded)) expanded <- p
      for (e in expanded) add_partner(pcode, e)
    }
  }
}

pcodes_covered <- ls(partners_by_pcode)
cat("Partner coverage resolved for", length(pcodes_covered), "LGAs.\n")

# ---------------------------------------------------------------------------
# 2. LGA polygons (OCHA/COD, authoritative - same source as every other
#    LGA-boundary layer in this project).
# ---------------------------------------------------------------------------
# NGA_shapes_all_cleaned$nga_admin2 already carries its own adm2_name/
# adm1_name columns - joining master_lgas (which also has those names) on
# top produced silently-suffixed adm2_name.x/.y duplicates instead of the
# plain names the KML writer expects, so row$adm2_name resolved to NULL
# for every row (caught 2026-08-17: every partner's KML came out with zero
# placemarks - polygon_to_kml() itself worked fine, but esc(row$adm2_name)
# on NULL silently collapsed the whole Placemark sprintf() to character(0)).
# Fixed by using the shapefile's own name columns directly - no join needed.
admin2_all <- NGA_shapes_all_cleaned$nga_admin2 %>% st_transform(4326) %>% st_make_valid() %>%
  filter(adm2_pcode %in% pcodes_covered)
stopifnot(all(c("adm2_name", "adm1_name") %in% names(admin2_all)))

# ---------------------------------------------------------------------------
# 3. KML writer - polygon outline only (no fill), so it never hides sample
#    points underneath. Navy (#1F3864 -> KML aabbggrr = ff64381f), 3px line.
#    Handles MULTIPOLYGON (multiple parts) and holes (inner rings) generically.
# ---------------------------------------------------------------------------
ring_to_kml_coords <- function(ring_mat) {
  paste(apply(ring_mat, 1, function(r) paste(r[1], r[2], 0, sep = ",")), collapse = " ")
}

polygon_to_kml <- function(geom) {
  # geom: an sfg of type POLYGON or MULTIPOLYGON
  if (inherits(geom, "POLYGON")) {
    parts <- list(geom)
  } else if (inherits(geom, "MULTIPOLYGON")) {
    parts <- geom
  } else {
    return("")
  }
  poly_kmls <- vapply(parts, function(rings) {
    outer <- rings[[1]]
    inner <- if (length(rings) > 1) rings[-1] else list()
    outer_kml <- sprintf(
      "<outerBoundaryIs><LinearRing><coordinates>%s</coordinates></LinearRing></outerBoundaryIs>",
      ring_to_kml_coords(outer)
    )
    inner_kml <- paste(vapply(inner, function(hole) {
      sprintf("<innerBoundaryIs><LinearRing><coordinates>%s</coordinates></LinearRing></innerBoundaryIs>",
              ring_to_kml_coords(hole))
    }, character(1)), collapse = "")
    sprintf("<Polygon><tessellate>1</tessellate>%s%s</Polygon>", outer_kml, inner_kml)
  }, character(1))
  if (length(poly_kmls) == 1) poly_kmls else sprintf("<MultiGeometry>%s</MultiGeometry>", paste(poly_kmls, collapse = ""))
}

write_lga_boundary_kml <- function(path, lgas_sf) {
  parts <- c(
    '<?xml version="1.0" encoding="utf-8" ?>',
    '<kml xmlns="http://www.opengis.net/kml/2.2">',
    '<Document id="root_doc">',
    '<Style id="lgaBoundaryStyle">',
    '  <LineStyle><color>ff64381f</color><width>3</width></LineStyle>',
    '  <PolyStyle><fill>0</fill><outline>1</outline></PolyStyle>',
    '</Style>',
    '<Folder><name>LGA boundaries</name>'
  )
  for (i in seq_len(nrow(lgas_sf))) {
    row <- lgas_sf[i, ]
    esc <- function(s) {
      s <- gsub("&", "&amp;", s); s <- gsub("<", "&lt;", s); s <- gsub(">", "&gt;", s); s
    }
    desc <- esc(sprintf("State: %s\nLGA boundary source: OCHA/COD (authoritative). Use this to visually check a sample point's GPS location falls within the correct LGA - see How_To_Use_This_Package.pdf.", row$adm1_name))
    geom_kml <- polygon_to_kml(sf::st_geometry(row)[[1]])
    parts <- c(parts, sprintf(
      '<Placemark id="lga.%d">\n\t<name>%s</name>\n\t<description>%s</description>\n\t<styleUrl>#lgaBoundaryStyle</styleUrl>\n      %s\n  </Placemark>',
      i, esc(row$adm2_name), desc, geom_kml
    ))
  }
  parts <- c(parts, "</Folder>", "</Document>", "</kml>")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(paste(parts, collapse = "\n"), path, useBytes = TRUE)
}

# ---------------------------------------------------------------------------
# 4. One KML per partner, at their root folder.
# ---------------------------------------------------------------------------
all_partners <- sort(unique(unlist(sapply(pcodes_covered, function(p) get(p, envir = partners_by_pcode)))))
cat("Partners:", length(all_partners), "\n")

n_written <- 0
for (partner in all_partners) {
  partner_pcodes <- pcodes_covered[sapply(pcodes_covered, function(p) partner %in% get(p, envir = partners_by_pcode))]
  lgas_sf <- admin2_all %>% filter(adm2_pcode %in% partner_pcodes)
  if (nrow(lgas_sf) == 0) next
  out_path <- file.path(OUT_ROOT, safe_folder_name(partner), "LGA_boundaries.kml")
  write_lga_boundary_kml(out_path, lgas_sf)
  n_written <- n_written + 1
  cat(sprintf("  %s: %d LGA(s) -> %s\n", partner, nrow(lgas_sf), out_path))
}

cat("\nDONE. Written for", n_written, "partners.\n")
