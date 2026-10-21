#!/usr/bin/env python3
"""Evaluate Laya MLX on labeled web blocks and compare prompt variants.

Run from the repository root:

    python3 eval/run_eval.py

The first run downloads the ~843 MB checkpoint. The script uses the same
question format, option rendering, calibration, and threshold as the app.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any

import laya_mlx as laya

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prompts import (  # noqa: E402
    VARIANTS,
    keyword_classify,
    questions_for,
    state_for,
)

DEFAULT_THRESHOLD = 0.55
MODEL_ID = "aac6fef/laya-mlx"


def clean_text(raw: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        row["text"] = clean_text(row["text"])
        rows.append(row)
    return rows


def split_name(item_id: str) -> str:
    digest = hashlib.sha1(item_id.encode()).hexdigest()
    return "dev" if int(digest[:8], 16) % 2 == 0 else "test"


def metrics(pairs: list[tuple[bool, bool]]) -> dict[str, Any]:
    tp = sum(1 for truth, pred in pairs if truth and pred)
    fp = sum(1 for truth, pred in pairs if not truth and pred)
    tn = sum(1 for truth, pred in pairs if not truth and not pred)
    fn = sum(1 for truth, pred in pairs if truth and not pred)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    total = tp + fp + tn + fn
    return {
        "n": total,
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "accuracy": round((tp + tn) / total, 4) if total else 0.0,
        "false_positive_rate": round(fp / (fp + tn), 4) if fp + tn else 0.0,
        "false_negative_rate": round(fn / (fn + tp), 4) if fn + tp else 0.0,
    }


def category_accuracy(
    rows: list[dict[str, Any]], predictions: list[dict[str, Any]]
) -> dict[str, Any]:
    correct = 0
    unsafe_correct = 0
    unsafe_total = 0
    confusion: dict[str, Counter[str]] = {}
    for row, pred in zip(rows, predictions):
        truth = row["category"]
        got = pred["category"]
        confusion.setdefault(truth, Counter())[got] += 1
        if truth == got:
            correct += 1
        if row["unsafe"]:
            unsafe_total += 1
            if truth == got:
                unsafe_correct += 1
    return {
        "overall": round(correct / len(rows), 4) if rows else 0.0,
        "on_unsafe_blocks": round(unsafe_correct / unsafe_total, 4) if unsafe_total else 0.0,
        "confusion": {k: dict(v) for k, v in sorted(confusion.items())},
    }


def evaluate_predictions(
    rows: list[dict[str, Any]],
    predictions: list[dict[str, Any]],
    threshold: float,
    split: str | None = None,
) -> dict[str, Any]:
    selected = [
        (row, pred)
        for row, pred in zip(rows, predictions)
        if split is None or split_name(row["id"]) == split
    ]
    if not selected:
        return {}
    pairs = [(row["unsafe"], pred["unsafe_probability"] >= threshold) for row, pred in selected]
    result = metrics(pairs)
    result["category"] = category_accuracy([row for row, _ in selected], [pred for _, pred in selected])
    return result


def predict_variant(
    agent: Any,
    rows: list[dict[str, Any]],
    variant: str,
    batch_size: int,
) -> tuple[list[dict[str, Any]], float]:
    questions = questions_for(variant)
    states = [state_for(variant, row["text"]) for row in rows]
    started = time.perf_counter()
    results = agent.predict_batch(states, questions, batch_size=batch_size)
    elapsed = time.perf_counter() - started

    predictions = []
    for result in results:
        unsafe = result["answers"]["unsafe"]
        category = result["answers"]["category"]
        predictions.append(
            {
                "unsafe_probability": round(float(unsafe["noul"]), 6),
                "unsafe_confidence": round(float(unsafe.get("confidence", 0.0)), 6),
                "category": category.get("choice"),
                "category_confidence": round(float(category.get("confidence", 0.0)), 6),
                "category_probabilities": {
                    key: round(float(value), 6)
                    for key, value in category.get("probabilities", {}).items()
                },
                "usage": result.get("usage", {}),
            }
        )
    return predictions, elapsed


def combined_predictions(
    rows: list[dict[str, Any]], predictions: list[dict[str, Any]], threshold: float
) -> list[dict[str, Any]]:
    combined = []
    for row, pred in zip(rows, predictions):
        keyword_safe, keyword_reason, keyword_score = keyword_classify(row["text"])
        model_unsafe = pred["unsafe_probability"] >= threshold
        combined.append(
            {
                "unsafe_probability": pred["unsafe_probability"],
                "unsafe": (not keyword_safe) or model_unsafe,
                "keyword_safe": keyword_safe,
                "keyword_reason": keyword_reason,
                "keyword_score": keyword_score,
                "model_unsafe": model_unsafe,
                "category": pred["category"],
            }
        )
    return combined


def metrics_for_combined(
    rows: list[dict[str, Any]], combined: list[dict[str, Any]], split: str | None = None
) -> dict[str, Any]:
    selected = [
        (row, pred)
        for row, pred in zip(rows, combined)
        if split is None or split_name(row["id"]) == split
    ]
    return metrics([(row["unsafe"], pred["unsafe"]) for row, pred in selected])


def keyword_metrics(rows: list[dict[str, Any]], split: str | None = None) -> dict[str, Any]:
    selected = [row for row in rows if split is None or split_name(row["id"]) == split]
    pairs = []
    for row in selected:
        safe, _, _ = keyword_classify(row["text"])
        pairs.append((row["unsafe"], not safe))
    return metrics(pairs)


def threshold_sweep(
    rows: list[dict[str, Any]], predictions: list[dict[str, Any]], split: str
) -> list[dict[str, Any]]:
    selected = [
        (row, pred)
        for row, pred in zip(rows, predictions)
        if split_name(row["id"]) == split
    ]
    sweep = []
    for step in range(30, 81, 5):
        threshold = step / 100
        result = metrics(
            [(row["unsafe"], pred["unsafe_probability"] >= threshold) for row, pred in selected]
        )
        result["threshold"] = threshold
        sweep.append(result)
    return sweep


def best_threshold(sweep: list[dict[str, Any]]) -> dict[str, Any]:
    return max(sweep, key=lambda item: (item["f1"], item["accuracy"]))


def summarize_variant(
    rows: list[dict[str, Any]],
    predictions: list[dict[str, Any]],
    elapsed: float,
) -> dict[str, Any]:
    sweep = threshold_sweep(rows, predictions, "dev")
    best = best_threshold(sweep)
    return {
        "at_0_55": {
            "overall": evaluate_predictions(rows, predictions, DEFAULT_THRESHOLD),
            "dev": evaluate_predictions(rows, predictions, DEFAULT_THRESHOLD, "dev"),
            "test": evaluate_predictions(rows, predictions, DEFAULT_THRESHOLD, "test"),
        },
        "threshold_sweep_dev": sweep,
        "best_threshold_dev": best,
        "test_at_best_threshold": evaluate_predictions(
            rows, predictions, best["threshold"], "test"
        ),
        "mean_latency_ms": round(elapsed / len(rows) * 1000, 2),
        "predictions": predictions,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=Path("eval/data/labeled_blocks.jsonl"))
    parser.add_argument("--out", type=Path, default=Path("eval/results/prompt_eval.json"))
    parser.add_argument("--variants", nargs="*", default=list(VARIANTS))
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--limit", type=int, default=0, help="Evaluate only the first N rows")
    parser.add_argument("--skip-model", action="store_true", help="Only compute keyword metrics")
    parser.add_argument("--merge", action="store_true", help="Merge into an existing results file")
    args = parser.parse_args()

    rows = load_rows(args.data)
    if args.limit:
        rows = rows[: args.limit]
    print(f"Loaded {len(rows)} labeled blocks ({sum(r['unsafe'] for r in rows)} unsafe)")
    print(f"Dev/test split: {Counter(split_name(r['id']) for r in rows)}")

    existing: dict[str, Any] = {}
    if args.merge and args.out.exists():
        existing = json.loads(args.out.read_text())
        print(f"Merging into {args.out} ({len(existing.get('variants', {}))} variants)")

    report: dict[str, Any] = {
        "model": MODEL_ID,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "threshold": args.threshold,
        "counts": {
            "total": len(rows),
            "unsafe": sum(1 for r in rows if r["unsafe"]),
            "safe": sum(1 for r in rows if not r["unsafe"]),
        },
        "keyword": {
            "overall": keyword_metrics(rows),
            "dev": keyword_metrics(rows, "dev"),
            "test": keyword_metrics(rows, "test"),
        },
        "variants": existing.get("variants", {}),
    }

    if not args.skip_model:
        print("Loading model (first run downloads the checkpoint)...")
        load_started = time.perf_counter()
        agent = laya.load(MODEL_ID)
        print(f"Model loaded in {time.perf_counter() - load_started:.1f}s")
        report["model_load_seconds"] = round(time.perf_counter() - load_started, 2)

        for variant in args.variants:
            if variant not in VARIANTS:
                raise SystemExit(f"Unknown variant: {variant}")
            print(f"\n== {variant} ==", flush=True)
            predictions, elapsed = predict_variant(agent, rows, variant, args.batch_size)
            summary = summarize_variant(rows, predictions, elapsed)
            report["variants"][variant] = summary

            overall = summary["at_0_55"]["overall"]
            test = summary["at_0_55"]["test"]
            best = summary["best_threshold_dev"]
            test_best = summary["test_at_best_threshold"]
            print(
                f"  0.55 overall: P={overall['precision']:.3f} R={overall['recall']:.3f} "
                f"F1={overall['f1']:.3f} acc={overall['accuracy']:.3f}"
            )
            print(
                f"  dev best threshold={best['threshold']:.2f} F1={best['f1']:.3f} | "
                f"test F1={test_best['f1']:.3f} acc={test_best['accuracy']:.3f}"
            )
            print(f"  mean latency: {summary['mean_latency_ms']:.1f} ms/block")

        for variant in ("baseline", "reporting_aware", "reader_impact", "strict_graphic"):
            if variant not in report["variants"]:
                continue
            predictions = report["variants"][variant]["predictions"]
            combined = combined_predictions(rows, predictions, args.threshold)
            report["variants"][variant]["combined_with_keyword"] = {
                "overall": metrics_for_combined(rows, combined),
                "dev": metrics_for_combined(rows, combined, "dev"),
                "test": metrics_for_combined(rows, combined, "test"),
            }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"\nWrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
