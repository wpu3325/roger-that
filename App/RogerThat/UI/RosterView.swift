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
        .overlay {
            if appState.members.isEmpty {
                ContentUnavailableView(
                    "No members nearby",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Others will appear when they join the channel in range.")
                )
            }
        }
    }
}
