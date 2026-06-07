USE Olist;

-- ============================================================
-- 1. 复购率(真实用户维度)
-- ============================================================
SELECT 
    CASE 
        WHEN order_count = 1 THEN '1次(一次性用户)'
        WHEN order_count = 2 THEN '2次'
        WHEN order_count BETWEEN 3 AND 5 THEN '3-5次'
        WHEN order_count BETWEEN 6 AND 10 THEN '6-10次'
        ELSE '10次以上'
    END AS purchase_frequency,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
    -- 按frequency分成不同频次段，计算每个购买频次段的用户占比,保留 1 位小数。
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
) t
GROUP BY purchase_frequency
ORDER BY MIN(order_count)
-- 让结果按购买次数从低到高排序，而不是按文字排序。
;
-- 找到高复购用户的特征 (购买频次、总消费金额、购买品类等)
SELECT 
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price + oi.freight_value) AS total_spent,
    GROUP_CONCAT(DISTINCT p.product_category_name) AS categories
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) > 10
ORDER BY order_count DESC;

-- ============================================================
-- 2. RFM 打分(每个维度 1-5 分,5 最优)
-- ============================================================
-- rfm_raw：计算每个用户的原始 RFM 指标
WITH rfm_raw AS (
    SELECT 
        c.customer_unique_id,
        DATEDIFF('2018-09-04', MAX(o.order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT *,
        -- R:recency 越小越好 → DESC(大值在前给 1)
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        -- F:用业务阈值,因为 NTILE 在低复购数据上失效
        CASE 
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency BETWEEN 3 AND 5 THEN 4
            ELSE 5
        END AS f_score,
        -- M:monetary 越大越好 → ASC(大值在后给 5)
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
)
SELECT 
    r_score, f_score, m_score,
    (r_score + f_score + m_score) AS rfm_total,
    COUNT(*) AS user_count,
    ROUND(AVG(recency_days), 0) AS avg_recency,
    ROUND(AVG(frequency), 1) AS avg_freq,
    ROUND(AVG(monetary), 0) AS avg_monetary
FROM rfm_scored
GROUP BY r_score, f_score, m_score
ORDER BY rfm_total DESC
LIMIT 20;

-- ============================================================
-- 3. 用户分层(按 RFM 总分)
-- ============================================================
WITH rfm_raw AS (
    SELECT 
        c.customer_unique_id,
        DATEDIFF('2018-09-04', MAX(o.order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT *,
        -- R:recency 越小越好 → DESC(大值在前给 1)
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        -- F:用业务阈值,因为 NTILE 在低复购数据上失效
        CASE 
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency BETWEEN 3 AND 5 THEN 4
            ELSE 5
        END AS f_score,
        -- M:monetary 越大越好 → ASC(大值在后给 5)
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
),
segments AS (
    SELECT 
        customer_unique_id,
        recency_days, frequency, monetary,
        r_score, f_score, m_score,
        (r_score + f_score + m_score) AS rfm_total,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '核心用户'
            WHEN r_score >= 4 AND f_score <= 2 THEN '新用户'
            WHEN r_score <= 2 AND f_score >= 4 THEN '沉睡高价值'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN '流失用户'
            WHEN f_score >= 3 AND m_score >= 3 THEN '中坚用户'
            ELSE '普通用户'
        END AS segment
    FROM rfm_scored
)
SELECT 
    segment,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct,
    ROUND(AVG(recency_days), 0) AS avg_recency,
    ROUND(AVG(frequency), 1) AS avg_freq,
    ROUND(AVG(monetary), 0) AS avg_monetary,
    ROUND(SUM(monetary), 0) AS total_gmv_contribution
FROM segments
GROUP BY segment
ORDER BY MIN(CASE segment
    WHEN '核心用户' THEN 1
    WHEN '中坚用户' THEN 2
    WHEN '新用户' THEN 3
    WHEN '沉睡高价值' THEN 4
    WHEN '普通用户' THEN 5
    WHEN '流失用户' THEN 6
END);
-- 普通用户(只买 1 次)的首单画像
SELECT 
    p.product_category_name,
    COUNT(DISTINCT c.customer_unique_id) AS users_bought,
    AVG(r.review_score) AS avg_score,
    AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)) AS avg_delivery_days
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE c.customer_unique_id IN (
    -- 只买过 1 次的用户
    SELECT customer_unique_id FROM customers c2
    JOIN orders o2 ON c2.customer_id = o2.customer_id
    WHERE o2.order_status = 'delivered'
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT o2.order_id) = 1
)
GROUP BY p.product_category_name
ORDER BY users_bought DESC
LIMIT 20;
