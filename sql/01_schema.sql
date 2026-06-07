-- ============================================================
-- 01. customers 客户表
-- 一个 customer_id 代表一次下单的客户（即"订单意义上"的客户）
-- 同一个真实用户多次下单会有多个 customer_id，
-- 真正的唯一用户身份是 customer_unique_id
-- ============================================================
USE Olist;
CREATE TABLE customers (
    customer_id              CHAR(32) NOT NULL COMMENT  '订单维度的客户ID（每次下单生成一个）',
    customer_unique_id       CHAR(32) NOT NULL COMMENT  '真实用户唯一ID（用于复购分析）',
    customer_zip_code_prefix VARCHAR(10) NOT NULL COMMENT  '邮编前缀（巴西邮编可能有前导0）',
    customer_city            VARCHAR(50) NOT NULL COMMENT '城市名',
    customer_state           CHAR(2) NOT NULL COMMENT '州缩写（如 SP/RJ）',
    PRIMARY KEY (customer_id),
    KEY idx_unique_id (customer_unique_id),
    -- 为它建索引：业务上要做"找出某个真实用户的所有订单"（复购分析必查），不建索引会全表扫描
    KEY idx_zip (customer_zip_code_prefix),
    KEY idx_state (customer_state)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '客户订单表（订单维度，非唯一用户维度）';

CREATE TABLE orders (
    order_id                      CHAR(32) NOT NULL COMMENT '订单ID每个订单有一个唯一的ID',
    customer_id                   CHAR(32) NOT NULL COMMENT '订单维度的客户ID(每次下单生成一个)',
    order_status                  VARCHAR(20) NOT NULL COMMENT '每个订单的状态',
    order_purchase_timestamp      DATETIME NOT NULL COMMENT '下单时间',
    order_approved_at             DATETIME NULL COMMENT '付款时间(可能有未付款)',
    order_delivered_carrier_date  DATETIME NULL COMMENT '发货时间',
    order_delivered_customer_date DATETIME NULL COMMENT '可能未送达',
    order_estimated_delivery_date DATETIME NOT NULL COMMENT '预计送达日期',
    PRIMARY KEY (order_id),
    KEY idx_customer_id (customer_id),
    KEY idx_order_status (order_status),
    KEY idx_timestamp (order_purchase_timestamp)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '订单表';

/* DECIMAL(10,2) 而不是 FLOAT/DOUBLE：
 浮点数算钱会丢精度（0.1 + 0.2 != 0.3）
 DECIMAL 是定点数，精确
 (10,2) = 总共 10 位、小数 2 位 = 最大 99999999.99 ≈ 1 亿，电商够用*/
CREATE TABLE order_items (
    order_id                    CHAR(32) NOT NULL COMMENT '订单ID，每个订单有一个唯一的ID',
    order_item_id               TINYINT UNSIGNED NOT NULL COMMENT '每个订单可以有多个项目',
    product_id                  CHAR(32) NOT NULL COMMENT '产品的ID',
    seller_id                   CHAR(32) NOT NULL COMMENT '销售员ID',
    shipping_limit_date         DATETIME NOT NULL COMMENT '发货截至时间',
    price                       DECIMAL(10, 2) NOT NULL COMMENT '价格',
    freight_value               DECIMAL(10, 2) NOT NULL COMMENT '运费',
    /* 复合主键的列顺序很关键：把 order_id 放前面，因为 InnoDB 主键索引可以前缀使用——查 WHERE order_id = X 走主键，
     查 WHERE order_item_id = Y 不走主键。Olist 业务上查"某订单的所有商品"远多于"序号为 Y 的所有商品"，所以 order_id 在前。*/
    PRIMARY KEY (order_id, order_item_id),
    KEY idx_seller_id (seller_id),
    KEY idx_product_id (product_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '订单商品明细表（一个订单可包含多个商品行，主键为 order_id + order_item_id)';

CREATE TABLE order_payments(
    order_id                     CHAR(32) NOT NULL COMMENT '订单id',
    payment_sequential           TINYINT UNSIGNED NOT NULL COMMENT '支付序号（一个订单可能分次付）',
    payment_type                 VARCHAR(20) NOT NULL COMMENT '付款方式',
    payment_installments         TINYINT unsigned NOT NULL COMMENT '分期数',
    payment_value DECIMAL(10, 2) NOT NULL COMMENT '付款金额',
    PRIMARY KEY (order_id, payment_sequential),
    KEY idx_payment_type (payment_type)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci 
COMMENT = '订单支付表（一个订单可分多次支付，主键为 order_id + payment_sequential）';

create TABLE order_reviews(
    review_id               CHAR(32) NOT NULL COMMENT '评价id',
    order_id                CHAR(32) NOT NULL COMMENT '订单Id',
    review_score            TINYINT UNSIGNED NOT NULL COMMENT '评分',
    review_comment_title    VARCHAR(100) NULL COMMENT '评价标题',
    review_comment_message  TEXT NULL COMMENT '评价内容',
    -- 自由输入的长文本一律 TEXT,预定义业务文本（如状态码或方式）才用 VARCHAR
    review_creation_date    DATETIME NOT NULL COMMENT = '评价时间',
    review_answer_timestamp DATETIME NULL COMMENT = '卖家回复评价时间',
    -- 可以不回复 '#'为MYSQL独有--更统一其他SQL语言可用
    PRIMARY KEY (order_id, review_id),
    -- 不能单独review_i做主键因为其在原数据中存在重复（同一 review_id 可能关联到多个 order_id，少数情况）
    KEY idx_review_score (review_score)
) engine = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci 
COMMENT = '订单评价表（注意：review_id 在原数据中可能重复，故采用复合主键）';

CREATE TABLE products(
    product_id                  CHAR(32) NOT NULL COMMENT  '产品ID（主键）',
    product_category_name       VARCHAR(50) NULL COMMENT '产品类别名',
    product_name_lenght         SMALLINT UNSIGNED NULL COMMENT '产品名称长度',
    product_description_lenght  SMALLINT UNSIGNED NULL COMMENT '产品描述长度',
    product_photos_qty           TINYINT UNSIGNED NULL COMMENT '产品图片数量',
    product_weight_g            INT UNSIGNED NULL COMMENT '产品重量克',
    product_length_cm           SMALLINT UNSIGNED NULL COMMENT '产品长度厘米',
    product_height_cm           SMALLINT UNSIGNED NULL COMMENT '产品高度厘米',
    product_width_cm            SMALLINT UNSIGNED NULL COMMENT '产品宽度厘米',
    PRIMARY KEY (product_id),
    KEY idx_category_name (product_category_name)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci 
COMMENT='商品维度表(注:product_category_name 为葡萄牙语,需 join product_category_name_translation 转英文)'

;
CREATE TABLE sellers(
    seller_id               CHAR(32) NOT NULL COMMENT '销售员ID（主键）',
    seller_zip_code_prefix  VARCHAR(10) NOT NULL COMMENT '邮编前缀（巴西邮编可能有前导0）',
    seller_city             VARCHAR(50) NOT NULL COMMENT '城市名',
    seller_state            CHAR(2) NOT NULL COMMENT '州缩写（如 SP/RJ）',
    PRIMARY KEY (seller_id),
    KEY idx_zip (seller_zip_code_prefix),
    -- JOIN geolocation 高频查询条件，建索引
    KEY idx_state (seller_state)
    -- 按州做卖家分析高频
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
COMMENT = '卖家表（每个卖家一个唯一ID）'
;

CREATE TABLE geolocation(
    geolocation_zip_code_prefix VARCHAR(10) NOT NULL COMMENT '邮编前缀（巴西邮编可能有前导0）',
    geolocation_lat            DECIMAL(10, 7) NOT NULL COMMENT '纬度',
    geolocation_lng            DECIMAL(10, 7) NOT NULL COMMENT '经度',
    geolocation_city           VARCHAR(50) NOT NULL COMMENT '城市名',
    geolocation_state          CHAR(2) NOT NULL COMMENT '州缩写（如 SP/RJ）',
    id                         BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT COMMENT '主键',
    PRIMARY KEY (id),
    KEY idx_zip (geolocation_zip_code_prefix),
    KEY idx_state_city (geolocation_state, geolocation_city)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
COMMENT = '地理位置表（邮编前缀维度的经纬度）'
-- 同一个邮编 01037 在 CSV 里对应多条经纬度记录（同一邮编覆盖一片区域，记录了多个采样点）
-- (zip, lat, lng) 组合也可能重复（数据本身就有重复行）
-- 没有任何字段组合能做唯一标识
/*为什么经纬度用 DECIMAL(10,7) 而不是 FLOAT
FLOAT 是浮点数有精度损失：地理坐标的小误差会导致定位偏移几十米
DECIMAL(10,7) = 整数 3 位 + 小数 7 位，精度 = 1.11 cm（1° 纬度 ≈ 111 km，10^-7 度 ≈ 1.11 cm）
10 位总数容纳 ±999.9999999，覆盖全球经纬度（-180180、-9090）
为什么建 (state, city) 复合索引?
业务上经常 WHERE state='SP' AND city='são paulo' 查特定城市
复合索引 (state, city) 同时支持 WHERE state=X 单条件 和 WHERE state=X AND city=Y 双条件（最左前缀原则）
不需要单独建 state 索引（被复合索引前缀覆盖）
面试常考：「最左前缀原则」标准考点
为什么要加自增 id 做物理主键
InnoDB 表必须有聚簇索引：不显式建主键，会用第一个 UNIQUE NOT NULL 字段；都没有就自动生成 6 字节隐藏 row_id
隐藏 row_id 的问题：
你看不见，无法在 SQL 里引用
全库共享一个递增计数器，高并发插入会有性能瓶颈
一旦未来要删除某条特定记录，没有 id 你定位不到
显式加 id BIGINT UNSIGNED AUTO_INCREMENT 解决全部问题*/
;
CREATE TABLE product_category_name_translation(
    product_category_name           VARCHAR(50) NOT NULL COMMENT '产品类别名（葡萄牙语），主键',
    product_category_name_english   VARCHAR(50) NOT NULL COMMENT '产品类别名（英语）',
    PRIMARY KEY (product_category_name)
    -- 不需要索引：只 71 行，且查询模式就是按 product_category_name 关联
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
COMMENT = '产品类别翻译表（葡萄牙语到英语）'
;
