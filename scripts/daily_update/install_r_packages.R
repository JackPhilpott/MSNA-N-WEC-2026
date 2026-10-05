# R packages for 1_sampling's daily update (frame refresh, stamp, mirror syncs).
# R 4.3 or newer (tested on 4.6.0). Run once: Rscript install_r_packages.R
# tools and utils ship with R. The validity gate (validity_checks/) and the dashboard
# (2_monitoring/) have their own package lists - see their READMEs.
pkgs <- c("dplyr", "readr")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
for (p in pkgs) cat(sprintf("%-6s %s\n", p, as.character(utils::packageVersion(p))))
