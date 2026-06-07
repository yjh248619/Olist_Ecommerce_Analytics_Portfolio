import os
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


load_dotenv()


def required_env(name: str) -> str:
    """Read a required environment variable with a clear setup hint."""
    value = os.getenv(name)
    if value:
        return value

    raise RuntimeError(
        f"Missing required environment variable: {name}. "
        "Copy .env.example to .env or set it in your shell first."
    )


def build_mysql_url() -> str:
    user = os.getenv("MYSQL_USER", "root")
    password = quote_plus(required_env("MYSQL_PASSWORD"))
    host = os.getenv("MYSQL_HOST", "localhost")
    port = os.getenv("MYSQL_PORT", "3306")
    database = os.getenv("MYSQL_DATABASE", "Olist")

    return (
        f"mysql+pymysql://{user}:{password}@{host}:{port}/"
        f"{database}?charset=utf8mb4"
    )


# pandas can robustly parse review text containing embedded newlines.
csv_path = Path(required_env("ORDER_REVIEWS_CSV"))
if not csv_path.exists():
    raise FileNotFoundError(f"ORDER_REVIEWS_CSV does not exist: {csv_path}")

df = pd.read_csv(csv_path, encoding="utf-8")
print(f"CSV 读取行数: {len(df)}")

# 空字符串 -> NaN，对应写入 MySQL 后的 NULL。
df = df.replace("", pd.NA)

df["review_creation_date"] = pd.to_datetime(df["review_creation_date"])
df["review_answer_timestamp"] = pd.to_datetime(
    df["review_answer_timestamp"],
    errors="coerce",
)

engine = create_engine(build_mysql_url())

df.to_sql(
    name="order_reviews",
    con=engine,
    if_exists="append",
    index=False,
    chunksize=5000,
    method="multi",
)

print("导入完成")

with engine.connect() as conn:
    cnt = conn.execute(text("SELECT COUNT(*) FROM order_reviews")).scalar()
    print(f"MySQL 实际行数: {cnt}")
