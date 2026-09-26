import SwiftUI

/// Identifies a stop for `.sheet(item:)`.
struct StopRef: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

/// Edit everything about one stop: its name, the walk there, and which buses you track at it.
/// Tick a service to add it, untick to remove it; nothing changes until Save.
struct StopEditor: View {
    let store: ArrivalStore
    let stopCode: String
    @Environment(\.dismiss) private var dismiss

    @State private var useNickname: Bool
    @State private var nickname: String
    @State private var walkMinutes: Int
    @State private var chosen: Set<String>
    @State private var extraServices: [String] = []
    @State private var live: [String: [Arrival]]?
    @State private var liveError: String?
    @State private var confirmingRemove = false

    init(store: ArrivalStore, stopCode: String) {
        self.store = store
        self.stopCode = stopCode
        let existing = store.nickname(forStop: stopCode)
        _useNickname = State(initialValue: existing != nil)
        _nickname = State(initialValue: existing ?? "")
        _walkMinutes = State(initialValue: store.walkMinutes(atStop: stopCode))
        _chosen = State(initialValue: Set(store.buses(atStop: stopCode).map(\.serviceNo)))
    }

    private var saved: [String] { store.buses(atStop: stopCode).map(\.serviceNo) }

    /// Kept in their current order, then the new ones.
    private var orderedChoice: [String] {
        saved.filter(chosen.contains) + chosen.subtracting(saved).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var removing: [String] { saved.filter { !chosen.contains($0) } }
    private var adding: Int { chosen.subtracting(saved).count }

    private var officialName: String { store.officialName(forStop: stopCode) }

    private var headingName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        return useNickname && !trimmed.isEmpty ? trimmed : officialName
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StopNamePicker(officialName: officialName, useNickname: $useNickname, nickname: $nickname)

                    WalkTimeStepper(minutes: $walkMinutes)

                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel("Buses at this stop")
                        ServiceChecklist(
                            store: store, stopCode: stopCode, live: live, liveError: liveError,
                            extraServices: $extraServices, chosen: $chosen, onRetry: loadServices
                        )
                    }

                    if !orderedChoice.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Preview")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                StopHeading(name: headingName, code: stopCode)
                                    .padding(.bottom, 2)
                                ForEach(orderedChoice, id: \.self) { service in
                                    ArrivalPreviewRow(
                                        store: store,
                                        bus: SavedBus(stopCode: stopCode, serviceNo: service, walkMinutes: walkMinutes),
                                        arrivals: live?[service] ?? store.arrivals[stopCode]?[service] ?? []
                                    )
                                }
                            }
                            .padding(10)
                            .card(cornerRadius: 10)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .task { loadServices() }
        .confirmationDialog("Remove \(store.stopName(stopCode))?", isPresented: $confirmingRemove) {
            Button("Remove Stop", role: .destructive) {
                store.removeStop(stopCode)
                dismiss()
            }
        } message: {
            Text("This removes its \(saved.count == 1 ? "bus" : "\(saved.count) buses"). You can add it again at any time.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Edit Stop")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(officialName)
                    .font(.title3.weight(.bold))
                Text([stopCode, store.directory.stop(code: stopCode)?.road].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Remove Stop…", role: .destructive) { confirmingRemove = true }
                .glassButton()
                .disabled(saved.isEmpty)
            Spacer()
            Text(changeSummary)
                .font(.callout)
                .foregroundStyle(removing.isEmpty ? Color.secondary : Color.red)
            GlassGroup {
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .glassButton()
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .glassButton(prominent: true)
                        .disabled(chosen.isEmpty)
                }
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    /// "Adds 1 · Removes 871", so it's clear what Save will do.
    private var changeSummary: String {
        if chosen.isEmpty { return "Tick a bus, or remove the stop" }
        var parts: [String] = []
        if adding > 0 { parts.append("Adds \(adding)") }
        if !removing.isEmpty { parts.append("Removes \(removing.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }

    private func loadServices() {
        liveError = nil
        Task {
            do {
                live = try await store.services(atStop: stopCode)
            } catch {
                liveError = error.localizedDescription
                live = [:]
            }
        }
    }

    private func save() {
        store.updateStop(stopCode, nickname: useNickname ? nickname : nil, walkMinutes: walkMinutes, services: orderedChoice)
        dismiss()
    }
}
