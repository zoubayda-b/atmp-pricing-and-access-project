# -----------------------------------------------------------------------------
# 03_descriptive.R
# Descriptive statistics by country: sample characteristics, price summaries,
# access status, and explicit missingness. Median and IQR are reported because
# means are dominated by extreme one-time therapy prices.
#
# Inputs : data/derived/analysis.csv, data/derived/prices_adjusted.csv
# Outputs: outputs/tables/table1_characteristics.{csv,html}
#          outputs/tables/table2_price_summary.csv
#          outputs/tables/table3_access_status.csv
#          outputs/tables/table4_missingness.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

analysis <- readr::read_csv(file.path(paths$derived, "analysis.csv"),
                            show_col_types = FALSE)
adjusted <- readr::read_csv(file.path(paths$derived, "prices_adjusted.csv"),
                            show_col_types = FALSE)

analysis <- analysis %>%
  mutate(country = factor(country, levels = country_levels))

# --- Table 1: sample characteristics ----------------------------------------
tbl1_data <- analysis %>%
  select(country, modality, approved, has_price, delay_analysable,
         list_price_lcu, delay_regulatory_to_access) %>%
  mutate(
    approved = factor(approved, levels = c(TRUE, FALSE),
                      labels = c("Regulatory approval", "No approval")),
    has_price = factor(has_price, levels = c(TRUE, FALSE),
                       labels = c("List price observed", "List price missing")),
    delay_analysable = factor(delay_analysable, levels = c(TRUE, FALSE),
                              labels = c("Delay analysable", "Delay not analysable"))
  )

tbl1 <- tbl1_data %>%
  tbl_summary(
    by = country,
    label = list(
      modality ~ "ATMP modality",
      approved ~ "Regulatory status",
      has_price ~ "Price availability",
      delay_analysable ~ "Launch-delay availability",
      list_price_lcu ~ "List price, local currency",
      delay_regulatory_to_access ~ "Delay, regulatory approval to access (days)"
    ),
    statistic = list(
      all_continuous() ~ "{median} ({p25}, {p75})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = all_continuous() ~ 0,
    missing = "ifany",
    missing_text = "Missing"
  ) %>%
  add_overall(last = TRUE) %>%
  modify_header(label ~ "**Characteristic**") %>%
  bold_labels()

readr::write_csv(as_tibble(tbl1), file.path(paths$tables, "table1_characteristics.csv"),
                 na = "")
gt::gtsave(as_gt(tbl1), file.path(paths$tables, "table1_characteristics.html"))

# --- Table 2: price summary by country --------------------------------------
price_summary <- adjusted %>%
  filter(!is.na(list_price_lcu)) %>%
  group_by(country) %>%
  summarise(
    n_priced = n(),
    median_local = median(list_price_lcu),
    q1_local = quantile(list_price_lcu, 0.25),
    q3_local = quantile(list_price_lcu, 0.75),
    min_local = min(list_price_lcu),
    max_local = max(list_price_lcu),
    median_usd = median(price_constant_usd_2024),
    q1_usd = quantile(price_constant_usd_2024, 0.25),
    q3_usd = quantile(price_constant_usd_2024, 0.75),
    .groups = "drop"
  ) %>%
  mutate(
    currency = c("USD", "EUR", "EUR", "GBP")[match(country, country_levels)],
    across(c(median_local, q1_local, q3_local, min_local, max_local,
             median_usd, q1_usd, q3_usd), ~ round(.x, 0))
  ) %>%
  arrange(match(country, country_levels))

readr::write_csv(price_summary, file.path(paths$tables, "table2_price_summary.csv"),
                 na = "")

# --- Table 3: access status --------------------------------------------------
access_status <- analysis %>%
  mutate(access_group = case_when(
    country == "United States" ~ "Marketed (US, no HTA gate)",
    product_id == "zynteglo" & country != "England" ~ "Withdrawn or discontinued",
    product_id %in% c("zynteglo", "skysona") & country == "England" ~
      "Not launched or not approved",
    product_id == "beqvez" & country == "Germany" ~ "Withdrawn or discontinued",
    product_id %in% c("beqvez", "elevidys", "lyfgenia") & country != "Germany" ~
      "Not launched or not approved",
    grepl("Not approved|Not launched", access_status) ~ "Not launched or not approved",
    grepl("Not reimbursed|No NICE|Terminated|not reimbursed", access_status) ~
      "Not reimbursed / no positive HTA",
    grepl("Reimbursed|Recommended|Early access", access_status) ~ "Reimbursed / recommended",
    TRUE ~ "Status not located"
  )) %>%
  count(country, access_group) %>%
  tidyr::complete(country, access_group, fill = list(n = 0)) %>%
  group_by(country) %>%
  mutate(percent = round(100 * n / sum(n), 0)) %>%
  ungroup() %>%
  arrange(country, desc(n))

readr::write_csv(access_status, file.path(paths$tables, "table3_access_status.csv"),
                 na = "")

# --- Figure 9: access status by country -------------------------------------
access_plot <- analysis %>%
  mutate(access_group = case_when(
    country == "United States" ~ "Marketed (US, no HTA gate)",
    product_id == "zynteglo" & country != "England" ~ "Withdrawn or discontinued",
    product_id %in% c("zynteglo", "skysona") & country == "England" ~
      "Not launched or not approved",
    product_id == "beqvez" & country == "Germany" ~ "Withdrawn or discontinued",
    product_id %in% c("beqvez", "elevidys", "lyfgenia") & country != "Germany" ~
      "Not launched or not approved",
    grepl("Not approved|Not launched", access_status) ~ "Not launched or not approved",
    grepl("Not reimbursed|No NICE|Terminated|not reimbursed", access_status) ~
      "Not reimbursed / no positive HTA",
    grepl("Reimbursed|Recommended|Early access", access_status) ~ "Reimbursed / recommended",
    TRUE ~ "Status not located"
  )) %>%
  count(country, access_group) %>%
  group_by(country) %>%
  mutate(share = n / sum(n)) %>%
  ungroup()

fig9 <- ggplot(access_plot, aes(x = country, y = share, fill = access_group)) +
  geom_col(width = 0.7, colour = "white", linewidth = 0.5) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_fill_manual(values = c(
    "Reimbursed / recommended" = "#3E6FA3",
    "Marketed (US, no HTA gate)" = "#1F3B57",
    "Not reimbursed / no positive HTA" = "#C98B5E",
    "Withdrawn or discontinued" = "#8C3B2E",
    "Not launched or not approved" = "#B9B9B9",
    "Status not located" = "#E3D9C6"
  )) +
  labs(
    x = NULL, y = "Share of product-country pairs",
    title = "Reimbursement outcome by country, 2018-2024",
    subtitle = "Each bar contains 17 products",
    caption = "Categories reflect status at the end of 2024; post-window events are noted in the data appendix."
  ) +
  theme(legend.position = "right",
        panel.grid.major.x = element_blank())

save_plot(fig9, "fig9_access_status.png", width = 8.2, height = 4.8)

# --- Table 4: missingness ----------------------------------------------------
miss_vars <- c("list_price_lcu", "first_access_date", "regulatory_date",
               "hta_date", "hta_rating_ordinal", "price_year")

missingness <- purrr::map_dfr(country_levels, function(cty) {
  d <- analysis %>% filter(country == cty)
  tibble(
    country = cty,
    variable = miss_vars,
    n = nrow(d),
    n_missing = sapply(miss_vars, function(v) sum(is.na(d[[v]]))),
    pct_missing = round(100 * n_missing / n, 0)
  )
}) %>%
  mutate(country = factor(country, levels = country_levels))

readr::write_csv(missingness, file.path(paths$tables, "table4_missingness.csv"),
                 na = "")

cat("Wrote descriptive tables.\n")
print(price_summary, n = Inf)
cat("\nAccess status groups:\n")
print(access_status %>% count(access_group, wt = n), n = Inf)
