# Performance review and fast-path changes

This pass looked at the startup, navigation, AI scan, DOM extraction, bridge, and
SwiftUI update paths. The goal was to remove work that is repeated, synchronous,
or unbounded before touching the UI.

## Findings

### Startup and navigation

1. **Blank tabs created a full `WKWebView` immediately.** `BrowserView` always
   rendered `DromeWebView` for the current tab, so `NewTabView` was unreachable
   and every new tab paid WebKit setup and memory cost before a URL existed.
2. **Ad-block rules were recompiled on every launch.** `ContentBlocker` only
   cached the compiled rule list in memory. Each launch called
   `compileContentRuleList` again even though WebKit persists compiled lists.
3. **The page snapshot was taken on every `didFinish`.** `takeSnapshot` renders
   the page a second time. The tab grid is the only consumer.
4. **Favicons used `Data(contentsOf:)`.** No timeout, no HTTP cache, and a
   blocking read on a cooperative thread.
5. **The readability script was injected into every page but unused by the AI
   pipeline.** The app's extraction is `JavaScriptInjector.extractContentBlocksJS`,
   not the Readability script. The extra document-end script was pure overhead.

### AI scan

6. **Each block was classified in a separate model call.** A 40-block page meant
   40 sequential encoder passes, even though the model and MLX support batching.
7. **The category question ran for every block.** The category is only needed to
   explain an unsafe result. Safe blocks (the majority) paid for it.
8. **Every label update was a separate `evaluateJavaScript` round trip.** Up to
   two JavaScript calls per block (pending, then result).
9. **The extraction walk called `getComputedStyle` and `getClientRects` for the
   same elements repeatedly,** and nested block wrappers could produce duplicate
   text candidates.
10. **The mutation observer rescanned whole subtrees on every mutation batch.**
    It also observed `class`/`style` changes, which the AI labels themselves
    trigger.

### Bridge and UI

11. **`fetch` was wrapped with `res.clone().text()`.** That buffers every
    response body a second time just to report a byte count. On large responses
    it doubles memory and delays the page's own consumer.
12. **XHR logging read `responseText` unconditionally.** That throws for binary
    responses and forces string conversion for non-text types.
13. **Console formatting stringified full objects.** Large or circular objects
    could stall the page and flood the Swift side.
14. **The bridge was injected into iframes.** Ad-heavy pages paid interception
    cost in every frame, while AI extraction only runs in the main frame.
15. **`AddressBarView` and `BottomToolbarView` did not observe `BrowserTab`.**
    `isLoading`, `estimatedProgress`, `canGoBack`, and `canGoForward` changes did
    not reliably refresh those views.
16. **KVO was registered manually on every navigation start.** A missed
    `removeObserver` (for example, overlapping fail/finish callbacks) could crash
    with "observer is not registered".
17. **Dark mode sent the bridge source instead of the dark-mode CSS** in
    `updateUIView`, so the style path and the source of truth disagreed.

## Changes in this pass

- `BrowserView` shows `NewTabView` until the tab has a URL, and `DromeWebView`
  is created lazily. Closing/creating blank tabs no longer creates a WebKit
  process.
- `ContentBlocker` looks up WebKit's persisted rule list before compiling,
  and deduplicates concurrent loads with a shared task.
- `AIContentFilter` and `LayaMLXRuntime` classify in batches. The unsafe
  question runs first; the category question runs only for flagged blocks.
- `WebViewCoordinator` drains batches of four, applies all labels from a batch
  in one JavaScript call, and uses a single `NSKeyValueObservation` token that
  is invalidated on finish/fail.
- `drome-extract.js` is a shared leaf-block extractor with per-run visibility
  caching, wrapper suppression, link-density filtering, source-order
  deduplication, and an 80-candidate cap. The initial scan and mutation observer
  use the same code.
- `drome-bridge.js` uses `Content-Length` for fetch responses, reads XHR size
  only for compatible response types, truncates console lines, and is injected
  in the main frame only.
- Tab snapshots are captured when the tab grid opens, not after every load.
- Favicons use `URLSession` with a five-second timeout and HTTP caching.
- `AddressBarView` and `BottomToolbarView` now observe the current `BrowserTab`.
- Dark mode has one code path (`applyDarkMode`) and is re-applied after
  navigation.

## Assumptions

- **Batch size 4.** This keeps activation memory conservative on 8 GB iPhones.
  The Python evaluation batch of 8 is not evidence that 8 is safe on device.
  Devices with 6 GB should be tested at 2.
- **Main-frame devtools.** Console and network capture now cover the main frame.
  Cross-frame logging can return later behind an explicit setting.
- **Snapshots are lazy.** A tab card may show a placeholder until the grid is
  opened after a navigation. This is preferable to rendering every page twice.
- **No prompt or threshold change yet.** The evaluation found a better
  reporting-aware prompt, but the shipping prompt stays at 0.55 until a larger
  labeled set confirms the gain.
- **No visual redesign in this pass.** The UI plan below is intentionally
  separate from the correctness/performance work.

## Expected impact

- First launch: one fewer WebKit creation for the initial blank tab, and a
  disk lookup instead of a rule-list compile.
- Every page load: no unused Readability parse, no full-page snapshot, no
  iframe instrumentation.
- Every scan: four blocks per model call instead of one, one label JS call per
  batch instead of two per block, and no category pass for safe blocks.
- Memory: no response-body clone, no pre-created WebView for blank tabs.

## Validation plan

1. CI build and unit tests (including the new batch-order test).
2. Run the extraction fixture and a real article through
   `eval/extract_blocks.mjs`; inspect duplicate and boilerplate counts.
3. On an iPhone, measure time-to-first-content, time-to-first-label,
   time-to-complete scan, and peak memory for batch sizes 1, 2, and 4.
4. Add `os_signpost` intervals around extraction, model load, each batch, and
   label application before optimizing further.
5. Re-run `eval/run_eval.py` after any prompt/threshold change.

## Remaining risks

- MLX batch memory on 6 GB devices is unmeasured.
- Leaf-block extraction can still miss mixed-content wrappers and virtualized
  lists.
- The bridge still intercepts every fetch/XHR on the main frame; a "DevTools
  off" fast path would remove that cost entirely.
- The 843 MB model download remains the dominant first-run cost. A prewarm or
  download-on-Wi-Fi flow is a product decision, not a code tweak.

## UI plan

See [`ui-plan.md`](ui-plan.md) for the calm-native-utility direction and the
browser shell + AI review sheet plan.
