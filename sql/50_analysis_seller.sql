USE Olist;

-- ============================================================
-- Block 1: 卖家全景指标
-- ============================================================
-- 关键技巧: CASE WHEN 在聚合函数内部做条件筛选，
-- 让同一个 CTE 里三个不同口径（经营/体验/风险）共存。
-- ============================================================
WITH seller_stats AS (
    SELECT
        s.seller_id,
        s.seller_state,
        -- 经营指标（口径：排除 canceled/unavailable）
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.order_id END)                              AS valid_orders,
        ROUND(SUM(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value ELSE 0 END), 2)     AS total_gmv,
        COUNT(DISTINCT oi.product_id)                                         AS sku_count,
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.customer_id END)                           AS customer_count,
        ROUND(AVG(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value END), 2)            AS avg_order_value,
        -- 体验指标（口径：仅 delivered + 有评价 + 时间戳完整）
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score IS NOT NULL
                        THEN r.review_score END), 2)                         AS avg_review_score,
        ROUND(SUM(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score <= 2 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(CASE WHEN o.order_status = 'delivered'
                                          AND r.review_score IS NOT NULL
                                          THEN 1 END), 0), 2)                AS negative_rate_pct,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_approved_at IS NOT NULL
                        AND o.order_delivered_carrier_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_carrier_date,
                                      o.order_approved_at) END), 2)          AS avg_processing_days,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_delivered_carrier_date IS NOT NULL
                        AND o.order_delivered_customer_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_customer_date,
                                      o.order_delivered_carrier_date) END), 2) AS avg_shipping_days,
        -- 风险指标（口径：所有订单状态）
        COUNT(DISTINCT o.order_id)                                            AS total_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)                              AS canceled_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)                              AS unavailable_orders,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS cancel_rate_pct,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS unavailable_rate_pct
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    GROUP BY s.seller_id, s.seller_state
),
-- ============================================================
-- Block 2: 卖家健康分计算
-- ============================================================
seller_scored AS (
    SELECT
        ss.*,
        -- 加分项：PERCENT_RANK 返回 0-1 的相对排名，×100 转为 0-100 分制
        -- 如最小卖家 GMV:100 PERCENT_RANK为0中位数卖家为0.5；最大卖家为1
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100, 1)               AS gmv_percentile,
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100, 1)        AS review_percentile,
        -- 备货天数越小越好 → 用 DESC 让最少的排最后拿最高分
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100, 1) AS processing_percentile,
        -- 惩罚项标记
        CASE WHEN ss.unavailable_rate_pct > 5  THEN 1 ELSE 0 END                 AS penalty_unavailable,
        CASE WHEN ss.cancel_rate_pct > 10      THEN 1 ELSE 0 END                 AS penalty_cancel,
        CASE WHEN ss.negative_rate_pct > 25    THEN 1 ELSE 0 END                 AS penalty_negative,
        -- 综合健康分
        ROUND(
            PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100
            - CASE WHEN ss.unavailable_rate_pct > 5  THEN 20 ELSE 0 END
            - CASE WHEN ss.cancel_rate_pct > 10      THEN 20 ELSE 0 END
            - CASE WHEN ss.negative_rate_pct > 25    THEN 20 ELSE 0 END,
            1
        ) AS health_score
    FROM seller_stats ss
    WHERE ss.valid_orders >= 5  -- 过滤统计不稳定的小卖家
)
-- ============================================================
-- Block 3: 最终输出
-- ============================================================
SELECT
    seller_id,
    seller_state,
    valid_orders,
    total_gmv,
    sku_count,
    customer_count,
    avg_order_value,
    avg_review_score,
    negative_rate_pct,
    avg_processing_days,
    avg_shipping_days,
    cancel_rate_pct,
    unavailable_rate_pct,
    gmv_percentile,
    review_percentile,
    processing_percentile,
    health_score,
    CASE
        WHEN health_score >= 180 THEN 'S级卖家（优质供给）'
        WHEN health_score >= 120 THEN 'A级卖家'
        WHEN health_score >= 60  THEN 'B级卖家'
        WHEN health_score >= 0   THEN 'C级卖家'
        ELSE 'D级卖家（风险供给）'
    END AS seller_tier,
    ROW_NUMBER() OVER(ORDER BY health_score DESC) AS health_rank
FROM seller_scored
ORDER BY health_score DESC;
-- 卖家集中度：头部卖家贡献多少 GMV？
WITH seller_stats AS (
    SELECT
        s.seller_id,
        s.seller_state,
        -- 经营指标（口径：排除 canceled/unavailable）
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.order_id END)                              AS valid_orders,
        ROUND(SUM(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value ELSE 0 END), 2)     AS total_gmv,
        COUNT(DISTINCT oi.product_id)                                         AS sku_count,
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.customer_id END)                           AS customer_count,
        ROUND(AVG(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value END), 2)            AS avg_order_value,
        -- 体验指标（口径：仅 delivered + 有评价 + 时间戳完整）
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score IS NOT NULL
                        THEN r.review_score END), 2)                         AS avg_review_score,
        ROUND(SUM(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score <= 2 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(CASE WHEN o.order_status = 'delivered'
                                          AND r.review_score IS NOT NULL
                                          THEN 1 END), 0), 2)                AS negative_rate_pct,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_approved_at IS NOT NULL
                        AND o.order_delivered_carrier_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_carrier_date,
                                      o.order_approved_at) END), 2)          AS avg_processing_days,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_delivered_carrier_date IS NOT NULL
                        AND o.order_delivered_customer_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_customer_date,
                                      o.order_delivered_carrier_date) END), 2) AS avg_shipping_days,
        -- 风险指标（口径：所有订单状态）
        COUNT(DISTINCT o.order_id)                                            AS total_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)                              AS canceled_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)                              AS unavailable_orders,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS cancel_rate_pct,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS unavailable_rate_pct
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    GROUP BY s.seller_id, s.seller_state
),
-- ============================================================
-- Block 2: 卖家健康分计算
-- ============================================================
seller_scored AS (
    SELECT
        ss.*,
        -- 加分项：PERCENT_RANK 返回 0-1 的相对排名，×100 转为 0-100 分制
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100, 1)               AS gmv_percentile,
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100, 1)        AS review_percentile,
        -- 备货天数越小越好 → 用 DESC 让最少的排最后拿最高分
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100, 1) AS processing_percentile,
        -- 惩罚项标记
        CASE WHEN ss.unavailable_rate_pct > 5  THEN 1 ELSE 0 END                 AS penalty_unavailable,
        CASE WHEN ss.cancel_rate_pct > 10      THEN 1 ELSE 0 END                 AS penalty_cancel,
        CASE WHEN ss.negative_rate_pct > 25    THEN 1 ELSE 0 END                 AS penalty_negative,
        -- 综合健康分
        ROUND(
            PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100
            - CASE WHEN ss.unavailable_rate_pct > 5  THEN 20 ELSE 0 END
            - CASE WHEN ss.cancel_rate_pct > 10      THEN 20 ELSE 0 END
            - CASE WHEN ss.negative_rate_pct > 25    THEN 20 ELSE 0 END,
            1
        ) AS health_score
    FROM seller_stats ss
    WHERE ss.valid_orders >= 5  -- 过滤统计不稳定的小卖家
)
-- ============================================================
-- 收尾查询一：卖家集中度
-- ============================================================
SELECT
    COUNT(*)                                        AS active_sellers,
    ROUND(SUM(total_gmv), 2)                       AS total_platform_gmv,
    -- Top 10 GMV 占比
    ROUND(SUM(CASE WHEN gmv_rank <= 10  THEN total_gmv ELSE 0 END)
          * 100.0 / SUM(total_gmv), 2)             AS top10_gmv_pct,
    -- Top 50 GMV 占比
    ROUND(SUM(CASE WHEN gmv_rank <= 50  THEN total_gmv ELSE 0 END)
          * 100.0 / SUM(total_gmv), 2)             AS top50_gmv_pct,
    -- Top 100 GMV 占比
    ROUND(SUM(CASE WHEN gmv_rank <= 100 THEN total_gmv ELSE 0 END)
          * 100.0 / SUM(total_gmv), 2)             AS top100_gmv_pct,
    -- Top 200 GMV 占比
    ROUND(SUM(CASE WHEN gmv_rank <= 200 THEN total_gmv ELSE 0 END)
          * 100.0 / SUM(total_gmv), 2)             AS top200_gmv_pct,
    -- 长尾卖家数（valid_orders < 5 的原表总卖家数需从 seller_stats 计算——这里只能用 active_sellers）
    ROUND(SUM(CASE WHEN total_gmv >= 5000 THEN total_gmv ELSE 0 END)
          * 100.0 / SUM(total_gmv), 2)             AS seller_over_5k_gmv_pct
FROM (
    SELECT
        total_gmv,
        ROW_NUMBER() OVER(ORDER BY total_gmv DESC) AS gmv_rank
    FROM seller_scored
) t;
-- Bottom 10 风险卖家
USE Olist;
-- ============================================================
-- Block 1: 卖家全景指标
-- ============================================================
-- 关键技巧: CASE WHEN 在聚合函数内部做条件筛选，
-- 让同一个 CTE 里三个不同口径（经营/体验/风险）共存。
-- ============================================================
WITH seller_stats AS (
    SELECT
        s.seller_id,
        s.seller_state,
        -- 经营指标（口径：排除 canceled/unavailable）
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.order_id END)                              AS valid_orders,
        ROUND(SUM(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value ELSE 0 END), 2)     AS total_gmv,
        COUNT(DISTINCT oi.product_id)                                         AS sku_count,
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                            THEN o.customer_id END)                           AS customer_count,
        ROUND(AVG(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable')
                        THEN oi.price + oi.freight_value END), 2)            AS avg_order_value,
        -- 体验指标（口径：仅 delivered + 有评价 + 时间戳完整）
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score IS NOT NULL
                        THEN r.review_score END), 2)                         AS avg_review_score,
        ROUND(SUM(CASE WHEN o.order_status = 'delivered'
                        AND r.review_score <= 2 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(CASE WHEN o.order_status = 'delivered'
                                          AND r.review_score IS NOT NULL
                                          THEN 1 END), 0), 2)                AS negative_rate_pct,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_approved_at IS NOT NULL
                        AND o.order_delivered_carrier_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_carrier_date,
                                      o.order_approved_at) END), 2)          AS avg_processing_days,
        ROUND(AVG(CASE WHEN o.order_status = 'delivered'
                        AND o.order_delivered_carrier_date IS NOT NULL
                        AND o.order_delivered_customer_date IS NOT NULL
                        THEN DATEDIFF(o.order_delivered_customer_date,
                                      o.order_delivered_carrier_date) END), 2) AS avg_shipping_days,
        -- 风险指标（口径：所有订单状态）
        COUNT(DISTINCT o.order_id)                                            AS total_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)                              AS canceled_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)                              AS unavailable_orders,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS cancel_rate_pct,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                                  THEN o.order_id END)
              * 100.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)            AS unavailable_rate_pct
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    GROUP BY s.seller_id, s.seller_state
),
-- ============================================================
-- Block 2: 卖家健康分计算
-- ============================================================
seller_scored AS (
    SELECT
        ss.*,
        -- 加分项：PERCENT_RANK 返回 0-1 的相对排名，×100 转为 0-100 分制
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100, 1)               AS gmv_percentile,
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100, 1)        AS review_percentile,
        -- 备货天数越小越好 → 用 DESC 让最少的排最后拿最高分
        ROUND(PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100, 1) AS processing_percentile,
        -- 惩罚项标记
        CASE WHEN ss.unavailable_rate_pct > 5  THEN 1 ELSE 0 END                 AS penalty_unavailable,
        CASE WHEN ss.cancel_rate_pct > 10      THEN 1 ELSE 0 END                 AS penalty_cancel,
        CASE WHEN ss.negative_rate_pct > 25    THEN 1 ELSE 0 END                 AS penalty_negative,
        -- 综合健康分
        ROUND(
            PERCENT_RANK() OVER(ORDER BY ss.total_gmv) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_review_score) * 100
            + PERCENT_RANK() OVER(ORDER BY ss.avg_processing_days DESC) * 100
            - CASE WHEN ss.unavailable_rate_pct > 5  THEN 20 ELSE 0 END
            - CASE WHEN ss.cancel_rate_pct > 10      THEN 20 ELSE 0 END
            - CASE WHEN ss.negative_rate_pct > 25    THEN 20 ELSE 0 END,
            1
        ) AS health_score
    FROM seller_stats ss
    WHERE ss.valid_orders >= 5  -- 过滤统计不稳定的小卖家
)
-- ============================================================
-- Block 3: 最终输出
-- ============================================================
SELECT
    seller_id,
    seller_state,
    valid_orders,
    total_gmv,
    sku_count,
    customer_count,
    avg_order_value,
    avg_review_score,
    negative_rate_pct,
    avg_processing_days,
    avg_shipping_days,
    cancel_rate_pct,
    unavailable_rate_pct,
    gmv_percentile,
    review_percentile,
    processing_percentile,
    health_score,
    CASE
        WHEN health_score >= 180 THEN 'S级卖家（优质供给）'
        WHEN health_score >= 120 THEN 'A级卖家'
        WHEN health_score >= 60  THEN 'B级卖家'
        WHEN health_score >= 0   THEN 'C级卖家'
        ELSE 'D级卖家（风险供给）'
    END AS seller_tier,
    ROW_NUMBER() OVER(ORDER BY health_score DESC) AS health_rank
FROM seller_scored
ORDER BY health_score ASC
LIMIT 10;
