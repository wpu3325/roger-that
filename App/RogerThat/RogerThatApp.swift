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
            appState.isForeground = (phase == .active)
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
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let channelID = notification.request.content.userInfo["channelID"] as? String
        Task { @MainActor in
            completionHandler(NotificationManager.shared.isOnScreen(channelID) ? [] : [.banner, .sound])
        }
    }

    // Tapped a notification → open that channel.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let channelID = response.notification.request.content.userInfo["channelID"] as? String
        Task { @MainActor in
            NotificationManager.shared.handleTap(channelID)
            completionHandler()
        }
    }
}
