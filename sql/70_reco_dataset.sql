USE Olist;

-- ============================================================
-- 70. 推荐系统候选召回数据集
-- ============================================================
-- 目标:
--   基于 Olist 购买行为构建推荐系统离线评估数据集。
--
-- 核心原则:
--   1. Olist 没有曝光/点击/加购数据，所以正反馈定义为“购买”。
--   2. 先保留事件级购买明细，再按时间切分 train / val。
--   3. 所有训练特征、热门榜、召回候选都只使用训练期数据。
--   4. 验证集只用于评估未来购买，避免未来信息泄漏。
-- ============================================================
SET @split_date := '2018-06-01 00:00:00';
SET @global_top_k := 200;
SET @category_top_k := 10;
SET @min_train_orders := 5;
-- ============================================================
-- Block 0: 清理旧结果表
-- ============================================================
DROP TABLE IF EXISTS category_hot_baseline;
DROP TABLE IF EXISTS global_hot_baseline;
DROP TABLE IF EXISTS product_features_train;
DROP TABLE IF EXISTS val_interactions;
DROP TABLE IF EXISTS train_interactions;
DROP TABLE IF EXISTS interaction_events;
-- ============================================================
-- Block 1: 购买事件明细表
-- ============================================================
-- 每一行代表一个订单商品明细事件。
-- 注意:
--   这里还不聚合 user-item，因为推荐系统要先按时间切分，
--   再分别聚合训练集和验证集。
-- ============================================================
CREATE TABLE interaction_events AS
SELECT
    c.customer_unique_id            AS user_id,
    oi.product_id,
    oi.seller_id,
    o.order_id,
    oi.order_item_id,
    o.order_purchase_timestamp,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL;

ALTER TABLE interaction_events
ADD PRIMARY KEY (order_id, order_item_id),
ADD INDEX idx_ie_user (user_id),
ADD INDEX idx_ie_product (product_id),
ADD INDEX idx_ie_time (order_purchase_timestamp),
ADD INDEX idx_ie_time_user_product (order_purchase_timestamp, user_id, product_id),
ADD INDEX idx_ie_user_time (user_id, order_purchase_timestamp),
ADD INDEX idx_ie_product_time (product_id, order_purchase_timestamp);
-- ============================================================
-- Block 2: 训练集 user-item 聚合
-- ============================================================
-- 训练集:
--   只使用 @split_date 之前的购买事件。
--
-- item_count:
--   商品件数，同一订单买多件会累计。
--
-- order_count:
--   购买次数，同一订单内多件只算一次。
--
-- interaction_score:
--   隐式反馈强度。截断到 5 分，避免极少数重复购买用户
--   对协同过滤相似度产生过强影响。
-- ============================================================
CREATE TABLE train_interactions AS
SELECT
    user_id,
    product_id,
    COUNT(*)                                               AS item_count,
    COUNT(DISTINCT order_id)                               AS order_count,
    ROUND(SUM(price + freight_value), 2)                   AS total_spent,
    MIN(order_purchase_timestamp)                          AS first_purchase_time,
    MAX(order_purchase_timestamp)                          AS last_purchase_time,
    1 + LEAST(COUNT(DISTINCT order_id) - 1, 4)             AS interaction_score
FROM interaction_events
WHERE order_purchase_timestamp < @split_date
GROUP BY user_id, product_id;
ALTER TABLE train_interactions
ADD PRIMARY KEY (user_id, product_id),
ADD INDEX idx_ti_product (product_id),
ADD INDEX idx_ti_product_score (product_id, interaction_score),
ADD INDEX idx_ti_user_score (user_id, interaction_score);
-- ============================================================
-- Block 3: 验证集 user-item 聚合
-- ============================================================
-- 验证集:
--   使用 @split_date 及之后的购买事件。
--   后续 Recall@K / NDCG@K 就用它作为 future ground truth。
-- ============================================================
CREATE TABLE val_interactions AS
SELECT
    user_id,
    product_id,
    COUNT(*)                                               AS item_count,
    COUNT(DISTINCT order_id)                               AS order_count,
    ROUND(SUM(price + freight_value), 2)                   AS total_spent,
    MIN(order_purchase_timestamp)                          AS first_purchase_time,
    MAX(order_purchase_timestamp)                          AS last_purchase_time,
    1 + LEAST(COUNT(DISTINCT order_id) - 1, 4)             AS interaction_score
FROM interaction_events
WHERE order_purchase_timestamp >= @split_date
GROUP BY user_id, product_id;
ALTER TABLE val_interactions
ADD PRIMARY KEY (user_id, product_id),
ADD INDEX idx_vi_product (product_id),
ADD INDEX idx_vi_user_score (user_id, interaction_score);
-- ============================================================
-- Block 4: 训练期商品特征宽表
-- ============================================================
-- 设计原则:
--   1. 商品销量、价格、评分都只用训练期数据。
--   2. review_creation_date 也必须早于切分点。
--   3. Olist 的 review 是订单级评分，不是商品级评分，
--      所以这里用订单评分近似商品体验评分。
--   4. 先按 order_id 聚合 review，再 join，避免一单多评放大明细行。
-- ============================================================
CREATE TABLE product_features_train AS
WITH review_agg AS (
    SELECT
        order_id,
        AVG(review_score) AS order_avg_review_score
    FROM order_reviews
    WHERE review_creation_date < @split_date
    GROUP BY order_id
),
train_stats AS (
    SELECT
        ie.product_id,
        COALESCE(t.product_category_name_english, 'NULL')      AS category_name,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        (p.product_length_cm * p.product_height_cm * p.product_width_cm)
                                                                 AS product_volume_cm3,
        ROUND(AVG(ie.price), 2)                                 AS avg_price,
        ROUND(AVG(ra.order_avg_review_score), 2)                AS avg_review_score,
        ROUND(
            AVG(
                CASE
                    WHEN ra.order_avg_review_score IS NULL THEN NULL
                    WHEN ra.order_avg_review_score <= 2 THEN 1
                    ELSE 0
                END
            ) * 100,
            2
        )                                                       AS bad_review_rate_pct,
        COUNT(*)                                                AS item_count_train,
        COUNT(DISTINCT ie.order_id)                             AS order_count_train,
        COUNT(DISTINCT ie.user_id)                              AS buyer_count_train,
        COUNT(DISTINCT CASE
            WHEN ra.order_avg_review_score IS NOT NULL THEN ie.order_id
        END)                                                    AS reviewed_order_count_train,
        MIN(ie.order_purchase_timestamp)                        AS first_seen_train,
        MAX(ie.order_purchase_timestamp)                        AS last_seen_train
    FROM interaction_events ie
    JOIN products p
        ON ie.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    LEFT JOIN review_agg ra
        ON ie.order_id = ra.order_id
    WHERE ie.order_purchase_timestamp < @split_date
    GROUP BY
        ie.product_id,
        t.product_category_name_english,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm
)
SELECT
    *,
    CASE
        WHEN avg_price < 50  THEN '低价(<50)'
        WHEN avg_price < 150 THEN '中价(50-150)'
        WHEN avg_price < 500 THEN '高价(150-500)'
        ELSE '超高价(>500)'
    END AS price_tier
FROM train_stats;

ALTER TABLE product_features_train
ADD PRIMARY KEY (product_id),
ADD INDEX idx_pft_category (category_name),
ADD INDEX idx_pft_order_count (order_count_train),
ADD INDEX idx_pft_buyer_count (buyer_count_train),
ADD INDEX idx_pft_price_tier (price_tier);
-- ============================================================
-- Block 5: 冷启动分析
-- ============================================================
-- 冷启动用户:
--   验证集出现，但训练集从未出现过的用户。
--
-- 冷启动商品:
--   验证集出现，但训练集从未出现过的商品。
--
-- 推荐系统意义:
--   冷启动比例越高，协同过滤越难覆盖，需要热门、品类、地域、
--   卖家质量等规则召回补位。
-- ============================================================
WITH val_users AS (
    SELECT DISTINCT user_id
    FROM val_interactions
),
train_users AS (
    SELECT DISTINCT user_id
    FROM train_interactions
),
val_products AS (
    SELECT DISTINCT product_id
    FROM val_interactions
),
train_products AS (
    SELECT DISTINCT product_id
    FROM train_interactions
)
SELECT
    '用户冷启动' AS type,
    COUNT(v.user_id) AS total_val,
    SUM(CASE WHEN t.user_id IS NULL THEN 1 ELSE 0 END) AS cold_start,
    ROUND(
        SUM(CASE WHEN t.user_id IS NULL THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(v.user_id), 0),
        2
    ) AS cold_start_rate_pct
FROM val_users v
LEFT JOIN train_users t
    ON v.user_id = t.user_id

UNION ALL

SELECT
    '商品冷启动' AS type,
    COUNT(v.product_id) AS total_val,
    SUM(CASE WHEN t.product_id IS NULL THEN 1 ELSE 0 END) AS cold_start,
    ROUND(
        SUM(CASE WHEN t.product_id IS NULL THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(v.product_id), 0),
        2
    ) AS cold_start_rate_pct
FROM val_products v
LEFT JOIN train_products t
    ON v.product_id = t.product_id;
-- ============================================================
-- Block 6: 全局热门 baseline
-- ============================================================
-- 用途:
--   最简单但很强的推荐 baseline。
--
-- 注意:
--   热门榜只能基于训练期销量生成，不能用全量销量。
-- ============================================================
CREATE TABLE global_hot_baseline AS
SELECT *
FROM (
    SELECT
        pf.product_id,
        pf.category_name,
        pf.price_tier,
        pf.avg_price,
        pf.avg_review_score,
        pf.bad_review_rate_pct,
        pf.order_count_train,
        pf.buyer_count_train,
        ROW_NUMBER() OVER (
            ORDER BY
                pf.order_count_train DESC,
                pf.buyer_count_train DESC,
                pf.avg_review_score DESC,
                pf.product_id
        ) AS global_hot_rank
    FROM product_features_train pf
    WHERE pf.order_count_train >= @min_train_orders
) ranked
WHERE global_hot_rank <= @global_top_k
ORDER BY global_hot_rank;

ALTER TABLE global_hot_baseline
ADD PRIMARY KEY (global_hot_rank),
ADD INDEX idx_gh_product (product_id),
ADD INDEX idx_gh_category (category_name);
-- ============================================================
-- Block 7: 每品类 Top K 热门 baseline
-- ============================================================
-- 用途:
--   给用户做“同品类热门召回”。
--
-- 典型用法:
--   用户买过某个品类 -> 召回该品类训练期热门商品。
-- ============================================================
CREATE TABLE category_hot_baseline AS
WITH ranked AS (
    SELECT
        pf.product_id,
        pf.category_name,
        pf.price_tier,
        pf.avg_price,
        pf.avg_review_score,
        pf.bad_review_rate_pct,
        pf.order_count_train,
        pf.buyer_count_train,
        ROW_NUMBER() OVER (
            PARTITION BY pf.category_name
            ORDER BY
                pf.order_count_train DESC,
                pf.buyer_count_train DESC,
                pf.avg_review_score DESC,
                pf.product_id
        ) AS category_hot_rank
    FROM product_features_train pf
    WHERE pf.order_count_train >= @min_train_orders
)
SELECT *
FROM ranked
WHERE category_hot_rank <= @category_top_k
ORDER BY category_name, category_hot_rank;

ALTER TABLE category_hot_baseline
ADD PRIMARY KEY (category_name, category_hot_rank),
ADD INDEX idx_ch_product (product_id),
ADD INDEX idx_ch_category_product (category_name, product_id);
-- ============================================================
-- Block 8: 数据集验证
-- ============================================================
SELECT
    'interaction_events' AS table_name,
    COUNT(*) AS rows_cnt,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT product_id) AS products,
    COUNT(DISTINCT order_id) AS orders
FROM interaction_events

UNION ALL

SELECT
    'train_interactions' AS table_name,
    COUNT(*) AS rows_cnt,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT product_id) AS products,
    NULL AS orders
FROM train_interactions

UNION ALL

SELECT
    'val_interactions' AS table_name,
    COUNT(*) AS rows_cnt,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT product_id) AS products,
    NULL AS orders
FROM val_interactions

UNION ALL

SELECT
    'product_features_train' AS table_name,
    COUNT(*) AS rows_cnt,
    NULL AS users,
    COUNT(DISTINCT product_id) AS products,
    NULL AS orders
FROM product_features_train;
-- ============================================================
-- Block 9: 切分结果概览
-- ============================================================
SELECT
    'train' AS split_name,
    COUNT(*) AS interactions,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT product_id) AS products,
    ROUND(AVG(interaction_score), 2) AS avg_interaction_score,
    MIN(first_purchase_time) AS min_time,
    MAX(last_purchase_time) AS max_time
FROM train_interactions

UNION ALL

SELECT
    'val' AS split_name,
    COUNT(*) AS interactions,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT product_id) AS products,
    ROUND(AVG(interaction_score), 2) AS avg_interaction_score,
    MIN(first_purchase_time) AS min_time,
    MAX(last_purchase_time) AS max_time
FROM val_interactions;
-- ============================================================
-- Block 10: baseline 表验证
-- ============================================================
SELECT
    'global_hot_baseline' AS baseline_name,
    COUNT(*) AS candidate_count,
    COUNT(DISTINCT product_id) AS unique_products,
    COUNT(DISTINCT category_name) AS covered_categories
FROM global_hot_baseline

UNION ALL

SELECT
    'category_hot_baseline' AS baseline_name,
    COUNT(*) AS candidate_count,
    COUNT(DISTINCT product_id) AS unique_products,
    COUNT(DISTINCT category_name) AS covered_categories
FROM category_hot_baseline;
-- ============================================================
-- Block 11: 查看全局热门 Top 20
-- ============================================================
SELECT
    global_hot_rank,
    product_id,
    category_name,
    price_tier,
    avg_price,
    avg_review_score,
    order_count_train,
    buyer_count_train
FROM global_hot_baseline
ORDER BY global_hot_rank
LIMIT 20;
-- ============================================================
-- Block 12: 查看每品类热门样例
-- ============================================================
SELECT
    category_name,
    category_hot_rank,
    product_id,
    price_tier,
    avg_price,
    avg_review_score,
    order_count_train,
    buyer_count_train
FROM category_hot_baseline
ORDER BY category_name, category_hot_rank;