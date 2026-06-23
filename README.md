# Roger That

Offline-first group walkie-talkie for dense cities, hikes, and ski slopes — no cell signal required.

## How it works

Roger That builds an ad-hoc mesh between nearby iPhones using Bluetooth LE (for text + presence) and Multipeer Connectivity (for voice). Text messages flood the mesh with TTL-bounded rebroadcasting; voice frames go only to direct peers with no relay.

## Module split

```
RogerThat/
  Package.swift              Swift Package (RogerThatCore library + unit tests)
  project.yml                XcodeGen spec for the iOS app target
  Sources/RogerThatCore/     Platform-agnostic core: protocol, routing, crypto, audio codec
  Tests/RogerThatCoreTests/  Unit tests (44 tests, all green with swift test)
  App/RogerThat/             iOS app: BLE, Multipeer, AVAudioEngine, SwiftUI UI
```

**RogerThatCore** — zero platform imports. Builds and tests with `swift test` on any macOS/Linux CI box.

**RogerThat** (iOS app) — depends on RogerThatCore. Contains all device-only APIs: CoreBluetooth, MultipeerConnectivity, AVFoundation, PushToTalk, SwiftUI.

## Build the core (CI / no Xcode required)

```sh
swift test
```

All 44 unit tests should be green.

## Build the app (Xcode 15+ required)

```sh
brew install xcodegen   # one-time
xcodegen generate       # creates RogerThat.xcodeproj from project.yml
```

Then open `RogerThat.xcodeproj` in Xcode — see `RUN_ON_DEVICE.md` for the full device-install checklist.

## Wire protocol

Big-endian fixed 22-byte cleartext header + encrypted body.

| Field | Type | Bytes |
|---|---|---|
| version | u8 | 1 |
| type | u8 | 1 |
| flags | u8 | 1 (bit0 = body encrypted) |
| ttl | u8 | 1 |
| channelIDHash | u32 | 4 |
| senderID | u32 | 4 |
| messageID | u64 | 8 |
| payloadLen | u16 | 2 |
| body | [payloadLen] | variable |

Encryption: ChaChaPoly AEAD. Body wire format when encrypted: `nonce(12) ‖ ciphertext ‖ tag(16)`.

## Audio

Default codec: `RawPCMCodec` — 16 kHz mono 16-bit PCM passthrough (20 ms frames).
Opus integration is a documented TODO in `App/RogerThat/Audio/OpusCodec.swift`.

## Architecture principles

- The seam between Core and App is enforced: nothing in Core imports a device framework.
- All transport implementations (`BLEMeshLink`, `MultipeerVoiceLink`, `InMemoryLink`) conform to the same `Link` protocol — a LoRa or satellite link would slot in without touching routing or crypto.
- Text flooding is the resilient fallback. Voice requires direct peer reachability.
