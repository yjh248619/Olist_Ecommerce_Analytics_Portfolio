-- ============================================================
-- 10. 宏观大盘分析
-- ============================================================
USE Olist;

-- ============================================================
-- 1. 按月 GMV / 订单量 / 客户数 趋势
-- ============================================================
SELECT 
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
    COUNT(DISTINCT o.order_id) AS order_count,
    COUNT(DISTINCT o.customer_id) AS customer_count,
    ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    ROUND(COUNT(oi.order_item_id) * 1.0 / COUNT(DISTINCT o.order_id), 2) AS avg_items_per_order
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY month
ORDER BY month;
SELECT o.order_status, COUNT(*) AS cnt
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status;
-- invoiced + shipped 但没有 order_items 的订单
SELECT o.order_id, o.order_status, o.order_purchase_timestamp
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
  AND o.order_status IN ('invoiced', 'shipped');


-- ============================================================
-- 2. 整体核心指标
-- ============================================================
SELECT 
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_gmv,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS total_customers,
    ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS arpu,
    ROUND(COUNT(oi.order_item_id) * 1.0 / COUNT(DISTINCT o.order_id), 2) AS avg_items_per_order,
    DATE(MIN(o.order_purchase_timestamp)) AS first_order_date,
    DATE(MAX(o.order_purchase_timestamp)) AS last_order_date,
    ROUND(DATEDIFF(MAX(o.order_purchase_timestamp), MIN(o.order_purchase_timestamp)) / 30.44, 1) AS months_span
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id;

-- ============================================================
-- 3. 按周几的订单量分布
-- ============================================================
SELECT 
    DAYOFWEEK(o.order_purchase_timestamp) AS day_of_week_num,
    CASE DAYOFWEEK(o.order_purchase_timestamp)
        WHEN 1 THEN '周日'
        WHEN 2 THEN '周一'
        WHEN 3 THEN '周二'
        WHEN 4 THEN '周三'
        WHEN 5 THEN '周四'
        WHEN 6 THEN '周五'
        WHEN 7 THEN '周六'
    END AS weekday,
    COUNT(DISTINCT o.order_id) AS order_count,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY day_of_week_num, weekday
ORDER BY day_of_week_num;
