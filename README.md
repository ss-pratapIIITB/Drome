# Drome

**An iOS browser with a fully on-device AI content filter.**

Drome pairs a real WKWebView browser — tabs, developer tools, blockers, downloads — with a native Swift port of a 421M-parameter decision model running on MLX. Page text is classified locally on the Apple GPU. There is no cloud inference, no API key, no Python process, and no Apple Intelligence dependency.

[![CI](https://github.com/ss-pratapIIITB/Drome/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ss-pratapIIITB/Drome/actions/workflows/ci.yml)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-0A84FF)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138)
![MLX Swift](https://img.shields.io/badge/MLX-Swift-5EEAD4)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)

![Drome architecture](docs/assets/architecture.svg)

## Highlights

- **Native MLX model port** — ModernBERT encoder, two-layer decision transformer, marker-token scoring head, prompt construction, and calibrated temperatures implemented in Swift.
- **On-device by construction** — the 843 MB FP16 checkpoint downloads once; inference is local and page text never leaves the phone.
- **DOM-aware removal** — finds the smallest container around flagged text, so one bad paragraph does not take down the whole article.
- **Cancellation-aware scanning** — queued work is dropped and late results are rejected when the page changes or the tab loses focus.
- **Incremental rescans** — mutation observers pick up expanded or dynamically loaded content without reclassifying unchanged blocks.
- **A real browser around it** — multi-tab browsing, snapshots, ad/tracker blocking, website blocking, dark mode, custom user agents, downloads, and a resizable developer-tools panel.

## Why this project exists

Most "AI in an app" demos call a remote endpoint. Drome is an exercise in the harder version: shipping a language model inside the app, on hardware you do not control, while keeping the UI responsive.

The interesting engineering is not the prompt. It is the memory budget, the tensor layout, the tokenizer special tokens, the calibration temperatures, the cancellation semantics, and the DOM strategy that turns a classifier's decision into a minimal, reversible visual change.

## Demo

A 90-second recording plan — including the reversible hide, the Laya playground, and the airplane-mode proof — is in [`docs/demo.md`](docs/demo.md). The same document lists the screenshots and GIF the repository should carry.

## Install

The app is not on the App Store. Build it from source or sideload a signed copy:

- **[Installation and sideloading guide](docs/install.md)** — Xcode, Sideloadly, and AltStore/SideStore paths, including free-Apple-ID limitations.
- **Unsigned IPA** — every `v*` tag produces an unsigned IPA artifact in GitHub Actions; sign it with your own Apple ID before installing.

Requirements: iOS 18 or later, an Apple-silicon iPhone (iPhone 15 Pro or newer is the practical baseline for the model), and about 1 GB of free storage.

## Architecture

```
DromeApp
└── ContentView (BrowserViewModel)
    ├── BrowserView
    │   ├── AddressBarView
    │   ├── DromeWebView ── WebViewCoordinator
    │   │                    ├── navigation, progress, snapshots
    │   │                    ├── console + network message bridge
    │   │                    ├── downloads
    │   │                    └── AI scan trigger
    │   ├── DeveloperToolsView
    │   └── BottomToolbarView
    ├── TabGridView
    ├── SettingsView
    └── WebsiteBlockerView

AI pipeline (per visible page):
  WebViewCoordinator.didFinish
    → PageScanSession            (cancellation, dedupe, bounded batches)
    → drome-readability.js       (Readability scoring, text + XPath)
    → AIContentFilter            (keyword guard + Laya classification)
    → LayaMLXRuntime             (actor-isolated MLX inference on GPU)
    → drome-bridge.js            (smallest container, reversible hide)
```

See [`docs/laya-mlx-swift.md`](docs/laya-mlx-swift.md) for the model port, runtime requirements, and the fidelity-validation plan.

## How the filter works

1. Mozilla Readability-style scoring finds meaningful text blocks on the page.
2. Qualifying blocks are queued in `PageScanSession` with a stable ID and content fingerprint.
3. A keyword guard handles short blocks and provides a fallback if the model cannot load.
4. Laya evaluates two typed questions per block — unsafe probability and safety category — in a single GPU batch.
5. Flagged blocks are mapped back to the smallest DOM container that is at most 1.8× the block's text.
6. Matching containers are deduplicated, faded out, and can be restored by toggling **Hide Unsafe Content** without reloading the page.

## Branch history

The repository keeps both AI implementations so the evolution is visible.

| Ref | What it is |
| --- | --- |
| `main` | Current implementation. Laya 421M decision model running natively on MLX Swift. |
| `apple-foundation-models` | Archived first implementation using Apple Foundation Models (iOS 26), with a keyword fallback. Also tagged `v0.1.0-apple-foundation-models`. |
| `feature/laya-mlx-backend` | Earlier MLX backend integration point, retained for comparison. |
| `claude/app-perf-gemma-eval-9oiqig` | Archived research branch exploring batching and Gemma/LiteRT evaluation. |

The Apple Foundation Models work is not dead code — it is the baseline this project is measured against.

## Build from source

```bash
git clone https://github.com/ss-pratapIIITB/Drome.git
cd Drome
xcodegen generate          # project.yml is the source of truth
open Drome.xcodeproj
```

In Xcode, select the `Drome` target, set your development team and a unique bundle identifier, then run on a device. If you are using a free Apple ID, switch **Code Signing Entitlements** from `Drome/Drome.entitlements` to `Drome/Drome.Sideload.entitlements`; the increased-memory entitlement is not available to personal teams. See [`docs/install.md`](docs/install.md).

To produce an unsigned IPA:

```bash
./scripts/build-ipa.sh
```

## Testing

```bash
./scripts/run-tests.sh
```

The suite covers page-scan cancellation and deduplication, JavaScript injection contracts, and the keyword/fallback path of the content filter. CI builds every pull request and runs the tests on an iOS simulator.

## Performance

- 421M parameters, FP16, 842,609,225-byte checkpoint.
- Model load and inference run on the Apple GPU through MLX.
- Latency, peak memory, and thermal behavior vary by device; measure on your target hardware before making claims. `docs/laya-mlx-swift.md` lists the metrics to capture.

## Privacy and limitations

- After the first model download, page text is classified on-device and is never uploaded by the app.
- The model is a research artifact, not a clinical or child-safety guarantee. False positives and false negatives are expected.
- The filter is off by default until enabled in Settings → Privacy.
- Only visible, qualifying text blocks are scanned; images, video, and canvas content are out of scope.
- The Laya MLX checkpoint is downloaded from Hugging Face at runtime and its metadata lists Apache-2.0. Review the model card before redistribution.

## License

Apache-2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Drome builds on [MLX Swift](https://github.com/ml-explore/mlx-swift), [swift-transformers](https://github.com/huggingface/swift-transformers), Mozilla's Readability algorithm, and the [Laya](https://huggingface.co/aac6fef/laya-mlx) model.
