# Multibrand-ecommerce-retention-and-LTV-analysis

This is a 5-brand Shopify store selling repeat-purchase consumables, some brands in home care, others in skin/body care. Findings were conveyed through a Power BI report.

## The Question

Which moment in the customer lifecycle actually predicts whether someone comes back, and where should acquisition and margin strategy focus as a result?

## Primary Metric

**Repeat Purchase Rate**: % of first-time paying customers who place a 2nd order, no time window limit.

## The Problem

Six brands sell through one platform, but nothing confirms whether they function as one connected business or six separate ones. Retention, repurchase behavior, and LTV are the levers available to test that, and to find out whether the first order is the moment that determines everything downstream.

## The Analysis

Data was pulled from 7 raw CSV exports, merged and cleaned in Python (pandas), then staged into PostgreSQL: 58k clean, paid orders across 5 months and 5 brands. Every supporting metric is anchored to a single, clearly defined population, first-order vendor attribution to avoid double-counting, and cumulative vs. per-period retention kept as two distinct numbers.

### Key findings

### 1. Retention has a hard ceiling

<img width="1330" height="747" alt="Page1V2" src="https://github.com/user-attachments/assets/58db8c51-0bb6-46c3-aca5-c2082f218d5c" />


23% cumulative retention (2nd order+), 11% per-period ceiling across all cohorts. January cohort: 21k new customers vs. 5–6.5k other months, yet worst immediate retention.

### 2. Discounts buy dependency, not loyalty

Discount and full-price acquired customers retain at the same rate (23%). But discount-acquired returners use a discount on 52% of return orders vs. 17% for full-price €43,084 in excess margin over 5 months.

<img width="1327" height="747" alt="Page2V2" src="https://github.com/user-attachments/assets/e1e2ada9-ac9d-4720-af58-cde4b4b8b870" />


### 3. Retention and value aren't the same lever

Brauzz retains best (48%) but has the lowest LTV multiplier (1.05x), wondr retains worst (15–16%) but has the highest (2.71x).

### 4. The products that sell the most aren't the products that bring customers back

<img width="1329" height="751" alt="PAge3V2" src="https://github.com/user-attachments/assets/225d4e39-d6e2-4cc2-9074-045ff3fe5df1" />

Best-retaining products (Hero Gateway, >35% retention) drive only 17.6% of first purchases, but retain customers at 48.95%. Worst-performing products retain under 15%, yet account for the largest single share of acquisitions.

## The Insight

The first order is the most important moment in this business** not because of what happens after it (there's no onboarding or CX data to test that), but because what a customer buys first already predicts whether they'll return. The data shows correlation between first-order profile and retention, not that changing onboarding would change the outcome.

## The Recommendation

| Priority | Recommendation | Stakeholder Team |
|---|---|---|
| 1 | Shift acquisition spend and placement toward Hero Gateway products, the ones that retain, instead of the volume drivers that convert easily but retain poorly | Marketing |
| 2 | Reconsider discount-based acquisition, it doesn't improve retention, just adds a recurring margin cost | Marketing/Finance |
| 3 | Run two strategies, not one: bundle brauzz/wondr/klaar since customers already cross-shop them; fix wondr and powr’s retention separately, starting with wondr, its customers are worth 2.7x more once retained | Leadership |

## Limitations & Scope

- No traffic, marketing, or session-level data exists for this dataset, retention/LTV is the only analyzable pillar, and no funnel or acquisition-channel claims are made.
- `planet_x` and one misattributed supplier record are excluded from all brand-level analysis (see `99_supporting_context.sql`).
- All findings are descriptive/predictive rather can causal.

## Tools

Python (Pandas), PostgreSQL, Power BI for the interactive dashboard (screenshots, provided in place of a hosted publish, due to Power BI Service publishing limitations).

