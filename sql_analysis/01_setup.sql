-- ==================================================================
-- PROJECT 3: SHOPIFY MULTI-BRAND RETENTION & LTV ANALYSIS
-- 01. SETUP: load raw orders, collapse to one row per order, exclude
--     non-DTC vendors, and build the clean view every other file reads from.
--
-- Story: the first order is the most important moment in this
-- business. What a customer buys first, and whether they got a
-- discount to buy it, predicts almost everything about whether
-- they come back and what they're worth.
-- ==================================================================

CREATE TABLE orders (
    order_name VARCHAR,
    email VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE,
    paid_at TIMESTAMP WITH TIME ZONE,
    financial_status VARCHAR,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    subtotal NUMERIC,
    total NUMERIC,
    discount_code VARCHAR,
    discount_amount NUMERIC,
    refunded_amount NUMERIC,
    accepts_marketing BOOLEAN,
    source VARCHAR,
    vendor VARCHAR,
    lineitem_name VARCHAR,
    lineitem_quantity INTEGER,
    lineitem_price NUMERIC,
    lineitem_sku VARCHAR,
    billing_country VARCHAR,
    billing_city VARCHAR,
    shipping_country VARCHAR,
    tags VARCHAR,
    note_attributes TEXT,
    notes TEXT,
    payment_id VARCHAR,
    gross_revenue NUMERIC,
    is_gratis BOOLEAN,
    first_touch_brand VARCHAR,
    last_touch_brand VARCHAR,
    has_attribution BOOLEAN
);

COPY orders FROM '/Applications/project_portfolio/brand_portfolio_orders_clean.csv'
DELIMITER ','
CSV HEADER;

-- quick check:
SELECT COUNT(*) FROM orders;
SELECT * FROM orders LIMIT 5;

-- collapse line-item-level rows into one row per order
DROP TABLE IF EXISTS customer_orders;

CREATE TABLE customer_orders AS
SELECT
    email AS customer_id,
    order_name,
    MIN(paid_at) AS order_date,
    SUM(gross_revenue) AS order_revenue,
    MAX(discount_amount) AS discount_amount,
    MAX(discount_code) AS discount_code,
    MAX(vendor) AS vendor,                          -- same vendor on every line item, MAX just picks it
    STRING_AGG(DISTINCT lineitem_name, ' | ') AS products_purchased,
    SUM(lineitem_quantity) AS total_items,
    BOOL_OR(accepts_marketing) AS accepts_marketing,
    MAX(billing_country) AS billing_country,         -- same for every line item, MAX just picks it
    MAX(tags) AS tags
FROM orders
WHERE financial_status = 'paid'
AND is_gratis = FALSE
AND paid_at IS NOT NULL
GROUP BY customer_id, order_name;

-- final analysis view: excludes a misattributed supplier and brand_x
DROP VIEW IF EXISTS customer_orders_clean;

CREATE VIEW customer_orders_clean AS
SELECT *
FROM customer_orders
WHERE vendor NOT IN ('supplier_x', 'brand_x');

-- sanity checks
SELECT COUNT(*) FROM customer_orders_clean WHERE order_date IS NULL;

-- monthly order volume, this is where the January acquisition spike showed up
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(DISTINCT order_name) AS total_orders
FROM customer_orders_clean
GROUP BY 1
ORDER BY 1;
