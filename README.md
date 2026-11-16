# ATMP pricing and access: a four-country comparative policy analysis

A reproducible R analysis of publicly listed prices and the time from regulatory approval to reimbursed patient access for advanced therapy medicinal products (ATMPs) across the United States, Germany, France, and England, 2018&ndash;2024.

The project builds a harmonised drug &times; country dataset (17 products &times; 4 countries = 68 observations), adjusts list prices for inflation and purchasing-power differences, and describes cross-country variation in prices, launch delays, reimbursement outcomes, and HTA ratings. All analyses are descriptive or exploratory; no regression modelling is performed.

## Research questions

1. How large are cross-country list-price differences for the same ATMP after CPI and PPP adjustment?
2. How long does it take from regulatory approval to first reimbursed access, and which countries are faster or slower?
3. Is there an association between list price and launch delay (the budget-shock hypothesis)?
4. What happens to ATMPs that receive regulatory authorisation but do not achieve sustainable reimbursement?

## Key findings

- **List prices converge after adjustment.** Median constant-2024 USD price indices (US = 100) were 111.4 in Germany, 108.7 in France, and 106.8 in England. A balanced six-product panel gives 112.0, 105.0, and 106.8.
- **Germany's zero delay is definitional.** AMNOG free pricing starts on the EMA decision date. At the end of the 12-month free-pricing period, Germany's median delay is 365 days.
- **France and England take about 10&ndash;11 months.** Median delays were 337 days (France) and 310.5 days (England), with long tails.
- **The price&ndash;delay association is weak overall but strong within England.** Pooled Spearman &rho; = 0.15 (95% CI &minus;0.33 to 0.57); England &rho; = 0.89 (95% CI 0.41 to 1.00; n = 7).
- **Approval is not access.** Only 29 of 68 product&ndash;country pairs reached a reimbursed or recommended status.

## Repository structure

```
.
├── R/
│   ├── 00_setup.R              # packages, paths, theme, helpers
│   ├── 00_build_extraction.R   # builds the 68-row dataset and source register
│   ├── 01_import_validate.R    # validation checks and derived outcomes
│   ├── 02_price_adjustment.R   # CPI -> PPP -> US=100 index
│   ├── 03_descriptive.R        # sample, price, access and missingness tables
│   ├── 04_price_index.R        # index tables and price figures
│   ├── 05_launch_delay.R       # ridgeline and timeline figures
│   ├── 06_correlations.R       # Spearman correlations with bootstrap CIs
│   ├── 07_sensitivity.R        # nine pre-specified sensitivity analyses
│   ├── 08_render_report.R      # Markdown -> HTML -> PDF
│   └── run_all.R               # runs the pipeline end to end
├── data/
│   ├── raw/
│   │   ├── atmp_extraction.csv # 68 rows, source-registered
│   │   ├── price_factors.csv   # World Bank CPI and PPP factors
│   │   ├── source_register.csv # 16 sources with tiers
│   │   ├── data_dictionary.md
│   │   └── sources/            # downloaded source PDFs and API extracts
│   └── derived/                # analysis.csv, prices_adjusted.csv, price_index.csv
├── outputs/
│   ├── figures/                # 9 figures at 300 dpi
│   └── tables/                 # CSV/HTML tables, validation log
├── report/
│   ├── atmp_report.Rmd
│   ├── atmp_report.md
│   ├── atmp_report.html
│   ├── atmp_report.pdf
│   └── report.css
├── protocol/protocol.md
├── references.bib
└── renv.lock
```

## Reproducing the analysis

Requirements: R (>= 4.3), the packages recorded in `renv.lock`, and Microsoft Edge for the PDF step (the HTML report is produced regardless).

```r
# Restore the locked environment
renv::restore()

# Run the full pipeline from the project root
source("R/run_all.R")
```

Or from a shell:

```bash
Rscript R/run_all.R
```

The pipeline is deterministic. `R/00_build_extraction.R` rewrites the raw extraction table; `R/01_import_validate.R` fails loudly if the 68-row structure, currency mapping, price-year coverage, or CPI/PPP coverage is violated.

## Data and sources

The unit of analysis is the drug &times; country pair. Prices are public list prices, not net prices. The dataset distinguishes US WAC, German ex-factory/Lauer-Taxe prices, French CEPS-set prices, and NICE-stated English prices. Confidential prices are coded `NA` with `price_confidential = TRUE` and a documented reason; no value is imputed.

- Products: 17 ATMPs approved by the FDA and/or EMA between 2017 and 2024.
- Countries: United States, Germany, France, England (NHS England/NICE only).
- Price factors: World Bank WDI `FP.CPI.TOTL` and `PA.NUS.PPP`. OECD retrieval failed in the execution environment; the deviation is documented in the report and data dictionary.
- Sources: 16 primary and authoritative sources, registered with tier and use in `data/raw/source_register.csv`.

## Outputs

- `report/atmp_report.pdf` &mdash; 32-page report with methods, results, discussion, limitations, and appendices.
- `outputs/figures/` &mdash; price index distribution, heatmap, price ladder, delay ridgeline, access timelines, correlation plots, sensitivity plot, access-status chart.
- `outputs/tables/` &mdash; validation log, descriptive tables, price-index tables, delay tables, correlation table, sensitivity table.

## Method notes

1. **Price transformation:** CPI deflation in local currency to 2024, then division by the 2024 GDP PPP factor (local currency per international dollar), then `100 &times; country price / US price`. Deflating after PPP conversion would mix inflation rates across currencies and is not used.
2. **Launch delay:** `first_access_date - regulatory_date` in days. The US is excluded because its delay is zero by construction. Germany's delay is zero by design under AMNOG free pricing.
3. **Statistics:** median and IQR; Spearman rank correlations with 4,000-sample bootstrap confidence intervals. No regression, by protocol.
4. **Sensitivity:** nine pre-specified analyses, including the German free-pricing year, the English 90-day funding lag, the French HAS anchor, a four-country median reference, and alternative PPP/CPI bases.

## Limitations

List prices are not net prices; confidential rebates and discounts are unobserved. Access endpoints are operationalised differently in each country and carry asymmetric biases. The sample is small (17 products; at most 68 observations), so correlations have wide confidence intervals and no causal inference is possible. Actual-individual-consumption PPP could not be retrieved and the corresponding sensitivity analysis is not estimable. HTA ratings are not comparable across countries.

## Data availability

The extracted dataset, source register, data dictionary, analysis scripts, and generated outputs are included in this repository. Downloaded source documents are retained in `data/raw/sources/` for audit. No confidential or patient-level data are used.

## Author

Zoubayda Baoubbou &mdash; Health Economics and Outcomes Research.

## License

Code: MIT. Text and figures: CC BY 4.0.
