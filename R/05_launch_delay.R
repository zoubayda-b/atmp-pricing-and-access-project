# -----------------------------------------------------------------------------
# 05_launch_delay.R
# Time from regulatory approval to first reimbursed access. The US is excluded
# from the comparison because its delay is zero by construction.
#
# Inputs : data/derived/analysis.csv
# Outputs: outputs/figures/fig4_delay_ridgeline.png
#          outputs/figures/fig5_access_timeline.png
#          outputs/tables/table7_delay_summary.csv
#          outputs/tables/table8_delay_by_product.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

analysis <- readr::read_csv(file.path(paths$derived, "analysis.csv"),
                            show_col_types = FALSE) %>%
  mutate(country = factor(country, levels = country_levels))

delay_df <- analysis %>%
  filter(delay_analysable, country != "United States") %>%
  mutate(country = factor(country, levels = c("Germany", "France", "England")))

# --- Summary table -----------------------------------------------------------
delay_summary <- delay_df %>%
  group_by(country) %>%
  summarise(
    n = n(),
    median_days = median(delay_regulatory_to_access),
    q1_days = quantile(delay_regulatory_to_access, 0.25),
    q3_days = quantile(delay_regulatory_to_access, 0.75),
    min_days = min(delay_regulatory_to_access),
    max_days = max(delay_regulatory_to_access),
    n_negative = sum(delay_regulatory_to_access < 0),
    n_within_90 = sum(delay_regulatory_to_access <= 90),
    n_within_180 = sum(delay_regulatory_to_access <= 180),
    n_within_365 = sum(delay_regulatory_to_access <= 365),
    median_months = median(delay_regulatory_to_access) / 30.44,
    .groups = "drop"
  ) %>%
  mutate(across(c(median_days, q1_days, q3_days, min_days, max_days,
                  median_months), ~ round(.x, 1)),
         country = as.character(country))

readr::write_csv(delay_summary, file.path(paths$tables, "table7_delay_summary.csv"),
                 na = "")

delay_by_product <- delay_df %>%
  select(brand, country, regulatory_date, first_access_date,
         delay_regulatory_to_access, delay_negative, access_status) %>%
  arrange(country, delay_regulatory_to_access)
readr::write_csv(delay_by_product, file.path(paths$tables, "table8_delay_by_product.csv"),
                 na = "")

# --- Balanced panel: products with a delay in all three countries ------------
balanced_delay_ids <- delay_df %>%
  count(product_id) %>%
  filter(n == 3) %>%
  pull(product_id)

balanced_delay <- delay_df %>%
  filter(product_id %in% balanced_delay_ids) %>%
  group_by(country) %>%
  summarise(
    n = n(),
    median_days = median(delay_regulatory_to_access),
    q1_days = quantile(delay_regulatory_to_access, 0.25),
    q3_days = quantile(delay_regulatory_to_access, 0.75),
    .groups = "drop"
  ) %>%
  mutate(across(c(median_days, q1_days, q3_days), ~ round(.x, 1)),
         country = as.character(country)) %>%
  arrange(match(country, c("Germany", "France", "England")))

readr::write_csv(balanced_delay,
                 file.path(paths$tables, "table12_balanced_delay.csv"), na = "")
cat("Balanced delay panel:", length(balanced_delay_ids), "products:",
    paste(unique(delay_df$brand[delay_df$product_id %in% balanced_delay_ids]), collapse = ", "), "\n")

# --- Figure 4: ridgeline -----------------------------------------------------
fig4 <- ggplot(delay_df, aes(x = delay_regulatory_to_access,
                             y = fct_rev(country), fill = country)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey35") +
  geom_density_ridges(scale = 1.15, alpha = 0.72, colour = "grey35",
                      linewidth = 0.4, quantile_lines = TRUE, quantiles = 2,
                      bandwidth = 90) +
  geom_jitter(aes(colour = country), height = 0.09, width = 0, size = 1.9,
              alpha = 0.9, inherit.aes = TRUE) +
  scale_fill_manual(values = country_pal_short) +
  scale_colour_manual(values = country_pal_short) +
  scale_x_continuous(labels = scales::label_comma()) +
  labs(
    x = "Days from regulatory approval to first reimbursed access",
    y = NULL,
    title = "Distribution of launch delays for ATMPs, 2018-2024",
    subtitle = "The United States is excluded because its delay is zero by definition",
    caption = paste("Vertical line = 0 days. White bar inside each ridge = median.",
                    "Negative values reflect pre-authorisation early access (France, Zolgensma).")
  ) +
  theme(legend.position = "none")

save_plot(fig4, "fig4_delay_ridgeline.png", width = 7.4, height = 4.6)

# --- Figure 5: access timeline ----------------------------------------------
timeline <- analysis %>%
  filter(delay_analysable, country != "United States") %>%
  mutate(country = factor(country, levels = c("Germany", "France", "England")))

fig5 <- ggplot(timeline) +
  geom_segment(aes(x = regulatory_date, xend = first_access_date,
                   y = fct_reorder(brand, regulatory_date),
                   yend = fct_reorder(brand, regulatory_date),
                   colour = country),
               linewidth = 1.2, alpha = 0.55) +
  geom_point(aes(x = regulatory_date, y = fct_reorder(brand, regulatory_date)),
             shape = 21, fill = "white", colour = "grey25", size = 2.2) +
  geom_point(aes(x = first_access_date, y = fct_reorder(brand, regulatory_date),
                 colour = country), size = 2.6) +
  facet_wrap(~ country, nrow = 1) +
  scale_colour_manual(values = country_pal_short) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y",
               limits = as.Date(c("2018-01-01", "2025-06-30"))) +
  labs(
    x = NULL, y = NULL,
    title = "Regulatory approval to reimbursed access: product timelines",
    subtitle = "Open circle = regulatory approval; filled circle = first reimbursed access",
    caption = "Facets show only products with an observed access date in each country."
  ) +
  theme(legend.position = "none",
        axis.text.y = element_text(size = 8),
        panel.grid.major.y = element_blank())

save_plot(fig5, "fig5_access_timeline.png", width = 10.5, height = 5.8)

# --- US note -----------------------------------------------------------------
us_delay <- analysis %>%
  filter(country == "United States") %>%
  summarise(n = n(), all_zero = all(delay_regulatory_to_access == 0, na.rm = TRUE))
cat("US rows:", us_delay$n, "| all zero delay:", us_delay$all_zero, "\n")
cat("Non-US analysable delays:", nrow(delay_df), "\n")
print(delay_summary, n = Inf)
