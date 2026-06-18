#!/usr/bin/env python3
"""LightGBM benchmark on the Credit Card Fraud Detection dataset.

Part 7 (CPU fallback) deliverable for LAB 16. Trains a gradient-boosting
classifier, reports the metrics from the 7.6 table, and writes
benchmark_result.json.

Usage:
    python3 benchmark.py [path/to/creditcard.csv]

Default dataset path: ~/ml-benchmark/creditcard.csv
"""

import json
import os
import sys
import time

import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)


def find_dataset(argv):
    if len(argv) > 1:
        return argv[1]
    candidates = [
        os.path.expanduser("~/ml-benchmark/creditcard.csv"),
        "creditcard.csv",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "creditcard.csv"),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return candidates[0]


def main():
    data_path = find_dataset(sys.argv)
    if not os.path.exists(data_path):
        sys.exit(
            f"[ERROR] Dataset not found at '{data_path}'.\n"
            "Download it first:\n"
            "  kaggle datasets download -d mlg-ulb/creditcardfraud --unzip -p ~/ml-benchmark/"
        )

    print("=" * 60)
    print("LightGBM Benchmark - Credit Card Fraud Detection")
    print("=" * 60)
    print(f"Dataset: {data_path}")

    # 1. Load data
    t0 = time.perf_counter()
    df = pd.read_csv(data_path)
    load_time = time.perf_counter() - t0
    print(f"Loaded {len(df):,} rows x {df.shape[1]} cols in {load_time:.3f}s")
    print(f"Fraud cases: {int(df['Class'].sum()):,} "
          f"({df['Class'].mean() * 100:.4f}%)")

    X = df.drop(columns=["Class"])
    y = df["Class"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    train_set = lgb.Dataset(X_train, label=y_train)
    valid_set = lgb.Dataset(X_test, label=y_test, reference=train_set)

    # Strongly regularized: V1-V28 are PCA components and few positives,
    # so a shallow + heavily regularized ensemble generalizes best here.
    params = {
        "objective": "binary",
        "metric": "auc",
        "boosting_type": "gbdt",
        "learning_rate": 0.02,
        "num_leaves": 8,
        "max_depth": -1,
        "min_child_samples": 100,
        "lambda_l1": 1.0,
        "lambda_l2": 1.0,
        "feature_fraction": 0.8,
        "bagging_fraction": 0.8,
        "bagging_freq": 5,
        "n_jobs": -1,
        "verbose": -1,
        "seed": 42,
    }
    num_boost_round = 500

    # 2. Training
    t0 = time.perf_counter()
    model = lgb.train(
        params,
        train_set,
        num_boost_round=num_boost_round,
        valid_sets=[valid_set],
        callbacks=[lgb.log_evaluation(period=0)],
    )
    train_time = time.perf_counter() - t0
    best_iteration = model.num_trees()
    print(f"Trained in {train_time:.3f}s (trees={best_iteration})")

    # 3. Evaluation
    y_prob = model.predict(X_test, num_iteration=best_iteration)
    y_pred = (y_prob >= 0.5).astype(int)

    metrics = {
        "auc_roc": float(roc_auc_score(y_test, y_prob)),
        "auc_pr": float(average_precision_score(y_test, y_prob)),
        "accuracy": float(accuracy_score(y_test, y_pred)),
        "f1_score": float(f1_score(y_test, y_pred)),
        "precision": float(precision_score(y_test, y_pred, zero_division=0)),
        "recall": float(recall_score(y_test, y_pred)),
    }

    # 4. Inference latency / throughput
    single = X_test.iloc[[0]]
    # warmup
    for _ in range(10):
        model.predict(single, num_iteration=best_iteration)

    runs = 100
    t0 = time.perf_counter()
    for _ in range(runs):
        model.predict(single, num_iteration=best_iteration)
    latency_ms = (time.perf_counter() - t0) / runs * 1000.0

    batch = X_test.iloc[:1000] if len(X_test) >= 1000 else X_test
    t0 = time.perf_counter()
    model.predict(batch, num_iteration=best_iteration)
    batch_time = time.perf_counter() - t0
    throughput = len(batch) / batch_time

    result = {
        "dataset": os.path.basename(data_path),
        "rows_total": int(len(df)),
        "rows_train": int(len(X_train)),
        "rows_test": int(len(X_test)),
        "features": int(X.shape[1]),
        "load_time_sec": round(load_time, 4),
        "train_time_sec": round(train_time, 4),
        "best_iteration": int(best_iteration),
        "auc_roc": round(metrics["auc_roc"], 6),
        "auc_pr": round(metrics["auc_pr"], 6),
        "accuracy": round(metrics["accuracy"], 6),
        "f1_score": round(metrics["f1_score"], 6),
        "precision": round(metrics["precision"], 6),
        "recall": round(metrics["recall"], 6),
        "inference_latency_ms_1row": round(latency_ms, 4),
        "inference_throughput_rows_per_sec_1000": round(throughput, 2),
        "instance_type": os.environ.get("INSTANCE_TYPE", "r5.xlarge"),
    }

    print("-" * 60)
    print(f"{'Load time':<32}: {result['load_time_sec']} s")
    print(f"{'Training time':<32}: {result['train_time_sec']} s")
    print(f"{'Trees (best iteration)':<32}: {result['best_iteration']}")
    print(f"{'AUC-ROC':<32}: {result['auc_roc']}")
    print(f"{'AUC-PR':<32}: {result['auc_pr']}")
    print(f"{'Accuracy':<32}: {result['accuracy']}")
    print(f"{'F1-Score':<32}: {result['f1_score']}")
    print(f"{'Precision':<32}: {result['precision']}")
    print(f"{'Recall':<32}: {result['recall']}")
    print(f"{'Inference latency (1 row)':<32}: {result['inference_latency_ms_1row']} ms")
    print(f"{'Throughput (1000 rows)':<32}: "
          f"{result['inference_throughput_rows_per_sec_1000']} rows/s")
    print("-" * 60)

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "benchmark_result.json")
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Saved metrics -> {out_path}")


if __name__ == "__main__":
    main()
