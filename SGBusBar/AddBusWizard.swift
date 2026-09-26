import SwiftUI

/// Three steps: find the stop, tick the services, then name it and set the walk time.
struct AddBusWizard: View {
    let store: ArrivalStore
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case stop, services, details

        var title: String {
            switch self {
            case .stop: "Find your stop"
            case .services: "Pick your buses"
            case .details: "Final touches"
            }
        }

        var subtitle: String {
            switch self {
            case .stop: "Search for the stop, or for your bus and pick the stop from its route."
            case .services: "Every bus that stops here is listed. Tick the ones you catch."
            case .details: "Keep the stop's name or give it a nickname, and set your walk so the colours tell you when to leave."
            }
        }
    }

    @State private var step = Step.stop
    @State private var findBy = FindBy.stop
    @State private var stop: BusStop?
    /// Searching by bus picks the service too, so step 2 starts with it ticked.
    @State private var preselectedService: String?
    @State private var live: [String: [Arrival]]?
    @State private var liveError: String?
    @State private var extraServices: [String] = []
    @State private var chosen: Set<String> = []
    @State private var useNickname = false
    @State private var nickname = ""
    @State private var walkMinutes = 0
    @State private var showInMenuBar = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case .stop:
                    FindStep(store: store, findBy: $findBy, stop: $stop, preselectedService: $preselectedService, onChoose: advance)
                case .services:
                    ServicesStep(
                        store: store, stop: stop!, live: live, liveError: liveError,
                        extraServices: $extraServices, chosen: $chosen, onRetry: loadServices
                    )
                case .details:
                    DetailsStep(
                        store: store, stop: stop!, services: orderedChoice, live: live ?? [:],
                        useNickname: $useNickname, nickname: $nickname,
                        walkMinutes: $walkMinutes, showInMenuBar: $showInMenuBar
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 540, height: 620)
        .task { await store.loadStopDirectory() }
        .onAppear { showInMenuBar = store.buses.isEmpty }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 28, height: 4)
                }
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Text(step.title)
                .font(.title2.weight(.semibold))
            Text(step.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .glassButton()
            Spacer()
            GlassGroup {
                HStack(spacing: 8) {
                    if step != .stop {
                        Button("Back") { step = Step(rawValue: step.rawValue - 1)! }
                            .glassButton()
                    }
                    Button(primaryTitle, action: advance)
                        .keyboardShortcut(.defaultAction)
                        .glassButton(prominent: true)
                        .disabled(!canAdvance)
                }
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    private var primaryTitle: String {
        guard step == .details else { return "Continue" }
        return chosen.count > 1 ? "Add \(chosen.count) Buses" : "Add Bus"
    }

    private var canAdvance: Bool {
        switch step {
        case .stop: stop != nil
        case .services: !chosen.isEmpty
        case .details: true
        }
    }

    private var orderedChoice: [String] {
        chosen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func advance() {
        guard canAdvance, let stop else { return }
        switch step {
        case .stop:
            // Start from the stop's current name and walk, if you already have buses there.
            let existing = store.nickname(forStop: stop.code)
            useNickname = existing != nil
            nickname = existing ?? ""
            walkMinutes = store.walkMinutes(atStop: stop.code)
            live = nil
            if let service = preselectedService, !store.isSaved(stopCode: stop.code, serviceNo: service) {
                chosen = [service]
            } else {
                chosen = []
            }
            extraServices = []
            loadServices()
            step = .services
        case .services:
            step = .details
        case .details:
            let name = useNickname ? nickname : nil
            let existing = store.buses(atStop: stop.code).map(\.serviceNo)
            if existing.isEmpty {
                let buses = orderedChoice.map {
                    SavedBus(stopCode: stop.code, serviceNo: $0, walkMinutes: walkMinutes)
                }
                store.setNickname(name, forStop: stop.code)
                store.add(buses, pin: showInMenuBar)
            } else {
                // A stop you already have: the new buses join it and share its name and walk.
                store.updateStop(stop.code, nickname: name, walkMinutes: walkMinutes, services: existing + orderedChoice)
                if showInMenuBar, let first = store.buses(atStop: stop.code).first(where: { $0.serviceNo == orderedChoice.first }) {
                    store.pin(first)
                }
            }
            dismiss()
        }
    }

    private func loadServices() {
        guard let stop else { return }
        liveError = nil
        Task {
            do {
                live = try await store.services(atStop: stop.code)
            } catch {
                liveError = error.localizedDescription
                live = [:]
            }
        }
    }
}

// MARK: - Step 1: find the stop

enum FindBy: Hashable {
    case stop, bus
}

/// Step 1: search for the stop itself, or for your bus and pick the stop along its route.
private struct FindStep: View {
    let store: ArrivalStore
    @Binding var findBy: FindBy
    @Binding var stop: BusStop?
    @Binding var preselectedService: String?
    let onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Find by", selection: $findBy) {
                Label("Stop", systemImage: "mappin.and.ellipse").tag(FindBy.stop)
                Label("Bus", systemImage: "bus").tag(FindBy.bus)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch findBy {
            case .stop:
                StopStep(store: store, stop: $stop, onChoose: onChoose)
            case .bus:
                RouteStep(store: store, stop: $stop, service: $preselectedService, onChoose: onChoose)
            }
        }
        .onChange(of: findBy) {
            stop = nil
            preselectedService = nil
        }
    }
}

/// The glass search capsule used by both searches.
private struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassBackground(in: Capsule())
    }
}

/// Search by bus: pick a service and direction, then the stop you get on at.
private struct RouteStep: View {
    let store: ArrivalStore
    @Binding var stop: BusStop?
    @Binding var service: String?
    let onChoose: () -> Void

    @State private var query = ""
    @State private var route: ServiceRoute?
    @FocusState private var searchFocused: Bool

    private var directory: BusStopDirectory { store.directory }

    private var results: [ServiceRoute] { directory.searchRoutes(query) }

    /// Routes of buses you already track, for one-click picks before you type.
    private var yourRoutes: [ServiceRoute] {
        let yours = Set(store.buses.map(\.serviceNo))
        return directory.routes.filter { yours.contains($0.serviceNo) }
    }

    var body: some View {
        if let route {
            RouteStops(store: store, route: route, stop: $stop, onBack: {
                self.route = nil
                stop = nil
            }, onChoose: onChoose)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SearchField(prompt: "Bus number, or where it goes, e.g. 992 or Joo Koon", text: $query) {
                    if let first = results.first { pick(first) }
                }
                .focused($searchFocused)

                if directory.routes.isEmpty {
                    if directory.loadingServices || directory.state == .loading {
                        ProgressView("Loading bus routes… (first time only)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("Couldn't load bus routes", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(directory.servicesError ?? "Check your internet connection, or search by stop instead.")
                        } actions: {
                            Button("Try Again") { Task { await store.loadStopDirectory(force: true) } }
                        }
                    }
                } else if query.isEmpty {
                    if !yourRoutes.isEmpty {
                        Text("Your buses")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        routeList(yourRoutes)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    routeList(results)
                }
            }
            .onAppear { searchFocused = true }
        }
    }

    private func routeList(_ routes: [ServiceRoute]) -> some View {
        List(routes) { route in
            Button { pick(route) } label: {
                HStack(spacing: 12) {
                    ServiceBadge(serviceNo: route.serviceNo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(directory.title(of: route))
                            .fontWeight(.medium)
                        Text(directory.subtitle(of: route))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.bordered)
    }

    private func pick(_ picked: ServiceRoute) {
        route = picked
        service = picked.serviceNo
        stop = nil
    }
}

/// A route's stops in order; pick the one you get on at. Stops you already have are marked.
private struct RouteStops: View {
    let store: ArrivalStore
    let route: ServiceRoute
    @Binding var stop: BusStop?
    let onBack: () -> Void
    let onChoose: () -> Void

    private var directory: BusStopDirectory { store.directory }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                Label("All buses", systemImage: "chevron.left")
            }
            .buttonStyle(.link)

            HStack(spacing: 10) {
                ServiceBadge(serviceNo: route.serviceNo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(directory.title(of: route))
                        .font(.headline)
                    Text("Pick the stop where you get on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollViewReader { proxy in
                List(selection: Binding(get: { stop?.code }, set: { code in stop = code.map(busStop) })) {
                    ForEach(Array(route.stopCodes.enumerated()), id: \.element) { index, code in
                        row(index: index, code: code)
                            .tag(code)
                            .id(code)
                    }
                }
                .listStyle(.bordered)
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { codes in
                    if let code = codes.first {
                        stop = busStop(code)
                        onChoose()
                    }
                }
                // Start at a stop you already use on this route, if there is one.
                .onAppear {
                    if let yours = route.stopCodes.first(where: { store.busCount(atStop: $0) > 0 }) {
                        proxy.scrollTo(yours, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(index: Int, code: String) -> some View {
        let info = directory.stop(code: code)
        let nickname = store.nickname(forStop: code)
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(nickname ?? info?.description ?? "Stop \(code)")
                    .fontWeight(.medium)
                Text([nickname == nil ? nil : info?.description, code, info?.road].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.busCount(atStop: code) > 0 {
                Text("Your stop")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func busStop(_ code: String) -> BusStop {
        directory.stop(code: code) ?? BusStop(code: code, description: "Stop \(code)", road: "")
    }
}

// MARK: - Step 1: search by stop


private struct StopStep: View {
    let store: ArrivalStore
    @Binding var stop: BusStop?
    let onChoose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var directory: BusStopDirectory { store.directory }

    /// Stops the user already has buses at, for one-click picks.
    private var savedStops: [BusStop] {
        var seen = Set<String>()
        return store.buses.compactMap { bus in
            guard seen.insert(bus.stopCode).inserted else { return nil }
            return directory.stop(code: bus.stopCode)
                ?? BusStop(code: bus.stopCode, description: store.stopName(bus.stopCode), road: "")
        }
    }

    private var results: [BusStop] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var found = directory.search(trimmed)
        // A full 5-digit code works even if the stop list couldn't load.
        if trimmed.count == 5, trimmed.allSatisfy(\.isNumber), !found.contains(where: { $0.code == trimmed }) {
            found.insert(BusStop(code: trimmed, description: "Stop \(trimmed)", road: ""), at: 0)
        }
        return found
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchField(prompt: "Stop name, road or code, e.g. Joo Koon Int or 24009", text: $query) {
                if let first = results.first { stop = first; onChoose() }
            }
            .focused($searchFocused)

            if query.isEmpty {
                if !savedStops.isEmpty {
                    Text("Your stops")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    stopList(savedStops)
                }
            } else if directory.state == .loading && results.isEmpty {
                ProgressView("Loading Singapore's bus stops… (first time only)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                noResults
            } else {
                stopList(results)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: query) {
            // Keep the choice only while it's still on screen.
            if let stop, !results.contains(stop), !savedStops.contains(stop) { self.stop = nil }
        }
    }

    private func stopList(_ stops: [BusStop]) -> some View {
        List(stops, selection: Binding(get: { stop?.code }, set: { code in stop = stops.first { $0.code == code } })) { item in
            // Your nickname first, with LTA's name underneath.
            let nickname = store.nickname(forStop: item.code)
            VStack(alignment: .leading, spacing: 1) {
                Text(nickname ?? item.description)
                    .fontWeight(.medium)
                Text([nickname == nil ? "" : item.description, item.code, item.road].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(item.code)
        }
        .listStyle(.bordered)
        .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { codes in
            if let code = codes.first, let picked = stops.first(where: { $0.code == code }) {
                stop = picked
                onChoose()
            }
        }
    }

    @ViewBuilder private var noResults: some View {
        if case .failed(let message) = directory.state {
            ContentUnavailableView {
                Label("Couldn't load the stop list", systemImage: "wifi.exclamationmark")
            } description: {
                Text("\(message). You can still type the 5-digit stop code.")
            } actions: {
                Button("Try Again") { Task { await store.loadStopDirectory() } }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

// MARK: - Step 2: services

private struct ServicesStep: View {
    let store: ArrivalStore
    let stop: BusStop
    let live: [String: [Arrival]]?
    let liveError: String?
    @Binding var extraServices: [String]
    @Binding var chosen: Set<String>
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StopTitle(stop: stop)
            ScrollView {
                ServiceChecklist(
                    store: store, stopCode: stop.code, live: live, liveError: liveError,
                    extraServices: $extraServices, chosen: $chosen, lockSaved: true, onRetry: onRetry
                )
            }
        }
    }
}

// MARK: - Step 3: details

private struct DetailsStep: View {
    let store: ArrivalStore
    let stop: BusStop
    let services: [String]
    let live: [String: [Arrival]]
    @Binding var useNickname: Bool
    @Binding var nickname: String
    @Binding var walkMinutes: Int
    @Binding var showInMenuBar: Bool

    /// The heading the popup will show, as you type.
    private var headingName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        return useNickname && !trimmed.isEmpty ? trimmed : stop.description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StopTitle(stop: stop)

            StopNamePicker(
                officialName: stop.description,
                useNickname: $useNickname,
                nickname: $nickname,
                otherBusesHere: store.busCount(atStop: stop.code)
            )

            WalkTimeStepper(minutes: $walkMinutes, otherBusesHere: store.busCount(atStop: stop.code))

            Toggle("Show in the menu bar", isOn: $showInMenuBar)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    StopHeading(name: headingName, code: stop.code)
                        .padding(.bottom, 2)
                    ForEach(services, id: \.self) { service in
                        ArrivalPreviewRow(
                            store: store,
                            bus: SavedBus(stopCode: stop.code, serviceNo: service, walkMinutes: walkMinutes),
                            arrivals: live[service] ?? []
                        )
                    }
                }
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            }
        }
    }
}

/// The stop's name and code, at the top of steps 2 and 3.
private struct StopTitle: View {
    let stop: BusStop

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(stop.description)
                    .font(.headline)
                Text([stop.code, stop.road].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
