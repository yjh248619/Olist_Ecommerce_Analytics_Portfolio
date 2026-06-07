USE Olist;

-- ============================================================
-- 55. 评价文本 VOC 分析
-- ============================================================
-- 一、分析目的:
-- 将 order_reviews 中的用户评论转成可解释的"用户声音"(VOC),
-- 补足纯数值指标看不到的差评原因。
--
-- 二、业务逻辑:
-- 平均评分和差评率只能告诉我们"体验不好",
-- 评论文本能进一步回答"为什么不好":
--   物流慢 / 没收到货 / 商品质量 / 退款客服 / 包装问题
--
-- 三、计算逻辑:
-- Block 1: 评论文本覆盖率与评分分布
-- Block 2: 差评关键词规则分类
-- Block 3: VOC 原因分布
-- Block 4: 品类 x VOC 原因
-- Block 5: 地域 x VOC 原因
-- Block 6: 履约时长与物流类差评关系
--
-- 四、注意:
-- Olist 评论主要是葡萄牙语。这里使用关键词规则,
-- 不是完整 NLP 模型。优点是可解释、SQL 可复现;缺点是召回不完整。
-- ============================================================

-- ============================================================
-- Block 1: 评论文本覆盖率
-- ============================================================
SELECT
    review_score,
    COUNT(*) AS review_count,
    SUM(CASE
        WHEN review_comment_message IS NOT NULL
         AND TRIM(review_comment_message) <> '' THEN 1
        ELSE 0
    END) AS with_comment_count,
    ROUND(SUM(CASE
        WHEN review_comment_message IS NOT NULL
         AND TRIM(review_comment_message) <> '' THEN 1
        ELSE 0
    END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS comment_rate_pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- ============================================================
-- Block 2: 差评关键词规则分类
-- ============================================================
-- 关键词说明:
-- atraso/demora/entrega       -> 物流慢或配送问题
-- nao recebi/nao chegou       -> 未收到货
-- defeito/quebrado/danificado -> 商品质量或破损
-- reembolso/estorno/troca     -> 退款退换
-- atendimento                 -> 客服体验
-- embalagem                   -> 包装问题
-- ============================================================
WITH negative_comments AS (
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        LOWER(
            REPLACE(
                REPLACE(
                    REPLACE(COALESCE(r.review_comment_message, ''), 'ã', 'a'),
                    'ç', 'c'
                ),
                'á', 'a'
            )
        ) AS comment_text
    FROM order_reviews r
    WHERE r.review_score <= 2
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
),
tagged AS (
    SELECT
        review_id,
        order_id,
        review_score,
        comment_text,
        CASE
            WHEN comment_text LIKE '%atras%'
              OR comment_text LIKE '%demora%'
              OR comment_text LIKE '%entrega%'
              OR comment_text LIKE '%correio%' THEN '物流配送问题'
            WHEN comment_text LIKE '%nao recebi%'
              OR comment_text LIKE '%nao chegou%'
              OR comment_text LIKE '%não recebi%'
              OR comment_text LIKE '%não chegou%' THEN '未收到货'
            WHEN comment_text LIKE '%defeito%'
              OR comment_text LIKE '%quebrad%'
              OR comment_text LIKE '%danific%'
              OR comment_text LIKE '%qualidade%' THEN '商品质量问题'
            WHEN comment_text LIKE '%reembolso%'
              OR comment_text LIKE '%estorno%'
              OR comment_text LIKE '%troca%'
              OR comment_text LIKE '%devolver%' THEN '退款退换问题'
            WHEN comment_text LIKE '%atendimento%'
              OR comment_text LIKE '%resposta%'
              OR comment_text LIKE '%suporte%' THEN '客服响应问题'
            WHEN comment_text LIKE '%embalagem%'
              OR comment_text LIKE '%pacote%' THEN '包装问题'
            ELSE '其他/未识别'
        END AS voc_reason
    FROM negative_comments
)
SELECT
    voc_reason,
    COUNT(*) AS comment_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS reason_share_pct,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM tagged
GROUP BY voc_reason
ORDER BY comment_count DESC;

-- ============================================================
-- Block 3: VOC 原因 x 评分
-- ============================================================
WITH tagged AS (
    SELECT
        r.review_score,
        CASE
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%atras%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%demora%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%entrega%' THEN '物流配送问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao chegou%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não chegou%' THEN '未收到货'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%defeito%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%quebrad%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%danific%' THEN '商品质量问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%reembolso%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%estorno%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%troca%' THEN '退款退换问题'
            ELSE '其他/未识别'
        END AS voc_reason
    FROM order_reviews r
    WHERE r.review_score <= 2
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
)
SELECT
    voc_reason,
    review_score,
    COUNT(*) AS cnt
FROM tagged
GROUP BY voc_reason, review_score
ORDER BY voc_reason, review_score;

-- ============================================================
-- Block 4: 品类 x VOC 原因
-- ============================================================
WITH order_category AS (
    SELECT
        oi.order_id,
        COALESCE(t.product_category_name_english, 'NULL') AS category_name
    FROM order_items oi
    JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    GROUP BY oi.order_id, COALESCE(t.product_category_name_english, 'NULL')
),
tagged AS (
    SELECT
        r.order_id,
        CASE
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%atras%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%demora%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%entrega%' THEN '物流配送问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao chegou%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não chegou%' THEN '未收到货'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%defeito%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%quebrad%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%danific%' THEN '商品质量问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%reembolso%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%estorno%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%troca%' THEN '退款退换问题'
            ELSE '其他/未识别'
        END AS voc_reason
    FROM order_reviews r
    WHERE r.review_score <= 2
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
)
SELECT
    oc.category_name,
    t.voc_reason,
    COUNT(*) AS comment_count,
    ROUND(COUNT(*) * 100.0
          / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY oc.category_name), 0), 2) AS reason_share_in_category_pct
FROM tagged t
JOIN order_category oc
    ON t.order_id = oc.order_id
GROUP BY oc.category_name, t.voc_reason
HAVING comment_count >= 5
ORDER BY oc.category_name, comment_count DESC;

-- ============================================================
-- Block 5: 地域 x VOC 原因
-- ============================================================
WITH tagged AS (
    SELECT
        o.order_id,
        c.customer_state,
        CASE
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%atras%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%demora%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%entrega%' THEN '物流配送问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não recebi%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%nao chegou%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%não chegou%' THEN '未收到货'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%defeito%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%quebrad%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%danific%' THEN '商品质量问题'
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%reembolso%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%estorno%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%troca%' THEN '退款退换问题'
            ELSE '其他/未识别'
        END AS voc_reason
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_reviews r
        ON o.order_id = r.order_id
    WHERE r.review_score <= 2
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
)
SELECT
    customer_state,
    voc_reason,
    COUNT(*) AS comment_count,
    ROUND(COUNT(*) * 100.0
          / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY customer_state), 0), 2) AS reason_share_in_state_pct
FROM tagged
GROUP BY customer_state, voc_reason
HAVING comment_count >= 5
ORDER BY customer_state, comment_count DESC;

-- ============================================================
-- Block 6: 履约时长与物流类差评关系
-- ============================================================
WITH review_tag AS (
    SELECT
        r.order_id,
        r.review_score,
        CASE
            WHEN LOWER(COALESCE(r.review_comment_message, '')) LIKE '%atras%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%demora%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%entrega%'
              OR LOWER(COALESCE(r.review_comment_message, '')) LIKE '%correio%' THEN 1
            ELSE 0
        END AS is_logistics_complaint
    FROM order_reviews r
    WHERE r.review_score <= 2
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
),
order_delivery AS (
    SELECT
        o.order_id,
        TIMESTAMPDIFF(HOUR, o.order_purchase_timestamp, o.order_delivered_customer_date) / 24 AS total_delivery_days
    FROM v_orders_clean o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE
        WHEN od.total_delivery_days < 7 THEN '<7天'
        WHEN od.total_delivery_days < 14 THEN '7-14天'
        WHEN od.total_delivery_days < 21 THEN '14-21天'
        ELSE '21天以上'
    END AS delivery_days_bucket,
    COUNT(*) AS negative_comment_count,
    SUM(rt.is_logistics_complaint) AS logistics_complaints,
    ROUND(SUM(rt.is_logistics_complaint) * 100.0 / NULLIF(COUNT(*), 0), 2) AS logistics_complaint_rate_pct,
    ROUND(AVG(rt.review_score), 2) AS avg_review_score
FROM review_tag rt
JOIN order_delivery od
    ON rt.order_id = od.order_id
GROUP BY delivery_days_bucket
ORDER BY MIN(od.total_delivery_days);

-- ============================================================
-- 七、预期结果:
-- 1. 差评文本覆盖率不会是 100%,因为很多用户只打分不留言。
-- 2. 物流配送问题和未收到货预计是差评文本中的重要类别。
-- 3. 慢履约区间的物流类投诉占比应更高。
-- 4. VOC 是关键词规则,不是完整 NLP,结论应作为方向性洞察。
-- ============================================================

