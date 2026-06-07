-- ============================================================
-- 40. 品类经营分析
-- ============================================================
-- 分析目的:
--   回答"哪些品类贡献 GMV、哪些品类体验差、哪些品类适合推荐或治理"。
--   补充 RFM + Cohort 的用户维度分析，从供给侧提供完整视角。
--
-- 业务逻辑:
--   品类是电商的供给单元。
--   GMV 高 + 体验好 → 推荐系统候选池
--   GMV 高 + 体验差 → 运营治理优先
--   GMV 低 + 复购高 → 潜力长尾品类
--
-- 计算逻辑:
--   Block 1: CTE category_gmv     — 品类 GMV / 订单量 / SKU（库存量） / 客单价
--   Block 2: CTE category_exp     — 品类评分 / 配送时长 / 早评率
--   Block 3: CTE category_supply  — 品类取消率 / 缺货率
--   Block 4: 三表 JOIN + 品类分层标签
--   Block 5: NULL category 钻取
-- ============================================================

USE Olist;
-- ============================================================
-- Block 1-4: 品类全景分析（CTE 串联）
-- CTE串联指的是在一个查询中，通过 WITH 关键字定义多个公共表表达式，并且这些 CTE 之间可以相互引用，形成一个处理链条。
-- 后面的 CTE 可以引用前面的，但前面不能引用后面的（不允许循环依赖）。 
WITH category_gmv AS (
    -- --------------------------------------------------------
    -- Block 1: 品类 GMV + 基础经营指标
    -- --------------------------------------------------------
    -- 口径说明:
    --   排除 canceled 和 unavailable 订单（这些订单未产生实际收入）
    --   保留 delivered/shipped/invoiced/approved/processing（已付款的）
    --   COALESCE 把 NULL 品类统一标记为 'NULL (未分类)'，避免被遗漏
    -- --------------------------------------------------------
    SELECT
        COALESCE(t.product_category_name_english, 'NULL (未分类)') AS category_name,
        -- 提取t.product_category_name_english的值，如果为NULL则使用'NULL (未分类)'作为默认值
        ROUND(SUM(oi.price + oi.freight_value), 2)        AS total_gmv,
        COUNT(DISTINCT o.order_id)                         AS order_count,
        COUNT(DISTINCT oi.product_id)                      AS sku_count,
        -- 品类数
        COUNT(oi.order_item_id)                            AS item_count,
        ROUND(SUM(oi.price + oi.freight_value)
              / COUNT(DISTINCT o.order_id), 2)             AS avg_order_value,
        -- 客单价 = GMV / 订单数       
        ROUND(SUM(oi.price) / COUNT(oi.order_item_id), 2)  AS avg_item_price
        -- 客单价（不含运费）= 商品总价 / 商品件数
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
         ON p.product_category_name = t.product_category_name
    JOIN v_orders_clean o ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    -- 只统计未取消且未缺货的订单，因为这些订单才产生实际收入
    GROUP BY t.product_category_name_english
),
category_exp AS (
    -- --------------------------------------------------------
    -- Block 2: 品类体验指标（评分 + 配送）
    -- --------------------------------------------------------
    -- 口径说明:
    --   评分: 只统计有评价的订单（INNER JOIN order_reviews）
    --   配送时长: 只统计 delivered 且时间戳完整的订单
    --   早评率: review_creation_date < order_delivered_customer_date
    --   注意: 一个订单可能有多条 review，取最早的 review_creation_date
    -- --------------------------------------------------------
    SELECT
        COALESCE(t.product_category_name_english, 'NULL (未分类)') AS category_name,
        -- 评分维度
        ROUND(AVG(r.review_score), 2)                              AS avg_review_score,
        -- 平均评分
        ROUND(SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
              * 100.0 / COUNT(*), 2)                               AS negative_rate_pct,
        -- 差评率
        COUNT(*)                                                    AS reviewed_order_count,
        -- 配送维度（仅 delivered + 时间戳完整）
        ROUND(AVG(DATEDIFF(o.order_delivered_carrier_date,
                            o.order_approved_at)), 2)              AS avg_processing_days,
        -- 平均备货时长                    
        ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                            o.order_delivered_carrier_date)), 2)   AS avg_shipping_days,
        -- 平均配送时长
        ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                            o.order_purchase_timestamp)), 2)       AS avg_total_delivery_days,
        -- 平均总履约时长 = 从下单到送达客户的天数
        ROUND(SUM(CASE WHEN r.review_creation_date
                             < o.order_delivered_customer_date
                        THEN 1 ELSE 0 END)
              * 100.0 / COUNT(*), 2)                               AS early_review_rate_pct
        -- 早评率 = 早评订单数 / 评价订单数
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    JOIN v_orders_clean o ON oi.order_id = o.order_id
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_carrier_date < o.order_delivered_customer_date
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_approved_at IS NOT NULL
        -- 只统计已送达且时间戳完整的订单，确保配送时长计算准确
    GROUP BY t.product_category_name_english
),

category_supply AS (
    -- --------------------------------------------------------
    -- Block 3: 品类供给稳定性（取消率 + 缺货率）
    -- --------------------------------------------------------
    -- 口径说明:
    --   这里需要 ALL orders（包括 canceled 和 unavailable），
    --   所以用 orders 表而不是 v_orders_clean。
    --   只统计有 order_items 的订单（能归到品类）。
    --   注意: 775 个订单没有 order_items，无法归因到品类，另作说明。
    -- --------------------------------------------------------
    SELECT
        COALESCE(t.product_category_name_english, 'NULL (未分类)') AS category_name,
        COUNT(DISTINCT o.order_id)                                  AS total_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)                   AS canceled_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)                   AS unavailable_orders,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                                  THEN o.order_id END)
              * 100.0 / COUNT(DISTINCT o.order_id), 2)             AS cancel_rate_pct,
        ROUND(COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                                  THEN o.order_id END)
              * 100.0 / COUNT(DISTINCT o.order_id), 2)             AS unavailable_rate_pct
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    GROUP BY t.product_category_name_english
)
-- ============================================================
-- Block 4: 综合评分表（三表 JOIN + 品类分层标签）
-- ============================================================
SELECT
    g.category_name,
    -- 经营指标
    g.total_gmv,
    g.order_count,
    g.sku_count,
    g.avg_order_value,
    g.avg_item_price,
    ROUND(g.total_gmv * 100.0 / SUM(g.total_gmv) OVER(), 2) AS gmv_pct,
    -- GMV占比：计算当前行的的GMV占所有行的GMV的比重
    ROW_NUMBER() OVER(ORDER BY g.total_gmv DESC)             AS gmv_rank,
    -- 按 GMV 降序给每行一个从 1 开始的数字。GMV 最高的品类是 1，第二是 2，以此类推。重复的GMV排名不重复1
    -- 体验指标
    e.avg_review_score,
    e.negative_rate_pct,
    e.avg_processing_days,
    e.avg_shipping_days,
    e.avg_total_delivery_days,
    e.early_review_rate_pct,
    -- 供给稳定性
    s.cancel_rate_pct,
    s.unavailable_rate_pct,
    -- 品类分层标签
    CASE
        -- 推荐优先: GMV 前 20 且评分 >= 4 且总履约 <= 15 天
        WHEN ROW_NUMBER() OVER(ORDER BY g.total_gmv DESC) <= 20
             -- 71 个品类中 top 20 通常贡献约 70-80% GMV（帕累托原则）
             AND e.avg_review_score >= 4.0
             --  分制中 4.0 是"满意"的心理阈值
             AND e.avg_total_delivery_days <= 15
             -- 之前漏斗分析显示平均总履约 11.6 天，15 天约是 75 分位
        THEN '推荐优先'
        -- 治理优先: GMV 前 20 但 (评分 < 3.5 或 总履约 > 20 天 或 缺货率 > 5%)
        WHEN ROW_NUMBER() OVER(ORDER BY g.total_gmv DESC) <= 20
             AND (e.avg_review_score < 3.5
                  OR e.avg_total_delivery_days > 20
                  OR s.unavailable_rate_pct > 5)
                  -- 缺货率超过5%意味着每20单将有一单缺货，用户感知明显
        THEN '治理优先'
        -- 潜力品类: GMV 排名 21-50 且评分 >= 4.0
        WHEN ROW_NUMBER() OVER(ORDER BY g.total_gmv DESC) BETWEEN 21 AND 50
             AND e.avg_review_score >= 4.0
        THEN '潜力品类'
        -- 常规品类: 其余
        ELSE '常规品类'
    END AS category_tier
FROM category_gmv g
LEFT JOIN category_exp e    ON g.category_name = e.category_name
LEFT JOIN category_supply s ON g.category_name = s.category_name
ORDER BY g.total_gmv DESC;
-- ============================================================
-- Block 5: NULL category 订单钻取
-- ============================================================
-- 目的: 量化"品类未知"商品的影响范围
-- 如果 GMV 占比 < 1%，可标注后忽略；如果 > 5%，需要标记为数据质量限制
-- ============================================================
SELECT
    'NULL (未分类)' AS category_name,
    COUNT(DISTINCT p.product_id) AS null_category_products,
    COUNT(DISTINCT o.order_id)   AS null_category_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS null_category_gmv,
    ROUND(SUM(oi.price + oi.freight_value) * 100.0
          / (SELECT SUM(price + freight_value)
             FROM order_items oi2
             JOIN v_orders_clean o2 ON oi2.order_id = o2.order_id
             WHERE o2.order_status NOT IN ('canceled', 'unavailable')
            ), 2) AS null_category_gmv_pct
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN v_orders_clean o ON oi.order_id = o.order_id
WHERE p.product_category_name IS NULL
  AND o.order_status NOT IN ('canceled', 'unavailable');
-- ============================================================
-- Block 6: 用户首购品类 vs 复购品类（跨品类或同品类）
-- ============================================================
-- 目的: 回答"用户复购时是买同一品类还是跨品类"
-- 如果同品类复购率高 → 推荐系统做同品类召回有效
-- 如果跨品类多 → ItemCF 比同品类推荐更有价值
-- ============================================================
WITH user_orders AS (
    SELECT
        c.customer_unique_id,
        COALESCE(t.product_category_name_english, 'NULL (未分类)') AS category_name,
        o.order_id,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER(
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_seq
        -- 按照unique_id分组，每个客户给下单时间进行排序
    FROM customers c
    JOIN v_orders_clean o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
),
first_purchase AS (
    -- 每个用户一行：首购品类
    SELECT
        customer_unique_id,
        category_name AS first_category
    FROM user_orders
    WHERE order_seq = 1
),
repurchase_check AS (
    -- 检查每个用户第2+ 单中是否有和首单同品类的
    SELECT fp.customer_unique_id,
           fp.first_category,
           -- MAX + CASE: 只要后续订单中有一笔及以上的同品类,就标记 1
           MAX(CASE WHEN uo.order_seq >1 
                    AND uo.category_name = fp.first_category
                    THEN 1 ELSE 0 END) AS has_same_category_repurchase
    FROM first_purchase fp
    JOIN user_orders uo  ON fp.customer_unique_id = uo.customer_unique_id
    GROUP BY fp.customer_unique_id , fp.first_category
)
SELECT 
    first_category,
    COUNT(DISTINCT customer_unique_id) AS first_purchase_users,
    -- 同品类复购用户数
    COUNT(DISTINCT CASE WHEN has_same_category_repurchase = 1
                        THEN customer_unique_id END) AS same_category_repurchase_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN has_same_category_repurchase =1 THEN customer_unique_id END)
        *100.0 / COUNT(DISTINCT customer_unique_id),2) AS same_category_rate_pct
FROM repurchase_check
GROUP BY first_category
ORDER BY first_purchase_users DESC;

-- ============================================================
-- Block 7: office_furniture 卖家维度钻取
-- ============================================================
-- 目的: 定位 office_furniture 品类体验差的根因——是品类天然属性还是个别卖家拖累
-- 如果 2-3 个卖家贡献大部分差评/慢履约 → 治理卖家而非治理品类
-- 如果所有卖家表现一致差 → 品类天然属性（大件家具），需匹配需求而非改善履约
-- ============================================================
WITH seller_stats AS (
    SELECT
        s.seller_id,
        -- 经营指标
        COUNT(DISTINCT o.order_id)                         AS order_count,
        ROUND(SUM(oi.price + oi.freight_value), 2)         AS gmv,
        ROUND(SUM(oi.price + oi.freight_value)
              / COUNT(DISTINCT o.order_id), 2)              AS avg_order_value,
        -- 体验指标
        ROUND(AVG(r.review_score), 2)                      AS avg_review_score,
        ROUND(SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
              * 100.0 / COUNT(*), 2)                        AS negative_rate_pct,
        ROUND(AVG(DATEDIFF(o.order_delivered_carrier_date,
                            o.order_approved_at)), 2)       AS avg_processing_days,
        ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                            o.order_delivered_carrier_date)), 2) AS avg_shipping_days,
        ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                            o.order_purchase_timestamp)), 2) AS avg_total_delivery_days,
        -- 供给稳定性
        COUNT(DISTINCT CASE WHEN o.order_status = 'canceled'
                            THEN o.order_id END)            AS canceled_orders,
        COUNT(DISTINCT CASE WHEN o.order_status = 'unavailable'
                            THEN o.order_id END)            AS unavailable_orders
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    JOIN orders o ON oi.order_id = o.order_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    WHERE t.product_category_name_english LIKE '%office_furniture%'
    GROUP BY s.seller_id
),
category_totals AS (
    -- 品类整体数据，用作分母
    SELECT
        SUM(order_count)          AS total_orders,
        SUM(gmv)                  AS total_gmv,
        COUNT(DISTINCT seller_id) AS seller_count
    FROM seller_stats
)
SELECT
    ss.seller_id,
    ss.order_count,
    ss.gmv,
    ROUND(ss.gmv * 100.0 / ct.total_gmv, 2)               AS gmv_pct,
    ROUND(ss.order_count * 100.0 / ct.total_orders, 2)     AS order_pct,
    ss.avg_order_value,
    ss.avg_review_score,
    ss.negative_rate_pct,
    ss.avg_processing_days,
    ss.avg_shipping_days,
    ss.avg_total_delivery_days,
    ss.canceled_orders,
    ss.unavailable_orders,
    -- 卖家分级标签
    CASE
        WHEN ss.avg_review_score >= 4.0
             AND ss.avg_total_delivery_days <= 15
             AND ss.order_count >= ct.total_orders * 0.02  -- 订单量 >= 品类总量的 2%
        THEN '优质卖家'
        WHEN ss.avg_review_score < 3.0
              OR ss.avg_total_delivery_days > 25
              OR ss.negative_rate_pct > 30
        THEN '风险卖家'
        WHEN ss.order_count < 5 THEN '小卖家（观望）'
        ELSE '普通卖家'
    END AS seller_tier
FROM seller_stats ss
CROSS JOIN category_totals ct
ORDER BY ss.gmv DESC;

-- office_furniture出现了不可见字符通过下面方式排查是否如此
-- 看看到底是什么字符
SELECT 
    product_category_name_english,
    HEX(product_category_name_english) AS hex_str,
    CHAR_LENGTH(product_category_name_english) AS char_len
FROM product_category_name_translation
WHERE product_category_name_english LIKE '%office_furniture%';

-- 同时扫一下全表，看还有没有其他品名也带了不可见字符（长度异常的）
SELECT 
    product_category_name_english,
    CHAR_LENGTH(product_category_name_english) AS char_len,
    LENGTH(product_category_name_english) AS byte_len
    -- 正常情况下char_len = byte_len
FROM product_category_name_translation
WHERE CHAR_LENGTH(product_category_name_english) != CHAR_LENGTH('office_furniture')  -- 这里只是触发条件，不重要
   OR CHAR_LENGTH(product_category_name_english) > 20;  -- 正常品名不会超过 20 个可见字符

