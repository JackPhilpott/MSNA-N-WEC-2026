# Decomposes the 2026-09-26 WORKING change (final accessibility decisions (FACT/Isa 38 + Kekeno + CRS Shagari 9) + refresh on the SAME 26 Sep export)
# into (i) accessibility, (ii) data basis (interviews completed / reopened) and (iii) anything else.
# READ-ONLY on the frame; writes results only to resampling/output/final_accessibility_change_result_2026-09-27/.
#
# Method: WORKING is a pure function of (FULL incl. ward_accessible_status, submissions, deletions overlay,
# cluster overlay, target-correction drops). Reproduce it offline with the shared functions:
#   W0 = WORKING before the change (snapshot)          [09-25 data, old accessibility]
#   W1 = build(FULL_old_status, 26 Sep data)           [26 Sep data, OLD accessibility]  -> W0 -> W1 = (ii) data basis
#   W2 = build(FULL_new_status, 26 Sep data)           [26 Sep data, NEW accessibility]  -> W1 -> W2 = (i) accessibility
# and validate the reproduction: build(FULL_new_status) must equal the WORKING the real refresh just wrote.
suppressMessages({ library(dplyr); library(readr); library(tidyr) })
B <- "C:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026"
S <- file.path(B, "1_sampling"); M <- file.path(B, "2_monitoring"); setwd(S)
source("scripts/shared/assert_plausible.R"); source("scripts/shared/frame_status.R")
DC <- "output/data/data_collection"; SNAP <- file.path(DC, "_archive/2026-09-26_pre_final_accessibility")
OUT <- "resampling/output/final_accessibility_change_result_2026-09-27"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
rd <- function(p) read_csv(p, show_col_types = FALSE, col_types = cols(.default = "c"))
fn <- function(k, v = "v13", s = "stage2_sampling_frame") sprintf("NGA_MSNA_2026_%s_%s_%s.csv", s, v, k)
t0 <- Sys.time(); options(width = 220)

W0 <- rd(file.path(SNAP, fn("WORKING"))); F0 <- rd(file.path(SNAP, fn("FULL")))
W2 <- rd(file.path(DC, fn("WORKING"))); F2 <- rd(file.path(DC, fn("FULL")))
subs <- rd(file.path(M, "data/real_submissions.csv")); del <- rd(file.path(M, "data/CONFIRMED_DELETIONS_OVERLAY.csv"))
al <- compute_achieved_lookup(subs, del)
stopifnot(!anyDuplicated(F2$survey_id), !anyDuplicated(W2$survey_id), !anyDuplicated(W0$survey_id))
cat("md5 check of snapshot vs expected: ", paste(tools::md5sum(file.path(SNAP, c(fn("WORKING"), fn("FULL")))), collapse = " / "), "\n")

# ---- exact copy of refresh_working_frame_daily.R lines 288-339 -------------------------------------------
build <- function(full_df) {
  acc <- compute_cluster_accessibility(full_df, 4)
  ca <- acc$covered_accessible
  non_idp_rows <- ca %>% filter(pop_type == "non_idp") %>% filter(!(survey_id %in% al$non_idp_survey_ids))
  idp_rows <- ca %>% filter(pop_type == "idp")
  idp_primary <- idp_rows %>% filter(status == "primary") %>%
    left_join(al$idp_counts %>% filter(matched_status == "primary") %>% select(matched_cluster_id, n_achieved), by = c("cluster_id" = "matched_cluster_id")) %>%
    mutate(n_achieved = coalesce(n_achieved, 0L), interview_number = as.integer(interview_number)) %>%
    group_by(cluster_id) %>% arrange(interview_number, .by_group = TRUE) %>% mutate(rn = row_number()) %>% filter(rn > n_achieved) %>% ungroup() %>%
    select(-n_achieved, -rn) %>% mutate(interview_number = as.character(interview_number))
  idp_reserve <- idp_rows %>% filter(status == "reserve") %>%
    left_join(al$idp_counts %>% filter(matched_status == "reserve") %>% select(matched_cluster_id, n_achieved), by = c("cluster_id" = "matched_cluster_id")) %>%
    mutate(n_achieved = coalesce(n_achieved, 0L), replacement_rank = as.integer(replacement_rank)) %>%
    group_by(cluster_id) %>% arrange(replacement_rank, .by_group = TRUE) %>% mutate(rn = row_number()) %>% filter(rn > n_achieved) %>% ungroup() %>%
    select(-n_achieved, -rn) %>% mutate(replacement_rank = as.character(replacement_rank))
  list(working = bind_rows(non_idp_rows, bind_rows(idp_primary, idp_reserve)) %>% select(all_of(names(full_df))), pool = ca)
}
b2 <- build(F2); b1 <- build(F0)
W1 <- b1$working
cat(sprintf("VALIDATION: reproduced W2 rows %d vs real WORKING %d; identical() = %s\n", nrow(b2$working), nrow(W2), identical(as.data.frame(b2$working), as.data.frame(W2))))
stopifnot(setequal(b2$working$survey_id, W2$survey_id))

ids0 <- W0$survey_id; ids1 <- W1$survey_id; ids2 <- W2$survey_id
pool1 <- b1$pool$survey_id
ref <- F2 %>% select(survey_id, cluster_id, pop_type, status, adm1_name, adm2_name, adm3_name, ward_accessible_status, strata_id)
ref0 <- F0 %>% select(survey_id, ward_status_old = ward_accessible_status)
ref <- ref %>% left_join(ref0, by = "survey_id")
rows <- function(ids) ref %>% filter(survey_id %in% ids)

# (ii-a) removed by data basis: in W0, not in W1
ii_a <- setdiff(ids0, ids1); ii_b <- setdiff(ids1, ids0)             # (ii-b) reopened: in W1 not in W0
i_rm <- setdiff(ids1, ids2); i_add <- setdiff(ids2, ids1)           # (i) removed by accessibility; added by accessibility (must be 0)
other_a <- ii_a[!(ii_a %in% pool1)]                                  # removed but NOT via the achieved filter of the old-accessibility pool
cat(sprintf("\nW0 %d rows / %d clusters -> W1 %d / %d -> W2 %d / %d\n", nrow(W0), n_distinct(W0$cluster_id), nrow(W1), n_distinct(W1$cluster_id), nrow(W2), n_distinct(W2$cluster_id)))
cat(sprintf("(ii-a) removed by data basis (interviews completed): %d rows | (ii-b) reopened by data basis: %d rows | (i) removed by accessibility: %d rows | (i-add) added by accessibility: %d\n",
            length(ii_a), length(ii_b), length(i_rm), length(i_add)))
cat(sprintf("(iii) removed 09-25->09-26 but NOT explained by the achieved filter on the old-accessibility pool: %d\n", length(other_a)))

# FULL diff: only ward_accessible_status may change, only in the flipped portions
stopifnot(identical(names(F0), names(F2)), setequal(F0$survey_id, F2$survey_id))
F0o <- F0[match(F2$survey_id, F0$survey_id), ]
chg_cols <- names(F2)[vapply(names(F2), function(cn) any(!(F0o[[cn]] == F2[[cn]] | (is.na(F0o[[cn]]) & is.na(F2[[cn]]))), na.rm = TRUE) || any(xor(is.na(F0o[[cn]]), is.na(F2[[cn]]))), logical(1))]
cat("\nFULL: columns that differ between snapshot and now:", paste(chg_cols, collapse = ", "), "\n")
fchg <- F2 %>% mutate(old = F0o$ward_accessible_status) %>% filter(old != ward_accessible_status)
full_by_portion <- fchg %>% count(adm1_name, adm2_name, adm3_name, old, new = ward_accessible_status, pop_type, name = "rows") %>% arrange(adm2_name, adm3_name)
full_by_portion_tot <- fchg %>% count(adm1_name, adm2_name, adm3_name, old, new = ward_accessible_status, name = "rows")
print(as.data.frame(full_by_portion_tot), right = FALSE)
cat("FULL rows changed total:", nrow(fchg), "\n")
partner_lgas <- c("Chibok", "Damboa", "Kankia", "Bodinga", "Goronyo", "Gwadabawa", "Rabah", "Tambuwal")
cat("FULL rows changed in the 8 partner-column LGAs (Chibok/Damboa/Kankia/5 Sokoto):", sum(fchg$adm2_name %in% partner_lgas & fchg$adm1_name %in% c("Borno", "Katsina", "Sokoto")), "\n")

# detail of every row that left WORKING
detail <- bind_rows(
  rows(ii_a) %>% mutate(bucket = "ii_removed_data_basis", why = as.character(ifelse(survey_id %in% pool1, "in old-accessibility pool, dropped as achieved", "NOT in old-accessibility pool"))),
  rows(i_rm) %>% mutate(bucket = "i_removed_accessibility", why = NA_character_),
  rows(ii_b) %>% mutate(bucket = "ii_reopened_data_basis", why = NA_character_),
  rows(i_add) %>% mutate(bucket = "i_added_by_accessibility", why = NA_character_))
flipped_portion_keys <- fchg %>% distinct(adm1_name, adm2_name, adm3_name)
fclusters <- F2 %>% semi_join(flipped_portion_keys, by = c("adm1_name", "adm2_name", "adm3_name")) %>% distinct(cluster_id) %>% pull(cluster_id)
# accessibility bucket: direct (row sits in a newly-Inaccessible portion) vs whole-cluster drop (<4 accessible primary rows left)
detail <- detail %>% mutate(
  acc_reason = case_when(bucket != "i_removed_accessibility" ~ NA_character_,
                         !is.na(ward_accessible_status) & ward_accessible_status == "Inaccessible" & ward_status_old != "Inaccessible" ~ "row in a newly-Inaccessible ward portion",
                         cluster_id %in% fclusters ~ "row in a cluster dropped whole (a flipped portion took it under 4 accessible primary rows or it straddles a flipped portion)",
                         TRUE ~ "UNEXPLAINED"))
write_csv(detail, file.path(OUT, "rows_that_left_or_entered_WORKING_detail.csv"))
cat("\nBucket x reason:\n"); print(as.data.frame(count(detail, bucket, why, acc_reason)), right = FALSE)
cat("\n(i) removed by accessibility, by LGA / pop_type / status:\n"); print(as.data.frame(rows(i_rm) %>% count(adm1_name, adm2_name, pop_type, status, name = "rows")), right = FALSE)
cat("(i) clusters affected (any row removed):", n_distinct(rows(i_rm)$cluster_id), "| clusters removed ENTIRELY from WORKING by accessibility:", length(setdiff(W1$cluster_id, W2$cluster_id)), "\n")
cat("(ii-a) removed by data basis, by pop_type:\n"); print(as.data.frame(rows(ii_a) %>% count(pop_type, name = "rows")), right = FALSE)
cat("(ii-a) clusters removed entirely from WORKING by data basis:", length(setdiff(W0$cluster_id, W1$cluster_id)), "\n")
cat("(ii-b) reopened rows:", length(ii_b), "\n"); if (length(ii_b)) print(as.data.frame(rows(ii_b) %>% count(adm1_name, adm2_name, pop_type, name = "rows")), right = FALSE)

# the 8 partner-column LGAs: every change must be data basis only
sel <- function(ids) rows(ids) %>% filter(adm2_name %in% partner_lgas & adm1_name %in% c("Borno", "Katsina", "Sokoto"))
cat("\nPartner-column LGAs (Chibok, Damboa, Kankia, 5 Sokoto): W0 rows", nrow(W0 %>% filter(adm2_name %in% partner_lgas, adm1_name %in% c("Borno", "Katsina", "Sokoto"))),
    "| W1 -> W2 (accessibility) rows changed:", nrow(sel(i_rm)) + nrow(sel(i_add)), "| removed by data basis:", nrow(sel(ii_a)), "| reopened:", nrow(sel(ii_b)), "\n")

# per-LGA Non-IDP primary points before / after
lgas <- c("Matazu", "Dandume", "Faskari", "Funtua", "Malumfashi")
npp <- function(w, lab) w %>% filter(adm1_name == "Katsina", adm2_name %in% lgas, pop_type == "non_idp", status == "primary") %>% count(adm2_name, name = lab)
per_lga <- Reduce(function(a, b) full_join(a, b, by = "adm2_name"), list(npp(W0, "W0_before_25Sep_frame"), npp(W1, "W1_26Sep_data_old_accessibility"), npp(W2, "W2_after"))) %>% arrange(match(adm2_name, lgas))
per_lga$register_expectation <- c(Matazu = "71->16", Dandume = "71->25", Faskari = "40->25", Funtua = "71->1", Malumfashi = "21->14")[per_lga$adm2_name]
cat("\nNon-IDP PRIMARY points in WORKING, Katsina:\n"); print(as.data.frame(per_lga), right = FALSE); write_csv(per_lga, file.path(OUT, "per_lga_nonidp_primary_points.csv"))
all_lga <- function(w, lab) w %>% count(adm1_name, adm2_name, pop_type, name = lab)
by_lga <- all_lga(W0, "W0") %>% full_join(all_lga(W1, "W1"), by = c("adm1_name", "adm2_name", "pop_type")) %>% full_join(all_lga(W2, "W2"), by = c("adm1_name", "adm2_name", "pop_type")) %>%
  mutate(across(c(W0, W1, W2), ~ coalesce(.x, 0L)), d_data_basis = W1 - W0, d_accessibility = W2 - W1) %>% arrange(adm1_name, adm2_name, pop_type)
write_csv(by_lga, file.path(OUT, "working_rows_by_lga_poptype_W0_W1_W2.csv"))
cat("\nLGA x pop_type with an ACCESSIBILITY change (W1 != W2):\n"); print(as.data.frame(by_lga %>% filter(d_accessibility != 0)), right = FALSE)
cat("Number of LGA x pop_type cells with a data-basis change:", sum(by_lga$d_data_basis != 0), "\n")

# columns / schema
cat("\nWORKING columns W0/W2:", ncol(W0), ncol(W2), "identical names:", identical(names(W0), names(W2)), "\n")

# strata WORKING + cluster status
SW0 <- rd(file.path(SNAP, fn("WORKING", s = "strata_level_sampling_frame"))); SW2 <- rd(file.path(DC, fn("WORKING", s = "strata_level_sampling_frame")))
cat("strata WORKING rows:", nrow(SW0), "->", nrow(SW2), " same strata set:", setequal(SW0$strata_id, SW2$strata_id), " same columns:", identical(names(SW0), names(SW2)), "\n")
scols <- setdiff(names(SW0), "strata_id"); SW0o <- SW0[match(SW2$strata_id, SW0$strata_id), ]
sd <- bind_rows(lapply(scols, function(cn) { a <- SW0o[[cn]]; b <- SW2[[cn]]; k <- which(!(a == b | (is.na(a) & is.na(b))) | xor(is.na(a), is.na(b))); if (!length(k)) NULL else data.frame(strata_id = SW2$strata_id[k], column = cn, before = a[k], after = b[k]) }))
cat("strata cells changed:", nrow(sd), " strata affected:", n_distinct(sd$strata_id), " columns:", paste(unique(sd$column), collapse = ", "), "\n")
write_csv(sd, file.path(OUT, "strata_working_cell_changes.csv")); print(as.data.frame(sd %>% count(column)), right = FALSE)
# strata-level attribution: SW0 (09-25 data, old access) -> SW1 (26 Sep data, OLD access) -> SW2 (26 Sep data, NEW access)
acc1 <- compute_cluster_accessibility(F0, 4); acc2 <- compute_cluster_accessibility(F2, 4)
s1 <- compute_strata_achieved(F0, al, acc1, TRUE)$agg; s2 <- compute_strata_achieved(F2, al, acc2, TRUE)$agg
stt <- SW0 %>% select(strata_id, target_sample, N_hh, ICC, clusters0 = achieved_clusters, sample0 = achieved_sample, moe0 = realized_moe_pct) %>%
  left_join(s1 %>% rename(clusters1 = achieved_clusters, sample1 = achieved_sample), by = "strata_id") %>%
  left_join(SW2 %>% select(strata_id, clusters2 = achieved_clusters, sample2 = achieved_sample, moe2 = realized_moe_pct), by = "strata_id") %>%
  mutate(across(c(clusters0, sample0, clusters1, sample1, clusters2, sample2, moe0, moe2, target_sample), as.numeric)) %>%
  mutate(clusters1 = coalesce(clusters1, 0), sample1 = coalesce(sample1, 0)) %>%
  mutate(d_data_basis_sample = sample1 - sample0, d_accessibility_sample = sample2 - sample1, d_data_basis_clusters = clusters1 - clusters0, d_accessibility_clusters = clusters2 - clusters1)
s2chk <- SW2 %>% select(strata_id, sample2 = achieved_sample) %>% mutate(sample2 = as.numeric(sample2)) %>% left_join(s2 %>% rename(sample_r = achieved_sample), by = "strata_id") %>% mutate(sample_r = coalesce(sample_r, 0L))
cat("strata-level reproduction of current WORKING achieved_sample (all strata equal):", all(s2chk$sample2 == s2chk$sample_r), "
")
sch <- stt %>% filter(d_data_basis_sample != 0 | d_accessibility_sample != 0 | d_data_basis_clusters != 0 | d_accessibility_clusters != 0)
cat("strata with any change:", nrow(sch), " | data-basis-only:", sum(sch$d_accessibility_sample == 0 & sch$d_accessibility_clusters == 0), " | accessibility-driven:", sum(sch$d_accessibility_sample != 0 | sch$d_accessibility_clusters != 0), "
")
print(as.data.frame(sch %>% select(strata_id, target_sample, sample0, sample1, sample2, d_data_basis_sample, d_accessibility_sample, clusters0, clusters1, clusters2, moe0, moe2) %>% mutate(across(c(moe0, moe2), ~ round(.x, 2)))), right = FALSE)
write_csv(sch, file.path(OUT, "strata_working_change_attribution.csv"))
CS0 <- rd(file.path(SNAP, "NGA_MSNA_2026_cluster_status_v13.csv")); CS2 <- rd(file.path(DC, "NGA_MSNA_2026_cluster_status_v13.csv"))
cs <- CS0 %>% select(cluster_id, status0 = status, acc0 = currently_accessible, ach0 = n_achieved) %>% full_join(CS2 %>% select(cluster_id, status2 = status, acc2 = currently_accessible, ach2 = n_achieved), by = "cluster_id")
cat("\ncluster_status rows:", nrow(CS0), "->", nrow(CS2), " status transitions:\n"); print(as.data.frame(cs %>% filter(is.na(status0) | is.na(status2) | status0 != status2) %>% count(status0, status2)), right = FALSE)
write_csv(cs %>% filter(is.na(status0) | is.na(status2) | status0 != status2 | acc0 != acc2 | ach0 != ach2), file.path(OUT, "cluster_status_changes.csv"))
write_csv(full_by_portion_tot, file.path(OUT, "FULL_ward_accessible_status_changes_by_portion.csv"))
cat(sprintf("\nELAPSED %.1f s\n", as.numeric(Sys.time() - t0, units = "secs")))
