import SwiftUI
import RogerThatCore

/// Top-level navigation: channel creation/join → channel view.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("rogerthat.onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView()                    // first launch — welcome + permissions
            } else if appState.activeChannelID != nil {
                ChannelView()                       // a channel is open
            } else if appState.joinedChannels.isEmpty {
                CreateOrJoinView()                  // no channels yet
            } else {
                ChannelListView()                   // pick a channel or add one
            }
        }
        .preferredColorScheme(.dark)
        .task { appState.bootstrap() }   // deferred startup — keeps launch snappy
    }
}
