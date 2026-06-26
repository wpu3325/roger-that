import SwiftUI
import UserNotifications

@main
struct RogerThatApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .onChange(of: scenePhase) { _, phase in
            let active = (phase == .active)
            appState.isForeground = active
            NotificationManager.shared.setForeground(active)
        }
    }
}

/// Owns the `UNUserNotificationCenter` delegate so message banners present in the
/// foreground and taps deep-link into the right channel.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show a banner even while in the foreground — unless the message's channel is already
    // the one on screen (then it's redundant; the chat shows it live).
    // `nonisolated` because UNUserNotificationCenterDelegate isn't MainActor-isolated while
    // this class is (via UIApplicationDelegate); we hop to the main actor to read state.
    // Both answers come from NotificationManager's thread-safe snapshot, so we call the
    // completion handler synchronously here — no actor hop, nothing sent across a boundary.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let channelID = notification.request.content.userInfo["channelID"] as? String
        let onScreen = NotificationManager.shared.isOnScreen(channelID)
        completionHandler(onScreen ? [] : [.banner, .sound])
    }

    // Tapped a notification → open that channel (handleTap hops to the main actor itself).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let channelID = response.notification.request.content.userInfo["channelID"] as? String
        NotificationManager.shared.handleTap(channelID)
        completionHandler()
    }
}
