"""
scripts/reco_baseline.py

Olist 推荐召回 Baseline 评估
==============================
召回路:
1. GlobalHot: 全局热门
2. CategoryHot: 用户历史品类 -> 同品类热门
3. ItemCF: 商品共现协同过滤
4. HybridRecall: 冷启动走 GlobalHot，非冷启动先 CategoryHot 再 GlobalHot 补足
5. QualityHybrid: 冷启动走高评分热门，非冷启动先 CategoryHot 再高评分热门补足

评估指标:
Recall@K, NDCG@K, Recommendation Coverage@K, Candidate Coverage
"""

import os
import warnings
import pymysql
import pandas as pd
from dotenv import load_dotenv

from collections import defaultdict
from math import sqrt, log2
from typing import Dict, Set, List, Tuple


# ============================================================
# 配置
# ============================================================

load_dotenv()


def required_env(name: str) -> str:
    value = os.getenv(name)
    if value:
        return value

    raise RuntimeError(
        f"Missing required environment variable: {name}. "
        "Copy .env.example to .env or set it in your shell first."
    )


DB_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": int(os.getenv("MYSQL_PORT", "3306")),
    "user": os.getenv("MYSQL_USER", "root"),
    "password": required_env("MYSQL_PASSWORD"),
    "database": os.getenv("MYSQL_DATABASE", "Olist"),
    "charset": "utf8mb4",
}

K_VALUES = [5, 10, 20, 50]
ITEMCF_NEIGHBORS = 20
MIN_COOCCUR = 2

warnings.filterwarnings(
    "ignore",
    message="pandas only supports SQLAlchemy connectable",
    category=UserWarning,
)


# ============================================================
# 1. 加载数据
# ============================================================

def load_data():
    """加载训练集、验证集、热门候选、品类候选、商品品类映射。"""
    conn = pymysql.connect(**DB_CONFIG)

    train = pd.read_sql(
        """
        SELECT user_id, product_id, order_count, interaction_score
        FROM train_interactions
        """,
        conn,
    )

    val = pd.read_sql(
        """
        SELECT user_id, product_id, order_count, interaction_score
        FROM val_interactions
        """,
        conn,
    )

    global_hot = pd.read_sql(
        """
        SELECT
            product_id,
            global_hot_rank,
            avg_review_score,
            bad_review_rate_pct,
            order_count_train
        FROM global_hot_baseline
        ORDER BY global_hot_rank
        """,
        conn,
    )

    category_hot = pd.read_sql(
        """
        SELECT product_id, category_name, category_hot_rank
        FROM category_hot_baseline
        ORDER BY category_name, category_hot_rank
        """,
        conn,
    )

    product_cat = pd.read_sql(
        """
        SELECT product_id, category_name
        FROM product_features_train
        """,
        conn,
    )

    conn.close()

    train_dict = build_user_item_dict(train)
    val_dict = build_user_item_dict(val)

    cat_map = dict(zip(product_cat["product_id"], product_cat["category_name"]))
    hot_list = global_hot["product_id"].tolist()
    quality_hot_list = build_quality_hot_list(global_hot)

    cat_hot_dict = defaultdict(list)
    for row in category_hot.itertuples(index=False):
        cat_hot_dict[row.category_name].append(row.product_id)

    train_products = set(train["product_id"])
    val_products = set(val["product_id"])
    catalog_products = train_products | val_products

    return (
        train_dict,
        val_dict,
        hot_list,
        quality_hot_list,
        cat_hot_dict,
        cat_map,
        train_products,
        catalog_products,
    )


def build_user_item_dict(df: pd.DataFrame) -> Dict[str, Set[str]]:
    """将 user-item 表转成 {user_id: {product_id}}。"""
    user_items = defaultdict(set)
    for row in df.itertuples(index=False):
        user_items[row.user_id].add(row.product_id)
    return user_items


def build_quality_hot_list(global_hot: pd.DataFrame) -> List[str]:
    """
    构建高质量热门候选。

    这里不重新扩大候选池，只在训练期 GlobalHot Top 200 内按评分和差评率重排。
    好处是既保留热门商品的成交稳定性，又把冷启动推荐的体验风险放进排序。
    """
    ranked = global_hot.copy()
    ranked["avg_review_score"] = ranked["avg_review_score"].fillna(-1)
    ranked["bad_review_rate_pct"] = ranked["bad_review_rate_pct"].fillna(100)

    ranked = ranked.sort_values(
        by=[
            "avg_review_score",
            "bad_review_rate_pct",
            "order_count_train",
            "global_hot_rank",
            "product_id",
        ],
        ascending=[False, True, False, True, True],
    )

    return ranked["product_id"].tolist()


def filter_actual_by_products(
    val_dict: Dict[str, Set[str]],
    allowed_products: Set[str],
) -> Dict[str, Set[str]]:
    """只保留验证集中训练期已出现过的商品，用于 warm target 评估。"""
    filtered = {}
    for user_id, items in val_dict.items():
        kept = items & allowed_products
        if kept:
            filtered[user_id] = kept
    return filtered


# ============================================================
# 2. 召回策略
# ============================================================

def recall_global_hot(
    hot_list: List[str],
    k: int,
    exclude: Set[str] = None,
) -> List[str]:
    """全局热门召回。"""
    exclude = exclude or set()
    candidates = []

    for product_id in hot_list:
        if product_id in exclude:
            continue

        candidates.append(product_id)

        if len(candidates) >= k:
            break

    return candidates


def recall_category_hot(
    user_history: Set[str],
    cat_hot_dict: Dict[str, List[str]],
    cat_map: Dict[str, str],
    k: int,
) -> List[str]:
    """基于用户历史购买品类，召回同品类热门商品。"""
    user_categories = set()

    for product_id in user_history:
        category = cat_map.get(product_id)
        if category:
            user_categories.add(category)

    candidates = []
    seen = set()

    # sorted 保证每次运行顺序稳定，方便复现实验结果。
    for category in sorted(user_categories):
        for product_id in cat_hot_dict.get(category, []):
            if product_id in user_history or product_id in seen:
                continue

            candidates.append(product_id)
            seen.add(product_id)

            if len(candidates) >= k:
                return candidates

    return candidates


def recall_hybrid(
    user_history: Set[str],
    cat_hot_dict: Dict[str, List[str]],
    cat_map: Dict[str, str],
    fallback_hot_list: List[str],
    k: int,
) -> List[str]:
    """
    混合召回。

    冷启动用户没有历史品类，直接使用 fallback 热门榜。
    非冷启动用户先用历史品类热门，候选不足时再用 fallback 热门榜补足。
    """
    if not user_history:
        return recall_global_hot(fallback_hot_list, k)

    candidates = recall_category_hot(
        user_history=user_history,
        cat_hot_dict=cat_hot_dict,
        cat_map=cat_map,
        k=k,
    )

    if len(candidates) >= k:
        return candidates[:k]

    exclude = set(user_history) | set(candidates)
    fallback = recall_global_hot(
        hot_list=fallback_hot_list,
        k=k - len(candidates),
        exclude=exclude,
    )

    return (candidates + fallback)[:k]


# ============================================================
# 3. ItemCF
# ============================================================

def build_item_cooccurrence(
    train_dict: Dict[str, Set[str]],
) -> Dict[str, Dict[str, int]]:
    """构建商品共现矩阵。"""
    cooccur = defaultdict(lambda: defaultdict(int))

    for _, items in train_dict.items():
        item_list = sorted(items)

        for i in range(len(item_list)):
            for j in range(i + 1, len(item_list)):
                a = item_list[i]
                b = item_list[j]

                cooccur[a][b] += 1
                cooccur[b][a] += 1

    return cooccur


def build_item_similarity(
    cooccur: Dict[str, Dict[str, int]],
    train_dict: Dict[str, Set[str]],
) -> Dict[str, Dict[str, float]]:
    """
    将共现次数归一化为 ItemCF 相似度。

    sim(i, j) = cooccur(i, j) / sqrt(pop(i) * pop(j))
    """
    item_pop = defaultdict(int)

    for _, items in train_dict.items():
        for product_id in items:
            item_pop[product_id] += 1

    item_sim = defaultdict(dict)

    for a, neighbors in cooccur.items():
        for b, cooccur_count in neighbors.items():
            if cooccur_count < MIN_COOCCUR:
                continue

            denom = sqrt(item_pop[a] * item_pop[b])

            if denom > 0:
                item_sim[a][b] = cooccur_count / denom

    return item_sim


def build_top_neighbors(
    item_sim: Dict[str, Dict[str, float]],
) -> Dict[str, List[Tuple[str, float]]]:
    """预先保存每个商品的 Top 相似商品，避免评估时重复排序。"""
    top_neighbors = {}

    for product_id, neighbors in item_sim.items():
        ranked = sorted(
            neighbors.items(),
            key=lambda x: (-x[1], x[0]),
        )
        top_neighbors[product_id] = ranked[:ITEMCF_NEIGHBORS]

    return top_neighbors


def recall_itemcf(
    user_history: Set[str],
    top_neighbors: Dict[str, List[Tuple[str, float]]],
    k: int,
) -> List[str]:
    """基于用户历史商品召回相似商品。"""
    scores = defaultdict(float)

    for seed_item in sorted(user_history):
        for product_id, sim_score in top_neighbors.get(seed_item, []):
            if product_id in user_history:
                continue

            scores[product_id] += sim_score

    ranked = sorted(
        scores.items(),
        key=lambda x: (-x[1], x[0]),
    )

    return [product_id for product_id, _ in ranked[:k]]


# ============================================================
# 4. 评估指标
# ============================================================

def recall_at_k(recalled: List[str], actual: Set[str], k: int) -> float:
    """Recall@K = 命中商品数 / 用户未来真实购买商品数。"""
    if not actual:
        return 0.0

    hits = len(set(recalled[:k]) & actual)
    return hits / len(actual)


def ndcg_at_k(recalled: List[str], actual: Set[str], k: int) -> float:
    """NDCG@K: 命中位置越靠前，得分越高。"""
    if not actual:
        return 0.0

    dcg = 0.0

    for idx, product_id in enumerate(recalled[:k]):
        if product_id in actual:
            dcg += 1.0 / log2(idx + 2)

    ideal_hits = min(len(actual), k)
    idcg = sum(1.0 / log2(idx + 2) for idx in range(ideal_hits))

    return dcg / idcg if idcg > 0 else 0.0


def generate_recall(
    recall_name: str,
    user_history: Set[str],
    k: int,
    hot_list: List[str],
    quality_hot_list: List[str],
    cat_hot_dict: Dict[str, List[str]],
    cat_map: Dict[str, str],
    top_neighbors: Dict[str, List[Tuple[str, float]]],
) -> List[str]:
    """根据召回名称生成推荐候选。"""
    if recall_name == "GlobalHot":
        return recall_global_hot(hot_list, k, exclude=user_history)

    if recall_name == "CategoryHot":
        return recall_category_hot(user_history, cat_hot_dict, cat_map, k)

    if recall_name == "ItemCF":
        return recall_itemcf(user_history, top_neighbors, k)

    if recall_name == "HybridRecall":
        return recall_hybrid(
            user_history=user_history,
            cat_hot_dict=cat_hot_dict,
            cat_map=cat_map,
            fallback_hot_list=hot_list,
            k=k,
        )

    if recall_name == "QualityHybrid":
        return recall_hybrid(
            user_history=user_history,
            cat_hot_dict=cat_hot_dict,
            cat_map=cat_map,
            fallback_hot_list=quality_hot_list,
            k=k,
        )

    raise ValueError(f"Unknown recall name: {recall_name}")


def evaluate_recall(
    recall_name: str,
    val_dict: Dict[str, Set[str]],
    train_dict: Dict[str, Set[str]],
    hot_list: List[str],
    quality_hot_list: List[str],
    cat_hot_dict: Dict[str, List[str]],
    cat_map: Dict[str, str],
    top_neighbors: Dict[str, List[Tuple[str, float]]],
    target_scope: str,
) -> Tuple[pd.DataFrame, Dict[int, Set[str]]]:
    """
    对召回路进行评估。

    重要:
    即使 recalled 为空，也必须记录 0 分。
    否则 CategoryHot / ItemCF 会跳过大量冷启动用户，导致结果虚高。
    """
    rows = []
    coverage_by_k = {k: set() for k in K_VALUES}
    max_k = max(K_VALUES)

    for user_id, actual_items in val_dict.items():
        user_history = train_dict.get(user_id, set())
        is_cold_start = len(user_history) == 0

        recalled = generate_recall(
            recall_name=recall_name,
            user_history=user_history,
            k=max_k,
            hot_list=hot_list,
            quality_hot_list=quality_hot_list,
            cat_hot_dict=cat_hot_dict,
            cat_map=cat_map,
            top_neighbors=top_neighbors,
        )

        for k in K_VALUES:
            top_k = recalled[:k]
            coverage_by_k[k].update(top_k)

            rows.append({
                "target_scope": target_scope,
                "recall": recall_name,
                "K": k,
                "user_id": user_id,
                "cold_start": is_cold_start,
                "recall@K": recall_at_k(top_k, actual_items, k),
                "ndcg@K": ndcg_at_k(top_k, actual_items, k),
                "actual_count": len(actual_items),
                "history_count": len(user_history),
                "recall_count": len(top_k),
            })

    return pd.DataFrame(rows), coverage_by_k


# ============================================================
# 5. 汇总输出
# ============================================================

def print_metric_summary(df: pd.DataFrame, title: str):
    """打印 Recall / NDCG 汇总。"""
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)

    if df.empty:
        print("无可评估数据")
        return

    summary = (
        df.groupby(["target_scope", "recall", "K"])
        .agg(
            users=("user_id", "nunique"),
            avg_recall=("recall@K", "mean"),
            avg_ndcg=("ndcg@K", "mean"),
            avg_recall_count=("recall_count", "mean"),
            avg_actual_count=("actual_count", "mean"),
        )
        .round(4)
    )

    print(summary.to_string())


def print_segment_summary(df: pd.DataFrame, title: str, cold_start: bool):
    """打印冷启动 / 非冷启动分组结果。"""
    segment = df[df["cold_start"] == cold_start]

    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)

    if segment.empty:
        print("无可评估数据")
        return

    summary = (
        segment.groupby(["target_scope", "recall", "K"])
        .agg(
            users=("user_id", "nunique"),
            avg_recall=("recall@K", "mean"),
            avg_ndcg=("ndcg@K", "mean"),
            avg_recall_count=("recall_count", "mean"),
            avg_actual_count=("actual_count", "mean"),
        )
        .round(4)
    )

    print(summary.to_string())


def print_recommendation_coverage(
    coverage_maps: Dict[Tuple[str, str], Dict[int, Set[str]]],
    catalog_size: int,
):
    """打印实际推荐覆盖率。"""
    print("\n" + "=" * 80)
    print("Recommendation Coverage@K（实际推荐覆盖率）")
    print("=" * 80)

    rows = []

    for (target_scope, recall_name), by_k in coverage_maps.items():
        for k, products in by_k.items():
            rows.append({
                "target_scope": target_scope,
                "recall": recall_name,
                "K": k,
                "recommended_products": len(products),
                "coverage": len(products) / catalog_size if catalog_size else 0.0,
            })

    df = pd.DataFrame(rows)

    if df.empty:
        print("无覆盖率数据")
        return

    df["coverage"] = df["coverage"].round(4)
    print(df.sort_values(["target_scope", "recall", "K"]).to_string(index=False))


def print_candidate_coverage(
    hot_list: List[str],
    quality_hot_list: List[str],
    cat_hot_dict: Dict[str, List[str]],
    item_sim: Dict[str, Dict[str, float]],
    catalog_size: int,
):
    """打印候选池覆盖率，不等同于实际推荐覆盖率。"""
    print("\n" + "=" * 80)
    print("Candidate Coverage（候选池覆盖率）")
    print("=" * 80)

    global_candidates = set(hot_list)

    category_candidates = set()
    for product_ids in cat_hot_dict.values():
        category_candidates.update(product_ids)

    quality_candidates = set(quality_hot_list)
    hybrid_candidates = global_candidates | category_candidates
    quality_hybrid_candidates = quality_candidates | category_candidates

    itemcf_candidates = set(item_sim.keys())
    for neighbors in item_sim.values():
        itemcf_candidates.update(neighbors.keys())

    rows = [
        {
            "candidate_pool": "GlobalHot",
            "products": len(global_candidates),
            "coverage": len(global_candidates) / catalog_size if catalog_size else 0.0,
        },
        {
            "candidate_pool": "CategoryHot",
            "products": len(category_candidates),
            "coverage": len(category_candidates) / catalog_size if catalog_size else 0.0,
        },
        {
            "candidate_pool": "QualityGlobalHot",
            "products": len(quality_candidates),
            "coverage": len(quality_candidates) / catalog_size if catalog_size else 0.0,
        },
        {
            "candidate_pool": "HybridRecall",
            "products": len(hybrid_candidates),
            "coverage": len(hybrid_candidates) / catalog_size if catalog_size else 0.0,
        },
        {
            "candidate_pool": "QualityHybrid",
            "products": len(quality_hybrid_candidates),
            "coverage": len(quality_hybrid_candidates) / catalog_size if catalog_size else 0.0,
        },
        {
            "candidate_pool": "ItemCF",
            "products": len(itemcf_candidates),
            "coverage": len(itemcf_candidates) / catalog_size if catalog_size else 0.0,
        },
    ]

    df = pd.DataFrame(rows)
    df["coverage"] = df["coverage"].round(4)
    print(df.to_string(index=False))


# ============================================================
# 6. 主流程
# ============================================================

def main():
    print("=" * 80)
    print("Olist 推荐召回 Baseline 评估")
    print("=" * 80)

    print("\n[1/6] 加载数据...")
    (
        train_dict,
        val_dict,
        hot_list,
        quality_hot_list,
        cat_hot_dict,
        cat_map,
        train_products,
        catalog_products,
    ) = load_data()

    catalog_size = len(catalog_products)

    print(f"训练集用户数: {len(train_dict)}")
    print(f"验证集用户数: {len(val_dict)}")
    print(f"商品总池大小: {catalog_size}")
    print(f"全局热门候选数: {len(hot_list)}")
    print(f"高质量热门候选数: {len(quality_hot_list)}")
    print(f"品类热门覆盖品类数: {len(cat_hot_dict)}")

    cold_users = sum(1 for user_id in val_dict if user_id not in train_dict)
    cold_rate = cold_users * 100.0 / len(val_dict) if val_dict else 0.0

    print(f"冷启动用户: {cold_users}/{len(val_dict)} ({cold_rate:.2f}%)")

    warm_target_val_dict = filter_actual_by_products(val_dict, train_products)

    print(f"全量验证用户数: {len(val_dict)}")
    print(f"warm target 可评估用户数: {len(warm_target_val_dict)}")

    print("\n[2/6] 构建 ItemCF...")
    cooccur = build_item_cooccurrence(train_dict)
    cooccur_pairs = sum(len(v) for v in cooccur.values())
    print(f"商品共现对数量: {cooccur_pairs}")

    item_sim = build_item_similarity(cooccur, train_dict)
    sim_pairs = sum(len(v) for v in item_sim.values())
    print(f"相似商品对数量(min_cooccur={MIN_COOCCUR}): {sim_pairs}")

    top_neighbors = build_top_neighbors(item_sim)

    print("\n[3/6] 评估召回路...")
    recall_names = [
        "GlobalHot",
        "CategoryHot",
        "ItemCF",
        "HybridRecall",
        "QualityHybrid",
    ]

    all_metric_frames = []
    coverage_maps = {}

    eval_scopes = [
        ("all_targets", val_dict),
        ("warm_targets", warm_target_val_dict),
    ]

    for target_scope, target_val_dict in eval_scopes:
        print(f"\n评估口径: {target_scope}")

        for recall_name in recall_names:
            print(f"  -> {recall_name}")

            df_metrics, coverage_by_k = evaluate_recall(
                recall_name=recall_name,
                val_dict=target_val_dict,
                train_dict=train_dict,
                hot_list=hot_list,
                quality_hot_list=quality_hot_list,
                cat_hot_dict=cat_hot_dict,
                cat_map=cat_map,
                top_neighbors=top_neighbors,
                target_scope=target_scope,
            )

            all_metric_frames.append(df_metrics)
            coverage_maps[(target_scope, recall_name)] = coverage_by_k

    df_all = pd.concat(all_metric_frames, ignore_index=True)

    print("\n[4/6] 汇总 Recall@K / NDCG@K...")
    print_metric_summary(df_all, "整体指标")
    print_segment_summary(df_all, "非冷启动用户指标", cold_start=False)
    print_segment_summary(df_all, "冷启动用户指标", cold_start=True)

    print("\n[5/6] 汇总 Coverage...")
    print_recommendation_coverage(coverage_maps, catalog_size)
    print_candidate_coverage(hot_list, quality_hot_list, cat_hot_dict, item_sim, catalog_size)

    print("\n[6/6] 结果解释提示")
    print("=" * 80)
    print("1. all_targets: 按真实业务全量验证集评估，包含用户冷启动和商品冷启动。")
    print("2. warm_targets: 只评估训练期已出现过的商品，更适合观察模型本身召回能力。")
    print("3. CategoryHot 和 ItemCF 对冷启动用户通常召回为空，但这部分现在会被计入 0 分。")
    print("4. HybridRecall 更贴近真实线上策略: 有历史就个性化，无历史就热门兜底。")
    print("5. QualityHybrid 把评分和差评率作为体验护栏，适合冷启动首单推荐。")
    print("6. Recommendation Coverage 是实际推荐出去的商品覆盖率。")
    print("7. Candidate Coverage 是候选池覆盖率，不代表真实推荐覆盖率。")

    print("\n评估完成。")


if __name__ == "__main__":
    main()


