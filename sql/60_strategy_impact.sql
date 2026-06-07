   USE Olist;

-- ============================================================
-- Block 1: unavailable + canceled 订单的 GMV 损失
-- ============================================================
-- 口径: 只统计有 order_items 的订单（775 个无 items 订单无法归因）
--       用 order_items 中的 price + freight_value 作为损失估算
--       因为 unavailable 订单已付款但缺货，canceled 订单多数也已付款
-- ============================================================
WITH lost_orders AS (
    SELECT
        o.order_id,
        o.order_status,
        o.order_purchase_timestamp,
        oi.product_id,
        oi.seller_id,
        oi.price,
        oi.freight_value
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status IN ('canceled', 'unavailable')
)
-- Block 1a: 整体损失：按canceled 和unavailable分为两组的整体的损失
SELECT
    '整体' AS dimension,
    order_status,
    COUNT(DISTINCT order_id)                                          AS lost_order_count,
    ROUND(SUM(price + freight_value), 2)                             AS lost_gmv,
    -- 假设治理能挽回 20% 的损失（保守估计），这里的20%是损失GMV的20%，下面50%同样
    ROUND(SUM(price + freight_value) * 0.20, 2)                      AS recoverable_gmv_20pct,
    ROUND(SUM(price + freight_value) * 0.50, 2)                      AS recoverable_gmv_50pct
FROM lost_orders
GROUP BY order_status
UNION ALL
-- Block 1b: 按品类损失排名：和BLOCK1A相连按状态和品类
SELECT
    COALESCE(t.product_category_name_english, 'NULL (未分类)')       AS dimension,
    lo.order_status,
    COUNT(DISTINCT lo.order_id)                                       AS lost_order_count,
    ROUND(SUM(lo.price + lo.freight_value), 2)                       AS lost_gmv,
    ROUND(SUM(lo.price + lo.freight_value) * 0.20, 2)                AS recoverable_gmv_20pct,
    ROUND(SUM(lo.price + lo.freight_value) * 0.50, 2)                AS recoverable_gmv_50pct
FROM lost_orders lo
JOIN products p ON lo.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english, lo.order_status
ORDER BY lost_gmv DESC;
-- ============================================================
-- Block 2: Top 风险卖家治理 — 缺货率 > 5% 的卖家 GMV 损失
-- ============================================================
-- 逻辑: 卖家分析中找到的 unavailable_rate > 5% 的卖家，
--       估算如果把它们的缺货率降低 20%，能挽回多少 GMV
-- ============================================================
-- ============================================================
-- Block 2: 风险卖家治理（修正 + 优化版）
-- ============================================================
-- 优化点:
--   1. LEFT JOIN 保证 unavailable 订单不丢
--   2. unavailable 的 GMV 损失 = 缺货订单数 × 该卖家客单价
--      而不是笼统用平台均值 160 BRL
--   3. canceled 的 GMV 损失 = order_items 实际 SUM
-- 取消流程：下单 → 付款（price + freight_value 扣款） → 取消 → 退款；而如果是缺货状态的订单没有付款这一步当然也没有实际金额
-- ============================================================
WITH risk_sellers AS (
    SELECT
        s.seller_id,
        s.seller_state,
        COUNT(DISTINCT o.order_id)                                 AS total_orders,
        -- 缺货订单数
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)                   AS unavailable_orders,
        -- 取消订单数
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)                    AS canceled_orders,
        -- 该卖家的客单价（用非 canceled/unavailable 订单算，口径干净）
        ROUND(AVG(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value END), 2)  AS seller_avg_order_value,
        -- canceled 订单的实际 GMV 损失（有 order_items 数据）
        ROUND(SUM(CASE WHEN o.order_status = 'canceled'
                        THEN oi.price + oi.freight_value ELSE 0 END), 2) AS canceled_lost_gmv,
        -- 缺货率
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS unavailable_rate_pct
              
    FROM orders o
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    LEFT JOIN sellers s ON oi.seller_id = s.seller_id
    WHERE s.seller_id IS NOT NULL
    GROUP BY s.seller_id, s.seller_state
    HAVING unavailable_rate_pct > 5
       AND COUNT(DISTINCT o.order_id) >= 5
)
SELECT
    '风险卖家治理' AS strategy,
    COUNT(*)                                                      AS risk_seller_count,
    SUM(total_orders)                                             AS total_orders_affected,
    SUM(unavailable_orders)                                       AS total_unavailable,
    SUM(canceled_orders)                                          AS total_canceled,
    -- canceled：精确值
    ROUND(SUM(canceled_lost_gmv), 2)                             AS canceled_lost_gmv_exact,
    -- unavailable：估算值 = 缺货订单数 × 该卖家客单价
    ROUND(SUM(unavailable_orders * seller_avg_order_value), 2)   AS unavailable_lost_gmv_estimated,
    -- 总损失 = 精确 + 估算
    ROUND(SUM(canceled_lost_gmv 
              + unavailable_orders * seller_avg_order_value), 2) AS total_lost_gmv,
    ROUND(AVG(unavailable_rate_pct), 2)                          AS avg_unavailable_rate,
    -- 假设治理后缺货率降低 20%
    ROUND(SUM(canceled_lost_gmv 
              + unavailable_orders * seller_avg_order_value) * 0.20, 2) AS recoverable_gmv_20pct,
    -- 假设治理后缺货率降低 50%
    ROUND(SUM(canceled_lost_gmv 
              + unavailable_orders * seller_avg_order_value) * 0.50, 2) AS recoverable_gmv_50pct
FROM risk_sellers
;
-- ============================================================
-- Block 3: 备货时长优化 — 如果备货减 0.5 天，哪些州受益最大
-- ============================================================
-- 逻辑: 找出备货时长 > 品类中位数的订单，估算如果这些订单
--       备货减少 0.5 天，能覆盖多少订单/用户
-- ============================================================
SELECT
    s.seller_state,
    ROUND(AVG(DATEDIFF(o.order_delivered_carrier_date,
                        o.order_approved_at)), 2)                 AS current_avg_processing_days,
    COUNT(DISTINCT o.order_id)                                     AS order_count,
    -- 备货 > 3 天的订单（中位数约 2 天，3 天为 75 分位，是优化空间所在）
    COUNT(DISTINCT CASE WHEN DATEDIFF(o.order_delivered_carrier_date,
                                      o.order_approved_at) > 3
                        THEN o.order_id END)                       AS slow_processing_orders,
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(o.order_delivered_carrier_date,
                                            o.order_approved_at) > 3
                              THEN o.order_id END)
          * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)    AS slow_order_pct,
    -- 这些慢备货的订单如果每单减少 0.5 天，累计节省的天数
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(o.order_delivered_carrier_date,
                                            o.order_approved_at) > 3
                              THEN o.order_id END) * 0.5, 0)      AS total_days_saved_if_optimized
FROM sellers s
JOIN order_items oi ON s.seller_id = oi.seller_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
GROUP BY s.seller_state
ORDER BY slow_processing_orders DESC;
-- ============================================================
-- Block 4: 早评偏差量化 — 如果早评比例降低，评分能提升多少
-- ============================================================
-- 背景: 数据质量报告发现早评(评价早于送达)平均 2.79 分，
--       签收后评价平均 4.28 分，差 1.49 分。
--       如果评价邀请从"发货后"改为"签收后"，早评比例将大幅下降。
-- ============================================================
SELECT
    '早评机制调整' AS strategy,
    -- 早评统计
    COUNT(CASE WHEN r.review_creation_date < o.order_delivered_customer_date
               THEN 1 END)                                         AS early_review_count,
    ROUND(AVG(CASE WHEN r.review_creation_date < o.order_delivered_customer_date
                    THEN r.review_score END), 2)                   AS early_avg_score,
    -- 正常评价统计
    COUNT(CASE WHEN r.review_creation_date >= o.order_delivered_customer_date
               THEN 1 END)                                         AS normal_review_count,
    ROUND(AVG(CASE WHEN r.review_creation_date >= o.order_delivered_customer_date
                    THEN r.review_score END), 2)                   AS normal_avg_score,
    -- 早评占比
    ROUND(COUNT(CASE WHEN r.review_creation_date < o.order_delivered_customer_date
                     THEN 1 END)
          * 100.0 / COUNT(*), 2)                                   AS early_review_rate_pct,
    -- 如果所有早评都变成正常评分（假设 100% 消除），平台平均评分能提升多少
    ROUND(
        AVG(r.review_score)  -- 当前全平台平均评分
        , 2)                                                        AS current_avg_score,
    ROUND(
        (AVG(CASE WHEN r.review_creation_date >= o.order_delivered_customer_date
                  THEN r.review_score END)
         - AVG(CASE WHEN r.review_creation_date < o.order_delivered_customer_date
                    THEN r.review_score END))
        * COUNT(CASE WHEN r.review_creation_date < o.order_delivered_customer_date
                     THEN 1 END)
        / COUNT(*), 2)                                              AS potential_score_uplift
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;
