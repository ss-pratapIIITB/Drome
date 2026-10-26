# Model runtime: what MLX does, and where the wins actually are

This note explains the execution stack behind Drome's classifier, why replacing
MLX is not a useful lever, and which optimizations are worth doing. It is meant
to be shareable as-is.

## The stack in one paragraph

The classifier is a 421M-parameter Laya decision model. Its weights are an
FP16 safetensors checkpoint (~843 MB) downloaded once from Hugging Face. The
**model architecture is implemented in this repository**
(`Drome/AI/LayaMLXRuntime.swift`): a ModernBERT encoder with local/global
attention, a question-type embedding, a small decision head, and a
marker-token scorer. **MLX Swift** executes the graph — it is the tensor
library and Metal backend, not the model.

`MLX` supplies the primitives used by that code:

- `MLXArray`, lazy graph construction, and `eval()` to materialize results
- GPU kernels for matmul, attention, softmax, LayerNorm, RoPE, gathers
- unified memory: weights and activations never cross a CPU/GPU bus
- `MLXNN` modules (`Linear`, `LayerNorm`, `Embedding`, quantized variants)
- safetensors I/O (`loadArrays`), allocator cache (`Memory.cacheLimit`)

So the layer you would "write yourself" already is yours. The layer beneath it
is the engine.

## Can we replace MLX with our own library?

You cannot run MLX *on* another library — MLX *is* the library. Replacing it
means writing the engine:

| Route | What it involves | Assessment |
| --- | --- | --- |
| Custom Metal kernels | matmul (fp16/int8), attention, softmax, LayerNorm, RoPE, embedding gathers, memory planning, batching | Multi-month project, tuned against Apple's own kernels. Negative expected value. |
| MPSGraph | Lower-level graph API, manual shape management, no NN layer ergonomics | Possible, but a large port for an uncertain gain. |
| Core ML | Convert encoder + head via coremltools; ANE possible | Only worth it if ANE/low-power becomes a hard requirement. Dynamic sequence lengths, marker-position gathers, and custom attention masks would likely fall back or force fixed-shape bucketing. |
| Keep MLX, optimize the model code and batching | Quantization, tokenization caching, compilation, calibration | The actual wins. |

The rule of thumb: optimize the layer that is *specific to this app* (model
code, batching, tokenization, thresholds), not the general-purpose engine.

## Levers, ranked by expected value

### 1. Weight quantization (shipped)

Quantize the linear stack to int8 (affine, group size 64). MLX runs int8
matmul kernels and reads half the weight traffic.

- FP16 resident: ~843 MB
- int8 resident: ~460 MB (embeddings and norms stay FP16, ~9% of the checkpoint)
- Load-time cost: a one-off quantize pass (seconds), with a transient peak of
  roughly FP16 + int8 ≈ 1.3 GB. The app carries the increased-memory-limit
  entitlement, so this is safe on 8 GB devices; it is the main reason to
  eventually move quantization offline.
- Accuracy: int8 with group 64 is near-lossless for transformer inference. It
  still must be verified against the labeled fixtures (see "Validating").

The implementation is `quantize(model:groupSize:bits:filter:)` at load in
`LayaMLXRuntime.swift`, filtered to `Linear` layers. `Settings → Privacy → Laya
MLX → 8-bit weights` switches between int8 and FP16; the choice applies the next
time the model loads (relaunch).

**Pitfall found in practice:** mlx-swift's `Module.update(modules:)` cannot
rewire a module array whose *first* element is not replaced. Flattened update
paths are unflattened with `.none` gaps, and the array branch of `update`
traps (the non-throwing wrapper is `try! update(modules:verify:)`). This model's
scorer is `Sequential { LayerNorm, Linear, GELU, Linear }`, so quantizing the
whole tree crashed on load with `SIGTRAP`. The runtime now quantizes the
encoder and head subtrees (their layer arrays are uniformly updated) and
rebuilds the scorer explicitly, using the throwing `update` overload so a
failure logs and leaves those weights FP16 instead of killing the app.

### 2. Tokenization caching (shipped)

`prepare(state:question:)` used to re-encode the same question instruction and
option strings for every block, on both passes. The encoded prefix
(`[CLS] + instruction + markers + [SEP]`) and its marker positions are now
tokenized once per question kind and reused; only the page text is tokenized per
block.

### 3. Incremental rescans (shipped)

`collect()` now skips a block that already carries a verdict with a matching
fingerprint (`data-drome-safe` + `data-drome-fingerprint`). Fresh navigations
clear labels first, so they scan everything; back/forward restores keep their
labels and become effectively free. An edited block gets a new fingerprint and
is classified again. The mutation observer already worked this way.

### 4. Graph compilation

MLX Swift exposes `compile` in the pinned revision. It fuses elementwise chains
and reduces dispatch overhead, but the payoff is bounded here because the graph
is dominated by large matmuls and Swift-side tokenization. Shapes are dynamic
(batch 1–4, sequence length varies per block), so this needs shape bucketing to
avoid retracing. Benchmark it after quantization and tokenization caching, not
before.

### 5. Allocator cache

`Memory.cacheLimit` is currently 64 MB. The cache recycles activation buffers
between batches; weights are long-lived and unaffected. A larger cache can
avoid reallocation churn, but it also raises peak RSS next to a large model.
Treat it as a measured experiment (128 MB vs 256 MB vs 64 MB), not a default
change.

### 6. Batch size

Batches are capped at 4. Larger batches amortize per-batch overhead but change
how quickly the page updates during scrolling. That trade-off was deliberately
parked; it belongs to scan-latency tuning, not model math.

## Accuracy levers (separate from runtime speed)

The false positives seen on realistic news text (for example a photo caption
describing a police scene) are classifier decisions, not hiding bugs. The
mechanism correctly hides what the model flags.

- **Thresholds** — unsafe at 0.55, category at 0.70. Raising the unsafe
  threshold trades recall for precision; sweep it against labeled fixtures.
  Model verdicts vary between runs (sampling), so a sweep needs repeats.
- **Question/option wording** — the option descriptions are constants in
  `LayaMLXRuntime.swift`; sweeping them costs nothing at runtime.
- **Decision-head fine-tuning** — the head is small and sits on a frozen
  encoder. Fine-tune offline against the labeled fixtures, export safetensors,
  and load the result in place of the shipped head. This is the real path to
  fewer news-text false positives.
- **Vision screening** — alt/aria text is the current media signal. Classifying
  pixels would be a new model, not a tweak.

## Validating

- **Removal quality / accuracy** — `eval/` fixtures plus
  `python3 eval/run_removal_eval.py`. `--skip-laya` isolates extraction and
  hiding bugs; the full run drives the Python Laya model. To compare int8 vs
  FP16 verdicts directly, quantize the checkpoint in Python MLX and re-run the
  harness with that model.
- **Latency and memory on device** — the app logs per-batch latency, a
  `⏱ N blocks — tokenize X ms · model Y ms` split in the devtools console, and
  the model-load report (weight mode, quantize time, active/peak memory).
  Compare FP16 vs int8 by toggling the setting and relaunching. The Laya
  playground shows single-text latency without a page scan.
