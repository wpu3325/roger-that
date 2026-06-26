import SwiftUI
import RogerThatCore

/// Main in-channel screen.
struct ChannelView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInviteQR = false
    @State private var keyboardVisible = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

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

                if !keyboardVisible {
                    TalkButton()
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            .navigationTitle(appState.activeMetadata?.name ?? "Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Back to the channel list; stays joined and keeps collecting in the background.
                    Button {
                        appState.setActive(nil)
                    } label: {
                        Label("Channels", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInviteQR = true
                    } label: {
                        Image(systemName: "qrcode")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            renameText = appState.activeMetadata?.name ?? ""
                            showRename = true
                        } label: {
                            Label("Rename channel", systemImage: "pencil")
                        }
                        // "Leave" keeps the channel (archived) and its history; you can rejoin.
                        Button {
                            appState.leaveActiveChannel()
                        } label: {
                            Label("Leave channel", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        // "Delete" permanently scrubs the channel, its key, and its history.
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete channel", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Rename channel", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let id = appState.activeChannelID { appState.rename(id, to: renameText) }
                }
            }
            .alert("Delete channel?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let id = appState.activeChannelID { appState.delete(id) }
                }
            } message: {
                Text("This permanently removes the channel and its message history on this device.")
            }
            .sheet(isPresented: $showInviteQR) {
                if let channel = appState.channel {
                    ChannelQRView(channel: channel)
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
                HStack(spacing: 8) {
                    VoiceWaveformView(level: CGFloat(appState.voiceLevel), color: .green,
                                      barCount: 4, maxBarHeight: 18, barWidth: 3)
                    Text("You are talking")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                }
            case .talkingRemote(_, let name):
                HStack(spacing: 8) {
                    VoiceWaveformView(level: CGFloat(appState.voiceLevel), color: .orange,
                                      barCount: 4, maxBarHeight: 18, barWidth: 3)
                    Text("\(name) is talking")
                        .foregroundStyle(.orange)
                        .font(.subheadline.bold())
                }
            }
        }
        .frame(height: 28)
    }
}
