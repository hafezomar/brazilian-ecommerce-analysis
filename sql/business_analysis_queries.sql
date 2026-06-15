/*
Brazilian E-Commerce Business Performance Analysis
SQL Business Analysis Queries

Database: SQLite
Dataset: Olist Brazilian E-Commerce dataset

Important grain notes:
- orders = one row per order.
- order_items = one row per item inside an order.
- reviews = one row per review record linked to an order.
- Joining orders -> order_items changes the grain from order-level to item-level.
- Joining orders -> order_items -> reviews creates an item-review-level result.
- Metric names intentionally reflect the row grain to avoid overclaiming.

Validation notes:
- These queries are written for SQLite.
- Query 3 was corrected from an invalid alias mismatch: the CTE creates delivery_group, so the final SELECT/GROUP BY must use delivery_group.
*/


/* ============================================================
Query 1: Order status overview
Grain: Order-level
============================================================ */
SELECT
    o.order_status,
    COUNT(*) AS total_orders
FROM orders AS o
GROUP BY o.order_status
ORDER BY total_orders DESC;


/* ============================================================
Query 2: Order status percentage overview
Grain: Order-level
============================================================ */
SELECT
    o.order_status,
    COUNT(*) AS total_orders,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) AS order_percentage
FROM orders AS o
GROUP BY o.order_status
ORDER BY total_orders DESC;


/* ============================================================
Query 3: Delivered vs not delivered order share
Grain: Order-level
============================================================ */
WITH categorized_orders AS (
    SELECT 
        o.order_id,
        CASE 
            WHEN o.order_status = 'delivered' THEN 'Delivered'
            ELSE 'Not Delivered'
        END AS delivery_group
    FROM orders AS o
)
SELECT 
    delivery_group,
    COUNT(*) AS total_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS order_percentage
FROM categorized_orders
GROUP BY delivery_group
ORDER BY total_orders DESC;


/* ============================================================
Query 4: Monthly order volume
Grain: Order-level
============================================================ */
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS purchase_month,
    COUNT(*) AS total_orders
FROM orders AS o
GROUP BY purchase_month
ORDER BY purchase_month;


/* ============================================================
Query 5: Monthly delivered order volume
Grain: Order-level
============================================================ */
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS purchase_month,
    COUNT(*) AS total_delivered_orders
FROM orders AS o
WHERE o.order_status = 'delivered'
GROUP BY purchase_month
ORDER BY purchase_month;


/* ============================================================
Query 6: Delivery time summary statistics
Grain: Order-level, delivered orders only
============================================================ */
WITH delivered_orders AS (
    SELECT
        o.order_id,
        julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp) AS delivery_days
    FROM orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
    ROUND(MIN(delivery_days), 2) AS min_delivery_days,
    ROUND(MAX(delivery_days), 2) AS max_delivery_days
FROM delivered_orders;


/* ============================================================
Query 7: Longest delivery outliers
Grain: Order-level, delivered orders only
============================================================ */
SELECT 
    o.order_id,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    ROUND(julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp), 2) AS delivery_days
FROM orders AS o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
ORDER BY delivery_days DESC
LIMIT 10;


/* ============================================================
Query 8: Delivery time bucket distribution
Grain: Order-level, delivered orders only
============================================================ */
WITH delivered_orders AS (
    SELECT 
        o.order_id,
        julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp) AS delivery_days
    FROM orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
bucketed_orders AS (
    SELECT
        order_id,
        delivery_days,
        CASE 
            WHEN delivery_days <= 7 THEN '0-7 days'
            WHEN delivery_days <= 14 THEN '8-14 days'
            WHEN delivery_days <= 30 THEN '15-30 days'
            WHEN delivery_days <= 60 THEN '31-60 days'
            ELSE '60+ days'
        END AS delivery_time_bucket,
        CASE 
            WHEN delivery_days <= 7 THEN 1
            WHEN delivery_days <= 14 THEN 2
            WHEN delivery_days <= 30 THEN 3
            WHEN delivery_days <= 60 THEN 4
            ELSE 5
        END AS bucket_sort_order
    FROM delivered_orders
)
SELECT 
    delivery_time_bucket,
    COUNT(*) AS total_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS order_percentage
FROM bucketed_orders
GROUP BY delivery_time_bucket, bucket_sort_order
ORDER BY bucket_sort_order;


/* ============================================================
Query 9: Average review score by delivery time bucket
Grain: Review-level after joining delivered orders to reviews
============================================================ */
WITH delivered_reviews AS (
    SELECT 
        o.order_id,
        r.review_id,
        r.review_score,
        julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp) AS delivery_days
    FROM orders AS o
    INNER JOIN reviews AS r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND r.review_score IS NOT NULL
),
bucketed_reviews AS (
    SELECT
        order_id,
        review_id,
        review_score,
        delivery_days,
        CASE 
            WHEN delivery_days <= 7 THEN '0-7 days'
            WHEN delivery_days <= 14 THEN '8-14 days'
            WHEN delivery_days <= 30 THEN '15-30 days'
            WHEN delivery_days <= 60 THEN '31-60 days'
            ELSE '60+ days'
        END AS delivery_time_bucket,
        CASE 
            WHEN delivery_days <= 7 THEN 1
            WHEN delivery_days <= 14 THEN 2
            WHEN delivery_days <= 30 THEN 3
            WHEN delivery_days <= 60 THEN 4
            ELSE 5
        END AS bucket_sort_order
    FROM delivered_reviews
)
SELECT 
    delivery_time_bucket,
    COUNT(*) AS total_reviews,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM bucketed_reviews
GROUP BY delivery_time_bucket, bucket_sort_order
ORDER BY bucket_sort_order;


/* ============================================================
Query 10: Average review score by delivery status
Grain: Review-level after joining delivered orders to reviews
============================================================ */
WITH delivered_reviews AS (
    SELECT 
        o.order_id,
        r.review_id,
        r.review_score,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM orders AS o
    INNER JOIN reviews AS r 
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND r.review_score IS NOT NULL
),
status_mapped_reviews AS (
    SELECT 
        order_id,
        review_id,
        review_score,
        CASE 
            WHEN julianday(order_delivered_customer_date) <= julianday(order_estimated_delivery_date) THEN 'Early / On Time'
            ELSE 'Late'
        END AS delivery_status
    FROM delivered_reviews
)
SELECT 
    delivery_status,
    COUNT(*) AS total_reviews,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM status_mapped_reviews
GROUP BY delivery_status
ORDER BY avg_review_score DESC;


/* ============================================================
Query 11: Late delivery rate
Grain: Order-level, delivered orders only
============================================================ */
WITH status_mapped_orders AS (
    SELECT 
        o.order_id,
        CASE 
            WHEN julianday(o.order_delivered_customer_date) <= julianday(o.order_estimated_delivery_date) THEN 'Early / On Time'
            ELSE 'Late'
        END AS delivery_status
    FROM orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT 
    delivery_status,
    COUNT(*) AS total_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS order_percentage
FROM status_mapped_orders
GROUP BY delivery_status
ORDER BY total_orders DESC;


/* ============================================================
Query 12: Monthly late delivery rate
Grain: Order-level, delivered orders only
============================================================ */
SELECT 
    strftime('%Y-%m', o.order_purchase_timestamp) AS purchase_month,
    COUNT(*) AS total_delivered_orders,
    SUM(
        CASE
            WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
            ELSE 0 
        END
    ) AS late_orders,
    ROUND(
        100.0 * SUM(
            CASE 
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_order_percentage
FROM orders AS o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY purchase_month
ORDER BY purchase_month ASC;


/* ============================================================
Query 13: Late delivery rate by customer state
Grain: Order-level after joining orders to customers
============================================================ */
SELECT 
    c.customer_state,
    COUNT(*) AS total_delivered_orders,
    SUM(
        CASE 
            WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1
            ELSE 0 
        END
    ) AS late_orders,
    ROUND(
        100.0 * SUM(
            CASE 
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_order_percentage
FROM orders AS o
INNER JOIN customers AS c 
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 500
ORDER BY late_order_percentage DESC;


/* ============================================================
Query 14: Late delivery rate by seller state
Grain: Item-level after joining orders to order items and sellers
============================================================ */
SELECT 
    s.seller_state,
    COUNT(*) AS total_order_items,
    SUM(
        CASE 
            WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1
            ELSE 0 
        END
    ) AS late_order_items,
    ROUND(
        100.0 * SUM(
            CASE 
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_item_percentage
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN sellers AS s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY s.seller_state
HAVING COUNT(*) >= 500
ORDER BY late_item_percentage DESC;


/* ============================================================
Query 15: Top product categories by revenue
Grain: Item-level after joining delivered orders to order items and products
============================================================ */
SELECT 
    ct.product_category_name_english,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    COUNT(*) AS total_items,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN products AS p 
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct 
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
ORDER BY total_product_revenue DESC
LIMIT 10;


/* ============================================================
Query 16: Top product categories by item volume
Grain: Item-level after joining delivered orders to order items and products
============================================================ */
SELECT 
    ct.product_category_name_english,
    COUNT(*) AS total_items,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN products AS p 
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct 
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
ORDER BY total_items DESC
LIMIT 10;


/* ============================================================
Query 17: Top product categories by revenue share
Grain: Item-level after joining delivered orders to order items and products
============================================================ */
SELECT 
    ct.product_category_name_english,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 2) AS revenue_percentage
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN products AS p 
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct 
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
ORDER BY total_product_revenue DESC
LIMIT 10;


/* ============================================================
Query 18: Product category review performance
Grain: Item-review-level after joining orders, items, products, and reviews
============================================================ */
SELECT
    ct.product_category_name_english,
    COUNT(*) AS total_item_reviews,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders AS o
INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id
INNER JOIN products AS p
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name
INNER JOIN reviews AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND r.review_score IS NOT NULL
GROUP BY ct.product_category_name_english
HAVING COUNT(*) >= 500
ORDER BY avg_review_score ASC;


/* ============================================================
Query 19: Product category late delivery performance
Grain: Item-level after joining delivered orders to order items and products
============================================================ */
SELECT 
    ct.product_category_name_english,
    COUNT(*) AS total_items,
    SUM(
        CASE
            WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1
            ELSE 0
        END
    ) AS late_items,
    ROUND(
        100.0 * SUM(
            CASE 
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_item_percentage
FROM orders AS o
INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id
INNER JOIN products AS p
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY ct.product_category_name_english
HAVING COUNT(*) >= 500
ORDER BY late_item_percentage DESC;


/* ============================================================
Query 20: Seller performance summary
Grain: Item-review-level after joining orders, items, sellers, and reviews
============================================================ */
SELECT 
    s.seller_id,
    s.seller_state,
    COUNT(*) AS total_item_reviews,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_item_percentage,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN sellers AS s 
    ON oi.seller_id = s.seller_id
INNER JOIN reviews AS r 
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND r.review_score IS NOT NULL
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(*) >= 100
ORDER BY total_product_revenue DESC
LIMIT 15;


/* ============================================================
Final Query: Category performance summary
Grain: Item-review-level after joining orders, items, products, categories, and reviews
============================================================ */
SELECT 
    ct.product_category_name_english,
    COUNT(*) AS total_item_reviews,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(
        100.0 * SUM(
            CASE 
                WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date) THEN 1 
                ELSE 0 
            END
        ) / COUNT(*),
        2
    ) AS late_item_percentage,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders AS o
INNER JOIN order_items AS oi 
    ON o.order_id = oi.order_id
INNER JOIN products AS p 
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct 
    ON p.product_category_name = ct.product_category_name
INNER JOIN reviews AS r 
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND r.review_score IS NOT NULL
GROUP BY ct.product_category_name_english
HAVING COUNT(*) >= 500
ORDER BY total_product_revenue DESC
LIMIT 15;