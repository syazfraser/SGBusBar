import Foundation
import Observation

/// Saved buses, preferences and the latest arrivals. Polls LTA once per distinct stop.
@MainActor
@Observable
final class ArrivalStore {
    private(set) var buses: [SavedBus]
    /// stop code → nickname. A stop without one uses LTA's name.
    private(set) var stopNicknames: [String: String]
    private(set) var pinnedID: SavedBus.ID?
    private(set) var format: MenuBarFormat
    private(set) var colourTimes: Bool
    private(set) var pollSeconds: Int
    private(set) var theme: AppTheme
    private(set) var popupBackground: PopupBackground
    private(set) var hasAPIKey: Bool

    /// stop code → service number → up to 3 arrivals. A missing stop means not loaded yet.
    private(set) var arrivals: [String: [String: [Arrival]]] = [:]
    /// When any stop last came back from LTA.
    private(set) var lastUpdated: Date?
    /// Set when every request in the last refresh failed.
    private(set) var lastError: String?
    /// False while macOS reports no network connection.
    private(set) var isOnline = true
    private(set) var isRefreshing = false
    /// stop code → when its times last came back (or it was skipped as having nothing scheduled).
    private(set) var stopUpdatedAt: [String: Date] = [:]
    /// Ticks so countdowns redraw between polls.
    private(set) var now = Date()

    @ObservationIgnored let directory: BusStopDirectory

    /// LTA refreshes arrival data every 20 seconds, so asking more often only repeats the same data.
    static let pollChoices = [20, 30, 45, 60, 90, 120, 300]
    static let minimumPollSeconds = 20
    static let defaultPollSeconds = 30
    static let tickInterval: Duration = .seconds(10)
    /// After failed refreshes the wait doubles, up to this.
    static let maxBackoffSeconds = 300
    /// LTA's guide warns buses can show up a little before the first scheduled one and after the last.
    static let scheduleMarginMinutes = 30
    /// A busy stop used to check a new API key when you have no buses yet (the example in LTA's guide).
    static let keyCheckStop = "83139"

    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The wait between polls, which `retryNow()` can cut short.
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    /// Poll again straight after the refresh under way instead of waiting.
    @ObservationIgnored private var retryRequested = false
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isPopupOpen = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var lastRefreshStarted: Date?

    /// `defaults`, `directory` and `apiKey` can be swapped out in tests, so they don't touch your
    /// real settings or Keychain.
    init(defaults: UserDefaults = .standard, directory: BusStopDirectory? = nil, apiKey: String? = Keychain.apiKey()) {
        self.defaults = defaults
        self.directory = directory ?? BusStopDirectory()

        buses = defaults.data(forKey: Keys.buses).flatMap { try? JSONDecoder().decode([SavedBus].self, from: $0) } ?? []
        stopNicknames = defaults.dictionary(forKey: Keys.stopNicknames) as? [String: String] ?? [:]
        pinnedID = defaults.string(forKey: Keys.pinnedID).flatMap(UUID.init(uuidString:))
        format = defaults.string(forKey: Keys.format).flatMap(MenuBarFormat.init(rawValue:)) ?? .nextAndSecond
        colourTimes = defaults.object(forKey: Keys.colourTimes) as? Bool ?? true
        let savedPoll = defaults.integer(forKey: Keys.pollSeconds)
        pollSeconds = savedPoll > 0 ? max(savedPoll, Self.minimumPollSeconds) : Self.defaultPollSeconds
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        popupBackground = defaults.string(forKey: Keys.popupBackground).flatMap(PopupBackground.init(rawValue:)) ?? .frosted
        self.apiKey = apiKey
        hasAPIKey = apiKey != nil
    }

    // MARK: - Reading

    var pinned: SavedBus? {
        buses.first { $0.id == pinnedID } ?? buses.first
    }

    var stopCount: Int {
        Set(buses.map(\.stopCode)).count
    }

    enum FeedStatus {
        case setUp, loading, live, offline
    }

    /// For the badge in the popup header and the Settings sidebar.
    var feedStatus: FeedStatus {
        if !hasAPIKey { return .setUp }
        if !isOnline { return .offline }
        if lastUpdated == nil { return lastError == nil ? .loading : .offline }
        return isStale ? .offline : .live
    }

    /// Two missed polls (and at least 2 minutes) before data counts as stale.
    private var staleAfter: TimeInterval { max(120, Double(pollSeconds) * 2.5) }

    /// Nothing has come back from LTA for a while.
    var isStale: Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > staleAfter
    }

    /// This stop's times are too old to trust, e.g. its requests have been failing.
    func isStale(stop code: String) -> Bool {
        guard let updated = stopUpdatedAt[code] else { return false }
        return now.timeIntervalSince(updated) > staleAfter
    }

    /// Whether LTA's timetable has this bus running now; nil if the route list doesn't cover it.
    func isInOperation(_ bus: SavedBus, marginMinutes: Int = 0) -> Bool? {
        directory.services(atStop: bus.stopCode)
            .first { $0.serviceNo == bus.serviceNo }
            .map { $0.isInOperation(at: now, marginMinutes: marginMinutes) }
    }

    /// What to show when a bus has no times, as LTA's guide advises: either there's no estimate
    /// right now, or it isn't scheduled to run at this hour.
    func noArrivalsMessage(for bus: SavedBus) -> String {
        switch isInOperation(bus) {
        case false?: "Not in operation"
        case true?: "No estimate available"
        case nil: "Not running now"
        }
    }

    func isSaved(stopCode: String, serviceNo: String) -> Bool {
        buses.contains { $0.stopCode == stopCode && $0.serviceNo == serviceNo }
    }

    func busCount(atStop code: String) -> Int {
        buses.filter { $0.stopCode == code }.count
    }

    /// The name shown for a stop: its nickname, else LTA's name.
    func stopName(_ code: String) -> String {
        stopNicknames[code] ?? officialName(forStop: code)
    }

    func officialName(forStop code: String) -> String {
        directory.stop(code: code)?.description ?? "Stop \(code)"
    }

    func nickname(forStop code: String) -> String? {
        stopNicknames[code]
    }

    /// nil = not loaded yet; empty = not running now.
    func arrivals(for bus: SavedBus) -> [Arrival]? {
        guard let services = arrivals[bus.stopCode] else { return nil }
        let cutoff = now.addingTimeInterval(-60)
        return (services[bus.serviceNo] ?? []).filter { $0.eta > cutoff }
    }

    func display(_ arrival: Arrival, for bus: SavedBus) -> TimeDisplay {
        let minutes = max(0, Int(arrival.eta.timeIntervalSince(now) / 60))
        let urgency: Urgency =
            if isStale(stop: bus.stopCode) { .stale }
            else if colourTimes { Urgency(minutesAway: minutes, walkMinutes: bus.walkMinutes) }
            else { .relaxed }
        return TimeDisplay(minutes: minutes, monitored: arrival.monitored, urgency: urgency)
    }

    /// Live arrivals at any stop, for the Add Bus wizard.
    func services(atStop stopCode: String) async throws -> [String: [Arrival]] {
        guard let apiKey else { throw LTAClient.Failure.unauthorized }
        return try await LTAClient(apiKey: apiKey).arrivals(atStop: stopCode)
    }

    /// `force` downloads the stop list even if it's less than a week old.
    func loadStopDirectory(force: Bool = false) async {
        guard let apiKey else { return }
        let client = LTAClient(apiKey: apiKey)
        if force {
            await directory.load(using: client)
        } else {
            await directory.loadIfNeeded(using: client)
        }
    }

    // MARK: - Buses

    func add(_ newBuses: [SavedBus], pin: Bool) {
        buses += newBuses
        if pin, let first = newBuses.first { self.pin(first) }
        saveBuses()
        Task { await refresh() }
    }

    func remove(_ bus: SavedBus) {
        buses.removeAll { $0.id == bus.id }
        saveBuses()
    }

    // MARK: - Stops

    /// Stops in the order the popup shows them, i.e. by each stop's first bus.
    var stopCodes: [String] {
        var seen = Set<String>()
        return buses.compactMap { seen.insert($0.stopCode).inserted ? $0.stopCode : nil }
    }

    func buses(atStop code: String) -> [SavedBus] {
        buses.filter { $0.stopCode == code }
    }

    /// The walk is the same whichever bus you catch, so every bus at a stop shares it.
    func walkMinutes(atStop code: String) -> Int {
        buses.first { $0.stopCode == code }?.walkMinutes ?? 0
    }

    /// Saves a stop in one go: its name, its walk time, and which services you want there
    /// (in order). Services left out are removed; new ones go after the stop's other buses.
    func updateStop(_ code: String, nickname: String?, walkMinutes: Int, services: [String]) {
        setNickname(nickname, forStop: code)
        let wanted = Set(services)
        buses.removeAll { $0.stopCode == code && !wanted.contains($0.serviceNo) }
        for index in buses.indices where buses[index].stopCode == code {
            buses[index].walkMinutes = walkMinutes
        }
        let existing = Set(buses(atStop: code).map(\.serviceNo))
        let added = services.filter { !existing.contains($0) }.map {
            SavedBus(stopCode: code, serviceNo: $0, walkMinutes: walkMinutes)
        }
        let insertAt = buses.lastIndex { $0.stopCode == code }.map { $0 + 1 } ?? buses.endIndex
        buses.insert(contentsOf: added, at: insertAt)
        saveBuses()
        if !arrivals.keys.contains(code) { Task { await refresh() } }
    }

    func removeStop(_ code: String) {
        buses.removeAll { $0.stopCode == code }
        saveBuses()
    }

    /// Moves a stop up (-1) or down (+1) in the popup.
    func moveStop(_ code: String, by offset: Int) {
        var order = stopCodes
        guard let from = order.firstIndex(of: code), order.indices.contains(from + offset) else { return }
        order.swapAt(from, from + offset)
        buses = order.flatMap { buses(atStop: $0) }
        saveBuses()
    }

    /// Reorders the buses within one stop.
    func moveBuses(atStop code: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        var here = buses(atStop: code)
        here.move(fromOffsets: source, toOffset: destination)
        buses = stopCodes.flatMap { $0 == code ? here : buses(atStop: $0) }
        saveBuses()
    }

    func pin(_ bus: SavedBus) {
        pinnedID = bus.id
        defaults.set(bus.id.uuidString, forKey: Keys.pinnedID)
    }

    private func saveBuses() {
        defaults.set(try? JSONEncoder().encode(buses), forKey: Keys.buses)
    }

    /// nil or blank goes back to LTA's name. Applies to every bus at the stop.
    func setNickname(_ nickname: String?, forStop code: String) {
        let trimmed = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        stopNicknames[code] = trimmed.isEmpty ? nil : trimmed
        defaults.set(stopNicknames, forKey: Keys.stopNicknames)
    }

    // MARK: - Preferences

    func setFormat(_ newFormat: MenuBarFormat) {
        let wasShowingTimes = format.count > 0
        format = newFormat
        defaults.set(newFormat.rawValue, forKey: Keys.format)
        // Polling pauses while the menu bar shows no times, so catch up straight away.
        if !wasShowingTimes && newFormat.count > 0 { Task { await refresh() } }
    }

    func setColourTimes(_ on: Bool) {
        colourTimes = on
        defaults.set(on, forKey: Keys.colourTimes)
    }

    func setTheme(_ newTheme: AppTheme) {
        theme = newTheme
        defaults.set(newTheme.rawValue, forKey: Keys.theme)
    }

    func setPopupBackground(_ background: PopupBackground) {
        popupBackground = background
        defaults.set(background.rawValue, forKey: Keys.popupBackground)
    }

    func setPollSeconds(_ seconds: Int) {
        pollSeconds = seconds
        defaults.set(seconds, forKey: Keys.pollSeconds)
        if pollTask != nil { start() }  // apply now, not after the current wait
    }

    /// Tests the key against LTA before saving it. Returns an error message on failure.
    func saveAPIKey(_ key: String) async -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Paste your AccountKey first." }
        do {
            _ = try await LTAClient(apiKey: key).arrivals(atStop: pinned?.stopCode ?? Self.keyCheckStop)
        } catch {
            return error.localizedDescription
        }
        guard Keychain.setAPIKey(key) else { return "Couldn't save the key to the Keychain." }
        apiKey = key
        hasAPIKey = true
        start()
        return nil
    }

    // MARK: - Polling

    func start() {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                await self?.waitForNextPoll()
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.now = Date()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        waitTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
    }

    /// With "None" in the menu bar and the popup closed, nothing on screen needs live times.
    private func poll() async {
        retryRequested = false
        guard format.count > 0 || isPopupOpen else { return }
        await refresh()
    }

    /// Sleeps until the next poll is due, unless `retryNow()` asks for one sooner.
    private func waitForNextPoll() async {
        guard !retryRequested else { return }
        let delay = nextPollDelay
        let wait = Task { _ = try? await Task.sleep(for: .seconds(delay)) }
        waitTask = wait
        await wait.value
        if waitTask == wait { waitTask = nil }
    }

    /// Polls now, or straight after the refresh under way.
    private func retryNow() {
        retryRequested = true
        waitTask?.cancel()
    }

    /// The chosen interval, doubled after each refresh that LTA failed outright (up to 5 minutes),
    /// so an LTA outage isn't retried every 30 seconds. Having no internet doesn't count: those
    /// requests never reach LTA, and coming back online retries straight away (see `setOnline`).
    var nextPollDelay: Int {
        guard consecutiveFailures > 0 else { return pollSeconds }
        return min(pollSeconds << min(consecutiveFailures, 4), Self.maxBackoffSeconds)
    }

    /// Called when the Mac's network connection comes or goes. Coming back online, e.g. once
    /// Wi-Fi joins after starting up or waking, fetches times straight away instead of waiting
    /// for the next poll, unless they're already fresh.
    func setOnline(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        guard cameBack else { return }
        let age = lastUpdated.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age >= Double(Self.minimumPollSeconds) else { return }
        consecutiveFailures = 0
        retryNow()
    }

    /// Opening the popup gets fresh times unless the last ones are under 20 seconds old (LTA's
    /// update interval), including stops that polling skips because nothing is scheduled there.
    func setPopupOpen(_ open: Bool) {
        isPopupOpen = open
        guard open else { return }
        let age = lastRefreshStarted.map { Date().timeIntervalSince($0) } ?? .infinity
        if age >= Double(Self.minimumPollSeconds) {
            Task { await refresh(includingQuietStops: true) }
        }
    }

    /// One request per stop you track. A stop with a single tracked service asks for just that
    /// service. Stops where the timetable has nothing running (give or take 30 minutes) are skipped
    /// unless `includingQuietStops`. A stop whose request fails keeps its last times, which go
    /// grey once stale, without affecting the other stops.
    func refresh(includingQuietStops: Bool = false) async {
        guard let apiKey, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefreshStarted = Date()

        var requests: [(stop: String, serviceNo: String?)] = []
        var quietStops: [String] = []
        for code in stopCodes {
            let here = buses(atStop: code)
            let scheduled = here.contains { isInOperation($0, marginMinutes: Self.scheduleMarginMinutes) != false }
            if includingQuietStops || scheduled {
                requests.append((code, here.count == 1 ? here[0].serviceNo : nil))
            } else {
                quietStops.append(code)
            }
        }

        let client = LTAClient(apiKey: apiKey)
        var fetched: [String: [String: [Arrival]]] = [:]
        var failure: String?
        var reachedLTA = false
        await withTaskGroup(of: StopFetch.self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let services = try await client.arrivals(atStop: request.stop, serviceNo: request.serviceNo)
                        return StopFetch(stop: request.stop, services: services, error: nil, noConnection: false)
                    } catch {
                        return StopFetch(stop: request.stop, services: nil, error: error.localizedDescription,
                                         noConnection: Self.isConnectionError(error))
                    }
                }
            }
            for await result in group {
                if let services = result.services { fetched[result.stop] = services }
                if let error = result.error { failure = error }
                if !result.noConnection { reachedLTA = true }
            }
        }
        // Stopped mid-refresh (e.g. the Mac is going to sleep): don't count it as a failure.
        if Task.isCancelled { return }

        let finished = Date()
        let allFailed = !requests.isEmpty && fetched.isEmpty
        for code in quietStops { fetched[code] = [:] }
        for code in fetched.keys { stopUpdatedAt[code] = finished }
        let tracked = Set(stopCodes)
        arrivals = arrivals.merging(fetched) { _, new in new }.filter { tracked.contains($0.key) }

        if allFailed {
            // With no internet the requests never reached LTA, so there's nothing to back off from.
            if reachedLTA { consecutiveFailures += 1 }
            lastError = failure
        } else {
            consecutiveFailures = 0
            lastError = nil
            lastUpdated = finished
            retryRequested = false
        }
        now = finished
    }

    /// Errors that mean the Mac isn't online (yet), rather than LTA having trouble.
    private nonisolated static func isConnectionError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        let offline: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed,
            .dataNotAllowed, .internationalRoamingOff,
        ]
        return offline.contains(error.code)
    }

    /// One stop's outcome in a refresh. Deliberately not `Result<_, Error>`: with the Release
    /// optimiser (Swift 6.3, Xcode 26.6), a task group of those comes back empty and then crashes
    /// the app on launch. A plain struct works in both builds.
    private struct StopFetch: Sendable {
        let stop: String
        let services: [String: [Arrival]]?
        let error: String?
        /// Failed because the Mac has no connection, so the request never reached LTA.
        let noConnection: Bool
    }

    private enum Keys {
        static let buses = "buses"
        static let stopNicknames = "stopNicknames"
        static let pinnedID = "pinnedID"
        static let format = "menuBarFormat"
        static let colourTimes = "colourTimes"
        static let pollSeconds = "pollSeconds"
        static let theme = "theme"
        static let popupBackground = "popupBackground"

    }
}
