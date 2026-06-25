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
| `Sources/RogerThatCore/Transport/LinkHub.swift` | Fans one shared Link out to N per-channel ports (multi-channel) |
| `Sources/RogerThatCore/Channel/ChannelMetadata.swift` | Codable persisted record of a joined channel |
| `Sources/RogerThatCore/Protocol/VoiceBody.swift` | Seal/open voice frame bodies with the channel key |
| `Sources/RogerThatCore/Crypto/PasswordKey.swift` | PBKDF2 channel key from name+password; verification fingerprint |
| `App/RogerThat/AppState.swift` | @MainActor; multi-channel sessions over a shared hub, active-channel mirror |
| `App/RogerThat/Persistence/ChannelStore.swift` | Joined channels: metadata in UserDefaults, keys in Keychain |
| `App/RogerThat/UI/ChannelListView.swift` | Channel-list home with unread badges + lock icons |
| `App/RogerThat/Transports/BLEMeshLink.swift` | Dual peripheral+central CoreBluetooth |
| `App/RogerThat/Transports/MultipeerVoiceLink.swift` | Single-MCSession voice link (tiebreak invites) |
| `App/RogerThat/Audio/AudioEngineIO.swift` | Mic capture + AVAudioPlayerNode playback + RMS levels |
| `App/RogerThat/PTT/PushToTalkController.swift` | Half-duplex PTT; TALK_START/END packetization |
| `App/RogerThat/PTT/TogglePTTIntent.swift` | AppIntent for Action Button PTT toggle |
| `App/RogerThat/UI/HelpView.swift` | In-app how-to guide |
| `App/RogerThat/UI/ActionButtonGuideView.swift` | Step-by-step Action Button setup |
| `project.yml` | XcodeGen spec; edit this, not the .pbxproj |

## Testing

73 unit tests across 9 suites — all in `Tests/RogerThatCoreTests/`:

```bash
swift test               # run all 73 tests
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

- **Voice RX needs four things wired**: (1) `voice.setHandlers(onReceive:)` in `AppState`
  to decode VOICE_FRAME/TALK_* off the Multipeer link, (2) `RogerThatCore.VoiceJitterBuffer`
  to reorder/dedup/conceal incoming frames before playback, (3) `AudioEngineIO` playback via
  an `AVAudioPlayerNode` (`startSession`/`playEncoded`/`playConcealment`), (4) the voice link
  + audio engine started on channel JOIN — not on PTT. A listener who never talks must still
  advertise/browse and run the engine, or no Multipeer connection forms and nothing plays.
  PTT only installs the mic tap (TX); it must NOT start/stop the voice link.

- **Voice frame body layout**: the inner body is `[sessionID u32 BE][seq u32 BE][encoded
  frame]`, but it's **sealed** — `RogerThatCore.VoiceBody.seal`/`open` ChaChaPoly-encrypts it
  with the channel key (the Multipeer path bypasses FloodRouter's crypto, so it does its own).
  VOICE_FRAME carries `flags: .bodyEncrypted`. VOICE/TALK packets carry the **real
  `channelIDHash`** (not `0` anymore — that was the cross-channel bleed) and `AppState`
  drops any whose hash ≠ the active channel. They still bypass the flood router (direct over
  Multipeer).

- **Multipeer is channel-scoped via discoveryInfo**: `serviceType` is shared across all
  channels (its 15-char limit can't hold a hash), so `MultipeerVoiceLink` advertises the
  channel hash in `discoveryInfo["ch"]`, the browser only invites peers whose `ch` matches,
  and the advertiser only accepts invitations whose **context** is the channel token. Three
  layers keep channels apart for voice: this discovery filter, the `channelIDHash` packet
  filter, and per-frame `VoiceBody` encryption (a stray cross-channel frame is undecryptable).

- **Multipeer voice topology**: use ONE shared `MCSession` for the channel + an invitation
  tiebreak (only the peer with the larger `MCPeerID.displayName` invites). A new MCSession per
  discovery/invitation makes both peers invite each other → competing sessions that never reach
  `.connected` → no audio. See `MultipeerVoiceLink`.

- **`MCPeerID` must be unique per device** (`RT-<localID>`): handles key off displayName and the
  tiebreak needs distinct names. User-facing names come from the BLE roster, not MCPeerID.

- **Remote-talking banner needs a watchdog**: TALK_START/END are single `.unreliable` packets;
  drive the "X is talking" state from voice-frame flow + a ~1.2s timeout (`AppState.showRemoteTalking`)
  so a dropped control packet can't leave it missing or stuck.

- **Loudspeaker, not earpiece**: `.voiceChat` mode forces the quiet earpiece AND pumps
  the signal (AGC/AEC), which sounds choppy. PTT is half-duplex (never capture+play at
  once), so `AudioEngineIO` uses `.playAndRecord` + mode `.default` + `.defaultToSpeaker`,
  then `overrideOutputAudioPort(.speaker)`. A `routeChangeNotification` observer re-asserts
  the speaker ONLY when stuck on `.builtInReceiver` (so it won't steal headphones/Bluetooth).

- **Crisp voice — TX side (`AudioEngineIO`)**: (1) the capture `AVAudioConverter` input block
  must feed the source buffer once then return `.noDataNow` — returning the same buffer on
  every re-request double-consumes samples and garbles audio; (2) emit fixed 320-sample
  (640-byte) frames via a TX accumulator. Don't `setPreferredSampleRate(16000)` — let the
  mixer resample; forcing the hardware rate glitches.

- **Crisp voice — RX side (`VoiceJitterBuffer` in Core)**: ordering/dedup/loss-conceal is
  pure logic in `RogerThatCore.VoiceJitterBuffer` (unit-tested), NOT in `AudioEngineIO`.
  `AppState.handleVoicePacket` parses `[sessionID][seq]` (big-endian) — these were previously
  decoded and thrown away — and feeds the buffer; it returns `.play`/`.conceal` in order.
  `AudioEngineIO.playEncoded` then schedules immediately (the cushion is the buffer's prime
  depth), and `playConcealment` bridges a lost frame with a last-frame fade (Opus PLC later).
  A new `sessionID` (per talk burst) auto-resets; also `reset()` on talkEnd / leave.

- **Half-duplex lockout**: PTT is half-duplex, so block local TX while a peer holds the floor.
  `AppState.canStartTalking` is false during `.talkingRemote`; `TalkButton` dims + disables and
  all three start paths (hold, toggle, `TogglePTTIntent`) guard on it. Without this, two
  simultaneous talkers garble each other (no AEC in `.default` mode).

- **Audio engine must survive interruptions**: a phone call, Siri, route change, or media
  reset stops `AVAudioEngine` and it never restarts on its own — voice silently dies until
  rejoin. `AudioEngineIO` observes `interruptionNotification` (.ended), `.AVAudioEngineConfigurationChange`,
  and `mediaServicesWereResetNotification`, and calls `restartEngine()`. `startSession` swallows
  start failures (mic not yet granted / session busy) and relies on these + the next frame to retry.

- **PTT sound cues + text haptic**: `SoundEffects.shared` (in `Audio/Feedback.swift`,
  `@MainActor`) plays `start_talk`/`end_talk` from `PushToTalkController.start/stopTalking`
  via `MainActor.assumeIsolated` (both PTT entry points are already on main). Incoming text
  fires `Haptics.messageReceived()` from `AppState`'s message handler. The cue files live in
  `App/RogerThat/Resources/Sounds/` (xcodegen bundles `.mp3` as resources at the bundle root)
  and are AAC-in-QuickTime despite the `.mp3` extension — `AVAudioPlayer` decodes by content.

- **Chat UI (iMessage-style)**: `ChatMessage.kind` is `.message` or `.system`; post
  `.system("X joined")` from `AppState.syncRoster` (tracked via `knownMemberIDs`, cumulative
  to avoid BLE flap spam). `TextChannelView` groups consecutive same-sender messages and
  swipe-left reveals timestamps via a `simultaneousGesture` drag.

- **PTT background wake**: PTChannelManager needs APNs. Fully offline = app must
  be in foreground to receive TALK_START.

- **Multi-channel = one shared radio, N sessions, one active**: you can join several
  channels. `AppState` runs ONE channel-agnostic `BLEMeshLink` through a `LinkHub`, which
  vends a port per channel to its own `SessionManager` (each filters its `channelIDHash`).
  Only ONE channel is *active* (open) at a time — its voice link + audio engine are the only
  ones running, and its data is mirrored into `channel`/`members`/`messages`/`floorState`/
  `voiceLevel` so the in-channel views didn't change. Background channels still collect text/
  presence and bump `unreadByChannel`. `setActive(nil)` returns to the list (stays joined);
  `setActive(id)` opens one (swaps the voice stack). Don't give each channel its own BLE
  stack — `Link.setHandlers` has a single handler, which is exactly why `LinkHub` exists.

- **Channel persistence**: `ChannelStore` saves metadata (`[ChannelMetadata]` JSON) in
  UserDefaults and the 32-byte key in the Keychain under `channelID`. On launch `AppState`
  reloads them and starts all sessions (background collection begins immediately); the app
  opens on the channel list, not in a channel.

- **Password channels = derive, don't share**: `PasswordKey.channel(name:password:)` derives
  the key via PBKDF2-HMAC-SHA256 (100k iters, salt = name) and the channelID from that key —
  so creating and joining are the SAME operation (enter name+password → derive → join), and
  different passwords don't even share a `channelIDHash`. `kind: .password` (lock icon in the
  list). PBKDF2 is deliberately slow — derive on a tap or on enter, NEVER per keystroke.
  `PasswordKey.fingerprint(of:)` is a short non-secret code (HKDF) both sides compare to
  confirm they typed the same password. PBKDF2 is hand-rolled on CryptoKit HMAC (single
  block, dkLen == 32) to keep Core platform-agnostic; verified against the RFC test vectors.

## Device install (current state)

Signing is already configured in `project.yml`. Steps:
1. `xcodegen generate` if project is stale, reload in Xcode (banner: "Load Changes")
2. Connect iPhone, select it as run destination, `⌘R`
3. Trust developer profile: Settings → General → VPN & Device Management
4. Grant Mic + Bluetooth + Local Network on first launch
5. Re-sign every 7 days (free Personal Team limit) — just run `⌘R` with phone connected
