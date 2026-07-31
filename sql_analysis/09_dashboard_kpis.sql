-- ==================================================================
-- 09. DASHBOARD BASE VIEW + KPI CARDS
--     Page 2: Brand Synergy & Repeat Dynamics
--     One row per customer, first-order-attributed, tiebreaker-stable
--     (matches project convention). Every KPI/chart query on this page
--     reads from this one view so attribution/tiebreak logic can never
--     drift between cards. Export as a single table into Power BI and
--     drive all 4 KPI cards with DAX measures from the brand/date slicer.
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

CREATE OR REPLACE VIEW customer_synergy_base AS (
    WITH ordered AS (
        SELECT
            customer_id,
            order_name,
            order_date,
            order_revenue,
            vendor,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id
                ORDER BY order_date ASC, order_name ASC
            ) AS order_rank
        FROM customer_orders_clean
    ),

    first_order AS (
        SELECT
            customer_id,
            order_date AS first_order_date,
            vendor AS first_purchase_vendor,
            order_revenue AS first_order_revenue
        FROM ordered
        WHERE order_rank = 1
    ),

    second_order AS (
        SELECT
            customer_id,
            order_date AS second_order_date
        FROM ordered
        WHERE order_rank = 2
    ),

    customer_agg AS (
        SELECT
            customer_id,
            COUNT(*) AS total_orders,
            SUM(order_revenue) AS total_revenue,
            COUNT(DISTINCT vendor) AS distinct_brands_purchased
        FROM ordered
        GROUP BY customer_id
    )

    SELECT
        ca.customer_id,
        fo.first_purchase_vendor,
        fo.first_order_date,
        fo.first_order_revenue,
        so.second_order_date,
        (so.second_order_date - fo.first_order_date) AS days_to_second_order,
        ca.total_orders,
        ca.total_revenue,
        ca.total_revenue - fo.first_order_revenue AS repeat_order_revenue,
        CASE WHEN ca.total_orders >= 2 THEN 1 ELSE 0 END AS is_repeat_customer,
        ca.distinct_brands_purchased,
        CASE WHEN ca.distinct_brands_purchased > 1 THEN 1 ELSE 0 END AS is_cross_shopper
    FROM customer_agg ca
    JOIN first_order fo ON fo.customer_id = ca.customer_id
    LEFT JOIN second_order so ON so.customer_id = ca.customer_id
);

-- KPI card: Portfolio LTV
-- Average total customer revenue, by first-purchase brand and cohort month
SELECT
    first_purchase_vendor AS brand,
    DATE_TRUNC('month', first_order_date)::date AS cohort_month,
    ROUND(AVG(total_revenue), 2) AS portfolio_ltv
FROM customer_synergy_base
GROUP BY first_purchase_vendor, DATE_TRUNC('month', first_order_date)
ORDER BY brand, cohort_month;

-- KPI card: Repeat Interval
SELECT
    first_purchase_vendor AS brand,
    DATE_TRUNC('month', first_order_date)::date AS cohort_month,
    COUNT(*) AS repeat_customers_in_cell,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_second_order) AS repeat_interval_median_days
FROM customer_synergy_base
WHERE days_to_second_order IS NOT NULL
GROUP BY first_purchase_vendor, DATE_TRUNC('month', first_order_date)
ORDER BY brand, cohort_month;

-- KPI card: Cross-Shop Rate
SELECT
    first_purchase_vendor AS brand,
    DATE_TRUNC('month', first_order_date)::date AS cohort_month,
    COUNT(*) AS customers_in_cell,
    ROUND(100.0 * SUM(is_cross_shopper) / COUNT(*), 2) AS cross_shop_rate_pct
FROM customer_synergy_base
GROUP BY first_purchase_vendor, DATE_TRUNC('month', first_order_date)
ORDER BY brand, cohort_month;

-- KPI card: Repeat Revenue
-- Revenue from 2nd+ orders only (excludes first-order revenue), by first-purchase brand
-- and cohort month. Deliberately separate from Portfolio LTV so the two cards don't overlap.
SELECT
    first_purchase_vendor AS brand,
    DATE_TRUNC('month', first_order_date)::date AS cohort_month,
    ROUND(SUM(repeat_order_revenue), 2) AS repeat_revenue
FROM customer_synergy_base
GROUP BY first_purchase_vendor, DATE_TRUNC('month', first_order_date)
ORDER BY brand, cohort_month;
