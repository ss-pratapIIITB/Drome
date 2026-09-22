# Drome — iOS Browser

A full-featured iOS browser built on WKWebView with developer tools, ad blocking, website blocking, and a fully on-device AI content filter powered by Laya MLX Swift.

## Features

- **Multi-tab browsing** with tab grid and snapshots
- **Ad blocking** via WKContentRuleList (EasyList-derived, ~55 rules)
- **Website blocker** — block any domain + all its subdomains
- **Developer Tools** panel (drag to resize):
  - Console — live JS log/warn/error interception with filtering
  - Network — fetch + XHR request/response monitoring with detail view
  - Elements — live DOM tree inspector
  - Storage — localStorage / sessionStorage viewer
  - Cookies — full cookie inspector
  - JS REPL — evaluate JS in the page context from within the app
- **AI Content Filter** — uses Laya MLX typed decisions directly on the iPhone to identify and remove anxiety-triggering/offensive content. Falls back to a keyword heuristic if the model cannot load.
  - Runs Mozilla's Readability scoring to find meaningful text blocks
  - Runs the 421M-parameter FP16 model with MLX Swift on the Apple GPU
  - Downloads the ~843 MB checkpoint once; page content never leaves the device
  - Finds the *smallest* DOM container wrapping the flagged content and removes it
- **Forced dark mode** via CSS invert injection
- **Custom user agent** with common presets (desktop Safari, Chrome, Firefox, Googlebot)
- **Pluggable search engine** (DuckDuckGo default, Google, Bing, Brave, Ecosia, Startpage)
- **File downloads** via WKDownloadDelegate
- **Safari Remote Web Inspector** support (`isInspectable = true`)
- Pop-up blocking, JavaScript toggle, Reader-mode-ready architecture

## Setup in Xcode

1. Open Xcode → **File → New → Project** → iOS App
2. Product Name: **Drome**, Interface: **SwiftUI**, Language: **Swift**
3. Set deployment target to **iOS 18.0**
4. Delete the generated `ContentView.swift`
5. Drag all `.swift` files from this directory into the Xcode project, maintaining the group structure
6. Add the two `.js` files to the project target:
   - `Drome/JavaScript/drome-bridge.js`
   - `Drome/JavaScript/drome-readability.js`
   - In the file inspector, ensure **Target Membership → Drome** is checked so they are included in the bundle
7. Build and run on device or simulator

## Laya MLX Swift

The native Swift port mirrors Laya's ModernBERT encoder, decision transformer,
marker-token scoring head, prompt construction, and probability calibration.
The first AI analysis downloads `aac6fef/laya-mlx` from Hugging Face; subsequent
inference is offline and fully on-device.

See [`docs/laya-mlx-swift.md`](docs/laya-mlx-swift.md) for model size, runtime
requirements, and the required cross-runtime fidelity validation.

## Architecture

```
DromeApp
└── ContentView (EnvironmentObject: BrowserViewModel)
    ├── BrowserView
    │   ├── AddressBarView       — URL bar, progress, security indicator, share
    │   ├── DromeWebView         — UIViewRepresentable → WKWebView
    │   │   └── WebViewCoordinator
    │   │       ├── WKNavigationDelegate  — blocking, progress, snapshots, AI trigger
    │   │       ├── WKUIDelegate          — alerts, popups
    │   │       ├── WKScriptMessageHandler — console + network events from JS
    │   │       └── WKDownloadDelegate    — file downloads
    │   ├── DeveloperToolsView   — resizable bottom panel
    │   └── BottomToolbarView    — back/forward/tabs/devtools/settings
    ├── TabGridView              — tab overview with screenshots
    ├── SettingsView             — all toggles and options
    └── WebsiteBlockerView       — blocked domains list

AI Pipeline (per page load):
  WebViewCoordinator.didFinish
    → AIContentFilter.analyzeAndFilter(webView:)
      → JS: extract text blocks via Readability scoring
      → Swift: classify each block (Laya MLX / heuristic)
      → JS: find smallest containing DOM element for flagged blocks
      → JS: fade out + remove flagged elements
```

## How the AI Filter Works

Mozilla's Readability algorithm scores DOM elements by paragraph density and link ratio to find meaningful content (same algorithm Firefox Reader Mode uses). The filter then:

1. Walks all text nodes, skipping scripts/styles/hidden elements
2. For each text block ≥30 chars, records its text + XPath
3. Runs two typed decisions per qualifying block with Laya MLX Swift on-device
4. For `"remove": true` responses, uses a second JS pass to walk *up* the DOM from the text node, stopping at the first ancestor whose text content is more than 1.8× the flagged block — that's the smallest meaningful container
5. All flagged containers are deduplicated (if a parent is already marked, skip its children), then faded out with CSS transition and removed

This means an offensive paragraph inside an otherwise-fine article won't take the whole article down — just the paragraph's card/div wrapper.
