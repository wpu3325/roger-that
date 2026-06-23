import Foundation
import RogerThatCore

// TODO: Integrate the libopus C library via a Swift package binary target or a
// local xcframework. Steps:
//   1. Add libopus as a SystemLibrary or BinaryTarget in Package.swift.
//   2. Import the C module and bridge opus_encode/opus_decode.
//   3. Replace the `RawPCMCodec()` default in AudioEngineIO with `OpusCodec()`.
//
// Until then, `RawPCMCodec` is used and all voice is transmitted as raw PCM
// (20 ms frames @ 16 kHz mono 16-bit = 640 bytes/frame).
//
// struct OpusCodec: AudioCodec {
//     func encode(pcm: Data) throws -> Data { ... }
//     func decode(frame: Data) throws -> Data { ... }
// }
