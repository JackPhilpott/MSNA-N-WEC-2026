# ==============================================================================
# LGA boundary KML - one file per partner, written at the partner's ROOT
# folder (not nested per-LGA like the point KMLs). Added 2026-08-17 per user
# request, after a field example session (Save the Children) revealed field
# teams have no easy way to visually cross-check a sample point's GPS
# location against its LGA boundary in Maps.me itself - this closes that
# gap directly, without needing a separate GIS tool.
#
# Revision 2026-08-18 (two changes, both from direct field testing):
#   1. Polygon -> LineString. The original version drew each LGA as a
#      filled-but-transparent Polygon outline. Confirmed via a minimal
#      isolated test (a single 4-point square, zero styling/dependencies)
#      that Maps.me's Bookmarks import rejects ANY Polygon placemark
#      outright as "corrupted or defective" - not a data defect (the file
#      was well-formed XML, valid UTF-8, topologically valid geometry, all
#      confirmed directly) but an actual Maps.me Bookmarks-import
#      limitation. The same shape as a closed LineString ("Track") imported
#      successfully. Every LGA boundary here is now a closed-loop
#      LineString instead of a Polygon - visually near-identical (an
#      outline either way) but actually opens in the app.
#   2. Whole-country context, not just the partner's own LGAs. Per direct
#      user request: every LGA in the 14 assessment states is now included
#      in every partner's file (thin blue, `lgaContextStyle`), with that
#      partner's own assigned LGAs additionally drawn in thick red
#      (`lgaCoveredStyle`) so their own assignment is unmistakable against
#      the surrounding context - useful for exactly the kind of "is this
#      point actually in a neighbouring LGA" confusion that prompted this
#      file in the first place (see the Gwandu/Tambuwal ward-boundary
#      case). Each LGA is drawn once, styled by whichever category it
#      falls into for that partner - not duplicated.
#
# Reuses the exact same LGA-name matching/reconciliation logic as
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
#    LGA-boundary layer in this project) - EVERY LGA in the 14 assessment
#    states now, not just covered ones (2026-08-18 revision #2 above).
#    admin1_focus_areas comes from the sourced pipeline prefix.
# ---------------------------------------------------------------------------
# NGA_shapes_all_cleaned$nga_admin2 already carries its own adm2_name/
# adm1_name columns - joining master_lgas (which also has those names) on
# top produced silently-suffixed adm2_name.x/.y duplicates instead of the
# plain names the KML writer expects (caught 2026-08-17 - every partner's
# KML came out with zero placemarks). Fixed by using the shapefile's own
# name columns directly - no join needed.
admin2_all <- NGA_shapes_all_cleaned$nga_admin2 %>% st_transform(4326) %>% st_make_valid() %>%
  filter(adm1_pcode %in% admin1_focus_areas)
stopifnot(all(c("adm2_name", "adm1_name") %in% names(admin2_all)))
cat("LGAs in the 14 assessment states (drawn in every partner's file as context):", nrow(admin2_all), "\n")

# ---------------------------------------------------------------------------
# 3. KML writer - closed-loop LineString per LGA (Maps.me rejects Polygon
#    placemarks in Bookmarks imports outright - confirmed 2026-08-18 via an
#    isolated minimal test; see header). Handles MULTIPOLYGON (multiple
#    parts, e.g. an LGA with an offshore/exclave piece) and holes (e.g. an
#    LGA that fully encloses another) generically - each ring becomes its
#    own closed LineString inside one MultiGeometry per placemark.
# ---------------------------------------------------------------------------
ring_to_kml_coords <- function(ring_mat) {
  paste(apply(ring_mat, 1, function(r) paste(r[1], r[2], 0, sep = ",")), collapse = " ")
}

geom_to_kml_linestrings <- function(geom) {
  # geom: an sfg of type POLYGON or MULTIPOLYGON. Returns one closed
  # LineString per ring (outer boundary + any holes), across all parts.
  if (inherits(geom, "POLYGON")) {
    parts <- list(geom)
  } else if (inherits(geom, "MULTIPOLYGON")) {
    parts <- geom
  } else {
    return("")
  }
  all_rings <- unlist(parts, recursive = FALSE)
  line_kmls <- vapply(all_rings, function(ring) {
    sprintf("<LineString><tessellate>1</tessellate><coordinates>%s</coordinates></LineString>", ring_to_kml_coords(ring))
  }, character(1))
  if (length(line_kmls) == 1) line_kmls else sprintf("<MultiGeometry>%s</MultiGeometry>", paste(line_kmls, collapse = ""))
}

write_lga_boundary_kml <- function(path, lgas_sf, covered_pcodes) {
  parts <- c(
    '<?xml version="1.0" encoding="utf-8" ?>',
    '<kml xmlns="http://www.opengis.net/kml/2.2">',
    '<Document id="root_doc">',
    # Red, thick - this partner's own assigned LGA(s). Reuses the same red
    # (#C00000) already used for warning/caution elements throughout this
    # project's factsheets.
    '<Style id="lgaCoveredStyle">',
    '  <LineStyle><color>ff0000c0</color><width>6</width></LineStyle>',
    '</Style>',
    # Blue (navy, #1F3864), thinner - every other LGA in the 14 assessment
    # states, for context only.
    '<Style id="lgaContextStyle">',
    '  <LineStyle><color>ff64381f</color><width>4</width></LineStyle>',
    '</Style>',
    '<Folder><name>LGA boundaries</name>'
  )
  # Draw order matters: a covered LGA shares its actual boundary LINE with
  # each neighbouring context LGA (same physical border, drawn once per
  # side), so whichever is written LAST wins visually where they overlap.
  # Context (blue) first, covered (red) last, so a partner's own red
  # boundary always renders as a complete, solid line on top of the blue
  # context underneath it - not the other way around (2026-08-18 feedback:
  # red lines were reading as broken/interrupted wherever a blue neighbour
  # happened to draw over the same shared edge afterward).
  is_covered_vec <- lgas_sf$adm2_pcode %in% covered_pcodes
  lgas_sf <- lgas_sf[order(is_covered_vec), ]
  for (i in seq_len(nrow(lgas_sf))) {
    row <- lgas_sf[i, ]
    is_covered <- row$adm2_pcode %in% covered_pcodes
    style_id <- if (is_covered) "lgaCoveredStyle" else "lgaContextStyle"
    # Matches build_partner_dc_packages.py's write_kml() exactly - a raw
    # newline embedded in a KML <description> text node is valid XML, but
    # was found 2026-08-18 to make Maps.me reject the whole file as
    # "corrupted or defective" alongside the Polygon issue above. The
    # already-working point KMLs avoid this by converting embedded
    # newlines to the numeric character reference &#10; before writing -
    # applied here too.
    esc <- function(s) {
      s <- gsub("&", "&amp;", s); s <- gsub("<", "&lt;", s); s <- gsub(">", "&gt;", s)
      gsub("\n", "&#10;", s)
    }
    coverage_note <- if (is_covered) {
      "This LGA is assigned to you."
    } else {
      "Shown for context only - not assigned to you."
    }
    desc <- esc(sprintf(
      "State: %s\n%s\nLGA boundary source: OCHA/COD (authoritative). Use this to visually check a sample point's GPS location falls within the correct LGA - see How_To_Use_This_Package.pdf.",
      row$adm1_name, coverage_note
    ))
    geom_kml <- geom_to_kml_linestrings(sf::st_geometry(row)[[1]])
    parts <- c(parts, sprintf(
      '<Placemark id="lga.%d">\n\t<name>%s</name>\n\t<description>%s</description>\n\t<styleUrl>#%s</styleUrl>\n      %s\n  </Placemark>',
      i, esc(row$adm2_name), desc, style_id, geom_kml
    ))
  }
  parts <- c(parts, "</Folder>", "</Document>", "</kml>")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(paste(parts, collapse = "\n"), path, useBytes = TRUE)
}

# ---------------------------------------------------------------------------
# 4. One KML per partner, at their root folder - same admin2_all (all 14-
#    state LGAs) drawn for every partner, only the red/blue styling differs
#    depending on which LGAs are THIS partner's own.
# ---------------------------------------------------------------------------
all_partners <- sort(unique(unlist(sapply(pcodes_covered, function(p) get(p, envir = partners_by_pcode)))))
cat("Partners:", length(all_partners), "\n")

# Opt-in single-partner scoping (env var, unset by default) - same
# BUILD_DC_ONLY_PARTNER hook build_partner_dc_packages.py and
# build_cluster_factsheets.py already use (see resampling/README.md's
# "Single-partner scoping" section); this script didn't have it yet
# (2026-08-28 fix, flagged in the comprehensive sweep). Lets a targeted fix
# (e.g. a corrected partner name) regenerate just that partner's own LGA
# boundary KML without rewriting the other 18 partners' already-delivered
# files. Normal/default behaviour (env var unset) is unchanged: every
# partner. Filtering all_partners here (rather than partners_by_pcode, like
# the Python siblings do) is enough on its own - partner_pcodes is only
# ever derived per-partner inside the loop below, so an unscoped partner's
# file is simply never reached, let alone rewritten.
BUILD_DC_ONLY_PARTNER <- Sys.getenv("BUILD_DC_ONLY_PARTNER", unset = "")
if (nzchar(BUILD_DC_ONLY_PARTNER)) {
  all_partners <- all_partners[all_partners == BUILD_DC_ONLY_PARTNER]
  cat("BUILD_DC_ONLY_PARTNER set - scoped to '", BUILD_DC_ONLY_PARTNER, "' only (", length(all_partners), " partner(s)).\n", sep = "")
}

n_written <- 0
for (partner in all_partners) {
  partner_pcodes <- pcodes_covered[sapply(pcodes_covered, function(p) partner %in% get(p, envir = partners_by_pcode))]
  out_path <- file.path(OUT_ROOT, safe_folder_name(partner), sprintf("LGA_boundaries_%s.kml", safe_folder_name(partner)))
  write_lga_boundary_kml(out_path, admin2_all, partner_pcodes)
  n_written <- n_written + 1
  cat(sprintf("  %s: %d of %d LGA(s) are theirs -> %s\n", partner, length(partner_pcodes), nrow(admin2_all), out_path))
}

cat("\nDONE. Written for", n_written, "partners.\n")
