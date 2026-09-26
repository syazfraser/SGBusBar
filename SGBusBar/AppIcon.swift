import SwiftUI

/// The app icon: a white bus on Singapore's lush green, drawn in code so the popup header,
/// About page and the generated AppIcon PNGs all match.
struct AppIconView: View {
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0x43C463), Color(hex: 0x137A36)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "bus.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.015)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size * 0.012)))
            .frame(width: size, height: size)
    }
}

/// The icon on a transparent canvas with the standard macOS margins and shadow, for AppIcon PNGs.
struct AppIconArtwork: View {
    var canvas: CGFloat

    var body: some View {
        AppIconView(size: canvas * 0.805)
            .shadow(color: .black.opacity(0.28), radius: canvas * 0.018, y: canvas * 0.01)
            .frame(width: canvas, height: canvas)
    }
}
