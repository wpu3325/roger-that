import Foundation

/// Passthrough codec: PCM bytes in, PCM bytes out.
///
/// Format: 16 kHz, mono, signed 16-bit little-endian.
/// Frame size: 320 samples = 20 ms at 16 kHz.
/// This is the default codec for the prototype; replace with OpusCodec once the
/// C library integration is completed.
public struct RawPCMCodec: AudioCodec {
    public init() {}

    public func encode(pcm: Data) throws -> Data { pcm }
    public func decode(frame: Data) throws -> Data { frame }
}
