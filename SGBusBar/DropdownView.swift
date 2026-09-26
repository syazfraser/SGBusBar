import SwiftUI

/// What the popup can ask the app to do outside itself.
struct DropdownActions {
    var addBus: () -> Void
    /// Opens Edit Stop for a stop code: rename it, or add and remove its buses.
    var editStop: (String) -> Void
    var openSettings: () -> Void
}

/// The panel that opens from the menu bar item: a header, the menu bar bus as a large card,
/// a card per stop, and a row of actions.
struct DropdownView: View {
    let store: ArrivalStore
    let actions: DropdownActions

    /// Taller than this and the cards scroll.
    private static let maxContentHeight: CGFloat = 700
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        VStack(spacing: 0) {
            PopupHeader(store: store)
            Divider()
            if !store.hasAPIKey {
                SetupView(store: store)
            } else if store.buses.isEmpty {
                EmptyBuses(onAdd: actions.addBus)
            } else {
                ScrollView {
                    cards
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollIndicators(contentHeight > Self.maxContentHeight ? .automatic : .never)
                .frame(height: min(contentHeight, Self.maxContentHeight))
            }
            Divider()
            Footer(store: store, actions: actions)
        }
        .frame(width: 500)
        // Frosted puts a calm light or dark surface behind everything; Clear leaves the popover's
        // own glass. Either way, coloured times sit in solid capsules so they stay readable.
        .background {
            if store.popupBackground == .frosted {
                PopupBackdrop()
            }
        }
        .environment(\.popupBackground, store.popupBackground)
    }

    private var cards: some View {
        VStack(spacing: 10) {
            if let pinned = store.pinned {
                MenuBarBusCard(store: store, bus: pinned, onEdit: { actions.editStop(pinned.stopCode) })
            }
            ForEach(groups, id: \.stopCode) { group in
                StopCard(store: store, stopCode: group.stopCode, buses: group.buses, actions: actions)
            }
        }
        .padding(12)
    }

    /// Saved buses grouped by stop, in saved order.
    private var groups: [(stopCode: String, buses: [SavedBus])] {
        var result: [(stopCode: String, buses: [SavedBus])] = []
        for bus in store.buses {
            if let index = result.firstIndex(where: { $0.stopCode == bus.stopCode }) {
                result[index].buses.append(bus)
            } else {
                result.append((bus.stopCode, [bus]))
            }
        }
        return result
    }
}

// MARK: - Header

private struct PopupHeader: View {
    let store: ArrivalStore

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("SGBusBar")
                    .font(.headline.weight(.bold))
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: store.feedStatus)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var subtitle: some View {
        if let lastUpdated = store.lastUpdated {
            Text("Updated \(lastUpdated, style: .relative) ago")
        } else if store.hasAPIKey {
            Text("Getting bus times…")
        } else {
            Text("Singapore bus arrivals")
        }
    }
}

/// "Live", "Offline" and so on, as a solid capsule so it reads on glass.
struct StatusBadge: View {
    let status: ArrivalStore.FeedStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
            Text(title)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
    }

    private var title: String {
        switch status {
        case .setUp: "Set up"
        case .loading: "Loading"
        case .live: "Live"
        case .offline: "Offline"
        }
    }

    private var color: Color {
        switch status {
        case .setUp: .accentColor
        case .loading: .gray
        case .live: Color(hex: 0x1F7F36)
        case .offline: Color(hex: 0xB35900)
        }
    }
}

// MARK: - Cards

/// The bus in your menu bar, large: how long until it comes and whether to leave now.
private struct MenuBarBusCard: View {
    let store: ArrivalStore
    let bus: SavedBus
    let onEdit: () -> Void

    private var arrivals: [Arrival]? { store.arrivals(for: bus) }
    private var next: TimeDisplay? { arrivals?.first.map { store.display($0, for: bus) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                formatMenu
                Spacer()
                if let next, store.colourTimes || next.urgency == .stale {
                    UrgencyBadge(time: next)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                ServiceBadge(serviceNo: bus.serviceNo)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.stopName(bus.stopCode))
                        .font(.headline)
                    if bus.walkMinutes > 0 {
                        Label("\(bus.walkMinutes) min walk", systemImage: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // The next bus's own details sit right beside its time.
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                bigTime
                if let first = arrivals?.first {
                    Details(arrival: first)
                        .help(ArrivalColumn.tooltip(for: first))
                }
                Spacer()
            }

            if let arrivals, arrivals.count > 1 {
                HStack(spacing: 14) {
                    Text("Then")
                        .foregroundStyle(.secondary)
                    ForEach(Array(arrivals.dropFirst().prefix(2).enumerated()), id: \.offset) { _, arrival in
                        HStack(spacing: 6) {
                            Text(store.display(arrival, for: bus).long)
                                .fontWeight(.medium)
                                .monospacedDigit()
                            BusInfo(arrival: arrival)
                        }
                        .help(ArrivalColumn.tooltip(for: arrival))
                    }
                }
                .font(.callout)
            }
        }
        .padding(14)
        .overlay(alignment: .leading) {
            // A strip in the urgency colour down the left edge.
            if let colour = next?.urgency.chipColor {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                    .fill(colour)
                    .frame(width: 5)
            }
        }
        .card()
        .contextMenu {
            Button("Edit Stop…", action: onEdit)
        }
    }

    @ViewBuilder private var bigTime: some View {
        if let arrivals {
            if let next {
                Text(next.long)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            } else if arrivals.isEmpty {
                Text(store.noArrivalsMessage(for: bus))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// "IN YOUR MENU BAR · NEXT 2 BUSES", which is also the quick way to change the format.
    private var formatMenu: some View {
        Menu {
            Picker("Menu bar shows", selection: Binding(get: { store.format }, set: { store.setFormat($0) })) {
                ForEach(MenuBarFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("In your menu bar · \(store.format == .iconOnly ? "icon only" : store.format.title)".uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change what the menu bar shows")
    }
}

/// "Leave now" and friends, in the urgency colour.
private struct UrgencyBadge: View {
    let time: TimeDisplay

    var body: some View {
        let colour = time.urgency.chipColor
        Text(time.minutes < 1 && time.urgency != .stale ? "Arriving" : time.urgency.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(colour == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(colour ?? Color.primary.opacity(0.08), in: Capsule())
    }
}

private struct StopCard: View {
    let store: ArrivalStore
    let stopCode: String
    let buses: [SavedBus]
    let actions: DropdownActions
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                StopHeading(name: store.stopName(stopCode), code: stopCode)
                Spacer()
                // Shown while the pointer is over the card, so the cards stay quiet otherwise.
                Button {
                    actions.editStop(stopCode)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0)
                .help("Rename this stop, or add and remove its buses")
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 2)
            ForEach(buses) { bus in
                BusRow(bus: bus, store: store, actions: actions)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .card()
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit Stop…") { actions.editStop(stopCode) }
            Button("Add Another Bus Here…") { actions.editStop(stopCode) }
        }
    }
}

/// "Home · 83139": the stop name in bold, the code small and grey. Also used by the previews.
struct StopHeading: View {
    let name: String
    let code: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.bold))
            Text("· \(code)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BusRow: View {
    let bus: SavedBus
    let store: ArrivalStore
    let actions: DropdownActions
    @State private var hovering = false

    private var isPinned: Bool { store.pinned?.id == bus.id }

    var body: some View {
        Button {
            store.pin(bus)
        } label: {
            // Line the service number up with the times, not with the details under them.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isPinned ? Color.accentColor : .clear)
                        .frame(width: 6, height: 6)
                    Text(bus.serviceNo)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(width: 44, alignment: .leading)
                }
                times
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isPinned ? "Shown in the menu bar" : "Click to show in the menu bar")
        .contextMenu {
            Button("Show in Menu Bar") { store.pin(bus) }
                .disabled(isPinned)
            Button("Edit Stop…") { actions.editStop(bus.stopCode) }
            Button("Add Another Bus Here…") { actions.editStop(bus.stopCode) }
        }
    }

    @ViewBuilder private var times: some View {
        if let arrivals = store.arrivals(for: bus) {
            if arrivals.isEmpty {
                Text(store.noArrivalsMessage(for: bus))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ArrivalColumns(store: store, bus: bus, arrivals: arrivals)
                Spacer(minLength: 0)
            }
        } else {
            ProgressView().controlSize(.small)
            Spacer()
        }
    }
}

/// The next bus's type, crowding and wheelchair access, on the menu bar bus's card.
private struct Details: View {
    let arrival: Arrival

    var body: some View {
        HStack(spacing: 6) {
            if let type = arrival.type {
                Text(type.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            if let load = arrival.load {
                HStack(spacing: 4) {
                    Circle().fill(load.color).frame(width: 7, height: 7)
                    Text(load.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if arrival.wheelchair {
                Image(systemName: "figure.roll")
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }
}

private struct EmptyBuses: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No buses yet")
                .font(.headline)
            Text("Add the buses you catch to see when they arrive.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add a Bus…", action: onAdd)
                .glassButton(prominent: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - First run

private struct SetupView: View {
    let store: ArrivalStore

    @State private var key = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect to LTA DataMall")
                .font(.headline)
            Text("Paste your DataMall AccountKey. It's stored in your Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("AccountKey", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Link("Get a free key", destination: URL(string: "https://datamall.lta.gov.sg/content/datamall/en/request-for-api.html")!)
                    .font(.callout)
                Spacer()
                Button(saving ? "Checking…" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                    .disabled(saving || key.isEmpty)
            }
        }
        .padding(16)
    }

    private func save() {
        saving = true
        Task {
            error = await store.saveAPIKey(key)
            saving = false
            if error == nil { key = "" }
        }
    }
}

// MARK: - Footer

private struct Footer: View {
    let store: ArrivalStore
    let actions: DropdownActions

    var body: some View {
        HStack(spacing: 8) {
            GlassGroup {
                HStack(spacing: 8) {
                    Button(action: actions.addBus) {
                        Label("Add Bus", systemImage: "plus")
                    }
                    .disabled(!store.hasAPIKey)

                    Button {
                        Task { await store.refresh(includingQuietStops: true) }
                    } label: {
                        Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!store.hasAPIKey || store.isRefreshing)
                    .keyboardShortcut("r")
                }
                .labelStyle(.titleAndIcon)
                .glassButton()
            }

            Spacer()

            GlassGroup {
                HStack(spacing: 8) {
                    Button(action: actions.openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .keyboardShortcut(",")
                    .help("Settings")

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .keyboardShortcut("q")
                    .help("Quit SGBusBar")
                }
                .glassButton()
                .buttonBorderShape(.circle)
            }
        }
        .controlSize(.large)
        .padding(12)
    }
}
