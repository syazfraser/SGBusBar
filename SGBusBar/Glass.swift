import SwiftUI

// Liquid Glass on macOS 26, with the closest older style before that.
// Glass is for controls that float above content (buttons, fields, the popup itself);
// content such as lists and times stays solid so it's readable on any background.

extension View {
    /// Glass buttons; `prominent` is the filled, tinted style for the main action.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    /// A glass surface behind a control, e.g. the search field.
    @ViewBuilder func glassBackground(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// Lets neighbouring glass controls blend into each other, as system toolbars do.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
