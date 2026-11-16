# -----------------------------------------------------------------------------
# 02_price_adjustment.R
# Strict, reversible price transformation:
#   1. CPI deflation in local currency to the reference year (2024 = base).
#   2. PPP conversion to constant-year international USD (LCU / PPP).
#   3. Cross-country price index relative to the United States (US = 100).
#
# The sequence matters: deflating after PPP conversion would mix inflation
# rates across currencies. Both steps are retained as intermediate columns so
# the transformation can be reversed and audited.
#
# Inputs : data/derived/analysis.csv, data/raw/price_factors.csv
# Outputs: data/derived/prices_adjusted.csv, data/derived/price_index.csv,
#          outputs/tables/price_adjustment_summary.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

analysis <- readr::read_csv(file.path(paths$derived, "analysis.csv"),
                            show_col_types = FALSE)
factors <- readr::read_csv(file.path(paths$raw, "price_factors.csv"),
                           show_col_types = FALSE)

ref_year <- 2024
alt_year <- 2020

# --- Reference-year factors --------------------------------------------------
ref_factors <- factors %>%
  filter(year == ref_year) %>%
  select(country,
         cpi_ref = cpi_index_2010,
         ppp_ref = ppp_gdp_lcu_per_intusd)

alt_factors <- factors %>%
  filter(year == alt_year) %>%
  select(country,
         cpi_alt = cpi_index_2010,
         ppp_alt = ppp_gdp_lcu_per_intusd)

price_year_factors <- factors %>%
  select(country, price_year = year,
         cpi_price_year = cpi_index_2010,
         ppp_price_year = ppp_gdp_lcu_per_intusd)

# --- Transform ---------------------------------------------------------------
adjusted <- analysis %>%
  left_join(ref_factors, by = "country") %>%
  left_join(alt_factors, by = "country") %>%
  left_join(price_year_factors, by = c("country", "price_year")) %>%
  mutate(
    # Step 1: local-currency deflation to the reference year.
    price_real_lcu_2024 = list_price_lcu * cpi_ref / cpi_price_year,
    # Step 2: PPP conversion. PA.NUS.PPP is LCU per international dollar.
    price_constant_usd_2024 = price_real_lcu_2024 / ppp_ref,
    # Alternative base year retained for sensitivity analysis 9.
    price_real_lcu_2020 = list_price_lcu * cpi_alt / cpi_price_year,
    price_constant_usd_2020 = price_real_lcu_2020 / ppp_alt
  )

# --- US reference price per product -----------------------------------------
us_ref <- adjusted %>%
  filter(country == "United States", !is.na(price_constant_usd_2024)) %>%
  select(product_id, us_price_constant_usd = price_constant_usd_2024,
         us_price_constant_usd_2020 = price_constant_usd_2020)

us_ref_2020 <- adjusted %>%
  filter(country == "United States", !is.na(price_constant_usd_2020)) %>%
  select(product_id, us_price_2020 = price_constant_usd_2020)

adjusted <- adjusted %>%
  left_join(us_ref, by = "product_id") %>%
  left_join(us_ref_2020, by = "product_id") %>%
  mutate(
    price_index_us100 = if_else(
      !is.na(price_constant_usd_2024) & !is.na(us_price_constant_usd),
      100 * price_constant_usd_2024 / us_price_constant_usd,
      NA_real_
    ),
    price_index_us100_2020 = if_else(
      !is.na(price_constant_usd_2020) & !is.na(us_price_2020),
      100 * price_constant_usd_2020 / us_price_2020,
      NA_real_
    )
  )

# --- Index dataset (priced pairs with a US comparator, non-US) ---------------
price_index <- adjusted %>%
  filter(country != "United States", !is.na(price_index_us100)) %>%
  select(product_id, brand, modality, country, price_year,
         list_price_lcu, currency, price_basis,
         price_real_lcu_2024, ppp_ref, price_constant_usd_2024,
         us_price_constant_usd, price_index_us100,
         price_index_us100_2020, verification)

# --- Adjustment audit table --------------------------------------------------
audit <- adjusted %>%
  filter(!is.na(list_price_lcu)) %>%
  transmute(
    product_id, brand, country,
    price_year,
    list_price_lcu, currency,
    cpi_price_year, cpi_ref,
    ppp_ref,
    price_real_lcu_2024,
    price_constant_usd_2024,
    us_price_constant_usd,
    price_index_us100,
    verification
  )

summary_tbl <- price_index %>%
  group_by(country) %>%
  summarise(
    n = n(),
    median_index = median(price_index_us100),
    q1_index = quantile(price_index_us100, 0.25),
    q3_index = quantile(price_index_us100, 0.75),
    min_index = min(price_index_us100),
    max_index = max(price_index_us100),
    .groups = "drop"
  )

# --- Checks ------------------------------------------------------------------
stopifnot(
  all(adjusted$price_constant_usd_2024 >= 0, na.rm = TRUE),
  all(adjusted$price_index_us100 > 0, na.rm = TRUE),
  nrow(price_index) == sum(!is.na(adjusted$price_index_us100) &
                             adjusted$country != "United States")
)

# US rows must equal 100 wherever both are available.
us_check <- adjusted %>%
  filter(country == "United States", !is.na(price_index_us100)) %>%
  pull(price_index_us100)
stopifnot(all(abs(us_check - 100) < 1e-8))

readr::write_csv(adjusted, file.path(paths$derived, "prices_adjusted.csv"), na = "")
readr::write_csv(price_index, file.path(paths$derived, "price_index.csv"), na = "")
readr::write_csv(summary_tbl,
                 file.path(paths$tables, "price_adjustment_summary.csv"), na = "")

cat("Priced rows:", sum(!is.na(adjusted$list_price_lcu)), "\n")
cat("Index observations (non-US with US comparator):", nrow(price_index), "\n")
cat("CPI/PPP missing for priced rows:",
    sum(is.na(adjusted$price_constant_usd_2024) & !is.na(adjusted$list_price_lcu)),
    "\n")
print(summary_tbl, n = Inf)
