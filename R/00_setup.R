# -----------------------------------------------------------------------------
# 00_setup.R
# Packages, paths, plotting theme and small helpers used by all scripts.
# -----------------------------------------------------------------------------

options(stringsAsFactors = FALSE, scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(lubridate)
  library(forcats)
  library(scales)
  library(gtsummary)
  library(gt)
  library(ggridges)
  library(patchwork)
  library(knitr)
  library(tibble)
})

# Paths -----------------------------------------------------------------------
paths <- list(
  raw = "data/raw",
  derived = "data/derived",
  tables = "outputs/tables",
  figures = "outputs/figures",
  report = "report"
)
invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))

# Country order and palette ---------------------------------------------------
country_levels <- c("United States", "Germany", "France", "England")
country_pal <- c(
  "United States" = "#1F3B57",
  "Germany"       = "#B5523B",
  "France"        = "#3E6FA3",
  "England"       = "#6E8B4A"
)
country_pal_short <- country_pal[c("Germany", "France", "England")]

# Plot theme ------------------------------------------------------------------
theme_set(
  theme_minimal(base_size = 11) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      axis.title = element_text(colour = "grey20"),
      axis.text = element_text(colour = "grey35"),
      plot.title = element_text(face = "bold", size = 12),
      plot.subtitle = element_text(colour = "grey40", size = 9.5),
      plot.caption = element_text(colour = "grey45", size = 8, hjust = 0),
      legend.position = "bottom",
      legend.title = element_blank(),
      strip.text = element_text(face = "bold"),
      plot.margin = margin(10, 14, 10, 10)
    )
)

# Helpers ---------------------------------------------------------------------
save_plot <- function(plot, filename, width = 7.2, height = 4.8, dpi = 300) {
  ggsave(file.path(paths$figures, filename), plot = plot,
         width = width, height = height, dpi = dpi, bg = "white")
}

save_table <- function(x, filename) {
  readr::write_csv(x, file.path(paths$tables, filename), na = "")
}

save_kable <- function(x, filename, caption = NULL, digits = 1) {
  txt <- knitr::kable(x, format = "pipe", digits = digits, caption = caption,
                      booktabs = TRUE)
  writeLines(as.character(txt), file.path(paths$tables, filename))
}

save_gt <- function(gt_object, filename) {
  gt::gtsave(gt_object, file.path(paths$tables, filename))
}

fmt_num <- function(x, digits = 0) {
  formatC(x, format = "f", digits = digits, big.mark = ",")
}

fmt_usd <- function(x, digits = 0) {
  paste0("$", fmt_num(x, digits))
}

fmt_eur <- function(x, digits = 0) {
  paste0("\u20ac", fmt_num(x, digits))
}

fmt_gbp <- function(x, digits = 0) {
  paste0("\u00a3", fmt_num(x, digits))
}

# Bootstrap CI for Spearman rho ----------------------------------------------
boot_spearman <- function(x, y, R = 2000, seed = 20261114) {
  ok <- complete.cases(x, y)
  x <- x[ok]; y <- y[ok]
  if (length(x) < 4 || length(unique(x)) < 2 || length(unique(y)) < 2) {
    return(c(estimate = NA_real_, conf.low = NA_real_, conf.high = NA_real_, p.value = NA_real_))
  }
  set.seed(seed)
  est <- suppressWarnings(cor(x, y, method = "spearman"))
  bs <- replicate(R, {
    i <- sample(seq_along(x), replace = TRUE)
    if (length(unique(x[i])) < 2 || length(unique(y[i])) < 2) return(NA_real_)
    suppressWarnings(cor(x[i], y[i], method = "spearman"))
  })
  ci <- quantile(bs, c(0.025, 0.975), na.rm = TRUE)
  p <- tryCatch(suppressWarnings(cor.test(x, y, method = "spearman")$p.value),
                error = function(e) NA_real_)
  c(estimate = est, conf.low = unname(ci[1]), conf.high = unname(ci[2]), p.value = p)
}

# Median and IQR summary ------------------------------------------------------
summarise_cont <- function(x, digits = 0) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return(tibble(n = 0, median = NA_real_, q1 = NA_real_, q3 = NA_real_,
                  min = NA_real_, max = NA_real_))
  }
  q <- quantile(x, c(0.25, 0.75), names = FALSE)
  tibble(n = length(x), median = median(x), q1 = q[1], q3 = q[2],
         min = min(x), max = max(x))
}

cat("Setup complete. R", as.character(getRversion()), "\n")
