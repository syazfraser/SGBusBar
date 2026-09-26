import SwiftUI

// Form pieces shared by the Add Bus wizard and the Edit Stop sheet.

/// A small heading above a form field.
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
    }
}

/// Choose between LTA's name for the stop and a nickname of your own.
struct StopNamePicker: View {
    let officialName: String
    @Binding var useNickname: Bool
    @Binding var nickname: String
    /// Other saved buses at this stop, which will share the name.
    var otherBusesHere = 0

    @FocusState private var nicknameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("Name in the popup")
            Picker("Name in the popup", selection: $useNickname) {
                Text("Bus stop name: \(officialName)").tag(false)
                Text("Nickname").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            TextField("Nickname", text: $nickname, prompt: Text("e.g. Home or Office"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($nicknameFocused)
                .disabled(!useNickname)
                .padding(.leading, 20)

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: useNickname) {
            if useNickname { nicknameFocused = true }
        }
    }

    private var hint: String {
        let base = useNickname && nickname.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Leave it blank to use \(officialName)."
            : "Shown as this stop's heading in the popup."
        return base + Self.sharing(otherBusesHere)
    }

    /// " Your other bus here uses it too."
    static func sharing(_ others: Int) -> String {
        switch others {
        case 0: ""
        case 1: " Your other bus here uses it too."
        default: " Your \(others) other buses here use it too."
        }
    }
}

/// "4 min walk to the stop" with − / + buttons. One walk time per stop.
struct WalkTimeStepper: View {
    @Binding var minutes: Int
    /// Other saved buses at this stop, which will share the walk time.
    var otherBusesHere = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Walk to the stop")
            Stepper(value: $minutes, in: 0...30) {
                Label(
                    minutes == 0 ? "I'm usually at the stop already" : "\(minutes) min walk to the stop",
                    systemImage: "figure.walk"
                )
            }
            Text("Colours count the minutes you have to spare after walking: orange means leave now." + StopNamePicker.sharing(otherBusesHere))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One bus as it will look in the popup, coloured for the current walk time.
struct ArrivalPreviewRow: View {
    let store: ArrivalStore
    let bus: SavedBus
    let arrivals: [Arrival]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ServiceBadge(serviceNo: bus.serviceNo)
            if arrivals.isEmpty {
                Text(store.noArrivalsMessage(for: bus))
                    .foregroundStyle(.secondary)
            } else {
                ArrivalColumns(store: store, bus: bus, arrivals: arrivals)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

/// Every service that calls at a stop, as checkboxes: the ones running now show live times,
/// the rest show when they usually run. Typing a number in is only a fallback.
struct ServiceChecklist: View {
    let store: ArrivalStore
    let stopCode: String
    /// nil while loading.
    let live: [String: [Arrival]]?
    let liveError: String?
    @Binding var extraServices: [String]
    @Binding var chosen: Set<String>
    /// In the Add Bus wizard, buses you already have here are ticked and locked.
    var lockSaved = false
    let onRetry: () -> Void

    @State private var typed = ""
    @State private var showingManualEntry = false

    private var directory: BusStopDirectory { store.directory }

    /// From LTA's route list, so it includes services that aren't running right now.
    private var scheduled: [ServiceAtStop] { directory.services(atStop: stopCode) }

    private var services: [String] {
        let saved = store.buses(atStop: stopCode).map(\.serviceNo)
        let all = Set((live ?? [:]).keys).union(scheduled.map(\.serviceNo)).union(extraServices).union(saved)
        return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The route list couldn't be loaded, so typing a number in is the only way to find some services.
    private var routeListMissing: Bool {
        !directory.loadingServices && directory.servicesByStop.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if services.isEmpty && (live == nil || directory.loadingServices) {
                ProgressView("Finding the buses that stop here…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                if let liveError {
                    HStack {
                        Label("Couldn't get live times: \(liveError)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Retry", action: onRetry)
                    }
                    .font(.callout)
                }

                if services.isEmpty {
                    Text("LTA doesn't list any buses at this stop.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(services.enumerated()), id: \.element) { index, service in
                            if index > 0 { Divider().padding(.leading, 12) }
                            row(service)
                        }
                    }
                    .card(cornerRadius: 10)
                }

                if directory.loadingServices && scheduled.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking up every service at this stop, including ones not running now…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                manualEntry
            }
        }
        .task { await store.loadStopDirectory() }
    }

    @ViewBuilder private var manualEntry: some View {
        if showingManualEntry || routeListMissing {
            HStack {
                TextField("Service number, e.g. 243W", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .glassButton()
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(routeListMissing
                 ? "Couldn't load LTA's route list\(directory.servicesError.map { " (\($0))" } ?? ""), so only running services are listed. Type any others here."
                 : "Only needed for a service LTA hasn't listed at this stop yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !directory.loadingServices {
            Button("Service not listed?") { showingManualEntry = true }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private func row(_ service: String) -> some View {
        let locked = lockSaved && store.isSaved(stopCode: stopCode, serviceNo: service)
        return Toggle(isOn: Binding(
            get: { locked || chosen.contains(service) },
            set: { on in if on { chosen.insert(service) } else { chosen.remove(service) } }
        )) {
            HStack(spacing: 12) {
                ServiceBadge(serviceNo: service)
                Text(locked ? "Already added" : summary(for: service))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .disabled(locked)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// "Next in 3 min, then 11 min", or when it runs if it isn't running now.
    private func summary(for service: String) -> String {
        let now = Date()
        let minutes = (live?[service] ?? []).prefix(2).map { max(0, Int($0.eta.timeIntervalSince(now) / 60)) }
        if let first = minutes.first {
            let next = first < 1 ? "Arriving now" : "Next in \(first) min"
            return minutes.count > 1 ? "\(next), then \(minutes[1]) min" : next
        }
        guard let timetable = scheduled.first(where: { $0.serviceNo == service }) else {
            return live == nil ? "Checking live times…" : "Not running now"
        }
        guard let hours = timetable.hours(on: now) else {
            return timetable.otherDaysText.map { "Not today · \($0)" } ?? "Doesn't run today"
        }
        if live == nil { return "Usually \(hours.text)" }
        // LTA's advice: tell "should be running but no estimate" apart from "not scheduled now".
        let status = timetable.isInOperation(at: now) ? "No estimate available" : "Not in operation"
        return "\(status) · usually \(hours.text)"
    }

    private func addTyped() {
        let service = typed.trimmingCharacters(in: .whitespaces).uppercased()
        guard !service.isEmpty else { return }
        if !services.contains(service) {
            extraServices.append(service)
        }
        if !(lockSaved && store.isSaved(stopCode: stopCode, serviceNo: service)) {
            chosen.insert(service)
        }
        typed = ""
    }
}
