USE Olist;

-- ============================================================
-- 45. 地域经营分析
-- ============================================================
-- 一、分析目的:
-- 回答"哪些州贡献交易规模,哪些州被物流和供给拖累"。
-- 地域分析是电商 DA 的基础能力,因为用户、卖家、物流网络天然有空间差异。
--
-- 二、业务逻辑:
-- Olist 是巴西电商平台,巴西地域跨度大,州与州之间的物流体验差异明显。
-- 前面已经发现早评率和评分存在州级差异,本文件进一步补全:
--   交易规模 -> 履约体验 -> 评价体验 -> 供需匹配
--
-- 三、计算逻辑:
-- Block 1: 客户州维度的 GMV、订单、用户、AOV
-- Block 2: 客户州维度的履约时长和准时率
-- Block 3: 客户州维度的评分、差评率、早评率
-- Block 4: 同州 vs 跨州订单履约差异
-- Block 5: 客户州 x 卖家州的物流干线分析
-- Block 6: 地域经营分层标签
--
-- 四、核心口径:
-- 交易/履约/评分均以 delivered 订单为主。
-- 使用 v_orders_clean 排除时间异常,但仍需显式过滤 order_status='delivered'。
-- ============================================================

-- ============================================================
-- Block 1: 各州交易规模
-- ============================================================
-- 目的:
-- 识别哪些州贡献 GMV、订单和用户。
-- ============================================================
SELECT
    c.customer_state,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
    COUNT(DISTINCT o.order_id) AS order_count,
    COUNT(DISTINCT c.customer_unique_id) AS buyer_count,
    COUNT(DISTINCT oi.product_id) AS sku_count,
    ROUND(SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov,
    ROUND(COUNT(DISTINCT o.order_id) / NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 3) AS orders_per_buyer,
    ROUND(SUM(oi.freight_value) * 100.0 / NULLIF(SUM(oi.price + oi.freight_value), 0), 2) AS freight_share_pct,
    ROUND(SUM(oi.price + oi.freight_value) * 100.0
          / SUM(SUM(oi.price + oi.freight_value)) OVER (), 2) AS gmv_share_pct
FROM v_orders_clean o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY gmv DESC;

-- ============================================================
-- Block 2: 各州履约体验
-- ============================================================
-- 目的:
-- 判断哪些州配送慢、超预计送达多。
-- ============================================================
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_approved_at, o.order_delivered_carrier_date)) / 24, 2) AS avg_processing_days,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_delivered_carrier_date, o.order_delivered_customer_date)) / 24, 2) AS avg_shipping_days,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_purchase_timestamp, o.order_delivered_customer_date)) / 24, 2) AS avg_total_delivery_days,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_purchase_timestamp, o.order_estimated_delivery_date)) / 24, 2) AS avg_estimated_days,
    ROUND(SUM(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
        ELSE 0
    END) * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS late_delivery_rate_pct,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_delivered_customer_date, o.order_estimated_delivery_date)) / 24, 2) AS avg_days_before_estimate
FROM v_orders_clean o
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING delivered_orders >= 30
ORDER BY avg_total_delivery_days DESC;

-- ============================================================
-- Block 3: 各州评价体验 + 早评偏差
-- ============================================================
-- 目的:
-- 结合前面发现的"收货前评价偏低",观察不同州的评分和早评差异。
-- ============================================================
WITH review_by_state AS (
    SELECT
        c.customer_state,
        o.order_id,
        AVG(r.review_score) AS avg_review_score,
        MAX(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS has_bad_review,
        MAX(CASE
            WHEN r.review_creation_date < o.order_delivered_customer_date THEN 1
            ELSE 0
        END) AS has_early_review
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state, o.order_id
)
SELECT
    customer_state,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score,
    ROUND(SUM(has_bad_review) * 100.0 / NULLIF(COUNT(*), 0), 2) AS bad_review_rate_pct,
    ROUND(SUM(has_early_review) * 100.0 / NULLIF(COUNT(*), 0), 2) AS early_review_rate_pct,
    ROUND(AVG(CASE WHEN has_early_review = 1 THEN avg_review_score END), 2) AS early_avg_score,
    ROUND(AVG(CASE WHEN has_early_review = 0 THEN avg_review_score END), 2) AS normal_avg_score,
    ROUND(
        AVG(CASE WHEN has_early_review = 1 THEN avg_review_score END)
        - AVG(CASE WHEN has_early_review = 0 THEN avg_review_score END),
        2
    ) AS early_score_gap
FROM review_by_state
GROUP BY customer_state
HAVING reviewed_orders >= 30
ORDER BY early_review_rate_pct DESC;

-- ============================================================
-- Block 4: 同州 vs 跨州履约差异
-- ============================================================
-- 目的:
-- 判断物流慢是否来自 seller 和 customer 不在同一州。
-- 注意:
-- 一个订单可能有多个卖家,这里按 order_item 粒度分析供需距离。
-- ============================================================
WITH item_route AS (
    SELECT
        o.order_id,
        oi.order_item_id,
        c.customer_state,
        s.seller_state,
        CASE
            WHEN c.customer_state = s.seller_state THEN '同州'
            ELSE '跨州'
        END AS route_type,
        oi.price + oi.freight_value AS item_gmv,
        TIMESTAMPDIFF(HOUR, o.order_delivered_carrier_date, o.order_delivered_customer_date) / 24 AS shipping_days,
        TIMESTAMPDIFF(HOUR, o.order_purchase_timestamp, o.order_delivered_customer_date) / 24 AS total_delivery_days,
        CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END AS is_late
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN sellers s
        ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    route_type,
    COUNT(*) AS item_rows,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(item_gmv), 2) AS gmv,
    ROUND(AVG(shipping_days), 2) AS avg_shipping_days,
    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,
    ROUND(SUM(is_late) * 100.0 / NULLIF(COUNT(*), 0), 2) AS late_rate_pct,
    ROUND(SUM(item_gmv) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS aov
FROM item_route
GROUP BY route_type
ORDER BY route_type;

-- ============================================================
-- Block 5: 客户州 x 卖家州物流干线
-- ============================================================
-- 目的:
-- 找出交易量大且履约慢的州际线路,用于物流或平台招商策略。
-- ============================================================
WITH route_metrics AS (
    SELECT
        c.customer_state,
        s.seller_state,
        COUNT(DISTINCT o.order_id) AS order_count,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
        ROUND(AVG(TIMESTAMPDIFF(HOUR, o.order_delivered_carrier_date, o.order_delivered_customer_date)) / 24, 2) AS avg_shipping_days,
        ROUND(SUM(CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END) * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS late_rate_pct
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN sellers s
        ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state, s.seller_state
)
SELECT
    customer_state,
    seller_state,
    CASE
        WHEN customer_state = seller_state THEN '同州'
        ELSE '跨州'
    END AS route_type,
    order_count,
    gmv,
    avg_shipping_days,
    late_rate_pct
FROM route_metrics
WHERE order_count >= 50
ORDER BY avg_shipping_days DESC, order_count DESC
LIMIT 50;

-- ============================================================
-- Block 6: 地域经营分层标签
-- ============================================================
-- 目的:
-- 综合 GMV、履约、评分,给各州打业务标签。
-- ============================================================
WITH state_trade AS (
    SELECT
        c.customer_state,
        SUM(oi.price + oi.freight_value) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT c.customer_unique_id) AS buyer_count,
        SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0) AS aov
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
state_delivery AS (
    SELECT
        c.customer_state,
        AVG(TIMESTAMPDIFF(HOUR, o.order_purchase_timestamp, o.order_delivered_customer_date)) / 24 AS avg_total_delivery_days
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state
),
state_review AS (
    SELECT
        c.customer_state,
        AVG(r.review_score) AS avg_review_score,
        SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS bad_review_rate_pct
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
combined AS (
    SELECT
        t.customer_state,
        t.gmv,
        t.order_count,
        t.buyer_count,
        t.aov,
        d.avg_total_delivery_days,
        r.avg_review_score,
        r.bad_review_rate_pct,
        PERCENT_RANK() OVER (ORDER BY t.gmv) AS gmv_rank,
        PERCENT_RANK() OVER (ORDER BY d.avg_total_delivery_days DESC) AS delivery_rank,
        PERCENT_RANK() OVER (ORDER BY r.avg_review_score) AS review_rank
    FROM state_trade t
    LEFT JOIN state_delivery d
        ON t.customer_state = d.customer_state
    LEFT JOIN state_review r
        ON t.customer_state = r.customer_state
)
SELECT
    customer_state,
    ROUND(gmv, 2) AS gmv,
    order_count,
    buyer_count,
    ROUND(aov, 2) AS aov,
    ROUND(avg_total_delivery_days, 2) AS avg_total_delivery_days,
    ROUND(avg_review_score, 2) AS avg_review_score,
    ROUND(bad_review_rate_pct, 2) AS bad_review_rate_pct,
    CASE
        WHEN gmv_rank >= 0.75 AND avg_review_score >= 4.1 AND avg_total_delivery_days <= 12 THEN '核心健康市场'
        WHEN gmv_rank >= 0.75 AND (avg_review_score < 4.0 OR avg_total_delivery_days > 15) THEN '高价值待治理市场'
        WHEN gmv_rank < 0.75 AND avg_review_score >= 4.1 AND avg_total_delivery_days <= 12 THEN '潜力市场'
        WHEN avg_total_delivery_days > 18 THEN '物流治理市场'
        ELSE '常规市场'
    END AS geo_segment
FROM combined
ORDER BY gmv DESC;

-- ============================================================
-- 七、预期结果:
-- 1. SP 应是 GMV 和订单规模最大的核心市场。
-- 2. 北部/东北部部分州可能配送更慢、早评率更高。
-- 3. 跨州订单的配送时长和延迟率应高于同州订单。
-- 4. 如果某州 GMV 高但评分低/配送慢,应进入"高价值待治理市场"。
-- 5. 地域分析结果可直接支撑 dashboard 和 AB test 的分层策略。
-- ============================================================

