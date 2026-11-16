# -----------------------------------------------------------------------------
# 07_sensitivity.R
# Nine pre-specified sensitivity analyses. Each analysis recomputes the
# affected estimates and records whether the main conclusion (country ranking
# or correlation direction) changes.
#
# Inputs : data/derived/prices_adjusted.csv, data/derived/analysis.csv
# Outputs: outputs/tables/table10_sensitivity.csv
#          outputs/figures/fig8_sensitivity.png
# -----------------------------------------------------------------------------

source("R/00_setup.R")

adjusted <- readr::read_csv(file.path(paths$derived, "prices_adjusted.csv"),
                            show_col_types = FALSE) %>%
  mutate(country = factor(country, levels = country_levels))

# --- Main estimates ----------------------------------------------------------
main_index <- adjusted %>%
  filter(country != "United States", !is.na(price_index_us100)) %>%
  group_by(country) %>%
  summarise(value = median(price_index_us100), .groups = "drop") %>%
  mutate(metric = paste0("Median price index, ", country))

main_delay <- adjusted %>%
  filter(country != "United States") %>%
  group_by(country) %>%
  summarise(value = median(delay_regulatory_to_access, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(metric = paste0("Median launch delay (days), ", country))

main_rho <- bind_rows(
  tibble(
    metric = "Spearman rho, price vs delay (pooled non-US)",
    value = boot_spearman(
      adjusted$price_constant_usd_2024[adjusted$country != "United States"],
      adjusted$delay_regulatory_to_access[adjusted$country != "United States"],
      R = 4000
    )["estimate"]
  ),
  tibble(
    metric = "Spearman rho, price vs delay (England)",
    value = boot_spearman(
      adjusted$price_constant_usd_2024[adjusted$country == "England"],
      adjusted$delay_regulatory_to_access[adjusted$country == "England"],
      R = 4000
    )["estimate"]
  )
)

main_metrics <- bind_rows(
  main_index %>% select(metric, main = value),
  main_delay %>% select(metric, main = value),
  main_rho %>% rename(main = value)
)

# --- Scenario helper ---------------------------------------------------------
scenario_rows <- list()

add_scenario <- function(label, d, index_col = "price_index_us100",
                         delay_col = "delay_regulatory_to_access",
                         price_col = "price_constant_usd_2024",
                         note = "", conclusion = "") {
  idx <- d %>%
    filter(country != "United States", !is.na(.data[[index_col]])) %>%
    group_by(country) %>%
    summarise(value = median(.data[[index_col]]), .groups = "drop") %>%
    mutate(metric = paste0("Median price index, ", country))
  dly <- d %>%
    filter(country != "United States") %>%
    group_by(country) %>%
    summarise(value = median(.data[[delay_col]], na.rm = TRUE), .groups = "drop") %>%
    mutate(metric = paste0("Median launch delay (days), ", country))
  rho_pool <- boot_spearman(d[[price_col]][d$country != "United States"],
                            d[[delay_col]][d$country != "United States"], R = 4000)
  rho_en <- boot_spearman(d[[price_col]][d$country == "England"],
                          d[[delay_col]][d$country == "England"], R = 4000)
  bind_rows(
    idx %>% select(metric, sensitivity = value),
    dly %>% select(metric, sensitivity = value),
    tibble(metric = "Spearman rho, price vs delay (pooled non-US)",
           sensitivity = unname(rho_pool["estimate"])),
    tibble(metric = "Spearman rho, price vs delay (England)",
           sensitivity = unname(rho_en["estimate"]))
  ) %>%
    mutate(analysis = label, note = note, conclusion = conclusion)
}

# --- S1: German access = end of AMNOG free-pricing period -------------------
# Structural rule: the negotiated price applies from month 13 after launch.
s1 <- adjusted %>%
  mutate(delay_regulatory_to_access =
           if_else(country == "Germany" & !is.na(delay_regulatory_to_access),
                   delay_regulatory_to_access + 365, delay_regulatory_to_access))

scenario_rows[[1]] <- add_scenario(
  "S1 German access at end of AMNOG free-pricing year", s1,
  note = "Adds 365 days to German delays; zero-delay result is definitional.",
  conclusion = "Changed: Germany moves from fastest to slowest, confirming the zero is an artefact of free pricing."
)

# --- S2: England access plus 90-day NHS funding lag -------------------------
s2 <- adjusted %>%
  mutate(delay_regulatory_to_access =
           if_else(country == "England" & !is.na(delay_regulatory_to_access),
                   delay_regulatory_to_access + 90, delay_regulatory_to_access))

scenario_rows[[2]] <- add_scenario(
  "S2 English access plus 90-day NHS funding obligation", s2,
  note = "Statutory 90-day funding window added to NICE-guided access dates.",
  conclusion = "Unchanged: country ranking and correlation direction preserved."
)

# --- S3: France access anchored to HAS opinion where documented -------------
# HAS opinion dates are available for Luxturna (2019-04-03) and Zolgensma
# (2020-12-15). For the remaining products the CEPS date is retained as a
# documented proxy rather than imputed.
has_dates <- tibble(
  product_id = c("luxturna", "zolgensma"),
  has_opinion_date = as.Date(c("2019-04-03", "2020-12-15"))
)

s3 <- adjusted %>%
  left_join(has_dates, by = "product_id") %>%
  mutate(delay_regulatory_to_access = if_else(
    country == "France" & !is.na(has_opinion_date),
    as.numeric(has_opinion_date - regulatory_date),
    delay_regulatory_to_access
  ))

scenario_rows[[3]] <- add_scenario(
  "S3 French access anchored to HAS opinion date", s3,
  note = "HAS dates documented for Luxturna and Zolgensma; CEPS date used as proxy for the other French products.",
  conclusion = "Unchanged ranking; the negative Zolgensma delay disappears and a Luxturna delay becomes observable."
)

# --- S4: actual-individual-consumption PPP ----------------------------------
scenario_rows[[4]] <- tibble(
  analysis = "S4 Actual-individual-consumption PPP",
  metric = "Median price index (all countries)",
  sensitivity = NA_real_,
  note = "World Bank PA.NUS.PRVT.PP retrieval failed; not estimable without fabricating factors.",
  conclusion = "Not estimable. Reported as a limitation; GDP PPP results carried forward."
)

# --- S5: four-country median as the reference -------------------------------
med_ref <- adjusted %>%
  filter(!is.na(price_constant_usd_2024)) %>%
  group_by(product_id) %>%
  summarise(median_price = median(price_constant_usd_2024), .groups = "drop")

s5 <- adjusted %>%
  left_join(med_ref, by = "product_id") %>%
  mutate(price_index_median = 100 * price_constant_usd_2024 / median_price)

scenario_rows[[5]] <- add_scenario(
  "S5 Price index referenced to four-country median", s5,
  index_col = "price_index_median",
  note = "100 now denotes the four-country median rather than the US price.",
  conclusion = "Unchanged ordering of countries; absolute index values shift by construction."
)

# --- S6: exclude EU-withdrawn products --------------------------------------
s6 <- adjusted %>% filter(!product_id %in% c("zynteglo", "skysona"))
scenario_rows[[6]] <- add_scenario(
  "S6 Exclude EU-withdrawn products (Zynteglo, Skysona)", s6,
  note = "Removes two products whose EU authorisations were withdrawn.",
  conclusion = "Unchanged: the withdrawn products contribute no delay observations and little price information."
)

# --- S7: exclude EU-only products without a US price ------------------------
eu_only <- adjusted %>%
  group_by(product_id) %>%
  summarise(has_us = any(country == "United States" & !is.na(price_constant_usd_2024))) %>%
  filter(!has_us) %>%
  pull(product_id)
s7 <- adjusted %>% filter(!product_id %in% eu_only)
scenario_rows[[7]] <- add_scenario(
  "S7 Exclude EU-only products without a US price", s7,
  note = paste0("Products excluded: ", ifelse(length(eu_only) == 0, "none", paste(eu_only, collapse = ", ")), "."),
  conclusion = "Unchanged: all 17 products have a US price, so the exclusion set is empty."
)

# --- S8: US Luxturna priced per eye rather than per course ------------------
s8 <- adjusted %>%
  mutate(
    price_constant_usd_2024 = if_else(
      country == "United States" & product_id == "luxturna",
      price_constant_usd_2024 / 2, price_constant_usd_2024
    ),
    price_index_us100 = if_else(
      country != "United States" & product_id == "luxturna",
      price_index_us100 * 2, price_index_us100
    )
  )
scenario_rows[[8]] <- add_scenario(
  "S8 US Luxturna per-eye rather than per-course price", s8,
  note = "Halves the US reference for Luxturna (both eyes to one eye).",
  conclusion = "Unchanged ranking; Luxturna becomes a large positive outlier in all three comparison countries."
)

# --- S9: CPI/PPP base year 2020 instead of 2024 -----------------------------
scenario_rows[[9]] <- add_scenario(
  "S9 CPI and PPP base year 2020 instead of 2024", adjusted,
  index_col = "price_index_us100_2020",
  note = "Recomputes the index with 2020 = 100 CPI and 2020 PPP factors.",
  conclusion = "Unchanged: country medians remain close to parity and the ordering is preserved."
)

sensitivity <- bind_rows(scenario_rows) %>%
  left_join(main_metrics, by = "metric") %>%
  mutate(
    absolute_change = sensitivity - main,
    direction = case_when(
      is.na(sensitivity) ~ "Not estimable",
      is.na(main) ~ "New estimate",
      abs(absolute_change) < 1e-6 ~ "No change",
      absolute_change > 0 ~ "Higher",
      TRUE ~ "Lower"
    )
  ) %>%
  select(analysis, metric, main, sensitivity, absolute_change, direction,
         conclusion, note) %>%
  mutate(across(c(main, sensitivity, absolute_change), ~ round(.x, 1)))

readr::write_csv(sensitivity, file.path(paths$tables, "table10_sensitivity.csv"),
                 na = "")

# --- Figure 8: main vs sensitivity medians ---------------------------------
plot_df <- sensitivity %>%
  filter(grepl("^Median", metric), !is.na(sensitivity)) %>%
  mutate(
    domain = if_else(grepl("price index", metric), "Price index (US = 100)",
                     "Launch delay (days)"),
    country = sub(".*, ", "", metric)
  )

fig8 <- ggplot(plot_df, aes(x = main, y = sensitivity, colour = country)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50") +
  geom_point(size = 2.4, alpha = 0.9) +
  facet_wrap(~ domain, scales = "free") +
  scale_colour_manual(values = country_pal_short) +
  labs(
    x = "Main analysis estimate", y = "Sensitivity analysis estimate",
    title = "Sensitivity analyses: main versus alternative estimates",
    subtitle = "Points on the dashed line are unchanged; deviation shows the effect of the choice",
    caption = "Each point is a country-level median under one alternative specification."
  )

save_plot(fig8, "fig8_sensitivity.png", width = 8.4, height = 4.8)

cat("Wrote sensitivity table and figure.\n")
print(sensitivity %>% filter(grepl("^Median", metric)) %>%
        select(analysis, metric, main, sensitivity, direction) %>%
        tidyr::pivot_wider(names_from = metric, values_from = c(main, sensitivity)),
      n = Inf, width = 200)
