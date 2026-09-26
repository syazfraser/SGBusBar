import SwiftUI

// Building blocks for the Settings pages: a big title and subtitle, rounded cards of rows,
// and tiles for picking one of a few options.

/// A Settings page: large title, one-line subtitle, then its cards.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    /// Pages holding a List scroll inside the list instead.
    var scrolls = true
    @ViewBuilder var content: Content

    var body: some View {
        if scrolls {
            ScrollView { page }
        } else {
            page
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .topLeading)
    }
}

/// A rounded group of rows, with an optional small caps label.
struct SettingsCard<Content: View>: View {
    var label: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 12)
    }
}

/// Title and description on the left, a control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The hairline between rows in a card.
struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

/// A switch for a SettingsRow.
struct RowToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

/// Tiles for choosing one of a few options, each with an icon, a title and a line of detail.
struct OptionTiles<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let detail: String
        let systemImage: String
    }

    let options: [Option]
    @Binding var selection: Value
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(options, id: \.value) { option in
                tile(option)
            }
        }
        .padding(16)
    }

    private func tile(_ option: Option) -> some View {
        let selected = option.value == selection
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .fontWeight(.semibold)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .contentShape(shape)
            .background(shape.fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
            .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// A System Settings–style icon: a white symbol on a coloured rounded square.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
