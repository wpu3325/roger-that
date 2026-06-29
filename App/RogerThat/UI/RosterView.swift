import SwiftUI
import RogerThatCore

/// List of active channel members.
struct RosterView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(appState.members) { member in
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(member.displayName)
                    .font(.body)
                Spacer()
                if member.id == appState.localID {
                    Text("(you)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await appState.refreshRoster()
        }
        .overlay {
            if appState.members.isEmpty {
                DSEmptyState(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "No one nearby yet",
                    message: "Members appear here when they join this channel in range. Pull down to refresh."
                )
            }
        }
    }
}
