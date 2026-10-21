#!/usr/bin/env python3
"""Compare decision rules on saved prompt-eval predictions.

This does not run the model. It reuses eval/results/prompt_eval.json.
"""

from __future__ import annotations

import json
from pathlib import Path

ROWS = [
    json.loads(line)
    for line in Path("eval/data/labeled_blocks.jsonl").read_text().splitlines()
    if line.strip()
]
REPORT = json.loads(Path("eval/results/prompt_eval.json").read_text())


def split_name(item_id: str) -> str:
    import hashlib

    return "dev" if int(hashlib.sha1(item_id.encode()).hexdigest()[:8], 16) % 2 == 0 else "test"


def metrics(pairs: list[tuple[bool, bool]]) -> dict[str, float | int]:
    tp = sum(1 for truth, pred in pairs if truth and pred)
    fp = sum(1 for truth, pred in pairs if not truth and pred)
    tn = sum(1 for truth, pred in pairs if not truth and not pred)
    fn = sum(1 for truth, pred in pairs if truth and not pred)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "n": tp + fp + tn + fn,
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "accuracy": round((tp + tn) / len(pairs), 4),
    }


def rule_prediction(prediction: dict, noul: float, category: float) -> bool:
    if prediction["unsafe_probability"] >= noul:
        return True
    top_category = max(prediction["category_probabilities"].values(), default=0.0)
    return prediction["category"] != "safe" and top_category >= category


def main() -> None:
    rules = []
    for variant, data in REPORT.get("variants", {}).items():
        predictions = data["predictions"]
        for noul in (0.50, 0.55, 0.60):
            for category in (0.55, 0.70, 0.80):
                for split in ("dev", "test"):
                    pairs = [
                        (row["unsafe"], rule_prediction(pred, noul, category))
                        for row, pred in zip(ROWS, predictions)
                        if split_name(row["id"]) == split
                    ]
                    rules.append({
                        "variant": variant,
                        "split": split,
                        "noul_threshold": noul,
                        "category_threshold": category,
                        **metrics(pairs),
                    })

    Path("eval/results/decision_rules.json").write_text(json.dumps(rules, indent=2) + "\n")

    best = {}
    for row in rules:
        if row["split"] != "dev":
            continue
        key = row["variant"]
        if key not in best or row["f1"] > best[key]["f1"]:
            best[key] = row
    print(f"{'variant':22} {'noul':>5} {'cat':>5} {'devP':>6} {'devR':>6} {'devF1':>6}")
    for variant, row in best.items():
        print(
            f"{variant:22} {row['noul_threshold']:5.2f} {row['category_threshold']:5.2f} "
            f"{row['precision']:6.3f} {row['recall']:6.3f} {row['f1']:6.3f}"
        )
        test = next(
            r for r in rules
            if r["variant"] == variant
            and r["split"] == "test"
            and r["noul_threshold"] == row["noul_threshold"]
            and r["category_threshold"] == row["category_threshold"]
        )
        print(
            f"{'':22} {'':5} {'':5} testF1={test['f1']:.3f} "
            f"testP={test['precision']:.3f} testR={test['recall']:.3f}"
        )


if __name__ == "__main__":
    main()
