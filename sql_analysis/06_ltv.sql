-- ==================================================================
-- 06. LTV: what's a retained customer actually worth vs a one-timer?
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

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
customer_lifetime AS (
    SELECT customer_id, COUNT(DISTINCT order_name) AS total_orders, SUM(order_revenue) AS total_revenue
    FROM customer_orders_clean
    GROUP BY customer_id
)
SELECT
    f.vendor AS first_purchase_vendor,
    COUNT(DISTINCT f.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN cl.total_orders = 1 THEN f.customer_id END) AS one_time_buyers,
    COUNT(DISTINCT CASE WHEN cl.total_orders >= 2 THEN f.customer_id END) AS retained_customers,
    ROUND(AVG(CASE WHEN cl.total_orders = 1 THEN cl.total_revenue END), 2) AS avg_ltv_one_time,
    ROUND(AVG(CASE WHEN cl.total_orders >= 2 THEN cl.total_revenue END), 2) AS avg_ltv_retained,
    ROUND(AVG(CASE WHEN cl.total_orders >= 2 THEN cl.total_revenue END) /
          NULLIF(AVG(CASE WHEN cl.total_orders = 1 THEN cl.total_revenue END), 0), 2) AS ltv_multiplier
FROM first_order f
JOIN customer_lifetime cl ON f.customer_id = cl.customer_id
GROUP BY f.vendor
ORDER BY ltv_multiplier DESC;

-- retained customers are worth multiples of one-timers across the board.
-- marvl has the highest multiplier despite the worst retention rate --
-- biggest revenue opportunity sitting in the weakest brand
