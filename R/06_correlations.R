# -----------------------------------------------------------------------------
# 06_correlations.R
# Exploratory Spearman correlations, reported with bootstrap confidence
# intervals rather than p-values alone. No regression is performed.
#
# Analyses:
#   A. Pooled non-US: constant-USD list price vs launch delay.
#   B. Within-country: price vs delay.
#   C. Within-country: ordinal HTA rating vs price.
#
# Inputs : data/derived/prices_adjusted.csv
# Outputs: outputs/figures/fig6_price_vs_delay.png
#          outputs/figures/fig7_hta_vs_price.png
#          outputs/tables/table9_correlations.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

adjusted <- readr::read_csv(file.path(paths$derived, "prices_adjusted.csv"),
                            show_col_types = FALSE) %>%
  mutate(country = factor(country, levels = country_levels))

# --- Correlation helper ------------------------------------------------------
cor_row <- function(data, x, y, analysis, country_label) {
  xv <- data[[x]]; yv <- data[[y]]
  res <- boot_spearman(xv, yv, R = 4000)
  tibble(
    analysis = analysis,
    country = country_label,
    n = sum(complete.cases(xv, yv)),
    spearman_rho = unname(res["estimate"]),
    ci_low = unname(res["conf.low"]),
    ci_high = unname(res["conf.high"]),
    p_value = unname(res["p.value"])
  )
}

non_us <- adjusted %>% filter(country != "United States", !is.na(delay_regulatory_to_access))

correlations <- bind_rows(
  cor_row(non_us, "price_constant_usd_2024", "delay_regulatory_to_access",
          "Price vs launch delay (pooled, non-US)", "Pooled (DE, FR, EN)"),
  purrr::map_dfr(c("Germany", "France", "England"), function(cty) {
    cor_row(non_us %>% filter(country == cty),
            "price_constant_usd_2024", "delay_regulatory_to_access",
            "Price vs launch delay (within country)", cty)
  }),
  purrr::map_dfr(c("Germany", "France", "England"), function(cty) {
    cor_row(adjusted %>% filter(country == cty),
            "price_constant_usd_2024", "hta_rating_ordinal",
            "Ordinal HTA rating vs price (within country)", cty)
  })
) %>%
  mutate(
    across(c(spearman_rho, ci_low, ci_high, p_value), ~ round(.x, 3)),
    direction = case_when(
      is.na(spearman_rho) ~ "Not estimable",
      spearman_rho > 0 ~ "Positive",
      spearman_rho < 0 ~ "Negative",
      TRUE ~ "Null"
    ),
    ci_crosses_zero = ci_low <= 0 & ci_high >= 0
  )

readr::write_csv(correlations, file.path(paths$tables, "table9_correlations.csv"),
                 na = "")

# --- Figure 6: price vs delay ------------------------------------------------
plot_df <- non_us %>%
  filter(!is.na(price_constant_usd_2024))

fig6 <- ggplot(plot_df, aes(x = price_constant_usd_2024,
                            y = delay_regulatory_to_access,
                            colour = country)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey55") +
  geom_point(size = 2.8, alpha = 0.9) +
  ggrepel::geom_text_repel(aes(label = brand), size = 2.6, colour = "grey25",
                           max.overlaps = 20, seed = 1) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_colour_manual(values = country_pal_short) +
  labs(
    x = "Constant-2024 USD list price (log scale)",
    y = "Days from approval to reimbursed access",
    title = "List price and launch delay: exploratory association",
    subtitle = "Pooled non-US observations; labels identify products",
    caption = paste("Spearman rho is reported with a bootstrap 95% CI.",
                    "The association is descriptive and cannot support causal inference.")
  )

save_plot(fig6, "fig6_price_vs_delay.png", width = 8.2, height = 5.6)

# --- Figure 7: HTA rating vs price ------------------------------------------
hta_df <- adjusted %>%
  filter(!is.na(hta_rating_ordinal), !is.na(price_constant_usd_2024),
         country != "United States")

fig7 <- ggplot(hta_df, aes(x = factor(hta_rating_ordinal),
                           y = price_constant_usd_2024,
                           colour = country)) +
  geom_jitter(width = 0.12, height = 0, size = 2.6, alpha = 0.9) +
  facet_wrap(~ country, nrow = 1, scales = "free_x") +
  scale_y_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_colour_manual(values = country_pal_short) +
  labs(
    x = "Ordinal HTA rating (country-specific scale)",
    y = "Constant-2024 USD list price (log scale)",
    title = "HTA benefit rating and list price, within country",
    subtitle = "Ordinal codes are not comparable across HTA systems",
    caption = paste("Germany: 0 = no additional benefit, 2 = non-quantifiable/minor,",
                    "3 = considerable, 4 = major.\nFrance ASMR: 1 = V ... 5 = I.",
                    "England: 2 = recommended, 1 = optimised, 0 = not recommended.")
  ) +
  theme(legend.position = "none")

save_plot(fig7, "fig7_hta_vs_price.png", width = 9.4, height = 4.4)

cat("Wrote correlation table and figures.\n")
print(correlations, n = Inf)
