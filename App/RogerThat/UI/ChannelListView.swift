import SwiftUI
import RogerThatCore

/// Home screen when you've joined channels but none is open: pick one (or add more).
/// Background channels keep collecting messages, so unread badges update live here.
/// "Left" channels drop into an Archived section — read-only history, reopen to rejoin.
struct ChannelListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdd = false
    @State private var renaming: ChannelMetadata?
    @State private var renameText = ""

    private var activeChannels: [ChannelMetadata] {
        appState.joinedChannels.filter { !$0.isArchived }
    }
    private var archivedChannels: [ChannelMetadata] {
        appState.joinedChannels.filter { $0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(activeChannels) { channelRow($0) }
                }

                if !archivedChannels.isEmpty {
                    Section("Archived") {
                        ForEach(archivedChannels) { channelRow($0) }
                    }
                }
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
            .alert("Rename channel", isPresented: renamePresented) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let meta = renaming { appState.rename(meta.channelID, to: renameText) }
                    renaming = nil
                }
            }
        }
    }

    // MARK: - Rows

    private func channelRow(_ meta: ChannelMetadata) -> some View {
        Button {
            appState.openChannel(meta.channelID)
        } label: {
            row(for: meta)
        }
        .tint(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                appState.delete(meta.channelID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !meta.isArchived {
                Button {
                    appState.archive(meta.channelID)
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .tint(.orange)
            }
            Button {
                startRename(meta)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                startRename(meta)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if !meta.isArchived {
                Button {
                    appState.archive(meta.channelID)
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Button(role: .destructive) {
                appState.delete(meta.channelID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func row(for meta: ChannelMetadata) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: meta.kind == .password ? "lock.fill" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(meta.name).font(.body)
                Text(summary(meta)).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if !meta.isArchived,
               let unread = appState.unreadByChannel[meta.channelID], unread > 0 {
                Text("\(unread)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(Capsule().fill(DS.Palette.brand))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, DS.Spacing.xs)
        .contentShape(Rectangle())
    }

    private func summary(_ meta: ChannelMetadata) -> String {
        if meta.isArchived { return "Archived · tap to rejoin" }
        let count = appState.memberCount(for: meta.channelID)
        switch count {
        case 0:  return "No one nearby"
        case 1:  return "Just you"
        default: return "\(count) here"
        }
    }

    // MARK: - Rename

    private func startRename(_ meta: ChannelMetadata) {
        renameText = meta.name
        renaming = meta
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
