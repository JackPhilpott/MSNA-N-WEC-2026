# ==============================================================================
# build_round1_weighting_package_2026-10-02.R
#
# Builds the data officer's Round 1 weighting package in
#   2_monitoring/reports/round1_weighting_package_2026-10-02/
# from the frozen Round 1 inputs (no weight is recomputed here):
#   - final weights      resampling/output/full_weighting_build_2026-09-28/round1_FINAL_2026-10-02/
#   - frozen submissions resampling/output/round1_final_snapshot_v2_2026-10-02/ (md5-checked)
#   - representativity   resampling/output/round1_representativity_prototype_2026-10-02/
#   - anonymised export  2_monitoring/cleaning/MSNA_Data_Cleaning/output/anonymised_data/ (1 Oct, latest)
#
# Round 1 analysis coverage (MSNA lead, 2 Oct): North-East and North-West
# states, Kebbi excluded; all North-Central states excluded. Weights are
# calibrated within each stratum (LGA x population group) and strata nest in
# states, so dropping states removes their strata and leaves every other
# weight unchanged - verified below, stratum by stratum.
#
# Run from 1_sampling/ (PowerShell; the dataset step needs a few minutes):
#   Rscript resampling/scripts/one_off_analyses/build_round1_weighting_package_2026-10-02.R             # everything
#   Rscript resampling/scripts/one_off_analyses/build_round1_weighting_package_2026-10-02.R --skip-dataset
# ==============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr) })

SKIP_DATASET <- "--skip-dataset" %in% commandArgs(trailingOnly = TRUE)

WS     <- normalizePath("..", winslash = "/")
S1     <- file.path(WS, "1_sampling")
PKG    <- file.path(WS, "2_monitoring/reports/round1_weighting_package_2026-10-02")
SNAP   <- file.path(S1, "resampling/output/round1_final_snapshot_v2_2026-10-02")
WDIR   <- file.path(S1, "resampling/output/full_weighting_build_2026-09-28/round1_FINAL_2026-10-02")
RDIR   <- file.path(S1, "resampling/output/round1_representativity_prototype_2026-10-02")
FRAME  <- file.path(S1, "output/data/data_collection/NGA_MSNA_2026_strata_level_sampling_frame_v14_FULL.csv")
EXPORT <- file.path(WS, "2_monitoring/cleaning/MSNA_Data_Cleaning/output/anonymised_data/NGA2605_MSNA_anonymised_2026-10-01.xlsx")
GUIDE  <- file.path(S1, "ROUND1_METHODOLOGY_AND_VALIDATION_GUIDE.md")

COVERAGE_REGIONS <- c("NE", "NW")
EXCLUDED_STATES  <- c("Kebbi")

rd <- function(p) read_csv(p, col_types = cols(.default = "c"), na = "", progress = FALSE)
blank <- function(x) is.na(x) | x == "" | x == "NA"
md5 <- function(p) unname(tools::md5sum(p))

# ---- inputs, checked against the frozen record ------------------------------
stopifnot(md5(file.path(SNAP, "real_submissions.csv")) == "24db61ae699e6de4bc6890f346a3b774")
stopifnot(startsWith(md5(file.path(WDIR, "ROUND1_WEIGHTS_FINAL_2026-10-02.csv")), "b3f261c8"))
rs  <- rd(file.path(SNAP, "real_submissions.csv"))
w   <- rd(file.path(WDIR, "ROUND1_WEIGHTS_FINAL_2026-10-02.csv"))
uw  <- rd(file.path(WDIR, "ROUND1_UNWEIGHTED_interviews_2026-10-02.csv"))
bs  <- rd(file.path(WDIR, "ROUND1_WEIGHTS_FINAL_by_stratum_2026-10-02.csv"))
r1s <- rd(file.path(RDIR, "round1_strata.csv"))
r1l <- rd(file.path(RDIR, "round1_lga.csv"))
r1t <- rd(file.path(RDIR, "round1_state.csv"))
fr  <- rd(FRAME)
mem_path <- list.files(SNAP, pattern = "^ROUND1_MEMBERSHIP.*\\.csv$", full.names = TRUE)[1]
if (is.na(mem_path)) mem_path <- file.path(WS, "2_monitoring/data/ROUND1_MEMBERSHIP.csv")
mem <- rd(mem_path)
mem_uuid <- mem[[intersect(c("submission_uuid", "uuid"), names(mem))[1]]]

states <- fr %>% distinct(adm1_pcode, adm1_name, region)
stopifnot(!anyDuplicated(states$adm1_pcode), !anyDuplicated(states$adm1_name))
covered_states <- states %>% filter(region %in% COVERAGE_REGIONS, !adm1_name %in% EXCLUDED_STATES) %>% pull(adm1_name)
cat("Round 1 analysis coverage states:", paste(sort(covered_states), collapse = ", "), "\n")
cat("Excluded states:", paste(sort(setdiff(states$adm1_name, covered_states)), collapse = ", "), "\n\n")

state_of_stratum <- function(sid) {
  pc <- sub("^(idp|non_idp)_(NG[0-9]{3})[0-9]{3}$", "\\2", sid)
  states$adm1_name[match(pc, states$adm1_pcode)]
}

# ---- household key: one row per Round 1 submission ---------------------------
stopifnot(nrow(rs) == 28046, !anyDuplicated(rs$submission_uuid), setequal(rs$submission_uuid, mem_uuid))
w <- w %>% mutate(weight_num = as.numeric(weight))
stopifnot(nrow(w) == 24855, nrow(uw) == 592, !anyDuplicated(c(w$submission_uuid, uw$submission_uuid)))

key <- rs %>%
  transmute(
    uuid = submission_uuid,
    deleted = deletion_status %in% c("confirmed", "contested"),
    completed = interview_outcome == "completed",
    matched = !blank(matched_survey_id),
    r1_strata_id = ifelse(blank(matched_strata_id), NA, matched_strata_id),
    r1_cluster_id = ifelse(blank(matched_cluster_id), NA, matched_cluster_id),
    r1_pop_type = case_when(grepl("^non_idp_", r1_strata_id) ~ "non_idp", grepl("^idp_", r1_strata_id) ~ "idp", TRUE ~ NA_character_),
    admin1 = admin1,
    deletion_reason = ifelse(deleted, flagged_deletion_reason, NA)
  ) %>%
  mutate(
    r1_status = case_when(deleted ~ "removed (settled deletion)",
                          !completed ~ "not completed",
                          !matched ~ "not matched to a sampled point",
                          TRUE ~ "achieved"),
    r1_state = coalesce(state_of_stratum(r1_strata_id), admin1),
    r1_region = states$region[match(r1_state, states$adm1_name)],
    r1_in_analysis_coverage = r1_state %in% covered_states
  )

stopifnot(sum(key$r1_status == "achieved") == 25447)
stopifnot(setequal(c(w$submission_uuid, uw$submission_uuid), key$uuid[key$r1_status == "achieved"]))
chk <- w %>% inner_join(key %>% select(uuid, r1_strata_id), by = c("submission_uuid" = "uuid"))
stopifnot(nrow(chk) == nrow(w), all(chk$strata_id == chk$r1_strata_id))
stopifnot(!any(is.na(key$r1_region)))

disc <- key %>% filter(!is.na(r1_strata_id), r1_state != admin1)
cat(sprintf("Submissions whose reported state differs from their sampled stratum's state: %d (coverage follows the stratum)\n", nrow(disc)))
if (nrow(disc) > 0) print(count(disc, admin1, r1_state, r1_in_analysis_coverage))

key <- key %>%
  left_join(w %>% select(submission_uuid, weight_num), by = c("uuid" = "submission_uuid")) %>%
  left_join(uw %>% select(submission_uuid, unweighted_reason = reason), by = c("uuid" = "submission_uuid")) %>%
  left_join(r1s %>% select(strata_id, r1_stratum_label = `Round 1 label`), by = c("r1_strata_id" = "strata_id")) %>%
  mutate(
    r1_weight = ifelse(r1_in_analysis_coverage & r1_status == "achieved", weight_num, NA_real_),
    r1_weight_note = case_when(
      !r1_in_analysis_coverage ~ "outside Round 1 analysis coverage (Kebbi or North-Central) - no weight",
      r1_status != "achieved" ~ paste0(r1_status, " - no weight"),
      !is.na(weight_num) ~ "weighted",
      !is.na(unweighted_reason) ~ paste0("achieved, not weighted: ", unweighted_reason),
      TRUE ~ NA_character_)
  )
stopifnot(!any(is.na(key$r1_weight_note)))

key_out <- key %>%
  transmute(uuid, r1_in_analysis_coverage, r1_state, r1_region, r1_status, deletion_reason,
            r1_strata_id, r1_cluster_id, r1_pop_type, r1_stratum_label,
            r1_weight = ifelse(is.na(r1_weight), "", format(r1_weight, digits = 15, scientific = FALSE, trim = TRUE)),
            r1_weight_note)

# ---- calibration holds in every covered stratum ------------------------------
bs_cov <- bs %>% filter(State %in% covered_states)
cal <- w %>% filter(state_of_stratum(strata_id) %in% covered_states) %>%
  group_by(strata_id) %>% summarise(n = n(), sum_w = sum(weight_num), .groups = "drop") %>%
  inner_join(bs_cov %>% transmute(strata_id, n_bs = as.integer(n), N_acc = as.numeric(N_acc)), by = "strata_id")
stopifnot(nrow(cal) == nrow(bs_cov), all(cal$n == cal$n_bs), all(abs(cal$sum_w - cal$N_acc) <= 0.06))
cat(sprintf("Calibration: %d covered strata, weights sum to accessible households in every one.\n\n", nrow(cal)))

# ---- write the small files ----------------------------------------------------
for (d in c("00_methodology", "01_weights", "02_dataset", "03_representativity", "04_scripts", "reference_all_states"))
  dir.create(file.path(PKG, d), recursive = TRUE, showWarnings = FALSE)

write_csv(key_out, file.path(PKG, "01_weights/R1_household_status_all_28046.csv"), na = "")
w_cov <- w %>% filter(state_of_stratum(strata_id) %in% covered_states) %>%
  left_join(bs %>% select(strata_id, State, LGA), by = "strata_id") %>%
  relocate(State, LGA, .after = submission_uuid) %>% select(-weight_num)
write_csv(w_cov, file.path(PKG, "01_weights/R1_weights_by_interview_NE_NW.csv"), na = "")
write_csv(bs_cov, file.path(PKG, "01_weights/R1_weights_by_stratum_NE_NW.csv"), na = "")
uw_cov <- uw %>% filter(state_of_stratum(strata_id) %in% covered_states)
write_csv(uw_cov, file.path(PKG, "01_weights/R1_unweighted_interviews_NE_NW.csv"), na = "")
# cluster table (added 3 Oct at the data officer's request): one row per weighting unit with every input of its
# design weight - written by the final weights script itself, so it cannot drift from the weights
ct <- rd(file.path(WDIR, "ROUND1_CLUSTER_TABLE_2026-10-02.csv"))
ct_cov <- ct %>% filter(State %in% covered_states)
stopifnot(sum(as.integer(ct_cov$interviews_weighted)) == nrow(w_cov),
          setequal(paste(w_cov$strata_id, w_cov$weighting_unit), paste(ct_cov$strata_id, ct_cov$unit_id)))
write_csv(ct_cov, file.path(PKG, "01_weights/R1_cluster_table_NE_NW.csv"), na = "")

write_csv(r1s %>% filter(State %in% covered_states), file.path(PKG, "03_representativity/R1_representativity_strata_NE_NW.csv"), na = "")
write_csv(r1l %>% filter(State %in% covered_states), file.path(PKG, "03_representativity/R1_representativity_lga_NE_NW.csv"), na = "")
write_csv(r1t %>% filter(State %in% covered_states), file.path(PKG, "03_representativity/R1_representativity_state_NE_NW.csv"), na = "")

for (f in list.files(WDIR, full.names = TRUE)) file.copy(f, file.path(PKG, "reference_all_states", basename(f)), overwrite = TRUE, copy.date = TRUE)
for (f in list.files(RDIR, full.names = TRUE)) file.copy(f, file.path(PKG, "reference_all_states", basename(f)), overwrite = TRUE, copy.date = TRUE)
file.copy(GUIDE, file.path(PKG, "00_methodology", basename(GUIDE)), overwrite = TRUE, copy.date = TRUE)
this_script <- file.path(S1, "resampling/scripts/one_off_analyses/build_round1_weighting_package_2026-10-02.R")
file.copy(this_script, file.path(PKG, "04_scripts", basename(this_script)), overwrite = TRUE)

# ---- summary for the README ----------------------------------------------------
cov <- key %>% filter(r1_in_analysis_coverage)
cat(sprintf("Coverage: %d submissions | achieved %d | removed %d | weighted %d | achieved but unweighted %d\n",
            nrow(cov), sum(cov$r1_status == "achieved"), sum(cov$r1_status != "achieved"),
            sum(!is.na(cov$r1_weight)), sum(cov$r1_status == "achieved" & is.na(cov$r1_weight))))
print(count(cov %>% filter(r1_status == "achieved", is.na(r1_weight)), r1_weight_note))
cat("\nBy state (coverage):\n")
print(cov %>% group_by(r1_state) %>%
        summarise(submissions = n(), achieved = sum(r1_status == "achieved"), weighted = sum(!is.na(r1_weight)),
                  sum_weight = round(sum(r1_weight, na.rm = TRUE)), .groups = "drop") %>% as.data.frame())
cat("\nStrata labels (coverage):\n")
print(table((r1s %>% filter(State %in% covered_states))$`Round 1 label`))
cat("\nLGA labels (coverage):\n")
print(table((r1l %>% filter(State %in% covered_states))$`Round 1 label`))
cat("\nState labels (coverage, all scopes):\n")
print(r1t %>% filter(State %in% covered_states) %>% select(State, Scope, `Round 1 label`, `MoE Round 1 (deff=1) %`) %>% as.data.frame())
cat("\nOut of coverage:", sum(!key$r1_in_analysis_coverage), "submissions,",
    sum(!key$r1_in_analysis_coverage & key$r1_status == "achieved"), "achieved\n")

# ---- the weighted dataset (largest step, last) ---------------------------------
if (!SKIP_DATASET) {
  source(file.path(PKG, "04_scripts/attach_round1_weights.R"))
  attach_round1_weights(EXPORT, file.path(PKG, "01_weights/R1_household_status_all_28046.csv"),
                        file.path(PKG, "02_dataset/NGA2605_MSNA_anonymised_2026-10-01_R1_NE_NW_weighted.xlsx"))
}

# ---- checksums --------------------------------------------------------------------
files <- setdiff(list.files(PKG, recursive = TRUE), "MD5SUMS.txt")
con <- file(file.path(PKG, "MD5SUMS.txt"), open = "wb")   # binary: LF line endings, so `md5sum -c` works too
writeLines(sprintf("%s  %s", unname(tools::md5sum(file.path(PKG, files))), files), con, sep = "\n")
close(con)
cat("\nDone:", PKG, "\n")
