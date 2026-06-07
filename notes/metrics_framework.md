# Olist 电商指标体系设计

> 模块定位:纯数据分析岗专项补充  
> 目标:把项目中的 GMV、用户、履约、品类、卖家、评价等指标组织成一套可下钻、可监控、可解释的电商平台指标体系。

---

## 一、分析目的

本模块回答一个数据分析岗高频问题:

**如果让你负责 Olist 这样一个电商平台的数据分析，你会怎么搭指标体系?**

前面的分析已经分别完成了大盘、漏斗、RFM、Cohort、品类、卖家、策略收益和推荐召回，但它们还是分散模块。指标体系的作用是把这些模块串成一张业务地图:

```text
平台是否健康
-> 哪个一级指标变了
-> 是哪个公式因子导致的
-> 下钻到时间 / 地域 / 品类 / 卖家 / 用户群
-> 输出策略和监控规则
```

这一步对纯 DA 岗尤其重要，因为真实工作里不是每天临时写一堆 SQL，而是先有指标树、口径、看板和异常归因框架。

---

## 二、业务逻辑

Olist 是 marketplace 模式，平台连接买家和卖家。一个健康的电商平台至少要同时回答四个问题:

| 问题 | 对应业务层 | 项目中已有证据 |
|---|---|---|
| 有没有成交规模 | 交易层 | GMV 1,584 万 BRL，订单 98,666 单 |
| 成交有没有顺利履约 | 履约层 | 平均履约 11.6 天，备货 2.32 天，配送 8.88 天 |
| 用户是否愿意回来 | 用户层 | 复购率 3.1%，次月留存 0.4%-0.7% |
| 供给是否健康 | 供给层 | 品类集中度、卖家健康分、office_furniture 卖家问题 |

因此指标体系不能只看 GMV。GMV 是结果指标，真正能指导动作的是它背后的诊断指标:

```text
GMV 下降
-> 订单量下降还是客单价下降
-> 用户数下降还是人均订单下降
-> 哪个州 / 品类 / 卖家贡献了下降
-> 是流量问题、转化问题、供给问题、履约问题还是评价问题
```

---

## 三、计算逻辑

### 3.1 北极星指标

建议北极星指标使用:

```text
有效 GMV = delivered 订单中商品价格 + 运费
```

为什么不是全量 GMV:

- `canceled` 和 `unavailable` 不代表真实成交。
- `created` / `processing` / `invoiced` / `shipped` 状态未完成履约。
- 项目大多数经营分析都基于 `delivered` 订单，更利于口径一致。

同时保留一个辅助北极星:

```text
有效成交订单数 = delivered 且存在 order_items 的订单数
```

为什么要保留订单数:

- GMV 可能被高客单价大件商品拉动。
- 订单数更能反映平台真实交易活跃度。
- GMV = 订单数 x 客单价，订单数是归因的第一拆解因子。

### 3.2 一级指标

一级指标回答“平台整体健康吗”。

| 一级指标 | 核心问题 | 代表指标 |
|---|---|---|
| 交易规模 | 平台卖得动吗 | GMV、订单量、买家数、AOV |
| 用户价值 | 用户会回来吗 | 复购率、Cohort 留存、LTV、RFM 分层 |
| 转化漏斗 | 订单有没有走完 | 付款率、发货率、送达率、取消率、缺货率 |
| 履约体验 | 等得久不久 | 付款耗时、备货耗时、配送耗时、准时率 |
| 评价体验 | 用户满意吗 | 平均评分、差评率、早评率、评分偏差 |
| 供给质量 | 卖家和品类健康吗 | 品类 GMV、卖家健康分、S 级卖家占比 |
| 增长效率 | 促销和拉新有效吗 | 新用户数、首单 ARPU、Cohort 首购 GMV |

### 3.3 二级公式拆解

GMV 的主公式:

```text
GMV = 订单量 x 客单价
    = 活跃购买用户数 x 人均订单数 x 客单价
    = 活跃购买用户数 x 人均订单数 x (商品均价 + 运费)
```

履约体验公式:

```text
总履约时长 = 付款耗时 + 备货耗时 + 配送耗时
```

用户价值公式:

```text
用户 LTV = 首单 GMV + 复购 GMV
复购率 = 下单次数 >= 2 的真实用户数 / 真实用户总数
```

卖家健康公式:

```text
卖家健康分 = GMV 分位 + 评分分位 + 备货时效分位 - 风险惩罚
风险惩罚 = 缺货惩罚 + 取消惩罚 + 差评惩罚
```

### 3.4 三级下钻路径

当指标异常时，按下面路径下钻:

| 下钻维度 | 用来回答 | 示例 |
|---|---|---|
| 时间 | 是长期趋势还是短期波动 | 月趋势、黑五峰值、狂欢节影响 |
| 地域 | 哪些州贡献变化 | SP/RJ/MG 等州 GMV、配送、评分 |
| 品类 | 哪些商品供给变化 | bed_bath_table、office_furniture |
| 卖家 | 是平台问题还是卖家问题 | office_furniture 70% 订单集中于单一卖家 |
| 用户 | 新老用户结构是否变化 | RFM、Cohort、首单品类 |
| 履约 | 是否由物流或备货拖累 | 备货 2.32 天、配送 8.88 天 |
| 评价 | 是否由评分偏差或真实体验导致 | 早评 8.63%，评分偏差 0.13 分 |

---

## 四、变量定义

| 指标 | 计算方式 | 口径 | 用途 |
|---|---|---|---|
| `gmv` | `SUM(price + freight_value)` | delivered + order_items | 北极星结果指标 |
| `order_count` | `COUNT(DISTINCT order_id)` | delivered + order_items | 交易规模 |
| `buyer_count` | `COUNT(DISTINCT customer_unique_id)` | delivered | 购买用户规模 |
| `aov` | `gmv / order_count` | delivered + order_items | 客单价 |
| `orders_per_buyer` | `order_count / buyer_count` | delivered | 人均订单数 |
| `payment_rate` | 有付款时间订单 / 全部订单 | orders 全量 | 漏斗第一层 |
| `shipping_rate` | 有发货时间订单 / 已付款订单 | orders 全量 | 漏斗第二层 |
| `delivery_rate` | 有送达时间订单 / 已发货订单 | orders 全量 | 漏斗第三层 |
| `approval_days` | 下单到付款 | delivered 或全量按场景 | 支付体验 |
| `processing_days` | 付款到发货 | delivered + 时间完整 | 卖家备货效率 |
| `shipping_days` | 发货到送达 | `v_orders_clean` + delivered | 物流体验 |
| `repeat_rate` | 购买 >= 2 次用户 / 总购买用户 | customer_unique_id | 用户留存 |
| `p1_retention` | cohort 次月复购用户 / cohort 用户 | delivered | 留存质量 |
| `avg_review_score` | `AVG(review_score)` | order_reviews | 用户满意度 |
| `bad_review_rate` | 评分 <= 2 的评价 / 总评价 | order_reviews | 体验风险 |
| `early_review_rate` | 收货前评价 / 总评价 | delivered + review | 评分偏差 |
| `seller_health_score` | GMV/评分/备货分位 - 惩罚 | active sellers | 供给治理 |
| `category_gmv_share` | 品类 GMV / 全站 GMV | delivered + category | 品类集中度 |

---

## 五、指标体系 SQL 模板

下面这段不是替代已有分析 SQL，而是后续看板和归因的统一口径模板。

```sql
USE Olist;

-- ============================================================
-- 指标体系基础宽表:月度经营核心指标
-- ============================================================
WITH delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date
    FROM v_orders_clean o
    JOIN customers c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
order_gmv AS (
    SELECT
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS gmv,
        SUM(oi.price) AS product_gmv,
        SUM(oi.freight_value) AS freight_gmv,
        COUNT(*) AS item_count
    FROM order_items oi
    GROUP BY oi.order_id
),
review_agg AS (
    SELECT
        order_id,
        AVG(review_score) AS avg_review_score,
        MAX(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS has_bad_review
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    d.month,
    ROUND(SUM(g.gmv), 2) AS gmv,
    COUNT(DISTINCT d.order_id) AS order_count,
    COUNT(DISTINCT d.customer_unique_id) AS buyer_count,
    ROUND(SUM(g.gmv) / NULLIF(COUNT(DISTINCT d.order_id), 0), 2) AS aov,
    ROUND(COUNT(DISTINCT d.order_id) / NULLIF(COUNT(DISTINCT d.customer_unique_id), 0), 3) AS orders_per_buyer,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, d.order_purchase_timestamp, d.order_approved_at)) / 24, 2) AS avg_approval_days,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, d.order_approved_at, d.order_delivered_carrier_date)) / 24, 2) AS avg_processing_days,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, d.order_delivered_carrier_date, d.order_delivered_customer_date)) / 24, 2) AS avg_shipping_days,
    ROUND(AVG(r.avg_review_score), 2) AS avg_review_score,
    ROUND(SUM(r.has_bad_review) * 100.0 / NULLIF(COUNT(r.order_id), 0), 2) AS bad_review_rate_pct
FROM delivered_orders d
JOIN order_gmv g
    ON d.order_id = g.order_id
LEFT JOIN review_agg r
    ON d.order_id = r.order_id
GROUP BY d.month
ORDER BY d.month;
```

关键语法说明:

- `v_orders_clean` 只排除时间异常，不自动过滤 `order_status`，所以必须额外写 `WHERE o.order_status = 'delivered'`。
- `order_gmv` 先按订单聚合，避免一单多商品导致订单数和 GMV 口径混乱。
- `review_agg` 先按订单聚合，避免一单多评放大 `order_items`。
- `NULLIF(分母, 0)` 防止除 0。
- 月度指标是后续 GMV 归因和看板监控的基础层。

---

## 六、常见坑位预警

| 坑 | 症状 | 原因 | 修正 | 面试讲法 |
|---|---|---|---|---|
| 把指标体系写成指标列表 | 只有 GMV、订单数、评分等散点 | 没有层级和归因路径 | 北极星 -> 一级 -> 二级公式 -> 三级下钻 | 指标体系是业务地图，不是指标清单 |
| GMV 口径混用 | 不同 SQL 的 GMV 对不上 | 有的用全量订单，有的用 delivered | 明确有效 GMV = delivered + order_items | 先定义口径再做分析 |
| 忘记 `v_orders_clean` 不过滤 status | shipped/canceled 混入履约指标 | 视图只排时间异常 | 加 `WHERE order_status = 'delivered'` | 清洗视图不是业务口径 |
| 一单多商品放大订单数 | 订单数虚高 | 直接 join order_items 后 count 行 | `COUNT(DISTINCT order_id)` | 明细表 join 后必须检查粒度 |
| 一单多评放大商品行 | 商品评分和价格被重复计算 | review 直接 join item 明细 | review 先按 order_id 聚合 | 先统一粒度，再 join |
| 只看 GMV 不看护栏指标 | GMV 上升但差评/取消上升 | 单指标优化有副作用 | 同时监控履约、差评、取消 | 北极星要配护栏指标 |

---

## 七、预期结果

完成这个模块后，项目表达应该从:

```text
我做了 GMV、漏斗、RFM、品类、卖家分析
```

升级为:

```text
我先搭了电商平台指标体系:
GMV 是北极星，订单量、AOV、用户数、人均订单数是拆解因子；
履约、评价、供给是护栏指标；
时间、地域、品类、卖家、用户是下钻维度。
后续所有分析都挂在这棵指标树上。
```

面试时应能清楚回答:

- 为什么北极星选 GMV，而不是评分或复购率。
- GMV 下降时如何归因。
- 为什么要给 GMV 配护栏指标。
- 如何从月度异常下钻到州、品类、卖家。
- 指标口径如何保证一致。

---

## 面试金句

```text
指标体系不是指标列表，而是一套从结果指标到过程指标、从公式拆解到维度下钻的业务诊断地图。
在 Olist 里，我用 GMV 作为北极星，但不会只看 GMV；我同时设置履约、评价、取消、缺货、卖家健康分作为护栏指标，避免平台为了短期 GMV 牺牲长期体验。
```

