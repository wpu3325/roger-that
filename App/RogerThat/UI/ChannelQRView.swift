import SwiftUI
import CoreImage.CIFilterBuiltins
import RogerThatCore

/// Shows the current channel's invite QR + short tag so a friend can scan to join
/// from inside an active channel.
struct ChannelQRView: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var code: String {
        (try? JoinPayload(channel: channel).encode()) ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Have a friend scan this to join your channel")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let img = generateQR(from: code) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                } else {
                    ContentUnavailableView("Couldn't build QR", systemImage: "qrcode")
                }

                Text(channelTag(channel.channelIDHash))
                    .font(.system(.title2, design: .monospaced).bold())
                    .tracking(6)
                    .foregroundStyle(.secondary)

                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Haptics.copied()
                } label: {
                    Label(copied ? "Copied" : "Copy invite code",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(copied ? "Invite code copied" : "Copy invite code")

                Text("No camera? Share the invite code and have them paste it under Join Channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func channelTag(_ hash: UInt32) -> String {
        let hex = String(format: "%08X", hash)
        return "\(hex.prefix(4))·\(hex.suffix(4))"
    }

    private func generateQR(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
