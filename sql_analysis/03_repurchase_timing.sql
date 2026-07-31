-- ==================================================================
-- 03. REPURCHASE TIMING: how long between a customer's orders?
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

WITH ordered_purchases AS (
    SELECT
        vendor,
        customer_id,
        order_date,
        LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date
    FROM customer_orders_clean
),
purchase_intervals AS (
    SELECT
        vendor,
        customer_id,
        EXTRACT(DAY FROM (next_order_date - order_date)) AS days_to_repurchase
    FROM ordered_purchases
    WHERE next_order_date IS NOT NULL
    AND EXTRACT(DAY FROM (next_order_date - order_date)) > 0   -- drop same-day double purchases
)
SELECT
    vendor,
    COUNT(DISTINCT customer_id) AS repeat_customers,
    COUNT(*) AS total_repeat_orders,
    ROUND(AVG(days_to_repurchase), 1) AS avg_days_to_repurchase,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_repurchase)::NUMERIC, 1) AS median_days_to_repurchase
FROM purchase_intervals
GROUP BY vendor
ORDER BY median_days_to_repurchase ASC;

-- Median days to 2nd purchase, across the whole portfolio
WITH first_two_orders AS (
    SELECT customer_id, order_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
    FROM customer_orders_clean
),
gap AS (
    SELECT a.customer_id, 
        EXTRACT(DAY FROM (b.order_date - a.order_date)) AS days_to_2nd
    FROM first_two_orders a
    JOIN first_two_orders b ON a.customer_id = b.customer_id AND b.rn = 2
    WHERE a.rn = 1
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_2nd) AS median_days_to_2nd_purchase
FROM gap;
