import SwiftUI
import RogerThatCore

/// Home screen when you've joined channels but none is open: pick one (or add more).
/// Background channels keep collecting messages, so unread badges update live here.
struct ChannelListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.joinedChannels) { meta in
                    Button {
                        appState.setActive(meta.channelID)
                    } label: {
                        row(for: meta)
                    }
                    .tint(.primary)
                }
                .onDelete(perform: deleteChannels)
            }
            .navigationTitle("Channels")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add channel")
                }
            }
            .sheet(isPresented: $showAdd) {
                CreateOrJoinView()
            }
        }
    }

    private func row(for meta: ChannelMetadata) -> some View {
        HStack(spacing: 12) {
            Image(systemName: meta.kind == .password ? "lock.fill" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(meta.name).font(.body)
                Text(memberSummary(meta)).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let unread = appState.unreadByChannel[meta.channelID], unread > 0 {
                Text("\(unread)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func memberSummary(_ meta: ChannelMetadata) -> String {
        let count = appState.memberCount(for: meta.channelID)
        switch count {
        case 0:  return "No one nearby"
        case 1:  return "Just you"
        default: return "\(count) here"
        }
    }

    private func deleteChannels(_ offsets: IndexSet) {
        for index in offsets {
            appState.leave(appState.joinedChannels[index].channelID)
        }
    }
}
