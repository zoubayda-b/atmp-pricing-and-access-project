# -----------------------------------------------------------------------------
# 01_import_validate.R
# Import the hand-extracted dataset, apply type coercions, validate structure,
# and derive the primary launch-delay outcome.
#
# Inputs : data/raw/atmp_extraction.csv, data/raw/price_factors.csv
# Outputs: data/derived/analysis.csv, outputs/tables/validation_log.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

# --- Import ------------------------------------------------------------------
read_raw <- function(file) {
  readr::read_csv(file, na = c("", "NA"), show_col_types = FALSE,
                  col_types = readr::cols(.default = readr::col_character()))
}

extraction <- read_raw(file.path(paths$raw, "atmp_extraction.csv"))
factors <- read_raw(file.path(paths$raw, "price_factors.csv"))

# Numeric / logical / date coercion (everything was read as character so that
# blanks become explicit NA rather than being silently dropped).
extraction <- extraction %>%
  mutate(
    across(c(hta_rating_ordinal, list_price_lcu, price_year), as.numeric),
    approved = case_when(approved == "TRUE" ~ TRUE,
                         approved == "FALSE" ~ FALSE,
                         TRUE ~ NA),
    price_confidential = case_when(price_confidential == "TRUE" ~ TRUE,
                                   price_confidential == "FALSE" ~ FALSE,
                                   TRUE ~ NA),
    across(c(regulatory_date, hta_date, reimbursement_date, first_access_date),
           as.Date)
  )

factors <- factors %>%
  mutate(across(c(year, cpi_index_2010, ppp_gdp_lcu_per_intusd,
                  ppp_private_consumption_lcu_per_intusd), as.numeric))

# --- Structure checks --------------------------------------------------------
checks <- list()

add_check <- function(check, expected, observed, pass, note = "") {
  checks[[length(checks) + 1]] <<- tibble(
    check = check, expected = expected, observed = as.character(observed),
    pass = pass, note = note
  )
}

add_check("Row count", "68", nrow(extraction), nrow(extraction) == 68,
          "17 products x 4 countries")
add_check("Unique product x country pairs", "68",
          sum(!duplicated(paste(extraction$product_id, extraction$country))),
          !any(duplicated(paste(extraction$product_id, extraction$country))))
add_check("Products", "17", length(unique(extraction$product_id)),
          length(unique(extraction$product_id)) == 17)
add_check("Countries", "4", length(unique(extraction$country)),
          length(unique(extraction$country)) == 4)
add_check("Balanced panel", "4 rows per product",
          paste(range(table(extraction$product_id)), collapse = "-"),
          all(table(extraction$product_id) == 4))

# Currency must match country.
currency_ok <- extraction %>%
  filter(!is.na(list_price_lcu)) %>%
  mutate(ok = (country == "United States" & currency == "USD") |
                (country %in% c("Germany", "France") & currency == "EUR") |
                (country == "England" & currency == "GBP")) %>%
  pull(ok) %>%
  all()
add_check("Currency consistent with country", "all rows", currency_ok, currency_ok)

# Every price must have a price year inside the study window.
price_year_ok <- extraction %>%
  filter(!is.na(list_price_lcu)) %>%
  mutate(ok = !is.na(price_year) & price_year >= 2015 & price_year <= 2024) %>%
  pull(ok) %>%
  all()
add_check("Price year present and in 2015-2024 for every priced row",
          "all rows", price_year_ok, price_year_ok)

# Confidential prices must not carry a value.
conf_ok <- !any(extraction$price_confidential & !is.na(extraction$list_price_lcu))
add_check("Confidential prices coded NA", "no value", conf_ok, conf_ok)

# Approval flag must be FALSE/NA where the product was never launched.
add_check("No price where approved is FALSE", "0 priced rows",
          sum(extraction$approved %in% FALSE & !is.na(extraction$list_price_lcu)),
          sum(extraction$approved %in% FALSE & !is.na(extraction$list_price_lcu)) == 0)

# Factor coverage: every priced row must be able to join CPI and PPP.
price_rows <- extraction %>% filter(!is.na(list_price_lcu))
factor_keys <- factors %>%
  select(country, year) %>%
  distinct() %>%
  mutate(has_factor = TRUE)
join_test <- price_rows %>%
  left_join(factor_keys, by = c("country" = "country", "price_year" = "year")) %>%
  mutate(has_factor = !is.na(has_factor))
add_check("CPI/PPP factor available for every priced row", "all rows",
          sum(join_test$has_factor), all(join_test$has_factor))

# --- Derived outcomes --------------------------------------------------------
analysis <- extraction %>%
  mutate(
    delay_regulatory_to_access =
      as.numeric(first_access_date - regulatory_date),
    delay_negative = !is.na(delay_regulatory_to_access) &
      delay_regulatory_to_access < 0,
    delay_years = delay_regulatory_to_access / 365.25,
    has_price = !is.na(list_price_lcu),
    has_delay = !is.na(delay_regulatory_to_access),
    us_only = country == "United States",
    # The US delay is zero by construction and must never enter the
    # cross-country comparison.
    delay_analysable = has_delay & !us_only
  )

# --- Validation log ----------------------------------------------------------
validation_log <- bind_rows(checks)

# Missingness summary, appended to the same log file.
missingness <- analysis %>%
  group_by(country) %>%
  summarise(
    n = n(),
    price_missing = sum(is.na(list_price_lcu)),
    price_confidential = sum(price_confidential %in% TRUE),
    first_access_missing = sum(is.na(first_access_date)),
    delay_missing = sum(is.na(delay_regulatory_to_access)),
    hta_rating_missing = sum(is.na(hta_rating_ordinal)),
    .groups = "drop"
  ) %>%
  mutate(check = paste0("Missingness: ", country),
         expected = "documented",
         observed = paste0("price NA ", price_missing, "/", n,
                           "; confidential ", price_confidential,
                           "; access NA ", first_access_missing,
                           "; delay NA ", delay_missing,
                           "; HTA rating NA ", hta_rating_missing),
         pass = NA,
         note = "Counts of explicitly coded missing values")

validation_log <- bind_rows(
  validation_log,
  missingness %>% select(check, expected, observed, pass, note)
)

readr::write_csv(validation_log, file.path(paths$tables, "validation_log.csv"),
                 na = "")
readr::write_csv(analysis, file.path(paths$derived, "analysis.csv"), na = "")

cat("Validation checks:", sum(validation_log$pass %in% TRUE), "passed,",
    sum(validation_log$pass %in% FALSE), "failed.\n")
cat("Rows:", nrow(analysis), "| priced:", sum(analysis$has_price),
    "| with delay:", sum(analysis$has_delay),
    "| analysable delays (non-US):", sum(analysis$delay_analysable), "\n")
cat("Negative delays:", sum(analysis$delay_negative), "\n")
