# Laya MLX Swift in Drome

Drome runs the Laya 421M typed-decision model directly on the iPhone with MLX
Swift. There is no Python process, local server, Apple Intelligence dependency,
or cloud inference API.

## Runtime flow

1. The first content-analysis request downloads `aac6fef/laya-mlx` from
   Hugging Face into the app's cache. The FP16 weights are 842,609,225 bytes.
2. Swift Transformers loads the checkpoint tokenizer.
3. The native Swift port builds Laya's ModernBERT encoder and decision head,
   then loads the published safetensors checkpoint without changing its tensor
   layout.
4. Drome asks two typed questions for every qualifying text block: an unsafe
   probability and a safety category.
5. MLX evaluates both questions together on the Apple GPU. The existing
   keyword classifier remains a hard override and load-failure fallback.

After the first download, inference is fully local and page text never leaves
the device.

## Requirements

- iOS 18 or later
- An Apple-silicon iPhone capable of holding approximately 1 GB of model and
  working memory; iPhone 15 Pro or newer is the practical baseline
- Approximately 850 MB of free storage for the checkpoint

The published Laya timings are macOS M3 Max measurements, not iPhone claims.
Measure cold load, peak memory, P50/P95 inference, and thermal behavior on each
supported device before shipping.

## Fidelity validation

The Swift model mirrors `laya-mlx`'s:

- ModernBERT token embedding, local/global RoPE attention, gated GELU MLPs,
  first-layer normalization exception, and final normalization
- two-layer decision transformer
- marker-token scoring head
- prompt construction, per-option truncation, and calibrated temperatures

Before release, run the upstream validation fixtures against both Python and
Swift using the same checkpoint. Selected labels must match and probability
error should be recorded. This repository cannot perform that GPU comparison
in Linux CI because MLX iOS execution requires Apple hardware.
