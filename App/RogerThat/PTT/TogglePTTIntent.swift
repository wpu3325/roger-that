import AppIntents
import RogerThatCore

struct TogglePTTIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Push to Talk"
    static let description = IntentDescription(
        "Start or stop transmitting on your active Roger That channel."
    )
    // false = runs silently without the Siri overlay; app must already be joined to a channel.
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            guard let appState = PTTIntentBridge.shared.appState,
                  appState.channel != nil else { return }
            if case .talkingLocal = appState.floorState {
                appState.pttController?.stopTalking()
            } else if appState.canStartTalking {
                // Half-duplex: don't cut in while a peer holds the floor.
                appState.pttController?.startTalking()
            }
        }
        return .result()
    }
}

// Registering an AppShortcutsProvider makes TogglePTTIntent appear
// directly in Settings → Action Button → Roger That, without the user
// needing to create a shortcut manually.
struct RogerThatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TogglePTTIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "PTT \(.applicationName)",
                "Talk on \(.applicationName)"
            ],
            shortTitle: "Toggle PTT",
            systemImageName: "mic.fill"
        )
    }
}
