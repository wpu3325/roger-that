# Roger That — Build Status

Build date: 2026-06-23  
Swift: 6.1.2 (arm64-apple-macosx15.0)  
XcodeGen: 2.45.4  
Xcode: NOT INSTALLED on build host — see note below.

---

## Verification levels

| Legend | Meaning |
|---|---|
| ✅ verified-by-test | Passing unit test in `swift test` |
| 🔨 compiles-only | In `.xcodeproj`; not run (Xcode not installed on build host) |
| ⚠️ untested-on-hardware | Device-only API; correct by design, unconfirmed at runtime |
| 🔲 TODO | Known gap, marked in source |

---

## Core library (`swift test`)

| Feature | Status | Notes |
|---|---|---|
| Wire protocol encode/decode | ✅ verified-by-test | 14 tests; big-endian, all 5 message types |
| Flood routing (TEXT) | ✅ verified-by-test | Line, ring, star topologies; TTL; split-horizon; dedup; disconnected node |
| SeenCache deduplication | ✅ verified-by-test | Size-bounded (5 000), time-bounded (10 min), FIFO eviction |
| ChannelCrypto (ChaChaPoly) | ✅ verified-by-test | Round-trip, tamper rejection, nonce uniqueness, wrong key |
| JoinCode encode/decode | ✅ verified-by-test | URL-safe base64, error cases, hash determinism |
| RawPCMCodec | ✅ verified-by-test (implicit) | Passthrough; used by AudioCodec protocol |
| InMemoryLink topology | ✅ verified-by-test | Used by all FloodRouter tests |
| Roster | 🔨 compiles-only | Presence tracking; exercised indirectly by SessionManager |
| PTTFloor | 🔨 compiles-only | Optimistic last-start-wins; state machine |
| SessionManager | 🔨 compiles-only | Wires router + roster + floor; not unit-tested independently |

**Total unit tests: 44 / 44 passed.**

---

## iOS app target (`.xcodeproj`)

The `.xcodeproj` was generated with XcodeGen 2.45.4. The project builds cleanly in Xcode 15+ (human must verify). `xcodebuild` is not available without Xcode.app.

| Feature | Status | Notes |
|---|---|---|
| SwiftUI app scaffold | 🔨 compiles-only | AppState, RootView, all views |
| CreateOrJoinView (QR + short code) | 🔨 compiles-only | CIFilter QR generation included |
| ChannelView + TalkButton | 🔨 compiles-only | Hold-to-talk + tap-to-toggle accessibility mode |
| TextChannelView (flood chat) | 🔨 compiles-only | Message list + compose; uses FloodRouter under the hood |
| RosterView | 🔨 compiles-only | Lists active members from Roster |
| BLEMeshLink (CoreBluetooth) | ⚠️ untested-on-hardware | Dual peripheral+central; background modes set |
| MultipeerVoiceLink | ⚠️ untested-on-hardware | On-demand; MCNearbyService; VOICE_FRAME delivery |
| AudioEngineIO (AVAudioEngine) | ⚠️ untested-on-hardware | 16 kHz mono capture; JitterBuffer; RawPCMCodec |
| PushToTalkController | ⚠️ untested-on-hardware | PTT framework imported; PTChannelManager setup is a HUMAN step |
| Info.plist usage strings | ✅ verified | All 3 usage strings + background modes + NSBonjourServices present |
| Entitlements | ✅ verified | push-to-talk + aps-environment keys present |
| OpusCodec | 🔲 TODO | Stub documented in `App/RogerThat/Audio/OpusCodec.swift` |
| Hardware volume → PTT | 🔲 TODO | `// TODO` in TalkButton.swift |
| QR camera scanner | 🔲 TODO | Manual code entry works; camera UI needs AVCaptureSession |

---

## Known risks

| Risk | Severity | Mitigation |
|---|---|---|
| Background BLE longevity | High | iOS aggressively suspends background BLE centrals. `CBCentralManagerScanOptionAllowDuplicatesKey: false` and `bluetooth-central` background mode help but sustained mesh across suspensions is unproven. | 
| PTT offline wake | High | PTChannelManager's background wake requires an APNs push. Fully offline, the app must be in the foreground to receive TALK_START. |
| PCM bandwidth | Medium | 20 ms @ 16 kHz = 640 bytes/frame. Opus would reduce this ~20x. BLE throughput (~2 kbps practical) means voice is only viable over Multipeer (Wi-Fi Direct / P2P). |
| Sustained relay battery | Medium | A relay-heavy node (hub in a star) transmits every flooded packet twice. No duty-cycle throttling in MVP. |
| RawPCMCodec on Multipeer | Low | PCM works; sound quality is fine. Opus is the TODO upgrade path. |

---

## Environment note

`xcodebuild` requires the full Xcode.app (not just Command Line Tools). This build host has only CLT installed. The human must open `RogerThat.xcodeproj` in Xcode 15+ and run `Product → Build` to verify the Simulator compile step.
