import SwiftUI
import RogerThatCore

/// Top-level navigation: channel creation/join → channel view.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.session == nil {
                CreateOrJoinView()
            } else {
                ChannelView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
