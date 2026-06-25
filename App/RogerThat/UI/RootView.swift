import SwiftUI
import RogerThatCore

/// Top-level navigation: channel creation/join → channel view.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.activeChannelID != nil {
                ChannelView()                       // a channel is open
            } else if appState.joinedChannels.isEmpty {
                CreateOrJoinView()                  // first run — no channels yet
            } else {
                ChannelListView()                   // pick a channel or add one
            }
        }
        .preferredColorScheme(.dark)
    }
}
