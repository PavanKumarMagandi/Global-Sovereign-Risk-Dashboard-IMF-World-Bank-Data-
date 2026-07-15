# 🌍 Global Sovereign Risk Dashboard — IMF & World Bank Data

[![SQL](https://img.shields.io/badge/SQL-PostgreSQL-336791?logo=postgresql&logoColor=white)](#-tech-stack)
[![Excel](https://img.shields.io/badge/Dashboard-Excel-217346?logo=microsoftexcel&logoColor=white)](#-repository-structure)
[![Live Demo](https://img.shields.io/badge/Live%20Demo-Sovereign%20Risk%20Terminal-black?logo=githubpages&logoColor=white)](https://pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-/)
[![Data](https://img.shields.io/badge/Data-IMF%20WEO%20%7C%20World%20Bank%20GEM-blue)](#-data-sources)

**Sovereign credit risk, macroeconomic, and fiscal stress analysis** built on IMF World Economic Outlook (WEO) and World Bank Global Economic Monitor (GEM) data, covering **183 countries from 2000–2031**.

This repository contains a **PostgreSQL analytical query suite**, a **fully modeled Excel dashboard**, and a **live interactive web terminal** for evaluating sovereign debt sustainability, currency risk, liquidity, fiscal deficits, and macroeconomic stress signals across global economies — the kind of analysis used in emerging-market (EM) bond investing, IMF program design, sovereign credit ratings, and country-risk research.

🔗 **[Launch the Live Dashboard →](https://pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-/)**

---

## 📑 Table of Contents

- [Project Overview](#-project-overview)
- [Live Dashboard](#-live-dashboard)
- [Repository Structure](#-repository-structure)
- [Database Schema](#️-database-schema)
- [The 10 Analytical Queries](#-the-10-analytical-queries)
- [Risk Flag Convention](#-risk-flag-convention)
- [How to Run](#️-how-to-run)
- [Tech Stack](#-tech-stack) 
- [Data Sources](#-data-sources)
- [Author](#-author)

---

## 🔑 Keywords / Topics

`sql` `postgresql` `sovereign-risk` `data-analysis` `excel-dashboard` `macroeconomics`
`imf-data` `world-bank-data` `emerging-markets` `fixed-income` `credit-risk`
`financial-analytics` `business-intelligence` `fiscal-policy` `debt-sustainability`
`country-risk` `data-analytics-portfolio` `finance-sql` `dashboard-design`
`risk-management` `economic-indicators` `weo` `gem-data` `sql-portfolio-project`

---

## 📌 Project Overview

Sovereign risk analysis answers a single core question: **can a country meet its financial obligations without defaulting, restructuring, or triggering a currency crisis?**

Most public dashboards stop at one or two static ratios — debt-to-GDP, maybe a fiscal deficit number. This project goes further by combining **two complementary data sources at different frequencies**:

| Source | Frequency | Coverage |
|---|---|---|
| **IMF World Economic Outlook (WEO)** | Annual (structural forecasts) | ~190 countries, 2000–2031 (2025–2031 = IMF projections) |
| **World Bank Global Economic Monitor (GEM)** | Monthly (market-pulse data) | ~190 countries, monthly observations |

The result is a **multi-dimensional sovereign risk intelligence layer** — solvency, liquidity, currency overvaluation, trade resilience, fiscal efficiency, social-political stress, market mispricing, debt trajectory, regional contagion, and structural multi-year decline — each built to answer *"what should we do?"*, not just report a number.

Every risk-classification query follows a consistent **🔴 RED / 🟡 YELLOW / 🟢 GREEN** flag convention, with thresholds grounded in IMF, World Bank, and sovereign credit literature benchmarks.

---

## 🖥️ Live Dashboard

**[pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-](https://pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-/)**

The 10 SQL queries are published as an interactive **"Sovereign Risk Terminal"** — a browser-based dashboard that turns the static query outputs into a filterable, visual research console organized around four risk pillars:

| Pillar | Screens |
|---|---|
| **I — Solvency & Liquidity** | Reserves vs. Debt · Fiscal Doomsday Clock |
| **II — External Sector & Currency** | Devaluation Risk · Trade Resilience · PPP Mispricing |
| **III — Fiscal Quality & Markets** | Market Disconnect · Spending Efficiency |
| **IV — Structural Trajectory** | Misery Index · Deterioration Streaks |

Also included is a standalone **Regional Contagion** view, clustering countries by simultaneous stress across debt burden, reserve adequacy, fiscal deficit, and current account deficit.

**Key features:**
- Global filter console — slice every screen by **region, country, composite Safe Score, and year**
- Each screen pairs a chart view with a **full data table** (e.g., 30 highest-debt economies, 184 currencies, 116 countries)
- Bubble charts, ranked leaderboards, and trajectory views driven directly by the pre-aggregated SQL outputs — no client-side recalculation of the underlying risk logic
- Consistent 🔴 Red / 🟠 Amber / 🟢 Green / 🔵 Blue flag convention carried over from the SQL layer, with Blue added for valuation/opportunity signals

The dashboard is a static site reading directly from the Q1–Q10 query outputs (CSV), making it a lightweight, dependency-free way to explore the same analysis in `SQL_GSR.sql` without running PostgreSQL locally.

---

## 📁 Repository Structure

```
├── SQL_GSR.sql                       # 10 self-contained PostgreSQL analytical queries
├── Global_sovereign_risk_excel.xlsx  # Multi-sheet Excel workbook: dashboard + raw/transformed data
└── README.md
```

> The live web dashboard is hosted separately via GitHub Pages, built on the outputs of `SQL_GSR.sql`. See [Live Dashboard](#-live-dashboard) above.

### Excel workbook contents

| Sheet | Purpose |
|---|---|
| `About` | Project background and methodology notes |
| `Dashboard` | Executive summary view of key sovereign risk indicators |
| `Crisis Watch` | Live RED / YELLOW / GREEN flagged countries |
| `Investors View` | EM investor-oriented risk/return snapshot |
| `Safe Score` | Composite sovereign safety scoring model |
| `Master Sheet` | Cleaned, joined master dataset used across the dashboard |
| `Countries Meta` | Country metadata — region, income group, lending category |
| `GEM` / `GEM-Transformed` | Raw and cleaned World Bank Global Economic Monitor data |
| `WEO April 2026` / `WEO-Transformed` | Raw and cleaned IMF World Economic Outlook data |
| `Master Sheet Raw` | Pre-transformation combined dataset |

---

## 🗄️ Database Schema

```sql
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
```

Recommended indexes for performance on large WEO/GEM tables:

```sql
CREATE INDEX idx_weo_indicator ON weo (indicator_name, iso_code, fiscal_year);
CREATE INDEX idx_gem_indicator ON gem (indicator_name, iso_code, fiscal_year, month);
```

---

## 📊 The 10 Analytical Queries

Each query in [`SQL_GSR.sql`](./SQL_GSR.sql) is self-contained (no cross-query dependencies) and maps to a specific sovereign risk dimension. Every query also powers a corresponding screen in the [live dashboard](#-live-dashboard).

| # | Query | Risk Dimension |
|---|---|---|
| 1 | The Reserves-vs-Debt Solvency Cross-Check | Solvency & liquidity |
| 2 | Currency Overvaluation vs. External Imbalance | Currency risk |
| 3 | Trade Resilience by Income Group | Trade resilience |
| 4 | Stock Market Disconnect from Macro Fundamentals | Market mispricing |
| 5 | Unemployment-Inflation Misery Ranking, Region-Adjusted | Social-political stress |
| 6 | Government Spending Efficiency vs. Growth Payoff | Fiscal efficiency |
| 7 | The PPP Currency Mispricing Gap ("Implied Fair Value" Screen) | Currency mispricing |
| 8 | The Fiscal Doomsday Clock | Debt trajectory |
| 9 | Regional Sovereign Stress Clustering | Regional contagion |
| 10 | The Consecutive-Year Deterioration Streak | Structural multi-year decline |

### Example — Query 1: Reserves-vs-Debt Solvency Cross-Check

Compares actual FX reserves (USD) against actual government debt (USD) — rather than mismatched ratios like "debt % of GDP" vs. "months of import cover" — and tracks the reserve cushion's 6-month trend for an early-warning signal.

```sql
WITH latest_debt_pct AS (
    SELECT DISTINCT ON (iso_code)
        iso_code, fiscal_year, indicator_value AS debt_pct_gdp
    FROM weo
    WHERE indicator_name = 'Gross debt, General government, Percent of GDP'
    ORDER BY iso_code, fiscal_year DESC
)
-- ...full query in SQL_GSR.sql (Question 1)
SELECT
    m.country_name, m.region, m.income_group,
    debt_pct_gdp, gdp_usd_billions, debt_usd_billions,
    reserves_now_usd_billions, reserves_6mo_ago_usd_billions,
    reserve_change_6mo_usd_billions, reserves_pct_of_debt,
    months_import_cover, liquidity_risk_flag
FROM ...
WHERE debt_pct_gdp > 70
  AND reserves_pct_of_debt < 15
ORDER BY reserves_pct_of_debt ASC;
```

*(The remaining 9 queries — full text, business rationale, and thresholds — are documented inline in [`SQL_GSR.sql`](./SQL_GSR.sql), and visualized live on the [dashboard](#-live-dashboard).)*

---

## 🚦 Risk Flag Convention

| Flag | Meaning |
|---|---|
| 🔴 **RED** | Breach of the primary danger threshold — requires immediate attention |
| 🟡 **YELLOW / AMBER** | Breach of the elevated-risk threshold — warrants active monitoring |
| 🟢 **GREEN** | Within acceptable bounds for the specific indicator measured |
| 🔵 **BLUE** | Valuation / opportunity signal *(dashboard only — e.g. currency mispricing screens)* |

---

## ⚙️ How to Run

**Environment:** PostgreSQL 13+
**Database:** `sovereign_risk` (or any database with the three tables above loaded)

```bash
# 1. Create the database
createdb sovereign_risk

# 2. Load the schema and data (adjust to your data-loading process)
psql -d sovereign_risk -f SQL_GSR.sql

# 3. Run any of the 10 queries independently, or all sequentially
#    for the full dashboard output
```

Each query block is independent — no need to run them in order except to reproduce the full dashboard.

Prefer not to set up PostgreSQL locally? Explore the same 10 screens instantly in the **[live web dashboard](https://pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-/)**.

---

## 🛠️ Tech Stack

- **SQL (PostgreSQL)** — CTEs, window functions, `DISTINCT ON`, conditional risk-flagging logic
- **Microsoft Excel** — multi-sheet dashboarding, data transformation, composite scoring models
- **Web** — static interactive dashboard (GitHub Pages) reading pre-aggregated SQL query outputs, with region/country/score/year filtering
- **Version Control** — Git & GitHub

---

## 🌐 Data Sources

- [IMF World Economic Outlook (WEO)](https://www.imf.org/en/Publications/WEO)
- [World Bank Global Economic Monitor (GEM)](https://databank.worldbank.org/source/global-economic-monitor)
- World Bank Country Metadata (region, income group, lending category)

---

## 👤 Author

**Pavan Kumar Magandi**
🔗 [GitHub](https://github.com/PavanKumarMagandi)
🌐 [Live Dashboard](https://pavankumarmagandi.github.io/Global-Sovereign-Risk-Dashboard-IMF-World-Bank-Data-/)
✉️ pavanmagandi@gmail.com

---

⭐ **If this project is useful for your own sovereign risk / SQL portfolio work, consider starring the repo!**
