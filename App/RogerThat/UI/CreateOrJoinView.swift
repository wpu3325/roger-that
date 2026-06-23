import SwiftUI
import CoreImage.CIFilterBuiltins
import RogerThatCore

/// Entry screen: create a new channel (shows QR + short code) or join an existing one.
struct CreateOrJoinView: View {
    @EnvironmentObject var appState: AppState
    @State private var displayName = ""
    @State private var joinCode = ""
    @State private var showJoinSheet = false
    @State private var errorMessage: String?
    @State private var createdChannel: Channel?
    @State private var createdCode: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Roger That")
                    .font(.largeTitle.bold())

                TextField("Your name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .padding(.horizontal)

                if let ch = createdChannel, let code = createdCode {
                    createdChannelCard(ch, code: code)
                } else {
                    createButton
                }

                Divider()

                joinButton
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showJoinSheet) {
                JoinSheet(displayName: displayName)
            }
        }
    }

    // MARK: - Subviews

    private var createButton: some View {
        Button {
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Enter your name first."
                return
            }
            let channel = Channel.create()
            let payload = JoinPayload(channel: channel)
            let code = (try? payload.encode()) ?? ""
            createdChannel = channel
            createdCode = code
        } label: {
            Label("Create Channel", systemImage: "antenna.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
    }

    private func createdChannelCard(_ channel: Channel, code: String) -> some View {
        VStack(spacing: 16) {
            Text("Share this to invite others")
                .font(.headline)

            if let qrImage = generateQR(from: code) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }

            Text(code)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Join This Channel") {
                appState.join(channel: channel, displayName: displayName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var joinButton: some View {
        Button {
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Enter your name first."
                return
            }
            showJoinSheet = true
        } label: {
            Label("Join Channel", systemImage: "qrcode.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal)
    }

    // MARK: - QR generation

    private func generateQR(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 8
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - JoinSheet

private struct JoinSheet: View {
    let displayName: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter the join code or scan QR")
                    .font(.headline)

                TextField("Join code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .padding(.horizontal)

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption)
                }

                Button("Join") {
                    joinWithCode(code)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.isEmpty)

                // MARK: QR scanner placeholder
                // TODO: integrate AVCaptureSession-based QR scanner.
                // For now users type the code manually.
                Button("Scan QR (TODO)") { }
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
            .padding()
            .navigationTitle("Join Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func joinWithCode(_ code: String) {
        do {
            let payload = try JoinPayload.decode(code)
            let channel = payload.toChannel()
            appState.join(channel: channel, displayName: displayName)
            dismiss()
        } catch {
            errorMessage = "Invalid code. Try again."
        }
    }
}
