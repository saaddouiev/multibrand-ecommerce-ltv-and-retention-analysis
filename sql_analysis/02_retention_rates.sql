-- ==================================================================
-- 02. RETENTION RATES: overall, monthly cohorts, and by brand
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

-- ------------------------------------------------------------------
-- Overall retention rate
-- ------------------------------------------------------------------

WITH ranked AS (
    SELECT
        customer_id,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date ASC, order_name ASC
        ) AS rn
    FROM customer_orders_clean
),
customer_status AS (
    SELECT customer_id, MAX(rn) AS total_orders
    FROM ranked
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS total_customers,
    COUNT(CASE WHEN total_orders >= 2 THEN 1 END) AS retained_customers,
    ROUND(COUNT(CASE WHEN total_orders >= 2 THEN 1 END) * 100.0 / COUNT(*), 2) AS overall_retention_rate
FROM customer_status;

-- New vs returning revenue split, by month and vendor
WITH first_order AS (
    SELECT customer_id, vendor AS acquisition_vendor, DATE_TRUNC('month', order_date) AS first_order_month
    FROM (
        SELECT customer_id, vendor, order_date,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
        FROM customer_orders_clean
    ) sub
    WHERE rn = 1
)
SELECT 
    DATE_TRUNC('month', co.order_date) AS order_month,
    co.vendor,
    CASE WHEN DATE_TRUNC('month', co.order_date) = fo.first_order_month THEN 'New' ELSE 'Returning' END AS customer_type,
    SUM(co.order_revenue) AS revenue,
    COUNT(DISTINCT co.order_name) AS orders
FROM customer_orders_clean co
JOIN first_order fo ON co.customer_id = fo.customer_id
GROUP BY order_month, vendor, customer_type
ORDER BY vendor, order_month, customer_type;

-- spot-check: marvlcare orders from a specific recent window
SELECT order_name, order_date, order_revenue, products_purchased, tags
FROM customer_orders_clean
WHERE vendor = 'marvlcare' AND order_date >= '2026-05-01'
ORDER BY order_date;

-- ------------------------------------------------------------------
-- Cohort view: retention by months since first purchase
-- ------------------------------------------------------------------

WITH user_cohorts AS (
    SELECT customer_id, DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM customer_orders_clean
    GROUP BY customer_id
),
user_activities AS (
    SELECT
        co.customer_id,
        uc.cohort_month,
        (EXTRACT(YEAR FROM co.order_date) * 12 + EXTRACT(MONTH FROM co.order_date))
        - (EXTRACT(YEAR FROM uc.cohort_month) * 12 + EXTRACT(MONTH FROM uc.cohort_month)) AS period_index
    FROM customer_orders_clean co
    JOIN user_cohorts uc ON co.customer_id = uc.customer_id
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS total_users
    FROM user_cohorts
    GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    s.total_users AS cohort_size,
    a.period_index AS months_after_first_purchase,
    COUNT(DISTINCT a.customer_id) AS retained_users,
    ROUND(COUNT(DISTINCT a.customer_id) * 100.0 / s.total_users, 2) AS retention_rate
FROM user_activities a
JOIN cohort_sizes s ON a.cohort_month = s.cohort_month
GROUP BY 1, 2, 3
ORDER BY 1, 3;

-- retention settles to a fairly flat ceiling per period across cohorts.
-- January stands out: by far the biggest acquisition month, but the weakest immediate retention, likely a seasonal/gift giving effect.

-- Cohort analysis by brand
WITH first_order AS (
    SELECT customer_id, vendor,
        DATE_TRUNC('month', order_date) AS cohort_month,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
    FROM customer_orders_clean
),
first_order_only AS (
    SELECT customer_id, vendor, cohort_month FROM first_order WHERE rn = 1
),
customer_activity AS (
    SELECT co.customer_id, fo.vendor, fo.cohort_month,
        DATE_TRUNC('month', co.order_date) AS activity_month
    FROM customer_orders_clean co
    JOIN first_order_only fo ON co.customer_id = fo.customer_id
),
cohort_data AS (
    SELECT vendor, cohort_month, activity_month,
        (EXTRACT(YEAR FROM activity_month) - EXTRACT(YEAR FROM cohort_month)) * 12 +
        (EXTRACT(MONTH FROM activity_month) - EXTRACT(MONTH FROM cohort_month)) AS period_number,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM customer_activity
    GROUP BY vendor, cohort_month, activity_month
),
cohort_size AS (
    SELECT vendor, cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM first_order_only
    GROUP BY vendor, cohort_month
)
SELECT cd.vendor, cd.cohort_month, cd.period_number, cs.cohort_size,
    cd.active_customers,
    ROUND(cd.active_customers::numeric / cs.cohort_size, 4) AS retention_rate
FROM cohort_data cd
JOIN cohort_size cs ON cd.vendor = cs.vendor AND cd.cohort_month = cs.cohort_month
ORDER BY cd.vendor, cd.cohort_month, cd.period_number;

-- ------------------------------------------------------------------
-- Retention by vendor: does the first brand someone buys from matter?
-- ------------------------------------------------------------------

WITH ranked AS (
    SELECT
        customer_id,
        vendor,
        order_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
    FROM customer_orders_clean
),
first_order AS (
    SELECT customer_id, vendor
    FROM ranked
    WHERE rn = 1
),
repeat_customers AS (
    SELECT DISTINCT customer_id
    FROM ranked
    WHERE rn > 1
)
SELECT
    f.vendor AS first_purchase_vendor,
    COUNT(DISTINCT f.customer_id) AS total_customers,
    COUNT(DISTINCT r.customer_id) AS returned_customers,
    ROUND(COUNT(DISTINCT r.customer_id) * 100.0 / COUNT(DISTINCT f.customer_id), 2) AS retention_rate
FROM first_order f
LEFT JOIN repeat_customers r ON f.customer_id = r.customer_id
GROUP BY 1
ORDER BY retention_rate DESC;

-- fresh retains far above the rest; marvl and mighty sit at the bottom. marvl's sheer order volume is what drags the whole store's average down.

-- Retention rate and revenue by brand
WITH first_order AS (
    SELECT customer_id, vendor AS acquisition_vendor
    FROM (
        SELECT customer_id, vendor, order_date,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
        FROM customer_orders_clean
    ) sub
    WHERE rn = 1
),
order_counts AS (
    SELECT customer_id, COUNT(DISTINCT order_name) AS order_count
    FROM customer_orders_clean
    GROUP BY customer_id
),
brand_sales AS (
    SELECT fo.acquisition_vendor AS vendor, SUM(co.order_revenue) AS total_sales
    FROM customer_orders_clean co
    JOIN first_order fo ON co.customer_id = fo.customer_id
    GROUP BY fo.acquisition_vendor
)
SELECT 
    fo.acquisition_vendor AS vendor,
    bs.total_sales,
    ROUND(COUNT(DISTINCT fo.customer_id) FILTER (WHERE oc.order_count >= 2)::numeric 
        / COUNT(DISTINCT fo.customer_id), 4) AS retention_rate
FROM first_order fo
JOIN order_counts oc ON fo.customer_id = oc.customer_id
JOIN brand_sales bs ON fo.acquisition_vendor = bs.vendor
GROUP BY fo.acquisition_vendor, bs.total_sales
ORDER BY retention_rate DESC;

-- spot-check on the excluded vendor, confirming it's safe to leave out of the clean view
SELECT vendor, COUNT(*), SUM(order_revenue), 
       MIN(order_date), MAX(order_date),
       array_agg(DISTINCT tags) AS sample_tags
FROM customer_orders
WHERE vendor = 'brand_x'
GROUP BY vendor;
