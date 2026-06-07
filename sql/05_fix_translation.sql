-- ============================================================
-- 05. 修复 product_category_name_translation 表中缺失的翻译
-- 原因:数据质量检查发现 13 条 products 记录引用了 2 个未翻译的类别
-- 来源:Olist 公开数据集,翻译表未跟进事实表的新增类别
-- ============================================================

USE Olist;

-- 补全 2 个缺失的类别翻译
INSERT INTO product_category_name_translation 
       (product_category_name, product_category_name_english)
VALUES
    ('pc_gamer', 'pc_gamer'),
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portables_kitchen_and_food_preparers');

-- 验证:补完后翻译表应有 73 行(原 71 + 新增 2)
SELECT COUNT(*) AS total_rows FROM product_category_name_translation;

-- 验证:再跑一次孤儿检查,应该为 0
SELECT COUNT(*) AS orphan_count
FROM products p
LEFT JOIN product_category_name_translation pct 
       ON p.product_category_name = pct.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND pct.product_category_name IS NULL;
