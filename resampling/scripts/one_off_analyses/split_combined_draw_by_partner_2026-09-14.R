# ==============================================================================
# Splits the 2026-09-14 comprehensive combined draw's staged output
# (resample_runs/_combined/2026-09-14_comprehensive/) into one folder per
# partner (resample_runs/<Partner>/2026-09-14_comprehensive/), using the
# partner column already present in shortfalls_non_idp.csv/shortfalls_idp.csv
# to map each adm2_pcode to its owning partner - all 9 shortfall partners
# were checked and confirmed to have fully disjoint LGA sets before this
# combined draw was run, so this split is unambiguous (same precedent as
# the 2026-09-08 "_batch5" 6-partner combined draw). Each partner folder
# gets exactly the merge script's expected filenames (new_clusters.csv/
# new_households.csv, new_clusters_idp_sitelevel.csv/new_households_
# idp_sitelevel.csv) containing only that partner's own rows, plus its own
# shortfalls_non_idp.csv/shortfalls_idp.csv (for merge_partner_resample_
# batch.R's PARTNER_PCODES derivation).
# ==============================================================================
suppressMessages({ library(dplyr); library(readr); library(sf) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
SRC <- "resampling/output/resample_runs/_combined/2026-09-14_comprehensive"

shortfalls_non_idp <- read_csv(file.path(SRC, "shortfalls_non_idp.csv"), show_col_types = FALSE)
shortfalls_idp <- read_csv(file.path(SRC, "shortfalls_idp.csv"), show_col_types = FALSE)
pcode_to_partner <- bind_rows(
  shortfalls_non_idp %>% select(adm2_pcode, partners),
  shortfalls_idp %>% select(adm2_pcode, partners)
) %>% distinct(adm2_pcode, partners)

partners <- sort(unique(pcode_to_partner$partners))
cat(sprintf("Splitting for %d partner(s): %s\n", length(partners), paste(partners, collapse = ", ")))

new_clusters <- st_read(file.path(SRC, "new_clusters.gpkg"), quiet = TRUE)
new_households <- read_csv(file.path(SRC, "new_households.csv"), show_col_types = FALSE)
new_clusters_idp_site <- read_csv(file.path(SRC, "new_clusters_idp_sitelevel.csv"), show_col_types = FALSE)
new_households_idp_site <- read_csv(file.path(SRC, "new_households_idp_sitelevel.csv"), show_col_types = FALSE)

for (p in partners) {
  pcodes <- pcode_to_partner %>% filter(partners == p) %>% pull(adm2_pcode)
  out_dir <- file.path("resampling/output/resample_runs", p, "2026-09-14_comprehensive")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  p_clusters <- new_clusters %>% filter(adm2_pcode %in% pcodes)
  p_households <- new_households %>% filter(cluster_id %in% p_clusters$cluster_id)
  if (nrow(p_clusters) > 0) {
    st_write(p_clusters, file.path(out_dir, "new_clusters.gpkg"), delete_layer = TRUE, quiet = TRUE)
  }
  write_csv(st_drop_geometry(p_clusters), file.path(out_dir, "new_clusters.csv"))
  write_csv(p_households, file.path(out_dir, "new_households.csv"))

  p_clusters_idp <- new_clusters_idp_site %>% filter(adm2_pcode %in% pcodes)
  p_households_idp <- new_households_idp_site %>% filter(cluster_id %in% p_clusters_idp$cluster_id)
  write_csv(p_clusters_idp, file.path(out_dir, "new_clusters_idp_sitelevel.csv"))
  write_csv(p_households_idp, file.path(out_dir, "new_households_idp_sitelevel.csv"))

  write_csv(shortfalls_non_idp %>% filter(adm2_pcode %in% pcodes), file.path(out_dir, "shortfalls_non_idp.csv"))
  write_csv(shortfalls_idp %>% filter(adm2_pcode %in% pcodes), file.path(out_dir, "shortfalls_idp.csv"))

  cat(sprintf("  %s: %d Non-IDP cluster(s)/%d hh, %d IDP site cluster(s)/%d hh -> %s\n",
              p, nrow(p_clusters), nrow(p_households), nrow(p_clusters_idp), nrow(p_households_idp), out_dir))
}
