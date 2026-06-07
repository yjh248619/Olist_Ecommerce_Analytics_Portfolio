USE Olist;

-- ============================================================
-- 1. 下单→付款→发货→送达 各环节转化率
SELECT
    COUNT(*) AS total_orders,
    -- 付款转化:有多少订单完成了付款
    SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END) AS paid_orders,
    ROUND(SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS payment_rate,
    -- 发货转化:付款的订单里有多少发货了
    SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END) AS shipped_orders,
    ROUND(SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 
          / NULLIF(SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS shipping_rate,
    -- 送达转化:发货的订单里有多少送达了
    SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS delivered_orders,
    ROUND(SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 
          / NULLIF(SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS delivery_rate
FROM orders;

-- ============================================================
-- 2. 各环节平均耗时(排除时间异常)
-- ============================================================
SELECT
    -- 付款耗时(小时):下单到付款
    ROUND(AVG(TIMESTAMPDIFF(HOUR, order_purchase_timestamp, order_approved_at)) / 24, 2) 
        AS avg_approval_days,
-- 备货耗时(天):付款到发货
    ROUND(AVG(TIMESTAMPDIFF(DAY, order_approved_at, order_delivered_carrier_date)), 2) 
        AS avg_processing_days,
-- 配送耗时(天):发货到送达(仅正常记录)
    ROUND(AVG(CASE 
        WHEN order_delivered_customer_date >= order_delivered_carrier_date 
        THEN TIMESTAMPDIFF(DAY, order_delivered_carrier_date, order_delivered_customer_date)
    END), 2) 
        AS avg_shipping_days
FROM orders
WHERE order_approved_at IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL;

-- ============================================================
-- 3. 按月漏斗趋势
-- ============================================================
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
    COUNT(*) AS order_count,
    
    ROUND(SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) 
        AS payment_rate,
    
    ROUND(SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 
          / NULLIF(SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END), 0), 1) 
        AS shipping_rate,
    
    ROUND(SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 
          / NULLIF(SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END), 0), 1) 
        AS delivery_rate
FROM orders
GROUP BY month
ORDER BY month;
