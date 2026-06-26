import Foundation
import UserNotifications

/// Local notifications for inbound messages that aren't already on screen — fires when the
/// app is backgrounded / the screen is locked, or when the user is on a different page than
/// the channel a message arrived on. These are *local* notifications, so no entitlement and
/// no APNs is needed; they work fully offline.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Set by `AppState` so taps can deep-link and foreground suppression can be decided.
    weak var appState: AppState?

    private var requested = false
    private var authorized = false

    /// Ask once, in context (first channel activity) — not at launch.
    func requestAuthorizationIfNeeded() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
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
    /// would be redundant — the message is already on screen).
    func isOnScreen(_ channelID: String?) -> Bool {
        guard let appState else { return false }
        return appState.isForeground && appState.activeChannelID == channelID
    }

    /// Notification tapped: open (rejoin) that channel.
    func handleTap(_ channelID: String?) {
        guard let channelID else { return }
        appState?.openChannel(channelID)
    }
}
