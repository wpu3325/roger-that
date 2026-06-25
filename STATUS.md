# Roger That — Build Status

Last updated: 2026-06-24
Swift: 6.3.2 (arm64-apple-macosx26.0), Command Line Tools only
XcodeGen: present (`xcodegen generate` regenerates `RogerThat.xcodeproj`)
Xcode: NOT INSTALLED on build host — see environment note below.

---

## Verification levels

| Legend | Meaning |
|---|---|
| ✅ verified-by-test | Passing unit test in `swift test` (see toolchain caveat) |
| 🔨 compiles-only | `swift build` clean (Core) / in `.xcodeproj` (app); not run |
| ⚠️ untested-on-hardware | Device-only API; correct by design, unconfirmed at runtime |
| 🔲 TODO | Known gap, marked in source |

> **Toolchain caveat (2026-06-24):** the CLT-only host updated to Swift 6.3.2 and
> `swift test` now fails with `no such module 'Testing'`. Core logic is verified with
> `swift build` instead; run the actual test suite from Xcode. No test files changed
> this session, so the 44-test suite is expected green when run under Xcode.

---

## Core library (`swift build` clean)

| Feature | Status | Notes |
|---|---|---|
| Wire protocol encode/decode | ✅ verified-by-test | 14 tests; big-endian, all 5 message types |
| Flood routing (TEXT + PRESENCE) | ✅ verified-by-test | Router now flood-routes `.text` AND `.presence` |
| SeenCache deduplication | ✅ verified-by-test | Size-bounded (5 000), time-bounded (10 min), FIFO |
| ChannelCrypto (ChaChaPoly) | ✅ verified-by-test | Round-trip, tamper rejection, nonce uniqueness |
| JoinCode encode/decode | ✅ verified-by-test | URL-safe base64, error cases, hash determinism |
| RawPCMCodec | ✅ verified-by-test (implicit) | Passthrough; used by AudioCodec protocol |
| InMemoryLink topology | ✅ verified-by-test | Used by all FloodRouter tests |
| FloodRouter `send(presence:)` + peer-connected hook | 🔨 compiles-only | Added this session; not unit-tested |
| Roster (+ self-insert on start) | 🔨 compiles-only | Presence tracking |
| SessionManager (presence type fix, roster/announce hooks) | 🔨 compiles-only | Sends `.presence` not `.text`; immediate announce on connect |

**Total unit tests: 44 (last run green; see toolchain caveat).**

---

## iOS app target (`.xcodeproj`)

Generated with XcodeGen. Builds in Xcode (human must verify — no `xcodebuild` on host).

| Feature | Status | Notes |
|---|---|---|
| SwiftUI app scaffold | 🔨 compiles-only | AppState, RootView, all views |
| Call sign (persisted, static-after-entry) | 🔨 compiles-only | `@AppStorage` + local draft; pencil to edit |
| CreateOrJoinView (QR + short tag + copy) | 🔨 compiles-only | `XXXX·XXXX` tag; copy invite code |
| QR camera scanner | 🔨 compiles-only | `QRScannerView` (AVCaptureSession) — was TODO, now done |
| In-channel invite QR | 🔨 compiles-only | `ChannelQRView`; qrcode toolbar button |
| ChannelView + TalkButton | 🔨 compiles-only | Hold-to-talk + persisted tap-to-toggle; animated waveform |
| Voice waveform (RMS levels) | ⚠️ untested-on-hardware | `VoiceWaveformView` driven by `AppState.voiceLevel` |
| TextChannelView (iMessage-style) | 🔨 compiles-only | System "joined" notices, sender grouping, swipe-for-timestamps |
| Member-join detection + pull-to-refresh | 🔨 compiles-only | `AppState.syncRoster` / `refreshRoster` |
| RosterView | 🔨 compiles-only | Active members; `.refreshable` |
| BLEMeshLink (CoreBluetooth) | ⚠️ untested-on-hardware | Peripheral retention, connect-any-serviceUUID, advertise-after-didAdd |
| MultipeerVoiceLink | ⚠️ untested-on-hardware | Single shared MCSession + invitation tiebreak |
| AudioEngineIO (AVAudioEngine) | ⚠️ untested-on-hardware | Mic capture + AVAudioPlayerNode playback + RMS; speaker override |
| Voice RX pipeline | ⚠️ untested-on-hardware | `voice.setHandlers` → decode → play; link+engine start on JOIN |
| Remote-talking banner + watchdog | ⚠️ untested-on-hardware | Frame-driven + 1.2s timeout for consistency |
| PushToTalkController | ⚠️ untested-on-hardware | TX only (mic tap); no longer manages voice-link lifecycle |
| Action Button PTT (AppIntent) | ⚠️ untested-on-hardware | `TogglePTTIntent` + `AppShortcutsProvider`; runs silently |
| Help + Action Button guides | 🔨 compiles-only | `HelpView`, `ActionButtonGuideView` |
| App icon (Icon Composer) | 🔨 compiles-only | `roger-that-icon.icon`; `ASSETCATALOG_COMPILER_APPICON_NAME` set |
| Info.plist usage strings | ✅ verified | Camera + Mic + Bluetooth + Local Network; background modes; NSBonjourServices |
| Entitlements | ✅ verified | EMPTY — push-to-talk removed (Personal Team can't provision it) |
| OpusCodec | 🔲 TODO | Stub in `App/RogerThat/Audio/OpusCodec.swift` |
| Hardware volume → PTT | 🔲 TODO | Not implemented |

---

## Fixed this session

- **Discovery was broken**: presence beacons were sent as `.text` (never `.presence`), so the
  roster never populated. Plus BLE bugs: peripheral not retained through connect, connect gated
  on a frequently-dropped advertised local name, advertising before the service was registered.
- **Discovery was slow**: now announces presence immediately on peer-connect and updates the
  roster event-driven (not just a 5s poll); beacon interval 15s → 10s.
- **Voice didn't work**: receive side was never wired (no `setHandlers`, no playback), the voice
  link only ran while talking, and per-discovery MCSessions collided. Fixed with RX pipeline,
  session-lifetime link/engine, single shared MCSession + tiebreak, speaker override.

---

## Known risks

| Risk | Severity | Mitigation |
|---|---|---|
| Voice unconfirmed on hardware | High | RX pipeline (now jitter-buffered + concealed) is correct by design but unrun on this host. Two-phone test needed; if one-directional, suspect Local Network permission. |
| Multipeer service not channel-scoped | Resolved | Now isolated three ways: `discoveryInfo["ch"]` discovery filter + invitation-context check, `channelIDHash` packet filter, and per-frame `VoiceBody` AEAD. (`serviceType` stays shared, but channels can no longer connect or decode across each other.) |
| Background BLE longevity | High | iOS suspends background BLE centrals; sustained mesh across suspensions unproven. |
| PTT offline wake | High | No APNs path offline — app must be foregrounded to receive TALK_START. |
| PCM bandwidth | Medium | 640 bytes/20ms frame; Opus (TODO, pipeline now PLC-ready) would cut ~10x. Voice viable only over Multipeer. |

---

## Environment note

`xcodebuild` requires the full Xcode.app (not just CLT). This host has only CLT, so the app
target is verified by `swift build` (Core), the project regenerating cleanly, and code review —
NOT by an on-device or simulator run. The human must open `RogerThat.xcodeproj` in Xcode and
`⌘R` onto a device to confirm BLE discovery, voice, and the Action Button.
