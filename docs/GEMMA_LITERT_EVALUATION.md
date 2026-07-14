# Evaluation v2: Apple Foundation Models vs. Gemma on LiteRT (iOS)

**Revised after review.** Two concerns were raised against the v1 conclusion
("stay on Apple FM"): Apple Intelligence is **unreliable** for this workload,
and its **4096-token context** is small for batching. Both concerns are
valid — and the LiteRT landscape has improved materially. This revision
compares the actual LiteRT model lineup with per-device RAM budgets in mind.

**Revised verdict:** Keep the batched Apple FM pipeline as the shipping
default (it costs 0 bytes and 0 RAM), but the Gemma path is now credible and
should be prototyped behind a flag. The strongest production endgame for this
specific feature is a **fine-tuned Gemma 3 270M classifier (~300 MB)** — it
fits every device Drome supports, has no guardrails to fight, and removes the
Apple Intelligence availability gate entirely.

---

## 1. Validating the two concerns about Apple FM

### Reliability — confirmed, and worse for *this* workload than most
- Drome's filter classifies text about violence, disasters, death, and health
  crises. That is exactly the content Apple's guardrails are trained to
  refuse. Developer reports show `guardrailViolation` firing on innocuous
  prompts (some apps see >50% refusal rates in sensitive-adjacent domains);
  iOS 26.4 reduced false positives but did not eliminate them, and iOS 27
  betas show refusal regressions on previously working prompts.
- Our code already carries the scar tissue: refusal → "mark unsafe" is a
  guess, and a guardrail refusal on a *batch* poisons 10 items at once
  (mitigated by per-item retry, which forfeits the batching win exactly when
  the page is most sensitive — i.e., when the filter matters most).
- Availability is gated three ways: supported hardware (8 GB / A17 Pro+),
  iOS 26+, and the user having Apple Intelligence enabled with the model
  downloaded. `SystemLanguageModel.default.availability` can flip at any time
  (low battery, storage pressure, model update in progress).
- Behavior drifts with OS updates — we don't pin the model.

### Input size — confirmed
- Apple FM: **4096 tokens total** (instructions + prompt + output share it).
  Practical batch ceiling at ~130 tokens/item: **~10–15 items**, ~20 absolute.
- Gemma 3 1B: **32k-token architecture**. Prebuilt on-device bundles ship
  with 1.2k–4k KV-cache configs, but the cache is configurable at build time,
  and Gemma 3's mostly-local (sliding-window) attention keeps KV memory small
  — 8k–16k configs are realistic on-device, i.e. **40–100+ items per prompt**.

One important nuance: on-device runtimes decode a single sequence, so a
bigger context means *fewer requests*, not faster tokens. Throughput is
decode-bound (~25–57 tok/s), and structured verdicts cost ~25–30 output
tokens per item. Beyond ~10–20 items per request, batching returns diminish —
the 4k window is an annoyance, not the bottleneck.

## 2. What changed in the LiteRT ecosystem

- **MediaPipe LLM Inference API is in maintenance mode.** The successor is
  **LiteRT-LM**, which has native iOS/macOS integration with Metal GPU
  acceleration and a Swift API — currently **Early Preview** (fine for a
  prototype flag, not yet for the App Store default path).
- Google publishes **iPhone 17 Pro benchmarks** for LiteRT-LM, and the
  runtime memory-maps weights aggressively (Gemma 4 E2B is a 2.58 GB file but
  peaks at ~607 MB physical on Apple CPU).

## 3. LiteRT model lineup (iOS-relevant, July 2026)

| Model | Download | Context (arch / shipped) | Peak RAM | iPhone 17 Pro perf | Fit for Drome |
|---|---|---|---|---|---|
| **Gemma 3 270M** (int4) | ~300 MB | 32k / configurable | ~400–550 MB | not published; ~4× faster than 1B | ⭐ Best with fine-tuning — built for task-specific classification |
| **Gemma 3 1B** (int4) | 529 MB–1 GB | 32k / 1.2k–4k prebuilt | GPU ~530–1740 MB · CPU ~1–1.5 GB | (S25 Ultra ref: 2585 tk/s prefill, 56 tk/s decode GPU) | ⭐ Best zero-shot quality/RAM balance |
| Gemma 4 E2B | 2.58 GB | large | CPU **607 MB** (mmap) · GPU 1.45 GB | CPU 532/25 tk/s · GPU 2878/57 tk/s, TTFT 0.3 s GPU | Overkill; 2.6 GB download is hostile |
| Gemma 4 E4B | 3.65 GB | large | higher | CPU 159/10 · GPU 1189/25 tk/s | No |
| Gemma 3n E2B/E4B | 3–4.2 GB | large | high | — | No — multimodal weight we don't need |

## 4. The RAM reality (the deciding constraint)

Per-app Jetsam limits are roughly half of device RAM (~4 GB app footprint on
an 8 GB iPhone 16 Pro, ~2 GB on 4 GB devices). Two browser-specific notes:
WKWebView page content lives in separate WebContent processes, so a model in
the app process doesn't directly steal tab memory — but it raises
*device-wide* pressure, which evicts background tabs (white-flash reloads)
and degrades exactly the multi-tab experience a browser sells.

| Device class | RAM | ~app budget | Apple FM available? | Which Gemma fits |
|---|---|---|---|---|
| iPhone SE3 / 11 | 4 GB | ~2 GB | ❌ | 270M only |
| iPhone 12–15 / Plus | 6 GB | ~3 GB | ❌ | 270M comfortably; 1B-int4 (GPU) workable but taxes multi-tab |
| iPhone 15 Pro – 17 / 16e | 8 GB | ~4 GB | ✅ | 1B easily; E2B OK |
| iPhone 17 Pro / Air | 12 GB | ~6 GB | ✅ | any |

**The RAM irony:** the devices that *lack* Apple FM (4–6 GB class) are
precisely the devices where a 1 GB+ resident model hurts most. Gemma 3 1B is
comfortable only on hardware that already has Apple FM. The only model that
fits the FM-less cohort well is **Gemma 3 270M** — which zero-shot is too
weak for nuanced safety judgments and really wants a LoRA fine-tune (that is
its designed use case: high-volume, well-defined classification).

## 5. Head-to-head for Drome's classifier

| Criterion | Apple FM (shipped) | Gemma 3 1B / LiteRT | Gemma 3 270M fine-tuned / LiteRT |
|---|---|---|---|
| Batch ≥10 per request | ✅ 10–15 (4k cap) | ✅ 10–100+ (configurable ctx) | ✅ same, and fastest per item |
| Refusals / guardrails | ❌ refuses our exact content domain | ✅ none | ✅ none |
| Availability | ❌ device+OS+setting gated, can flip anytime | ✅ deterministic once downloaded | ✅ deterministic |
| Version stability | ❌ drifts with OS | ✅ pinned model file | ✅ pinned |
| Structured output | ✅ `@Generable` guarantees schema | ⚠️ prompt-and-parse JSON, must validate+retry | ⚠️ same (or emit single logit-like label, trivial to parse) |
| App RAM cost | ✅ ~0 (system-hosted) | ❌ 0.5–1.5 GB in-process | ✅ ~0.5 GB |
| Download cost | ✅ 0 | ❌ ~530 MB–1 GB | ⚠️ ~300 MB |
| Device coverage | ❌ 8 GB/iOS 26/AI-on only | ⚠️ 8 GB well; 6 GB marginal | ✅ everything incl. 4 GB |
| Zero-shot accuracy | Good (~3B, but refusal noise) | Decent (1B) | ❌ needs fine-tune + eval set |
| iOS SDK maturity | ✅ GA | ⚠️ LiteRT-LM Swift = Early Preview (MediaPipe route = maintenance mode) | same |
| Battery/thermals | ✅ ANE | ⚠️ GPU/CPU | ✅ tiny |

## 6. Revised recommendation

1. **Now:** ship the batched Apple FM pipeline (done). It's free, and the
   fallback ladder contains the guardrail damage.
2. **Next:** build a small eval set (~500 labeled real page blocks) — nothing
   below can be "finalised" without it, and it will also quantify how often FM
   guardrails misfire on real browsing.
3. **Prototype (flagged):** Gemma 3 1B int4 on the LiteRT-LM Swift preview,
   GPU backend, 8 GB+ devices only. Same numbered-ITEM prompt packing at
   10–20 items; JSON parse with one reformat retry. Compare accuracy, P95
   latency, and page-load memory pressure against FM on the eval set.
4. **Production endgame (if eval supports it):** LoRA-fine-tune **Gemma 3
   270M** on the eval set as a dedicated safe/unsafe classifier. ~300 MB
   Wi-Fi download with consent, ~0.5 GB peak RAM, runs on every device, no
   guardrails, no availability gate — one code path replaces FM, and the
   keyword heuristic demotes to a pre-filter only.
5. Keep the keyword pre-filter permanently — it's free and catches the
   obvious cases before any model runs.

### Sources
- LiteRT-LM overview + iPhone 17 Pro benchmarks: developers.google.com/edge/litert-lm/overview
- Gemma3-1B-IT LiteRT bundle sizes/benchmarks: huggingface.co/litert-community/Gemma3-1B-IT
- MediaPipe LLM Inference (maintenance-mode notice): ai.google.dev/edge/mediapipe/solutions/genai/llm_inference
- Apple FM 4096-token window + iOS 26.4 context management: infoq.com/news/2026/03/apple-foundation-models-context/
- FM guardrail false-positive reports: developer.apple.com/forums/thread/787736, thread/792908; drobinin.com (shipping FM in real apps)
- Jetsam per-app limits: developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports; developer forums thread/688973
