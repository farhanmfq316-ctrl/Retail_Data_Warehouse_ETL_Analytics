-- ============================================================
-- RETAIL DATA WAREHOUSE & ETL ANALYTICS
-- ============================================================
-- Project:
-- Retail Data Warehouse & ETL Analytics
--
-- Database:
-- retail_dw
--
-- Technology:
-- Python | PostgreSQL | SQL | Power BI
--
-- Author:
-- Mohammad Farhan
--
-- ETL Note:
-- Source CSV files were cleaned, validated and transformed
-- using Python/Pandas before loading into PostgreSQL.
-- ============================================================


-- ============================================================
-- 1. DATA WAREHOUSE TABLES
-- ============================================================


-- ------------------------------------------------------------
-- 1.1 Dimension: Date
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_date (
    date_key INTEGER PRIMARY KEY,
    date DATE NOT NULL,
    year INTEGER NOT NULL,
    quarter VARCHAR(2) NOT NULL,
    month_number INTEGER NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    month_short VARCHAR(3) NOT NULL,
    week_number INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    day_of_week INTEGER NOT NULL
);


-- ------------------------------------------------------------
-- 1.2 Dimension: Customer
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key INTEGER PRIMARY KEY,
    person_key INTEGER,
    store_key INTEGER,
    territory_key INTEGER NOT NULL,
    account_number VARCHAR(20) NOT NULL
);


-- ------------------------------------------------------------
-- 1.3 Dimension: Store
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_store (
    store_key INTEGER PRIMARY KEY,
    store_name VARCHAR(200) NOT NULL,
    sales_person_key INTEGER
);


-- ------------------------------------------------------------
-- 1.4 Dimension: Territory
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_territory (
    territory_key INTEGER PRIMARY KEY,
    territory_name VARCHAR(100) NOT NULL,
    country_code VARCHAR(10) NOT NULL,
    region_group VARCHAR(100) NOT NULL
);


-- ------------------------------------------------------------
-- 1.5 Dimension: Product
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_product (
    product_key INTEGER PRIMARY KEY,
    product_name VARCHAR(200) NOT NULL,
    product_number VARCHAR(50) NOT NULL,
    color VARCHAR(50),
    size VARCHAR(50),
    standard_cost NUMERIC(18,2) NOT NULL,
    list_price NUMERIC(18,2) NOT NULL,
    product_line VARCHAR(50),
    product_class VARCHAR(50),
    style VARCHAR(50),
    product_subcategory_key INTEGER NOT NULL,
    product_category_key INTEGER NOT NULL,
    category_name VARCHAR(100) NOT NULL
);


-- ------------------------------------------------------------
-- 1.6 Fact: Sales
-- Grain: One row per sales order line
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fact_sales (
    sales_order_detail_key INTEGER PRIMARY KEY,
    order_key INTEGER NOT NULL,
    date_key INTEGER NOT NULL,
    customer_key INTEGER NOT NULL,
    product_key INTEGER NOT NULL,
    territory_key INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(18,6) NOT NULL,
    discount_rate NUMERIC(18,6) NOT NULL,
    sales_amount NUMERIC(18,6) NOT NULL,
    store_key INTEGER,

    CONSTRAINT fk_sales_date
        FOREIGN KEY (date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT fk_sales_customer
        FOREIGN KEY (customer_key)
        REFERENCES dim_customer(customer_key),

    CONSTRAINT fk_sales_product
        FOREIGN KEY (product_key)
        REFERENCES dim_product(product_key),

    CONSTRAINT fk_sales_territory
        FOREIGN KEY (territory_key)
        REFERENCES dim_territory(territory_key),

    CONSTRAINT fk_sales_store
        FOREIGN KEY (store_key)
        REFERENCES dim_store(store_key)
);


-- ============================================================
-- 2. WAREHOUSE ROW COUNTS
-- ============================================================

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count
FROM dim_date

UNION ALL

SELECT 'dim_customer', COUNT(*)
FROM dim_customer

UNION ALL

SELECT 'dim_store', COUNT(*)
FROM dim_store

UNION ALL

SELECT 'dim_territory', COUNT(*)
FROM dim_territory

UNION ALL

SELECT 'dim_product', COUNT(*)
FROM dim_product

UNION ALL

SELECT 'fact_sales', COUNT(*)
FROM fact_sales

ORDER BY row_count DESC;


-- ============================================================
-- 3. REFERENTIAL INTEGRITY VALIDATION
-- ============================================================


-- ------------------------------------------------------------
-- 3.1 Fact → Date
-- ------------------------------------------------------------

SELECT COUNT(*) AS unmatched_dates
FROM fact_sales f
LEFT JOIN dim_date d
    ON f.date_key = d.date_key
WHERE d.date_key IS NULL;


-- ------------------------------------------------------------
-- 3.2 Fact → Customer
-- ------------------------------------------------------------

SELECT COUNT(*) AS unmatched_customers
FROM fact_sales f
LEFT JOIN dim_customer c
    ON f.customer_key = c.customer_key
WHERE c.customer_key IS NULL;


-- ------------------------------------------------------------
-- 3.3 Fact → Product
-- ------------------------------------------------------------

SELECT COUNT(*) AS unmatched_products
FROM fact_sales f
LEFT JOIN dim_product p
    ON f.product_key = p.product_key
WHERE p.product_key IS NULL;


-- ------------------------------------------------------------
-- 3.4 Fact → Territory
-- ------------------------------------------------------------

SELECT COUNT(*) AS unmatched_territories
FROM fact_sales f
LEFT JOIN dim_territory t
    ON f.territory_key = t.territory_key
WHERE t.territory_key IS NULL;


-- ------------------------------------------------------------
-- 3.5 Fact → Store
-- ------------------------------------------------------------
-- NULL StoreKey values are retained because they represent
-- missing source relationships rather than failed joins.

SELECT COUNT(*) AS unmatched_stores
FROM fact_sales f
LEFT JOIN dim_store s
    ON f.store_key = s.store_key
WHERE f.store_key IS NOT NULL
  AND s.store_key IS NULL;


-- ============================================================
-- 4. FACT TABLE QUALITY CHECKS
-- ============================================================


-- ------------------------------------------------------------
-- 4.1 Duplicate Fact Keys
-- ------------------------------------------------------------

SELECT
    COUNT(*) - COUNT(DISTINCT sales_order_detail_key)
        AS duplicate_fact_keys
FROM fact_sales;


-- ------------------------------------------------------------
-- 4.2 Negative / Invalid Sales Values
-- ------------------------------------------------------------

SELECT COUNT(*) AS invalid_sales_rows
FROM fact_sales
WHERE quantity < 0
   OR unit_price < 0
   OR sales_amount < 0
   OR discount_rate < 0
   OR discount_rate > 1;


-- ============================================================
-- 5. MONTHLY SALES ANALYSIS
-- ============================================================

SELECT
    d.year,
    d.month_number,
    d.month_name,
    ROUND(SUM(f.sales_amount), 2) AS total_sales,
    SUM(f.quantity) AS total_quantity
FROM fact_sales f
JOIN dim_date d
    ON f.date_key = d.date_key
GROUP BY
    d.year,
    d.month_number,
    d.month_name
ORDER BY
    d.year,
    d.month_number;


-- ============================================================
-- 6. SALES BY PRODUCT CATEGORY
-- ============================================================

SELECT
    p.category_name,
    ROUND(SUM(f.sales_amount), 2) AS total_sales,
    SUM(f.quantity) AS total_quantity,
    COUNT(DISTINCT f.order_key) AS total_orders,
    ROUND(
        SUM(f.sales_amount)
        / NULLIF(COUNT(DISTINCT f.order_key), 0),
        2
    ) AS average_order_value
FROM fact_sales f
JOIN dim_product p
    ON f.product_key = p.product_key
GROUP BY
    p.category_name
ORDER BY
    total_sales DESC;


-- ============================================================
-- 7. SALES BY TERRITORY
-- ============================================================

SELECT
    t.territory_name,
    ROUND(SUM(f.sales_amount), 2) AS total_sales,
    SUM(f.quantity) AS total_quantity,
    COUNT(DISTINCT f.order_key) AS total_orders
FROM fact_sales f
JOIN dim_territory t
    ON f.territory_key = t.territory_key
GROUP BY
    t.territory_name
ORDER BY
    total_sales DESC;


-- ============================================================
-- 8. TOP 10 CUSTOMERS BY SALES
-- ============================================================

SELECT
    f.customer_key,
    COUNT(DISTINCT f.order_key) AS total_orders,
    SUM(f.quantity) AS total_quantity,
    ROUND(SUM(f.sales_amount), 2) AS total_sales,
    ROUND(
        SUM(f.sales_amount)
        / NULLIF(COUNT(DISTINCT f.order_key), 0),
        2
    ) AS average_order_value
FROM fact_sales f
GROUP BY
    f.customer_key
ORDER BY
    total_sales DESC
LIMIT 10;


-- ============================================================
-- 9. CUSTOMER SEGMENTATION
-- ============================================================
-- Segmentation rules:
--
-- High Value:
--   8+ orders AND $500K+ sales
--
-- Medium Value:
--   4+ orders AND $100K+ sales
--
-- Low Value:
--   All remaining customers
-- ============================================================

WITH customer_metrics AS (
    SELECT
        customer_key,
        COUNT(DISTINCT order_key) AS total_orders,
        SUM(quantity) AS total_quantity,
        SUM(sales_amount) AS total_sales
    FROM fact_sales
    GROUP BY
        customer_key
),

customer_segments AS (
    SELECT
        customer_key,
        total_orders,
        total_quantity,
        total_sales,
        CASE
            WHEN total_orders >= 8
                 AND total_sales >= 500000
                THEN 'High Value'

            WHEN total_orders >= 4
                 AND total_sales >= 100000
                THEN 'Medium Value'

            ELSE 'Low Value'
        END AS customer_segment
    FROM customer_metrics
)

SELECT
    customer_segment,
    COUNT(*) AS customers,
    ROUND(SUM(total_sales), 2) AS total_sales,
    ROUND(AVG(total_sales), 2) AS avg_customer_sales,
    ROUND(AVG(total_orders), 2) AS avg_orders_per_customer
FROM customer_segments
GROUP BY
    customer_segment
ORDER BY
    CASE customer_segment
        WHEN 'High Value' THEN 1
        WHEN 'Medium Value' THEN 2
        WHEN 'Low Value' THEN 3
    END;


-- ============================================================
-- 10. PRODUCT PROFITABILITY
-- ============================================================
-- Estimated product cost:
-- Quantity × recorded standard cost
--
-- Important:
-- Standard cost is not necessarily the historical actual
-- transaction cost. Therefore profitability is an estimate.
-- ============================================================

SELECT
    p.category_name,

    ROUND(SUM(f.sales_amount), 2)
        AS total_sales,

    ROUND(
        SUM(
            f.quantity * p.standard_cost
        ),
        2
    ) AS estimated_product_cost,

    ROUND(
        SUM(f.sales_amount)
        - SUM(
            f.quantity * p.standard_cost
        ),
        2
    ) AS estimated_gross_profit,

    ROUND(
        (
            SUM(f.sales_amount)
            - SUM(
                f.quantity * p.standard_cost
            )
        )
        / NULLIF(SUM(f.sales_amount), 0)
        * 100,
        2
    ) AS estimated_gross_margin_percent

FROM fact_sales f
JOIN dim_product p
    ON f.product_key = p.product_key

GROUP BY
    p.category_name

ORDER BY
    estimated_gross_profit DESC;


-- ============================================================
-- 11. TOP 10 PRODUCTS BY ESTIMATED GROSS PROFIT
-- ============================================================

SELECT
    f.product_key,
    p.product_name,

    ROUND(SUM(f.sales_amount), 2)
        AS total_sales,

    ROUND(
        SUM(
            f.quantity * p.standard_cost
        ),
        2
    ) AS estimated_product_cost,

    ROUND(
        SUM(f.sales_amount)
        - SUM(
            f.quantity * p.standard_cost
        ),
        2
    ) AS estimated_gross_profit

FROM fact_sales f
JOIN dim_product p
    ON f.product_key = p.product_key

GROUP BY
    f.product_key,
    p.product_name

ORDER BY
    estimated_gross_profit DESC

LIMIT 10;


-- ============================================================
-- 12. EXECUTIVE KPIs
-- ============================================================

SELECT
    COUNT(DISTINCT order_key) AS total_orders,

    COUNT(DISTINCT customer_key) AS total_customers,

    SUM(quantity) AS total_units_sold,

    ROUND(
        SUM(sales_amount),
        2
    ) AS total_sales,

    ROUND(
        SUM(sales_amount)
        / NULLIF(COUNT(DISTINCT order_key), 0),
        2
    ) AS average_order_value,

    ROUND(
        SUM(
            quantity *
            p.standard_cost
        ),
        2
    ) AS estimated_product_cost,

    ROUND(
        SUM(sales_amount)
        -
        SUM(
            quantity *
            p.standard_cost
        ),
        2
    ) AS estimated_gross_profit,

    ROUND(
        (
            SUM(sales_amount)
            -
            SUM(
                quantity *
                p.standard_cost
            )
        )
        / NULLIF(SUM(sales_amount), 0)
        * 100,
        2
    ) AS estimated_gross_margin_percent

FROM fact_sales f
JOIN dim_product p
    ON f.product_key = p.product_key;


-- ============================================================
-- 13. PRODUCT CATEGORY COVERAGE
-- ============================================================

SELECT
    category_name,
    COUNT(*) AS product_count
FROM dim_product
GROUP BY
    category_name
ORDER BY
    product_count DESC;


-- ============================================================
-- END OF SQL SCRIPT
-- ============================================================