# -----------------------------------------------------------------------------
# 04_price_index.R
# Cross-country price index (US = 100) and absolute price ladder.
#
# Inputs : data/derived/prices_adjusted.csv, data/derived/price_index.csv
# Outputs: outputs/figures/fig1_price_index_distribution.png
#          outputs/figures/fig2_price_index_heatmap.png
#          outputs/figures/fig3_price_ladder.png
#          outputs/tables/table5_price_index.csv
#          outputs/tables/table6_price_index_summary.csv
# -----------------------------------------------------------------------------

source("R/00_setup.R")

adjusted <- readr::read_csv(file.path(paths$derived, "prices_adjusted.csv"),
                            show_col_types = FALSE) %>%
  mutate(country = factor(country, levels = country_levels))

price_index <- readr::read_csv(file.path(paths$derived, "price_index.csv"),
                               show_col_types = FALSE) %>%
  mutate(country = factor(country, levels = country_levels))

# --- Per-product index table -------------------------------------------------
index_wide <- price_index %>%
  select(brand, country, price_index_us100) %>%
  pivot_wider(names_from = country, values_from = price_index_us100) %>%
  mutate(across(where(is.numeric), ~ round(.x, 1))) %>%
  arrange(brand)

readr::write_csv(index_wide, file.path(paths$tables, "table5_price_index.csv"),
                 na = "")

# --- Summary table -----------------------------------------------------------
index_summary <- price_index %>%
  group_by(country) %>%
  summarise(
    n = n(),
    median = median(price_index_us100),
    q1 = quantile(price_index_us100, 0.25),
    q3 = quantile(price_index_us100, 0.75),
    min = min(price_index_us100),
    max = max(price_index_us100),
    below_us = sum(price_index_us100 < 100),
    at_or_above_us = sum(price_index_us100 >= 100),
    .groups = "drop"
  ) %>%
  mutate(across(c(median, q1, q3, min, max), ~ round(.x, 1)),
         country = as.character(country)) %>%
  arrange(match(country, country_levels))

readr::write_csv(index_summary, file.path(paths$tables, "table6_price_index_summary.csv"),
                 na = "")

# --- Balanced panel: products priced in all three European countries ---------
balanced_ids <- price_index %>%
  count(product_id) %>%
  filter(n == 3) %>%
  pull(product_id)

balanced_summary <- price_index %>%
  filter(product_id %in% balanced_ids) %>%
  group_by(country) %>%
  summarise(
    n = n(),
    median = median(price_index_us100),
    q1 = quantile(price_index_us100, 0.25),
    q3 = quantile(price_index_us100, 0.75),
    min = min(price_index_us100),
    max = max(price_index_us100),
    .groups = "drop"
  ) %>%
  mutate(across(c(median, q1, q3, min, max), ~ round(.x, 1)),
         country = as.character(country)) %>%
  arrange(match(country, country_levels))

readr::write_csv(balanced_summary,
                 file.path(paths$tables, "table11_balanced_price_index.csv"), na = "")
cat("Balanced price panel:", length(balanced_ids), "products:",
    paste(unique(price_index$brand[price_index$product_id %in% balanced_ids]), collapse = ", "), "\n")

# --- Figure 1: index distribution -------------------------------------------
fig1 <- ggplot(price_index, aes(x = country, y = price_index_us100,
                               colour = country)) +
  geom_hline(yintercept = 100, linetype = "dashed", colour = "grey35") +
  geom_boxplot(width = 0.45, outlier.shape = NA, alpha = 0.12,
               colour = "grey30", fill = "grey85") +
  geom_jitter(width = 0.08, height = 0, size = 2.3, alpha = 0.9) +
  stat_summary(fun = median, geom = "point", shape = 23, size = 3.2,
               fill = "white", colour = "grey15") +
  scale_colour_manual(values = country_pal_short) +
  scale_y_continuous(breaks = seq(60, 140, 20)) +
  labs(
    x = NULL, y = "Price index (US = 100)",
    title = "Constant-2024 USD list prices relative to the United States",
    subtitle = "Each point is one ATMP with a US comparator; diamond marks the median",
    caption = paste("Prices deflated with national CPI to 2024 and converted with",
                    "World Bank GDP PPP.\n100 = parity with the US price; 50 = half the US price.")
  ) +
  theme(legend.position = "none")

save_plot(fig1, "fig1_price_index_distribution.png", width = 7.2, height = 4.8)

# --- Figure 2: heatmap of index by product ----------------------------------
heat <- price_index %>%
  mutate(country = fct_rev(country))

fig2 <- ggplot(heat, aes(x = country, y = fct_reorder(brand, price_index_us100, .fun = median),
                         fill = price_index_us100)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = sprintf("%.0f", price_index_us100)),
            size = 3, colour = "grey10") +
  scale_fill_gradient2(low = "#4C7FA8", mid = "white", high = "#B5523B",
                       midpoint = 100, limits = c(60, 140),
                       oob = scales::squish, name = "Index") +
  labs(
    x = NULL, y = NULL,
    title = "ATMP price index by product and country (US = 100)",
    subtitle = "Blank cells indicate no comparable public list price",
    caption = "Constant-2024 USD, CPI-deflated and GDP-PPP converted."
  ) +
  theme(panel.grid = element_blank(),
        axis.text.y = element_text(size = 8.5),
        legend.position = "right")

save_plot(fig2, "fig2_price_index_heatmap.png", width = 7.4, height = 6.4)

# --- Figure 3: absolute price ladder ----------------------------------------
ladder <- adjusted %>%
  filter(!is.na(price_constant_usd_2024)) %>%
  mutate(country = factor(country, levels = country_levels))

fig3 <- ggplot(ladder, aes(x = price_constant_usd_2024,
                           y = fct_reorder(brand, us_price_constant_usd),
                           colour = country)) +
  geom_line(aes(group = brand), colour = "grey80", linewidth = 0.5) +
  geom_point(size = 2.6, alpha = 0.95) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale()),
                breaks = c(3e5, 1e6, 2e6, 4e6)) +
  scale_colour_manual(values = country_pal, name = NULL) +
  labs(
    x = "Constant-2024 USD list price (log scale)", y = NULL,
    title = "ATMP price ladder across the four jurisdictions",
    subtitle = "Products ordered by the US list price; US points are the reference",
    caption = "Grey segments connect the same product across countries."
  ) +
  theme(legend.position = "top")

save_plot(fig3, "fig3_price_ladder.png", width = 7.6, height = 7.6)

cat("Wrote price-index tables and figures.\n")
print(index_summary, n = Inf)
