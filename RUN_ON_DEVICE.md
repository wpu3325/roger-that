# Running Roger That on a Physical iPhone

> Signing is already configured in `project.yml` (Team `TPYY95V67H`, Bundle ID
> `com.wilsonpu.rogerthat`, Automatic signing, iOS 17+). If you're on the original
> developer's machine you can skip straight to Step 3. If you're building under a
> different Apple ID, do Step 2a first.

## Prerequisites

- macOS with **Xcode 15 or later** installed (not just Command Line Tools)
- A free Apple Developer account (Personal Team is sufficient for device testing)
- Two iPhones running **iOS 17+** to actually test mesh text and Multipeer voice

---

## Step 1 — Regenerate the project

```sh
brew install xcodegen     # one-time
xcodegen generate         # (re)creates RogerThat.xcodeproj from project.yml
```

Run this any time you add or remove a `.swift` file under `App/RogerThat/` (it's a
glob) or edit `project.yml`. If Xcode is open, accept the "Load Changes" banner.

## Step 2 — Open in Xcode

```sh
open RogerThat.xcodeproj
```

### Step 2a — Only if building under a different Apple ID

The committed signing is tied to one developer account. To build under your own:

1. Select the **RogerThat** target → **Signing & Capabilities**.
2. Set **Team** to your own Apple Developer team.
3. Change **Bundle Identifier** to something unique, e.g. `com.yourname.rogerthat`.
4. Mirror both values in `project.yml` (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`)
   so the next `xcodegen generate` keeps them.

> **Do not add the Push to Talk capability.** It was deliberately removed — it requires
> a paid Apple Developer account ($99/yr) and a Personal Team cannot provision it. The
> entitlements file is intentionally empty. The app uses an in-app PTT button + the
> Action Button instead.

## Step 3 — Run on device

1. Plug in an iPhone via USB (or connect wirelessly via Xcode).
2. Select the device as the **run destination**.
3. Click **Run** (⌘R).
4. On the iPhone: **Settings → General → VPN & Device Management** → trust your
   developer profile.
5. Relaunch the app.

> **Free Personal Team certs expire after 7 days.** When the app refuses to launch with
> a signing error, just reconnect the phone and `⌘R` again to re-sign.

## Step 4 — Grant permissions on first launch

| Permission | When | Why |
|---|---|---|
| Bluetooth | On launch | BLE mesh (text + presence/roster) |
| Local Network | On launch | Multipeer Connectivity (voice) |
| Camera | First time you scan a join QR | QR channel-join scanner |
| Microphone | On first PTT press | Voice capture |

Without each one, the corresponding feature silently fails.

## Step 5 — Test with two devices

1. Install the app on **two iPhones** (same build).
2. Both join the same channel (one creates, the other joins via the displayed code or QR).
3. Text + presence flood over BLE: messages and the roster should appear on the other
   device within a second or two when within ~10 m.
4. Hold the **Talk** button on one device — the other should show "X is talking" and
   play back the audio over Multipeer.

> If text/roster works but voice doesn't, confirm both devices granted **Local Network**
> permission and are within Bluetooth/Wi-Fi P2P range. One-directional voice most often
> means a missing Local Network grant on one side.

---

## A note on the Simulator and unit tests

BLE, Multipeer Connectivity, and audio I/O **do not function in the Simulator** — those
APIs compile but are no-ops there. Real testing needs hardware.

The pure-logic Core suite (44 tests) is the only part that runs without a device. On a
**CLT-only host** `swift test` currently fails with `no such module 'Testing'` (Swift
6.3.2 toolchain issue) — verify Core with `swift build` from the CLI, and run the actual
suite from Xcode via **Product → Test (⌘U)** against any Simulator.

---

## Known limitations (read before testing)

- **PTT background wake is best-effort offline.** Waking the app on an incoming TALK_START
  needs an APNs push (PTChannelManager). Fully offline, the receiving device must have the
  app in the foreground.
- **BLE range is ~10 m indoors.** Outdoors can be further; dense RF reduces reliability.
- **Audio is raw PCM (640 bytes/frame).** Opus compression is a TODO (`OpusCodec.swift`).
  Fine for testing.
- **No mesh voice relay.** Voice reaches only direct Multipeer peers. Text is the
  multi-hop fallback.
