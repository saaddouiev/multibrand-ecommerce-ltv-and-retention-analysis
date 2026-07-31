-- ==================================================================
-- 05. CROSS-BRAND BEHAVIOR: do customers shop across the brands,
--     or are these separate customer bases?
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

WITH first_order AS (
    SELECT customer_id, vendor AS acquisition_vendor
    FROM (
        SELECT customer_id, vendor, order_date,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC, order_name ASC) AS rn
        FROM customer_orders_clean
    ) sub
    WHERE rn = 1
),
customer_brands AS (
    SELECT DISTINCT customer_id, vendor AS purchased_vendor
    FROM customer_orders_clean
)
SELECT 
    fo.acquisition_vendor,
    cb.purchased_vendor,
    COUNT(DISTINCT fo.customer_id) AS customer_count
FROM first_order fo
JOIN customer_brands cb ON fo.customer_id = cb.customer_id
GROUP BY fo.acquisition_vendor, cb.purchased_vendor
ORDER BY fo.acquisition_vendor, cb.purchased_vendor;

-- most customers stay within their acquisition brand; cross-shopping is the exception, not the norm
