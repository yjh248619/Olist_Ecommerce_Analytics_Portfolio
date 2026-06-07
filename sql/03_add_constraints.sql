-- SQLBook: Code
-- ============================================================
-- 03. 添加外键约束
-- 前提:04_data_quality.sql 已确认所有外键引用 0 孤儿
-- 为什么导入后才加(而非建表时):
--   1. LOAD DATA 时逐行检查外键会拖慢 10 倍+
--   2. 导入顺序耦合(必须先父后子)
--   3. 工业界 ODS 层通常不加外键,事后补
-- ============================================================

USE Olist;

-- 3.1 orders → customers
ALTER TABLE orders
ADD CONSTRAINT fk_orders_customer
FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

-- 3.2 order_items → orders
ALTER TABLE order_items
ADD CONSTRAINT fk_order_items_order
FOREIGN KEY (order_id) REFERENCES orders(order_id);

-- 3.3 order_items → products
ALTER TABLE order_items
ADD CONSTRAINT fk_order_items_product
FOREIGN KEY (product_id) REFERENCES products(product_id);

-- 3.4 order_items → sellers
ALTER TABLE order_items
ADD CONSTRAINT fk_order_items_seller
FOREIGN KEY (seller_id) REFERENCES sellers(seller_id);

-- 3.5 order_payments → orders
ALTER TABLE order_payments
ADD CONSTRAINT fk_order_payments_order
FOREIGN KEY (order_id) REFERENCES orders(order_id);

-- 3.6 order_reviews → orders
ALTER TABLE order_reviews
ADD CONSTRAINT fk_order_reviews_order
FOREIGN KEY (order_id) REFERENCES orders(order_id);

-- ============================================================
-- 验证:所有外键是否建立成功
-- ============================================================
SELECT
    TABLE_NAME AS 子表,
    COLUMN_NAME AS 外键列,
    CONSTRAINT_NAME AS 约束名,
    REFERENCED_TABLE_NAME AS 父表,
    REFERENCED_COLUMN_NAME AS 父表列
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'olist'
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME;
