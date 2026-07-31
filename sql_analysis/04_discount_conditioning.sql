-- ==================================================================
-- 04. DISCOUNT CONDITIONING: does acquiring on a discount change
--     long-run customer behavior and margin?
--     Depends on: 01_setup.sql (customer_orders_clean)
-- ==================================================================

-- 4a. does a first-order discount change whether a customer comes back at all?
WITH orders_ranked AS (
    SELECT
        customer_id,
        order_date,
        discount_amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS order_chronology
    FROM customer_orders_clean
),
first_order_discount AS (
    SELECT
        customer_id,
        CASE WHEN discount_amount > 0 THEN 'Discount' ELSE 'Full Price' END AS first_order_type
    FROM orders_ranked
    WHERE order_chronology = 1
),
customer_order_totals AS (
    SELECT customer_id, MAX(order_chronology) AS total_orders
    FROM orders_ranked
    GROUP BY customer_id
)
SELECT
    f.first_order_type AS acquisition_type,
    COUNT(DISTINCT f.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN t.total_orders >= 2 THEN f.customer_id END) AS returned_2nd_order,
    ROUND(COUNT(DISTINCT CASE WHEN t.total_orders >= 2 THEN f.customer_id END) * 100.0
        / COUNT(DISTINCT f.customer_id), 2) AS second_order_retention_pct
FROM first_order_discount f
JOIN customer_order_totals t ON f.customer_id = t.customer_id
GROUP BY 1
ORDER BY 1;

-- retention rate is basically the same either way, a discount doesn't make someone more likely to come back

-- 4b. for the customers who do come back, are the discount-acquired ones still leaning on discounts, or did they convert to full price?
WITH orders_ranked AS (
    SELECT
        customer_id,
        discount_amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS order_chronology
    FROM customer_orders_clean
),
cohort_definition AS (
    SELECT
        customer_id,
        CASE WHEN discount_amount > 0 THEN 'Discount Acquired' ELSE 'Full Price Acquired' END AS acquisition_type
    FROM orders_ranked
    WHERE order_chronology = 1
)
SELECT
    c.acquisition_type,
    COUNT(*) AS total_return_orders,
    SUM(CASE WHEN o.discount_amount > 0 THEN 1 ELSE 0 END) AS discounted_return_orders,
    ROUND(SUM(CASE WHEN o.discount_amount > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS promo_dependent_pct
FROM orders_ranked o
JOIN cohort_definition c ON o.customer_id = c.customer_id
WHERE o.order_chronology > 1
GROUP BY 1
ORDER BY 1;

-- discount-acquired customers still use a promo on roughly half their return orders, vs a small minority for full-price-acquired customers

-- 4c. translate that gap into an actual euro cost
-- FIRST_VALUE grabs the discount amount from each customer's very first
-- order (ordered by date), which tells us their acquisition type
WITH customer_cohorts AS (
    SELECT
        customer_id,
        order_date,
        discount_amount,
        CASE WHEN FIRST_VALUE(discount_amount) OVER (PARTITION BY customer_id ORDER BY order_date ASC) > 0
            THEN 'Discount Acquired' ELSE 'Full Price Acquired'
        END AS acquisition_type,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS order_seq
    FROM customer_orders_clean
),
return_orders AS (
    SELECT acquisition_type, discount_amount
    FROM customer_cohorts
    WHERE order_seq > 1
),
baseline AS (
    SELECT
        SUM(CASE WHEN acquisition_type = 'Discount Acquired' THEN discount_amount ELSE 0 END) AS actual_discounts,
        COUNT(CASE WHEN acquisition_type = 'Discount Acquired' THEN 1 END) AS discount_return_orders,
        SUM(CASE WHEN acquisition_type = 'Full Price Acquired' THEN discount_amount ELSE 0 END) * 1.0
            / NULLIF(COUNT(CASE WHEN acquisition_type = 'Full Price Acquired' THEN 1 END), 0) AS full_price_avg_discount
    FROM return_orders
)
SELECT
    ROUND(actual_discounts, 2) AS actual_discounts_given,
    ROUND(discount_return_orders * full_price_avg_discount, 2) AS expected_if_no_conditioning,
    ROUND(actual_discounts - (discount_return_orders * full_price_avg_discount), 2) AS excess_margin_cost
FROM baseline;

-- excess_margin_cost = what we'd save if discount-acquired returners
-- discounted at the same rate as full-price-acquired returners
