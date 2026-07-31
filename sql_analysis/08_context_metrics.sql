-- ==================================================================
-- 08. CONTEXT METRICS: top-selling products, AOV, order frequency
--     Framing/supporting numbers for the write-up, not standalone findings.
--     Depends on: 01_setup.sql (customer_orders_clean, orders)
-- ==================================================================

SELECT lineitem_name, COUNT(DISTINCT order_name) AS order_count
FROM orders
WHERE financial_status = 'paid'
AND is_gratis = FALSE
GROUP BY lineitem_name
ORDER BY order_count DESC
LIMIT 30;

-- Overall AOV
SELECT ROUND(SUM(order_revenue) / COUNT(DISTINCT order_name), 2) AS aov
FROM customer_orders_clean;

-- AOV by brand
SELECT 
    vendor,
    ROUND(SUM(order_revenue) / COUNT(DISTINCT order_name), 2) AS aov,
    COUNT(DISTINCT order_name) AS total_orders
FROM customer_orders_clean
GROUP BY vendor
ORDER BY aov DESC;

-- Order frequency, by acquisition vendor
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
    SELECT customer_id, COUNT(DISTINCT order_name) AS num_orders
    FROM customer_orders_clean
    GROUP BY customer_id
)
SELECT 
    fo.acquisition_vendor AS vendor,
    CASE WHEN oc.num_orders >= 6 THEN '6+' ELSE oc.num_orders::text END AS order_frequency_bucket,
    COUNT(*) AS customer_count
FROM first_order fo
JOIN order_counts oc ON fo.customer_id = oc.customer_id
GROUP BY fo.acquisition_vendor, 
    CASE WHEN oc.num_orders >= 6 THEN '6+' ELSE oc.num_orders::text END
ORDER BY vendor, order_frequency_bucket;

-- Order frequency, by vendor of each order (not just acquisition vendor)
WITH customer_brand_order_counts AS (
    SELECT
        vendor,
        customer_id,
        COUNT(order_name) AS total_orders
    FROM customer_orders_clean
    WHERE vendor IS NOT NULL
    GROUP BY vendor, customer_id
)
SELECT
    vendor,
    CASE
        WHEN total_orders = 1 THEN '1 Order'
        WHEN total_orders = 2 THEN '2 Orders'
        WHEN total_orders BETWEEN 3 AND 5 THEN '3-5 Orders'
        ELSE '6+ Orders'
    END AS frequency_bin,
    CASE
        WHEN total_orders = 1 THEN 1
        WHEN total_orders = 2 THEN 2
        WHEN total_orders BETWEEN 3 AND 5 THEN 3
        ELSE 4
    END AS sort_order,
    COUNT(customer_id) AS total_customers,
    -- % of total customers within THAT specific brand
    ROUND(
        100.0 * COUNT(customer_id) / SUM(COUNT(customer_id)) OVER (PARTITION BY vendor), 
        2
    ) AS pct_of_brand_customers
FROM customer_brand_order_counts
GROUP BY vendor, frequency_bin, sort_order
ORDER BY vendor, sort_order;
