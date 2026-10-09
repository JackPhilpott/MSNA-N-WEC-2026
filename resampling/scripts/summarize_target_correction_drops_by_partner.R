# ==============================================================================
# Task 5 (2026-09-13/14) follow-up: per-partner summary of the target-
# correction drop list, for wrapping into the end-of-batch partner emails
# Jack asked for. Read-only - just summarizes resampling/output/target_
# correction_dropped_clusters.csv, doesn't touch anything live.
#
# Usage: Rscript summarize_target_correction_drops_by_partner.R
# ==============================================================================
# Portable paths (9 Oct 2026, #17): find 1_sampling/scripts/shared/msna_paths.R from MSNA_WORKSPACE, this script's
# own location or the working directory, so a sandbox copy never reads or writes the live workspace.
local({
  starts <- c(Sys.getenv("MSNA_WORKSPACE"),
              sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)),
              unlist(lapply(sys.frames(), function(f) f$ofile)), getwd())
  helper <- NA_character_
  for (s in starts[nzchar(starts)]) {
    d <- normalizePath(s, winslash = "/", mustWork = FALSE)
    while (is.na(helper)) {
      h <- file.path(d, "1_sampling", "scripts", "shared", "msna_paths.R")
      if (file.exists(h)) helper <- h
      p <- dirname(d)
      if (identical(p, d)) break
      d <- p
    }
    if (!is.na(helper)) break
  }
  if (is.na(helper)) stop("Cannot find 1_sampling/scripts/shared/msna_paths.R - set MSNA_WORKSPACE.", call. = FALSE)
  assign(".msna_paths_file", helper, envir = globalenv())
  source(helper)
})
PROJECT_DIR <- msna_sampling_dir()
setwd(PROJECT_DIR)
suppressMessages({ library(dplyr); library(readr); library(tidyr) })

drops <- read_csv("resampling/output/target_correction_dropped_clusters.csv", show_col_types = FALSE)
strata <- read_csv(msna_frame_file("strata_FULL"),
                    show_col_types = FALSE, col_types = cols(.default = "c")) %>%
  distinct(strata_id, adm1_name, adm2_name, partners_covering)

detail <- drops %>% left_join(strata, by = "strata_id")

by_partner <- detail %>%
  separate_rows(partners_covering, sep = ",\\s*") %>%
  group_by(partners_covering) %>%
  summarise(
    n_clusters_dropped = n(),
    n_households_dropped = sum(as.integer(target_households)),
    n_already_achieved_in_dropped = sum(as.integer(n_achieved)),
    n_strata_affected = n_distinct(strata_id),
    .groups = "drop"
  ) %>%
  arrange(desc(n_clusters_dropped))

cat("=== By partner ===\n")
print(as.data.frame(by_partner))
write_csv(by_partner, "resampling/output/target_correction_drops_by_partner_summary.csv")

out <- detail %>%
  separate_rows(partners_covering, sep = ",\\s*") %>%
  select(partners_covering, adm1_name, adm2_name, strata_id, cluster_id, target_households, n_achieved) %>%
  arrange(partners_covering, adm1_name, adm2_name, strata_id)
write_csv(out, "resampling/output/target_correction_drops_by_partner_for_emails.csv")

cat(sprintf("\nWrote resampling/output/target_correction_drops_by_partner_summary.csv (per-partner totals) and "))
cat("target_correction_drops_by_partner_for_emails.csv (full per-cluster detail).\n")
cat(sprintf("\nTotals: %d clusters dropped, %d nominal households, %d already-achieved households preserved (stranded credit) across %d partners.\n",
            sum(by_partner$n_clusters_dropped), sum(by_partner$n_households_dropped), sum(by_partner$n_already_achieved_in_dropped), nrow(by_partner)))
