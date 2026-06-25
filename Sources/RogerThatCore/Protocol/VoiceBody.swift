import Foundation

/// Wire body for `VOICE_FRAME` packets.
///
/// The voice path bypasses `FloodRouter` (frames go direct over Multipeer), so it doesn't
/// get the router's body encryption for free. This type gives voice the same protection
/// TEXT has: an inner layout
///
///     [sessionID u32 BE][seq u32 BE][encoded audio frame]
///
/// sealed with the channel key (ChaChaPoly via `ChannelCrypto`). Only channel members can
/// open it, so even if two channels share a Multipeer session the audio of one is
/// unintelligible — and undecryptable — to the other.
///
/// Each frame is sealed independently (its own nonce), which suits an unreliable transport
/// where frames are dropped and reordered: any frame decrypts on its own.
public enum VoiceBody {

    /// Plaintext inner layout, before encryption.
    static func pack(sessionID: UInt32, seq: UInt32, frame: Data) -> Data {
        var out = Data(capacity: 8 + frame.count)
        out.append(bigEndian(sessionID))
        out.append(bigEndian(seq))
        out.append(frame)
        return out
    }

    /// Parse the plaintext inner layout. Returns nil if it's too short to hold the header.
    static func unpack(_ inner: Data) -> (sessionID: UInt32, seq: UInt32, frame: Data)? {
        let bytes = Data(inner)   // rebase indices to 0
        guard bytes.count >= 8 else { return nil }
        let sessionID = readUInt32(bytes[0..<4])
        let seq = readUInt32(bytes[4..<8])
        let frame = Data(bytes[8...])
        return (sessionID, seq, frame)
    }

    /// Seal for transmit: pack the header + frame, then encrypt with the channel key.
    public static func seal(sessionID: UInt32, seq: UInt32, frame: Data,
                            crypto: ChannelCrypto) throws -> Data {
        try crypto.encrypt(pack(sessionID: sessionID, seq: seq, frame: frame))
    }

    /// Open on receive: decrypt with the channel key, then parse. Returns nil on auth
    /// failure (wrong channel / tampered) or a short body — caller just drops the frame.
    public static func open(_ body: Data,
                            crypto: ChannelCrypto) -> (sessionID: UInt32, seq: UInt32, frame: Data)? {
        guard let inner = try? crypto.decrypt(body) else { return nil }
        return unpack(inner)
    }

    // MARK: - Big-endian helpers

    private static func bigEndian(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Swift.withUnsafeBytes(of: &be) { Data($0) }
    }

    private static func readUInt32(_ bytes: Data) -> UInt32 {
        bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
