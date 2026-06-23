import Foundation

/// Opaque identifier for a directly-connected peer.
public struct PeerHandle: Hashable, Sendable {
    public let id: String
    public init(_ id: String) { self.id = id }
}
