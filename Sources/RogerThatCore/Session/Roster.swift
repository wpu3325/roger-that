import Foundation

/// A member present in the channel.
public struct Member: Identifiable, Sendable, Equatable {
    public let id: UInt32   // senderID
    public var displayName: String
    public var lastSeen: Date

    public init(id: UInt32, displayName: String, lastSeen: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.lastSeen = lastSeen
    }
}

/// Tracks the live presence roster for a channel.
public final class Roster: @unchecked Sendable {

    private let lock = NSLock()
    private var members: [UInt32: Member] = [:]
    /// How long before a member is considered gone (no PRESENCE heard).
    public let expiryInterval: TimeInterval

    public init(expiryInterval: TimeInterval = 60) {
        self.expiryInterval = expiryInterval
    }

    /// Upsert a member from an incoming PRESENCE packet.
    public func upsert(id: UInt32, displayName: String) {
        lock.withLock {
            members[id] = Member(id: id, displayName: displayName)
        }
    }

    /// Remove an explicitly departed member.
    public func remove(id: UInt32) {
        lock.withLock { members.removeValue(forKey: id) }
    }

    /// All members currently seen within the expiry window.
    public func activeMembersSnapshot() -> [Member] {
        let cutoff = Date().addingTimeInterval(-expiryInterval)
        return lock.withLock {
            members.values.filter { $0.lastSeen >= cutoff }
        }
    }
}
