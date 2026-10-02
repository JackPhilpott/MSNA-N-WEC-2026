# ==============================================================================
# 2026-10-02 READ-ONLY (Coordinator request, Option 3 IDP weights): per-batch
# phase-2 inclusion probability for every site_v2 cluster in FULL.
#   pi_b = min(1, k_b * site_hh / T2_b)  if the site was in batch b's pool, else 0
#   pi2  = 1 - prod_b (1 - pi_b)   over ALL merged site_v2 batches of the stratum
# k_b  = n_drawn_this_stratum from the staged batch file.
# T2_b = sum of pop_hh over the stratum LGA's sites that were Accessible in the
#        frame state at batch time and not within 30 m of any IDP cluster point
#        that existed before the batch (all hex_v1 clusters + site_v2 clusters
#        from earlier merged batches).
# Frame state at batch time (snapshot = state just BEFORE the refresh it names):
#   before 3 Sep 18:35 -> PRE_MOBBAR (exact) | to 7 Sep 06:00 -> PRE_REFRESH_0907
#   (exact) | to 21 Sep 00:48 -> PRE_REFRESH_0921 (exact if no unlogged refresh)
#   | 21 Sep 00:48 onward -> current frame if the LGA's sites are unchanged
#   between the 21 Sep .bak and today (then exact), else the 21 Sep .bak for the
#   4 later-closed LGAs (Safana/Tarmua/Gudu/Tureta), else current, flagged.
# Strata whose batch history is incomplete (a live site_v2 cluster that no
# staged batch accounts for, or a partially merged batch) are FLAGGED and get
# no pi2 - the Coordinator falls back to the single-pool approximation there.
# Inputs read only; writes the two CSVs named below.
# ==============================================================================
suppressMessages({ library(dplyr); library(sf); library(readr); library(tidyr) })
sf_use_s2(FALSE)
setwd("c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling")
OUT_DIR <- "resampling/output/full_weighting_build_2026-09-28"
SF <- "input_data/population/sampling_frame/"
snap <- list(
  s1 = readRDS(paste0(SF, "idp_site_level_psu_frame_2026-09-02_PRE_MOBBAR_backup_2026-09-03.rds")),
  s2 = readRDS(paste0(SF, "idp_site_level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-07.rds.bak")),
  s3 = readRDS(paste0(SF, "idp_site_level_psu_frame_2026-09-02_PRE_ACCESSIBILITY_REFRESH_2026-09-21.rds.bak")),
  s4 = readRDS(paste0(SF, "idp_site_level_psu_frame_2026-09-02.rds"))
)
for (n in names(snap)) stopifnot(!anyDuplicated(snap[[n]]$uuid_site), sf::st_crs(snap[[n]])$epsg == 31028)
site_hh <- st_drop_geometry(snap$s4) %>% select(uuid_site, adm2_pcode, pop_hh)
LATER_CLOSED <- c("Safana", "Tarmua", "Gudu", "Tureta")
t_mobbar <- as.POSIXct("2026-09-03 18:35:00"); t_0907 <- as.POSIXct("2026-09-07 06:00:00"); t_0921 <- as.POSIXct("2026-09-21 00:48:00")

# ---- live IDP clusters (one point each) ----
full <- read_csv("output/data/data_collection/NGA_MSNA_2026_stage2_sampling_frame_v14_FULL.csv",
                 col_types = cols(.default = "c"), show_col_types = FALSE) %>%
  filter(pop_type == "idp") %>% distinct(cluster_id, .keep_all = TRUE) %>%
  transmute(cluster_id, strata_id, adm2_pcode, adm2_name, psu_definition_version, uuid_hex,
            lon = as.numeric(longitude), lat = as.numeric(latitude))
pts <- st_transform(st_as_sf(full, coords = c("lon", "lat"), crs = 4326, remove = FALSE), 31028)

# ---- merged batches, de-duplicated across partner copies ----
inv <- read_csv(file.path(OUT_DIR, "site_v2_batch_inventory_2026-10-02.csv"), col_types = cols(.default = "c"), show_col_types = FALSE) %>%
  mutate(staged_clusters = as.integer(staged_clusters), staged_live_same_site = as.integer(staged_live_same_site),
         batch_time = as.POSIXct(batch_time), has_log = time_source != "folder_date")
long_inv <- inv %>% mutate(cid = strsplit(cluster_ids, "|", fixed = TRUE), usite = strsplit(uuid_sites, "|", fixed = TRUE)) %>%
  unnest(c(cid, usite)) %>% left_join(full %>% select(cid = cluster_id, live_site = uuid_hex, live_ver = psu_definition_version), by = "cid") %>%
  mutate(is_live = !is.na(live_site) & live_site == usite & live_ver == "site_v2")
merge_status <- long_inv %>% group_by(batch, strata_id) %>%
  summarise(n = n(), n_live = sum(is_live), .groups = "drop") %>%
  mutate(status = case_when(n_live == n ~ "merged", n_live == 0 ~ "not_merged", TRUE ~ "partial"))
merged_rows <- inv %>% inner_join(merge_status %>% filter(status == "merged") %>% select(batch, strata_id), by = c("batch", "strata_id")) %>%
  mutate(site_key = vapply(strsplit(uuid_sites, "|", fixed = TRUE), function(x) paste(sort(x), collapse = "|"), "")) %>%
  arrange(desc(has_log), batch_time) %>%
  group_by(strata_id, site_key) %>%
  summarise(batch = first(batch), batch_time = first(batch_time), time_basis = if (first(has_log)) "run log" else "folder date only",
            k_b = first(k_n_drawn_this_stratum), copies = n(), copy_batches = paste(sort(unique(batch)), collapse = " | "),
            adm2_pcode = first(adm2_pcode), .groups = "drop") %>%
  mutate(k_b = as.numeric(k_b))

# ---- ambiguous strata ----
live_v2 <- full %>% filter(psu_definition_version == "site_v2")
accounted <- long_inv %>% filter(is_live) %>% distinct(cid)
unaccounted <- live_v2 %>% filter(!cluster_id %in% accounted$cid)
partial <- merge_status %>% filter(status == "partial")
# Overlapping restagings: the same live site appearing in more than one de-duplicated
# batch of a stratum (e.g. the 7 Sep REDO 06:10 / redo_post_incident_purge 19:28 / v7
# 19:44 stagings around the incident purge). Which staging was the real draw event
# can't be confirmed from the files, and counting each as a separate draw inflates pi2.
site_batch_count <- merged_rows %>% mutate(site = strsplit(site_key, "|", fixed = TRUE)) %>%
  unnest(site) %>% count(strata_id, site, name = "n_batches")
overlap <- site_batch_count %>% filter(n_batches > 1) %>% distinct(strata_id) %>%
  left_join(merged_rows %>% group_by(strata_id) %>% summarise(b = paste(sort(unique(batch)), collapse = " / "), .groups = "drop"), by = "strata_id")
amb <- bind_rows(
  unaccounted %>% count(strata_id, name = "n") %>% mutate(reason = paste0(n, " live site_v2 cluster(s) not accounted for by any staged batch (site never staged under any id)")),
  partial %>% distinct(strata_id) %>% mutate(reason = "a staged batch is only partially live (merge unconfirmed)"),
  overlap %>% transmute(strata_id, reason = paste0("overlapping restagings of the same live clusters (", b, ") - which one was the draw event can't be confirmed"))
) %>% group_by(strata_id) %>% summarise(ambiguous_reason = paste(unique(reason), collapse = "; "), .groups = "drop")

# ---- frame state per (batch, LGA) ----
lga_changed <- function(adm2) {   # did any site's status in this LGA change between the 21 Sep .bak and now?
  a <- st_drop_geometry(snap$s3) %>% filter(adm2_pcode == adm2) %>% arrange(uuid_site)
  b <- st_drop_geometry(snap$s4) %>% filter(adm2_pcode == adm2) %>% arrange(uuid_site)
  !identical(a$uuid_site, b$uuid_site) || !identical(a$accessible_status, b$accessible_status)
}
pick_state <- function(t, adm2, adm2_name) {
  if (t < t_mobbar) return(list(s = "s1", basis = "exact snapshot (pre-Mobbar, 2-3 Sep)"))
  if (t < t_0907) return(list(s = "s2", basis = "exact snapshot (3-7 Sep)"))
  if (t < t_0921) return(list(s = "s3", basis = "snapshot 7-21 Sep (exact unless an unlogged refresh ran in between)"))
  if (!lga_changed(adm2)) return(list(s = "s4", basis = "exact (LGA's sites unchanged from 21 Sep .bak to today)"))
  if (adm2_name %in% LATER_CLOSED) return(list(s = "s3", basis = "nearest preserved state (21 Sep pre-refresh .bak; LGA closed later)"))
  list(s = "s4", basis = "UNCERTAIN: current frame, but this LGA's site statuses changed after 21 Sep")
}
hex_v1_pts <- pts %>% filter(psu_definition_version == "hex_v1")

batch_tbl <- merged_rows %>% filter(!strata_id %in% amb$strata_id)
adm2_names <- full %>% distinct(adm2_pcode, adm2_name)
batch_tbl <- batch_tbl %>% left_join(adm2_names, by = "adm2_pcode")
res <- list()
for (i in seq_len(nrow(batch_tbl))) {
  b <- batch_tbl[i, ]
  st <- pick_state(b$batch_time, b$adm2_pcode, b$adm2_name)
  sites <- snap[[st$s]] %>% filter(adm2_pcode == b$adm2_pcode)
  earlier_v2_ids <- merged_rows %>% filter(batch_time < b$batch_time) %>% pull(site_key) %>% strsplit("|", fixed = TRUE) %>% unlist()
  existing <- bind_rows(hex_v1_pts, pts %>% filter(psu_definition_version == "site_v2", uuid_hex %in% earlier_v2_ids))
  near <- lengths(st_is_within_distance(sites, existing, dist = 30)) > 0
  pool <- sites %>% mutate(in_pool = accessible_status %in% "Accessible" & !near)
  T2 <- sum(pool$pop_hh[pool$in_pool], na.rm = TRUE)
  drawn <- strsplit(b$site_key, "|", fixed = TRUE)[[1]]
  # why a drawn site is missing from its own batch's reconstructed pool (self-check diagnostics)
  why <- vapply(setdiff(drawn, pool$uuid_site[pool$in_pool]), function(u) {
    if (!u %in% sites$uuid_site) return("absent from snapshot LGA")
    s_ <- sites$accessible_status[sites$uuid_site == u]
    if (!(s_ %in% "Accessible")) return(paste0("status '", ifelse(is.na(s_), "NA", s_), "' in ", st$s))
    if (near[sites$uuid_site == u]) return("within 30 m of a pre-existing IDP point (Tier-2 repeat?)")
    "other"
  }, "")
  why_txt <- paste(unique(why), collapse = "; ")
  res[[i]] <- tibble(strata_id = b$strata_id, batch = b$batch, batch_time = format(b$batch_time, "%Y-%m-%d %H:%M:%S"),
                     time_basis = b$time_basis, k_b = b$k_b, T2_b = T2, pool_sites = sum(pool$in_pool),
                     frame_state = st$s, pool_basis = st$basis, staged_copies = b$copy_batches,
                     eligible_sites = list(pool$uuid_site[pool$in_pool]), drawn_sites = list(drawn),
                     drawn_but_not_in_pool = paste(setdiff(drawn, pool$uuid_site[pool$in_pool]), collapse = "|"),
                     n_drawn_not_in_pool = length(setdiff(drawn, pool$uuid_site[pool$in_pool])),
                     self_check_reason = if (length(why)) why_txt else "")
}
batches <- bind_rows(res)
write_csv(batches %>% select(-eligible_sites, -drawn_sites) %>% arrange(strata_id, batch_time),
          file.path(OUT_DIR, "idp_site_v2_pi2_batches_2026-10-02.csv"), na = "")
cat("\nbatch-strata failing the self-check, by reason:\n")
print(batches %>% filter(n_drawn_not_in_pool > 0) %>% count(self_check_reason, pool_basis, wt = n_drawn_not_in_pool, name = "drawn_sites_not_in_pool"))

# ---- per cluster x batch, then pi2 ----
clus <- live_v2 %>% filter(!strata_id %in% amb$strata_id) %>% select(cluster_id, strata_id, adm2_pcode, uuid_site = uuid_hex) %>%
  left_join(site_hh %>% select(uuid_site, site_hh = pop_hh), by = "uuid_site")
cb <- clus %>% inner_join(batches, by = "strata_id", relationship = "many-to-many")
cb$eligible <- mapply(function(u, e) u %in% e, cb$uuid_site, cb$eligible_sites)
cb$drawn_here <- mapply(function(u, d) u %in% d, cb$uuid_site, cb$drawn_sites)
cb$pi_b <- ifelse(cb$eligible & cb$T2_b > 0, pmin(1, cb$k_b * cb$site_hh / cb$T2_b), 0)
cb <- cb %>% select(-eligible_sites, -drawn_sites)
cat(sprintf("earliest merged site_v2 batch: %s (hex_v1 points are treated as pre-existing for every site_v2 batch)\n",
            format(min(merged_rows$batch_time), "%Y-%m-%d %H:%M:%S")))
pi2 <- cb %>% group_by(cluster_id) %>%
  summarise(n_batches = n(), pi2 = 1 - prod(1 - pi_b),
            drawn_in_batch = paste(batch[drawn_here], collapse = " | "),
            check_drawn_batch_eligible = all(eligible[drawn_here]) && any(drawn_here),
            .groups = "drop")
wide <- clus %>% left_join(pi2, by = "cluster_id") %>%
  left_join(cb %>% group_by(cluster_id) %>% arrange(batch_time) %>% mutate(j = row_number()) %>%
              summarise(batch_detail = paste0("[", j, "] ", batch, " @", batch_time, " k=", k_b, " T2=", round(T2_b), " pi=", signif(pi_b, 4),
                                              ifelse(drawn_here, " (DRAWN)", ""), ifelse(eligible, "", " (not in pool)"), " {", pool_basis, "}", collapse = " ;; "),
                        .groups = "drop"), by = "cluster_id")
amb_rows <- live_v2 %>% filter(strata_id %in% amb$strata_id) %>% select(cluster_id, strata_id, adm2_pcode, uuid_site = uuid_hex) %>%
  left_join(site_hh %>% select(uuid_site, site_hh = pop_hh), by = "uuid_site") %>% left_join(amb, by = "strata_id")
out <- bind_rows(wide %>% mutate(ambiguous_reason = NA_character_), amb_rows) %>% arrange(strata_id, cluster_id)
write_csv(out, file.path(OUT_DIR, "idp_site_v2_pi2_per_batch_2026-10-02.csv"), na = "")
write_csv(cb %>% arrange(strata_id, cluster_id, batch_time), file.path(OUT_DIR, "idp_site_v2_pi2_per_batch_LONG_2026-10-02.csv"), na = "")

cat(sprintf("site_v2 clusters: %d | computed: %d | ambiguous strata: %d (%d clusters)\n",
            nrow(live_v2), sum(!is.na(out$pi2)), nrow(amb), nrow(amb_rows)))
cat("merged batch x stratum (deduplicated):", nrow(merged_rows), "| used:", nrow(batches), "\n")
cat("pool bases used:\n"); print(table(batches$pool_basis))
cat(sprintf("self-check - drawn site inside its own batch's reconstructed pool: %d of %d clusters OK\n",
            sum(pi2$check_drawn_batch_eligible), nrow(pi2)))
bad <- pi2 %>% filter(!check_drawn_batch_eligible)
if (nrow(bad)) { cat("clusters whose drawing batch does NOT contain their site in the reconstructed pool:\n"); print(head(bad %>% select(cluster_id, drawn_in_batch), 15)) }
cat("pi2 summary (computed):\n"); print(summary(out$pi2))
print(amb)
