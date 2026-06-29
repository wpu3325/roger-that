import SwiftUI
import CoreImage.CIFilterBuiltins
import RogerThatCore

struct CreateOrJoinView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("rogerthat.callSign") private var displayName = ""
    @State private var callSignDraft = ""
    @State private var isEditingCallSign = false
    @State private var showJoinSheet = false
    @State private var showPasswordSheet = false
    @State private var errorMessage: String?
    @State private var createdChannel: Channel?
    @State private var createdCode: String?
    @State private var showHelp = false
    @State private var copyToast: String?
    @FocusState private var callSignFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xxl) {
                HStack {
                    Spacer()
                    Text("Roger That")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Help")
                }
                .padding(.horizontal)

                callSignField

                if let err = errorMessage {
                    Text(err).foregroundStyle(DS.Palette.danger).font(.caption)
                }

                if let ch = createdChannel, let code = createdCode {
                    createdChannelCard(ch, code: code)
                } else {
                    createButton
                }

                Divider()

                joinButton

                passwordButton
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showJoinSheet) {
                JoinSheet(displayName: displayName)
            }
            .sheet(isPresented: $showPasswordSheet) {
                PasswordChannelSheet(displayName: displayName)
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
            .dsToast(message: $copyToast)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var callSignField: some View {
        if displayName.isEmpty || isEditingCallSign {
            HStack(spacing: DS.Spacing.sm) {
                TextField("Call sign", text: $callSignDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($callSignFocused)
                    .onSubmit { commitCallSign() }
                    .onAppear {
                        callSignDraft = displayName
                        if displayName.isEmpty { callSignFocused = true }
                    }
                Button("Done") {
                    commitCallSign()
                }
                .buttonStyle(.borderedProminent)
                .disabled(callSignDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
        } else {
            HStack(spacing: DS.Spacing.md) {
                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Button {
                    callSignDraft = displayName
                    isEditingCallSign = true
                    callSignFocused = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Edit call sign")
            }
            .padding(.horizontal)
        }
    }

    private func commitCallSign() {
        let trimmed = callSignDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        isEditingCallSign = false
        callSignFocused = false
    }

    private var createButton: some View {
        Button {
            commitCallSign()
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Enter your call sign first."
                return
            }
            callSignFocused = false
            errorMessage = nil
            let channel = Channel.create()
            let payload = JoinPayload(channel: channel)
            let code = (try? payload.encode()) ?? ""
            createdChannel = channel
            createdCode = code
        } label: {
            Label("Create Channel", systemImage: "antenna.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .dsPrimaryButton()
        .padding(.horizontal)
    }

    private func createdChannelCard(_ channel: Channel, code: String) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Text("Show this QR to invite others")
                .font(.headline)

            if let qrImage = generateQR(from: code) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }

            Text(channelTag(channel.channelIDHash))
                .font(.system(.title2, design: .monospaced).bold())
                .tracking(6)
                .foregroundStyle(.secondary)

            Button {
                UIPasteboard.general.string = code
                Haptics.copied()
                copyToast = "Invite code copied"
            } label: {
                Label("Copy invite code", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            .accessibilityLabel("Copy invite code")

            Button("Join This Channel") {
                appState.join(channel: channel, displayName: displayName)
            }
            .dsPrimaryButton()
        }
        .padding()
        .background(DS.Palette.surfaceSecondary)
        .cornerRadius(DS.Radius.md)
        .padding(.horizontal)
    }

    private var joinButton: some View {
        Button {
            commitCallSign()
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Enter your call sign first."
                return
            }
            showJoinSheet = true
        } label: {
            Label("Join Channel", systemImage: "qrcode.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .dsSecondaryButton()
        .padding(.horizontal)
    }

    private var passwordButton: some View {
        Button {
            commitCallSign()
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Enter your call sign first."
                return
            }
            showPasswordSheet = true
        } label: {
            Label("Channel with Password", systemImage: "lock.fill")
                .frame(maxWidth: .infinity)
        }
        .dsSecondaryButton()
        .padding(.horizontal)
    }

    // MARK: - Helpers

    /// 8-char hex tag from the channel hash, e.g. "A3F7·B248".
    private func channelTag(_ hash: UInt32) -> String {
        let hex = String(format: "%08X", hash)
        return "\(hex.prefix(4))·\(hex.suffix(4))"
    }

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
            VStack(spacing: DS.Spacing.xl) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fullScreenCover(isPresented: $showScanner) {
                    QRScannerView {
                        showScanner = false
                        joinWithCode($0)
                    } onCancel: {
                        showScanner = false
                    }
                    .ignoresSafeArea()
                }

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or paste invite code").font(.caption).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }
                .padding(.horizontal)

                TextField("Paste invite code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .padding(.horizontal)

                if let err = errorMessage {
                    Text(err).foregroundStyle(DS.Palette.danger).font(.caption)
                }

                Button("Join") {
                    joinWithCode(code)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(code.isEmpty)
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

// MARK: - PasswordChannelSheet

/// Create *or* join a password channel — they're the same operation: derive the key from
/// the name + password and enter. The first person in "creates" it; everyone after "joins".
private struct PasswordChannelSheet: View {
    let displayName: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var password = ""
    /// Computed on demand (PBKDF2 is deliberately slow — never per keystroke).
    @State private var verificationCode: String?
    /// True while PBKDF2 runs off-main, so the UI shows progress instead of freezing.
    @State private var deriving = false

    private var canEnter: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !deriving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: name) { _, _ in verificationCode = nil }
                    SecureField("Password", text: $password)
                        .onChange(of: password) { _, _ in verificationCode = nil }
                } footer: {
                    Text("Anyone who enters the same name and password joins the same channel — no QR needed. Share them however you like.")
                }

                Section {
                    Button("Show verification code") { deriveVerification() }
                        .disabled(!canEnter)

                    if let code = verificationCode {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(code)
                                .font(.system(.title3, design: .monospaced).bold())
                                .tracking(3)
                            Text("Everyone who typed the same password sees this code. Compare it to be sure you're in the same channel.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        enter()
                    } label: {
                        HStack {
                            Text("Enter Channel")
                            if deriving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canEnter)
                }
            }
            .navigationTitle("Password Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Derive the verification fingerprint off the main thread (PBKDF2 is ~100k iters).
    private func deriveVerification() {
        guard canEnter else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let pass = password
        deriving = true
        Task {
            let fingerprint = await Task.detached(priority: .userInitiated) {
                PasswordKey.fingerprint(of: PasswordKey.channel(name: trimmed, password: pass).key)
            }.value
            verificationCode = fingerprint
            deriving = false
        }
    }

    private func enter() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !password.isEmpty, !deriving else { return }
        let pass = password
        deriving = true
        Task {
            let channel = await Task.detached(priority: .userInitiated) {
                PasswordKey.channel(name: trimmed, password: pass)
            }.value
            appState.join(channel: channel, displayName: displayName, name: trimmed, kind: .password)
            deriving = false
            dismiss()
        }
    }
}
