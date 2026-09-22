# Laya MLX evaluation for Drome

## Decision

Use Laya MLX as Drome's local typed-decision backend, behind a small HTTP
bridge. Remove the Apple Foundation Models dependency and retain the existing
keyword classifier as the zero-setup fallback and hard safety override.

## Why it fits

- Laya produces constrained choices and probabilities without token-by-token
  generation, which matches Drome's safe/unsafe classification task.
- The published M3 Max results are 7–14 ms for one short decision after model
  loading. Drome asks two decisions per text block: unsafe probability and
  category.
- The model and inference stay local and require no cloud API.
- The Apache-2.0 runtime is straightforward to run as a development service.

## Important limitation

`laya-mlx` 0.1.x is a Python 3.11+ package for macOS 14+ on Apple Silicon. It
is not an iOS Swift package and cannot run inside Drome on an iPhone as
published. In this branch, "local" means a Laya process on the same Mac when
using Simulator, or on a Mac reachable over the user's trusted LAN when using
a physical iPhone. A true phone-only release needs a separate Core ML or
MLX-Swift port of the model architecture and weights.

## Run

On an Apple-Silicon Mac:

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python laya_server.py
```

The first run downloads the checkpoint. Later runs are local. Drome Simulator
uses `http://127.0.0.1:8765` by default.

For a physical iPhone, start the service on the LAN interface:

```bash
python laya_server.py --host 0.0.0.0
```

Then open Drome Settings → Laya MLX and enter the Mac's LAN URL, such as
`http://192.168.1.10:8765`. Only use this development service on a trusted
network; it intentionally has no public-internet authentication layer.

## Follow-up for true iPhone inference

1. Reimplement Laya's ModernBERT/mmBERT encoder and decision heads in
   MLX-Swift or convert them to Core ML.
2. Validate selected-answer fidelity against the upstream fixtures.
3. Quantize and measure memory, cold-start, thermal behavior, and latency on
   the oldest supported iPhone.
4. Bundle or securely download the checkpoint with integrity verification.
