# -----------------------------------------------------------------------------
# 00_build_extraction.R
# Build the hand-extracted drug x country dataset.
#
# This script is the auditable bridge between the source register and the
# analysis file. Every value below was extracted from a named primary or
# authoritative secondary source; missing values are coded NA with a reason in
# `price_notes` or `access_status`. No value is imputed.
#
# Outputs:
#   data/raw/atmp_extraction.csv   (68 rows: 17 products x 4 countries)
#   data/raw/source_register.csv   (source-level audit trail)
# -----------------------------------------------------------------------------

rm(list = ls())

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/derived", recursive = TRUE, showWarnings = FALSE)

as_date <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || identical(x, "")) {
    return(as.Date(NA))
  }
  as.Date(x)
}

FDA <- "https://www.fda.gov/vaccines-blood-biologics/cellular-gene-therapy-products/approved-cellular-and-gene-therapy-products"
ISPOR25 <- "https://www.ispor.org/docs/default-source/cti-meeting-21305-documents/fe7c1234-8a03-4c2f-b370-1e1f171166ac.pdf"
ISPOR24 <- "https://www.ispor.org/docs/default-source/euro2024/isporeurope24nghta21poster146626-pdf.pdf"
NICE <- function(id) paste0("https://www.nice.org.uk/guidance/", id)
EMA <- function(slug) paste0("https://www.ema.europa.eu/en/medicines/human/EPAR/", slug)

# --- Product-level frame -----------------------------------------------------
products <- data.frame(
  product_id = c("kymriah", "yescarta", "luxturna", "zynteglo", "zolgensma",
                 "libmeldy", "tecartus", "skysona", "abecma", "breyanzi",
                 "carvykti", "roctavian", "hemgenix", "casgevy", "lyfgenia",
                 "beqvez", "elevidys"),
  brand = c("Kymriah", "Yescarta", "Luxturna", "Zynteglo", "Zolgensma",
            "Libmeldy/Lenmeldy", "Tecartus", "Skysona", "Abecma", "Breyanzi",
            "Carvykti", "Roctavian", "Hemgenix", "Casgevy", "Lyfgenia",
            "Beqvez", "Elevidys"),
  inn = c("tisagenlecleucel", "axicabtagene ciloleucel", "voretigene neparvovec",
          "betibeglogene autotemcel", "onasemnogene abeparvovec",
          "atidarsagene autotemcel", "brexucabtagene autoleucel",
          "elivaldogene autotemcel", "idecabtagene vicleucel",
          "lisocabtagene maraleucel", "ciltacabtagene autoleucel",
          "valoctocogene roxaparvovec", "etranacogene dezaparvovec",
          "exagamglogene autotemcel", "lovotibeglogene autotemcel",
          "fidanacogene elaparvovec", "delandistrogene moxeparvovec"),
  modality = c("CAR-T cell therapy", "CAR-T cell therapy", "Gene therapy",
               "Gene therapy", "Gene therapy", "Gene therapy", "CAR-T cell therapy",
               "Gene therapy", "CAR-T cell therapy", "CAR-T cell therapy",
               "CAR-T cell therapy", "Gene therapy", "Gene therapy",
               "Gene-edited cell therapy", "Gene therapy", "Gene therapy",
               "Gene therapy"),
  manufacturer = c("Novartis", "Kite/Gilead", "Spark/Novartis", "bluebird bio",
                   "Novartis Gene Therapies", "Orchard Therapeutics",
                   "Kite/Gilead", "bluebird bio", "BMS/2seventy bio",
                   "Bristol Myers Squibb", "Janssen/Legend", "BioMarin",
                   "CSL Behring", "Vertex/CRISPR Therapeutics", "bluebird bio",
                   "Pfizer", "Sarepta/Roche"),
  us_date = as.Date(c("2017-08-30", "2017-10-18", "2017-12-19", "2022-08-17",
                      "2019-05-24", "2024-03-18", "2020-07-24", "2022-09-16",
                      "2021-03-26", "2021-02-05", "2022-02-28", "2023-06-29",
                      "2022-11-22", "2023-12-08", "2023-12-08", "2024-04-25",
                      "2023-06-22")),
  eu_date = as.Date(c("2018-08-23", "2018-08-23", "2018-11-22", "2019-05-29",
                      "2020-05-18", "2020-12-17", "2020-12-14", "2021-07-16",
                      "2021-08-18", "2022-04-04", "2022-05-25", "2022-08-24",
                      "2023-02-20", "2024-02-09", NA, "2024-07-24", NA)),
  uk_date = as.Date(c("2018-08-23", "2018-08-23", "2018-11-22", "2019-05-29",
                      "2020-05-18", "2020-12-17", "2020-12-14", "2021-07-16",
                      "2021-08-18", "2022-04-04", "2022-05-25", "2022-08-24",
                      "2023-02-20", "2023-11-16", NA, NA, NA)),
  uk_anchor = c(rep("EMA decision (pre-2021)", 8), rep("EMA/MHRA reliance (post-2021)", 5),
                "MHRA decision", NA, NA, NA),
  us_price = c(475000, 373000, 850000, 2800000, 2125000, 4250000, 373000,
               3000000, 419500, 410300, 465000, 2900000, 3500000, 2200000,
               3100000, 3500000, 3200000),
  us_price_year = c(2017L, 2017L, 2017L, 2022L, 2019L, 2024L, 2020L, 2022L,
                    2021L, 2021L, 2022L, 2023L, 2022L, 2023L, 2023L, 2024L, 2023L),
  stringsAsFactors = FALSE
)

# --- Row builder -------------------------------------------------------------
rows <- list()

add <- function(product_id, country, approved = TRUE, regulatory_anchor = NA,
                regulatory_date = NA, hta_body = NA, hta_date = NA,
                hta_rating_raw = NA, hta_rating_ordinal = NA,
                hta_recommendation = NA, reimbursement_date = NA,
                first_access_date = NA, access_status = NA,
                list_price_lcu = NA, currency = NA, price_basis = NA,
                price_year = NA, price_confidential = FALSE, price_notes = NA,
                source_primary = NA, source_url = NA, source_secondary = NA,
                verification = "not_located") {
  rows[[length(rows) + 1]] <<- data.frame(
    product_id = product_id,
    country = country,
    approved = approved,
    regulatory_anchor = regulatory_anchor,
    regulatory_date = as_date(regulatory_date),
    hta_body = hta_body,
    hta_date = as_date(hta_date),
    hta_rating_raw = hta_rating_raw,
    hta_rating_ordinal = hta_rating_ordinal,
    hta_recommendation = hta_recommendation,
    reimbursement_date = as_date(reimbursement_date),
    first_access_date = as_date(first_access_date),
    access_status = access_status,
    list_price_lcu = list_price_lcu,
    currency = currency,
    price_basis = price_basis,
    price_year = as.integer(price_year),
    price_confidential = price_confidential,
    price_notes = price_notes,
    source_primary = source_primary,
    source_url = source_url,
    source_secondary = source_secondary,
    verification = verification,
    stringsAsFactors = FALSE
  )
}

# --- United States -----------------------------------------------------------
for (i in seq_len(nrow(products))) {
  p <- products[i, ]
  add(
    product_id = p$product_id, country = "United States",
    approved = TRUE, regulatory_anchor = "FDA",
    regulatory_date = p$us_date,
    hta_body = "None (FDA/CBER)",
    hta_recommendation = "No national HTA gate; coverage determined by payers",
    first_access_date = p$us_date,
    access_status = "Marketed (FDA approval)",
    list_price_lcu = p$us_price, currency = "USD",
    price_basis = "US wholesale acquisition cost (WAC) at launch, per course",
    price_year = p$us_price_year,
    price_notes = ifelse(p$product_id == "libmeldy",
                         "US brand is Lenmeldy; WAC is per course. Same active substance as EU Libmeldy.",
                         "WAC is a list price before discounts, rebates and 340B/Medicaid adjustments."),
    source_primary = "FDA CBER approved cellular and gene therapy products; manufacturer launch announcement",
    source_url = FDA,
    source_secondary = "Company press release / trade press (Fierce Pharma, BioPharma Dive) at launch",
    verification = "verified_secondary"
  )
}

# --- Germany -----------------------------------------------------------------
add("kymriah", "Germany", regulatory_anchor = "EMA", regulatory_date = "2018-08-23",
    hta_body = "G-BA", hta_rating_raw = "Non-quantifiable additional benefit",
    hta_rating_ordinal = 2,
    hta_recommendation = "AMNOG benefit assessment; reimbursement at free price during first year",
    reimbursement_date = "2018-08-23", first_access_date = "2018-08-23",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 320000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)",
    price_year = 2018,
    price_notes = "Launch price; post-AMNOG price fell to EUR 239,000 by 2023-2024.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster",
    source_url = ISPOR25, source_secondary = "GlobalData POLI / AMNOG database (ISPOR 2024 CAR-T poster)",
    verification = "verified_secondary")

add("yescarta", "Germany", regulatory_anchor = "EMA", regulatory_date = "2018-08-23",
    hta_body = "G-BA", hta_rating_raw = "Additional benefit (not individually verified)",
    hta_rating_ordinal = NA,
    hta_recommendation = "AMNOG benefit assessment; reimbursement at free price during first year",
    reimbursement_date = "2018-08-23", first_access_date = "2018-08-23",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 327000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)", price_year = 2018,
    price_notes = "Launch price; post-AMNOG price EUR 272,000 by 2023-2024.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "GlobalData POLI (ISPOR 2024 CAR-T poster)", verification = "verified_secondary")

add("luxturna", "Germany", regulatory_anchor = "EMA", regulatory_date = "2018-11-22",
    hta_body = "G-BA", hta_date = "2022-09-15",
    hta_rating_raw = "Considerable additional benefit",
    hta_rating_ordinal = 3, hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2018-11-22", first_access_date = "2018-11-22",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 690000, currency = "EUR",
    price_basis = "Ex-factory launch price, two packs (both eyes)", price_year = 2019,
    price_notes = "Two packs; per-eye price approximately EUR 345,000.",
    source_primary = "ISPOR 2024 HTA/pricing poster; 2023 health-policy price table",
    source_url = ISPOR24, source_secondary = "G-BA resolution 2022-09-15",
    verification = "verified_secondary")

add("zynteglo", "Germany", regulatory_anchor = "EMA", regulatory_date = "2019-05-29",
    hta_body = "G-BA", hta_rating_raw = "Non-quantifiable additional benefit",
    hta_rating_ordinal = 2,
    hta_recommendation = "AMNOG assessment; manufacturer withdrew from Germany in 2021",
    first_access_date = "2019-05-29",
    access_status = "Withdrawn from Germany (2021) after pricing dispute",
    list_price_lcu = 1575000, currency = "EUR",
    price_basis = "Ex-factory launch price", price_year = 2019,
    price_notes = "bluebird bio announced a EUR 1.575m launch price; a secondary table reports approximately EUR 1.93m. Discrepancy flagged; the lower, company-announced figure is used.",
    source_primary = "Labiotech / BioPharma Dive reporting of bluebird bio launch price",
    source_url = "https://www.labiotech.eu/best-biotech/most-expensive-drugs-biopharma",
    source_secondary = "2023 health-policy price table (EUR ~1.93m)",
    verification = "single_source")

add("zolgensma", "Germany", regulatory_anchor = "EMA", regulatory_date = "2020-05-18",
    hta_body = "G-BA", hta_date = "2021-11-01",
    hta_rating_raw = "No additional benefit",
    hta_rating_ordinal = 0,
    hta_recommendation = "AMNOG reassessment after orphan sales threshold; no added benefit vs appropriate comparator",
    reimbursement_date = "2020-05-18", first_access_date = "2020-05-18",
    access_status = "Reimbursed (AMNOG; routine-practice data collection)",
    list_price_lcu = 1945000, currency = "EUR",
    price_basis = "Hospital/ex-factory launch price (Lauer-Taxe)", price_year = 2020,
    price_notes = "Launch price; negotiated reimbursement price EUR 1,385,000 (29% cumulative rebate).",
    source_primary = "NAVLIN/Pharmaphorum launch price; Ecker + Ecker AMNOG case note",
    source_url = "https://www.ecker-ecker.de/fach-posts-bei-linkedin/atmp/atmps-in-germany-zolgensma-r",
    source_secondary = "ISPOR 2025 poster (no German price shown for Zolgensma)",
    verification = "verified_secondary")

add("libmeldy", "Germany", regulatory_anchor = "EMA", regulatory_date = "2020-12-17",
    hta_body = "G-BA", hta_rating_raw = "Non-quantifiable additional benefit",
    hta_rating_ordinal = 2,
    hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2020-12-17", first_access_date = "2020-12-17",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 2875000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)", price_year = 2021,
    price_notes = "Launched May 2021; price reduced to EUR 2,125,000 after negotiation.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "ISPOR 2024 HTA/pricing poster", verification = "verified_secondary")

add("tecartus", "Germany", regulatory_anchor = "EMA", regulatory_date = "2020-12-14",
    hta_body = "G-BA", hta_rating_raw = "Considerable additional benefit",
    hta_rating_ordinal = 3, hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2020-12-14", first_access_date = "2020-12-14",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 282000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)", price_year = 2022,
    price_notes = "Launch price EUR 282,000 per GlobalData POLI. A separate 2023 table reports EUR 360,000; discrepancy flagged and the GlobalData figure used.",
    source_primary = "ISPOR 2024 CAR-T price-evolution poster (GlobalData POLI)",
    source_url = "https://www.ispor.org/docs/default-source/euro2024/isporeurope2024cullenhta362poster144884-pdf.pdf",
    source_secondary = "ISPOR 2024 HTA/pricing poster (considerable added benefit)",
    verification = "verified_secondary")

add("skysona", "Germany", regulatory_anchor = "EMA", regulatory_date = "2021-07-16",
    hta_recommendation = "No G-BA assessment; product never launched in Germany",
    access_status = "Not launched; EU marketing authorisation withdrawn November 2021",
    price_notes = "No German list price; no HTA procedure. Structural missingness, not a zero price.",
    source_primary = "Ecker + Ecker AMNOG case note; EMA withdrawal notice",
    source_url = "https://www.ecker-ecker.de/fach-posts-bei-linkedin/atmp/atmps-in-germany-skysona-r",
    source_secondary = "BioPharma Dive (bluebird withdraws Skysona from Europe)",
    verification = "verified_secondary")

add("abecma", "Germany", regulatory_anchor = "EMA", regulatory_date = "2021-08-18",
    hta_body = "G-BA", hta_date = "2022-06-16",
    hta_rating_raw = "Non-quantifiable additional benefit",
    hta_rating_ordinal = 2,
    hta_recommendation = "AMNOG benefit assessment (2022); reassessed as no additional benefit in 2024",
    reimbursement_date = "2021-08-18", first_access_date = "2021-08-18",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 350000, currency = "EUR",
    price_basis = "Hospital purchase price / ex-factory launch price", price_year = 2022,
    price_notes = "Launch price EUR 350,000; negotiated price EUR 240,000 by 2024.",
    source_primary = "G-BA dossier and Ecker + Ecker AMNOG case note",
    source_url = "https://www.ecker-ecker.de/fach-posts-bei-linkedin/atmp/atmps-in-germany-abecma-r",
    source_secondary = "GlobalData POLI (ISPOR 2024 CAR-T poster)",
    verification = "verified_primary")

add("breyanzi", "Germany", regulatory_anchor = "EMA", regulatory_date = "2022-04-04",
    hta_body = "G-BA", hta_rating_raw = "Additional benefit (not individually verified)",
    hta_rating_ordinal = NA, hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2022-04-04", first_access_date = "2022-04-04",
    access_status = "Reimbursed (AMNOG free-pricing period); later withdrawn from German market",
    list_price_lcu = 345000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)", price_year = 2022,
    price_notes = "Launch price; post-AMNOG price EUR 233,750 by 2024.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "GlobalData POLI (ISPOR 2024 CAR-T poster)", verification = "verified_secondary")

add("carvykti", "Germany", regulatory_anchor = "EMA", regulatory_date = "2022-05-25",
    hta_body = "G-BA", hta_rating_raw = "Additional benefit (not individually verified)",
    hta_rating_ordinal = NA, hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2022-05-25", first_access_date = "2022-05-25",
    access_status = "Reimbursed (AMNOG free-pricing period)",
    list_price_lcu = 420000, currency = "EUR",
    price_basis = "Ex-factory launch price (Lauer-Taxe)", price_year = 2023,
    price_notes = "Launch price; post-AMNOG price EUR 285,000.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "GlobalData POLI (ISPOR 2024 CAR-T poster)", verification = "verified_secondary")

add("roctavian", "Germany", regulatory_anchor = "EMA", regulatory_date = "2022-08-24",
    hta_body = "G-BA", hta_rating_raw = "Non-quantifiable additional benefit",
    hta_rating_ordinal = 2, hta_recommendation = "AMNOG benefit assessment",
    reimbursement_date = "2022-08-24", first_access_date = "2022-08-24",
    access_status = "Reimbursed under outcomes-based agreement; withdrawn 2026",
    currency = "EUR", price_confidential = TRUE,
    price_notes = "No public German list price located. BioMarin referred to a European net price of approximately EUR 1.5m; net prices are outside this study's list-price definition.",
    source_primary = "NAVLIN GKV-Spitzenverband report; BioMarin statements",
    source_url = "https://www.navlindaily.com/article/17336/gkv-spitzenverband-discusses-payment-models-following-hemgenix-roctavian-approvals",
    source_secondary = "ISPOR 2024 HTA/pricing poster (non-quantifiable benefit)",
    verification = "not_located")

add("hemgenix", "Germany", regulatory_anchor = "EMA", regulatory_date = "2023-02-20",
    hta_body = "G-BA", hta_rating_raw = "Additional benefit (not individually verified)",
    hta_rating_ordinal = NA, hta_recommendation = "AMNOG benefit assessment; pay-for-performance negotiation",
    reimbursement_date = "2023-02-20", first_access_date = "2023-02-20",
    access_status = "Reimbursed under pay-for-performance agreement",
    list_price_lcu = 2500000, currency = "EUR",
    price_basis = "Ex-factory list price", price_year = 2023,
    price_notes = "List price EUR 2.5m; initial P4P payment approximately EUR 350,000 plus annual instalments.",
    source_primary = "Pharmazeutische Zeitung ATMP cost table (2025/2026)",
    source_url = "https://www.pharmazeutische-zeitung.de/heilen-statt-behandeln-167605/seite/alle",
    source_secondary = "GKV-Spitzenverband / NAVLIN",
    verification = "verified_secondary")

add("casgevy", "Germany", regulatory_anchor = "EMA", regulatory_date = "2024-02-09",
    hta_body = "G-BA", hta_rating_raw = "Assessment pending/not located",
    hta_rating_ordinal = NA, hta_recommendation = "AMNOG assessment and P4P negotiation",
    reimbursement_date = "2024-02-09", first_access_date = "2024-02-09",
    access_status = "Reimbursed; pay-for-performance terms under negotiation",
    currency = "EUR", price_confidential = TRUE,
    price_notes = "No single public German list price located; trade press reports a range of approximately EUR 1.5m-2.2m. Coded confidential rather than imputed.",
    source_primary = "Pharmazeutische Zeitung ATMP cost table", source_url = "https://www.pharmazeutische-zeitung.de/heilen-statt-behandeln-167605/seite/alle",
    source_secondary = "Vertex investor communications",
    verification = "not_located")

add("lyfgenia", "Germany", approved = FALSE,
    access_status = "Not approved in the EU (no EMA marketing authorisation)",
    price_notes = "Structural missingness: US-only product.",
    source_primary = "EMA / FDA approval records", source_url = EMA("lyfgenia"),
    verification = "verified_primary")

add("beqvez", "Germany", regulatory_anchor = "EMA", regulatory_date = "2024-07-24",
    hta_body = "G-BA", hta_recommendation = "AMNOG assessment not completed before withdrawal",
    access_status = "Launched 2024; withdrawn from market 2025 without commercial patients",
    currency = "EUR", price_confidential = TRUE,
    price_notes = "No public German list price located. Product withdrawn in 2025.",
    source_primary = "EMA withdrawal notice; trade press",
    source_url = "https://www.ema.europa.eu/en/medicines/human/EPAR/beqvez",
    source_secondary = "Pfizer announcement (Feb 2025)",
    verification = "not_located")

add("elevidys", "Germany", approved = FALSE,
    access_status = "Not approved in the EU (EMA marketing authorisation refused/withdrawn)",
    price_notes = "Structural missingness: US-only product.",
    source_primary = "EMA / FDA approval records", source_url = EMA("elevidys"),
    verification = "verified_primary")

# --- France ------------------------------------------------------------------
add("kymriah", "France", regulatory_anchor = "EMA", regulatory_date = "2018-08-23",
    hta_body = "HAS", hta_rating_raw = "ASMR III (ALL); ASMR IV (DLBCL)",
    hta_rating_ordinal = 3, hta_recommendation = "Reimbursed (SMR important)",
    reimbursement_date = "2019-08-13", first_access_date = "2019-08-13",
    access_status = "Reimbursed (CEPS price; outcomes-based payment)",
    list_price_lcu = 297666, currency = "EUR",
    price_basis = "CEPS-set hospital price (prix fabricant)", price_year = 2019,
    price_notes = "CEPS price EUR 297,666 plus EUR 15,000 hospital add-on. The ATU/interim price was EUR 320,000; the CEPS price is used per protocol.",
    source_primary = "Ronco et al. 2021, J Pharm Policy Pract (Table 3); Universite de Strasbourg thesis (2024)",
    source_url = "https://pmc.ncbi.nlm.nih.gov/articles/PMC7980570/",
    source_secondary = "NAVLIN (France approves hospital reimbursement for Kymriah)",
    verification = "verified_secondary")

add("yescarta", "France", regulatory_anchor = "EMA", regulatory_date = "2018-08-23",
    hta_body = "HAS", hta_rating_raw = "ASMR III",
    hta_rating_ordinal = 3, hta_recommendation = "Reimbursed (SMR important)",
    reimbursement_date = "2019-07-08", first_access_date = "2019-07-08",
    access_status = "Reimbursed (CEPS price; outcomes-based payment)",
    list_price_lcu = 327000, currency = "EUR",
    price_basis = "CEPS-set hospital price (prix fabricant)", price_year = 2019,
    price_notes = "CEPS price EUR 327,000 plus EUR 15,000 hospital add-on. The ATU/interim price was EUR 350,000; the CEPS price is used per protocol.",
    source_primary = "Ronco et al. 2021, J Pharm Policy Pract (Table 3); Egora (CEPS agreement, 8 July 2019)",
    source_url = "https://pmc.ncbi.nlm.nih.gov/articles/PMC7980570/",
    source_secondary = "ISPOR 2025 poster (EUR 350,000 ATU price, 30 Jul 2018)",
    verification = "verified_secondary")

add("luxturna", "France", regulatory_anchor = "EMA", regulatory_date = "2018-11-22",
    hta_body = "HAS", hta_date = "2019-04-03",
    hta_rating_raw = "ASMR II; SMR important",
    hta_rating_ordinal = 4, hta_recommendation = "Reimbursed",
    access_status = "Reimbursed; CEPS price decision date not located",
    list_price_lcu = 613410, currency = "EUR",
    price_basis = "Public launch price per patient (both eyes)", price_year = 2019,
    price_notes = "Price per patient. CEPS decision date not located; first_access_date left missing rather than proxied.",
    source_primary = "HAS Transparency Committee opinion, 3 April 2019",
    source_url = "https://www.has-sante.fr/jcms/c_2964759/fr/luxturna-voretigene-neparvovec",
    source_secondary = "2023 health-policy price table (FR EUR 613,410/patient)",
    verification = "verified_secondary")

add("zynteglo", "France", regulatory_anchor = "EMA", regulatory_date = "2019-05-29",
    hta_body = "HAS", hta_rating_raw = "ASMR III",
    hta_rating_ordinal = 3,
    hta_recommendation = "No reimbursement; manufacturer withdrew from Europe",
    access_status = "Not reimbursed; EU authorisation withdrawn 2022",
    price_notes = "No French list price; product withdrawn before CEPS agreement.",
    source_primary = "BioPharma Dive / bluebird bio withdrawal statements",
    source_url = "https://www.biopharmadive.com/news/bluebird-withdraw-gene-therapy-europe-skysona/608666/",
    source_secondary = "Ronco et al. 2021 (ASMR III, price not agreed)",
    verification = "verified_secondary")

add("zolgensma", "France", regulatory_anchor = "EMA", regulatory_date = "2020-05-18",
    hta_body = "HAS", hta_date = "2020-12-15",
    hta_rating_raw = "ASMR III (SMA type I/pre-symptomatic); ASMR V (type II)",
    hta_rating_ordinal = 3, hta_recommendation = "Favourable for reimbursement; early access",
    reimbursement_date = "2019-07-25", first_access_date = "2019-07-25",
    access_status = "Early access (ATU) from July 2019; CEPS price not confirmed",
    list_price_lcu = 1945000, currency = "EUR",
    price_basis = "ATU/early-access maximum price (not a CEPS-confirmed price)", price_year = 2019,
    price_notes = "ATU price reported as EUR 1.945m; CEPS price not published. Negative delay reflects pre-authorisation early access. Flagged as a proxy price basis.",
    source_primary = "Les Echos (25 Sep 2019); HAS opinion December 2020",
    source_url = "https://www.lesechos.fr/economie-france/social/therapie-genique-une-piqre-facturee-2-millions-deuros-1134553",
    source_secondary = "Institut de Myologie summary of HAS opinion",
    verification = "proxy")

add("libmeldy", "France", regulatory_anchor = "EMA", regulatory_date = "2020-12-17",
    hta_body = "HAS", hta_rating_raw = "ASMR not individually located",
    hta_rating_ordinal = NA, hta_recommendation = "Reimbursed",
    reimbursement_date = "2023-09-01", first_access_date = "2023-09-01",
    access_status = "Reimbursed",
    list_price_lcu = 2875000, currency = "EUR",
    price_basis = "CEPS/launch price", price_year = 2023,
    price_notes = "Price aligned with German launch price.",
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "HAS reimbursement records",
    verification = "verified_secondary")

add("tecartus", "France", regulatory_anchor = "EMA", regulatory_date = "2020-12-14",
    hta_body = "HAS", hta_rating_raw = "ASMR not individually located",
    hta_rating_ordinal = NA, hta_recommendation = "Reimbursed",
    access_status = "Reimbursed; price confidential",
    currency = "EUR", price_confidential = TRUE,
    price_notes = "French price reported as confidential in the 2023 health-policy table; no public list price.",
    source_primary = "2023 health-policy price table; HAS records",
    source_url = "https://www.has-sante.fr/",
    source_secondary = "ISPOR 2025 poster (France not listed for Tecartus)",
    verification = "verified_secondary")

add("skysona", "France", regulatory_anchor = "EMA", regulatory_date = "2021-07-16",
    hta_recommendation = "No reimbursement assessment; product never launched",
    access_status = "Not launched; EU authorisation withdrawn November 2021",
    price_notes = "Structural missingness: no French launch.",
    source_primary = "BioPharma Dive (bluebird withdraws Skysona from Europe)",
    source_url = "https://www.biopharmadive.com/news/bluebird-withdraw-gene-therapy-europe-skysona/608666/",
    verification = "verified_secondary")

add("abecma", "France", regulatory_anchor = "EMA", regulatory_date = "2021-08-18",
    hta_body = "HAS", hta_rating_raw = "ASMR not individually located",
    hta_rating_ordinal = NA, hta_recommendation = "Reimbursed",
    access_status = "Reimbursed; price and CEPS date confidential/not located",
    currency = "EUR", price_confidential = TRUE,
    price_notes = "CEPS price not public. ATU price of EUR 350,000 was published in 2021 but is not the CEPS price; coded confidential.",
    source_primary = "NAVLIN (France ATU price list, July 2021)",
    source_url = "https://www.navlindaily.com/article/8133/france-publishes-list-of-updated-atu-drug-prices",
    source_secondary = "HAS records",
    verification = "not_located")

add("breyanzi", "France", regulatory_anchor = "EMA", regulatory_date = "2022-04-04",
    hta_body = "HAS", hta_rating_raw = "ASMR not individually located",
    hta_rating_ordinal = NA, hta_recommendation = "Reimbursed",
    reimbursement_date = "2023-01-26", first_access_date = "2023-01-26",
    access_status = "Reimbursed",
    list_price_lcu = 345000, currency = "EUR",
    price_basis = "CEPS/launch price", price_year = 2023,
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "HAS reimbursement records", verification = "verified_secondary")

add("carvykti", "France", regulatory_anchor = "EMA", regulatory_date = "2022-05-25",
    hta_body = "HAS", hta_rating_raw = "ASMR not individually located",
    hta_rating_ordinal = NA, hta_recommendation = "Reimbursed",
    reimbursement_date = "2023-09-01", first_access_date = "2023-09-01",
    access_status = "Reimbursed",
    list_price_lcu = 420000, currency = "EUR",
    price_basis = "CEPS/launch price", price_year = 2023,
    source_primary = "ISPOR 2025 multi-country ATMP pricing poster", source_url = ISPOR25,
    source_secondary = "HAS reimbursement records", verification = "verified_secondary")

add("roctavian", "France", regulatory_anchor = "EMA", regulatory_date = "2022-08-24",
    hta_body = "HAS", hta_recommendation = "Not reimbursed",
    access_status = "Not reimbursed in France (company limited launch to US, Germany, Italy)",
    price_notes = "No French list price; no reimbursement.",
    source_primary = "BioMarin withdrawal/restricted-launch statements",
    source_url = "https://www.drozdogan.com/en/first-gene-therapy-for-adults-with-severe-hemophilia-a-receives-fda-approval-roctavian",
    verification = "verified_secondary")

add("hemgenix", "France", regulatory_anchor = "EMA", regulatory_date = "2023-02-20",
    hta_body = "HAS", hta_recommendation = "Reimbursement status not located",
    access_status = "Reimbursement status not located within study window",
    price_notes = "No public French list price located.",
    source_primary = "HAS records (search not conclusive)",
    source_url = "https://www.has-sante.fr/",
    verification = "not_located")

add("casgevy", "France", regulatory_anchor = "EMA", regulatory_date = "2024-02-09",
    hta_body = "HAS", hta_recommendation = "Reimbursement pending at end-2024",
    access_status = "Not reimbursed by 31 December 2024 (post-window decision)",
    price_notes = "No 2024 French list price; coded missing rather than using a 2025 price.",
    source_primary = "HAS records; Vertex communications",
    source_url = "https://www.has-sante.fr/",
    verification = "verified_secondary")

add("lyfgenia", "France", approved = FALSE,
    access_status = "Not approved in the EU (no EMA marketing authorisation)",
    price_notes = "Structural missingness: US-only product.",
    source_primary = "EMA / FDA approval records", source_url = EMA("lyfgenia"),
    verification = "verified_primary")

add("beqvez", "France", regulatory_anchor = "EMA", regulatory_date = "2024-07-24",
    hta_body = "HAS", hta_recommendation = "Not reimbursed",
    access_status = "Not reimbursed; withdrawn from market 2025",
    price_notes = "No French list price.",
    source_primary = "EMA withdrawal notice; Pfizer announcement",
    source_url = "https://www.ema.europa.eu/en/medicines/human/EPAR/beqvez",
    verification = "verified_secondary")

add("elevidys", "France", approved = FALSE,
    access_status = "Not approved in the EU (no EMA marketing authorisation)",
    price_notes = "Structural missingness: US-only product.",
    source_primary = "EMA / FDA approval records", source_url = EMA("elevidys"),
    verification = "verified_primary")

# --- England -----------------------------------------------------------------
add("kymriah", "England", regulatory_anchor = "EMA decision (pre-2021)",
    regulatory_date = "2018-08-23",
    hta_body = "NICE", hta_date = "2018-12-21",
    hta_rating_raw = "Recommended (TA554)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2018-12-21", first_access_date = "2018-12-21",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 282000, currency = "GBP",
    price_basis = "NICE-stated list price per infusion",
    price_year = 2018,
    price_notes = "Commercial arrangement discount confidential.",
    source_primary = "NICE TA554 (published 21 Dec 2018); TA975 price statement",
    source_url = NICE("ta975"),
    source_secondary = "NICE TA554",
    verification = "verified_primary")

add("yescarta", "England", regulatory_anchor = "EMA decision (pre-2021)",
    regulatory_date = "2018-08-23",
    hta_body = "NICE", hta_date = "2019-01-23",
    hta_rating_raw = "Recommended (TA559)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2019-01-23", first_access_date = "2019-01-23",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 280451, currency = "GBP",
    price_basis = "NICE-stated list price per infusion",
    price_year = 2019,
    price_notes = "Commercial arrangement discount confidential.",
    source_primary = "NICE TA872 price statement (list price GBP 280,451)",
    source_url = NICE("ta872"),
    source_secondary = "NICE TA559 (published 23 Jan 2019)",
    verification = "verified_primary")

add("luxturna", "England", regulatory_anchor = "EMA decision (pre-2021)",
    regulatory_date = "2018-11-22",
    hta_body = "NICE", hta_date = "2019-10-09",
    hta_rating_raw = "Recommended (HST11)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2019-10-09", first_access_date = "2019-10-09",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 613410, currency = "GBP",
    price_basis = "NICE-stated list price per patient (both eyes)",
    price_year = 2019,
    price_notes = "List price per patient, excluding VAT; commercial arrangement confidential.",
    source_primary = "NICE HST11 price statement",
    source_url = NICE("hst11"),
    source_secondary = "NICE guidance publication date 9 Oct 2019",
    verification = "verified_primary")

add("zynteglo", "England", approved = FALSE,
    regulatory_anchor = "EMA decision (pre-2021)", regulatory_date = "2019-05-29",
    hta_recommendation = "Discontinued; UK marketing application withdrawn",
    access_status = "Not launched; UK MAA withdrawn and EU authorisation withdrawn",
    price_notes = "Structural missingness: no UK launch.",
    source_primary = "BioPharma Dive / bluebird bio statements",
    source_url = "https://www.biopharmadive.com/news/bluebird-withdraw-gene-therapy-europe-skysona/608666/",
    verification = "verified_secondary")

add("zolgensma", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2020-05-18",
    hta_body = "NICE", hta_date = "2021-07-07",
    hta_rating_raw = "Recommended (HST15)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2021-07-07", first_access_date = "2021-07-07",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 1795000, currency = "GBP",
    price_basis = "NICE-stated list price", price_year = 2021,
    price_notes = "Commercial arrangement discount confidential.",
    source_primary = "NICE HST15 price statement",
    source_url = NICE("hst15"),
    source_secondary = "NICE guidance published 7 Jul 2021",
    verification = "verified_primary")

add("libmeldy", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2020-12-17",
    hta_body = "NICE", hta_date = "2022-03-28",
    hta_rating_raw = "Recommended (HST18)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2022-03-28", first_access_date = "2022-03-28",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 2875000, currency = "GBP",
    price_basis = "NICE-stated list price", price_year = 2022,
    price_notes = "Commercial arrangement discount confidential.",
    source_primary = "NICE HST18 price statement",
    source_url = NICE("hst18"),
    source_secondary = "NICE guidance published 28 Mar 2022",
    verification = "verified_primary")

add("tecartus", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2020-12-14",
    hta_body = "NICE", hta_date = "2021-02-24",
    hta_rating_raw = "Recommended (TA677)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2021-02-24", first_access_date = "2021-02-24",
    access_status = "Recommended and funded by NHS England",
    currency = "GBP", price_confidential = TRUE,
    price_notes = "NICE TA677 states the price was submitted as commercial in confidence. A secondary table reports GBP 316,118; not used because NICE did not publish it.",
    source_primary = "NICE TA677",
    source_url = NICE("ta677"),
    source_secondary = "2023 health-policy price table (GBP 316,118, not NICE-confirmed)",
    verification = "verified_primary")

add("skysona", "England", approved = FALSE,
    regulatory_anchor = "EMA/MHRA reliance (post-2021)", regulatory_date = "2021-07-16",
    hta_recommendation = "Discontinued",
    access_status = "Not launched; UK MAA withdrawn and EU authorisation withdrawn",
    price_notes = "Structural missingness: no UK launch.",
    source_primary = "BioPharma Dive / bluebird bio statements",
    source_url = "https://www.biopharmadive.com/news/bluebird-withdraw-gene-therapy-europe-skysona/608666/",
    verification = "verified_secondary")

add("abecma", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2021-08-18",
    hta_body = "NICE", hta_rating_raw = "Terminated appraisal (TA936; TA1084)",
    hta_rating_ordinal = NA, hta_recommendation = "Terminated appraisal",
    access_status = "No NICE recommendation; appraisal terminated",
    price_notes = "No NICE-stated list price.",
    source_primary = "NICE terminated appraisal TA936 and TA1084",
    source_url = "https://www.nice.org.uk/guidance/terminated/ta936",
    source_secondary = "NICE search results",
    verification = "verified_primary")

add("breyanzi", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2022-04-04",
    hta_body = "NICE", hta_date = "2026-06-03",
    hta_rating_raw = "Recommended (TA1159; outside 2024 window)",
    hta_rating_ordinal = 2,
    hta_recommendation = "Recommended in 2026, after the study window",
    access_status = "Not reimbursed within 2018-2024 window; recommended 2026",
    list_price_lcu = 297000, currency = "GBP",
    price_basis = "NICE-stated list price per infusion", price_year = 2024,
    price_notes = "NICE price statement from 2026; price year coded 2024 (last study year) so the value can be deflated with 2024 CPI. Flagged in sensitivity and data-quality appendix.",
    source_primary = "NICE TA1159 (published 3 June 2026)",
    source_url = NICE("ta1159"),
    source_secondary = "ISPOR 2025 poster (UK launch price March 2025)",
    verification = "verified_primary")

add("carvykti", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2022-05-25",
    hta_body = "NICE", hta_rating_raw = "Terminated appraisal (TA889)",
    hta_rating_ordinal = NA, hta_recommendation = "Terminated appraisal",
    access_status = "No NICE recommendation; appraisal terminated",
    price_notes = "UK company list price first reported January 2025, outside the 2018-2024 price window; coded missing.",
    source_primary = "NICE terminated appraisal TA889",
    source_url = "https://www.nice.org.uk/guidance/terminated/ta889",
    source_secondary = "ISPOR 2025 poster (UK EUR 435,525.56, 28 Jan 2025)",
    verification = "verified_primary")

add("roctavian", "England", approved = NA,
    regulatory_anchor = "EMA/MHRA reliance (post-2021)", regulatory_date = "2022-08-24",
    hta_recommendation = "No NICE appraisal",
    access_status = "No NICE appraisal; not reimbursed",
    price_notes = "UK marketing authorisation not verified; no NICE guidance.",
    source_primary = "NICE guidance search (no result)",
    source_url = "https://www.nice.org.uk/search?q=Roctavian",
    verification = "not_located")

add("hemgenix", "England", regulatory_anchor = "EMA/MHRA reliance (post-2021)",
    regulatory_date = "2023-02-20",
    hta_body = "NICE", hta_date = "2024-07-24",
    hta_rating_raw = "Recommended (TA989)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended",
    reimbursement_date = "2024-07-24", first_access_date = "2024-07-24",
    access_status = "Recommended and funded by NHS England",
    list_price_lcu = 2600000, currency = "GBP",
    price_basis = "NICE-stated list price per treatment", price_year = 2024,
    price_notes = "Commercial arrangement discount confidential.",
    source_primary = "NICE TA989 price statement",
    source_url = NICE("ta989"),
    source_secondary = "NICE guidance published 24 Jul 2024",
    verification = "verified_primary")

add("casgevy", "England", regulatory_anchor = "MHRA decision",
    regulatory_date = "2023-11-16",
    hta_body = "NICE", hta_date = "2024-09-11",
    hta_rating_raw = "Recommended (TA1003 TDT; TA1044 SCD 2025)",
    hta_rating_ordinal = 2, hta_recommendation = "Recommended with managed access",
    reimbursement_date = "2024-09-11", first_access_date = "2024-09-11",
    access_status = "Recommended with managed access (TDT first; SCD from Feb 2025)",
    list_price_lcu = 1651000, currency = "GBP",
    price_basis = "NICE-stated list price per course", price_year = 2023,
    price_notes = "Commercial arrangement discount confidential. First access date uses the TDT recommendation (Sep 2024).",
    source_primary = "NICE TA1003/TA1044 price statements",
    source_url = NICE("ta1003"),
    source_secondary = "Vertex/NHS England reimbursement announcement (31 Jan 2025)",
    verification = "verified_primary")

add("lyfgenia", "England", approved = FALSE,
    access_status = "Not approved in the UK (no MHRA marketing authorisation)",
    price_notes = "Structural missingness: US-only product.",
    source_primary = "MHRA / FDA approval records", source_url = "https://www.gov.uk/government/organisations/medicines-and-healthcare-products-regulatory-agency",
    verification = "verified_primary")

add("beqvez", "England", approved = NA,
    regulatory_anchor = "EMA/MHRA reliance (post-2021)", regulatory_date = "2024-07-24",
    hta_recommendation = "Discontinued appraisal (GID-TA11117)",
    access_status = "Discontinued; product withdrawn 2025",
    price_notes = "No UK list price.",
    source_primary = "NICE discontinued appraisal GID-TA11117",
    source_url = "https://www.nice.org.uk/guidance/discontinued/gid-ta11117",
    verification = "verified_primary")

add("elevidys", "England", approved = FALSE,
    access_status = "Not approved in the UK; NICE appraisal awaiting development",
    price_notes = "Structural missingness: no UK launch.",
    source_primary = "NICE awaiting-development record GID-TA11437",
    source_url = "https://www.nice.org.uk/guidance/awaiting-development/gid-ta11437",
    verification = "verified_primary")

# --- Assemble ----------------------------------------------------------------
extraction <- do.call(rbind, rows)
extraction <- merge(products[, c("product_id", "brand", "inn", "modality", "manufacturer")],
                    extraction, by = "product_id", all.x = TRUE, sort = FALSE)
extraction$country <- factor(extraction$country,
                             levels = c("United States", "Germany", "France", "England"))
extraction <- extraction[order(extraction$product_id, extraction$country), ]
row.names(extraction) <- NULL
extraction <- extraction[, c("product_id", "brand", "inn", "modality", "manufacturer",
                             "country", "approved", "regulatory_anchor", "regulatory_date",
                             "hta_body", "hta_date", "hta_rating_raw", "hta_rating_ordinal",
                             "hta_recommendation", "reimbursement_date", "first_access_date",
                             "access_status", "list_price_lcu", "currency", "price_basis",
                             "price_year", "price_confidential", "price_notes",
                             "source_primary", "source_url", "source_secondary", "verification")]

stopifnot(nrow(extraction) == 68)
write.csv(extraction, "data/raw/atmp_extraction.csv", row.names = FALSE, na = "")

# --- Source register ---------------------------------------------------------
source_register <- data.frame(
  source_id = c("S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08",
                "S09", "S10", "S11", "S12", "S13", "S14", "S15", "S16"),
  source_type = c("Regulatory", "Regulatory", "HTA", "HTA", "HTA", "HTA",
                  "Price database/poster", "Price database/poster", "Peer-reviewed",
                  "Peer-reviewed", "Government/HTA", "Government/HTA",
                  "Trade press", "Trade press", "Trade press", "Statistical"),
  citation = c(
    "FDA CBER, Approved Cellular and Gene Therapy Products (accessed 2026-11-14)",
    "European Medicines Agency, EPARs and CAT meeting reports (accessed 2026-11-14)",
    "NICE guidance TA554, TA559, TA677, TA872, TA975, TA989, TA1003, TA1044, TA1159, HST11, HST15, HST18",
    "G-BA benefit assessment resolutions and Ecker + Ecker AMNOG case notes",
    "HAS Transparency Committee opinions (Luxturna, Zolgensma and others)",
    "NICE terminated/discontinued/awaiting-development records (TA889, TA936, TA1084, GID-TA11117, GID-TA11437)",
    "Rehkopf et al. ISPOR Europe 2025 poster HTA163: launch and current ex-factory prices of seven ATMPs",
    "Ng & Patel, ISPOR Europe 2024 poster HTA21: HTA outcomes and pricing for ATMPs in Germany, France and the UK",
    "Ronco et al. (2021) J Pharm Policy Pract 14:30, Table 3",
    "Kiefer (2024) Universite de Strasbourg thesis on financing expensive medicines in southern Europe",
    "Les Echos (25 Sep 2019), Zolgensma ATU price",
    "NAVLIN Daily (2021-2023) on French ATU list prices and German GKV payment models",
    "Pharmazeutische Zeitung (2025/2026), ATMP cost table",
    "BioPharma Dive / Fierce Pharma / Labiotech reporting on bluebird bio, BioMarin and Pfizer launches and withdrawals",
    "Vertex, NHS England and NICE announcements on Casgevy reimbursement",
    "World Bank World Development Indicators: FP.CPI.TOTL and PA.NUS.PPP (retrieved 2026-11-14)"
  ),
  url = c(FDA, "https://www.ema.europa.eu/en/medicines/human/epar",
          "https://www.nice.org.uk/guidance", "https://www.g-ba.de/",
          "https://www.has-sante.fr/", "https://www.nice.org.uk/guidance",
          ISPOR25, ISPOR24,
          "https://pmc.ncbi.nlm.nih.gov/articles/PMC7980570/",
          "https://publication-theses.unistra.fr/public/theses_exercice/PHA/2024/2024_KIEFER_Samuel.pdf",
          "https://www.lesechos.fr/economie-france/social/therapie-genique-une-piqre-facturee-2-millions-deuros-1134553",
          "https://www.navlindaily.com/", "https://www.pharmazeutische-zeitung.de/heilen-statt-behandeln-167605/seite/alle",
          "https://www.biopharmadive.com/", "https://investors.vrtx.com/",
          "https://api.worldbank.org/v2/"),
  tier = c(1, 1, 2, 2, 2, 2, 6, 6, 6, 6, 7, 7, 7, 7, 7, 4),
  used_for = c("US approval dates; product identity",
               "EU approval dates; withdrawal dates",
               "England HTA dates, recommendations and list prices",
               "Germany benefit ratings",
               "France HTA ratings and dates",
               "England non-access statuses",
               "Germany/France/UK launch prices for seven products",
               "Germany/France/UK HTA ratings and aggregate distributions",
               "France CEPS prices for Kymriah and Yescarta",
               "France reimbursement dates and ATU context",
               "France Zolgensma ATU price",
               "France ATU prices and Germany payment models",
               "Germany Hemgenix and Casgevy price context",
               "Launch, withdrawal and discontinuation context",
               "England Casgevy access dates and price",
               "CPI and PPP factors"),
  accessed = "2026-11-14",
  stringsAsFactors = FALSE
)
write.csv(source_register, "data/raw/source_register.csv", row.names = FALSE, na = "")

cat("Wrote", nrow(extraction), "drug-country rows and", nrow(source_register), "sources.\n")
cat("Products:", length(unique(extraction$product_id)), "\n")
cat("Rows with a price:", sum(!is.na(extraction$list_price_lcu)), "\n")
cat("Rows with a first-access date:", sum(!is.na(extraction$first_access_date)), "\n")
