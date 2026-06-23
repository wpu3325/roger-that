# Running Roger That on a Physical iPhone

## Prerequisites

- macOS 14+ with **Xcode 15 or later** installed (not just Command Line Tools)
- An Apple Developer account (free tier is sufficient for personal device testing)
- Two iPhones running iOS 16+ to actually test mesh voice and BLE relay

---

## Step 1 — Install XcodeGen and regenerate the project

```sh
brew install xcodegen
xcodegen generate        # creates RogerThat.xcodeproj
```

## Step 2 — Open in Xcode

```sh
open RogerThat.xcodeproj
```

## Step 3 — Set your Bundle ID and Team

1. Select the **RogerThat** target in the left sidebar.
2. Go to **Signing & Capabilities**.
3. Set **Team** to your Apple Developer team.
4. Set **Bundle Identifier** to something unique, e.g. `com.yourname.rogerthat`.
   - Also update `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) so regenerating keeps it.
5. Let Xcode manage signing automatically (toggle **Automatically manage signing**).

## Step 4 — Enable Push to Talk capability

1. In **Signing & Capabilities**, click **+ Capability**.
2. Search for and add **Push to Talk**.
3. Xcode will update the entitlements file.  
   > If you see a build error about `com.apple.developer.push-to-talk` not being provisioned, log in to [developer.apple.com](https://developer.apple.com), go to Certificates → Identifiers, find your App ID, and enable the Push to Talk capability there, then re-download the provisioning profile in Xcode via `Xcode → Preferences → Accounts → Download Manual Profiles`.

## Step 5 — Verify the Simulator build (no device needed)

```
Product → Destination → iPhone 16 Simulator
Product → Build (⌘B)
```

All 44 unit tests run in the Simulator too:

```
Product → Test (⌘U)
```

> Note: BLE, Multipeer Connectivity, and audio I/O do not function in the Simulator. The tests that run in `swift test` (pure-logic Core) also run here. Device-only APIs compile but are no-ops in the Simulator.

## Step 6 — Run on device

1. Plug in an iPhone via USB (or connect wirelessly via Xcode).
2. Select the device as the **run destination**.
3. Click **Run** (▶).
4. On the iPhone, go to **Settings → General → VPN & Device Management** and trust your developer profile.
5. Relaunch the app.

## Step 7 — Grant permissions on first launch

The app will request:

| Permission | When | Why |
|---|---|---|
| Microphone | On first PTT press | Voice capture |
| Bluetooth | On launch | BLE mesh |
| Local Network | On launch | Multipeer Connectivity |

Grant all three. Without them the respective features silently fail.

## Step 8 — Test with two devices

1. Install the app on **two iPhones** (same build, same bundle ID).
2. Both must be in the same channel (one creates, one joins via the displayed code).
3. Text messages flood over BLE; you should see them appear on the other device within a second or two when within ~10 m.
4. Hold the **Talk** button on one device — the other should display "X is talking" and play back the audio.

> If voice doesn't work but text does, confirm both devices have Multipeer / Local Network permission granted and are on the same Wi-Fi network or within Bluetooth range for P2P.

---

## Known limitations (read before testing)

- **PTT background wake is best-effort offline.** PTChannelManager can wake the app when it receives a TALK_START push notification over APNs. Without cell/Wi-Fi connectivity the push won't arrive — the receiving device must have the app in the foreground.
- **BLE range is ~10 m indoors.** Outdoors can be further. Dense RF environments reduce reliability.
- **Audio is raw PCM (640 bytes/frame).** Opus compression is a TODO. This is fine for testing; for production ranges beyond 2–3 hops you'll want Opus.
- **No mesh voice relay.** Voice goes only to direct Multipeer peers. Text is the fallback for multi-hop scenarios.
