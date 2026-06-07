USE olist;
SHOW VARIABLES LIKE 'secure_file_priv';
-- MySQL 出于安全考虑,默认只允许从指定目录读取本地文件。先查这个目录在哪,然后把数据文件放到这个目录下
-- 公开仓库中的 C:/path/to/mysql_uploads/ 是占位路径,请替换为你本机 secure_file_priv 允许的目录
-- custoemrs 表
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_customers_dataset.csv'
-- INFILE '...'作用是指定要加载的文件路径,这个路径必须在 secure_file_priv 指定的目录下
-- Windows 用正斜杠 /,反斜杠 \ 要双写 \\(转义),正斜杠最简单
INTO TABLE customers
CHARACTER SET utf8mb4
-- 	Olist 有葡萄牙语字符(如 são paulo),不指定会乱码
FIELDS TERMINATED BY ','
-- CSV 默认逗号分隔
       OPTIONALLY ENCLOSED BY '"'
-- 含逗号的字段(如商品描述)用双引号包围,加 OPTIONALLY 表示"可选"(不是每行都有)
LINES TERMINATED BY '\n'
-- Windows CSV 用 \r\n,Mac/Linux 用 \n。Olist 的 CSV 是 \r\n,但 MySQL 默认是 \n —— 不指定会出错
IGNORE 1 LINES
-- 	CSV 第一行是字段名,不能当数据
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
-- 	显式声明字段,字段顺序必须与 CSV 列顺序一致(不是与表 DDL 顺序!)
;
SELECT COUNT(*) FROM customers;
-- 检查行数是否正确
SELECT *FROM customers LIMIT 5;
-- 抽样检查数据是否正确
SELECT DISTINCT customer_state FROM customers;
-- 检查州名是否正确(如 SP 是 São Paulo 的缩写)
SELECT customer_city FROM customers WHERE customer_city LIKE '%são%' LIMIT 5;
-- 检查城市名是否正确(如 São Paulo)

-- product_category_name_translation 表
LOAD DATA INFILE 'C:/path/to/mysql_uploads/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
       OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name,product_category_name_english)
;
SELECT COUNT(*) FROM product_category_name_translation;
SELECT*FROM product_category_name_translation LIMIT 5;
SELECT DISTINCT product_category_name FROM product_category_name_translation;

-- sellers 表
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
       OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);
SELECT COUNT(*) FROM sellers;
SELECT*FROM sellers LIMIT 5;
SELECT DISTINCT seller_id FROM sellers;
SELECT seller_city FROM sellers WHERE seller_city LIKE '%são%' LIMIT 5;
-- 4. products (~32951 行) ⚠️ 字段顺序对照 CSV 第一行!
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' 
       OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, @category, @name_len, @desc_len,
 @photos, @weight, @length, @height, @width)
 SET product_category_name     = NULLIF(@category, ''),
     product_name_lenght       = NULLIF(@name_len, ''),
     product_description_lenght = NULLIF(@desc_len, ''),
     product_photos_qty        = NULLIF(@photos, ''),
     product_weight_g          = NULLIF(@weight, ''),
     product_length_cm         = NULLIF(@length, ''),
     product_height_cm         = NULLIF(@height, ''),
     product_width_cm          = NULLIF(@width, '')
 ;
 SELECT COUNT(*) FROM products;
 SELECT COUNT(*) FROM products WHERE product_name_lenght IS NULL;

-- 5. geolocation (~100 万行,最大的表,会跑久一点)
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state);
-- 6. orders (~99441 行)
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, order_purchase_timestamp,
 @approved, @carrier_date,
 @delivered_customer_date, order_estimated_delivery_date)
 SET order_approved_at       = NULLIF(@approved, ''),
     order_delivered_carrier_date      = NULLIF(@carrier_date, ''),
     order_delivered_customer_date = NULLIF(@delivered_customer_date, '');

-- 7. order_items (~112650 行)
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value);

-- 8. order_payments (~103886 行)
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, payment_value);
-- 9. order_reviews (~100k 行)
TRUNCATE TABLE order_reviews;
LOAD DATA INFILE 'C:/path/to/mysql_uploads/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(review_id, order_id, review_score, @comment_title, @comment_message, review_creation_date, @timestamp)
 SET review_comment_title   = NULLIF(@comment_title, ''),
     review_comment_message = NULLIF(@comment_message, ''),
     review_answer_timestamp =NULLIF(@timestamp, '')
       ;
