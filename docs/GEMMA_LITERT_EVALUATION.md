# Evaluation: Gemma via LiteRT on iOS vs. Apple Foundation Models

**Question:** Should Drome replace (or supplement) Apple Foundation Models with
Google's Gemma models running on LiteRT, and does either path support the
batch-size-10 requirement for production readiness?

**Verdict: Not worth the effort right now.** Batch-10 is achievable — and now
implemented — on Apple Foundation Models via prompt packing. Switching to Gemma
would not unlock anything batching-wise (on-device LLM runtimes are all
single-sequence), while costing a ~0.5–1.5 GB model download, 1.5–2.5 GB of
runtime memory next to an already memory-hungry WKWebView, and a second
inference stack to maintain. Gemma only makes sense later as a *fallback* for
devices without Apple Intelligence, and only if usage data shows that segment
matters.

---

## 1. The batching requirement (≥10 items per batch)

The requirement is satisfiable **without changing model stacks**. The key
insight: on-device LLM runtimes (Apple FM, LiteRT/MediaPipe, MLC, llama.cpp)
do **not** offer server-style continuous batching or multi-sequence batch
decode. "Batch size 10" on-device means **prompt packing**: 10 classification
items in one request, one structured response listing 10 verdicts.

### Feasibility math (Apple Foundation Models)

| Budget item | Tokens |
|---|---|
| Context window | 4096 |
| System instructions | ~100 |
| 10 items × 400 chars (~130 tokens each) | ~1300 |
| Structured output (10 × `{item, safe, reason}`) | ~300 |
| **Total** | **~1700 — fits with >2× headroom** |

This is now implemented in `AIContentFilter` (`aiBatchSize = 10`):

- One `LanguageModelSession` per batch, numbered `ITEM n:` prompt, and a
  `@Generable` array response (`BatchContentSafetyResult`).
- A 40-block page previously cost **40 sequential model calls** (each paying
  session setup + instruction prefill); it now costs **≤4** — instructions are
  prefilled once per 10 items instead of once per item. Expect roughly an
  order-of-magnitude reduction in end-to-end classification time.
- Fallback ladder: context overflow → split batch in half and retry;
  guardrail violation → reclassify that batch's items individually (one
  sensitive item no longer taints its batch-mates); other errors → keyword
  heuristics.
- Live DOM mutations flow through the same batched path (up to 30 per
  debounce window = 3 model calls).

**Conclusion: the "can't finalize unless batch ≥ 10" blocker is cleared on the
current Apple stack.**

## 2. Gemma on iOS: what actually exists

The supported route is Google's **MediaPipe LLM Inference API**
(`MediaPipeTasksGenAI` pod), which runs on LiteRT (the TensorFlow Lite
successor). Status for iOS:

| Model | Size (int4) | iOS support | Notes |
|---|---|---|---|
| Gemma-3 1B | ~530 MB | ✅ | The only realistic candidate for a browser app |
| Gemma-2 2B | ~1.3 GB | ✅ | Better quality; heavy download + memory |
| Gemma 3n (E2B/E4B) | 2–4 GB | ⚠️ Android/LiteRT-LM first | iOS support lags |
| Phi-2 / Falcon-1B / StableLM-3B | ~1–2 GB | ✅ | No advantage over Gemma here |

Practical constraints:

- **Delivery:** models can't ship in the app bundle (App Store size limits);
  you need a post-install download flow, resumable transfer, and storage
  management for 0.5–1.3 GB.
- **Memory:** ~1–1.5 GB peak for Gemma-3 1B int4. Combined with multiple
  WKWebView tabs, this flirts with jetsam limits on 6 GB iPhones.
- **Compute:** LiteRT runs on CPU/GPU (XNNPack/Metal). Apple FM runs on the
  Neural Engine — faster prefill, dramatically better battery/thermals for a
  filter that fires on *every page load*.
- **Batching:** the LLM Inference API is single-prompt, single-sequence — the
  same prompt-packing technique is the only way to "batch," so Gemma gains
  nothing on the requirement that motivated this evaluation.
- **Licensing:** Gemma's Terms of Use require flow-down of use restrictions to
  end users — extra legal/App Review surface.
- **Quality:** classification quality of Gemma-3 1B vs. Apple's ~3B FM for
  this binary safe/unsafe task would need a proper eval set; a 1B model is
  unlikely to beat it.

## 3. Comparison for Drome's use case

| Criterion | Apple FM (current) | Gemma-3 1B via LiteRT |
|---|---|---|
| App size / download | +0 | +~50 MB framework, +530 MB model |
| Runtime memory | Managed by OS (shared system model) | ~1–1.5 GB in-process |
| Hardware | Neural Engine | CPU/GPU |
| Batch ≥10 | ✅ prompt packing (implemented) | Same technique, no advantage |
| Device coverage | iPhone 15 Pro+ / M-series, iOS 26+, Apple Intelligence on | Any recent iPhone, iOS 15+ |
| Privacy | On-device | On-device |
| Guardrails | Built-in (occasionally refuses) | None (must build own) |
| Maintenance | Zero model ops | Model downloads, updates, second code path |

## 4. Recommendation

1. **Keep Apple Foundation Models as the primary classifier** with the new
   batch-of-10 pipeline. This clears the production-readiness bar.
2. **Keep the keyword heuristic as the universal fallback** (it already covers
   iOS < 26 and non-Apple-Intelligence devices at zero cost).
3. **Defer Gemma.** Revisit only if analytics show a significant share of
   users on devices without Apple Intelligence *and* the keyword fallback
   measurably underperforms. The integration path at that point:
   - Add `MediaPipeTasksGenAI` via SwiftPM/CocoaPods.
   - Download `gemma3-1b-it-int4.task` on first enable (Wi-Fi only, with
     user consent), store in Application Support.
   - Implement the classifier behind the same batch interface
     (`classifyBatch(texts:) -> [(Bool, String)]`) that `AIContentFilter`
     uses internally, with the same numbered-ITEM prompt packing.
   - Gate on ≥6 GB RAM devices and unload the model under memory pressure.
