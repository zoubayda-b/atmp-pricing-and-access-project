# -----------------------------------------------------------------------------
# run_all.R
# Run the full analysis pipeline from a clean state.
#
# Usage (from the project root):
#   source("R/run_all.R")
#   # or
#   Rscript R/run_all.R
# -----------------------------------------------------------------------------

scripts <- c(
  "R/00_build_extraction.R",
  "R/01_import_validate.R",
  "R/02_price_adjustment.R",
  "R/03_descriptive.R",
  "R/04_price_index.R",
  "R/05_launch_delay.R",
  "R/06_correlations.R",
  "R/07_sensitivity.R",
  "R/08_render_report.R"
)

for (s in scripts) {
  message("\n=== ", s, " ===")
  status <- system2("Rscript", s)
  if (!identical(status, 0L)) {
    stop("Pipeline stopped at ", s, " (exit status ", status, ").", call. = FALSE)
  }
}

message("\nPipeline complete. See report/atmp_report.pdf and outputs/.")
