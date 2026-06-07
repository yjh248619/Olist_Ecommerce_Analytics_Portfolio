USE Olist;

-- ============================================================
-- 15. GMV 波动归因分析
-- ============================================================
-- 一、分析目的:
-- 回答"GMV 为什么涨/为什么跌"。纯 DA 岗项目汇报里,这比单纯展示
-- GMV 月趋势更重要,因为业务方真正关心的是波动原因和下一步动作。
--
-- 二、业务逻辑:
-- GMV 是结果指标,不能直接解释自己。需要拆成:
--   GMV = 订单量 x 客单价
--       = 活跃购买用户数 x 人均订单数 x 客单价
--
-- 三、计算逻辑:
-- Block 1: 生成月度经营基础指标
-- Block 2: 用订单量效应 + 客单价效应 + 交叉项拆解 GMV 环比变化
-- Block 3: 拆解订单量背后的用户数和人均订单数
-- Block 4: 黑五 2017-11 峰值归因
-- Block 5: 黑五品类贡献拆解
-- Block 6: 月份完整性检查,标注数据截断风险
--
-- 四、变量定义:
-- gmv                  = SUM(price + freight_value)
-- order_count          = COUNT(DISTINCT order_id)
-- buyer_count          = COUNT(DISTINCT customer_unique_id)
-- aov                  = gmv / order_count
-- orders_per_buyer     = order_count / buyer_count
-- order_count_effect   = (本月订单量 - 上月订单量) x 上月 AOV
-- aov_effect           = (本月 AOV - 上月 AOV) x 上月订单量
-- interaction_effect   = 订单量变化 x AOV 变化
--
-- 五、口径说明:
-- 使用 v_orders_clean 排除 23 条时间异常订单,但该视图不含 status 过滤,
-- 所以必须显式写 WHERE o.order_status = 'delivered'。
-- ============================================================

-- ============================================================
-- Block 1: 月度经营基础指标
-- ============================================================
-- 目的:
-- 先得到 GMV、订单量、购买用户数、客单价、人均订单数等核心指标。
-- 这是后续所有归因分析的基础表。
-- ============================================================
WITH monthly_base AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
        ROUND(SUM(oi.price), 2) AS product_gmv,
        ROUND(SUM(oi.freight_value), 2) AS freight_gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT c.customer_unique_id) AS buyer_count,
        COUNT(*) AS item_count
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    month,
    gmv,
    product_gmv,
    freight_gmv,
    order_count,
    buyer_count,
    item_count,
    ROUND(gmv / NULLIF(order_count, 0), 2) AS aov,
    ROUND(order_count / NULLIF(buyer_count, 0), 3) AS orders_per_buyer,
    ROUND(item_count / NULLIF(order_count, 0), 3) AS items_per_order,
    ROUND(freight_gmv * 100.0 / NULLIF(gmv, 0), 2) AS freight_share_pct
FROM monthly_base
ORDER BY month;

-- ============================================================
-- Block 2: GMV 环比波动归因
-- ============================================================
-- 目的:
-- 拆解每个月 GMV 变化到底来自订单量变化,还是客单价变化。
--
-- 精确拆解:
-- ΔGMV = 本月订单量 x 本月 AOV - 上月订单量 x 上月 AOV
--      = (订单量变化 x 上月 AOV)
--      + (AOV 变化 x 上月订单量)
--      + (订单量变化 x AOV 变化)
--
-- 解读:
-- order_count_effect 为正 -> 主要是量拉动
-- aov_effect 为正         -> 主要是价拉动
-- interaction_effect      -> 量价同时变化带来的交叉项
-- ============================================================
WITH monthly_base AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        SUM(oi.price + oi.freight_value) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT c.customer_unique_id) AS buyer_count
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
),
monthly_metrics AS (
    SELECT
        month,
        gmv,
        order_count,
        buyer_count,
        gmv / NULLIF(order_count, 0) AS aov,
        order_count / NULLIF(buyer_count, 0) AS orders_per_buyer
    FROM monthly_base
),
with_lag AS (
    SELECT
        month,
        gmv,
        order_count,
        buyer_count,
        aov,
        orders_per_buyer,
        LAG(gmv) OVER (ORDER BY month) AS prev_gmv,
        LAG(order_count) OVER (ORDER BY month) AS prev_order_count,
        LAG(aov) OVER (ORDER BY month) AS prev_aov
    FROM monthly_metrics
)
SELECT
    month,
    ROUND(gmv, 2) AS gmv,
    ROUND(prev_gmv, 2) AS prev_gmv,
    ROUND(gmv - prev_gmv, 2) AS gmv_delta,
    ROUND((gmv - prev_gmv) * 100.0 / NULLIF(prev_gmv, 0), 2) AS gmv_mom_pct,
    order_count,
    prev_order_count,
    ROUND(aov, 2) AS aov,
    ROUND(prev_aov, 2) AS prev_aov,
    ROUND((order_count - prev_order_count) * prev_aov, 2) AS order_count_effect,
    ROUND((aov - prev_aov) * prev_order_count, 2) AS aov_effect,
    ROUND((order_count - prev_order_count) * (aov - prev_aov), 2) AS interaction_effect,
    CASE
        WHEN prev_gmv IS NULL THEN '首月无环比'
        WHEN ABS((order_count - prev_order_count) * prev_aov)
             >= ABS((aov - prev_aov) * prev_order_count)
             THEN '订单量主导'
        ELSE '客单价主导'
    END AS main_driver
FROM with_lag
ORDER BY month;

-- ============================================================
-- Block 3: 订单量背后的用户结构拆解
-- ============================================================
-- 目的:
-- 如果 GMV 是订单量主导,继续拆订单量:
--   订单量 = 购买用户数 x 人均订单数
--
-- 由于 Olist 复购极低,预期 orders_per_buyer 接近 1。
-- 如果 GMV 增长主要来自 buyer_count 增长,说明平台是获客驱动。
-- ============================================================
WITH monthly_base AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        SUM(oi.price + oi.freight_value) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT c.customer_unique_id) AS buyer_count
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
),
metrics AS (
    SELECT
        month,
        gmv,
        order_count,
        buyer_count,
        order_count / NULLIF(buyer_count, 0) AS orders_per_buyer,
        gmv / NULLIF(order_count, 0) AS aov
    FROM monthly_base
),
with_lag AS (
    SELECT
        *,
        LAG(buyer_count) OVER (ORDER BY month) AS prev_buyer_count,
        LAG(orders_per_buyer) OVER (ORDER BY month) AS prev_orders_per_buyer,
        LAG(order_count) OVER (ORDER BY month) AS prev_order_count
    FROM metrics
)
SELECT
    month,
    order_count,
    prev_order_count,
    order_count - prev_order_count AS order_delta,
    buyer_count,
    prev_buyer_count,
    buyer_count - prev_buyer_count AS buyer_delta,
    ROUND(orders_per_buyer, 3) AS orders_per_buyer,
    ROUND(prev_orders_per_buyer, 3) AS prev_orders_per_buyer,
    ROUND(orders_per_buyer - prev_orders_per_buyer, 4) AS orders_per_buyer_delta,
    CASE
        WHEN prev_order_count IS NULL THEN '首月无环比'
        WHEN ABS(buyer_count - prev_buyer_count)
             >= ABS((orders_per_buyer - prev_orders_per_buyer) * prev_buyer_count)
             THEN '购买用户数主导'
        ELSE '人均订单数主导'
    END AS order_driver
FROM with_lag
ORDER BY month;

-- ============================================================
-- Block 4: 2017-11 黑五峰值归因
-- ============================================================
-- 目的:
-- 针对项目中最明显的 GMV 峰值(2017-11)做单点复盘。
-- 判断黑五增长来自"量"还是"价"。
-- ============================================================
WITH monthly_base AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT c.customer_unique_id) AS buyer_count,
        ROUND(SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov,
        ROUND(COUNT(DISTINCT o.order_id) / NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 3) AS orders_per_buyer
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    month,
    gmv,
    order_count,
    buyer_count,
    aov,
    orders_per_buyer,
    ROUND((gmv - LAG(gmv) OVER (ORDER BY month)) * 100.0
          / NULLIF(LAG(gmv) OVER (ORDER BY month), 0), 2) AS gmv_mom_pct,
    ROUND((order_count - LAG(order_count) OVER (ORDER BY month)) * 100.0
          / NULLIF(LAG(order_count) OVER (ORDER BY month), 0), 2) AS order_mom_pct,
    ROUND((aov - LAG(aov) OVER (ORDER BY month)) * 100.0
          / NULLIF(LAG(aov) OVER (ORDER BY month), 0), 2) AS aov_mom_pct
FROM monthly_base
WHERE month BETWEEN '2017-09' AND '2018-01'
ORDER BY month;

-- ============================================================
-- Block 5: 黑五品类贡献拆解
-- ============================================================
-- 目的:
-- 如果 2017-11 GMV 暴涨,继续看哪些品类贡献最大增量。
-- 对比 2017-10 与 2017-11。
-- ============================================================
WITH category_month AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        COALESCE(t.product_category_name_english, 'NULL') AS category_name,
        SUM(oi.price + oi.freight_value) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count,
        SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0) AS aov
    FROM v_orders_clean o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
      AND DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') IN ('2017-10', '2017-11')
    GROUP BY
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
        COALESCE(t.product_category_name_english, 'NULL')
),
pivoted AS (
    SELECT
        category_name,
        SUM(CASE WHEN month = '2017-10' THEN gmv ELSE 0 END) AS gmv_2017_10,
        SUM(CASE WHEN month = '2017-11' THEN gmv ELSE 0 END) AS gmv_2017_11,
        SUM(CASE WHEN month = '2017-10' THEN order_count ELSE 0 END) AS orders_2017_10,
        SUM(CASE WHEN month = '2017-11' THEN order_count ELSE 0 END) AS orders_2017_11
    FROM category_month
    GROUP BY category_name
)
SELECT
    category_name,
    ROUND(gmv_2017_10, 2) AS gmv_2017_10,
    ROUND(gmv_2017_11, 2) AS gmv_2017_11,
    ROUND(gmv_2017_11 - gmv_2017_10, 2) AS gmv_delta,
    orders_2017_10,
    orders_2017_11,
    orders_2017_11 - orders_2017_10 AS order_delta,
    ROUND(gmv_2017_11 / NULLIF(orders_2017_11, 0), 2) AS aov_2017_11,
    ROUND((gmv_2017_11 - gmv_2017_10) * 100.0
          / NULLIF(SUM(gmv_2017_11 - gmv_2017_10) OVER (), 0), 2) AS contribution_to_delta_pct
FROM pivoted
WHERE gmv_2017_11 > gmv_2017_10
ORDER BY gmv_delta DESC
LIMIT 20;

-- ============================================================
-- Block 6: 月份完整性检查
-- ============================================================
-- 目的:
-- 标注数据截断风险。首月和末月通常不是完整月份,
-- 不能直接拿来判断真实经营趋势。
-- ============================================================
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
    DATE(MIN(order_purchase_timestamp)) AS first_purchase_date,
    DATE(MAX(order_purchase_timestamp)) AS last_purchase_date,
    COUNT(DISTINCT DATE(order_purchase_timestamp)) AS observed_days,
    CASE
        WHEN DAY(MIN(order_purchase_timestamp)) > 1
          OR DAY(MAX(order_purchase_timestamp)) < DAY(LAST_DAY(MAX(order_purchase_timestamp)))
        THEN '不完整月份,趋势解读需谨慎'
        ELSE '完整月份'
    END AS month_completeness_flag
FROM orders
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY month;

-- ============================================================
-- 七、预期结果:
-- 1. 2017-11 应出现明显 GMV 峰值,主要由订单量拉动。
-- 2. orders_per_buyer 应接近 1,说明 Olist 增长主要来自新购买用户。
-- 3. 2016-09 与 2018-09 应被标记为不完整月份。
-- 4. 若某月 GMV 暴涨但订单量不涨,说明是 AOV 或高客单品类结构变化。
-- 5. 若 GMV 下跌集中在少数品类,下一步应下钻卖家或地域。
-- ============================================================

