# Drome — iOS Browser

A full-featured iOS browser built on WKWebView with developer tools, ad blocking, website blocking, and an on-device AI content filter powered by Apple Foundation Models.

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
- **AI Content Filter** — uses Apple Foundation Models (iOS 26+) to identify and remove offensive/spam content from pages. Falls back to a keyword heuristic on older iOS.
  - Runs Mozilla's Readability scoring to find meaningful text blocks
  - Classifies blocks in **batches of 10 per model request** (structured array output — a 40-block page costs ≤4 model calls, private, no network)
  - See `docs/GEMMA_LITERT_EVALUATION.md` for why Apple FM + batching was chosen over Gemma/LiteRT
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
3. Set deployment target to **iOS 18.0** (iOS 26.0 for Foundation Models)
4. Delete the generated `ContentView.swift`
5. Drag all `.swift` files from this directory into the Xcode project, maintaining the group structure
6. Add the two `.js` files to the project target:
   - `Drome/JavaScript/drome-bridge.js`
   - `Drome/JavaScript/drome-readability.js`
   - In the file inspector, ensure **Target Membership → Drome** is checked so they are included in the bundle
7. Build and run on device or simulator

## Foundation Models (iOS 26)

The AI filter is fully wired up. To activate it once the iOS 26 SDK ships:

1. Add `import FoundationModels` at the top of `AIContentFilter.swift`
2. Uncomment the `classifyWithFoundationModels` implementation block
3. The model requires a device with Apple Intelligence (iPhone 15 Pro+, iPhone 16+, or iPad with M-series chip)
4. Users must have Apple Intelligence enabled in Settings → Apple Intelligence & Siri

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
    → AIContentFilter.analyzeAndLabel(webView:)
      → JS: extract text blocks via Readability scoring
      → Swift: keyword pre-filter resolves cheap cases
      → Swift: remaining blocks → Foundation Models, 10 per request (batched)
      → JS: one label-update call per batch
      → JS: fade out + remove flagged elements
```

## How the AI Filter Works

Mozilla's Readability algorithm scores DOM elements by paragraph density and link ratio to find meaningful content (same algorithm Firefox Reader Mode uses). The filter then:

1. Walks all text nodes, skipping scripts/styles/hidden elements
2. For each text block ≥30 chars, records its text + XPath
3. Sends batches to the on-device language model with a classification prompt
4. For `"remove": true` responses, uses a second JS pass to walk *up* the DOM from the text node, stopping at the first ancestor whose text content is more than 1.8× the flagged block — that's the smallest meaningful container
5. All flagged containers are deduplicated (if a parent is already marked, skip its children), then faded out with CSS transition and removed

This means an offensive paragraph inside an otherwise-fine article won't take the whole article down — just the paragraph's card/div wrapper.
