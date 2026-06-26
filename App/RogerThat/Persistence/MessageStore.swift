import Foundation

/// Persists per-channel chat history to disk so it survives app restarts and "leaving"
/// (archiving) a channel. One JSON file per `channelID` under Application Support.
///
/// Writes are **debounced** and run off the main thread, so a burst of appends (typing,
/// presence-driven system notices) coalesces into a single atomic write. Reads are
/// synchronous but cheap and meant to be called from a background task at startup.
final class MessageStore: @unchecked Sendable {

    private let directory: URL
    private let io = DispatchQueue(label: "com.rogerthat.messagestore", qos: .utility)
    private let lock = NSLock()
    /// Latest snapshot per channel awaiting a write (coalesced).
    private var pending: [String: [ChatMessage]] = [:]
    private var flushScheduled = false

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Load a channel's history. Background-callable; returns `[]` if none saved.
    func load(_ channelID: String) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL(for: channelID)),
              let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return [] }
        return msgs
    }

    /// Save a channel's full history. Debounced + off-main: rapid appends become one write.
    func save(_ messages: [ChatMessage], for channelID: String) {
        let schedule: Bool = lock.withLock {
            pending[channelID] = messages
            if flushScheduled { return false }
            flushScheduled = true
            return true
        }
        guard schedule else { return }
        io.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    /// Permanently remove a channel's history file (used by "Delete channel").
    func delete(_ channelID: String) {
        lock.withLock { pending[channelID] = nil }
        io.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.fileURL(for: channelID))
        }
    }

    // MARK: - Private

    private func flush() {
        let snapshot: [String: [ChatMessage]] = lock.withLock {
            flushScheduled = false
            let p = pending
            pending = [:]
            return p
        }
        for (id, msgs) in snapshot {
            guard let data = try? JSONEncoder().encode(msgs) else { continue }
            try? data.write(to: fileURL(for: id), options: .atomic)
        }
    }

    private func fileURL(for channelID: String) -> URL {
        // channelIDs are hex / "pw-"+hex / url-safe-base64 — already filesystem-safe, but
        // replace path separators defensively so an ID can never escape the directory.
        let safe = channelID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent(safe + ".json")
    }
}
