# Laya prompt evaluation

This directory evaluates the on-device Laya classifier against labeled web
blocks and audits the DOM extraction that feeds it. It is deliberately separate
from the app target so model experiments cannot accidentally ship.

## Data

- `data/labeled_blocks.jsonl` — 84 labeled blocks (38 unsafe, 46 safe).
- Each row has `id`, `text`, `unsafe`, `category`, and `tag`.
- Labels follow the same rubric as `AIContentFilter`: content that is likely to
  make a reader anxious or that contains graphic violence, self-harm, explicit
  sexual content, alarming health claims, financial doom, urgency pressure, or
  outrage bait.
- Blocks are split deterministically into dev/test using a hash of the `id`, so
  prompt selection and threshold selection never use the test split.
- The set is small and was written as a first audit, not a benchmark. Treat the
  numbers as directional.

## Reproduce

```bash
pip install 'laya-mlx==0.5.0'
python3 eval/run_eval.py                 # all variants, ~10 minutes on an M-series Mac
python3 eval/run_eval.py --skip-model    # keyword metrics only
python3 eval/analyze_rules.py            # compare NLI / category / hybrid rules
node eval/extract_blocks.mjs --html eval/fixtures/extract-test.html
```

## Section-removal eval (mobile fixtures)

Real mobile pages (BBC article, Verge feed, Al Jazeera article) are saved with
an iPhone user agent (`eval/save_fixture.mjs`), then synthetic unsafe units
(ad urgency, doom finance, gore comments, panic health) are cloned into each
page's own card/paragraph structure (`eval/fixture_build.mjs`) with ground
truth in `fixtures/mobile/fixtures.json`.

```bash
node eval/fixture_build.mjs                        # rebuild fixtures + ground truth
python3 eval/run_removal_eval.py --skip-laya       # remove with hand labels
python3 eval/run_removal_eval.py                   # classify with Laya, then remove
```

Each fixture scores two booleans:

- `removedAll` — no unsafe unit's text is visible after hiding
- `noCollateral` — nothing visible before hiding ended up hidden beyond the
  flagged unit (cascade-hidden text inside a flagged unit is reported
  separately as `cascade-covered`)

The same `resolveSection()` in `drome-extract.js` powers the app and this
eval, unit-level hiding of flagged sections was tuned on these fixtures.

`run_eval.py` writes `results/prompt_eval.json`; `analyze_rules.py` writes
`results/decision_rules.json`. The model is `aac6fef/laya-mlx`; the first run
downloads about 843 MB.

## Results (84 blocks, threshold 0.55)

| Variant | Precision | Recall | F1 | Accuracy | Mean latency* |
| --- | ---: | ---: | ---: | ---: | ---: |
| Keyword guard only | 0.857 | 0.158 | 0.267 | 0.607 | ~0 ms |
| Baseline question | 0.833 | 0.658 | 0.735 | 0.786 | 158 ms |
| Reporting-aware question | **0.962** | 0.658 | **0.781** | **0.833** | 611 ms |
| Reader-impact question | 0.650 | 0.342 | 0.448 | 0.619 | 724 ms |
| Strict-graphic question | 0.658 | 0.658 | 0.658 | 0.691 | 978 ms |
| With examples | 0.818 | 0.237 | 0.367 | 0.631 | 902 ms |
| Short question | 0.909 | 0.263 | 0.408 | 0.655 | 810 ms |
| `block` field, report-aware | 1.000 | 0.447 | 0.618 | 0.750 | 344 ms |
| `block` field, plain state | 1.000 | 0.316 | 0.480 | 0.691 | 373 ms |
| Compact reporting | 1.000 | 0.474 | 0.643 | 0.762 | 195 ms |
| Compact flag | 0.815 | 0.579 | 0.677 | 0.750 | 614 ms |
| Outrage-aware | 0.909 | 0.526 | 0.667 | 0.762 | 1,092 ms |
| Outrage compact | 1.000 | 0.158 | 0.273 | 0.619 | 1,041 ms |

\* Latency is per block on an 8 GB Apple-silicon Mac with prompt length as the
main variable. It is useful for comparing prompts, not for predicting iPhone
performance.

## Findings

1. **The reporting-aware prompt is the best precision/recall trade-off at the
   shipping threshold.** It removes four of five false positives without losing
   recall. The extra wording costs latency because the head is longer.
2. **The compact reporting prompt is the speed option.** It keeps 100% precision
   at 0.55 but misses more unsafe blocks. Its dev-optimal threshold (0.30) gives
   F1 0.880 on dev and 0.815 on test, so a lower threshold deserves a larger
   evaluation before changing the app.
3. **The category head sees outrage and self-harm that the unsafe head misses.**
   On the saved predictions, `unsafe >= 0.55 OR (category != safe and max
   category probability >= 0.70)` raises recall from 0.658 to 0.868 with F1 0.805,
   but precision falls to 0.750 because factual violence is also categorized as
   violence. Per-category thresholds need more data.
4. **The keyword guard is fast but low-recall.** It catches 6 of 38 unsafe
   blocks and produces one false positive. It is best kept as a load-failure
   fallback and as a cheap short-block path, not as the main classifier.
5. **Longer instructions are not automatically better.** Examples and
   reader-impact phrasing both reduced recall sharply.

## Extraction audit

`eval/fixtures/extract-test.html` contains navigation, a wrapper around two
paragraphs, a hidden paragraph, a link list, a code block, an aside, and a
footer. The current `drome-extract.js` returns exactly three blocks: the
headline and the two paragraphs. Navigation, hidden text, links, code, aside,
and footer are rejected, and the wrapper is not duplicated.

On real pages the remaining risks are:

- leaf blocks with short nested blocks (rare mixed-content wrappers),
- consent dialogs and virtualized lists that mutate while scanning,
- text rendered inside canvas or images (explicitly out of scope),
- very long articles that exceed the 80-candidate cap.

## Next experiments

- Expand to 300+ blocks from real pages, with a second annotator for agreement.
- Evaluate truncation at 256/400 characters, matching the app's input cap.
- Sweep per-category thresholds for violence, self-harm, and outrage.
- Measure iPhone latency and memory for batch sizes 1, 2, and 4.
- Add a regression fixture for extraction on a saved news article and a saved
  product page.
