-- ============================================================
-- 35. Cohort 留存 + LTV 分析
-- ============================================================
-- 分析目的:
--   从时间维度观察用户首购后的留存和累计价值，弥补 RFM"只有横截面快照"的盲点。
--
-- 业务逻辑:
--   按用户首购月份划分 cohort，追踪每个 cohort 在首购后第 N 个月的
--   留存人数和人均累计 GMV。
--
-- 计算逻辑:
--   Block 1: 为每个用户找到首购月份 + 每笔订单距首购的月偏移 → CTE
--   Block 2: 基于 CTE 生成 cohort × period 留存矩阵（长表格式）
--   Block 3: 基于 CTE 生成 cohort × period LTV 矩阵
--
-- 预期结果:
--   次月留存率约 2-5%，绝大多数 cohort 的 LTV 在 period 1 后不再增长。
-- =================================================
USE Olist;
-- ============================================================
-- Block 1: Cohort 基础表
-- ============================================================
WITH cohort_base AS (
    -- 1a: 每个真实用户的首购月份
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m') AS cohort_month
    FROM customers c
    JOIN v_orders_clean o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    -- v_orders_clean 是一个视图（VIEW），不是表。从 orders 表排除 23 条"送达早于发货"的异常订单，其他全部保留
    GROUP BY c.customer_unique_id

),
cohort_orders AS (
    -- 1b: 每笔订单关联首购月份，计算月偏移 + GMV
    SELECT
        cb.customer_unique_id,
        cb.cohort_month,
        PERIOD_DIFF(
            DATE_FORMAT(o.order_purchase_timestamp, '%Y%m'),
            REPLACE(cb.cohort_month, '-', '')
        ) AS period_number,
        SUM(oi.price + oi.freight_value) AS gmv
    FROM cohort_base cb
    JOIN customers c2 ON c2.customer_unique_id = cb.customer_unique_id
    -- orders 表用的是 customer_id，所以必须再 JOIN 一次 customers（c2）来桥接。
    JOIN v_orders_clean o ON o.customer_id = c2.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        cb.customer_unique_id,
        cb.cohort_month,
        period_number  -- MySQL 8.0 允许按 SELECT 别名 GROUP BY
),
-- ============================================================
-- Block 2: Cohort 留存矩阵（长表格式）
-- ============================================================
cohort_retention AS (
    SELECT
        cohort_month,
        period_number,
        COUNT(DISTINCT customer_unique_id) AS active_users,
        -- cohort_size: 该 cohort 初始人数（period=0），用窗口函数扩展到所有行
        MAX(COUNT(DISTINCT CASE WHEN period_number = 0 THEN customer_unique_id END))
            OVER (PARTITION BY cohort_month) AS cohort_size,
        -- retention_pct: 当期留存率 = 当期活跃 / 初始人数 × 100
        ROUND(
            COUNT(DISTINCT customer_unique_id) * 100.0
            / MAX(COUNT(DISTINCT CASE WHEN period_number = 0 THEN customer_unique_id END))
                OVER (PARTITION BY cohort_month),
            2
        ) AS retention_pct
    FROM cohort_orders
    GROUP BY cohort_month, period_number
),
-- ============================================================
-- Block 3: Cohort LTV 矩阵
-- ============================================================
cohort_ltv AS (
    SELECT
        cohort_month,
        period_number,
        -- 分母：该 cohort 初始人数
        MAX(COUNT(DISTINCT CASE WHEN period_number = 0 THEN customer_unique_id END))
            OVER (PARTITION BY cohort_month) AS cohort_size,
        -- 该 cohort 的首购用户总数
        ROUND(SUM(gmv), 2) AS period_gmv,
        -- 首购月GMV
        ROUND(
            SUM(gmv)
            / MAX(COUNT(DISTINCT CASE WHEN period_number = 0 THEN customer_unique_id END))
                OVER (PARTITION BY cohort_month),
            2
        ) AS period_avg_revenue,
         -- 首购月人均 GMV
        ROUND(
            SUM(SUM(gmv)) OVER (
                PARTITION BY cohort_month
                ORDER BY period_number
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ),
            2
        ) AS cumulative_gmv,
        -- 累计 GMV（从 period 0 累加到当前 period）
        ROUND(
            SUM(SUM(gmv)) OVER (
                PARTITION BY cohort_month
                ORDER BY period_number
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
            / MAX(COUNT(DISTINCT CASE WHEN period_number = 0 THEN customer_unique_id END))
                OVER (PARTITION BY cohort_month),
            2
        ) AS cumulative_ltv
        -- 累计人均 GMV（近似 LTV）
    FROM cohort_orders
    GROUP BY cohort_month, period_number
)
SELECT * FROM cohort_ltv
ORDER BY cohort_month, period_number;
SELECT * FROM cohort_retention
ORDER BY cohort_month, period_number;
-- ============================================================
-- Block 4: 跨 Cohort 横向对比汇总表
-- ============================================================
-- 分析目的:
--   将每个 cohort 的关键指标浓缩成一行，方便横向对比不同 cohort 的质量差异。
--
-- 业务逻辑:
--   同一 period（如 period_1），对比不同 cohort 的留存率和人均 GMV，
--   看平台用户质量是否在改善，以及 LTV 天花板在哪里。
-- ============================================================
SELECT
    r.cohort_month,
    r.cohort_size,
    -- 首单客单价（period 0 的人均 GMV）
    MAX(CASE WHEN r.period_number = 0 THEN l.period_avg_revenue END) AS p0_arpu,
    -- 次月留存率
    MAX(CASE WHEN r.period_number = 1 THEN r.retention_pct END) AS p1_retention_pct,
    -- 3 月留存率
    MAX(CASE WHEN r.period_number = 3 THEN r.retention_pct END) AS p3_retention_pct,
    -- 6 月留存率
    MAX(CASE WHEN r.period_number = 6 THEN r.retention_pct END) AS p6_retention_pct,
    -- 12 月留存率
    MAX(CASE WHEN r.period_number = 12 THEN r.retention_pct END) AS p12_retention_pct,
    -- 最大观测期数（早的 cohort 窗口长，晚的窗口短）
    MAX(r.period_number) AS max_period,
    -- 最终累计 LTV（最后一个有数据的 period 的 cumulative_ltv）
    MAX(CASE WHEN r.period_number = max_period_inner.max_p THEN l.cumulative_ltv END) AS final_ltv,
    -- LTV 增幅 = 最终 LTV - 首单 ARPU
    MAX(CASE WHEN r.period_number = max_period_inner.max_p THEN l.cumulative_ltv END)
        - MAX(CASE WHEN r.period_number = 0 THEN l.period_avg_revenue END) AS ltv_uplift
FROM cohort_retention r
JOIN cohort_ltv l
    ON r.cohort_month = l.cohort_month
   AND r.period_number = l.period_number
-- 子查询：每个 cohort 的最大 period_number
JOIN (
    SELECT cohort_month, MAX(period_number) AS max_p
    FROM cohort_retention
    GROUP BY cohort_month
) max_period_inner ON r.cohort_month = max_period_inner.cohort_month
GROUP BY r.cohort_month, r.cohort_size, max_period_inner.max_p
ORDER BY r.cohort_month;

-- ============================================================
-- 最终输出
-- ============================================================
-- 先看留存矩阵
--  SELECT * FROM cohort_retention
-- ORDER BY cohort_month, period_number
-- 再看 LTV 矩阵
-- SELECT * FROM cohort_ltv
-- ORDER BY cohort_month, period_number




