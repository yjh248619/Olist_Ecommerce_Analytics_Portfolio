# 推荐召回原型分析笔记

> 文件对应: `sql/70_reco_dataset.sql`, `scripts/reco_baseline.py`  
> 最后更新: 2026-06-07  
> 定位: 基于购买行为的离线候选召回原型，不是完整工业推荐系统。

## 一、分析目的

Olist 数据没有曝光、点击、搜索词、加购和实验分组，因此不能直接训练完整推荐排序模型。本模块的目标是用历史购买行为构建一个离线召回原型，回答三个问题:

```text
1. 只用热门商品能不能作为冷启动 baseline?
2. 用户有历史品类时，同品类热门是否比全局热门更好?
3. 在低复购、强冷启动数据下，ItemCF 是否仍然有效?
```

新增 `HybridRecall` 的目的，是把前面单路召回的发现转成更贴近线上业务的策略:

```text
冷启动用户: GlobalHot
非冷启动用户: CategoryHot 优先，不足用 GlobalHot 补足
```

## 二、业务逻辑

Olist 是典型低复购平台，验证期用户冷启动率达到 **97.72%**。这意味着绝大多数用户没有历史购买行为，复杂协同过滤没有足够信号，冷启动策略反而是主战场。

因此推荐链路应该分人群处理:

| 用户类型 | 可用信号 | 更合理的召回 |
|---|---|---|
| 冷启动用户 | 无历史购买 | GlobalHot / QualityGlobalHot |
| 非冷启动用户 | 历史商品和品类 | CategoryHot + GlobalHot 兜底 |
| 多次购买用户 | 商品共现 | ItemCF 可尝试，但 Olist 中信号极弱 |

## 三、计算逻辑

推荐数据集先按事件级时间切分，再分别聚合:

```text
interaction_events
-> train_interactions (< 2018-06-01)
-> val_interactions (>= 2018-06-01)
-> product_features_train
-> global_hot_baseline / category_hot_baseline
-> Python 评估 Recall@K, NDCG@K, Coverage
```

这样做是为了避免 `user-item pair` 先聚合后用 `last_purchase_time` 切分带来的未来信息泄漏。

## 四、召回策略

| 召回路 | 逻辑 | 适用场景 |
|---|---|---|
| GlobalHot | 训练期全局热门 Top 200 | 冷启动兜底 |
| CategoryHot | 用户历史品类 -> 同品类 Top K | 有历史品类的 warm user |
| ItemCF | 商品共现相似度召回 | 多次购买用户，但 Olist 中稀疏 |
| HybridRecall | 冷启动 GlobalHot；非冷启动 CategoryHot + GlobalHot 补足 | 当前最推荐写进项目亮点 |
| QualityHybrid | 冷启动高评分热门；非冷启动 CategoryHot + 高评分热门补足 | 体验优先版本，适合 AB 实验假设 |

## 五、核心结果

### 5.1 全量验证集

| 召回路 | Recall@50 | NDCG@50 | 解释 |
|---|---:|---:|---|
| GlobalHot | 0.0373 | 0.0110 | 最强单路 baseline |
| HybridRecall | 0.0375 | 0.0112 | 略优于 GlobalHot，且逻辑更贴近业务 |
| CategoryHot | 0.0004 | 0.0003 | 冷启动用户无历史品类，整体被稀释 |
| ItemCF | 0.0000 | 0.0000 | 共现矩阵过稀疏 |
| QualityHybrid | 0.0120 | 0.0029 | 体验优先重排牺牲购买命中 |

### 5.2 Warm target 口径

| 召回路 | Recall@50 | NDCG@50 | 解释 |
|---|---:|---:|---|
| GlobalHot | 0.0649 | 0.0191 | 去掉商品冷启动噪声后效果更清楚 |
| HybridRecall | 0.0654 | 0.0195 | 当前最强整体方案 |
| QualityHybrid | 0.0208 | 0.0050 | 适合作为体验护栏策略，不适合作纯召回最优 |

### 5.3 非冷启动 warm 用户

这是最能证明 Hybrid 价值的分组:

| 召回路 | Recall@20 | Recall@50 |
|---|---:|---:|
| CategoryHot | 0.0339 | 0.0339 |
| GlobalHot | 0.0239 | 0.0478 |
| HybridRecall | 0.0458 | 0.0657 |

结论:  
`CategoryHot` 在前排能利用用户历史品类，`GlobalHot` 在后排补足候选池，因此 Hybrid 同时吃到个性化和热门兜底的收益。

## 六、踩坑预警

| 坑 | 症状 | 修正 |
|---|---|---|
| 把空召回用户排除 | CategoryHot / ItemCF 指标虚高 | 空召回也计入 0 分 |
| 先聚合再切分 | 训练集提前知道未来购买 | 事件级先切分，再聚合 |
| 全量商品特征做热门榜 | 未来销量泄漏 | `product_features_train` 只用训练期 |
| ItemCF 调参过度 | Recall 仍然为 0 | 承认数据稀疏，转向冷启动策略 |
| 只看 Recall 不看 Coverage | 热门榜过度集中 | 同时输出 Recommendation Coverage 和 Candidate Coverage |
| 高评分重排直接替代热门 | Recall 明显下降 | 把 QualityHybrid 作为体验护栏或 AB 实验假设 |

## 七、汇报口径

```text
我没有把推荐系统理解成“上来训练一个模型”。
我先按时间切分构建购买行为样本，再做 GlobalHot、CategoryHot、ItemCF 三条 baseline。
评估后发现 Olist 验证期 97.72% 用户是冷启动，ItemCF 共现矩阵几乎为空，
所以最合理的策略不是继续调模型，而是做 HybridRecall:
冷启动用户用 GlobalHot 兜底，非冷启动用户先按历史品类召回，再用全局热门补足。
这个方案在 warm target Recall@50 上达到 6.54%，并且在非冷启动 warm 用户上从 GlobalHot 的 4.78% 提升到 6.57%。
```

更进一步可以讲:

```text
如果业务目标是首单体验，而不是纯购买命中，我会把高评分、低差评、快履约商品作为 QualityHybrid，
但离线结果显示它会牺牲 Recall，所以更适合作为 AB 实验中的体验护栏策略，而不是直接替代主召回。
```
