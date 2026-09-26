import SwiftUI

struct SettingsView: View {
    let store: ArrivalStore
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        // A sidebar like System Settings; on macOS 26 it floats as Liquid Glass.
        NavigationSplitView {
            List(selection: Binding(get: { navigation.tab }, set: { if let tab = $0 { navigation.tab = tab } })) {
                Section("App") {
                    sidebarRow(.general)
                    sidebarRow(.appearance)
                    sidebarRow(.menuBar)
                }
                Section("Buses") {
                    sidebarRow(.buses, badge: store.buses.count)
                }
                Section("System") {
                    sidebarRow(.about)
                }
            }
            .safeAreaInset(edge: .bottom) { SidebarFooter(store: store) }
            .navigationSplitViewColumnWidth(210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch navigation.tab {
                case .general: GeneralPage(store: store)
                case .appearance: AppearancePage(store: store)
                case .menuBar: MenuBarPage(store: store)
                case .buses: BusesPage(store: store, navigation: navigation)
                case .about: AboutPage(store: store)
                }
            }
            .navigationTitle(navigation.tab.title)
        }
        .frame(minWidth: 820, minHeight: 580)
    }

    /// `tag` must come last: a modifier after it (e.g. `badge`) hides the tag from the list,
    /// and that row can't be selected.
    private func sidebarRow(_ tab: SettingsTab, badge: Int = 0) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            SettingsIcon(systemName: tab.systemImage, color: tab.color)
        }
        .badge(badge)
        .tag(tab)
    }
}

extension SettingsTab {
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .buses: "Buses"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .menuBar: "menubar.rectangle"
        case .buses: "bus.fill"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .menuBar: .indigo
        case .buses: Color(hex: 0x1F9A48)
        case .about: .gray
        }
    }
}

/// "● v0.2 · Live" at the bottom of the sidebar.
private struct SidebarFooter: View {
    let store: ArrivalStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text("v\(AppInfo.version) · \(statusText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        switch store.feedStatus {
        case .setUp: "No API key"
        case .loading: "Connecting"
        case .live: "Live"
        case .offline: "Offline"
        }
    }

    private var dotColor: Color {
        switch store.feedStatus {
        case .setUp, .loading: .gray
        case .live: .green
        case .offline: .orange
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    static let author = "syazfraser"
    static let authorURL = URL(string: "https://github.com/syazfraser")!
    static let repositoryURL = URL(string: "https://github.com/syazfraser/SGBusBar")!
    static let issuesURL = URL(string: "https://github.com/syazfraser/SGBusBar/issues/new/choose")!
    static let releasesURL = URL(string: "https://github.com/syazfraser/SGBusBar/releases")!
    static let licenseURL = URL(string: "https://github.com/syazfraser/SGBusBar/blob/main/LICENSE")!
}

/// The versions from CHANGELOG.md, newest first.
private struct WhatsNewView: View {
    let entries: [ChangelogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("What's New")
                        .font(.title2.weight(.bold))
                    Text("You're on version \(AppInfo.version)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if entries.isEmpty {
                        Text("The changelog isn't available in this build.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Version \(entry.version)")
                                    .font(.headline)
                                if entry.version == AppInfo.version || entry.version == AppInfo.version + ".0" {
                                    Text("Installed")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Spacer()
                                if let date = entry.date {
                                    Text(date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(entry.summary, id: \.self) { line in
                                Text(Self.markdown(line))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                                if let title = section.title {
                                    Text(title.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }
                                ForEach(section.items, id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•").foregroundStyle(.secondary)
                                        Text(Self.markdown(item))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(cornerRadius: 12)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Link("All releases on GitHub", destination: AppInfo.releasesURL)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 560, height: 580)
    }

    /// Lets the changelog use **bold** and [links].
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: - General

private struct GeneralPage: View {
    let store: ArrivalStore
    @State private var loginItem = LoginItem()

    var body: some View {
        SettingsPage(title: "General", subtitle: "Startup, refresh and your LTA connection.") {
            SettingsCard {
                SettingsRow(title: "Launch at Login", detail: loginDetail) {
                    RowToggle(isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                }
                if loginItem.needsApproval {
                    RowDivider()
                    SettingsRow(title: "Allow in System Settings", detail: "macOS needs you to switch SGBusBar on under Login Items.") {
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                            .glassButton()
                    }
                }
            }
            .onAppear { loginItem.refresh() }

            SettingsCard(label: "Refresh") {
                SettingsRow(title: "Check for new times every", detail: refreshDetail) {
                    Picker("Check for new times every", selection: Binding(get: { store.pollSeconds }, set: { store.setPollSeconds($0) })) {
                        ForEach(ArrivalStore.pollChoices, id: \.self) { seconds in
                            Text(Self.label(forSeconds: seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(label: "LTA DataMall") {
                APIKeyRow(store: store)
            }
        }
    }

    private var loginDetail: String {
        loginItem.error ?? "Start SGBusBar automatically when you log in to your Mac."
    }

    private var refreshDetail: String {
        let perHour = store.stopCount * 3600 / max(store.pollSeconds, 1)
        return "LTA updates arrival times every 20 seconds, so that's the fastest option. Your \(store.buses.count) buses are at \(store.stopCount) stops: up to \(store.stopCount) requests per refresh (about \(perHour) an hour). Stops with no buses scheduled are skipped, and nothing is fetched while your Mac sleeps or the menu bar shows no times."
    }

    static func label(forSeconds seconds: Int) -> String {
        let text = switch seconds {
        case 60: "1 minute"
        case 120, 300: "\(seconds / 60) minutes"
        default: "\(seconds) seconds"
        }
        return seconds == ArrivalStore.defaultPollSeconds ? "\(text) (recommended)" : text
    }
}

private struct APIKeyRow: View {
    let store: ArrivalStore
    @State private var changing = false
    @State private var newKey = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        if changing || !store.hasAPIKey {
            VStack(alignment: .leading, spacing: 8) {
                Text("API key")
                    .fontWeight(.medium)
                SecureField("Paste your AccountKey", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                HStack {
                    Link("Get a free key", destination: URL(string: "https://datamall.lta.gov.sg/content/datamall/en/request-for-api.html")!)
                    Spacer()
                    if store.hasAPIKey {
                        Button("Cancel") {
                            changing = false
                            newKey = ""
                            error = nil
                        }
                        .glassButton()
                    }
                    Button(saving ? "Checking…" : "Save Key", action: save)
                        .glassButton(prominent: true)
                        .disabled(saving || newKey.isEmpty)
                }
            }
            .padding(16)
        } else {
            SettingsRow(title: "API key", detail: "Saved in your Keychain. Used only to ask LTA for arrival times.") {
                HStack(spacing: 10) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                    Button("Change…") { changing = true }
                        .glassButton()
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            error = await store.saveAPIKey(newKey)
            saving = false
            if error == nil {
                changing = false
                newKey = ""
            }
        }
    }
}

// MARK: - Appearance

private struct AppearancePage: View {
    let store: ArrivalStore

    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "How the popup and this window look.") {
            SettingsCard(label: "Theme") {
                ThemePicker(
                    selection: Binding(get: { store.theme }, set: { store.setTheme($0) }),
                    background: store.popupBackground
                )
                Text("System follows your Mac's Light or Dark setting. The menu bar itself always follows macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                RowDivider()
                SettingsRow(title: "Popup background", detail: store.popupBackground == .frosted
                            ? "A clean light or dark surface that looks the same over any wallpaper."
                            : "See-through Liquid Glass; your wallpaper shows behind the cards.") {
                    Picker("Popup background", selection: Binding(get: { store.popupBackground }, set: { store.setPopupBackground($0) })) {
                        ForEach(PopupBackground.allCases) { background in
                            Text(background.title).tag(background)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(label: "Time colours") {
                SettingsRow(title: "Colour-code times", detail: "Colour each arrival by how soon you need to leave.") {
                    RowToggle(isOn: Binding(get: { store.colourTimes }, set: { store.setColourTimes($0) }))
                }
                ForEach(Self.bands, id: \.urgency) { band in
                    RowDivider()
                    SettingsRow(title: band.urgency.title, detail: band.detail) {
                        TimeChip(time: TimeDisplay(minutes: band.sampleMinutes, monitored: true, urgency: band.urgency))
                    }
                    .opacity(store.colourTimes ? 1 : 0.45)
                }
                Text("Minutes to spare = minutes until the bus minus your walk to the stop. Set walk times under Buses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .padding(.top, 4)
            }
        }
    }

    private static let bands: [(urgency: Urgency, detail: String, sampleMinutes: Int)] = [
        (.miss, "Under 1 min to spare: you'll miss it unless you're at the stop.", 0),
        (.leaveNow, "1–4 min to spare.", 3),
        (.comfortable, "5–14 min to spare.", 9),
        (.relaxed, "15 min or more to spare.", 19),
    ]
}

/// Light, Dark and System as pictures of the popup, like macOS's own Appearance settings.
private struct ThemePicker: View {
    @Binding var selection: AppTheme
    let background: PopupBackground

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppTheme.allCases) { theme in
                let selected = theme == selection
                Button {
                    selection = theme
                } label: {
                    VStack(spacing: 6) {
                        ThemeThumbnail(theme: theme, background: background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                                    .padding(selected ? -3 : 0)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        Text(theme.title)
                            .fontWeight(selected ? .semibold : .regular)
                        Text(theme.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Menu Bar

private struct MenuBarPage: View {
    let store: ArrivalStore

    var body: some View {
        SettingsPage(title: "Menu Bar", subtitle: "Choose what appears in your menu bar. The popup always shows the next 3 buses.") {
            SettingsCard(label: "Bus times in the menu bar") {
                OptionTiles(
                    options: MenuBarFormat.allCases.map { .init(value: $0, title: $0.title, detail: $0.example, systemImage: $0.systemImage) },
                    selection: Binding(get: { store.format }, set: { store.setFormat($0) }),
                    columns: 2
                )
                HStack {
                    Text("Preview")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    MenuBarPreview(format: store.format, coloured: store.colourTimes)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            SettingsCard(label: "Which bus") {
                SettingsRow(title: "Shown in the menu bar", detail: "You can also click any bus in the popup.") {
                    Picker("Shown in the menu bar", selection: Binding(get: { store.pinned?.id }, set: { id in
                        if let bus = store.buses.first(where: { $0.id == id }) { store.pin(bus) }
                    })) {
                        ForEach(store.buses) { bus in
                            Text("\(bus.serviceNo) at \(store.stopName(bus.stopCode))").tag(Optional(bus.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(store.buses.isEmpty)
                }
            }
        }
    }
}

extension MenuBarFormat {
    var example: String {
        switch self {
        case .iconOnly: "Just the bus icon"
        case .nextOnly: "992  3m"
        case .nextAndSecond: "992  3m · 11m"
        case .nextThree: "992  3m · 11m · 19m"
        }
    }

    var systemImage: String {
        switch self {
        case .iconOnly: "bus.fill"
        case .nextOnly: "1.circle.fill"
        case .nextAndSecond: "2.circle.fill"
        case .nextThree: "3.circle.fill"
        }
    }
}

/// A sample of the menu bar label for the chosen format, drawn on a dark strip like the menu bar
/// over a dark wallpaper, using the same system colours as the real one.
private struct MenuBarPreview: View {
    let format: MenuBarFormat
    let coloured: Bool

    private let samples: [(String, Urgency)] = [("3m", .leaveNow), ("11m", .comfortable), ("19m", .relaxed)]

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bus.fill")
            if format.count > 0 {
                Text("992 ")
                ForEach(0..<format.count, id: \.self) { index in
                    if index > 0 { Text("·").opacity(0.6) }
                    let (text, urgency) = samples[index]
                    Text(text)
                        .foregroundStyle(coloured ? urgency.nsColor.map(Color.init(nsColor:)) ?? .white : .white)
                }
            }
        }
        .font(.body.monospacedDigit())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.85), in: Capsule())
    }
}

// MARK: - Buses

private struct BusesPage: View {
    let store: ArrivalStore
    @Bindable var navigation: SettingsNavigation
    @State private var selection: SavedBus.ID?
    @State private var removingBus: SavedBus?
    @State private var removingStop: String?

    private var selectedBus: SavedBus? {
        store.buses.first { $0.id == selection }
    }

    var body: some View {
        SettingsPage(title: "Buses", subtitle: "Your stops and the buses you catch at each. Edit a stop to rename it or add and remove its buses.", scrolls: false) {
            if store.buses.isEmpty {
                ContentUnavailableView {
                    Label("No buses yet", systemImage: "bus")
                } description: {
                    Text("Add the buses you catch and see their next arrivals in the menu bar.")
                } actions: {
                    Button("Add a Bus…") { navigation.addingBus = true }
                        .glassButton(prominent: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card(cornerRadius: 12)
            } else {
                list
            }

            HStack {
                Button {
                    navigation.addingBus = true
                } label: {
                    Label("Add Bus…", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .glassButton(prominent: true)
                .help("Find a stop, or find your bus and pick its stop")

                Spacer()

                GlassGroup {
                    HStack(spacing: 6) {
                        Button("Show in Menu Bar") {
                            if let selectedBus { store.pin(selectedBus) }
                        }
                        .disabled(selectedBus == nil || selectedBus?.id == store.pinned?.id)
                        Button("Remove Bus…", role: .destructive) { removingBus = selectedBus }
                            .disabled(selectedBus == nil)
                    }
                    .glassButton()
                }
            }
            .controlSize(.large)
        }
        .sheet(isPresented: $navigation.addingBus) {
            AddBusWizard(store: store)
        }
        .sheet(item: $navigation.editingStop) { stop in
            StopEditor(store: store, stopCode: stop.code)
        }
        .confirmationDialog(
            removingBus.map { "Remove \($0.serviceNo) at \(store.stopName($0.stopCode))?" } ?? "",
            isPresented: Binding(get: { removingBus != nil }, set: { if !$0 { removingBus = nil } }),
            presenting: removingBus
        ) { bus in
            Button("Remove", role: .destructive) {
                store.remove(bus)
                if selection == bus.id { selection = nil }
            }
        } message: { _ in
            Text("You can add it again at any time.")
        }
        .confirmationDialog(
            removingStop.map { "Remove \(store.stopName($0)) and its buses?" } ?? "",
            isPresented: Binding(get: { removingStop != nil }, set: { if !$0 { removingStop = nil } }),
            presenting: removingStop
        ) { code in
            Button("Remove Stop", role: .destructive) { store.removeStop(code) }
        } message: { _ in
            Text("You can add it again at any time.")
        }
    }

    /// One section per stop, in popup order; drag buses to reorder them within their stop.
    private var list: some View {
        let stops = store.stopCodes
        return List(selection: $selection) {
            ForEach(Array(stops.enumerated()), id: \.element) { index, code in
                Section {
                    ForEach(store.buses(atStop: code)) { bus in
                        BusSettingsRow(store: store, bus: bus, isPinned: store.pinned?.id == bus.id)
                            .tag(bus.id)
                    }
                    .onMove { store.moveBuses(atStop: code, fromOffsets: $0, toOffset: $1) }
                } header: {
                    StopSectionHeader(
                        store: store,
                        stopCode: code,
                        canMoveUp: index > 0,
                        canMoveDown: index < stops.count - 1,
                        onEdit: { navigation.editingStop = StopRef(code: code) },
                        onRemove: { removingStop = code }
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.inset)
        .contextMenu(forSelectionType: SavedBus.ID.self) { ids in
            if let bus = store.buses.first(where: { ids.contains($0.id) }) {
                Button("Show in Menu Bar") { store.pin(bus) }
                    .disabled(store.pinned?.id == bus.id)
                Button("Edit Stop…") { navigation.editingStop = StopRef(code: bus.stopCode) }
                Divider()
                Button("Remove Bus…", role: .destructive) { removingBus = bus }
            }
        } primaryAction: { ids in
            if let bus = store.buses.first(where: { ids.contains($0.id) }) {
                navigation.editingStop = StopRef(code: bus.stopCode)
            }
        }
        .onDeleteCommand { removingBus = selectedBus }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card(cornerRadius: 12)
    }
}

/// A stop's name, what LTA calls it, its walk time, and what you can do with it.
private struct StopSectionHeader: View {
    let store: ArrivalStore
    let stopCode: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let nickname = store.nickname(forStop: stopCode)
        let stop = store.directory.stop(code: stopCode)
        let walk = store.walkMinutes(atStop: stopCode)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.stopName(stopCode))
                    .font(.headline)
                    .foregroundStyle(.primary)
                // With a nickname, LTA's name goes underneath so it's still clear which stop it is.
                Text([nickname == nil ? nil : stop?.description, stop?.road, "Stop \(stopCode)", walk > 0 ? "\(walk) min walk" : nil]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onEdit) {
                Label("Edit Stop…", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
            .glassButton()
            .controlSize(.small)
            .help("Rename this stop, change the walk, or add and remove its buses")
            Menu {
                Button("Move Up") { store.moveStop(stopCode, by: -1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { store.moveStop(stopCode, by: 1) }
                    .disabled(!canMoveDown)
                Divider()
                Button("Remove Stop…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .glassButton()
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .fixedSize()
            .help("Move or remove this stop")
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .textCase(nil)
    }
}

/// One bus under its stop: the service number, its next arrival, and whether it's in the menu bar.
private struct BusSettingsRow: View {
    let store: ArrivalStore
    let bus: SavedBus
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 12) {
            ServiceBadge(serviceNo: bus.serviceNo)
            Text(nextArrival)
                .foregroundStyle(.secondary)
            Spacer()
            if isPinned {
                Label("Menu bar", systemImage: "menubar.rectangle")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 3)
    }

    private var nextArrival: String {
        guard let arrivals = store.arrivals(for: bus) else { return "" }
        guard let first = arrivals.first else { return store.noArrivalsMessage(for: bus) }
        let time = store.display(first, for: bus)
        return time.minutes < 1 ? "Arriving now" : "Next in \(time.long)"
    }
}

/// A service number in a rounded badge, like the number on the front of the bus.
struct ServiceBadge: View {
    let serviceNo: String

    var body: some View {
        Text(serviceNo)
            .font(.body.weight(.semibold).monospacedDigit())
            .frame(minWidth: 44)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - About

private struct AboutPage: View {
    let store: ArrivalStore
    @State private var updatingStops = false
    @State private var showingWhatsNew = false

    var body: some View {
        SettingsPage(title: "About", subtitle: "Singapore bus arrivals in your menu bar.") {
            HStack(spacing: 18) {
                AppIconView(size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SGBusBar")
                        .font(.title.weight(.bold))
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .foregroundStyle(.secondary)
                    Text("Your next buses at a glance, coloured by when to leave.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("Made by")
                        Link(AppInfo.author, destination: AppInfo.authorURL)
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 12)

            GlassGroup {
                HStack(spacing: 8) {
                    Button {
                        showingWhatsNew = true
                    } label: {
                        Label("What's New", systemImage: "sparkles")
                    }
                    .glassButton(prominent: true)
                    Link(destination: AppInfo.repositoryURL) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .glassButton()
                    Link(destination: AppInfo.issuesURL) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                    .glassButton()
                }
                .labelStyle(.titleAndIcon)
            }

            SettingsCard(label: "Data") {
                SettingsRow(title: "Bus arrivals", detail: "Live from LTA DataMall, every \(GeneralPage.label(forSeconds: store.pollSeconds).replacingOccurrences(of: " (recommended)", with: "")).") {
                    Link(destination: URL(string: "https://datamall.lta.gov.sg")!) {
                        Label("LTA DataMall", systemImage: "arrow.up.right")
                    }
                }
                RowDivider()
                SettingsRow(title: "Bus stops and routes", detail: stopsDetail) {
                    Button(updatingStops ? "Updating…" : "Update Now") {
                        updatingStops = true
                        Task {
                            await store.loadStopDirectory(force: true)
                            updatingStops = false
                        }
                    }
                    .glassButton()
                    .disabled(updatingStops || !store.hasAPIKey)
                }
                RowDivider()
                SettingsRow(title: "Your data", detail: "Your buses and settings stay on this Mac. The API key is kept in your Keychain.") {
                    EmptyView()
                }
            }

            HStack(spacing: 4) {
                Text("Open source under the")
                Link("MIT licence", destination: AppInfo.licenseURL)
                Text("· Arrival times are LTA's estimates and can change. SGBusBar isn't affiliated with LTA.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(entries: Changelog.load())
        }
    }

    private var stopsDetail: String {
        let directory = store.directory
        let count = directory.stops.count
        guard count > 0 else { return "Not downloaded yet. It downloads when you first add a bus." }
        let when = directory.updatedAt.map { "updated \($0.formatted(.relative(presentation: .named)))" } ?? "saved on this Mac"
        let services = directory.loadingServices
            ? " and their services (downloading…)"
            : directory.serviceCount > 0 ? " and \(directory.serviceCount.formatted()) services" : ""
        return "\(count.formatted()) stops\(services), \(when). Refreshed weekly so you can pick buses without typing."
    }
}
