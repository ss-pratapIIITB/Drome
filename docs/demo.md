# Demo script

A 90-second walkthrough is enough to show the project. Record it on a physical iPhone; the model does not run in the simulator.

## Before recording

- Install a build with [the sideload guide](install.md).
- Open an article with several text blocks and at least one sensitive paragraph.
- Complete the first model download ahead of time so the demo does not wait on 843 MB.
- Turn on **Settings → Privacy → AI Content Filter** and **Hide Unsafe Content**.
- Enable **Settings → Privacy → Laya MLX Playground** for the inspection segment.
- Put the phone in Do Not Disturb and set brightness to a comfortable level.

## 90-second storyboard

1. **0:00–0:10 — The browser**
   Open the article. Show tabs, the address bar, and the developer-tools button. Establish that this is a real browser, not a mock.

2. **0:10–0:30 — The filter**
   Scroll a little, then toggle **Hide Unsafe Content**. The flagged blocks fade out while the rest of the article stays in place. Toggle it back on to prove the change is reversible.

3. **0:30–0:50 — The proof**
   Open **Settings → Laya MLX Playground**. Show a decision with its confidence, latency, and category. Say explicitly: "This ran on the phone; page text never left the device."

4. **0:50–1:10 — The engineering**
   Open **Developer Tools → Network** and show that no classification request leaves the app. Switch to **Console** or **Elements** to show the bridge and DOM tooling.

5. **1:10–1:30 — The close**
   Switch to airplane mode, reopen the article, and show the filter still working. End on the architecture diagram in the README.

## Things to capture for the repository

- `docs/assets/demo.gif` — 10–20 second loop of the reversible hide.
- `docs/assets/filter-before.png` and `docs/assets/filter-after.png` — same viewport, before and after.
- `docs/assets/playground.png` — one decision with confidence and latency visible.
- `docs/assets/devtools.png` — the developer-tools panel.

Keep screenshots at the device's native resolution and redact any personal tabs, history, or account details.

## Recording on macOS

For a physical device, use QuickTime Player → **File → New Movie Recording** and select the iPhone. For a simulator, `xcrun simctl io booted recordVideo demo.mp4` works, but the Laya runtime requires Apple-silicon hardware and a device is the honest demo.

Convert a short recording to a looping GIF with `ffmpeg`:

```bash
ffmpeg -i demo.mp4 -vf "fps=12,scale=720:-1:flags=lanczos" -loop 0 docs/assets/demo.gif
```

## Claims to avoid

- Do not present the filter as a safety guarantee or a clinical tool.
- Do not quote M3 Max timings as iPhone performance. Measure on the device you demo.
- Do not say "no data leaves the device" without the caveat that the model checkpoint is downloaded from Hugging Face on first use.
