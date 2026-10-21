# Install Drome on an iPhone

Drome is not distributed through the App Store. You can build it with Xcode or sideload a signed copy with your own Apple ID. This guide covers both.

> Sideloading means you sign the app with your Apple ID. Only install builds you produced yourself or downloaded from this repository's [Releases](https://github.com/ss-pratapIIITB/Drome/releases). Never use a shared or untrusted signing service for an app that can read your browsing data.

## Requirements

- iPhone with **iOS 18 or later**
- Apple-silicon iPhone for the Laya model (iPhone 15 Pro or newer is the practical baseline)
- About **1 GB of free storage** for the model checkpoint
- Internet access on first AI scan to download the model from Hugging Face
- A Mac with Xcode 26 (for the Xcode path) **or** a Mac/Windows PC with [Sideloadly](https://sideloadly.io/) or AltServer

## Which path should I use?

| Path | Cost | App lifetime | Best for |
| --- | --- | --- | --- |
| Xcode + free Apple ID | Free | 7 days per signature | Testing on your own device |
| Sideloadly + unsigned IPA | Free | 7 days per signature | No Xcode project setup |
| AltStore / SideStore | Free | 7 days, refreshes | Long-term personal use |
| Paid Apple Developer | $99/year | 1 year | Sharing with other people |

A free Apple ID can sign at most **3 apps per device** and **10 App IDs per week**, and signatures expire after **7 days**. A paid developer account removes the 7-day limit and allows TestFlight.

## Path A — Build and run with Xcode

1. Install **Xcode 26** from the Mac App Store and open it once.
2. Clone the repository and generate the project:

   ```bash
   git clone https://github.com/ss-pratapIIITB/Drome.git
   cd Drome
   xcodegen generate
   open Drome.xcodeproj
   ```

3. Select the **Drome** target → **Signing & Capabilities**.
4. Choose your personal team and replace the bundle identifier with something unique, for example `com.yourname.drome`.
5. **Free Apple ID only:** in **Build Settings**, change `CODE_SIGN_ENTITLEMENTS` from `Drome/Drome.entitlements` to `Drome/Drome.Sideload.entitlements`. The default file requests `com.apple.developer.kernel.increased-memory-limit`, which personal teams cannot provision.
6. Connect the iPhone, select it as the run destination, and press **Run**.
7. On the iPhone, enable **Settings → Privacy & Security → Developer Mode**, then reboot and confirm.
8. Trust your certificate under **Settings → General → VPN & Device Management**.

The app will stop launching after 7 days. Re-run from Xcode to refresh the signature.

## Path B — Sideload an unsigned IPA with Sideloadly

Use this if you do not want to open the project in Xcode.

1. Download the unsigned IPA from the latest [release](https://github.com/ss-pratapIIITB/Drome/releases) (or build one with `./scripts/build-ipa.sh`).
2. Install [Sideloadly](https://sideloadly.io/) on macOS or Windows.
3. Connect the iPhone and trust the computer when prompted.
4. Drag the `.ipa` into Sideloadly.
5. Enter your Apple ID. Sideloadly signs the app locally with your account.
6. Start the install and wait for it to finish.
7. Enable **Developer Mode** on the iPhone if it is not already on.
8. Trust the developer certificate under **Settings → General → VPN & Device Management**.

Sideloadly may warn about the increased-memory entitlement. The release IPA is built with `Drome/Drome.Sideload.entitlements`, which deliberately omits it.

## Path C — AltStore or SideStore

AltStore and SideStore install a helper that re-signs apps before the 7-day expiry.

1. Install AltServer on a Mac/PC (AltStore) or follow the SideStore setup guide.
2. Install AltStore/SideStore on the iPhone using your Apple ID.
3. Download the unsigned IPA from the latest release.
4. Open the IPA with AltStore/SideStore and sign it with your Apple ID.
5. Keep the helper reachable on the same network so it can refresh before expiry.

## Build an unsigned IPA yourself

```bash
./scripts/build-ipa.sh
```

The script archives the `Drome` scheme for `generic/platform=iOS` with code signing disabled, packages `Payload/Drome.app` into `build/Drome-unsigned.ipa`, and writes a SHA-256 checksum next to it. Signing is done later by Sideloadly, AltStore, or Xcode.

Requirements:

- macOS with Xcode 26 and the iOS device SDK
- `xcodegen` only if you changed `project.yml` and need to regenerate the project

Tagged builds on `main` are also produced by [`.github/workflows/release-ipa.yml`](https://github.com/ss-pratapIIITB/Drome/blob/main/.github/workflows/release-ipa.yml).

## First launch

1. Open **Settings → Privacy → AI Content Filter** and enable it.
2. Open any article. The first scan downloads the ~843 MB Laya checkpoint; keep the app in the foreground and on Wi-Fi.
3. Later scans are fully offline.
4. Use **Settings → Laya MLX Playground** to inspect individual decisions, confidence, and latency.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Unable to install" or duplicate app | Change the bundle identifier to a unique value and rebuild. |
| "Untrusted Developer" | Trust the certificate in Settings → General → VPN & Device Management. |
| App stops opening after a week | Free signatures expired. Reinstall/refresh with Xcode, Sideloadly, or AltStore. |
| Signing fails on `increased-memory-limit` | Use `Drome/Drome.Sideload.entitlements` (Path A, step 5) or the release IPA. |
| Model never finishes downloading | Keep the app open, check free storage, and retry on a stable connection. |
| Very slow inference or memory warnings | Expected on older devices without the increased-memory entitlement. Close other apps. |
| `xcodegen: command not found` | `brew install xcodegen`. |

## Verifying a release

Every release IPA is accompanied by a `.sha256` file. Verify before signing:

```bash
shasum -a 256 -c Drome-unsigned.ipa.sha256
```

The checksum proves the download matches the build artifact. It does not replace code review — the source is public so you can build it yourself.
