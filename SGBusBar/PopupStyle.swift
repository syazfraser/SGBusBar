import SwiftUI

// The popup's two looks. Frosted is a calm, near-solid light or dark surface with white or
// charcoal cards, the same over any wallpaper. Clear keeps plain Liquid Glass, with faint cards.
// Settings uses the Clear style for its cards.

private struct PopupBackgroundKey: EnvironmentKey {
    static let defaultValue = PopupBackground.clear
}

extension EnvironmentValues {
    var popupBackground: PopupBackground {
        get { self[PopupBackgroundKey.self] }
        set { self[PopupBackgroundKey.self] = newValue }
    }
}

/// The surface behind the popup's content with Frosted on. It also fills the arrow at the top.
struct PopupBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color(hex: 0x141416).opacity(0.94) : Color(hex: 0xF2F3F5).opacity(0.94))
            .ignoresSafeArea()
    }
}

extension View {
    /// A rounded card for a group of content.
    func card(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupBackground) private var background

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch background {
        case .frosted:
            // White cards on light grey, or charcoal on near-black, like a modern app.
            content
                .background(
                    shape
                        .fill(colorScheme == .dark ? Color(hex: 0x232326) : .white)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.07), radius: 3, y: 1)
                )
                .overlay(shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05)))
        case .clear:
            // A faint fill and hairline, so content on glass still reads as grouped.
            content
                .background(shape.fill(Color.primary.opacity(0.045)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

/// A small picture of the popup in a theme, for the Appearance settings.
struct ThemeThumbnail: View {
    let theme: AppTheme
    let background: PopupBackground

    var body: some View {
        switch theme {
        case .light:
            mock(dark: false)
        case .dark:
            mock(dark: true)
        case .system:
            // Light on the left, dark on the right, like macOS's own Auto appearance.
            mock(dark: false)
                .overlay {
                    mock(dark: true)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(maxWidth: .infinity).padding(.leading, 60)
                        }
                }
        }
    }

    private func mock(dark: Bool) -> some View {
        let surface = background == .frosted
            ? (dark ? Color(hex: 0x141416) : Color(hex: 0xF2F3F5))
            : (dark ? Color(hex: 0x3A3F4A) : Color(hex: 0xC9CED8))
        let cardFill = background == .frosted ? (dark ? Color(hex: 0x232326) : .white) : Color(white: dark ? 1 : 0, opacity: 0.08)
        let ink = dark ? Color.white : Color.black
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2.5).fill(Color(hex: 0x1F9A48)).frame(width: 10, height: 10)
                Capsule().fill(ink.opacity(0.7)).frame(width: 30, height: 4)
                Spacer()
                Capsule().fill(Color(hex: 0x1F7F36)).frame(width: 14, height: 6)
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 5) {
                    Capsule().fill(ink.opacity(0.55)).frame(width: 12, height: 4)
                    Capsule().fill(row == 0 ? Color(hex: 0xB35900) : Color(hex: 0x1F7F36)).frame(width: 18, height: 6)
                    Capsule().fill(ink.opacity(0.35)).frame(width: 14, height: 4)
                    Spacer()
                }
                .padding(5)
                .background(cardFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(8)
        .frame(width: 120, height: 72)
        .background(surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
