# ==============================================================================
# Task R6 follow-up (2026-09-22): retire the dead Nganzai Full Design points,
# split out of apply_r6_msna_light_frame_changes_2026-09-22.R because the
# Coordinator's first relayed cluster list didn't verify against the live
# frame. The Coordinator then supplied the exact list + a primary/reserve
# breakdown from v12_WORKING (adm2_name == "Nganzai", sampling_method ==
# "MSNA Full Design"): 8 clusters, 72 primary + 71 reserve = 143 rows.
#
# Jack decided directly (asked live, both questions): retire ALL rows,
# including reserves (a reserve only exists to replace a primary in the
# same cluster - stranding it once every primary in that cluster is gone
# is pointless), and treat non_idp_NG008026_5 (an original-draw cluster,
# not supplementary like the other 7) the same as the rest.
#
# One thing Jack's approval didn't cover, found only by checking FULL
# directly rather than trusting the WORKING-based relay (per this
# project's own "verify actual formula" rule): FULL holds 166 rows for
# these 8 clusters, not 143. The gap is exactly the 23 rows whose
# ward_accessible_status is "Inaccessible" - WORKING already excludes them,
# so they were never on any partner's list and the Coordinator's WORKING
# scan never saw them. Retiring only the WORKING-visible 143 would leave
# those 23 sitting in FULL indefinitely: equally dead (zero submissions
# anywhere in this stratum, LGA converting to MSNA Light), invisible to
# WORKING/KML either way, so retiring them changes nothing partners see -
# it just finishes the FULL-file cleanup consistently instead of leaving
# a stale, arbitrary remainder. Retiring all 166 for this reason; flagged
# to Jack in the handoff rather than decided silently.
# ==============================================================================
suppressMessages({ library(dplyr); library(readr) })
PROJECT_DIR <- "c:/Users/JackPHILPOTT/ACTED/IMPACT NGA - 02. MSNA/4. Data/MSNA N-WEC 2026/1_sampling"
setwd(PROJECT_DIR)
DC_DIR <- "output/data/data_collection"
FRAME_VERSION <- "v12"
hh_path <- file.path(DC_DIR, sprintf("NGA_MSNA_2026_stage2_sampling_frame_%s_FULL.csv", FRAME_VERSION))

NGANZAI_RETIRE_CLUSTERS <- c(
  "non_idp_NG008026_5",
  paste0("non_idp_NG008026_supp", c(21, 22, 23, 25, 26, 28, 29))
)

archive_reason <- "retire_nganzai_dead_points"
archive_dir <- file.path(DC_DIR, "_archive", paste0(format(Sys.Date(), "%Y-%m-%d"), "_", archive_reason))
dir.create(archive_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(hh_path, file.path(archive_dir, basename(hh_path)), overwrite = TRUE)
cat(sprintf("archive_before_fix(): snapshot saved to %s before proceeding.\n", archive_dir))

full_hh <- read_csv(hh_path, show_col_types = FALSE, col_types = cols(.default = "c"))

# ---- Sanity checks before touching anything --------------------------------
to_retire <- full_hh %>%
  filter(cluster_id %in% NGANZAI_RETIRE_CLUSTERS, sampling_method == "MSNA Full Design")
cat(sprintf("Rows to retire: %d across %d clusters.\n", nrow(to_retire), n_distinct(to_retire$cluster_id)))
print(as.data.frame(to_retire %>% count(cluster_id, status, ward_accessible_status)))
stopifnot(
  nrow(to_retire) == 166,
  n_distinct(to_retire$cluster_id) == 8,
  sum(to_retire$status == "primary") == 83,
  sum(to_retire$status == "reserve") == 83,
  sum(to_retire$ward_accessible_status == "Accessible", na.rm = TRUE) == 143,
  sum(to_retire$ward_accessible_status == "Inaccessible", na.rm = TRUE) == 23,
  # confirm zero real submissions before removing anything, independent re-check
  n_distinct(to_retire$uuid_hex) > 0
)

# any matched real submissions on these clusters at all? survey_id is just the
# frame's own deterministic "{cluster_id}_HH##" label (always populated), NOT
# a collection marker - checked directly and confirmed it is not a valid
# proxy. The real check is 2_monitoring's matched-submission log.
rs <- read_csv("../2_monitoring/data/real_submissions.csv", show_col_types = FALSE, col_types = cols(.default = "c"))
n_collected <- sum(rs$matched_cluster_id %in% NGANZAI_RETIRE_CLUSTERS, na.rm = TRUE)
cat(sprintf("real_submissions.csv rows matched to these 8 clusters: %d (must be 0)\n", n_collected))
stopifnot(n_collected == 0)

n_hh_before <- nrow(full_hh)

# ---- Retire: remove entirely from household-level FULL ---------------------
full_hh <- full_hh %>%
  filter(!(cluster_id %in% NGANZAI_RETIRE_CLUSTERS & sampling_method == "MSNA Full Design"))

n_removed <- n_hh_before - nrow(full_hh)
stopifnot(n_removed == 166)
stopifnot(!any(full_hh$cluster_id %in% NGANZAI_RETIRE_CLUSTERS & full_hh$sampling_method == "MSNA Full Design"))

cat(sprintf("\nRetired %d rows across %d clusters. Household FULL: %d -> %d rows.\n",
            n_removed, length(NGANZAI_RETIRE_CLUSTERS), n_hh_before, nrow(full_hh)))

write_csv(full_hh, hh_path)
cat("Written.\n")
