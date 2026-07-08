-- ============================================================================
--
--   Global Sovereign Risk Dashboard (IMF & World Bank Data)
--
--   Author      : Pavan Kumar Magandi
--   Platform    : PostgreSQL
--   Data Sources: IMF World Economic Outlook (WEO) | World Bank Global
--                 Economic Monitor (GEM) | World Bank Country Metadata
--   Scope       : ~190 Countries | 2000–2031 (actuals + IMF projections)
--
-- ============================================================================
--
--   PROJECT CONTEXT
--   ---------------
--   Sovereign risk analysis is the discipline of assessing whether a country
--   can meet its financial obligations — to bondholders, multilateral lenders,
--   and trading partners — without defaulting, restructuring, or triggering a
--   currency crisis. It is the foundational question behind every EM bond
--   portfolio, every IMF programme, and every sovereign credit rating.
--
--   Most public dashboards answer this question with one or two static ratios:
--   debt-to-GDP and maybe a fiscal deficit figure. The Apex Capital platform
--   goes further by combining two complementary data sources at different
--   frequencies — the IMF's annual structural forecasts (WEO) and the World
--   Bank's monthly market-pulse data (GEM) — to produce a multi-dimensional
--   risk intelligence layer that no single source alone can provide.
--
--   The 10 analytical queries in this file cover the full sovereign risk
--   spectrum: solvency, liquidity, currency overvaluation, trade resilience,
--   fiscal efficiency, social-political stress, market mispricing, debt
--   trajectory, regional contagion, and structural multi-year decline. Each
--   query is designed to produce an output that directly supports a business
--   decision — not just a number, but an answer to "what should we do?"
--
-- ============================================================================
--
--   DATA ARCHITECTURE
--   -----------------
--   Three tables underpin the entire analysis:
--
--   weo  — IMF World Economic Outlook (annual)
--          One row per country × indicator × year.
--          Covers ~190 countries from the early 2000s through 2031.
--          Years 2025–2031 are IMF projections, not actuals; queries that
--          use WEO forward data explicitly label forecast columns as such.
--          Key indicators used: GDP (current USD & domestic currency),
--          gross debt % of GDP, fiscal balance % of GDP, current account
--          (% of GDP and USD), CPI, unemployment, government expenditure.
--
--   gem  — World Bank Global Economic Monitor (monthly where available)
--          One row per country × indicator × year × month.
--          month = 0 is a source-provided annual summary row; all queries
--          in this file filter to month <> 0 to work exclusively with the
--          true monthly observations and re-aggregate where needed, avoiding
--          reliance on an opaque upstream pre-aggregate.
--          Key indicators used: Total Reserves (USD millions), REER index,
--          official FX rate (LCU per USD), months of import cover, stock
--          market index (USD), merchandise export prices.
--
--   meta — World Bank Country Metadata (static)
--          One row per country.
--          Fields: country_name, iso_code (CHAR(3)), region, income_group,
--          lending_category (IDA / IBRD / Blend / Not classified).
--          Used throughout as the classification backbone for regional and
--          income-group segmentation.
--
-- ============================================================================
--
--   ANALYTICAL FRAMEWORK
--   --------------------
--   The 10 queries are organised around four sovereign risk pillars:
--
--   PILLAR 1 — SOLVENCY & LIQUIDITY (Q1, Q8, Q9)
--   Can the government pay its debts? How quickly is the debt burden
--   growing relative to the economy? Which regions are most exposed?
--
--   PILLAR 2 — EXTERNAL SECTOR & CURRENCY (Q2, Q3, Q7)
--   Is the exchange rate overvalued? Is the current account deteriorating?
--   Are export revenues stable enough to service external obligations?
--
--   PILLAR 3 — FISCAL QUALITY & MARKET PERCEPTION (Q4, Q6)
--   Is government spending generating growth? Have equity markets priced
--   in the fiscal deterioration, or is there a dangerous disconnect?
--
--   PILLAR 4 — STRUCTURAL TRAJECTORY (Q5, Q10)
--   What is the social and political stress level? Are the key risk
--   indicators deteriorating in a sustained multi-year structural pattern,
--   or was this just a single shock year?
--
-- ============================================================================
--
--   FLAG CONVENTION
--   ---------------
--   All queries that produce a risk classification follow a consistent
--   three-tier flag convention:
--
--   RED    — Breach of the primary danger threshold. Requires immediate
--            attention; indicates a country or region where risk is
--            acute and the potential for a crisis event is elevated.
--
--   YELLOW — Breach of the elevated-risk threshold, but not yet critical.
--            Warrants active monitoring and stress-scenario planning.
--
--   GREEN  — Within acceptable bounds. Does not mean zero risk; means the
--            specific indicator being measured is not currently a primary
--            concern relative to the defined thresholds.
--
--   Threshold rationale for each flag is documented within the individual
--   query comments below. All thresholds are grounded in IMF, World Bank,
--   and standard sovereign credit literature benchmarks.
--
-- ============================================================================
--
--   HOW TO RUN
--   ----------
--   Environment : PostgreSQL 13+
--   Database    : sovereign_risk  (or any database where the three tables
--                 have been loaded)
--   Execution   : Each query block is self-contained and can be run
--                 independently. No cross-query dependencies exist.
--                 Run all 10 sequentially for the full dashboard output.
--
--   Recommended indexes for performance on large WEO/GEM datasets:
--     CREATE INDEX idx_weo_indicator ON weo (indicator_name, iso_code, fiscal_year);
--     CREATE INDEX idx_gem_indicator ON gem (indicator_name, iso_code, fiscal_year, month);
--
-- ============================================================================


-- ============================================================================
-- TABLE DEFINITIONS
-- ============================================================================

CREATE TABLE meta (
    country_name      TEXT,
    iso_code          CHAR(3),
    region            TEXT,
    income_group      TEXT,
    lending_category  TEXT
);

CREATE TABLE gem (
    country_name_gem  TEXT,
    iso_code          CHAR(3),
    fiscal_year       INTEGER,
    month             INTEGER,
    indicator_name    TEXT,
    indicator_value   NUMERIC
);

CREATE TABLE weo (
    iso_code          CHAR(3),
    indicator_code    TEXT,
    fiscal_year       INTEGER,
    indicator_name    TEXT,
    unit              TEXT,
    scale             TEXT,
    indicator_value   NUMERIC
);


-- ============================================================================
-- QUESTION 1: The Reserves-vs-Debt Solvency Cross-Check
-- ============================================================================
-- Among countries with high government debt (WEO), which ones have FX reserves (GEM, actual USD) that cover only
-- a small fraction of their total government debt (also converted to actual USD) — and is that
-- reserve cushion shrinking right now?

-- WHY IT IS IMPORTANT:
-- "Months of import cover" and "debt % of GDP" are two different units that were never directly comparable — one's a liquidity ratio, 
-- the other's a solvency ratio. The sharper question is a true apples-to-apples one: how many actual dollars of reserves 
-- exist for every dollar of government debt. WEO gives debt as % of GDP and GDP in current US dollars (billions), 
-- so actual debt in USD can be derived. GEM gives Total Reserves in USD millions directly.
-- Comparing the two dollar figures — and tracking the reserves figure's 6-month trend from true monthly GEM data — produces a
-- real solvency cushion ratio plus a live early-warning signal, instead of two numbers in incompatible units sitting side by side.
-- Months-of-import-cover is kept as a supplementary liquidity reference, not the primary comparison.
-- gdp_usd_billions is surfaced explicitly (it was already being computed internally to derive debt_usd_billions)
-- so debt_pct_gdp can be independently cross-checked against the dollar figures.

WITH latest_debt_pct AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS debt_pct_gdp
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_gdp_usd AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
    ORDER BY iso_code, fiscal_year DESC
),
debt_usd AS (
    SELECT
        d.iso_code,
        d.fiscal_year,
        d.debt_pct_gdp,
        g.gdp_usd_billions,
        ROUND(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 1) AS debt_usd_billions
    FROM latest_debt_pct d
    JOIN latest_gdp_usd g ON d.iso_code = g.iso_code
),
reserves_monthly AS (
    SELECT iso_code, fiscal_year, month, indicator_value / 1000.0 AS reserves_usd_billions
    FROM gem
    WHERE indicator_name = 'Total Reserves,,,,'
      AND month <> 0
),
latest_reserve_point AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, month, reserves_usd_billions
    FROM reserves_monthly
    ORDER BY iso_code, fiscal_year DESC, month DESC
),
reserve_6mo_prior AS (
    SELECT r2.iso_code, r2.reserves_usd_billions AS reserves_6mo_ago_usd_billions
    FROM latest_reserve_point lp
    JOIN reserves_monthly r2
      ON r2.iso_code = lp.iso_code
     AND ((r2.fiscal_year = lp.fiscal_year AND r2.month = lp.month - 6)
       OR (r2.fiscal_year = lp.fiscal_year - 1 AND lp.month <= 6 AND r2.month = lp.month + 6))
),
months_cover_latest AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, round(indicator_value,1) AS months_import_cover
    FROM gem
    WHERE indicator_name = 'Months Import Cover of Foreign Reserves,,,,'
      AND month <> 0
    ORDER BY iso_code, fiscal_year DESC, month DESC
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
	round(du.debt_pct_gdp,2) AS debt_pct_gdp, 
    du.gdp_usd_billions,
    du.debt_usd_billions,
    Round(lp.reserves_usd_billions,2) AS reserves_now_usd_billions,
    ROUND(r6.reserves_6mo_ago_usd_billions, 2) AS reserves_6mo_ago_usd_billions,
    ROUND(lp.reserves_usd_billions - r6.reserves_6mo_ago_usd_billions, 2) AS reserve_change_6mo_usd_billions,
    ROUND(lp.reserves_usd_billions / NULLIF(du.debt_usd_billions, 0) * 100, 2) AS reserves_pct_of_debt,
    mc.months_import_cover,
    CASE
        WHEN mc.months_import_cover < 3 THEN 'RED - Worrying'
        WHEN mc.months_import_cover >= 3 AND mc.months_import_cover < 6 THEN 'YELLOW - Manageable'
        WHEN mc.months_import_cover >= 6 THEN 'GREEN - Good'
        ELSE 'No Data'
    END AS liquidity_risk_flag
FROM debt_usd du
JOIN latest_reserve_point lp ON du.iso_code = lp.iso_code
JOIN meta m ON du.iso_code = m.iso_code
LEFT JOIN reserve_6mo_prior r6 ON du.iso_code = r6.iso_code
LEFT JOIN months_cover_latest mc ON du.iso_code = mc.iso_code
WHERE du.debt_pct_gdp > 70
  AND lp.reserves_usd_billions / NULLIF(du.debt_usd_billions, 0) < 0.15   -- reserves cover less than 15% of total debt
ORDER BY reserves_pct_of_debt ASC;


-- ============================================================================
-- QUESTION 2: Currency Overvaluation vs. External Imbalance
-- ============================================================================
-- Which currencies look overvalued on REER (GEM, latest available reading) while the country is running an
-- ACTUALLY WORSENING current account deficit over the last 2 years (WEO) — a classic setup for a forced devaluation?

-- WHY IT IS IMPORTANT:
-- A strong REER feels good politically but is unsustainable if the current account is bleeding dollars out of the economy.
-- "Worsening" means a trend, not a level — a country sitting at a stable deficit for years is a
-- structural fact, not an emerging crisis; a deficit that's actively widening is the real warning sign.
-- Note: REER (Real Effective Exchange Rate) is an INDEX, not a literal currency price — it's the trade-weighted,
-- inflation-adjusted value of the currency relative to a base year (100 = the benchmark).
-- A reading of 130 means the currency is ~30% stronger than that benchmark in real terms,
-- not that 1 USD buys 130 of anything. To show the actual price of the currency,
-- this query adds the literal market exchange rate (local currency units per 1 USD) alongside the REER index.
-- No currency name/code field exists in the meta table, so iso_code is shown as the currency/country identifier.
-- The "now vs 2 years ago" worsening test is anchored to the SAME year as the REER reading (not each
-- country's independent latest WEO year) — otherwise, since WEO data extends to 2031 for nearly every country, 
-- the comparison would silently jump to a distant smoothed forecast year and the "worsening" signal would
-- become meaningless. Forward-looking WEO forecasts are still shown, but as
-- explicit separate columns (2-year-ahead, 4-year-ahead current account),
-- so future trajectory is visible without corrupting the current-state comparison.
-- gdp_usd_billions is added for the same year as the current account reading, so
-- current_account_pct_gdp_now can be cross-checked against current_account_usd_billions_now / gdp_usd_billions.

WITH latest_reer AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, month, indicator_value AS reer_index
    FROM gem
    WHERE indicator_name = 'Real Effective Exchange Rate,,,,'
      AND month <> 0
      AND fiscal_year >= 2018
    ORDER BY iso_code, fiscal_year DESC, month DESC
),
fx_rate_at_reer AS (
    SELECT g.iso_code, g.fiscal_year, g.month, g.indicator_value AS market_rate_lcu_per_usd
    FROM gem g
    JOIN latest_reer r
      ON g.iso_code = r.iso_code
     AND g.fiscal_year = r.fiscal_year
     AND g.month = r.month
    WHERE g.indicator_name = 'Official exchange rate, LCU per USD, period average,,'
),
ca_pct_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS ca_pct_gdp
    FROM weo
    WHERE indicator_name = 'Current account balance (credit less debit), Percent of GDP'
),
ca_usd_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS ca_usd_billions
    FROM weo
    WHERE indicator_name = 'Current account balance (credit less debit), US dollar'
),
gdp_usd_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
),
ca_trend AS (
    SELECT
        p.iso_code,
        p.fiscal_year AS current_account_year,
        p.ca_pct_gdp AS ca_pct_now,
        LAG(p.ca_pct_gdp, 2) OVER (PARTITION BY p.iso_code ORDER BY p.fiscal_year) AS ca_pct_2yr_ago,
        LEAD(p.ca_pct_gdp, 2) OVER (PARTITION BY p.iso_code ORDER BY p.fiscal_year) AS ca_pct_2yr_ahead_forecast,
        LEAD(p.ca_pct_gdp, 4) OVER (PARTITION BY p.iso_code ORDER BY p.fiscal_year) AS ca_pct_4yr_ahead_forecast,
        u.ca_usd_billions AS ca_usd_now,
        LAG(u.ca_usd_billions, 2) OVER (PARTITION BY p.iso_code ORDER BY p.fiscal_year) AS ca_usd_2yr_ago,
        gd.gdp_usd_billions
    FROM ca_pct_series p
    JOIN ca_usd_series u ON p.iso_code = u.iso_code AND p.fiscal_year = u.fiscal_year
    LEFT JOIN gdp_usd_series gd ON p.iso_code = gd.iso_code AND p.fiscal_year = gd.fiscal_year
)
SELECT
    m.country_name,
    m.iso_code AS country_code,
    r.fiscal_year AS reer_year,
    r.month AS reer_month,
    ROUND(r.reer_index, 2) AS reer_index,
    ROUND(fx.market_rate_lcu_per_usd, 2) AS market_rate_lcu_per_usd,
    c.gdp_usd_billions,
    ROUND(c.ca_pct_now, 2) AS current_account_pct_gdp_now,
    ROUND(c.ca_usd_now, 2) AS current_account_usd_billions_now,
    ROUND(c.ca_pct_2yr_ago, 2) AS current_account_pct_gdp_2yr_ago,
    ROUND(c.ca_usd_2yr_ago, 2) AS current_account_usd_billions_2yr_ago,
    ROUND(c.ca_pct_now - c.ca_pct_2yr_ago, 2) AS ca_pct_deterioration_2yr,
    ROUND(c.ca_usd_now - c.ca_usd_2yr_ago, 2) AS ca_usd_deterioration_2yr,
    ROUND(c.ca_pct_2yr_ahead_forecast, 2) AS ca_pct_gdp_forecast_2yr_ahead,
    ROUND(c.ca_pct_4yr_ahead_forecast, 2) AS ca_pct_gdp_forecast_4yr_ahead,
    CASE
        WHEN r.reer_index >= 130 AND c.ca_pct_now <= -6 AND (c.ca_pct_now - c.ca_pct_2yr_ago) <= -3 THEN 'RED - Severe Devaluation Risk'
        WHEN r.reer_index >= 110 AND c.ca_pct_now <= -4 AND (c.ca_pct_now - c.ca_pct_2yr_ago) < 0    THEN 'YELLOW - Elevated Devaluation Risk'
        ELSE 'WATCH'
    END AS devaluation_risk_flag
FROM latest_reer r
LEFT JOIN fx_rate_at_reer fx ON r.iso_code = fx.iso_code
JOIN ca_trend c ON r.iso_code = c.iso_code AND r.fiscal_year = c.current_account_year
JOIN meta m ON r.iso_code = m.iso_code
WHERE r.reer_index > 110
  AND c.ca_pct_now < -4
  AND c.ca_pct_2yr_ago IS NOT NULL
  AND c.ca_pct_now < c.ca_pct_2yr_ago     -- current account is genuinely worsening, not just deficit-heavy
ORDER BY r.reer_index DESC, ca_pct_deterioration_2yr ASC;


-- ============================================================================
-- QUESTION 3: Trade Resilience by Income Group
-- ============================================================================
-- Do low-income (IDA) countries show structurally worse export-price shock
-- absorption than middle-income (IBRD) countries, using GEM's merchandise
-- export price series alongside Meta's lending category?
--
-- WHY IT IS IMPORTANT:
-- Commodity-dependent low-income countries are far more exposed to terms-of-
-- trade shocks than diversified middle-income economies. This tests whether
-- a composite sovereign risk score needs different trade-shock thresholds
-- by lending category, rather than one universal cutoff. Annual export
-- price is built by averaging true monthly observations (month <> 0)
-- rather than trusting a single pre-aggregated row, so the year-over-year
-- change is computed from real data, not an opaque upstream summary.

WITH export_price_annual AS (
    SELECT iso_code, fiscal_year, AVG(indicator_value) AS export_price_avg
    FROM gem
    WHERE indicator_name = 'Exports Merchandise, Customs, Price, US$, not seas. adj.'
      AND month <> 0
    GROUP BY iso_code, fiscal_year
),
export_price_yoy AS (
    SELECT
        iso_code, fiscal_year, export_price_avg,
        LAG(export_price_avg) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS export_price_prev_year
    FROM export_price_annual
),
export_price_change AS (
    SELECT
        iso_code, fiscal_year,
        ROUND((export_price_avg - export_price_prev_year) / export_price_prev_year * 100, 2) AS yoy_pct_change
    FROM export_price_yoy
    WHERE export_price_prev_year IS NOT NULL
)
SELECT
    m.lending_category,
    COUNT(*) AS num_country_year_observations,
    COUNT(DISTINCT e.iso_code) AS num_countries,
    ROUND(AVG(e.yoy_pct_change), 2) AS avg_yoy_export_price_pct_change,
    ROUND(STDDEV(e.yoy_pct_change), 2) AS export_price_volatility_stddev,
    ROUND(MIN(e.yoy_pct_change), 2) AS worst_export_price_yoy_shock,
    ROUND(MAX(e.yoy_pct_change), 2) AS best_export_price_yoy_swing
FROM export_price_change e
JOIN meta m ON e.iso_code = m.iso_code
Where m.lending_category IS NOT NULL 
GROUP BY m.lending_category
ORDER BY export_price_volatility_stddev DESC;


-- ============================================================================
-- QUESTION 4: Stock Market Disconnect from Macro Fundamentals
-- ============================================================================
-- Which countries have rising stock markets (GEM, latest month vs. 3 years ago)
-- while their fiscal balance is actively deteriorating (WEO) — a sign
-- the market hasn't priced in sovereign risk yet?
--
-- WHY IT IS IMPORTANT:
-- Equity markets often lag sovereign stress until a trigger event forces a
-- sharp repricing. Spotting the gap between "markets are calm" and
-- "fundamentals are worsening" is exactly the asymmetric, contrarian signal
-- a macro hedge fund desk hunts for before consensus catches up. Region and
-- income group are included so the finding can be read in context — e.g.
-- whether mispricing clusters in a specific region or income tier — and a
-- disconnect-severity flag turns the raw numbers into a ranked watchlist.
-- gdp_usd_billions and the derived dollar fiscal balance are added so
-- fiscal_balance_now_pct_gdp can be cross-checked against an actual dollar figure.

WITH stock_monthly AS (
    SELECT iso_code, fiscal_year, month, indicator_value AS stock_index_usd
    FROM gem
    WHERE indicator_name = 'Stock Markets, US$,,,'
      AND month <> 0
),
latest_stock AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, month, stock_index_usd
    FROM stock_monthly
    ORDER BY iso_code, fiscal_year DESC, month DESC
),
stock_3yr_ago AS (
    SELECT DISTINCT ON (s.iso_code)
        s.iso_code, s.stock_index_usd AS stock_index_3yr_ago
    FROM latest_stock l
    JOIN stock_monthly s
      ON s.iso_code = l.iso_code
     AND s.fiscal_year = l.fiscal_year - 3
     AND s.month = l.month
),
fiscal_trend AS (
    SELECT
        iso_code, fiscal_year, indicator_value AS fiscal_balance_pct_gdp,
        LAG(indicator_value, 3) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS fiscal_3yr_ago
    FROM weo
    WHERE indicator_name = 'Net lending (+) / net borrowing (-), General government, Percent of GDP'
),
gdp_usd_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
    l.fiscal_year AS stock_data_year,
    l.month AS stock_data_month,
    ROUND((l.stock_index_usd - p.stock_index_3yr_ago) / p.stock_index_3yr_ago * 100, 2) AS stock_3yr_gain_pct,
    gd.gdp_usd_billions,
    ROUND(f.fiscal_balance_pct_gdp, 2) AS fiscal_balance_now_pct_gdp,
    ROUND(f.fiscal_balance_pct_gdp / 100.0 * gd.gdp_usd_billions, 2) AS fiscal_balance_now_usd_billions,
    ROUND(f.fiscal_3yr_ago, 2) AS fiscal_balance_3yr_ago_pct_gdp,
    ROUND(f.fiscal_balance_pct_gdp - f.fiscal_3yr_ago, 2) AS fiscal_balance_deterioration,
    CASE
        WHEN (l.stock_index_usd - p.stock_index_3yr_ago) / p.stock_index_3yr_ago > 0.40
             AND (f.fiscal_balance_pct_gdp - f.fiscal_3yr_ago) < -3 THEN 'RED - Severe Disconnect'
        WHEN (l.stock_index_usd - p.stock_index_3yr_ago) / p.stock_index_3yr_ago > 0.20
             AND f.fiscal_balance_pct_gdp < f.fiscal_3yr_ago THEN 'YELLOW - Emerging Disconnect'
        ELSE 'WATCH'
    END AS market_mispricing_flag
FROM latest_stock l
JOIN stock_3yr_ago p ON l.iso_code = p.iso_code
JOIN fiscal_trend f ON l.iso_code = f.iso_code AND l.fiscal_year = f.fiscal_year
JOIN meta m ON l.iso_code = m.iso_code
LEFT JOIN gdp_usd_series gd ON l.iso_code = gd.iso_code AND l.fiscal_year = gd.fiscal_year
WHERE f.fiscal_3yr_ago IS NOT NULL
  AND (l.stock_index_usd - p.stock_index_3yr_ago) / p.stock_index_3yr_ago > 0.20
  AND f.fiscal_balance_pct_gdp < f.fiscal_3yr_ago
ORDER BY stock_3yr_gain_pct DESC;


-- ============================================================================
-- QUESTION 5: Unemployment-Inflation Misery Ranking, Region-Adjusted
-- ============================================================================
-- Which countries have the worst combined unemployment + inflation burden ("Misery Index"),
-- and how does that ranking change once adjusted for regional norms rather than a single global bar?
-- 
-- WHY IT IS IMPORTANT:
-- A 12% unemployment rate means something very different in Sub-Saharan
-- Africa than in Europe & Central Asia. A raw global ranking flatters or
-- unfairly penalizes entire regions. Reporting both the global rank and the
-- region-adjusted rank side by side lets a reviewer see immediately when a
-- country is "bad globally but normal regionally" versus a true regional
-- outlier — and a severity tier converts the raw index into language a
-- non-technical stakeholder can act on directly.

WITH latest_unemp AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS unemployment_rate
    FROM weo
    WHERE indicator_name = 'Unemployment rate'
    ORDER BY iso_code, fiscal_year DESC
),
latest_cpi AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS cpi_pct_change
    FROM weo
    WHERE indicator_name = 'All Items, Consumer price index (CPI), Period average, percent change'
    ORDER BY iso_code, fiscal_year DESC
),
misery AS (
    SELECT
        u.iso_code,
        u.fiscal_year AS unemployment_year,
        c.fiscal_year AS cpi_year,
        u.unemployment_rate,
        c.cpi_pct_change,
        u.unemployment_rate + c.cpi_pct_change AS misery_index
    FROM latest_unemp u
    JOIN latest_cpi c ON u.iso_code = c.iso_code
)
SELECT
    m.country_name,
    m.region,
    ROUND(mi.unemployment_rate, 2) AS unemployment_rate_pct,
    ROUND(mi.cpi_pct_change, 2) AS inflation_pct,
    ROUND(mi.misery_index, 2) AS misery_index,
    RANK() OVER (ORDER BY mi.misery_index DESC) AS global_misery_rank,
    RANK() OVER (PARTITION BY m.region ORDER BY mi.misery_index DESC) AS regional_misery_rank,
    CASE
        WHEN mi.misery_index >= 30 THEN 'RED - Severe'
        WHEN mi.misery_index >= 15 THEN 'YELLOW - High'
        ELSE 'GREEN - Manageable'
    END AS misery_severity_flag
FROM misery mi
JOIN meta m ON mi.iso_code = m.iso_code
ORDER BY mi.misery_index DESC;


-- ============================================================================
-- QUESTION 6: Government Spending Efficiency vs. Growth Payoff
-- ============================================================================
-- Which countries are spending heavily as a share of GDP (WEO government
-- expenditure) without a corresponding payoff in GDP growth — where is
-- government spending the least efficient?
--
-- WHY IT IS IMPORTANT:
-- Spending level alone tells you nothing about quality. A country spending
-- 35% of GDP and growing 1% is a very different story than one spending 35%
-- and growing 6%. Critically, comparing spend % of GDP against GDP growth %
-- is dividing two different kinds of ratios — not a real "value for money"
-- number. The actual question is: for every real dollar of government
-- spending, how many real dollars of GDP growth did the economy produce?
-- WEO has no direct USD expenditure series, only "Domestic currency" and
-- "Percent of GDP," so actual USD spend is derived as spend % of GDP times
-- GDP in current US dollars. Actual dollar GDP growth is derived as the
-- year-over-year change in GDP (current US dollars), not the % growth rate.
-- Dividing growth dollars by spend dollars gives a genuine $-for-$
-- efficiency ratio — the kind sovereign wealth funds and multilateral
-- lenders actually use to judge fiscal policy quality. The standard WEO
-- GDP growth % is added alongside the dollar figures so it can be cross-
-- checked against gdp_usd_billions and the derived dollar growth.

WITH spend_pct AS (
    SELECT iso_code, fiscal_year, indicator_value AS govt_spend_pct_gdp
    FROM weo
    WHERE indicator_name = 'Expenditure, General government, Percent of GDP'
),
gdp_growth_pct_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS gdp_growth_pct
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Constant prices, Percent change'
),
gdp_usd AS (
    SELECT iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
),
gdp_usd_growth AS (
    SELECT
        iso_code, fiscal_year, gdp_usd_billions,
        gdp_usd_billions - LAG(gdp_usd_billions) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS gdp_growth_usd_billions
    FROM gdp_usd
),
spend_and_growth AS (
    SELECT
        s.iso_code,
        s.fiscal_year,
        s.govt_spend_pct_gdp,
        g.gdp_usd_billions,
        ROUND(s.govt_spend_pct_gdp / 100.0 * g.gdp_usd_billions, 2) AS govt_spend_usd_billions,
        g.gdp_growth_usd_billions,
        p.gdp_growth_pct
    FROM spend_pct s
    JOIN gdp_usd_growth g ON s.iso_code = g.iso_code AND s.fiscal_year = g.fiscal_year
    LEFT JOIN gdp_growth_pct_series p ON s.iso_code = p.iso_code AND s.fiscal_year = p.fiscal_year
),
latest_spend_growth AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, govt_spend_pct_gdp, gdp_usd_billions,
        govt_spend_usd_billions, gdp_growth_usd_billions, gdp_growth_pct
    FROM spend_and_growth
    WHERE gdp_growth_usd_billions IS NOT NULL
    ORDER BY iso_code, fiscal_year DESC
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
    sg.fiscal_year,
    ROUND(sg.govt_spend_pct_gdp, 2) AS govt_spend_pct_gdp,
    sg.gdp_usd_billions,
    sg.govt_spend_usd_billions,
    ROUND(sg.gdp_growth_pct, 2) AS gdp_growth_pct,
    ROUND(sg.gdp_growth_usd_billions, 2) AS gdp_growth_usd_billions,
    ROUND(sg.gdp_growth_usd_billions / NULLIF(sg.govt_spend_usd_billions, 0), 4) AS usd_growth_per_usd_spend,
    CASE
        WHEN sg.gdp_growth_usd_billions < 0 THEN 'RED - Spending With Contraction'
        WHEN sg.gdp_growth_usd_billions / NULLIF(sg.govt_spend_usd_billions, 0) < 0.05 THEN 'YELLOW - Low Efficiency'
        ELSE 'GREEN - Reasonable Efficiency'
    END AS spending_efficiency_flag
FROM latest_spend_growth sg
JOIN meta m ON sg.iso_code = m.iso_code
WHERE sg.govt_spend_pct_gdp > 25
ORDER BY usd_growth_per_usd_spend ASC
LIMIT 25;


-- ============================================================================
-- QUESTION 7: The PPP Currency Mispricing Gap ("Implied Fair Value" Screen)
-- ============================================================================
-- WEO gives the theoretical PPP exchange rate (what a currency should be
-- worth based on price-level equality). GEM gives the actual official
-- market exchange rate. The gap between them tells you which currencies
-- are most over- or under-valued in real terms — a Big Mac Index built from
-- raw macro data instead of burger prices.
--
-- WHY IT IS IMPORTANT:
-- Currency misvaluation drives capital flows, import inflation, and
-- devaluation risk. Computing the percentage gap between PPP-implied rate
-- and market rate is the kind of proprietary "fair value" signal FX trading
-- desks build internally. Using the latest monthly market rate sharpens the
-- comparison to a true point-in-time read, and a valuation tier converts
-- the raw percentage gap into a directly usable classification.

WITH latest_ppp_rate AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS ppp_rate
    FROM weo
    WHERE indicator_name = 'Rate, Domestic currency per international dollar in PPP terms, ICP benchmarks 2017-2021'
    ORDER BY iso_code, fiscal_year DESC
),
latest_market_rate AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, month, indicator_value AS market_rate
    FROM gem
    WHERE indicator_name = 'Official exchange rate, LCU per USD, period average,,'
      AND month <> 0
    ORDER BY iso_code, fiscal_year DESC, month DESC
)
SELECT
    m.country_name,
    m.region,
    ROUND(p.ppp_rate, 2) AS ppp_implied_rate,
    ROUND(g.market_rate, 2) AS actual_market_rate,
    g.fiscal_year AS market_rate_year,
    g.month AS market_rate_month,
    ROUND((g.market_rate - p.ppp_rate) / p.ppp_rate * 100, 2) AS pct_over_undervalued,
    CASE
        WHEN (g.market_rate - p.ppp_rate) / p.ppp_rate * 100 <= -25 THEN 'RED - Significantly Overvalued'
        WHEN (g.market_rate - p.ppp_rate) / p.ppp_rate * 100 <= -10 THEN 'YELLOW - Overvalued'
        WHEN (g.market_rate - p.ppp_rate) / p.ppp_rate * 100 >= 25  THEN 'BLUE - Significantly Undervalued'
        WHEN (g.market_rate - p.ppp_rate) / p.ppp_rate * 100 >= 10  THEN 'GREEN - Undervalued'
        ELSE 'NEUTRAL - Near Fair Value'
    END AS valuation_flag
FROM latest_ppp_rate p
JOIN latest_market_rate g ON p.iso_code = g.iso_code
JOIN meta m ON p.iso_code = m.iso_code
ORDER BY pct_over_undervalued DESC;
-- Positive value = market rate weaker than PPP implies (currency undervalued)
-- Negative value = currency overvalued relative to PPP fair value


-- ============================================================================
-- QUESTION 8: The Fiscal Doomsday Clock
-- ============================================================================
-- Using WEO's full historical time series, calculate each country's
-- compound annual growth rate (CAGR) of government debt versus CAGR of
-- nominal GDP, then project how many years until debt-to-GDP effectively
-- doubles — a literal countdown clock per country.
--
-- WHY IT IS IMPORTANT:
-- A debt ratio is a snapshot; a trajectory is a forecast. Two countries can
-- both sit at 60% debt/GDP today, but if one's debt is growing 3x faster
-- than its economy, they are on completely different paths. This converts
-- a static risk score into a forward-looking "time to crisis" estimate, and
-- an urgency flag turns the raw years-to-doubling figure into an immediate
-- read on which countries need attention now versus later.
-- Note (Postgres-specific): LN(2) resolves to the double-precision overload
-- of ln(), so the division result is double precision; Postgres's two-
-- argument ROUND() only matches the numeric overload, hence the explicit
-- ::numeric casts below.

WITH debt_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS debt_lcu
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Domestic currency'
),
gdp_series AS (
    SELECT iso_code, fiscal_year, indicator_value AS gdp_lcu
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, Domestic currency'
),
debt_bounds AS (
    SELECT iso_code, MIN(fiscal_year) AS start_year, MAX(fiscal_year) AS end_year
    FROM debt_series
    GROUP BY iso_code
),
debt_cagr AS (
    SELECT
        b.iso_code,
        b.start_year,
        b.end_year,
        POWER(d_end.debt_lcu / NULLIF(d_start.debt_lcu, 0),
              1.0 / NULLIF(b.end_year - b.start_year, 0)) - 1 AS debt_cagr,
        POWER(g_end.gdp_lcu / NULLIF(g_start.gdp_lcu, 0),
              1.0 / NULLIF(b.end_year - b.start_year, 0)) - 1 AS gdp_cagr
    FROM debt_bounds b
    JOIN debt_series d_start ON d_start.iso_code = b.iso_code AND d_start.fiscal_year = b.start_year
    JOIN debt_series d_end   ON d_end.iso_code   = b.iso_code AND d_end.fiscal_year   = b.end_year
    JOIN gdp_series  g_start ON g_start.iso_code = b.iso_code AND g_start.fiscal_year = b.start_year
    JOIN gdp_series  g_end   ON g_end.iso_code   = b.iso_code AND g_end.fiscal_year   = b.end_year
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
    c.start_year,
    c.end_year,
    ROUND((c.debt_cagr * 100)::numeric, 2) AS debt_cagr_pct,
    ROUND((c.gdp_cagr * 100)::numeric, 2) AS gdp_cagr_pct,
    ROUND(((c.debt_cagr - c.gdp_cagr) * 100)::numeric, 2) AS excess_debt_growth_pct,
    ROUND((LN(2) / NULLIF((c.debt_cagr - c.gdp_cagr), 0))::numeric, 2) AS years_to_ratio_doubling,
    CASE
        WHEN LN(2) / NULLIF((c.debt_cagr - c.gdp_cagr), 0) < 5  THEN 'RED - Urgent'
        WHEN LN(2) / NULLIF((c.debt_cagr - c.gdp_cagr), 0) < 10 THEN 'YELLOW - Monitor'
        ELSE 'GREEN - Manageable'
    END AS doomsday_urgency_flag
FROM debt_cagr c
JOIN meta m ON c.iso_code = m.iso_code
WHERE c.debt_cagr > c.gdp_cagr
ORDER BY years_to_ratio_doubling ASC
LIMIT 25;


-- ============================================================================
-- QUESTION 9: Regional Sovereign Stress Clustering
-- ============================================================================
-- Which regions are carrying the highest concentration of simultaneously
-- stressed countries — combining debt burden, reserve adequacy, fiscal
-- deficit, and current account deficit into a single regional stress score?
--
-- WHY IT IS IMPORTANT:
-- All 8 prior queries treat countries as independent observations. Real
-- sovereign risk does not work that way. When multiple countries in the
-- same region show simultaneous stress across debt, reserves, and external
-- balance, the risk is no longer additive — it becomes contagious. Trade
-- linkages, shared currency zones, cross-border banking exposure, and
-- investor sentiment mean that stress in one country raises the cost of
-- borrowing for its neighbours even before they default. This query
-- aggregates per-country stress flags into a regional-level dashboard,
-- so a portfolio manager or risk committee can see at a glance which
-- regions need the most immediate attention and how many countries within
-- each region are simultaneously flashing warning signs across multiple
-- dimensions — not just one.

WITH latest_debt AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS debt_pct_gdp
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_gdp_usd AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
    ORDER BY iso_code, fiscal_year DESC
),
latest_fiscal AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS fiscal_balance_pct_gdp
    FROM weo
    WHERE indicator_name = 'Net lending (+) / net borrowing (-), General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_ca AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS ca_pct_gdp
    FROM weo
    WHERE indicator_name = 'Current account balance (credit less debit), Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_reserves AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, indicator_value / 1000.0 AS reserves_usd_billions
    FROM gem
    WHERE indicator_name = 'Total Reserves,,,,'
      AND month <> 0
    ORDER BY iso_code, fiscal_year DESC, month DESC
),
country_stress AS (
    SELECT
        d.iso_code,
        d.debt_pct_gdp,
        g.gdp_usd_billions,
        ROUND(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 1) AS debt_usd_billions,
        r.reserves_usd_billions,
        f.fiscal_balance_pct_gdp,
        ca.ca_pct_gdp,
        CASE WHEN d.debt_pct_gdp > 70 THEN 1 ELSE 0 END AS debt_stress_flag,
        CASE WHEN r.reserves_usd_billions / NULLIF(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 0) < 0.15
             THEN 1 ELSE 0 END AS reserves_stress_flag,
        CASE WHEN f.fiscal_balance_pct_gdp < -5 THEN 1 ELSE 0 END AS fiscal_stress_flag,
        CASE WHEN ca.ca_pct_gdp < -5 THEN 1 ELSE 0 END AS ca_stress_flag,
        CASE WHEN d.debt_pct_gdp > 70 THEN 1 ELSE 0 END +
        CASE WHEN r.reserves_usd_billions / NULLIF(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 0) < 0.15
             THEN 1 ELSE 0 END +
        CASE WHEN f.fiscal_balance_pct_gdp < -5 THEN 1 ELSE 0 END +
        CASE WHEN ca.ca_pct_gdp < -5 THEN 1 ELSE 0 END AS country_stress_score
    FROM latest_debt d
    JOIN latest_gdp_usd g  ON d.iso_code = g.iso_code
    JOIN latest_fiscal f   ON d.iso_code = f.iso_code
    JOIN latest_ca ca      ON d.iso_code = ca.iso_code
    LEFT JOIN latest_reserves r ON d.iso_code = r.iso_code
)
SELECT
    m.region,
    COUNT(DISTINCT cs.iso_code) AS total_countries_in_region,
    SUM(cs.debt_stress_flag) AS countries_with_high_debt,
    SUM(cs.reserves_stress_flag) AS countries_with_thin_reserves,
    SUM(cs.fiscal_stress_flag) AS countries_with_fiscal_deficit,
    SUM(cs.ca_stress_flag) AS countries_with_ca_deficit,
    SUM(CASE WHEN cs.country_stress_score >= 2 THEN 1 ELSE 0 END) AS countries_stressed_on_2plus_dimensions,
    SUM(CASE WHEN cs.country_stress_score >= 3 THEN 1 ELSE 0 END) AS countries_stressed_on_3plus_dimensions,
    ROUND(AVG(cs.country_stress_score), 2) AS avg_regional_stress_score,
    ROUND(SUM(cs.gdp_usd_billions), 1) AS total_regional_gdp_usd_billions,
    ROUND(
        SUM(CASE WHEN cs.country_stress_score >= 2 THEN cs.gdp_usd_billions ELSE 0 END)
        / NULLIF(SUM(cs.gdp_usd_billions), 0) * 100, 1
    ) AS pct_regional_gdp_in_stressed_countries,
    CASE
        WHEN AVG(cs.country_stress_score) >= 2.0 THEN 'RED - High Regional Contagion Risk'
        WHEN AVG(cs.country_stress_score) >= 1.0 THEN 'YELLOW - Elevated Regional Stress'
        ELSE 'GREEN - Region Broadly Stable'
    END AS regional_stress_flag
FROM country_stress cs
JOIN meta m ON cs.iso_code = m.iso_code
GROUP BY m.region
ORDER BY avg_regional_stress_score DESC;


-- ----------------------------------------------------------------------------
-- Q9b — Country-level stress detail (bonus view, not in original 10)
-- Tableau tip: Q9's regional rollup is great for a map/summary tile, but a
-- drill-down dashboard usually also wants the country-level rows behind it.
-- This exposes country_stress before the GROUP BY collapses it, so you can
-- filter Q9's regional summary and cross-filter into this for the detail
-- table. Safe to ignore if you only want the original 10.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW gsr_q9b_country_stress_detail AS
WITH latest_debt AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS debt_pct_gdp
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_gdp_usd AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS gdp_usd_billions
    FROM weo
    WHERE indicator_name = 'Gross domestic product (GDP), Current prices, US dollar'
    ORDER BY iso_code, fiscal_year DESC
),
latest_fiscal AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS fiscal_balance_pct_gdp
    FROM weo
    WHERE indicator_name = 'Net lending (+) / net borrowing (-), General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_ca AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS ca_pct_gdp
    FROM weo
    WHERE indicator_name = 'Current account balance (credit less debit), Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
),
latest_reserves AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, indicator_value / 1000.0 AS reserves_usd_billions
    FROM gem
    WHERE indicator_name = 'Total Reserves,,,,'
      AND month <> 0
    ORDER BY iso_code, fiscal_year DESC, month DESC
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
    d.debt_pct_gdp,
    g.gdp_usd_billions,
    r.reserves_usd_billions,
    f.fiscal_balance_pct_gdp,
    ca.ca_pct_gdp,
    CASE WHEN d.debt_pct_gdp > 70 THEN 1 ELSE 0 END AS debt_stress_flag,
    CASE WHEN r.reserves_usd_billions / NULLIF(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 0) < 0.15
         THEN 1 ELSE 0 END AS reserves_stress_flag,
    CASE WHEN f.fiscal_balance_pct_gdp < -5 THEN 1 ELSE 0 END AS fiscal_stress_flag,
    CASE WHEN ca.ca_pct_gdp < -5 THEN 1 ELSE 0 END AS ca_stress_flag,
    (CASE WHEN d.debt_pct_gdp > 70 THEN 1 ELSE 0 END +
     CASE WHEN r.reserves_usd_billions / NULLIF(d.debt_pct_gdp / 100.0 * g.gdp_usd_billions, 0) < 0.15
          THEN 1 ELSE 0 END +
     CASE WHEN f.fiscal_balance_pct_gdp < -5 THEN 1 ELSE 0 END +
     CASE WHEN ca.ca_pct_gdp < -5 THEN 1 ELSE 0 END) AS country_stress_score
FROM latest_debt d
JOIN latest_gdp_usd g  ON d.iso_code = g.iso_code
JOIN meta m             ON d.iso_code = m.iso_code
JOIN latest_fiscal f   ON d.iso_code = f.iso_code
JOIN latest_ca ca      ON d.iso_code = ca.iso_code
LEFT JOIN latest_reserves r ON d.iso_code = r.iso_code;



-- ============================================================================
-- QUESTION 10: The Consecutive-Year Deterioration Streak
-- ============================================================================
-- Which countries have been deteriorating consistently across fiscal balance,
-- debt, and current account for 3 or more consecutive years — distinguishing
-- a genuine structural decline from a single bad year that gets smoothed out
-- in any point-in-time or fixed-lookback comparison?
--
-- WHY IT IS IMPORTANT:
-- Every query in this file compares "now" versus "N years ago." That approach
-- misses a critical distinction: a country that had one catastrophic year
-- (COVID 2020) and then recovered looks identical in a 3-year lookback to a
-- country that has been steadily worsening every single year since 2019 with
-- no sign of reversal. The second pattern is far more dangerous — it signals
-- a structural problem that policy has failed to arrest, not a shock that
-- was absorbed. Consecutive-year streaks are the sovereign risk equivalent
-- of a patient whose vitals have been declining at every checkup for five
-- years, versus one who had a single bad reading. Rating agencies use streak
-- analysis informally in their sovereign outlook changes (Negative Outlook
-- → Downgrade); this query makes that logic explicit and quantifiable.
-- A country with a 5-year unbroken deterioration streak in ALL THREE
-- dimensions simultaneously (fiscal, debt, and external) is the highest-
-- conviction early-warning signal this dataset can produce.

WITH fiscal_series AS (
    SELECT
        iso_code, fiscal_year,
        indicator_value AS fiscal_balance_pct_gdp,
        LAG(indicator_value) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS fiscal_prev_year
    FROM weo
    WHERE indicator_name = 'Net lending (+) / net borrowing (-), General government, Percent of GDP'
),
debt_series AS (
    SELECT
        iso_code, fiscal_year,
        indicator_value AS debt_pct_gdp,
        LAG(indicator_value) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS debt_prev_year
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Percent of GDP'
),
ca_series AS (
    SELECT
        iso_code, fiscal_year,
        indicator_value AS ca_pct_gdp,
        LAG(indicator_value) OVER (PARTITION BY iso_code ORDER BY fiscal_year) AS ca_prev_year
    FROM weo
    WHERE indicator_name = 'Current account balance (credit less debit), Percent of GDP'
),
annual_flags AS (
    SELECT
        f.iso_code,
        f.fiscal_year,
        f.fiscal_balance_pct_gdp,
        d.debt_pct_gdp,
        c.ca_pct_gdp,
        CASE WHEN f.fiscal_balance_pct_gdp < f.fiscal_prev_year THEN 1 ELSE 0 END AS fiscal_worse,
        CASE WHEN d.debt_pct_gdp > d.debt_prev_year             THEN 1 ELSE 0 END AS debt_worse,
        CASE WHEN c.ca_pct_gdp < c.ca_prev_year                 THEN 1 ELSE 0 END AS ca_worse
    FROM fiscal_series f
    JOIN debt_series d ON f.iso_code = d.iso_code AND f.fiscal_year = d.fiscal_year
    JOIN ca_series c   ON f.iso_code = c.iso_code AND f.fiscal_year = c.fiscal_year
    WHERE f.fiscal_prev_year IS NOT NULL
      AND d.debt_prev_year   IS NOT NULL
      AND c.ca_prev_year     IS NOT NULL
),
streaks AS (
    SELECT
        iso_code, fiscal_year,
        fiscal_balance_pct_gdp, debt_pct_gdp, ca_pct_gdp,
        fiscal_worse, debt_worse, ca_worse,
        fiscal_year - ROW_NUMBER() OVER (PARTITION BY iso_code, fiscal_worse ORDER BY fiscal_year) AS fiscal_streak_group,
        fiscal_year - ROW_NUMBER() OVER (PARTITION BY iso_code, debt_worse   ORDER BY fiscal_year) AS debt_streak_group,
        fiscal_year - ROW_NUMBER() OVER (PARTITION BY iso_code, ca_worse     ORDER BY fiscal_year) AS ca_streak_group
    FROM annual_flags
),
streak_lengths AS (
    SELECT
        iso_code,
        MAX(fiscal_year) AS latest_year,
        SUM(CASE WHEN fiscal_worse = 1
                  AND fiscal_streak_group = (
                      SELECT fiscal_streak_group FROM streaks s2
                      WHERE s2.iso_code = s.iso_code AND s2.fiscal_worse = 1
                      ORDER BY s2.fiscal_year DESC LIMIT 1
                  ) THEN 1 ELSE 0 END) AS fiscal_deterioration_streak_yrs,
        SUM(CASE WHEN debt_worse = 1
                  AND debt_streak_group = (
                      SELECT debt_streak_group FROM streaks s2
                      WHERE s2.iso_code = s.iso_code AND s2.debt_worse = 1
                      ORDER BY s2.fiscal_year DESC LIMIT 1
                  ) THEN 1 ELSE 0 END) AS debt_deterioration_streak_yrs,
        SUM(CASE WHEN ca_worse = 1
                  AND ca_streak_group = (
                      SELECT ca_streak_group FROM streaks s2
                      WHERE s2.iso_code = s.iso_code AND s2.ca_worse = 1
                      ORDER BY s2.fiscal_year DESC LIMIT 1
                  ) THEN 1 ELSE 0 END) AS ca_deterioration_streak_yrs,
        MAX(CASE WHEN fiscal_year = (SELECT MAX(fiscal_year) FROM streaks s2 WHERE s2.iso_code = s.iso_code)
            THEN fiscal_balance_pct_gdp END) AS latest_fiscal_balance_pct_gdp,
        MAX(CASE WHEN fiscal_year = (SELECT MAX(fiscal_year) FROM streaks s2 WHERE s2.iso_code = s.iso_code)
            THEN debt_pct_gdp END) AS latest_debt_pct_gdp,
        MAX(CASE WHEN fiscal_year = (SELECT MAX(fiscal_year) FROM streaks s2 WHERE s2.iso_code = s.iso_code)
            THEN ca_pct_gdp END) AS latest_ca_pct_gdp
    FROM streaks s
    GROUP BY iso_code
)
SELECT
    m.country_name,
    m.region,
    m.income_group,
    sl.latest_year,
    sl.fiscal_deterioration_streak_yrs,
    sl.debt_deterioration_streak_yrs,
    sl.ca_deterioration_streak_yrs,
    (CASE WHEN sl.fiscal_deterioration_streak_yrs >= 3 THEN 1 ELSE 0 END +
     CASE WHEN sl.debt_deterioration_streak_yrs   >= 3 THEN 1 ELSE 0 END +
     CASE WHEN sl.ca_deterioration_streak_yrs     >= 3 THEN 1 ELSE 0 END) AS dimensions_on_3yr_plus_streak,
    ROUND(sl.latest_fiscal_balance_pct_gdp, 2) AS latest_fiscal_balance_pct_gdp,
    ROUND(sl.latest_debt_pct_gdp, 2) AS latest_debt_pct_gdp,
    ROUND(sl.latest_ca_pct_gdp, 2) AS latest_ca_pct_gdp,
    CASE
        WHEN (sl.fiscal_deterioration_streak_yrs >= 3 AND
              sl.debt_deterioration_streak_yrs   >= 3 AND
              sl.ca_deterioration_streak_yrs     >= 3) THEN 'RED - Structural Decline Across All Dimensions'
        WHEN (CASE WHEN sl.fiscal_deterioration_streak_yrs >= 3 THEN 1 ELSE 0 END +
              CASE WHEN sl.debt_deterioration_streak_yrs   >= 3 THEN 1 ELSE 0 END +
              CASE WHEN sl.ca_deterioration_streak_yrs     >= 3 THEN 1 ELSE 0 END) >= 2
             THEN 'YELLOW - Persistent Deterioration on Multiple Fronts'
        ELSE 'WATCH - Isolated or Short-Term Stress'
    END AS structural_decline_flag
FROM streak_lengths sl
JOIN meta m ON sl.iso_code = m.iso_code
WHERE sl.fiscal_deterioration_streak_yrs >= 3
   OR sl.debt_deterioration_streak_yrs   >= 3
   OR sl.ca_deterioration_streak_yrs     >= 3
ORDER BY dimensions_on_3yr_plus_streak DESC,
         sl.fiscal_deterioration_streak_yrs DESC;


