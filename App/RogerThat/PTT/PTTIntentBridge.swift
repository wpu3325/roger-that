import Foundation

/// Lets AppIntents reach AppState without a direct dependency.
/// AppState registers itself here; TogglePTTIntent reads through it.
final class PTTIntentBridge: @unchecked Sendable {
    static let shared = PTTIntentBridge()
    private init() {}

    weak var appState: AppState?
}
