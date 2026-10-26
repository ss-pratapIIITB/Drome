#!/usr/bin/env python3
"""End-to-end removal eval for Drome on mobile fixtures.

Pipeline per fixture (real pages saved with injected synthetic unsafe units):

  1. extract candidates           node extract_blocks.mjs --html … --out blocks.json
  2. classify candidates          Laya MLX (shipping news-soft question, threshold 0.55)
                                  or --skip-laya for deterministic hand labels
  3. hide unsafe candidates       node extract_blocks.mjs --html … --hide labels.json
     (same code path the app uses: leaf + resolved section)
  4. score                        removedAll (no unsafe text visible)
                                  noCollateral (no safe text hidden)

    python3 eval/run_removal_eval.py                 # with Laya
    python3 eval/run_removal_eval.py --skip-laya     # hand labels only
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOBILE = HERE / "fixtures" / "mobile"
REPORTS = HERE / "reports"
sys.path.insert(0, str(HERE))

MODEL_ID = "aac6fef/laya-mlx"
VARIANT = "baseline"
THRESHOLD = 0.55
CATEGORY_THRESHOLD = 0.70
FIXTURES = ["bbc-article", "verge-feed", "aljazeera-article"]

# Page context prepended to every block, mirroring the app (title + host).
CONTEXTS = {
    "bbc-article": 'Article: "BBC News" — bbc.co.uk',
    "verge-feed": 'Article: "The Verge" — theverge.com',
    "aljazeera-article": (
        'Article: "European, Middle East ministers urge US-Iran diplomacy, not new '
        'attacks" — aljazeera.com'
    ),
}


def run_node_extract(html: Path, out: Path) -> list[dict]:
    subprocess.run(
        ["node", "extract_blocks.mjs", "--html", str(html), "--out", str(out)],
        cwd=HERE, check=True, capture_output=True, text=True,
    )
    return json.loads(out.read_text())


def classify_laya(texts: list[str], context: str | None = None) -> list[dict]:
    import laya_mlx as laya
    from prompts import VARIANTS, questions_for, state_for

    agent = laya.load(MODEL_ID)
    states = [state_for(VARIANT, text) for text in texts]
    if context:
        states = [
            f"{context}\n\n{state}" if isinstance(state, str) else state
            for state in states
        ]
    questions = questions_for(VARIANT)
    started = time.perf_counter()
    results = agent.predict_batch(states, questions, batch_size=4)
    elapsed = time.perf_counter() - started
    out = []
    for result in results:
        unsafe = result["answers"]["unsafe"]
        category = result["answers"]["category"]
        prob = float(unsafe["noul"])
        cat = category.get("choice", "safe")
        cat_prob = float(category.get("confidence", 0.0) or 0.0)
        out.append({
            "unsafe_prob": round(prob, 4),
            "category": cat,
            "cat_prob": round(cat_prob, 4),
            "unsafe": prob >= THRESHOLD or (cat != "safe" and cat_prob >= CATEGORY_THRESHOLD),
        })
    print(f"    laya latency: {elapsed * 1000:.0f} ms total")
    return out


def labels_for(name: str, blocks: list[dict], ground: dict, use_laya: bool) -> dict:
    if not use_laya:
        yes = [b["text"] for b in blocks if any(g.split("—")[-1].strip()[:20] in b["text"] or g[:20] in b["text"] for g in ground["hide"])]
        no = [b["text"] for b in blocks if b["text"] not in yes]
        return {"hide": yes, "keep": no[:60]}
    preds = classify_laya([b["text"] for b in blocks], CONTEXTS.get(name))
    hide, keep, missed = [], [], []
    for b, p in zip(blocks, preds):
        unsafe = p["unsafe"]
        if (
            unsafe
            and b.get("heading")
            and p["unsafe_prob"] < 0.85
            and p["category"] not in {"adult", "self_harm"}
        ):
            unsafe = False
        (hide if unsafe else keep).append(b["text"])
        if any(g[:20] in b["text"] for g in ground["hide"]) and not p["unsafe"]:
            missed.append(b["text"][:60])
    if missed:
        print(f"    ⚠ classifier missed {len(missed)} synthetic fragment(s): " +
              " | ".join(m[:40] for m in missed[:3]))
    return {"hide": hide, "keep": keep[:60]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-laya", action="store_true")
    args = parser.parse_args()

    ground_all = json.loads((MOBILE / "fixtures.json").read_text())
    REPORTS.mkdir(exist_ok=True)
    summary = {}
    for name in FIXTURES:
        html = MOBILE / f"{name}.html"
        ground = ground_all.get(name, {"hide": [], "keep": []})
        print(f"\n== {name} ==")
        blocks = run_node_extract(html, REPORTS / f"blocks-{name}.json")
        labels = labels_for(name, blocks, ground, use_laya=not args.skip_laya)
        labels_path = REPORTS / f"labels-{name}.json"
        labels_path.write_text(json.dumps(labels, indent=2) + "\n")
        print(f"    blocks={len(blocks)} classified-unsafe={len(labels['hide'])}")

        result = subprocess.run(
            ["node", "extract_blocks.mjs", "--html", str(html),
             "--hide", str(labels_path), "--out", str(REPORTS / f"removal-{name}.json")],
            cwd=HERE, capture_output=True, text=True,
        )
        print(result.stdout.strip())
        if result.returncode != 0:
            print(result.stderr.strip())
        report = json.loads((REPORTS / f"removal-{name}.json").read_text())
        summary[name] = {
            "removedAll": not report["remainingVisible"],
            "noCollateral": not report["collateralHidden"],
            "cascade": report.get("cascadeHidden", 0),
            "remaining": [r["fragment"] for r in report["remainingVisible"]],
            "collateral": [c["fragment"] for c in report["collateralHidden"]],
        }

    print("\n== summary ==")
    failed = 0
    for name, s in summary.items():
        ok = s["removedAll"] and s["noCollateral"]
        failed += 0 if ok else 1
        print(f"  {name}: removedAll={s['removedAll']} noCollateral={s['noCollateral']} cascade-covered={s['cascade']}")
        for r in s["remaining"]:
            print(f"    ✗ still visible: {r[:60]}")
        for c in s["collateral"]:
            print(f"    ✗ wrongly hidden: {c[:60]}")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
