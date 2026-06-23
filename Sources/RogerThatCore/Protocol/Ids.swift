import Foundation

/// Globally unique identifier for this device install, persistent across sessions.
public struct DeviceID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) { self.rawValue = rawValue }

    /// Generate a random device id.
    public static func random() -> DeviceID {
        DeviceID(UInt32.random(in: .min ... .max))
    }
}

/// Per-message identifier; used for deduplication.
public struct MessageID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) { self.rawValue = rawValue }

    public static func random() -> MessageID {
        MessageID(UInt64.random(in: .min ... .max))
    }
}
