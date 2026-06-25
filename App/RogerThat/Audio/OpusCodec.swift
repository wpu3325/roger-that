import Foundation
import RogerThatCore

// Opus integration — the single biggest remaining voice-quality/bandwidth win.
//
// Raw PCM is 640 bytes/frame (20 ms @ 16 kHz mono 16-bit). Opus wideband at the same
// rate is ~40–80 bytes/frame — roughly 10× less data over BLE/Multipeer, which is what
// turns congested links from "choppy" into "clear". Opus also provides real packet-loss
// concealment: the decoder can synthesize a missing frame from prior audio.
//
// Integration steps (must be done in Xcode — needs the C library + a device build):
//   1. Add libopus as a SystemLibrary or BinaryTarget (xcframework) — in the App target,
//      NOT RogerThatCore (Core stays Foundation+CryptoKit only, Linux-buildable).
//   2. Bridge opus_encode/opus_decode behind this type.
//   3. Swap the `RawPCMCodec()` default in `AudioEngineIO.codec` for `OpusCodec()`.
//   4. Wire decoder PLC into `AudioEngineIO.playConcealment()` (call opus_decode with a
//      null payload) instead of the current last-frame-fade fallback.
//
// The rest of the pipeline is already Opus-ready: frames are fixed 20 ms, carry a
// per-burst sequence number, and run through `RogerThatCore.VoiceJitterBuffer`, which
// detects losses and asks for concealment exactly where Opus PLC belongs.
//
// struct OpusCodec: AudioCodec {
//     func encode(pcm: Data) throws -> Data { /* opus_encode */ }
//     func decode(frame: Data) throws -> Data { /* opus_decode */ }
// }
