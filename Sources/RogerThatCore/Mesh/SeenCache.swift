import Foundation

/// Deduplication cache for flood routing.
///
/// A (senderID, messageID) pair is "seen" until it expires (10-minute TTL)
/// or the cache exceeds its capacity (5,000 entries, evict oldest).
public final class SeenCache: @unchecked Sendable {

    public static let defaultCapacity = 5_000
    public static let defaultTTL: TimeInterval = 600 // 10 minutes

    private struct Entry {
        let key: Key
        let expires: Date
    }

    private struct Key: Hashable {
        let senderID: UInt32
        let messageID: UInt64
    }

    private let capacity: Int
    private let ttl: TimeInterval
    private let lock = NSLock()
    private var entries: [Key: Date] = [:]     // key → expiry
    private var insertionOrder: [Key] = []      // for FIFO eviction

    public init(capacity: Int = defaultCapacity, ttl: TimeInterval = defaultTTL) {
        self.capacity = capacity
        self.ttl = ttl
    }

    /// Returns `true` if this (senderID, messageID) pair is already known.
    public func contains(senderID: UInt32, messageID: UInt64) -> Bool {
        let key = Key(senderID: senderID, messageID: messageID)
        return lock.withLock {
            guard let expiry = entries[key] else { return false }
            if expiry < Date() {
                remove(key: key)
                return false
            }
            return true
        }
    }

    /// Insert a new (senderID, messageID) pair; returns `false` if it was already present.
    @discardableResult
    public func insert(senderID: UInt32, messageID: UInt64) -> Bool {
        let key = Key(senderID: senderID, messageID: messageID)
        return lock.withLock {
            let now = Date()
            if let expiry = entries[key], expiry >= now { return false }

            entries[key] = now.addingTimeInterval(ttl)
            insertionOrder.append(key)

            if insertionOrder.count > capacity {
                evictOldest()
            }
            return true
        }
    }

    // MARK: - Private (must be called under lock)

    private func remove(key: Key) {
        entries.removeValue(forKey: key)
        insertionOrder.removeAll { $0 == key }
    }

    private func evictOldest() {
        while insertionOrder.count > capacity {
            let oldest = insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
