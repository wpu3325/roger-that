import SwiftUI

/// Lightweight design system: one source of truth for spacing, corner radius, color roles,
/// typography, and the common button / card / empty-state / toast patterns. Keeps the app
/// visually consistent (Apple HIG: clarity, consistency, deference) without a heavy rewrite.
/// Brand accent stays the native system blue; dark mode stays forced.
enum DS {

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18   // chat bubbles
    }

    enum Layout {
        /// HIG minimum comfortable touch target.
        static let minTouchTarget: CGFloat = 44
    }

    /// Semantic color roles. Change `brand` in one place to retheme the whole app.
    enum Palette {
        static let brand = Color.accentColor          // native system blue
        static let talkingLocal = Color.green
        static let talkingRemote = Color.orange
        static let danger = Color.red
        static let warning = Color.orange
        static let surface = Color(.systemBackground)
        static let surfaceSecondary = Color(.secondarySystemBackground)
    }

    enum Typography {
        static let sectionHeader = Font.caption.weight(.semibold)
        static let cardTitle = Font.headline
    }
}

// MARK: - Button styles

/// Full-width, prominent primary action. Meets the 44pt touch-target minimum.
struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.Layout.minTouchTarget)
            .background(DS.Palette.brand,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Full-width secondary action: tinted, bordered, lower visual weight than primary.
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(DS.Palette.brand)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.Layout.minTouchTarget)
            .background(DS.Palette.brand.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    func dsPrimaryButton() -> some View { buttonStyle(DSPrimaryButtonStyle()) }
    func dsSecondaryButton() -> some View { buttonStyle(DSSecondaryButtonStyle()) }

    /// Standard padded card surface.
    func dsCard() -> some View {
        padding(DS.Spacing.lg)
            .background(DS.Palette.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

// MARK: - Empty state

/// Consistent empty state across screens (wraps `ContentUnavailableView`).
struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}

// MARK: - Toast

/// Brief, non-blocking confirmation (e.g. "Copied"). Never intercepts touches.
private struct DSToast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
    }
}

extension View {
    /// Show a transient toast pinned near the bottom; auto-dismisses after ~1.6s. Set the
    /// binding to a non-nil string to show it. Does not block touches (safe over the TalkButton).
    func dsToast(message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let msg = message.wrappedValue {
                DSToast(text: msg)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        message.wrappedValue = nil
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message.wrappedValue)
    }
}
