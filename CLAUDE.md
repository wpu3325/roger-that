# Roger That

Offline-first group walkie-talkie (BLE mesh + Multipeer voice). No cell signal required.

## Commands

```bash
# Core unit tests (no Xcode needed)
swift test

# Regenerate .xcodeproj after editing project.yml
xcodegen generate

# Open in Xcode
open RogerThat.xcodeproj
```

## Architecture — enforced module seam

**RogerThatCore** (`Sources/RogerThatCore/`) — Swift Package, zero platform imports.
Only `Foundation` and `CryptoKit`. Builds with `swift test` on any macOS/Linux box.

**RogerThat** (`App/RogerThat/`) — iOS 16+ app. All device-only APIs live here:
CoreBluetooth, MultipeerConnectivity, AVFoundation, PushToTalk, SwiftUI.

> Rule: if it needs a radio, mic, or screen it belongs in the App target, not Core.

## Key files

| File | Purpose |
|---|---|
| `Sources/RogerThatCore/Protocol/PacketCodec.swift` | Wire encode/decode (22-byte big-endian header) |
| `Sources/RogerThatCore/Mesh/FloodRouter.swift` | TEXT flood routing; TTL=8, split-horizon, jitter relay |
| `Sources/RogerThatCore/Crypto/ChannelCrypto.swift` | ChaChaPoly AEAD body encryption |
| `Sources/RogerThatCore/Channel/JoinCode.swift` | URL-safe base64 channel join payload |
| `Sources/RogerThatCore/Transport/InMemoryLink.swift` | In-process link used by all unit tests |
| `App/RogerThat/AppState.swift` | @MainActor observable; wires session, BLE, voice, PTT |
| `App/RogerThat/Transports/BLEMeshLink.swift` | Dual peripheral+central CoreBluetooth |
| `App/RogerThat/PTT/PushToTalkController.swift` | Half-duplex PTT; TALK_START/END packetization |
| `project.yml` | XcodeGen spec; edit this, not the .pbxproj |

## Testing

44 unit tests across 4 suites — all in `Tests/RogerThatCoreTests/`:

```bash
swift test               # run all 44 tests
swift test --filter PacketCodec   # run one suite
```

Tests use `import Testing` (Swift 6 built-in). **Do not use `import XCTest`** — XCTest
requires the full Xcode.app; it's not available from CLT-only installs.

## Gotchas

- **`withUnsafeBytes` ambiguity in Swift 6**: inside a `Data` extension method, the
  compiler resolves it as an instance method. Always qualify: `Swift.withUnsafeBytes(of:)`.

- **XCTest unavailable without Xcode.app**: this host has CLT only. Use `import Testing`
  for all test files. The `swift test` runner picks it up automatically.

- **XcodeGen overwrites Info.plist and entitlements** when the `info:` key is used.
  All plist keys (usage strings, background modes, NSBonjourServices) live in
  `project.yml` under `info.properties`, not in the plist file itself.

- **`CODE_SIGN_STYLE: Manual` + empty `DEVELOPMENT_TEAM`**: the generated project
  requires a human to set Team + Bundle ID in Xcode before building on device.
  Marked with `# HUMAN:` comments in `project.yml`.

- **TTL semantics**: TTL=8 means 8 relay-hops, so the message reaches the node
  at distance **9** from the originator (not 8). Node at distance 9 receives but
  doesn't relay (TTL=0 on arrival). Confused the test bounds once — see git history.

- **Opus**: not integrated. Default is `RawPCMCodec` (640 bytes/frame @ 16kHz).
  Stub is in `App/RogerThat/Audio/OpusCodec.swift`.

- **PTT background wake**: PTChannelManager needs APNs. Fully offline = app must
  be in foreground to receive TALK_START.

## Human steps (device install)

See `RUN_ON_DEVICE.md` for the full checklist. Short version:
1. Set Team + Bundle ID in Signing & Capabilities
2. Add Push to Talk capability (`+ Capability`)
3. `⌘B` to build, `⌘R` to run on device
4. Trust developer profile on iPhone: Settings → General → VPN & Device Management
5. Grant Mic + Bluetooth + Local Network on first launch
