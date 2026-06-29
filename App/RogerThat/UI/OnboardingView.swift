import SwiftUI

/// First-run welcome experience: a short branded intro, a one-line description, an
/// explanation-first permission request for each capability, and finally the call sign.
/// Sets `rogerthat.onboardingComplete` when finished so it only shows once.
struct OnboardingView: View {
    @AppStorage("rogerthat.onboardingComplete") private var onboardingComplete = false
    @AppStorage("rogerthat.callSign") private var callSign = ""

    @StateObject private var primer = PermissionPrimer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var working = false
    @State private var titleShown = false
    @State private var callSignDraft = ""
    @FocusState private var callSignFocused: Bool

    /// Ordered permission screens (steps 2…6).
    private let permissions: [PermissionInfo] = [
        PermissionInfo(
            icon: "dot.radiowaves.left.and.right", tint: .blue,
            title: "Bluetooth",
            blurb: "Bluetooth lets Roger That find people near you and carry text messages — phone to phone, with no internet or cell signal. It's the backbone of the mesh: messages even hop through other members to reach people out of direct range.",
            footnote: nil,
            allowLabel: "Allow Bluetooth",
            request: { await $0.requestBluetooth() }
        ),
        PermissionInfo(
            icon: "wifi", tint: .teal,
            title: "Wi-Fi & Device Discovery",
            blurb: "Live voice travels over peer-to-peer Wi-Fi, directly between phones. Allowing local network lets Roger That discover nearby devices and stream your voice.",
            footnote: "Grant both Bluetooth and Wi-Fi for the full experience — voice and text. With Bluetooth only, you can still chat by text; you just won't have voice.",
            allowLabel: "Allow Wi-Fi & Discovery",
            request: { await $0.requestLocalNetwork() }
        ),
        PermissionInfo(
            icon: "mic.fill", tint: .red,
            title: "Microphone",
            blurb: "So you can transmit when you hold the talk button. Roger That only listens while you're actively talking — never in the background.",
            footnote: nil,
            allowLabel: "Allow Microphone",
            request: { await $0.requestMicrophone() }
        ),
        PermissionInfo(
            icon: "bell.badge.fill", tint: .orange,
            title: "Notifications",
            blurb: "Get alerted when a new message arrives while the app is in your pocket or your screen is locked, so you never miss a call from your group.",
            footnote: nil,
            allowLabel: "Allow Notifications",
            request: { await $0.requestNotifications() }
        ),
        PermissionInfo(
            icon: "qrcode.viewfinder", tint: .purple,
            title: "Camera",
            blurb: "Joining a channel is as easy as scanning its QR code. The camera is only ever used to scan a code to join.",
            footnote: nil,
            allowLabel: "Allow Camera",
            request: { await $0.requestCamera() }
        ),
    ]

    private var lastStep: Int { 2 + permissions.count }   // call-sign screen

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Palette.surface, DS.Palette.surfaceSecondary],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, DS.Spacing.sm)

                Spacer(minLength: 0)

                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(.horizontal, DS.Spacing.xxl)

                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomePage
        case 1: aboutPage
        case lastStep: callSignPage
        default: permissionPage(permissions[step - 2])
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 86, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative.reversing)
                .scaleEffect(titleShown ? 1 : 0.6)
                .opacity(titleShown ? 1 : 0)

            VStack(spacing: DS.Spacing.md) {
                Text("Welcome to")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Roger That")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
            }
            .opacity(titleShown ? 1 : 0)
            .offset(y: titleShown ? 0 : DS.Spacing.lg)

            primaryButton("Get Started") { advance() }
                .padding(.top, DS.Spacing.md)
                .opacity(titleShown ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                titleShown = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    titleShown = true
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: DS.Spacing.md) {
                Text("Your offline walkie-talkie")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Talk and text with people nearby — even with no signal, no Wi-Fi network, and no internet. Everything is end-to-end encrypted and stays between your group.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                featureBullet("antenna.radiowaves.left.and.right", "Works completely offline")
                featureBullet("waveform", "Push-to-talk voice + group text")
                featureBullet("lock.shield.fill", "Encrypted, no servers")
            }
            .padding(.top, DS.Spacing.xs)

            primaryButton("Continue") { advance() }
        }
    }

    private func permissionPage(_ info: PermissionInfo) -> some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle().fill(info.tint.opacity(0.15)).frame(width: 96, height: 96)
                Image(systemName: info.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(info.tint)
            }

            Text(info.title)
                .font(.title.bold())

            Text(info.blurb)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let footnote = info.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xs)
            }

            VStack(spacing: DS.Spacing.md) {
                primaryButton(info.allowLabel, loading: working) {
                    Task {
                        working = true
                        await info.request(primer)
                        working = false
                        advance()
                    }
                }
                Button("Not now") { advance() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(working)
            }
            .padding(.top, DS.Spacing.sm)
        }
    }

    private var callSignPage: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle().fill(DS.Palette.brand.opacity(0.15)).frame(width: 96, height: 96)
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: DS.Spacing.md) {
                Text("Pick your call sign")
                    .font(.title.bold())
                Text("This is how others see you on the channel. You can change it anytime.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Call sign", text: $callSignDraft)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($callSignFocused)
                .submitLabel(.done)
                .onSubmit(finish)
                .onAppear {
                    callSignDraft = callSign
                    callSignFocused = true
                }

            primaryButton("Start Talking") { finish() }
                .disabled(callSignDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Building blocks

    private func featureBullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }

    private func primaryButton(_ title: String, loading: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(loading ? 0 : 1)
                if loading { ProgressView().tint(.white) }
            }
        }
        .dsPrimaryButton()
        .disabled(loading)
    }

    private var progressDots: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i == step ? DS.Palette.brand : Color.secondary.opacity(0.3))
                    .frame(width: i == step ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(lastStep + 1)")
    }

    // MARK: - Navigation

    private func advance() {
        if step < lastStep { step += 1 }
    }

    private func finish() {
        let trimmed = callSignDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        callSign = trimmed
        callSignFocused = false
        onboardingComplete = true
    }
}

/// One permission screen's content + the action that fires its system prompt.
private struct PermissionInfo {
    let icon: String
    let tint: Color
    let title: String
    let blurb: String
    let footnote: String?
    let allowLabel: String
    let request: (PermissionPrimer) async -> Void
}
