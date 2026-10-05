# ==============================================================================
# 2026-10-05 STAGING ONLY (Jack, via the Coordinator: "partner check = yes, send today"; Jack sends the emails
# himself): per-partner KML + reply-form CSV of the SETTLEMENT-SCALE Non-IDP hexes the building check dropped (>= 200
# WorldPop people per hex, fewer than 6 accessible unclaimed buildings), asking whether host-community households live
# there. Scope (Jack/Coordinator): NRC Gwoza; FACT Dikwa, Machina, Kala/Balge; INTERSOS Magumeri; PLAN Kala/Balge;
# FACT Mafa as a separate optional file. Writes only to resampling/output/partner_check_settlement_hexes_2026-10-05/.
# KML for Maps.me: hex outline as a CLOSED LineString (Maps.me rejects Polygon, see build_partner_lga_boundary_kml.R)
# plus a point at the centre carrying the question; newlines as &#10; (Maps.me rejects raw ones).
# Usage (from 1_sampling): Rscript resampling/scripts/one_off_analyses/stage_partner_check_settlement_hexes_2026-10-05.R
# ==============================================================================
suppressPackageStartupMessages({ library(sf); library(dplyr); library(readr) })
sf_use_s2(FALSE)
IN <- file.path("resampling", "output", "analysis_building_vs_worldpop_2026-10-05", "dropped_hexes_by_ward.csv")
OUT <- file.path("resampling", "output", "partner_check_settlement_hexes_2026-10-05")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
QUESTION <- paste("Are there HOST-COMMUNITY (non-IDP) households living in this area? If yes, roughly how many?",
                  "If it is an IDP camp/site or empty/abandoned, say so.")
FILES <- list(NRC = c("Gwoza"), FACT = c("Dikwa", "Machina", "Kala/Balge"), INTERSOS = c("Magumeri"),
              PLAN = c("Kala/Balge"), FACT_optional_Mafa = c("Mafa"))

hx <- read_csv(IN, col_types = cols(.default = "c"), show_col_types = FALSE) %>% filter(scale == "settlement")
geo <- readRDS("input_data/population/sampling_frame/hex_grid_non_idp.rds") %>% filter(uuid_hex_pop %in% hx$uuid_hex_pop) %>%
  select(uuid_hex_pop) %>% st_transform(4326)
cent <- suppressWarnings(st_centroid(geo)) %>% mutate(lon = st_coordinates(.)[, 1], lat = st_coordinates(.)[, 2]) %>% st_drop_geometry()
esc <- function(s) { s <- gsub("&", "&amp;", s); s <- gsub("<", "&lt;", s); s <- gsub(">", "&gt;", s); gsub("\n", "&#10;", s) }
ring_kml <- function(g) {  # closed LineString(s) for every ring of the hex polygon
  xy <- st_coordinates(g)
  rings <- split(as.data.frame(xy), interaction(xy[, "L1"], if ("L2" %in% colnames(xy)) xy[, "L2"] else 1, drop = TRUE))
  paste(vapply(rings, function(r) {
    pts <- rbind(r[, c("X", "Y")], r[1, c("X", "Y")])
    sprintf("<LineString><tessellate>1</tessellate><coordinates>%s</coordinates></LineString>",
            paste(sprintf("%.6f,%.6f,0", pts$X, pts$Y), collapse = " "))
  }, character(1)), collapse = "")
}

summary <- list()
for (f in names(FILES)) {
  sel <- hx %>% filter(lga %in% FILES[[f]]) %>% left_join(cent, by = "uuid_hex_pop") %>%
    arrange(lga, ward, desc(as.numeric(worldpop_people))) %>% mutate(check_no = row_number())
  partner <- sub("_optional_.*", "", f)
  pm <- character(0)
  for (i in seq_len(nrow(sel))) {
    r <- sel[i, ]
    label <- sprintf("CHECK %d - %s / %s (~%s people)", r$check_no, r$lga, r$ward, format(as.numeric(r$worldpop_people), big.mark = ","))
    desc <- esc(sprintf("Hex: %s\nState: %s\nLGA: %s\nWard: %s\nWorldPop estimate: %s people (~%s households)\nCentre: %.5f, %.5f\n\nQUESTION: %s\n\nPlease answer in the reply sheet (CSV), row CHECK %d.",
                        r$uuid_hex_pop, r$state, r$lga, r$ward, format(as.numeric(r$worldpop_people), big.mark = ","),
                        format(as.numeric(r$est_households), big.mark = ","), r$lat, r$lon, QUESTION, r$check_no))
    g <- geo$geometry[geo$uuid_hex_pop == r$uuid_hex_pop][[1]]
    pm <- c(pm,
      sprintf('<Placemark>\n\t<name>%s</name>\n\t<description>%s</description>\n\t<styleUrl>#checkPoint</styleUrl>\n\t<Point><coordinates>%.6f,%.6f,0</coordinates></Point>\n</Placemark>',
              esc(label), desc, r$lon, r$lat),
      sprintf('<Placemark>\n\t<name>%s (area outline)</name>\n\t<styleUrl>#checkOutline</styleUrl>\n\t%s\n</Placemark>', esc(label), ring_kml(g)))
  }
  kml <- c('<?xml version="1.0" encoding="UTF-8"?>', '<kml xmlns="http://www.opengis.net/kml/2.2">', "<Document>",
           sprintf("<name>%s - areas to check (host households?)</name>", esc(partner)),
           '<Style id="checkPoint"><IconStyle><color>ff00a5ff</color><scale>1.2</scale></IconStyle></Style>',
           '<Style id="checkOutline"><LineStyle><color>ff00a5ff</color><width>3</width></LineStyle></Style>',
           pm, "</Document>", "</kml>")
  writeLines(paste(kml, collapse = "\n"), file.path(OUT, sprintf("%s_areas_to_check_2026-10-05.kml", f)), useBytes = TRUE)
  form <- sel %>% transmute(check_no, hex_id = uuid_hex_pop, state, lga, ward, centre_lat = round(lat, 5), centre_lon = round(lon, 5),
                            worldpop_people, worldpop_est_households = est_households, question = QUESTION,
                            host_households_present_yes_no = "", approx_host_households = "", idp_camp_or_site_yes_no = "",
                            empty_or_abandoned_yes_no = "", notes = "", answered_by = "", date = "")
  write_csv(form, file.path(OUT, sprintf("%s_reply_form_2026-10-05.csv", f)), na = "")
  summary[[f]] <- tibble(file = f, hexes = nrow(sel), people = sum(as.numeric(sel$worldpop_people)),
                         lgas = paste(unique(sel$lga), collapse = ", "))
}
print(as.data.frame(bind_rows(summary)), row.names = FALSE)
cat("written to", OUT, "\n")
