# Olist 项目简历项目段公司定制版

> 用途: 针对不同电商公司 DA 岗投递时替换简历项目描述  
> 建议: 简历正文使用 3-5 条 bullet；面试时再展开项目叙事  
> 版本: 2026-06-07

## 0. 通用简历版

**Olist 电商交易增长与供给治理分析 | MySQL, Python, pandas, 推荐召回评估**

- 基于 Olist 巴西电商 9 张核心业务表，完成 MySQL 建表、`LOAD DATA` 导入、主外键约束、数据质量检查与清洗视图建设，修复评论换行、时间异常、品类翻译缺失等问题，保证 GMV/漏斗/推荐样本口径可信。
- 构建电商经营指标体系，围绕 GMV、订单量、AOV、购买用户数、履约时长、评分、差评率等指标完成交易大盘与归因分析；识别 2017-11 黑五 GMV 环比 +53.55% 主要由订单量 +62.77% 驱动。
- 通过 RFM、Cohort、LTV 分析发现平台复购率仅 3.1%、次月留存 0.4%-0.7%，判断 Olist 属于低复购/首单驱动业务，策略重点应放在首单体验与冷启动承接。
- 从品类和卖家维度定位供给问题，发现 `office_furniture` 低评分并非品类天然问题，而是 70% 订单集中在单一低评分慢履约卖家，提出卖家健康分、流量加权和供给治理策略。
- 基于购买行为构建离线推荐召回原型，实现 GlobalHot、CategoryHot、ItemCF、HybridRecall；验证用户冷启动率 97.72%，ItemCF 失效，HybridRecall 在非冷启动 warm 用户 Recall@50 达 6.57%。

## 1. 淘宝 / 天猫 DA 岗版本

**侧重点: 平台指标体系、用户增长、品类运营、推荐召回、AB 实验**

**Olist 电商增长与推荐召回分析 | MySQL, Python, 指标体系, AB 实验设计**

- 搭建电商交易指标体系，将 GMV 拆解为 `购买用户数 × 人均订单数 × AOV`，并设计时间、品类、卖家、地域、用户分层等下钻路径，支持经营异常定位。
- 对黑五促销进行 GMV 波动归因，发现 2017-11 GMV 环比 +53.55%，订单量环比 +62.77%，AOV 环比 -5.66%，判断增长主要来自促销拉新而非客单提升。
- 结合 RFM 与 Cohort 分析识别低复购业务特征:复购率 3.1%、次月留存 0.4%-0.7%、LTV 增幅仅 3%-5%，提出首单体验治理和冷启动流量承接策略。
- 从品类和卖家侧定位供给质量问题，识别 Top 10 品类贡献 62.19% GMV，并发现 `office_furniture` 的体验问题源于单一低健康卖家集中供给，提出卖家健康分接入流量分配。
- 构建购买行为推荐召回原型，实现 GlobalHot、CategoryHot、ItemCF 与 HybridRecall；验证用户冷启动率 97.72%，HybridRecall 比单纯热门更适合冷启动/轻个性化混合场景。

**淘宝面试时主打表达:**

```text
我不是只看 GMV，而是从 GMV 拆解、品类运营、卖家健康、推荐召回和 AB 实验完整闭环来做平台增长诊断。
```

## 2. 京东 DA 岗版本

**侧重点: 履约体验、供应链/卖家治理、地域物流、用户评价**

**Olist 电商履约体验与供给治理分析 | MySQL, Python, 地域分析, VOC**

- 基于订单、商品、卖家、评价和地域数据构建电商履约分析口径，识别平均总履约 11.6 天，其中备货 2.32 天、配送 8.88 天，判断备货时效是平台更可控的优化点。
- 按州分析 GMV、履约和评分，发现 SP 贡献 37.41% GMV 且为核心健康市场；RJ、RS、BA 属于高 GMV 但履约/评分待治理市场。
- 对同州与跨州订单进行供需匹配分析，发现跨州订单平均配送 11.69 天、同州 4.73 天，跨州 AOV 更高但延迟率更高，定位高价值高风险物流链路。
- 构建卖家健康分体系，综合 GMV、评分、备货时效、差评率和缺货/取消惩罚，发现最大卖家不等于最好卖家，支持供给分层治理和流量分配。
- 通过 VOC 关键词规则分析差评文本，发现物流配送问题 21.98%、未收到货 16.96%，21 天以上订单物流投诉占比 33.12%，验证履约体验对评分的影响。

**京东面试时主打表达:**

```text
我会把履约体验拆成备货、配送、跨州线路和卖家供给责任，而不是只报一个平均配送时长。
```

## 3. 拼多多 DA 岗版本

**侧重点: 促销增长、转化效率、低复购/拉新、供给性价比、策略收益**

**Olist 促销增长归因与供给效率分析 | MySQL, Python, GMV 归因, 策略收益**

- 对平台 GMV 进行公式拆解与环比归因，识别 2017-11 黑五 GMV 环比 +53.55% 由订单量 +62.77% 驱动，同时 AOV -5.66%，判断促销增长主要来自拉新放量。
- 通过 RFM/Cohort 发现平台复购率仅 3.1%、次月留存 0.4%-0.7%，说明业务更依赖首单转化和拉新效率，而非高频复购。
- 对品类集中度与首单体验进行分析，识别 Top 5 品类贡献 39.24% GMV、Top 10 贡献 62.19%，支持活动选品和流量优先级判断。
- 估算 canceled 与 unavailable 带来的 GMV 损失天花板约 20 万 BRL，并主动标注 unavailable 订单缺少商品/卖家明细导致归因受限，体现数据边界意识。
- 设计冷启动热门召回与高质量供给实验方案，核心指标关注 CVR、首单 GMV，护栏指标关注差评率、配送时长和商品覆盖率，避免只追短期成交。

**拼多多面试时主打表达:**

```text
我会先判断增长是量驱动还是价驱动，再评估促销拉新后的留存、履约和供给风险，避免只看短期 GMV。
```

## 4. Shopee DA 岗版本

**侧重点: 跨区域经营、卖家生态、物流体验、本地化市场、冷启动推荐**

**Olist 跨区域电商经营与卖家生态分析 | MySQL, Python, Geo, VOC, Recall**

- 基于巴西多州交易数据构建地域经营分析，识别 SP 为核心健康市场，RJ/RS/BA 为高价值待治理市场，支持不同区域的运营优先级划分。
- 对跨州与同州订单进行履约差异分析，发现跨州订单配送 11.69 天，同州 4.73 天；跨州 AOV 更高但延迟率更高，说明跨区域订单存在“高价值高体验风险”。
- 结合 VOC 评论文本和履约时长分析，发现差评中物流配送问题与未收到货合计 38.94%，21 天以上订单物流投诉占比 33.12%，支撑区域物流治理策略。
- 构建卖家健康分与品类治理框架，识别 `office_furniture` 体验问题来自单一卖家集中供给，而非品类天然问题，提出平台型卖家分层与流量治理方案。
- 构建冷启动推荐召回 baseline，验证用户冷启动率 97.72%，HybridRecall 通过热门兜底 + 历史品类轻个性化提升 warm 用户召回表现，适合跨区域平台新用户承接。

**Shopee 面试时主打表达:**

```text
这个项目本质上是跨区域 marketplace 经营分析，我重点看地区、卖家、物流和新用户冷启动，而不是只做单市场 GMV 报表。
```

## 5. 美团 / 本地生活 DA 岗迁移版

**侧重点: 履约体验、商家治理、用户评价、区域运营**

**Olist 平台履约与商家健康度分析 | MySQL, Python, 商家分层, VOC**

- 构建订单履约链路分析，将交易过程拆解为付款、备货、配送、评价等环节，识别履约时长和评价偏差对用户体验的影响。
- 设计卖家健康分体系，综合成交规模、评分、差评率、备货时效、取消/缺货惩罚，支持商家分层、流量加权和治理优先级判断。
- 通过地域分析识别高价值但体验待治理市场，发现跨区域配送时长显著高于同区域订单，为区域运营和履约资源配置提供依据。
- 使用 VOC 关键词规则将低分评论拆解为物流、未收到货、质量、退款客服等原因，推动从“评分低”定位到“责任环节和动作”。

**美团面试时主打表达:**

```text
我会把商家、履约、评价放在同一套健康度框架里看，目标不是只提升成交，而是提升可持续交易质量。
```

## 6. Amazon / 跨境电商 DA 岗英文简历版

**Olist Marketplace Growth & Supply Quality Analytics | MySQL, Python, pandas**

- Built an end-to-end e-commerce analytics project on 9 Olist marketplace tables, covering schema design, data ingestion, data quality validation, anomaly handling, and clean analytical views.
- Decomposed GMV into order volume and AOV; identified that the Nov-2017 Black Friday peak was volume-driven, with GMV +53.55%, order volume +62.77%, and AOV -5.66% MoM.
- Conducted RFM, cohort, and LTV analyses and found a low-retention marketplace pattern: repeat purchase rate 3.1%, next-month retention 0.4%-0.7%, and LTV uplift only 3%-5%.
- Diagnosed category and seller supply quality; found that poor `office_furniture` performance was driven by one low-rated slow-fulfillment seller contributing 70% of orders, rather than the category itself.
- Built offline purchase-based recommendation baselines including GlobalHot, CategoryHot, ItemCF, and HybridRecall; identified 97.72% user cold-start rate and proposed a hybrid cold-start recall strategy.

## 7. 简历精简 3 条版

如果简历空间很紧，可以只放 3 条:

- 基于 Olist 巴西电商 9 张业务表，完成 MySQL 建表导入、质量治理、GMV/漏斗/RFM/Cohort/品类/卖家/地域/VOC 分析，沉淀指标体系、看板和 AB 实验方案。
- 拆解 GMV 波动并识别 2017-11 黑五增长由订单量驱动（GMV +53.55%、订单量 +62.77%、AOV -5.66%）；发现平台复购率仅 3.1%、用户冷启动率 97.72%，策略重点应放在首单体验和冷启动承接。
- 构建购买行为推荐召回 baseline，实现 GlobalHot、CategoryHot、ItemCF、HybridRecall；验证 ItemCF 因共现稀疏失效，并提出“冷启动热门兜底 + 非冷启动品类召回”的业务化方案。

## 8. 投递时怎么选版本

| 公司/岗位 | 推荐版本 | 简历关键词 |
|---|---|---|
| 淘宝/天猫 DA | 淘宝版 | 指标体系、品类运营、推荐召回、AB 实验 |
| 京东 DA | 京东版 | 履约、供应链、卖家治理、VOC |
| 拼多多 DA | 拼多多版 | GMV 归因、促销拉新、转化效率、策略收益 |
| Shopee DA | Shopee 版 | 跨区域、卖家生态、物流体验、冷启动 |
| 美团/本地生活 DA | 美团版 | 商家健康、履约体验、区域运营 |
| 外企/英文简历 | Amazon 版 | marketplace analytics, cohort, seller quality, recommendation baseline |
