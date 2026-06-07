-- ============================================================
-- 06. 数据异常修复
-- 基于 04_data_quality.sql 的发现做最小化修复
-- 原则:保留原始数据,只规范化"明显的录入缺失"
-- ============================================================

USE Olist;

-- ============================================================
-- 6.1 products.product_weight_g = 0 改为 NULL
-- 原因:0 不是真实重量,是上架时未填导致的默认值
--      改为 NULL 后,AVG() 等聚合函数会自动跳过,避免污染统计
-- ============================================================
UPDATE products
SET product_weight_g = NULL
WHERE product_weight_g = 0;

-- 验证:应该修复了 4 条
SELECT COUNT(*) AS fixed_weight_count 
FROM products 
WHERE product_weight_g IS NULL 
  AND product_category_name = 'cama_mesa_banho';

-- ============================================================
-- 6.2 时间异常:不修复,创建清洗视图
-- 原因:74 条无法确定真实时间,标记 + 分析时排除是工业界标准做法
-- ============================================================
CREATE OR REPLACE VIEW v_orders_clean AS
SELECT *
FROM orders
WHERE NOT (order_delivered_customer_date < order_delivered_carrier_date)
   OR order_delivered_carrier_date IS NULL
   OR order_delivered_customer_date IS NULL;

-- 验证:视图行数 = 99441 - 23 = 99367
SELECT COUNT(*) FROM v_orders_clean;
