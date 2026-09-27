# Page-Scoped Laya Scanning Design

## Goal

Make Drome's Laya content scanning follow the page the user is currently viewing, discard stale work immediately when that page changes, process dynamically revealed content incrementally, and provide a reversible setting for hiding unsafe elements.

## Scope

This work targets the native on-device Laya MLX implementation on `feature/laya-mlx-swift-on-device`. It does not add a remote inference backend, change the safety taxonomy, or rescan an entire document after each DOM mutation.

## Chosen Approach

Use one page-scoped scan session per visible tab/navigation. A session owns its initial scan task, debounced mutation queue, processed-content fingerprints, and cancellation state. The coordinator accepts model results only while the session is still current for both the navigation and the selected tab.

This is preferable to scattered active-tab checks because all work and validity rules share one lifecycle. It is also preferable to a global scheduler because Drome needs only one active page pipeline and should not retain background-page work.

## Page and Tab Lifecycle

- A session identity contains the tab identifier and a new navigation generation identifier.
- Navigation start cancels and discards the existing session before clearing page annotations.
- Selecting another tab cancels and discards the previously visible tab's session and stops its mutation observer.
- Closing a tab or disabling AI filtering cancels the affected session.
- A page may start scanning only when its tab is currently selected.
- Every asynchronous boundary, especially before and after Laya inference, checks that the session remains current. Late results from cancelled work are ignored and cannot label, hide, or log results for another page.
- Returning to a previously selected tab starts a fresh session against its current DOM. Extraction includes only visible elements that are unlabeled or whose content fingerprint changed, so already completed work is not repeated.

## Scan Pipeline

The coordinator delegates page lifecycle and queued work to a focused `PageScanSession`. The session exposes cancellation, current-session validation, mutation coalescing, and processed-fingerprint tracking. `BrowserViewModel` exposes the selected tab identifier and notifies each tab coordinator when selection changes.

`AIContentFilter` separates classification from DOM mutation. It returns a classification value containing safety, reason, and method. The coordinator checks session validity before applying the value to the page and recording it in DevTools. This guarantees stale Laya responses have no side effects even if underlying inference does not stop immediately when its Swift task is cancelled.

Initial extraction remains capped to protect responsiveness, but pending work belongs only to the active session. Mutation work is drained serially in bounded batches and rescheduled until the coalesced queue is empty. No current-page mutation is discarded merely because a batch limit was reached.

## Dynamic Content

The page observer starts immediately after navigation finishes, before model preparation or the initial scan. It watches:

- inserted nodes and subtrees;
- text-node changes;
- visibility and expansion-related attributes: `hidden`, `open`, `aria-expanded`, `class`, and `style`.

Observer callbacks collect only visible text-bearing elements within the affected subtree. Each candidate carries a stable page-local element identifier and a fingerprint of normalized text. JavaScript-side debouncing collapses mutation bursts, while Swift-side coalescing keeps only the latest candidate for an element. Changes created by Drome's own labels and hiding classes are excluded to avoid feedback loops.

An expand action therefore scans newly visible or changed elements only. It does not rerun document-wide extraction.

## Hiding Unsafe Content

The existing `aiRemoveUnsafe` preference is retained for stored-settings compatibility but presented as the native iOS toggle `Hide Unsafe Content` under `AI Content Filter`. A binary toggle is the appropriate iOS control for this setting; a radio group would imply multiple mutually exclusive choices.

Unsafe elements receive a Drome-owned CSS class instead of an irreversible inline `display: none`. Turning the setting on hides all currently classified unsafe elements and causes future unsafe results to be hidden. Turning it off removes the class and reveals those elements without reloading or rescanning. Drome removes only its own class and does not overwrite the site's original display styles.

## Error Handling

- Laya preparation or classification failure continues to use the existing heuristic fallback for the current session.
- A JavaScript extraction or element lookup failure skips that candidate and leaves the session alive.
- Cancellation is a normal lifecycle event, not an error; cancelled sessions must clear their pending UI state and must not emit completion counts.
- If the selected page changes while a batch is running, remaining queued work is discarded.

## Testing

Add a Drome unit-test target and cover the pure session state independently of WebKit and MLX:

- navigation or tab transfer invalidates the old session;
- cancelled sessions reject late results;
- mutation candidates coalesce by element identifier and preserve the newest fingerprint;
- bounded drains retain later current-page work;
- unchanged fingerprints are not reprocessed;
- returning to a tab permits only unlabeled or changed candidates.

Test generated JavaScript contracts for the observer configuration and reversible hide/reveal behavior. Build the app for an iOS simulator to catch integration and concurrency errors, then build, install, and launch the signed app on the Wi-Fi-connected iPhone.

## Success Criteria

- Switching pages or tabs prevents all previous-page Laya work from changing either page or DevTools.
- The newly visible page begins scanning without waiting for stale queued classifications.
- Expanding or dynamically loading content scans only newly visible or changed elements.
- Mutation bursts are coalesced without silently dropping remaining active-page work.
- `Hide Unsafe Content` immediately hides or reveals already classified unsafe elements and persists across launches.
- Automated tests pass, the iOS build succeeds, and the updated app launches on the available iPhone over Wi-Fi.
