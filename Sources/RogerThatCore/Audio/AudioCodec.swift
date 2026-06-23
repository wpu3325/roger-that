import Foundation

/// Audio codec contract: PCM ↔ compressed frame.
///
/// All implementations are radio-agnostic (no AVFoundation).
/// Default: RawPCMCodec (16 kHz mono 16-bit passthrough).
/// TODO: OpusCodec (device-only, blocked on C library integration).
public protocol AudioCodec: Sendable {
    /// Encode a PCM buffer (16 kHz, mono, Int16) to a compressed frame.
    func encode(pcm: Data) throws -> Data

    /// Decode a compressed frame back to PCM (16 kHz, mono, Int16).
    func decode(frame: Data) throws -> Data
}

/// Errors from audio codecs.
public enum AudioCodecError: Error {
    case encodingFailed
    case decodingFailed
}
