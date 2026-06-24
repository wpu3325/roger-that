import SwiftUI

/// Step-by-step guide for wiring the iPhone Action Button to PTT.
struct ActionButtonGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use the Action Button as your PTT trigger for a true walkie-talkie feel.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Requires iPhone 15 Pro or later.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Steps
                    StepRow(number: 1, icon: "gearshape.fill", iconColor: .gray,
                            title: "Open the Settings app",
                            detail: "On your iPhone home screen or App Library.")

                    StepRow(number: 2, icon: "button.angledtop.vertical.right", iconColor: .orange,
                            title: "Tap 'Action Button'",
                            detail: "Scroll down — it appears just below Sound & Haptics.")

                    StepRow(number: 3, icon: "arrow.left.arrow.right",
                            iconColor: .blue,
                            title: "Swipe to 'Shortcut'",
                            detail: "The Action Button picker is a horizontal carousel. Swipe right until you reach the Shortcut option (star icon).")

                    StepRow(number: 4, icon: "star.fill", iconColor: .yellow,
                            title: "Tap 'Choose a Shortcut'",
                            detail: "A shortcut picker will appear.")

                    StepRow(number: 5, icon: "mic.fill", iconColor: .accentColor,
                            title: "Select 'Toggle Push to Talk'",
                            detail: "Search for Roger That or scroll to find Toggle Push to Talk under the app.")

                    Divider()

                    // Result callout
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("That's it.")
                                .font(.headline)
                            Text("Press the Action Button once to start talking. Press it again to stop. This works in both PTT modes — the Action Button always uses tap-to-toggle since it sends a single press event (no hold detection).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // Open Settings shortcut
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Action Button Setup")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
