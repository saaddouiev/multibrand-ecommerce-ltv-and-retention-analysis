-- ==================================================================
-- 07. PRODUCT & CATEGORY RETENTION: does the FIRST PRODUCT someone
--     buys predict retention?
--     Depends on: 01_setup.sql (customer_orders_clean, orders)
-- ==================================================================

-- ------------------------------------------------------------------
-- 7a. Single-brand deep dive (marvl and marvlcare, the two vendors with
--     enough product variety for this to be meaningful at this stage)
-- ------------------------------------------------------------------

-- marvl
WITH first_order_names AS (
    SELECT customer_id, order_name
    FROM (
        SELECT
            customer_id,
            order_name,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
        WHERE vendor = 'marvl'
    ) ranked
    WHERE rn = 1
),
first_product AS (
    -- an order can have multiple line items; treat the highest-priced
    -- item as "the" first product for that order
    SELECT fon.customer_id, ranked.lineitem_name AS first_product
    FROM first_order_names fon
    JOIN (
        SELECT
            order_name,
            lineitem_name,
            lineitem_price,
            ROW_NUMBER() OVER (PARTITION BY order_name ORDER BY lineitem_price DESC) AS rn
        FROM orders
        WHERE financial_status = 'paid' AND is_gratis = FALSE
    ) ranked ON fon.order_name = ranked.order_name
    WHERE ranked.rn = 1
),
returned AS (
    SELECT DISTINCT customer_id
    FROM (
        SELECT customer_id, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
    ) ranked
    WHERE rn > 1
)
SELECT
    fp.first_product,
    COUNT(DISTINCT fp.customer_id) AS total_customers,
    COUNT(DISTINCT r.customer_id) AS returned_customers,
    ROUND(COUNT(DISTINCT r.customer_id) * 100.0 / COUNT(DISTINCT fp.customer_id), 2) AS retention_rate
FROM first_product fp
LEFT JOIN returned r ON fp.customer_id = r.customer_id
GROUP BY 1
HAVING COUNT(DISTINCT fp.customer_id) > 100
ORDER BY retention_rate DESC;

-- marvlcare (same logic, different vendor filter and a lower volume threshold
-- since marvlcare has fewer orders)
WITH first_order_names AS (
    SELECT customer_id, order_name
    FROM (
        SELECT
            customer_id,
            order_name,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
        WHERE vendor = 'marvlcare'
    ) ranked
    WHERE rn = 1
),
first_product AS (
    SELECT fon.customer_id, ranked.lineitem_name AS first_product
    FROM first_order_names fon
    JOIN (
        SELECT
            order_name,
            lineitem_name,
            lineitem_price,
            ROW_NUMBER() OVER (PARTITION BY order_name ORDER BY lineitem_price DESC) AS rn
        FROM orders
        WHERE financial_status = 'paid' AND is_gratis = FALSE
    ) ranked ON fon.order_name = ranked.order_name
    WHERE ranked.rn = 1
),
returned AS (
    SELECT DISTINCT customer_id
    FROM (
        SELECT customer_id, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
    ) ranked
    WHERE rn > 1
)
SELECT
    fp.first_product,
    COUNT(DISTINCT fp.customer_id) AS total_customers,
    COUNT(DISTINCT r.customer_id) AS returned_customers,
    ROUND(COUNT(DISTINCT r.customer_id) * 100.0 / COUNT(DISTINCT fp.customer_id), 2) AS retention_rate
FROM first_product fp
LEFT JOIN returned r ON fp.customer_id = r.customer_id
GROUP BY 1
HAVING COUNT(DISTINCT fp.customer_id) > 50
ORDER BY retention_rate DESC;

-- skincare products retain far better than shampoo bars, which retain better than the safety razor kits, first product predicts return
-- behavior, which points to an acquisition-targeting recommendation, not a CX/onboarding one

-- ------------------------------------------------------------------
-- 7b. Portfolio-wide version: same question, extended to every brand
--     at once, with category tagging for a clean visual slicer
-- ------------------------------------------------------------------

SELECT DISTINCT products_purchased 
FROM customer_orders_clean
LIMIT 200;

WITH customer_orders_ranked AS (
    -- Step 1: Rank orders for each customer to isolate Order #1
    SELECT 
        customer_id,
        order_name,
        order_date,
        vendor,
        products_purchased,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id 
            ORDER BY order_date ASC, order_name ASC
        ) AS order_rank
    FROM customer_orders_clean
),

first_order_products AS (
    -- Step 2: Unnest pipe-separated (|) products on Order #1 & strip extra spacing
    SELECT DISTINCT
        customer_id,
        LOWER(TRIM(vendor)) AS vendor,
        TRIM(p.gateway_product) AS gateway_product,
        order_date AS first_order_date
    FROM customer_orders_ranked
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(products_purchased, '|')) AS p(gateway_product)
    WHERE order_rank = 1
      AND TRIM(p.gateway_product) != ''
),

customer_lifecycle_summary AS (
    -- Step 3: Count total lifetime orders per customer & flag retained buyers (> 1 order)
    SELECT 
        fo.customer_id,
        fo.vendor,
        fo.gateway_product,
        COUNT(DISTINCT o.order_name) AS total_orders,
        CASE 
            WHEN COUNT(DISTINCT o.order_name) > 1 THEN 1 
            ELSE 0 
        END AS is_retained_customer
    FROM first_order_products fo
    INNER JOIN customer_orders_clean o 
        ON fo.customer_id = o.customer_id
    GROUP BY 
        fo.customer_id, 
        fo.vendor,
        fo.gateway_product
)

-- Step 4: Final metric aggregation + category tagging
SELECT 
    vendor,
    gateway_product,

    -- High-level category mapping for clean visual slicing
    CASE 
        WHEN gateway_product ILIKE '%vaatwas%' OR gateway_product ILIKE '%mighty%' THEN 'Dishwasher Care'
        WHEN gateway_product ILIKE '%toilet%' THEN 'Toilet Care'
        WHEN gateway_product ILIKE '%wasstrip%' THEN 'Laundry Care'
        WHEN gateway_product ILIKE '%cream%' OR gateway_product ILIKE '%serum%' THEN 'Facial Skincare'
        WHEN gateway_product ILIKE '%shampoo bar%' OR gateway_product ILIKE '%conditioner bar%' THEN 'Haircare Bars'
        WHEN gateway_product ILIKE '%handdoek%' OR gateway_product ILIKE '%holder%' OR gateway_product ILIKE '%terrazzo%' THEN 'Accessories & Hardware'
        ELSE 'Other Consumables'
    END AS product_category,

    COUNT(customer_id) AS total_customers_acquired,
    SUM(is_retained_customer) AS retained_customers,
    ROUND(
        100.0 * SUM(is_retained_customer) / NULLIF(COUNT(customer_id), 0), 
        2
    ) AS repeat_purchase_rate_pct,
    ROUND(AVG(total_orders), 2) AS avg_orders_per_customer

FROM customer_lifecycle_summary
GROUP BY 
    vendor, 
    gateway_product,
    product_category
HAVING COUNT(customer_id) >= 15 -- filters out single-digit sample noise
ORDER BY 
    vendor ASC,
    repeat_purchase_rate_pct DESC;

-- Retaining products for each brand: acquisition volume + retention rate,
-- with a benchmark-based tier (final version — includes minimum sample
-- size floor to prevent small-n products showing misleadingly high rates)
WITH customer_first_orders AS (
    -- Step 1: Identify absolute first order date & order name for every customer
    SELECT 
        customer_id,
        order_name,
        order_date
    FROM (
        SELECT 
            customer_id,
            order_name,
            order_date,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
    ) ranked_orders
    WHERE rn = 1
),

first_order_products AS (
    -- Step 2: Extract primary (highest-priced) product for each customer's first order
    SELECT 
        fo.customer_id,
        o.vendor,
        o.lineitem_name AS first_product
    FROM customer_first_orders fo
    JOIN (
        SELECT 
            order_name,
            vendor,
            lineitem_name,
            lineitem_price,
            ROW_NUMBER() OVER (PARTITION BY order_name ORDER BY lineitem_price DESC) AS rn
        FROM orders
        WHERE financial_status = 'paid' 
          AND is_gratis = FALSE
    ) o ON fo.order_name = o.order_name
    WHERE o.rn = 1
),

retained_customers AS (
    -- Step 3: Flag customers who made 2 or more total orders on the site
    SELECT DISTINCT customer_id
    FROM (
        SELECT 
            customer_id,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS rn
        FROM customer_orders_clean
    ) ranked_orders
    WHERE rn > 1
),

product_metrics AS (
    -- Step 4: Calculate total acquisitions & retention rate per product
    -- minimum sample size floor eliminates low-volume noise (e.g. 1 out of 2 = 50%)
    SELECT 
        fop.vendor,
        fop.first_product,
        COUNT(DISTINCT fop.customer_id) AS total_acquisitions,
        COUNT(DISTINCT rc.customer_id) AS retained_customers,
        ROUND(COUNT(DISTINCT rc.customer_id) * 100.0 / COUNT(DISTINCT fop.customer_id), 2) AS retention_rate_pct
    FROM first_order_products fop
    LEFT JOIN retained_customers rc ON fop.customer_id = rc.customer_id
    GROUP BY fop.vendor, fop.first_product
    HAVING COUNT(DISTINCT fop.customer_id) >= 20
)

-- Step 5: Final evaluation using industry-standard DTC benchmarks
SELECT 
    vendor,
    first_product,
    total_acquisitions,
    retained_customers,
    retention_rate_pct,
    CASE 
        WHEN retention_rate_pct >= 35.0 THEN 'Hero Gateway (Elite >35% Retention)'
        WHEN retention_rate_pct >= 25.0 THEN 'Solid Performer (DTC Average 25-34%)'
        WHEN retention_rate_pct >= 15.0 THEN 'Below Average (15-24% Retention)'
        ELSE 'Acquisition Trap (<15% Retention Leak)'
    END AS retention_profile
FROM product_metrics
ORDER BY vendor ASC, retention_rate_pct DESC;
