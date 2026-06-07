# Olist 数据分析看板与监控设计

> 模块定位:纯数据分析岗专项补充  
> 目标:把指标体系转成业务方每天/每周可用的看板、预警规则和复盘模板。

---

## 一、分析目的

本模块回答数据分析岗常见问题:

**如果让你给 Olist 设计 BI 看板，你会放哪些指标，怎么监控异常，怎么帮助业务定位问题?**

看板不是把所有图堆在一起。好的看板要做到:

```text
3 秒判断平台是否健康
1 分钟定位异常发生在哪个模块
5 分钟下钻到可行动对象
```

在本项目中，看板承接 `notes/metrics_framework.md` 的指标体系，并服务后续 `notes/ab_test_design.md` 的实验监控。

---

## 二、业务逻辑

Olist 的核心业务链路是:

```text
用户下单 -> 付款 -> 卖家备货 -> 物流配送 -> 用户评价 -> 复购或流失
```

因此看板不应只有 GMV，而应覆盖四类业务视角:

| 看板 | 回答问题 | 使用者 |
|---|---|---|
| 经营总览看板 | 今天/本周平台整体健康吗 | 业务负责人、数据分析师 |
| 履约体验看板 | 订单卡在哪个履约环节 | 物流/履约团队、卖家运营 |
| 品类经营看板 | 哪些品类值得推、哪些需要治理 | 品类运营、活动运营 |
| 卖家健康看板 | 哪些卖家该奖励或治理 | 卖家运营、平台治理 |

---

## 三、计算逻辑

### 3.1 经营总览看板

核心指标:

| 指标 | 计算口径 | 展示方式 |
|---|---|---|
| GMV | delivered 订单 `SUM(price + freight_value)` | KPI 卡 + 月趋势 |
| 订单量 | delivered 订单数 | KPI 卡 + 月趋势 |
| 购买用户数 | `COUNT(DISTINCT customer_unique_id)` | KPI 卡 |
| AOV | GMV / 订单量 | KPI 卡 |
| 人均订单数 | 订单量 / 购买用户数 | KPI 卡 |
| 复购率 | 下单 >= 2 次用户 / 总用户 | 趋势 + 分层 |

推荐视图:

```text
顶部: GMV / 订单量 / AOV / 买家数 / 复购率
中部: 月度 GMV 趋势 + GMV 环比归因
底部: Top 州 / Top 品类 / Top 卖家贡献
```

### 3.2 履约体验看板

核心指标:

| 指标 | 计算口径 | 业务含义 |
|---|---|---|
| 付款耗时 | 下单到付款 | 支付摩擦 |
| 备货耗时 | 付款到发货 | 卖家效率 |
| 配送耗时 | 发货到送达 | 物流效率 |
| 总履约时长 | 下单到送达 | 用户等待体验 |
| 延迟送达率 | 实际送达 > 预计送达 | SLA 风险 |
| 缺货率 | unavailable / 全量订单 | 供给风险 |
| 取消率 | canceled / 全量订单 | 交易损耗 |

推荐视图:

```text
履约漏斗: 下单 -> 付款 -> 发货 -> 送达
耗时拆解: 付款/备货/配送堆叠图
异常列表: 慢履约州、慢履约品类、慢履约卖家
```

### 3.3 品类经营看板

核心指标:

| 指标 | 计算口径 | 用途 |
|---|---|---|
| 品类 GMV | 按英文品类聚合 | 找核心品类 |
| 品类订单量 | `COUNT(DISTINCT order_id)` | 看交易规模 |
| 品类 AOV | GMV / 订单量 | 看价格带 |
| 品类评分 | 订单评分近似 | 看体验 |
| 差评率 | review_score <= 2 | 找治理对象 |
| 履约时长 | 下单到送达 | 找物流痛点 |
| 首单用户数 | 首购品类用户数 | 看流量入口 |
| 同品类复购率 | 首单后再次购买同品类 | 看推荐潜力 |

推荐视图:

```text
品类矩阵:
X 轴 = GMV
Y 轴 = 平均评分
气泡大小 = 订单量
颜色 = 履约时长

四象限:
高 GMV 高评分 -> 推荐优先
高 GMV 低评分 -> 治理优先
低 GMV 高评分 -> 潜力品类
低 GMV 低评分 -> 常规观察
```

### 3.4 卖家健康看板

核心指标:

| 指标 | 计算口径 | 用途 |
|---|---|---|
| seller_health_score | GMV/评分/备货分位 - 惩罚 | 卖家分层 |
| S/A/B/C/D 卖家数 | 按健康分分档 | 看供给结构 |
| 卖家 GMV | 卖家维度聚合 | 找核心供给 |
| 卖家评分 | 订单评分聚合 | 看体验 |
| 差评率 | review_score <= 2 | 风险监控 |
| 备货时长 | 付款到发货 | 卖家 SLA |
| 缺货率 | unavailable 相关 | 供给稳定性 |
| 取消率 | canceled 相关 | 履约风险 |

推荐视图:

```text
顶部: S/A/B/C/D 卖家分布
中部: GMV Top 卖家 vs 健康分 Top 卖家对比
底部: 风险卖家列表 + 治理建议
```

---

## 四、变量定义

| 变量 | 含义 | 刷新频率 | 预警方向 |
|---|---|---|---|
| `gmv` | 有效成交金额 | 日/周/月 | 下降预警 |
| `order_count` | 有效订单数 | 日/周/月 | 下降预警 |
| `aov` | 客单价 | 日/周/月 | 异常升降 |
| `buyer_count` | 购买用户数 | 日/周/月 | 下降预警 |
| `payment_rate` | 付款转化率 | 日 | 下降预警 |
| `shipping_rate` | 发货转化率 | 日 | 下降预警 |
| `delivery_rate` | 送达转化率 | 日 | 下降预警 |
| `processing_days` | 备货耗时 | 日/周 | 上升预警 |
| `shipping_days` | 配送耗时 | 日/周 | 上升预警 |
| `late_delivery_rate` | 延迟送达率 | 日/周 | 上升预警 |
| `bad_review_rate` | 差评率 | 周 | 上升预警 |
| `early_review_rate` | 早评率 | 周 | 上升预警 |
| `seller_health_score` | 卖家健康分 | 周 | 下降预警 |

---

## 五、看板 SQL 模板

### 5.1 日级经营监控

```sql
USE Olist;

SELECT
    DATE(o.order_purchase_timestamp) AS dt,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
    COUNT(DISTINCT o.order_id) AS order_count,
    COUNT(DISTINCT c.customer_unique_id) AS buyer_count,
    ROUND(SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov
FROM v_orders_clean o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE(o.order_purchase_timestamp)
ORDER BY dt;
```

### 5.2 异常预警规则样例

```sql
WITH daily_metrics AS (
    SELECT
        DATE(o.order_purchase_timestamp) AS dt,
        SUM(oi.price + oi.freight_value) AS gmv,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM v_orders_clean o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE(o.order_purchase_timestamp)
),
with_lag AS (
    SELECT
        dt,
        gmv,
        order_count,
        LAG(gmv, 7) OVER (ORDER BY dt) AS gmv_7d_ago
    FROM daily_metrics
)
SELECT
    dt,
    ROUND(gmv, 2) AS gmv,
    ROUND(gmv_7d_ago, 2) AS gmv_7d_ago,
    ROUND((gmv - gmv_7d_ago) * 100.0 / NULLIF(gmv_7d_ago, 0), 2) AS wow_pct,
    CASE
        WHEN (gmv - gmv_7d_ago) / NULLIF(gmv_7d_ago, 0) <= -0.1 THEN 'GMV 周同比下降超 10%,需排查'
        ELSE '正常'
    END AS alert_flag
FROM with_lag
WHERE gmv_7d_ago IS NOT NULL
ORDER BY dt;
```

---

## 六、常见坑位预警

| 坑 | 症状 | 原因 | 修正 | 面试讲法 |
|---|---|---|---|---|
| 看板只放结果指标 | GMV 变了但不知道为什么 | 没有过程指标 | GMV + 漏斗 + 履约 + 评价 + 供给 | 看板要能定位原因 |
| 图表太多 | 业务方不知道先看哪个 | 没有分层 | KPI 卡 -> 趋势 -> 下钻表 | 看板是决策界面不是数据仓库 |
| 没有预警规则 | 异常只能靠人肉发现 | 缺少阈值 | 环比/同比/P90/均值倍数 | 预警是自动化的数据分析 |
| 只看均值 | 极端卖家或州被掩盖 | 分布长尾 | 增加 P90、Top/Bottom 列表 | 平均值只能看整体，不能做治理 |
| 没有护栏指标 | GMV 提升但体验变差 | 单指标优化 | 配置取消率、差评率、履约时长 | 好看板要防止业务副作用 |

---

## 七、预期结果

看板设计完成后，面试表达应升级为:

```text
我不是只做了一次性分析，而是把分析结果沉淀成了四类看板:
经营总览看 GMV 和用户规模，履约看板定位订单卡点，
品类看板支持选品和治理，卖家看板支持供给分层。
每个看板都有核心指标、下钻维度和异常预警规则。
```

---

## 日报模板

```text
Olist 日报 YYYY-MM-DD

1. 核心经营
- GMV:
- 订单量:
- AOV:
- 购买用户数:

2. 主要波动
- GMV 环比/周同比:
- 订单量变化:
- AOV 变化:

3. 异常预警
- 履约异常:
- 差评异常:
- 品类异常:
- 卖家异常:

4. 归因结论
- 主要由哪个指标驱动:
- 主要影响州/品类/卖家:

5. 建议动作
- 今日需要业务跟进:
- 后续观察指标:
```

---

## 面试金句

```text
看板不是图表集合，而是业务诊断界面。
我设计看板时会先放北极星指标，再放过程指标和护栏指标，
最后配置异常预警和下钻路径，确保业务方不只是看到数字变化，
还能知道下一步该找谁、查哪里、做什么。
```

