# Data dictionary

## `data/raw/atmp_extraction.csv`

One row per drug × country pair (17 products × 4 countries = 68 rows). Blank cells are
explicit missing values, never zeros.

| Variable | Type | Definition | Coding / notes |
|---|---|---|---|
| `product_id` | character | Lower-case product key | Stable across files |
| `brand` | character | Brand name | US brand used where EU/US names differ (`Libmeldy/Lenmeldy`) |
| `inn` | character | International non-proprietary name | |
| `modality` | character | ATMP class | `CAR-T cell therapy`, `Gene therapy`, `Gene-edited cell therapy` |
| `manufacturer` | character | Marketing authorisation holder | |
| `country` | character | Jurisdiction | `United States`, `Germany`, `France`, `England` |
| `approved` | logical | Marketing authorisation exists in that jurisdiction | `FALSE` = never approved; `NA` = not verified |
| `regulatory_anchor` | character | Regulator used for the approval date | `FDA`, `EMA`, `MHRA`, `EMA/MHRA reliance (post-2021)` |
| `regulatory_date` | date | Date of marketing authorisation | FDA approval, EMA EC decision, or MHRA decision |
| `hta_body` | character | National HTA body | `G-BA`, `HAS`, `NICE`, `None (FDA/CBER)` |
| `hta_date` | date | Date of HTA decision/opinion | Missing where not located |
| `hta_rating_raw` | character | Verbatim HTA rating | e.g. `ASMR III`, `Non-quantifiable additional benefit` |
| `hta_rating_ordinal` | integer | Ordinal HTA code used for exploratory correlation | Germany: 4 major, 3 considerable, 2 minor/non-quantifiable, 0 none, −1 less. France ASMR I–V → 5–1. England recommended = 2, optimised = 1, not recommended = 0 |
| `hta_recommendation` | character | Free-text recommendation | |
| `reimbursement_date` | date | Formal reimbursement/price decision date | Germany = launch (free-pricing period); France = CEPS date; England = NICE publication |
| `first_access_date` | date | Primary access endpoint | US = FDA date; DE = EMA date; FR = CEPS date (or documented ATU); EN = NICE publication |
| `access_status` | character | Reimbursement outcome | Free text; grouped in analysis |
| `list_price_lcu` | numeric | Public list price at/near launch, local currency | `NA` when confidential or not located |
| `currency` | character | Currency of `list_price_lcu` | `USD`, `EUR`, `GBP` |
| `price_basis` | character | What the price represents | WAC, ex-factory/Lauer-Taxe, CEPS prix fabricant, NICE-stated, ATU proxy |
| `price_year` | integer | Year to which the price applies | Used to select the CPI/PPP factor |
| `price_confidential` | logical | Price exists but is confidential | `TRUE` implies `list_price_lcu = NA` |
| `price_notes` | character | Extraction note and discrepancy flag | |
| `source_primary` | character | Primary source | |
| `source_url` | character | URL of the primary source | |
| `source_secondary` | character | Verification source | |
| `verification` | character | Evidence grade | `verified_primary`, `verified_secondary`, `proxy`, `single_source`, `not_located` |

## `data/raw/price_factors.csv`

One row per country × year (2015–2024).

| Variable | Definition | Source |
|---|---|---|
| `cpi_index_2010` | Consumer price index, 2010 = 100 | World Bank WDI `FP.CPI.TOTL` |
| `ppp_gdp_lcu_per_intusd` | GDP-based PPP conversion factor, local currency per international dollar | World Bank WDI `PA.NUS.PPP` |
| `ppp_private_consumption_lcu_per_intusd` | Actual-individual-consumption PPP | Not retrievable; retained as `NA` |

## `data/derived/analysis.csv`

The 68-row analysis file with derived fields:

| Variable | Definition |
|---|---|
| `delay_regulatory_to_access` | `first_access_date − regulatory_date`, in days |
| `delay_years` | Delay in years (days / 365.25) |
| `delay_negative` | Flag for access preceding formal approval (early access) |
| `has_price` | `TRUE` where `list_price_lcu` is observed |
| `has_delay` | `TRUE` where the delay can be computed |
| `delay_analysable` | `TRUE` for non-US rows with an observed delay |

## `data/derived/prices_adjusted.csv`

Adds the transformation columns:

| Variable | Formula |
|---|---|
| `price_real_lcu_2024` | `list_price_lcu × CPI_2024 / CPI_price_year` |
| `price_constant_usd_2024` | `price_real_lcu_2024 / PPP_2024` |
| `price_real_lcu_2020` | `list_price_lcu × CPI_2020 / CPI_price_year` |
| `price_constant_usd_2020` | `price_real_lcu_2020 / PPP_2020` |
| `us_price_constant_usd` | US constant-2024 USD price for the same product |
| `price_index_us100` | `100 × price_constant_usd_2024 / us_price_constant_usd` |
| `price_index_us100_2020` | Same index computed on the 2020 base |

## Missing-value conventions

- **Structural missingness**: product not approved or not launched in a country. All
  country-specific variables are `NA`.
- **Confidential price**: `list_price_lcu = NA`, `price_confidential = TRUE`, reason in
  `price_notes`.
- **Not located**: `verification = "not_located"` and the reason in `price_notes`.
- **Factor missingness**: none in the final dataset; all 43 priced rows have CPI and PPP
  factors.
