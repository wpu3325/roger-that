import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HelpRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: DS.Palette.brand,
                        title: "What is Roger That?",
                        detail: "A walkie-talkie that works without cell signal. It uses Bluetooth and peer-to-peer Wi-Fi to carry voice and text directly between phones — no internet, no server."
                    )
                }

                Section("Getting started") {
                    HelpRow(
                        icon: "plus.circle.fill",
                        iconColor: .green,
                        title: "Create a channel",
                        detail: "Enter your call sign, tap Create Channel. A QR code appears — share it with your group before you head out. Everyone scans it once and you're all connected."
                    )
                    HelpRow(
                        icon: "qrcode.viewfinder",
                        iconColor: .blue,
                        title: "Join a channel",
                        detail: "Enter your call sign, tap Join Channel, then scan the creator's QR code. No QR? Ask them to tap Copy Invite Code and send it to you — paste it in the join field."
                    )
                    HelpRow(
                        icon: "person.2.fill",
                        iconColor: .purple,
                        title: "Who is on the channel?",
                        detail: "Tap the Members tab inside the channel to see everyone currently active nearby."
                    )
                }

                Section("Talking") {
                    HelpRow(
                        icon: "mic.fill",
                        iconColor: .red,
                        title: "Push to Talk (PTT)",
                        detail: "Hold the big mic button to transmit your voice. Release to stop. Only one person can talk at a time — if someone else is already talking, you will see their name at the top."
                    )
                    HelpRow(
                        icon: "hand.tap.fill",
                        iconColor: .orange,
                        title: "Tap-to-toggle mode",
                        detail: "Toggle the switch above the PTT button to switch to tap-to-toggle mode. Tap once to start talking, tap again to stop — useful if you need a free hand."
                    )
                    HelpRow(
                        icon: "wifi",
                        iconColor: .blue,
                        title: "Voice range",
                        detail: "Voice travels directly between phones over peer-to-peer Wi-Fi. Both phones need Wi-Fi and Bluetooth on. Typical range is 30-100m. If someone is out of voice range, use text instead."
                    )
                }

                Section("Messaging") {
                    HelpRow(
                        icon: "message.fill",
                        iconColor: .green,
                        title: "Text messages",
                        detail: "Type in the Chat tab and tap Send. Messages travel over Bluetooth and relay hop-by-hop through everyone on the channel — they can reach people outside direct voice range."
                    )
                    HelpRow(
                        icon: "arrow.triangle.branch",
                        iconColor: .gray,
                        title: "Mesh relay",
                        detail: "If Phone A and Phone C are out of range but both are in range of Phone B, texts from A still reach C — Phone B relays them automatically without any setup."
                    )
                }

                Section("Good to know") {
                    HelpRow(
                        icon: "iphone.slash",
                        iconColor: .secondary,
                        title: "No internet needed",
                        detail: "Roger That works entirely offline. Turn off cellular if you want to confirm it — just keep Bluetooth and Wi-Fi on."
                    )
                    HelpRow(
                        icon: "clock.arrow.circlepath",
                        iconColor: .secondary,
                        title: "Channel history",
                        detail: "Your messages are saved on your phone, so they're still here when you reopen the app. Leaving a channel keeps its history under Archived — tap it to rejoin. Delete a channel to remove it and its history for good."
                    )
                    HelpRow(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "Privacy",
                        detail: "All messages and voice are encrypted with a key that never leaves your group. Only people who scanned the QR can read your traffic."
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("How to Use")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 16))
            }
            .padding(.top, DS.Spacing.xxs)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
