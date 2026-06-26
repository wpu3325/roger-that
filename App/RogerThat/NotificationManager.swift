import Foundation
import UserNotifications

/// Local notifications for inbound messages that aren't already on screen — fires when the
/// app is backgrounded / the screen is locked, or when the user is on a different page than
/// the channel a message arrived on. These are *local* notifications, so no entitlement and
/// no APNs is needed; they work fully offline.
///
/// Not `@MainActor`: the `UNUserNotificationCenterDelegate` callbacks are nonisolated, so this
/// keeps a small lock-protected snapshot of foreground/active-channel state (mirrored from
/// `AppState`) that the delegate can read synchronously — avoiding any actor hop that would
/// "send" the non-Sendable completion handler across a boundary.
final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    private let lock = NSLock()
    private weak var appState: AppState?
    private var foreground = true
    private var activeID: String?
    private var requested = false

    /// Wire up the app state (for deep-link taps) once at startup.
    func bind(_ appState: AppState) {
        lock.withLock { self.appState = appState }
    }

    /// Mirror of `scenePhase == .active`.
    func setForeground(_ value: Bool) {
        lock.withLock { foreground = value }
    }

    /// Mirror of the currently open channel (nil on the channel list).
    func setActiveChannel(_ channelID: String?) {
        lock.withLock { activeID = channelID }
    }

    /// Ask once, in context (first channel activity) — not at launch.
    func requestAuthorizationIfNeeded() {
        let shouldAsk: Bool = lock.withLock {
            if requested { return false }
            requested = true
            return true
        }
        guard shouldAsk else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Post a banner for a received message. `channelID` threads a channel's notifications.
    func postMessage(channelName: String, sender: String, body: String, channelID: String) {
        let content = UNMutableNotificationContent()
        content.title = channelName
        content.subtitle = sender
        content.body = body
        content.sound = .default
        content.threadIdentifier = channelID
        content.userInfo = ["channelID": channelID]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// True when the given channel is the one currently open in the foreground (so a banner
    /// would be redundant — the message is already on screen). Safe to call off the main actor.
    func isOnScreen(_ channelID: String?) -> Bool {
        lock.withLock { foreground && activeID == channelID }
    }

    /// Notification tapped: open (rejoin) that channel on the main actor.
    func handleTap(_ channelID: String?) {
        guard let channelID else { return }
        let appState = lock.withLock { self.appState }
        Task { @MainActor in appState?.openChannel(channelID) }
    }
}
