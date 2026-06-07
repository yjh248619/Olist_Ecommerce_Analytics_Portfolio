# Olist 项目流程图

> 用途: README / 项目汇报讲解中的项目结构辅助图
> 版本: 2026-06-07

## 1. 分析主线流程

```mermaid
flowchart LR
    A[原始 CSV 数据] --> B[MySQL 建表与导入]
    B --> C[数据质量检查]
    C --> D[清洗视图 v_orders_clean]
    D --> E[交易大盘与漏斗]
    E --> F[用户生命周期 RFM/Cohort/LTV]
    E --> G[品类经营分析]
    G --> H[卖家健康度分析]
    H --> I[策略收益估算]
    I --> J[指标体系与看板]
    I --> K[AB 实验设计]
    G --> L[推荐召回数据集]
    F --> L
    H --> L
    L --> M[GlobalHot / CategoryHot / ItemCF]
    M --> N[HybridRecall]
```

## 2. 业务诊断闭环

```mermaid
flowchart TD
    A[发现指标异常] --> B{先拆公式}
    B --> C[GMV = 订单量 x AOV]
    C --> D[订单量 = 购买用户数 x 人均订单数]
    C --> E[AOV = 商品价格 + 运费]
    D --> F[按时间 / 地域 / 品类 / 卖家 / 用户下钻]
    E --> F
    F --> G[定位可行动对象]
    G --> H[策略设计]
    H --> I[收益估算]
    I --> J[AB 实验验证]
    J --> K[看板监控]
```

## 3. 推荐召回原型

```mermaid
flowchart TD
    A[购买事件 interaction_events] --> B[时间切分]
    B --> C[train_interactions]
    B --> D[val_interactions]
    C --> E[训练期商品特征 product_features_train]
    E --> F[GlobalHot]
    E --> G[CategoryHot]
    C --> H[ItemCF 共现矩阵]
    F --> I[HybridRecall]
    G --> I
    H --> J[Recall@K / NDCG@K / Coverage]
    I --> J
    D --> J
```

## 4. 一句话讲图

```text
这个项目从数据可信开始，先做交易和用户供给诊断，再把发现转成策略收益、看板监控和 AB 实验，最后基于购买行为构建推荐召回原型。
```
