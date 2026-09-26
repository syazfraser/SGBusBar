import Foundation
import Observation

/// All Singapore bus stops, the services at each, and every service's route, for the Add Bus
/// wizard and Edit Stop.
/// Both lists are cached in Application Support and refreshed weekly.
@MainActor
@Observable
final class BusStopDirectory {
    enum State: Equatable {
        case empty
        case loading
        case ready
        case failed(String)
    }

    /// The stop list.
    private(set) var state: State = .empty
    private(set) var stops: [BusStop] = []
    /// stop code → every service that calls there, running now or not. Empty until loaded.
    private(set) var servicesByStop: [String: [ServiceAtStop]] = [:]
    /// Every direction of every service with its stops in order, for finding a stop by bus.
    private(set) var routes: [ServiceRoute] = []
    private(set) var loadingServices = false
    private(set) var servicesError: String?
    /// When the lists were last downloaded from LTA.
    private(set) var updatedAt: Date?
    private var byCode: [String: BusStop] = [:]
    @ObservationIgnored private var isLoading = false

    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "SGBusBar/bus-stops.json")
    }

    private static var servicesCacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "SGBusBar/stop-services.json")
    }

    private static var routesCacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "SGBusBar/service-routes.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode([BusStop].self, from: data) {
            use(cached, updatedAt: Self.modificationDate(of: Self.cacheURL))
        }
        if let data = try? Data(contentsOf: Self.servicesCacheURL),
           let cached = try? JSONDecoder().decode([String: [ServiceAtStop]].self, from: data) {
            servicesByStop = cached
        }
        if let data = try? Data(contentsOf: Self.routesCacheURL),
           let cached = try? JSONDecoder().decode([ServiceRoute].self, from: data) {
            routes = cached
        }
    }

    /// Starts from the given lists instead of the cache on disk, for tests.
    init(stops: [BusStop], servicesByStop: [String: [ServiceAtStop]] = [:], routes: [ServiceRoute] = []) {
        use(stops, updatedAt: nil)
        self.servicesByStop = servicesByStop
        self.routes = routes
    }

    func stop(code: String) -> BusStop? {
        byCode[code]
    }

    /// Every service that calls at a stop, whether or not it's running right now.
    func services(atStop code: String) -> [ServiceAtStop] {
        servicesByStop[code] ?? []
    }

    /// How many different services the route list covers.
    var serviceCount: Int {
        Set(servicesByStop.values.flatMap { $0.map(\.serviceNo) }).count
    }

    /// Loads from LTA unless both lists are less than a week old. Keeps the old lists if a download fails.
    func loadIfNeeded(using client: LTAClient) async {
        let fresh = updatedAt.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false
        if state == .ready, fresh, !servicesByStop.isEmpty, !routes.isEmpty { return }
        await load(using: client)
    }

    /// Downloads both lists now, whatever their age: stops first so search works sooner, then services.
    func load(using client: LTAClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let previous = state
        if stops.isEmpty { state = .loading }
        do {
            let fresh = try await client.busStops()
            use(fresh, updatedAt: Date())
            Self.save(fresh, to: Self.cacheURL)
        } catch {
            state = stops.isEmpty ? .failed(error.localizedDescription) : previous
        }

        loadingServices = true
        servicesError = nil
        do {
            let lists = try await client.routeLists()
            servicesByStop = lists.servicesByStop
            routes = lists.routes
            Self.save(lists.servicesByStop, to: Self.servicesCacheURL)
            Self.save(lists.routes, to: Self.routesCacheURL)
        } catch {
            if servicesByStop.isEmpty { servicesError = error.localizedDescription }
        }
        loadingServices = false
    }

    private static func save(_ value: some Encodable, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: url)
    }

    /// "To Bukit Batok Int", or "Loop from Tengah Int" for a service that comes back to where it started.
    func title(of route: ServiceRoute) -> String {
        let first = route.stopCodes.first.flatMap(stop(code:))?.description ?? "its first stop"
        let last = route.stopCodes.last.flatMap(stop(code:))?.description ?? "its last stop"
        return route.isLoop ? "Loop from \(first)" : "To \(last)"
    }

    /// "From Tengah Int · 32 stops"
    func subtitle(of route: ServiceRoute) -> String {
        let first = route.stopCodes.first.flatMap(stop(code:))?.description
        let count = "\(route.stopCodes.count) stops"
        return route.isLoop || first == nil ? count : "From \(first!) · \(count)"
    }

    /// Finds buses by service number ("99" also finds 990, 991…), or by where they go
    /// ("joo koon" finds services to or from Joo Koon).
    func searchRoutes(_ query: String, limit: Int = 40) -> [ServiceRoute] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let upper = query.uppercased()
        let byNumber = routes.filter { $0.serviceNo.uppercased().hasPrefix(upper) }
        if !byNumber.isEmpty {
            // An exact match first, then the rest in number order (routes are already sorted).
            return Array((byNumber.filter { $0.serviceNo == upper } + byNumber.filter { $0.serviceNo != upper }).prefix(limit))
        }
        let words = query.lowercased().split(separator: " ")
        return Array(routes.lazy.filter { route in
            let ends = [route.stopCodes.first, route.stopCodes.last].compactMap { $0.flatMap(self.stop(code:))?.description }
            let text = ends.joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }.prefix(limit))
    }

    /// Matches a 5-digit code prefix, or every word against the stop name and road.
    func search(_ query: String, limit: Int = 40) -> [BusStop] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }

        if query.allSatisfy(\.isNumber) {
            return Array(stops.lazy.filter { $0.code.hasPrefix(query) }.prefix(limit))
        }

        let words = query.split(separator: " ")
        let matches = stops.filter { stop in
            let haystack = "\(stop.description) \(stop.road)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        // Names that start with the query first, then the rest alphabetically.
        return Array(matches.sorted { a, b in
            let aStarts = a.description.lowercased().hasPrefix(query)
            let bStarts = b.description.lowercased().hasPrefix(query)
            if aStarts != bStarts { return aStarts }
            return a.description < b.description
        }.prefix(limit))
    }

    private func use(_ list: [BusStop], updatedAt: Date?) {
        stops = list
        byCode = Dictionary(list.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        self.updatedAt = updatedAt
        state = .ready
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
