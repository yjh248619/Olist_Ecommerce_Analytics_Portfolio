-- SQLBook: Markup
1. 行数最终核对
-- SQLBook: Code

USE Olist ;
SELECT'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders' , COUNT(*) FROM orders
UNION ALL SELECT 'order_items' , COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments' , COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews' , COUNT(*) FROM order_reviews
UNION ALL SELECT 'products' , COUNT(*) FROM products
UNION ALL SELECT 'sellers' , COUNT(*) FROM sellers
UNION ALL SELECT 'product_category_name_translation' , COUNT(*) FROM product_category_name_translation
union ALL SELECT 'geolocation' ,COUNT(*)FROM geolocation
ORDER BY row_count DESC ;
-- SQLBook: Markup
行数结果如下：
![alt text](各表行数预览.png)
-- SQLBook: Code
2.主键唯一性检查
每张表的主键应该是唯一的，不能有重复的值。可以使用以下SQL查询来检查每张表的主键唯一性：
这样写是错的因为需要找的是每张表组的COUNT，而不是有哪些ID重复了和它重复的次数。这样写如果有多个ID重复了就会有多行结果，而我们需要的是每张表的重复ID的数量。
SELECT 'customers' AS 'table_name', COUNT(*) AS 'cnt'
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1
UNION ALL SELECT 'orders' ,              COUNT(*)  FROM orders         GROUP BY order_id HAVING COUNT(*) > 1
UNION ALL SELECT 'order_items' ,         COUNT(*)  FROM order_items    GROUP BY order_item_id,order_id HAVING COUNT(*) > 1
UNION ALL SELECT 'payment_sequential' ,    COUNT(*)  FROM order_payments GROUP BY payment_sequential,order_id  HAVING COUNT(*) > 1
UNION ALL SELECT 'order_reviews' ,             COUNT(*)  FROM order_reviews  GROUP BY review_id,order_id HAVING COUNT(*) > 1
UNION ALL SELECT 'products' ,            COUNT(*)  FROM products       GROUP BY product_id HAVING COUNT(*) > 1
UNION ALL SELECT 'sellers' ,             COUNT(*)  FROM sellers        GROUP BY seller_id HAVING COUNT(*) > 1
UNION ALL SELECT 'geolocation' ,                    COUNT(*)  FROM geolocation    GROUP BY id HAVING COUNT(*) > 1
UNION ALL SELECT 'product_category_name_translation' , COUNT(*)  FROM product_category_name_translation GROUP BY product_category_name HAVING COUNT(*) > 1
ORDER BY cnt DESC ;
-- SQLBook: Code
SELECT 'customers' AS 'table_name', 'customer_id' AS 'pk_columns', COUNT(*) AS duplicate_groups
FROM (SELECT customer_id
      FROM customers
      GROUP BY customer_id
      HAVING COUNT(*) > 1
) t
UNION ALL SELECT 'orders', 'order_id' ,                   COUNT(*) FROM (SELECT order_id FROM orders GROUP BY order_id HAVING COUNT(*) > 1) AS orders
UNION ALL SELECT 'order_items', 'order_item_id' ,         COUNT(*) FROM (SELECT order_id, order_item_id FROM order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1) AS order_items
UNION ALL SELECT 'order_payments', 'payment_sequential' , COUNT(*) FROM (SELECT order_id, payment_sequential FROM order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1) AS order_payments
UNION ALL SELECT 'order_reviews', 'review_id' ,           COUNT(*) FROM (SELECT review_id, order_id FROM order_reviews GROUP BY review_id, order_id HAVING COUNT(*) > 1) AS order_reviews
UNION ALL SELECT 'products', 'product_id' ,               COUNT(*) FROM (SELECT product_id FROM products GROUP BY product_id HAVING COUNT(*) > 1) AS products
UNION ALL SELECT 'sellers', 'seller_id' ,                 COUNT(*) FROM (SELECT seller_id FROM sellers GROUP BY seller_id HAVING COUNT(*) > 1) AS sellers
UNION ALL SELECT 'geolocation', 'id' ,                    COUNT(*) FROM (SELECT id FROM geolocation GROUP BY id HAVING COUNT(*) > 1) AS geolocation
UNION ALL SELECT 'product_category_name_translation', 'product_category_name' , COUNT(*) FROM (SELECT product_category_name FROM product_category_name_translation GROUP BY product_category_name HAVING COUNT(*) > 1) AS product_category_name_translation
ORDER BY duplicate_groups DESC ;
-- SQLBook: Markup
3. 外键完整性检查(找孤儿)
这一步最重要,直接决定能不能加外键。
-- 例:order_items 里有 product_id,但 products 表里找不到这个 product_id
SELECT COUNT(*) AS orphan_count
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;
-- 预期 0;如果 > 0 = 孤儿记录,加外键会失败

-- SQLBook: Code
-- UNION ALL 联合查询
SELECT 'order_items' AS reference_path ,'product_id' AS fk_column, COUNt(*) AS orphan_count
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL 
UNION ALL 
SELECT 'order_items','seller_id' , COUNT(*)
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL 
UNION ALL
SELECT 'order_items','order_id' , COUNT(*)
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL 
UNION ALL
SELECT 'orders','customer_id' , COUNT(*)
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'order_payments','order_id' ,COUNT(*)
FROM order_payments op
LEFT JOIN orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL 
UNION ALL
SELECT 'order_reviews','order_id' , COUNT(*)
FROM order_reviews  as odr
LEFT JOIN orders o ON odr.order_id = o.order_id
WHERE o.order_id IS NULL 
UNION ALL
SELECT 'products','product_category_name' , COUNT(*)
FROM products p
LEFT JOIN product_category_name_translation pct ON p.product_category_name = pct.product_category_name  
WHERE  p.product_category_name IS NOT NULL AND pct.product_category_name IS NULL ;
    
-- SQLBook: Code
SELECT COUNT(*), p.product_category_name
FROM products p
LEFT JOIN product_category_name_translation pct ON p.product_category_name = pct.product_category_name  
WHERE  p.product_category_name IS NOT NULL AND pct.product_category_name IS NULL 
GROUP BY p.product_category_name
ORDER BY COUNT(*) DESC ;
-- SQLBook: Markup
4. 时间逻辑检查
-- SQLBook: Code

-- 付款时间不能早于下单时间
SELECT COUNT(*) 
FROM orders
WHERE order_approved_at < order_purchase_timestamp;
-- 订单评论时间不能早于下单时间
SELECT COUNT(*)
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date < o.order_purchase_timestamp 
;
-- 送达时间不能早于发货时间
SELECT COUNT(*)
FROM orders
WHERE order_delivered_carrier_date > order_delivered_customer_date ;
-- 看具体差几天/几小时,能定位是时区问题还是真 BUG
SELECT 
    order_id,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    TIMESTAMPDIFF(MINUTE, 
                  order_delivered_carrier_date, 
                  order_delivered_customer_date) AS minutes_diff,
    TIMESTAMPDIFF(DAY, 
                  order_delivered_carrier_date, 
                  order_delivered_customer_date) AS days_diff
FROM orders
WHERE order_delivered_customer_date < order_delivered_carrier_date
ORDER BY minutes_diff
;
-- 评论时间不早于发货时间
SELECT COUNT(*)
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date < o.order_delivered_carrier_date
; 
-- 评论早于发货且送达早于发货的数据
SELECT o.order_id, o.order_delivered_carrier_date, r.review_creation_date ,o.order_purchase_timestamp , o.order_delivered_customer_date
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date < o.order_delivered_carrier_date AND order_delivered_carrier_date > order_delivered_customer_date;
-- 评论时间不早于送达时间 （8320条）
SELECT o.order_delivered_customer_date, r.review_creation_date ,o.order_purchase_timestamp , o.order_delivered_carrier_date
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date < o.order_delivered_customer_date
GROUP BY r.review_id, o.order_id
;
-- 评论早于送达的订单,到底早了多少天?
SELECT 
    CASE 
        WHEN DATEDIFF(order_delivered_customer_date, review_creation_date) >= 30 THEN '30天以上'
        WHEN DATEDIFF(order_delivered_customer_date, review_creation_date) >= 14 THEN '14-30天'
        WHEN DATEDIFF(order_delivered_customer_date, review_creation_date) >= 7  THEN '7-14天'
        WHEN DATEDIFF(order_delivered_customer_date, review_creation_date) >= 3  THEN '3-7天'
        WHEN DATEDIFF(order_delivered_customer_date, review_creation_date) >= 1  THEN '1-3天'
        ELSE '同一天(差几小时)'
    END AS advance_period,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 100.0 / 8320, 1) AS pct
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date < o.order_delivered_customer_date
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY advance_period
ORDER BY MIN(DATEDIFF(o.order_delivered_customer_date, r.review_creation_date));
-- 提前评价 vs 正常评价,评分有没有差异?
SELECT
    CASE WHEN r.review_creation_date < o.order_delivered_customer_date  
         THEN '收货前评价'ELSE '收货后评价' END AS review_timing,
    COUNT(*) AS cnt,
    ROUND(AVG(review_score), 2) AS avg_score,
    ROUND(SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END) *100.0/COUNT(*), 1) AS positive_rate
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_creation_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY review_timing;
-- 验证:偏远地区的收货前评分是否特别低
SELECT 
    c.customer_state,
    COUNT(*) AS total_reviews,
    SUM(CASE WHEN r.review_creation_date < o.order_delivered_customer_date 
        THEN 1 ELSE 0 END) AS early_reviews,
    ROUND(AVG(CASE WHEN r.review_creation_date < o.order_delivered_customer_date 
        THEN r.review_score END), 2) AS early_avg_score,
    ROUND(AVG(CASE WHEN r.review_creation_date >= o.order_delivered_customer_date 
        THEN r.review_score END), 2) AS normal_avg_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING early_reviews > 30
ORDER BY early_avg_score ASC;
-- 5. 业务异常值检查
-- 评分必须在 1-5 之间
SELECT review_score, COUNT(*) FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- 价格不应该 = 0 或负数
SELECT COUNT(*) FROM order_items WHERE price <= 0;

-- 运费不应该 < 0
SELECT COUNT(*) FROM order_items WHERE freight_value < 0;

-- 产品尺寸/重量异常(零或离谱大值)
SELECT COUNT(*) FROM products WHERE product_weight_g = 0 OR product_weight_g > 30000;

SELECT 
    product_id,
    product_category_name,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    -- 看看是不是体积计算合理性也异常
    product_length_cm * product_height_cm * product_width_cm AS volume_cm3
FROM products
WHERE product_weight_g = 0 OR product_weight_g > 30000
ORDER BY product_weight_g;

-- 6. 空值分布检查(对可空字段)
SELECT
    SUM(order_approved_at IS NULL) AS missing_approved,
    SUM(order_delivered_carrier_date IS NULL) AS missing_carrier,
    SUM(order_delivered_customer_date IS NULL) AS missing_delivered
FROM orders;

-- 然后按 status 分组,看哪些 status 对应空值
SELECT order_status, COUNT(*) AS cnt,
    SUM(order_delivered_customer_date IS NULL) AS missing_delivered,
    SUM(order_approved_at IS NULL) AS missing_approved,
    SUM(order_delivered_carrier_date IS NULL) AS missing_carrier
FROM orders
GROUP BY order_status
ORDER BY cnt DESC ;
-- 查看已送达订单中的8条异常的数据
SELECT 
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
-- 验证"2018-07-01 集群"假设
SELECT 
    order_id,
    order_purchase_timestamp,
    order_delivered_carrier_date,
    -- 看 carrier 时间是否聚集在某个时间窗
    DATE(order_delivered_carrier_date) AS carrier_date_only,
    -- 看是否和某个 seller 关联
    (SELECT DISTINCT seller_id FROM order_items oi WHERE oi.order_id = o.order_id LIMIT 1) AS sample_seller
FROM orders o
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL
ORDER BY order_delivered_carrier_date;