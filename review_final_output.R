suppressMessages(library(dplyr))

h <- readr::read_csv("output/stage2_sampling_frame.csv", show_col_types = FALSE)

cat("=== ROW COUNTS ===\n")
cat("Total rows:", nrow(h), "\n")
cat("Duplicate survey_id:", anyDuplicated(h$survey_id), "\n")
print(table(h$status))
print(table(h$pop_type))

cat("\n=== HOUSEHOLDS PER CLUSTER (primary only) ===\n")
primary_per_cluster <- h %>% filter(status == "primary") %>% count(cluster_id)
print(table(primary_per_cluster$n))

cat("\n=== UNDERSTAFFED CLUSTERS ===\n")
understaffed <- h %>% filter(understaffed_cluster) %>% distinct(cluster_id, households_in_cluster, target_households)
cat("Count of understaffed clusters:", nrow(understaffed), "\n")
cat("Total clusters represented in output:", n_distinct(h$cluster_id), "\n")

cat("\n=== ZERO-BUILDING CLUSTERS (from warning) ===\n")
# computed separately - see warning message in run log

cat("\n=== WEIGHTS ===\n")
print(summary(h$base_weight))
print(summary(h$psu_probability))
print(summary(h$ssu_probability))

cat("\n=== ADMIN3 COVERAGE ===\n")
cat("NA adm3_pcode (GRID3 primary):", sum(is.na(h$adm3_pcode)), "of", nrow(h), "\n")
print(table(h$admin3_source, useNA = "ifany"))
cat("NA admin3_cod_pcode (secondary):", sum(is.na(h$admin3_cod_pcode)), "of", nrow(h), "\n")
print(table(h$region, !is.na(h$admin3_cod_pcode)))

cat("\n=== GEOGRAPHIC SPREAD ===\n")
print(table(h$region))
print(table(h$region, h$pop_type))

cat("\n=== COORDINATE SANITY ===\n")
cat("Longitude range:", range(h$longitude, na.rm=TRUE), "\n")
cat("Latitude range:", range(h$latitude, na.rm=TRUE), "\n")
cat("NA coordinates:", sum(is.na(h$longitude) | is.na(h$latitude)), "\n")

cat("\n=== CERTAINTY VS PPS ===\n")
print(table(h$selection_type))

cat("\nDONE\n")
