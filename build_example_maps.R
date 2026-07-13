suppressMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(ggspatial)
})

households <- sf::st_read("output/stage2_sampling_frame.gpkg", quiet = TRUE)

# ---- Pick good example clusters: well-populated, not understaffed ----

cluster_summary <-
  households %>%
  sf::st_drop_geometry() %>%
  group_by(cluster_id, pop_type, region, adm2_name, households_in_cluster, understaffed_cluster) %>%
  summarise(n_primary = sum(status == "primary"), n_reserve = sum(status == "reserve"), .groups = "drop") %>%
  filter(!understaffed_cluster, n_primary == 6, households_in_cluster >= 20, households_in_cluster <= 60) %>%
  arrange(desc(households_in_cluster))

host_example <- cluster_summary %>% filter(pop_type == "host") %>% slice(1)
idp_example  <- cluster_summary %>% filter(pop_type == "idp") %>% slice(1)

cat("Host example cluster:", host_example$cluster_id, "-", host_example$adm2_name, host_example$region,
    "- N buildings:", host_example$households_in_cluster, "\n")
cat("IDP example cluster:", idp_example$cluster_id, "-", idp_example$adm2_name, idp_example$region,
    "- N buildings:", idp_example$households_in_cluster, "\n")

saveRDS(list(host_id = host_example$cluster_id, idp_id = idp_example$cluster_id),
        "output/example_cluster_ids.rds")

cat("DONE\n")
