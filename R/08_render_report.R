# -----------------------------------------------------------------------------
# 08_render_report.R
# Knit the report to Markdown, resolve citations from references.bib, convert
# to HTML with a print stylesheet, and print to PDF with headless Edge.
#
# Inputs : report/atmp_report.Rmd, references.bib, outputs/*
# Outputs: report/atmp_report.md, report/atmp_report.html, report/atmp_report.pdf
# -----------------------------------------------------------------------------

source("R/00_setup.R")

report_dir <- normalizePath(paths$report, mustWork = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

# --- Minimal BibTeX reader ---------------------------------------------------
parse_bib <- function(file) {
  txt <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  entries <- strsplit(txt, "@", fixed = TRUE)[[1]][-1]
  keys <- sub("^[A-Za-z]+\\{([^,]+),.*$", "\\1", entries)
  fields <- c("author", "shortauthor", "title", "year", "journal",
              "howpublished", "volume", "number", "pages", "doi", "url", "note")
  vals <- lapply(entries, function(e) {
    out <- lapply(fields, function(f) {
      pat <- paste0("(?m)^[[:space:]]*", f, "[[:space:]]*=[[:space:]]*\\{")
      pos <- regexpr(pat, e, perl = TRUE)
      if (pos < 0) return(NA_character_)
      start <- pos + attr(pos, "match.length")
      rest <- substr(e, start, nchar(e))
      sub("(?s)\\}.*$", "", rest, perl = TRUE)
    })
    names(out) <- fields
    as.data.frame(out, stringsAsFactors = FALSE)
  })
  out <- dplyr::bind_rows(vals)
  out$key <- keys
  out
}

bib <- parse_bib("references.bib")
bib <- bib %>% mutate(across(everything(), ~ ifelse(is.na(.x), "", .x)))

format_reference <- function(row) {
  clean <- function(x) sub("\\.$", "", x)
  authors <- clean(row$author)
  title <- clean(row$title)
  if (nzchar(row$journal)) {
    paste0(authors, ". ", title, ". ", clean(row$journal), ". ",
           row$year, ";", row$volume,
           ifelse(nzchar(row$number), paste0("(", row$number, ")"), ""),
           ":", row$pages, ". ",
           ifelse(nzchar(row$doi), paste0("doi:", row$doi), ""))
  } else {
    paste0(authors, ". ", title, ". ",
           ifelse(nzchar(row$howpublished), paste0(clean(row$howpublished), ". "), ""),
           row$year, ". ",
           ifelse(nzchar(row$url), row$url, ""))
  }
}

cite_key <- function(key) {
  row <- bib[bib$key == key, ]
  if (nrow(row) == 0) return(key)
  paste0(row$shortauthor, ", ", row$year)
}

# --- Knit --------------------------------------------------------------------
knitr::opts_knit$set(root.dir = normalizePath("."))
knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE)

md_path <- file.path(report_dir, "atmp_report.md")
knitr::knit(file.path(report_dir, "atmp_report.Rmd"), output = md_path,
            quiet = TRUE, encoding = "UTF-8")

# --- Resolve citations -------------------------------------------------------
md <- paste(readLines(md_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

citation_matches <- regmatches(md, gregexpr("\\[@[^\\]]+\\]", md, perl = TRUE))[[1]]
citation_matches <- unique(citation_matches)

ordered_keys <- character(0)
for (cit in citation_matches) {
  keys <- regmatches(cit, gregexpr("@([A-Za-z0-9_]+)", cit, perl = TRUE))[[1]]
  keys <- sub("^@", "", keys)
  ordered_keys <- c(ordered_keys, setdiff(keys, ordered_keys))
}

for (cit in citation_matches) {
  keys <- regmatches(cit, gregexpr("@([A-Za-z0-9_]+)", cit, perl = TRUE))[[1]]
  keys <- sub("^@", "", keys)
  replacement <- paste0("(", paste(vapply(keys, cite_key, character(1)), collapse = "; "), ")")
  md <- gsub(cit, replacement, md, fixed = TRUE)
}

# Number the references in order of first citation.
ref_lines <- vapply(ordered_keys, function(k) {
  row <- bib[bib$key == k, ]
  if (nrow(row) == 0) return(paste0("- ", k))
  paste0("- ", format_reference(row))
}, character(1))

ref_block <- paste(c(paste0(seq_along(ref_lines), ". ",
                            sub("^- ", "", ref_lines))), collapse = "\n")
md <- sub("::: \\{#refs\\}\n:::", ref_block, md)

writeLines(md, md_path, useBytes = TRUE)

md <- paste(readLines(md_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
md <- gsub("Table: Table ", "Table ", md, fixed = TRUE)
writeLines(md, md_path, useBytes = TRUE)

# --- Markdown to HTML --------------------------------------------------------
html_path <- file.path(report_dir, "atmp_report.html")
markdown::markdownToHTML(
  md_path, html_path,
  options = c("standalone", "smart", "number_sections"),
  stylesheet = "report.css",
  encoding = "UTF-8"
)

# --- HTML to PDF via headless Edge ------------------------------------------
edge <- "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
pdf_path <- file.path(report_dir, "atmp_report.pdf")

if (file.exists(edge)) {
  html_url <- paste0("file:///", gsub("\\\\", "/", normalizePath(html_path)))
  cmd <- paste(
    shQuote(edge),
    "--headless --disable-gpu --no-pdf-header-footer",
    "--run-all-compositor-stages-before-draw --virtual-time-budget=15000",
    paste0("--print-to-pdf=", shQuote(pdf_path)),
    shQuote(html_url)
  )
  status <- system(cmd, intern = FALSE)
  if (!file.exists(pdf_path)) {
    warning("Edge did not produce a PDF (exit status ", status, ").")
  }
} else {
  warning("Edge not found; HTML report generated without PDF.")
}

cat("Report written to:\n")
cat(" -", md_path, "\n")
cat(" -", html_path, "\n")
if (file.exists(pdf_path)) cat(" -", pdf_path, "\n")
cat("Citations resolved:", length(ordered_keys), "references.\n")
