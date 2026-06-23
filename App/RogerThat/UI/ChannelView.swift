import SwiftUI
import RogerThatCore

/// Main in-channel screen.
struct ChannelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FloorBanner()
                    .padding(.horizontal)
                    .padding(.top, 8)

                Divider()

                TabView {
                    TextChannelView()
                        .tabItem { Label("Chat", systemImage: "message") }

                    RosterView()
                        .tabItem { Label("Members", systemImage: "person.2") }
                }

                TalkButton()
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
            .navigationTitle(appState.channel?.channelID.prefix(8).description ?? "Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Leave") { appState.leaveChannel() }
                }
            }
        }
    }
}

/// Shows who is currently talking.
private struct FloorBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.floorState {
            case .idle:
                Text("Channel clear")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case .talkingLocal:
                Label("You are talking", systemImage: "waveform")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())
            case .talkingRemote(_, let name):
                Label("\(name) is talking", systemImage: "waveform")
                    .foregroundStyle(.orange)
                    .font(.subheadline.bold())
            }
        }
        .frame(height: 28)
    }
}
