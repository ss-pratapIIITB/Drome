# UI plan: calm native utility

Status: proposed, not implemented. Scope: browser shell + AI filter panel.
Platform: iOS 18+, iPhone. Mode: Operate.

## Brief

**Job and audience.** A privacy-conscious reader opens a link on an iPhone and
wants to understand, in a glance, whether Drome found anything alarming — then
keep reading with as little chrome as possible. Secondary audience: a developer
or reviewer who wants to inspect what the on-device model decided.

**Outcome and proof.** Success is one primary task: read the page without
fighting the UI. Proof is a quiet shell, a persistent but unobtrusive filter
signal, and an inspectable decision trail. The filter must feel like a safety
lens, not a second browser inside the browser.

**Direction.** Calm native utility. The visual authority is iOS itself:
semantic system colors, SF Pro, system materials behind bars, one tint, native
controls, 44 pt targets. The page is the hero; chrome recedes. The distinct
Drome moment is the filter signal: a small status chip that expands into a
clear, plain-language review sheet.

## Structural thesis

1. **One signal, not a dashboard.** The browser chrome carries a single filter
   status: `Scanning`, `All clear`, or `2 hidden`. Tapping it opens the review
   sheet. Per-block badges remain optional; the default page stays clean.
2. **Move AI out of DevTools.** The AI filter is the product. DevTools keeps
   the raw analysis for debugging, but the primary review sheet is a native
   sheet reachable from the toolbar, not a tab behind a hammer icon.
3. **Five controls maximum.** Back, forward, filter, tabs, menu. Reading mode
   and DevTools move into the menu. The filter control gets the center weight.
4. **No custom chrome invented where iOS already has an answer.** Use a
   `NavigationStack` + toolbar for the tab grid, a sheet for review, and a
   compact title pill in place of a permanent full-width URL field.

## Screen plan

### Browser shell

- Address area: a compact pill with lock icon, title, and a trailing reload or
  stop control. Tapping expands into an editable URL field; the page does not
  jump because the pill keeps its height.
- Below the pill: a 28 pt status strip only when filtering is active. It shows a
  progress line while scanning and settles into `All clear` or `2 hidden · Review`.
  The strip collapses entirely when the filter is off.
- Bottom toolbar: back, forward, filter, tabs, menu. Use SF Symbols at 17–18 pt,
  one accent color, and a subtle tinted background for active states.
- Toolbar background: system material with a hairline separator; no gradients.
- Page content: edge-to-edge; no card wrapper, no floating toolbar.

### Filter review sheet

- Presented as a medium/large detent sheet with a grabber.
- Header: `Page review`, then a one-line summary in plain language:
  `Drome checked 24 blocks and hid 2.` Avoid model jargon in the primary line.
- Three groups, in this order: `Hidden`, `Reviewed`, `Not checked`.
  - Hidden rows: short preview, category, and a `Show` action.
  - Reviewed rows: preview + `Safe` or `Flagged` label; no raw scores by default.
  - Not checked: short blocks or unreadable content, with a one-line reason.
- Footer actions: `Show all hidden` / `Hide flagged`, and a secondary
  `Advanced details` disclosure containing XPath, confidence, latency, and the
  prompt variant used. This is where developer detail belongs.
- Empty state: `No page scanned yet` with a single `Scan this page` action.
- Error state: `On-device model unavailable` plus `Use keyword filter` and
  `Try again`.

### Tab grid

- Convert the current full-screen overlay into a native sheet or
  `fullScreenCover` with a `NavigationStack`.
- Large title: `Tabs`. Trailing `Done`.
- Two-column grid with 16 pt gutters, 12 pt corner radius, selection ring in the
  accent color, title + favicon in a 44 pt footer.
- Close affordance: a 28 pt circular button with a 44 pt hit area, or a context
  menu / swipe action. Keep it visible but not louder than the snapshot.
- Bottom action row: `New Tab` as the only filled button; `Duplicate` becomes a
  secondary bordered button or a menu item.
- Empty state: one sentence and the `New Tab` button; no illustration.

### Menu

Use a native `Menu` from the ellipsis button:

- Reading mode
- Developer Tools
- Downloads
- Settings
- Share

This removes two permanent toolbar slots and makes the primary feature
(filter) unambiguous.

## Visual tokens

- **Type:** system text styles only. Address title `.headline`, status
  `.caption`, sheet headers `.title3`, body `.body`, metadata `.caption`.
  No hard-coded point sizes in new UI.
- **Spacing:** 4, 8, 12, 16, 24. Toolbar height 44; status strip 28; sheet
  section gap 24.
- **Shape:** 12 pt radius for compact controls, 16 pt for sheets/cards, capsule
  for the address pill and status chip. No mixed radii in one cluster.
- **Color:** system background, secondary background, separator, label,
  secondary label. One accent (system blue). Green/red only for safety status,
  never for decoration. No raw hex.
- **Materials:** `.bar` / `.regularMaterial` only for chrome and sheets. No
  hand-rolled blur, glow, or glass cards.
- **Iconography:** SF Symbols only. Filled variants for active states; no icon
  fonts or mixed families.

## Motion

- One spring for tab-grid presentation, one short fade for status changes, and
  no animation on page load or scan progress beyond the progress bar.
- Filter results fade in; hidden blocks never animate height (that would move
  the article under the reader).
- Honor Reduce Motion: crossfade instead of slide for the tab grid and sheet
  content.

## States and ranges

- **First run:** filter off until the model is ready; status strip says
  `Preparing on-device filter` with a progress indicator and a `Use keyword
  filter` escape hatch.
- **Scanning:** `Scanning 12 of 24` in the strip; page remains interactive.
- **All clear:** `All clear` with a checkmark; strip can auto-collapse after a
  few seconds but remains tappable from the filter button.
- **Unsafe found:** `2 hidden · Review`; strip stays visible until dismissed.
- **Filter off:** no strip; filter button shows an outlined shield.
- **Model unavailable:** strip becomes `Keyword filter only` with an info
  action; never a modal on page load.
- **Long pages:** show `24 of 80 checked` and a `Continue scanning` action
  rather than silently stopping at the 40-block initial batch.
- **Dynamic Type:** title pill truncates with a tail; status strip wraps to two
  lines at accessibility sizes; sheet rows grow vertically.
- **Dark Mode:** verify semantic colors; screenshots in both appearances.

## Accessibility

- 44×44 pt minimum for every control; 8 pt minimum between adjacent targets.
- VoiceOver labels: `Filter: 2 hidden`, `Show hidden block`, `Review page`.
- Status is never conveyed by color alone: icon + text.
- Announce scan completion once, not per block.
- Test at AX3 and AX5; no clipped titles or overlapping toolbar items.

## Anti-goals

- No glassmorphism, gradient hero, neon accent, or “AI sparkle” decoration.
- No custom tab bar or reinvented navigation stack.
- No raw confidence scores, XPaths, or prompt text in the primary sheet.
- No permanent developer-tools panel on first launch.
- No layout shift when the filter status appears or disappears.

## Implementation sequence

1. **Shell:** move reading mode/DevTools into a menu; add the filter button;
   convert the address bar to a compact pill with expansion.
2. **Status strip:** bind to scan progress and results; add the `All clear` /
   `hidden` states.
3. **Review sheet:** new sheet using `aiResults`, grouped and summarized; keep
   DevTools AI tab as the advanced view.
4. **Tab grid:** native presentation, 2-column cards, bottom actions, empty
   state.
5. **Polish:** Dynamic Type, VoiceOver, dark mode, reduce motion, screenshot
   pass on the simulator.

## Open decisions

- Whether the status strip should auto-collapse after `All clear`. Recommendation:
  yes, after 4 seconds, but keep the filter button tinted.
- Whether hiding unsafe content remains opt-in. Recommendation: keep the current
  setting; the review sheet always offers `Hide flagged` as an explicit action.
- Whether the AI chat belongs in the review sheet. Recommendation: no. Keep chat
  in DevTools; the review sheet is for decisions, not conversation.

## Assumptions

- iOS 18+ is the only target; no iPad layout in this pass.
- The review sheet can read `DeveloperToolsViewModel.aiResults` without adding a
  new model layer.
- The filter remains on-device and keyword fallback remains available.
