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

**RogerThat** (`App/RogerThat/`) — iOS 17+ app. All device-only APIs live here:
CoreBluetooth, MultipeerConnectivity, AVFoundation, AppIntents, SwiftUI.

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
| `App/RogerThat/Transports/MultipeerVoiceLink.swift` | Single-MCSession voice link (tiebreak invites) |
| `App/RogerThat/Audio/AudioEngineIO.swift` | Mic capture + AVAudioPlayerNode playback + RMS levels |
| `App/RogerThat/PTT/PushToTalkController.swift` | Half-duplex PTT; TALK_START/END packetization |
| `App/RogerThat/PTT/TogglePTTIntent.swift` | AppIntent for Action Button PTT toggle |
| `App/RogerThat/UI/HelpView.swift` | In-app how-to guide |
| `App/RogerThat/UI/ActionButtonGuideView.swift` | Step-by-step Action Button setup |
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

- **New files need xcodegen**: `App/RogerThat/` is a glob — run `xcodegen generate`
  and reload in Xcode after adding any new `.swift` file. Safe to regenerate; signing
  settings are baked into `project.yml` (Team `TPYY95V67H`, Bundle ID `com.wilsonpu.rogerthat`,
  Automatic signing, iOS 17+, portrait-only).

- **`AudioCodec` ambiguity**: qualify as `RogerThatCore.AudioCodec` when importing
  `AVFoundation` — AudioToolbox (transitive) also defines a C type named `AudioCodec`.

- **`@preconcurrency import AVFoundation`**: `AVAudioPCMBuffer` is non-Sendable but
  `AVAudioConverterInputBlock` is `@Sendable`; capturing the buffer trips Swift 6 strict
  concurrency. The compiler suggests exactly this fix.

- **`CBPeripheralManager` restore identifier**: providing `CBPeripheralManagerOptionRestoreIdentifierKey`
  requires implementing `peripheralManager(_:willRestoreState:)` — NOT the non-existent
  `peripheralManagerDidRestoreState`. Wrong name compiles but crashes at runtime.

- **`CBUUID` / `MCPeerID` globals in Swift 6**: module-level `let` constants of these
  types must be `nonisolated(unsafe) let` to satisfy the concurrency checker.

- **`AppIntent` static properties**: use `static let`, not `static var` — Swift 6 flags
  mutable statics on value types as non-concurrency-safe.

- **Push to Talk entitlement removed**: requires paid Apple Developer account ($99/yr).
  Personal Team cannot provision it. App uses in-app PTT button + Action Button instead.
  Do not re-add `com.apple.developer.push-to-talk` to the entitlements file.

- **`withUnsafeBytes` ambiguity in Swift 6**: inside a `Data` extension method, the
  compiler resolves it as an instance method. Always qualify: `Swift.withUnsafeBytes(of:)`.

- **XCTest unavailable without Xcode.app**: this host has CLT only. Use `import Testing`
  for all test files. NOTE: as of CLT Swift 6.3.2 the `swift test` runner itself fails with
  `no such module 'Testing'` — verify Core with `swift build`; run the suite from Xcode.

- **Roster/discovery = BLE presence beacons, not Multipeer**: members appear only when
  `.presence` packets flow over `BLEMeshLink`. `FloodRouter.send(presence:)` produces them;
  `send(text:)` produces `.text`. Don't send presence via `send(text:)` (it lands in chat,
  never the roster). FloodRouter only flood-routes `.text` + `.presence`.

- **CoreBluetooth peripheral retention**: you MUST keep a strong reference to a `CBPeripheral`
  from `didDiscover` through connection, or ARC frees it and the connect silently aborts.
  See `discoveredPeripherals` in `BLEMeshLink`.

- **Don't gate BLE connect on advertised local name**: the 31-byte advert often drops
  `CBAdvertisementDataLocalNameKey`. Connect to any peripheral with our serviceUUID; channel
  isolation is enforced at the packet layer (channelIDHash + body encryption).

- **Advertise only after `peripheralManager(_:didAdd:)`**: `add(service)` is async; advertising
  immediately can expose an empty service (no characteristic → no subscription → no presence).

- **XcodeGen overwrites Info.plist and entitlements** when the `info:` key is used.
  All plist keys (usage strings, background modes, NSBonjourServices) live in
  `project.yml` under `info.properties`, not in the plist file itself.

- **Icon Composer `.icon` files**: `App/RogerThat/roger-that-icon.icon` is a directory bundle.
  Set `ASSETCATALOG_COMPILER_APPICON_NAME: roger-that-icon` (base name, no extension) in
  project.yml, or the build fails looking for an "AppIcon" asset set.

- **`UIRequiresFullScreen: true`**: required for a portrait-only app to silence the
  "all interface orientations must be supported" validation (project.yml info.properties).

- **TextField + `@AppStorage`**: a field bound directly to `@AppStorage` writes on every
  keystroke (and can collapse edit UI mid-type). Type into a local `@State` draft, commit on
  submit. See the call-sign field in `CreateOrJoinView`.

- **Signing is fully configured in `project.yml`**: `CODE_SIGN_STYLE: Automatic`,
  `DEVELOPMENT_TEAM: TPYY95V67H`, `PRODUCT_BUNDLE_IDENTIFIER: com.wilsonpu.rogerthat`.
  Building under a different Apple ID means changing Team + Bundle ID in both Xcode and
  `project.yml` (see `RUN_ON_DEVICE.md` Step 2a). Free Personal Team certs expire after
  7 days — reconnect the phone and `⌘R` to re-sign.

- **TTL semantics**: TTL=8 means 8 relay-hops, so the message reaches the node
  at distance **9** from the originator (not 8). Node at distance 9 receives but
  doesn't relay (TTL=0 on arrival). Confused the test bounds once — see git history.

- **Opus**: not integrated. Default is `RawPCMCodec` (640 bytes/frame @ 16kHz).
  Stub is in `App/RogerThat/Audio/OpusCodec.swift`.

- **Voice RX needs three things wired**: (1) `voice.setHandlers(onReceive:)` in `AppState`
  to decode VOICE_FRAME/TALK_* off the Multipeer link, (2) `AudioEngineIO` playback via an
  `AVAudioPlayerNode` (`startSession`/`playEncoded`), (3) the voice link + audio engine
  started on channel JOIN — not on PTT. A listener who never talks must still advertise/browse
  and run the engine, or no Multipeer connection forms and nothing plays. PTT only installs
  the mic tap (TX); it must NOT start/stop the voice link.

- **Voice frame body layout**: `[sessionID u32 BE][seq u32 BE][encoded frame]`. VOICE/TALK
  packets use `channelIDHash: 0` and bypass the flood router (they go direct over Multipeer).

- **Multipeer voice topology**: use ONE shared `MCSession` for the channel + an invitation
  tiebreak (only the peer with the larger `MCPeerID.displayName` invites). A new MCSession per
  discovery/invitation makes both peers invite each other → competing sessions that never reach
  `.connected` → no audio. See `MultipeerVoiceLink`.

- **`MCPeerID` must be unique per device** (`RT-<localID>`): handles key off displayName and the
  tiebreak needs distinct names. User-facing names come from the BLE roster, not MCPeerID.

- **Remote-talking banner needs a watchdog**: TALK_START/END are single `.unreliable` packets;
  drive the "X is talking" state from voice-frame flow + a ~1.2s timeout (`AppState.showRemoteTalking`)
  so a dropped control packet can't leave it missing or stuck.

- **Force loudspeaker for voice**: `.voiceChat` mode routes to the earpiece; call
  `overrideOutputAudioPort(.speaker)` after `setActive(true)`.

- **Chat UI (iMessage-style)**: `ChatMessage.kind` is `.message` or `.system`; post
  `.system("X joined")` from `AppState.syncRoster` (tracked via `knownMemberIDs`, cumulative
  to avoid BLE flap spam). `TextChannelView` groups consecutive same-sender messages and
  swipe-left reveals timestamps via a `simultaneousGesture` drag.

- **PTT background wake**: PTChannelManager needs APNs. Fully offline = app must
  be in foreground to receive TALK_START.

## Device install (current state)

Signing is already configured in `project.yml`. Steps:
1. `xcodegen generate` if project is stale, reload in Xcode (banner: "Load Changes")
2. Connect iPhone, select it as run destination, `⌘R`
3. Trust developer profile: Settings → General → VPN & Device Management
4. Grant Mic + Bluetooth + Local Network on first launch
5. Re-sign every 7 days (free Personal Team limit) — just run `⌘R` with phone connected
