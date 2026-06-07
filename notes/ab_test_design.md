# Olist AB 实验设计

> 模块定位:策略验证闭环  
> 目标:把前面分析得到的业务策略转成可验证的实验方案，体现 DA 岗对因果验证、核心指标和护栏指标的理解。

---

## 一、分析目的

前面的分析已经给出多个策略方向:

- 早评机制调整:收货前评价评分显著偏低，消除后平台评分约 +0.13。
- 卖家健康分:最大卖家不一定最好卖家，流量分配应兼顾体验。
- 缺货/取消治理:GMV 损失天花板约 20 万 BRL。
- 推荐召回:GlobalHot 适合冷启动，CategoryHot 只适合非冷启动用户。

但策略建议不能直接等于因果结论。AB 实验的作用是回答:

```text
如果真的上线这个策略，它是否让核心指标变好?
有没有伤害护栏指标?
效果是否足够大，值得长期保留?
```

---

## 二、业务逻辑

AB 实验应从前面的分析结论自然推出:

| 分析发现 | 策略假设 | 实验方向 |
|---|---|---|
| 早评 8.63%，早评评分 2.79 vs 正常 4.28 | 发货后邀请评价过早，会污染评分 | 评价邀请改为签收后发送 |
| 高 GMV 卖家不一定高体验 | 流量只按 GMV 分配会奖励差体验 | 高健康度卖家加权排序 |
| unavailable/canceled 造成约 20 万 BRL 损失 | 风险卖家或风险商品应被治理 | 缺货高风险供给降权 |
| 97.72% 用户冷启动 | 冷启动用户更适合热门/高质量供给 | 冷启动高质量热门推荐 |

---

## 三、计算逻辑

### 实验 1:评价邀请时机实验

实验假设:

```text
将评价邀请从"发货后"改为"签收后",可以减少用户等待中的愤怒评分，
提升评分信号质量，并降低早评率。
```

实验设计:

| 项目 | 设计 |
|---|---|
| 实验对象 | delivered 订单用户 |
| 控制组 | 维持发货后发送评价邀请 |
| 实验组 | 签收后发送评价邀请 |
| 核心指标 | 平均评分、差评率、早评率 |
| 护栏指标 | 评论提交率、评论延迟天数、客服投诉率 |
| 预期方向 | 早评率下降，平均评分上升，差评率下降 |

指标口径:

```text
early_review_rate = review_creation_date < order_delivered_customer_date 的评价数 / 总评价数
bad_review_rate = review_score <= 2 的评价数 / 总评价数
comment_submit_rate = 有评价订单数 / delivered 订单数
```

风险:

- 评价邀请延后可能导致评论量下降。
- 平均评分上升可能只是测量偏差消除，不代表真实体验改善。
- 因此必须同时看评论提交率和投诉率。

### 实验 2:高健康度卖家加权实验

实验假设:

```text
在搜索/推荐排序中给高 seller_health_score 卖家适度加权，
可以在不显著损害 GMV 的前提下提升评分、降低差评率和履约风险。
```

实验设计:

| 项目 | 设计 |
|---|---|
| 实验对象 | 有商品列表页或推荐位曝光的用户 |
| 控制组 | 原排序逻辑 |
| 实验组 | S/A 级卖家商品排序加权，D 级卖家轻度降权 |
| 核心指标 | GMV、CVR、订单量 |
| 护栏指标 | 平均评分、差评率、取消率、缺货率、供给覆盖率 |
| 预期方向 | 评分提升、差评率下降，GMV 不显著下降 |

关键点:

```text
不能只看 GMV。
如果实验组 GMV +2%，但差评率 +5%，说明策略伤害长期体验。
```

### 实验 3:缺货高风险供给降权实验

实验假设:

```text
对历史缺货/取消风险高的供给降低曝光，可以降低 unavailable 和 canceled，
减少无效交易损耗。
```

实验设计:

| 项目 | 设计 |
|---|---|
| 实验对象 | 高风险品类或高风险卖家相关商品流量 |
| 控制组 | 原流量分配 |
| 实验组 | 高风险供给降权，优先展示健康卖家 |
| 核心指标 | unavailable 率、canceled 率 |
| 护栏指标 | GMV、订单量、卖家覆盖率、商品覆盖率 |
| 预期方向 | 缺货/取消下降，GMV 不显著下降 |

数据限制:

- Olist 中 609 单 unavailable 有 603 单无 `order_items`，无法精确归因到卖家。
- 因此真实线上实验前，必须先完善缺货订单到商品/卖家的数据链路。

### 实验 4:冷启动高质量热门推荐实验

实验假设:

```text
对冷启动用户，用高评分、低差评、履约稳定的热门商品替代纯销量热门，
可以提升新用户首单体验。
```

实验设计:

| 项目 | 设计 |
|---|---|
| 实验对象 | 新用户 / 无历史购买用户 |
| 控制组 | GlobalHot |
| 实验组 | QualityGlobalHot = 热门 + 评分 + 履约 + 卖家健康过滤 |
| 核心指标 | CVR、首单 GMV |
| 护栏指标 | 首单评分、差评率、取消率、配送时长 |
| 预期方向 | CVR 不下降，首单评分提升 |

为什么这个实验重要:

- 推荐 baseline 显示 97.72% 验证期用户是冷启动。
- ItemCF 在 Olist 上完全失效。
- 因此冷启动推荐策略比复杂协同过滤更有业务价值。

---

## 四、变量定义

| 指标 | 含义 | 类型 |
|---|---|---|
| `gmv` | 实验期间有效成交金额 | 核心指标 |
| `cvr` | 点击/访问后成交转化率 | 核心指标 |
| `order_count` | 有效成交订单数 | 核心指标 |
| `avg_review_score` | 平均评分 | 体验指标 |
| `bad_review_rate` | 评分 <= 2 的比例 | 护栏指标 |
| `early_review_rate` | 收货前评价比例 | 核心/诊断指标 |
| `comment_submit_rate` | 有评价订单 / delivered 订单 | 护栏指标 |
| `cancel_rate` | canceled / 全部订单 | 护栏指标 |
| `unavailable_rate` | unavailable / 全部订单 | 护栏指标 |
| `late_delivery_rate` | 实际送达晚于预计送达 | 护栏指标 |
| `seller_coverage` | 被曝光/成交卖家数 | 供给多样性护栏 |
| `product_coverage` | 被曝光/成交商品数 | 供给多样性护栏 |

---

## 五、实验分析 SQL 模板

真实 AB 实验需要线上埋点表。Olist 没有实验分组表，下面是上线后应有的数据结构和分析模板。

```sql
-- 假设线上有 experiment_assignment 表:
-- user_id, experiment_name, group_name, assigned_at

WITH exp_users AS (
    SELECT
        user_id,
        group_name
    FROM experiment_assignment
    WHERE experiment_name = 'review_invite_after_delivery'
),
order_metrics AS (
    SELECT
        e.group_name,
        o.order_id,
        c.customer_unique_id AS user_id,
        SUM(oi.price + oi.freight_value) AS gmv,
        AVG(r.review_score) AS avg_review_score,
        MAX(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS has_bad_review,
        MAX(CASE
            WHEN r.review_creation_date < o.order_delivered_customer_date THEN 1
            ELSE 0
        END) AS has_early_review
    FROM exp_users e
    JOIN customers c
        ON e.user_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    LEFT JOIN order_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY e.group_name, o.order_id, c.customer_unique_id
)
SELECT
    group_name,
    COUNT(DISTINCT user_id) AS users,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(gmv), 2) AS gmv,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score,
    ROUND(SUM(has_bad_review) * 100.0 / NULLIF(COUNT(order_id), 0), 2) AS bad_review_rate_pct,
    ROUND(SUM(has_early_review) * 100.0 / NULLIF(COUNT(order_id), 0), 2) AS early_review_rate_pct
FROM order_metrics
GROUP BY group_name;
```

关键说明:

- Olist 离线数据没有曝光、点击、实验分组，因此不能真实计算 CVR。
- 本项目中的 AB 设计是实验方案设计，不是伪造实验结果。
- 面试时必须主动说明这个边界。

---

## 六、常见坑位预警

| 坑 | 症状 | 原因 | 修正 | 面试讲法 |
|---|---|---|---|---|
| 把相关性说成因果 | "评分高所以 GMV 高" | 没有随机实验 | 用 AB 验证 | 分析发现是假设，AB 才是因果验证 |
| 只看核心指标 | GMV 上升但差评也上升 | 缺少护栏指标 | 配置体验/供给护栏 | 实验不能牺牲长期体验 |
| 样本污染 | 用户同时进入多个实验 | 实验互相干扰 | 分层互斥或正交实验 | 实验设计要控制干扰 |
| 实验周期过短 | 评分/复购没来得及发生 | 指标滞后 | 按指标周期设实验时长 | 不同指标有不同成熟期 |
| 忽略冷启动结构 | ItemCF 实验覆盖不到用户 | 97.72% 用户冷启动 | 单独设计冷启动实验 | 不是所有用户都适合同一种策略 |
| 编造 Olist AB 结果 | 离线数据无实验分组 | 数据边界不支持 | 只做方案设计 | 承认数据边界是专业表现 |

---

## 七、预期结果

完成 AB 实验设计后，项目逻辑闭环为:

```text
数据质量
-> 业务分析发现问题
-> 指标体系定义口径
-> 策略收益估算优先级
-> AB 实验验证因果
-> 看板监控上线效果
```

面试中可以这样收束:

```text
我不会把离线分析结论直接当成上线策略。
比如早评机制调整能让评分理论上 +0.13，但这只是消除测量偏差，
是否影响 CVR 和评论量必须通过 AB 实验验证。
所以我为每个策略都设计了核心指标和护栏指标。
```

---

## 面试金句

```text
分析给出的是假设，AB 实验验证的是因果。
一个策略能不能上线，不只看核心指标是否提升，
还要看护栏指标是否被伤害。尤其在电商里，GMV、体验、供给覆盖率必须同时看。
```

