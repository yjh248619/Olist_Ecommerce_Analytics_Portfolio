# Olist 电商平台交易增长与供给治理分析

基于 Kaggle 的 Brazilian E-Commerce Public Dataset by Olist，构建一个从数据质量治理、交易漏斗诊断、用户生命周期、品类与卖家经营，到推荐召回原型和 AB 实验设计的完整电商数据分析项目。

> 这是一个面向数据分析 / 商业分析 / 电商策略分析岗位的作品集项目。项目重点不是单纯 EDA，而是模拟平台数据分析师如何从可信数据出发，定位增长与体验问题，并把分析结论落到策略、看板、实验和推荐召回原型。

## 快速入口

| 入口 | 适合场景 |
|---|---|
| [1 页 PDF 作品集](docs/olist_one_page_portfolio.pdf) | 快速了解项目背景、方法、发现和业务价值 |
| [完整项目叙事稿](notes/project_narrative.md) | 面试中 15-20 分钟讲项目 |
| [模拟面试稿](notes/mock_interview_da_to_reco.md) | 从业务大盘讲到推荐系统 |
| [不同公司简历项目段](notes/resume_project_variants_da.md) | 淘宝 / 京东 / 拼多多 / Shopee 等岗位投递 |
| [推荐召回笔记](notes/reco_notes.md) | GlobalHot / CategoryHot / ItemCF / HybridRecall 评估 |

## 项目一页摘要

| 模块 | 业务问题 | 方法与产出 |
|---|---|---|
| 数据质量治理 | 分析前数据是否可信 | MySQL 建模、LOAD DATA 导入、外键完整性检查、异常视图 |
| 交易增长诊断 | GMV 增长来自哪里 | 订单量 × AOV 拆解、黑五增长归因、漏斗损耗识别 |
| 用户生命周期 | Olist 是留存型还是获取型业务 | RFM、Cohort、LTV，识别低复购与高冷启动特征 |
| 品类与卖家治理 | 哪些供给带来 GMV 与体验风险 | 品类钻取、卖家健康分、低评分慢履约卖家定位 |
| 地域与 VOC | 低评分背后的真实原因是什么 | 州维度履约分析、评论关键词规则、物流投诉归因 |
| 推荐召回原型 | 冷启动场景下如何做推荐 baseline | GlobalHot、CategoryHot、ItemCF、HybridRecall 离线评估 |
| DA 专项交付 | 如何把分析变成业务动作 | 指标体系、看板设计、AB 实验方案、策略收益估算 |

项目定位不是普通 EDA，而是模拟电商平台数据分析师的真实工作流:

```text
数据可信
-> 业务大盘
-> 用户与供给诊断
-> 策略收益估算
-> 推荐召回原型
-> 指标体系 / 看板 / AB 实验
```

## 技术栈

| 类型 | 工具 |
|---|---|
| 数据库 | MySQL 8.0 |
| 数据导入 | LOAD DATA INFILE, Python pandas |
| 分析语言 | SQL, Python |
| 推荐评估 | Recall@K, NDCG@K, Coverage |
| 文档 | Markdown |

## 数据集

数据包含 9 张表，约 150 万行:

原始 CSV 不纳入本仓库。复现时请从 Kaggle 下载 `Brazilian E-Commerce Public Dataset by Olist`，并放到 MySQL `secure_file_priv` 允许读取的本机目录。

| 表 | 含义 |
|---|---|
| customers | 客户表，`customer_unique_id` 表示真实用户 |
| orders | 订单状态与关键时间 |
| order_items | 订单商品明细 |
| order_payments | 支付记录 |
| order_reviews | 用户评价 |
| products | 商品维度 |
| sellers | 卖家维度 |
| geolocation | 邮编经纬度 |
| product_category_name_translation | 品类葡英翻译 |

## 项目结构

```text
Olist_Ecommerce_Analytics_Portfolio/
├── sql/                          建表、导入、质量检查、业务分析与 DA 专项 SQL
├── scripts/                      Python ETL 与推荐 baseline
├── notes/                        分析报告、路线图、指标体系、看板与实验设计
├── docs/                         1 页作品集 PDF 与 HTML
├── .env.example                  本地复现所需环境变量模板
├── requirements.txt              Python 依赖
├── 面试回答.md                    项目面试 Q&A
└── README.md                     项目入口
```

## 核心发现

### 数据质量

- `LOAD DATA` 曾出现"行数正确但时间字段全 NULL"的假成功问题，根因是 `SET` 子句前多了分号。
- `order_reviews` 评论字段含换行，改用 pandas 导入，最终 99,224 行零丢失。
- 13 条商品品类引用缺失只涉及 2 个未翻译类别，采用补维度而不是删事实。
- 23 条送达早于发货的时间异常通过 `v_orders_clean` 视图排除。
- 8 单 `delivered` 但无送达时间，钻取发现物流回调批量丢失迹象。

### 交易与履约

- 总 GMV 约 1,584 万 BRL。
- 有效订单约 98,666 单，客单价约 160.58 BRL。
- 平均履约约 11.6 天，其中备货 2.32 天、配送 8.88 天。
- 物流耗时是最大时长来源，但备货是平台更可控的优化点。
- 2017-11 黑五 GMV 环比 +53.55%，订单量环比 +62.77%，AOV 环比 -5.66%，属于典型促销拉新驱动增长。

### 地域与 VOC

- SP 单州贡献 37.41% GMV，是核心健康市场；RJ、RS、BA 是高价值待治理市场。
- 跨州订单平均配送 11.69 天，同州订单 4.73 天，跨州是履约体验的主要风险来源。
- 差评文本中物流配送问题占 21.98%，未收到货占 16.96%，两者合计 38.94%。
- 21 天以上订单的物流投诉占比 33.12%，约为 <7 天订单的 2.7 倍。

### 用户生命周期

- 真实用户数约 96,096。
- 复购率约 3.1%，96.9% 用户只购买一次。
- Cohort 次月留存约 0.4%-0.7%。
- 17 个月 LTV 增幅仅 3%-5%，首单贡献用户价值的绝大部分。

### 品类与卖家

- Top 5 品类贡献约 39.24% GMV，Top 10 贡献约 62.19%。
- `bed_bath_table` 是最大流量入口之一，但评分和差评率显示体验压力。
- `office_furniture` 表面是品类问题，钻取后发现 70% 订单集中在一个低评分慢履约卖家。
- 最大卖家不等于最好卖家，卖家健康分能揭示 GMV 排名掩盖的体验风险。

### 策略收益

- canceled 与 unavailable 造成的 GMV 损失天花板约 20 万 BRL。
- unavailable 609 单中 603 单无 `order_items`，无法精确归因到卖家，已主动标注数据限制。
- 早评机制导致评分偏差，消除后平台评分理论上约 +0.13。

### 推荐召回

- 验证期用户冷启动率 97.72%，商品冷启动率 60.48%。
- ItemCF 在该数据集上完全失效，过滤后相似商品对仅 422 对，Recall@K 为 0。
- GlobalHot 是最强 baseline，all_targets Recall@50 = 3.73%，warm_targets Recall@50 = 6.49%。
- HybridRecall 进一步把策略落地为“冷启动 GlobalHot，非冷启动 CategoryHot + GlobalHot 补足”，warm_targets Recall@50 = 6.54%。
- 在非冷启动 warm 用户上，HybridRecall Recall@50 = 6.57%，高于 GlobalHot 的 4.78%。
- 项目结论:Olist 更适合冷启动热门/品类/高质量供给召回，而不是强依赖协同过滤。

## 重要文档

| 文件 | 内容 |
|---|---|
| [notes/project_roadmap.md](notes/project_roadmap.md) | 项目路线图与剩余任务 |
| [notes/data_quality_report.md](notes/data_quality_report.md) | 完整分析记录 |
| [notes/metrics_framework.md](notes/metrics_framework.md) | 电商指标体系 |
| [notes/dashboard_design.md](notes/dashboard_design.md) | 看板与监控设计 |
| [notes/ab_test_design.md](notes/ab_test_design.md) | AB 实验设计 |
| [notes/reco_notes.md](notes/reco_notes.md) | 推荐召回原型与 Hybrid baseline |
| [notes/project_narrative.md](notes/project_narrative.md) | 15-20 分钟项目面试叙事稿 |
| [notes/project_flow.md](notes/project_flow.md) | 项目流程图 |
| [notes/mock_interview_da_to_reco.md](notes/mock_interview_da_to_reco.md) | 从大盘到推荐的完整模拟面试 |
| [notes/resume_project_variants_da.md](notes/resume_project_variants_da.md) | 淘宝/京东/拼多多/Shopee 等简历项目段 |
| [docs/olist_one_page_portfolio.pdf](docs/olist_one_page_portfolio.pdf) | 1 页 PDF 作品集 |
| [docs/olist_one_page_portfolio.html](docs/olist_one_page_portfolio.html) | 作品集 HTML 源文件 |
| [notes/15_analysis_gmv_attribution_results.txt](notes/15_analysis_gmv_attribution_results.txt) | GMV 归因结果 |
| [notes/45_analysis_geo_market_results.txt](notes/45_analysis_geo_market_results.txt) | 地域经营结果 |
| [notes/55_analysis_review_voc_results.txt](notes/55_analysis_review_voc_results.txt) | VOC 分析结果 |
| [面试回答.md](面试回答.md) | 16 个 Part 的面试 Q&A |

## 如何复现

1. 在 MySQL 中创建数据库 `Olist`。
2. 执行 `sql/01_schema.sql` 创建 9 张表。
3. 将 CSV 复制到 MySQL `secure_file_priv` 允许的目录，并把 `sql/02_load_data.sql` 中的 `C:/path/to/mysql_uploads/` 替换为你的本机路径。
4. 执行 `sql/02_load_data.sql` 导入 8 张规整表。
5. 复制 `.env.example` 为 `.env`，填写 MySQL 密码和 `ORDER_REVIEWS_CSV` 路径。
6. 执行 `pip install -r requirements.txt` 安装依赖。
7. 执行 `scripts/import_reviews.py` 导入 `order_reviews`。
8. 执行 `sql/04_data_quality.sql` 做质量检查。
9. 执行 `sql/05_fix_translation.sql` 和 `sql/06_fix_anomalies.sql` 修复维度和异常。
10. 执行 `sql/03_add_constraints.sql` 添加外键。
11. 依次执行业务分析 SQL 和推荐数据集 SQL。
12. 执行 `scripts/reco_baseline.py` 评估推荐召回 baseline。

## 面试亮点

- 不是直接 EDA，而是先做数据质量治理，能讲清楚 LOAD DATA 假成功、脏文本导入、维度补全和异常视图。
- RFM 没有机械套 `NTILE`，而是识别低复购场景下 F 维度失效，改用业务阈值。
- Cohort 与 RFM 交叉验证，得出 Olist 是获取型业务而非留存型业务。
- 品类分析中通过钻取推翻初始假设，证明 `office_furniture` 不是品类天然差，而是单卖家流量集中导致。
- 推荐系统主动说明数据边界:无曝光/点击，只能做购买行为召回原型。
- 推荐 baseline 不停在 ItemCF 失败，而是进一步提出 HybridRecall，把冷启动与非冷启动用户分流处理。
- DA 专项补足指标体系、GMV 归因、地域分析、看板监控和 AB 实验设计。

## 项目结论

Olist 的核心问题不是单一指标低，而是平台商业模式呈现明显的"低复购、高冷启动、长尾供给、履约体验影响评分"特征。

因此更合理的业务策略是:

- 拉新和首单体验优先于复杂复购运营。
- 对高 GMV 但低体验的品类和卖家做治理。
- 对评价邀请时机做 AB 实验，减少早评偏差。
- 推荐系统优先做 HybridRecall 和冷启动热门兜底，而不是死磕 ItemCF。
