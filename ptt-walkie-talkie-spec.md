# Push-to-Talk Walkie-Talkie — Prototype Spec & Roadmap

iOS-first, offline-first group voice and text for bad-service areas (dense cities, hikes, ski slopes). Two behaviors only: **direct live voice** and **flooded text**. Designed for very low power and to extend cleanly to Android, satellite relay, and a range-extender radio later.

---

## 1. Goal & scope

A small group joins a shared channel while together, then disperses. Within the channel they can:

- **Talk live** to anyone within direct radio range (half-duplex push-to-talk).
- **Text** anyone in the channel, with messages relayed hop-by-hop through other members' phones so they reach people beyond direct range.

### In scope for the prototype
- iOS ↔ iOS only.
- Live voice over on-demand peer Wi-Fi (Multipeer Connectivity).
- Text over an always-on, low-power BLE mesh with multi-hop flooding.
- Channel create/join in proximity via QR or short code, with payload encryption.
- Presence (who's still on the channel).
- System push-to-talk UX via Apple's PushToTalk framework.

### Explicit non-goals (deferred — see roadmap)
- Android and cross-platform iOS↔Android.
- **Voice clips / store-and-forward voice ("voice flooding").** Deferred precisely because each hop is expensive in bandwidth and battery. Live voice is direct-only.
- Internet / satellite relay.
- LoRa or any external range-extender hardware.
- Delivery acknowledgements / read receipts.
- Large channels beyond a single direct mesh (~8 directly-connected peers per Multipeer session).
- Maps, accounts, message history sync, media attachments.

---

## 2. Core model

| Behavior | Transport | Relayed? | Power | Range |
|---|---|---|---|---|
| Live voice | Peer Wi-Fi (Multipeer), on-demand | No — direct only | High, but only while talking | Direct radio range |
| Text | BLE, always-on | Yes — flooded, multi-hop | Very low | Whole connected channel |
| Presence | BLE, periodic | No (or 1-hop) | Very low | Direct neighbors |

The guiding rule: **the mesh relays messages, not live streams.** If a peer is out of direct voice range, you reach them by text, not by chaining audio.

---

## 3. Architecture

Everything above the transport abstraction is written once and is radio-agnostic. Each transport is a swappable `Link`.

```
App UX + PushToTalk framework
        │
Session manager  (channels · roster · PTT floor · flood/dedup · routing)
        │
Audio pipeline   (capture → Opus → playback)   +   Message types
        │
Wire protocol    (transport-agnostic packets)
        │
Transport abstraction (Link interface)
   ├── BLE Link            (Core Bluetooth)        ← text + presence, always-on
   ├── Wi-Fi Link          (Multipeer Connectivity)← live voice, on-demand
   ├── [later] Relay Link  (internet / satellite)
   ├── [later] Nearby Link (Android)
   └── [later] LoRa Link   (range device)
```

`Link` contract (narrow on purpose):
- `discover()` / `stopDiscovery()`
- `neighbors() -> [PeerHandle]`
- `send(packet, to: [PeerHandle])`
- `onReceive(packet, from: PeerHandle)`
- `linkQuality(PeerHandle) -> {latency, bandwidth}` (used later for routing)

---

## 4. Transports

### BLE Link (Core Bluetooth) — the always-on substrate
- Each device acts as both peripheral (advertises channel presence) and central (scans for channel members).
- Carries presence and text only — small payloads, duty-cycled scanning, background-friendly on iOS (more permissive than background Wi-Fi).
- Message exchange via a GATT characteristic write (simple) or an L2CAP channel (higher throughput; preferred if text volume grows).
- Advertise a fixed service UUID for the app; include a truncated channel-id hash so scanning devices can pre-filter without connecting.

### Wi-Fi Link (Multipeer Connectivity) — on-demand voice
- Stays **dark** until a push-to-talk press AND at least one channel member is a direct neighbor.
- On press: bring up the Multipeer session, stream Opus voice frames to directly-connected peers, tear down shortly after release.
- `MCSession` is for small groups (~8 peers) — fine for a cluster, and we never relay voice, so this ceiling is acceptable.

---

## 5. Wire protocol

Big-endian. Fixed common header, type-specific body. Header is cleartext (needed for dedup, scoping, routing); body is encrypted under the channel key.

### Common header (22 bytes)

| Field | Type | Bytes | Notes |
|---|---|---|---|
| `version` | u8 | 1 | Protocol version, starts at 1 |
| `type` | u8 | 1 | 0 PRESENCE · 1 TEXT · 2 VOICE_FRAME · 3 TALK_START · 4 TALK_END |
| `flags` | u8 | 1 | bit0 = encrypted body |
| `ttl` | u8 | 1 | Hops remaining (TEXT only; ignored otherwise) |
| `channelId` | u32 | 4 | Truncated hash of channel id, for fast cleartext scoping |
| `senderId` | u32 | 4 | Per-device id (random at install) |
| `messageId` | u64 | 8 | Unique per message; dedup key for flooding |
| `payloadLen` | u16 | 2 | Length of body that follows |

### Bodies (encrypted: 12-byte nonce ‖ ciphertext ‖ 16-byte tag)

- **PRESENCE** — `displayName` (length-prefixed UTF-8). Optional later: status, battery.
- **TEXT** — UTF-8 message bytes.
- **VOICE_FRAME** — `talkSessionId` u32, `seq` u32, then one Opus frame. Never flooded; sent only to direct peers over the Wi-Fi Link.
- **TALK_START / TALK_END** — `talkSessionId` u32. Control only.

### Encryption
- AEAD (ChaCha20-Poly1305 or AES-GCM) with the channel's shared symmetric key.
- Nonce: random 12 bytes prepended to the body.
- Cleartext header intentionally leaks only channel-hash, sender, message-id, and size — acceptable for the prototype; revisit if metadata privacy becomes a requirement.

---

## 6. Flooding spec (TEXT only)

Controlled flooding with TTL and de-duplication. No routing tables — robust to a constantly-changing topology.

**State per device:** a `seenCache` — an LRU/time-bounded set of `(senderId, messageId)` keys. Suggested bound: ~5,000 entries or 10-minute expiry, whichever first.

**On send (originating a text):**
1. Assign `messageId` (monotonic counter or random 64-bit).
2. Set `ttl` to default (start with 8).
3. Add own `(senderId, messageId)` to `seenCache`.
4. Broadcast to all BLE neighbors.

**On receive a TEXT packet:**
1. If `channelId` hash doesn't match a joined channel → drop.
2. If `(senderId, messageId)` in `seenCache` → drop (already handled).
3. Add to `seenCache`. Decrypt; deliver to local UI.
4. If `ttl > 0`: decrement `ttl`, then rebroadcast to all neighbors **except the one it arrived from** (split-horizon), after a small random jitter (20–100 ms) to avoid collision storms.

**Notes**
- MVP is best-effort: no acknowledgements, no retransmission. A message that never reaches a fully-disconnected peer is simply lost. (Store-carry-forward across gaps and optional end-to-end acks are later additions.)
- TTL of 8 comfortably covers channel-sized groups; tune against field tests.

---

## 7. Live voice spec

- **Press:** send `TALK_START(talkSessionId)` to direct peers, activate the audio session, bring up the Wi-Fi Link, start capture.
- **Capture path:** `AVAudioEngine` mono @ 16–24 kHz → Opus 20 ms frames @ ~16–24 kbps → `VOICE_FRAME` packets to direct neighbors.
- **Receive path:** decode → 2–4 frame jitter buffer → playback.
- **Release:** send `TALK_END`, stop capture, tear down the Wi-Fi Link after a short grace period.
- **Floor control:** optimistic half-duplex — on `TALK_START`, receivers show "X is talking" and lock/duck their own mic; last-start-wins on the rare collision. No token arbiter in the prototype.
- **Range:** direct only. If no direct peer is present, voice is simply not delivered — text is the fallback. This is by design, not a bug.

---

## 8. Channel & session model

- **Create:** generate a `channelId` and a symmetric channel key on-device.
- **Join (in proximity, before dispersal):** transfer `{channelId, key, displayName}` via QR code or short numeric code. This seeds every device — no server needed in the field.
- **Identity:** `senderId` is a random per-install id; `displayName` is user-set and shared via presence.
- **Scoping:** a device only processes, surfaces, and relays packets whose `channelId` hash matches a joined channel. Other nearby channels' traffic passes through the air but is ignored and unreadable.
- **Walkie-talkie semantics:** press talk → everyone on the channel in direct range hears you live; text → everyone on the channel, relayed to those out of range.

---

## 9. Power design

The whole reason the two behaviors are split this way:

- **BLE always-on, duty-cycled** for presence + text. This is the steady-state cost and it's tiny.
- **Wi-Fi only in bursts** — spun up on a talk press when a direct peer exists, town down on release. No idle Wi-Fi scanning.
- **Half-duplex PTT** — idle listening is cheap; the phone only transmits while the button is held.
- **Relay cost is real but bounded** — relaying text over BLE is cheap, but a phone in the middle of a long chain still does more work than an endpoint. Acceptable for the prototype; later, duty-cycle relays harder or rotate the load, trading a little latency for battery fairness.

Design rule: nothing high-power runs unless the user is actively talking.

---

## 10. Tech stack

- **Language / OS:** Swift, iOS 16+ (required for the PushToTalk framework).
- **Live voice transport:** Multipeer Connectivity.
- **Mesh transport:** Core Bluetooth (peripheral + central roles).
- **Audio:** AVAudioEngine; libopus via a Swift Package wrapper.
- **PTT UX:** PushToTalk framework (`PTChannelManager`) — requires the Push to Talk entitlement.
- **Crypto:** CryptoKit (AEAD + key handling).
- **Backend:** none.

---

## 11. Roadmap

### Prototype (P0–P4)

**P0 — Opus audio loop, single device** *(~2–4 days)*
Capture → Opus encode → decode → playback on one phone. Proves the codec integration and that audio is intelligible at the target bitrate.

**P1 — Two-iPhone live PTT** *(~1–2 weeks)*
Direct half-duplex talk over Multipeer with a hardcoded channel and the PushToTalk UX. Field-test real range in a forest, a parking garage, and an open slope. Proves the core feel and gives real range numbers.

**P2 — BLE text mesh: flooding + dedup** *(~2–3 weeks) — the spine of the prototype*
Core Bluetooth presence + text with TTL flooding and the seen-cache. Get a text to chain end-to-end across 3–4 iPhones spread down a trail. This is the genuinely new, load-bearing code and where the power story is won.

**P3 — Channel model + crypto** *(~1–2 weeks)*
Create/join via QR or short code; channel-id scoping; AEAD payload encryption under the channel key.

**P4 — Unify, presence, power-tune, field-test** *(~2–3 weeks)*
One app: live voice + flooded text + presence roster, with PushToTalk UX. Measure battery in steady state and while relaying. Full field tests across all four target scenarios. **End of prototype.**

### Post-prototype roadmap (P5+)

**P5 — Voice clips (store-and-forward, the deferred "voice flooding").**
A press-to-talk recording delivered as a flooded message to peers out of live range. Reuses the text flooding path with a larger payload; arrives seconds late. This is where far-apart members can finally exchange voice, asynchronously.

**P6 — Internet / satellite relay Link.**
A relay path for peers reachable via any internet (cell, Wi-Fi, or transparent direct-to-cell satellite). Carries text and voice clips — not live voice — since satellite is low-bandwidth and high-latency.

**P7 — Android via Nearby Connections.**
A second platform island speaking the identical wire protocol (Opus + the packet spec above), validated within Android first.

**P8 — Cross-platform bridge.**
Prototype iOS↔Android peer Wi-Fi interop via Wi-Fi Aware (newly possible on iOS 26, but unproven for cross-vendor connections — must be measured, not assumed).

**P9 — LoRa range-extender device.**
A small companion radio as another store-and-forward `Link` for kilometer-scale text and clips. (Live voice at that range needs a different, regulated voice-radio module — a separate hardware effort, not this Link.)

---

## 12. Risks to validate early

1. **Background BLE longevity (highest risk).** How long can the text/presence mesh keep running with the screen off and no internet? Test in P2, not at the end.
2. **PushToTalk offline wake.** Its background-wake leans on a network push; with no internet there's no push, so deep-background offline receive is best-effort. Scope expectations accordingly.
3. **Multipeer voice range & reconnect** in real terrain — measured in P1.
4. **Flooding under churn.** Behavior as people move in and out of range; tune TTL, jitter, and cache bounds against real tests.
5. **Sustained relay battery drain** on mid-chain phones — measured in P4.

---

## 13. Decisions locked for the prototype

- Text floods (multi-hop). Live voice does not — direct only.
- Voice clips are deferred (P5); they are "voice flooding" and too expensive per hop for the prototype.
- iOS-first; Android and cross-platform are post-prototype.
- Best-effort delivery; no acknowledgements in the prototype.
- No backend; channels are seeded peer-to-peer in proximity.
