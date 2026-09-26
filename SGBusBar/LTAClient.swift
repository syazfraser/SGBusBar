import Foundation

/// LTA DataMall: BusArrival v3, and the BusStops and BusRoutes lists.
struct LTAClient {
    enum Failure: LocalizedError {
        case unauthorized
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "LTA rejected the API key"
            case .http(let code): "LTA returned HTTP \(code)"
            }
        }
    }

    let apiKey: String

    private static let base = URL(string: "https://datamall2.mytransport.sg/ltaodataservice/")!
    /// LTA's lists come 500 rows per request.
    private static let pageSize = 500
    private static let pagesAtOnce = 6

    /// Arrivals at a stop, keyed by service number: every service, or just `serviceNo`
    /// (a much smaller response at a busy interchange). A service missing from the result isn't running.
    func arrivals(atStop stopCode: String, serviceNo: String? = nil) async throws -> [String: [Arrival]] {
        var query = ["BusStopCode": stopCode]
        if let serviceNo { query["ServiceNo"] = serviceNo }
        let decoded: ArrivalResponse = try await get("v3/BusArrival", query: query)
        return Dictionary(decoded.services.map { ($0.serviceNo, $0.arrivals) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every bus stop in Singapore (about 5,200).
    func busStops() async throws -> [BusStop] {
        let rows: [StopRow] = try await allPages("BusStops")
        return rows.map { BusStop(code: $0.code, description: $0.description, road: $0.road) }
    }

    /// Both views of LTA's route list (about 26,800 rows, one per service per stop).
    struct RouteLists {
        /// stop code → every service that calls there, with its hours.
        var servicesByStop: [String: [ServiceAtStop]]
        /// Every direction of every service, with its stops in order, sorted by service number.
        var routes: [ServiceRoute]
    }

    func routeLists() async throws -> RouteLists {
        let rows: [RouteRow] = try await allPages("BusRoutes")

        var servicesByStop: [String: [ServiceAtStop]] = [:]
        for row in rows {
            // A loop service can call at a stop in both directions; list it once.
            if servicesByStop[row.stopCode]?.contains(where: { $0.serviceNo == row.serviceNo }) == true { continue }
            servicesByStop[row.stopCode, default: []].append(ServiceAtStop(
                serviceNo: row.serviceNo,
                weekday: RouteRow.hours(row.weekdayFirst, row.weekdayLast),
                saturday: RouteRow.hours(row.saturdayFirst, row.saturdayLast),
                sunday: RouteRow.hours(row.sundayFirst, row.sundayLast)
            ))
        }

        let byDirection = Dictionary(grouping: rows) { "\($0.serviceNo)-\($0.direction ?? 1)" }
        let routes = byDirection.values.compactMap { rows -> ServiceRoute? in
            let ordered = rows.sorted { ($0.stopSequence ?? 0) < ($1.stopSequence ?? 0) }.map(\.stopCode)
            guard let first = ordered.first, let row = rows.first else { return nil }
            var seen = Set<String>()
            return ServiceRoute(
                serviceNo: row.serviceNo,
                direction: row.direction ?? 1,
                stopCodes: ordered.filter { seen.insert($0).inserted },
                isLoop: ordered.count > 1 && ordered.last == first
            )
        }
        .sorted { a, b in
            a.serviceNo == b.serviceNo ? a.direction < b.direction
                : a.serviceNo.localizedStandardCompare(b.serviceNo) == .orderedAscending
        }
        return RouteLists(servicesByStop: servicesByStop, routes: routes)
    }

    /// Fetches a whole LTA list, several pages at a time, until a page comes back short.
    private func allPages<Row: Decodable>(_ path: String) async throws -> [Row] {
        var all: [Row] = []
        var skip = 0
        while true {
            let pages = try await withThrowingTaskGroup(of: (Int, [Row]).self) { group in
                for offset in stride(from: skip, to: skip + Self.pagesAtOnce * Self.pageSize, by: Self.pageSize) {
                    group.addTask {
                        let page: Page<Row> = try await getRetrying(path, query: ["$skip": String(offset)])
                        return (offset, page.value)
                    }
                }
                var pages: [(Int, [Row])] = []
                for try await page in group {
                    pages.append(page)
                }
                return pages.sorted { $0.0 < $1.0 }.map(\.1)
            }
            all += pages.joined()
            if pages.contains(where: { $0.count < Self.pageSize }) {
                return all
            }
            skip += Self.pagesAtOnce * Self.pageSize
        }
    }

    /// LTA sometimes answers a burst of list requests with a 500; one bad page shouldn't sink
    /// the whole download, so each page gets two more tries, 1 then 2 seconds apart.
    private func getRetrying<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        for wait in [1, 2] {
            do {
                return try await get(path, query: query)
            } catch Failure.unauthorized {
                throw Failure.unauthorized
            } catch {
                try await Task.sleep(for: .seconds(wait))
            }
        }
        return try await get(path, query: query)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "AccountKey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 401 ? Failure.unauthorized : Failure.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - BusArrival

private struct ArrivalResponse: Decodable {
    let services: [Service]

    enum CodingKeys: String, CodingKey {
        case services = "Services"
    }
}

private struct Service: Decodable {
    let serviceNo: String
    let nextBus: NextBus?
    let nextBus2: NextBus?
    let nextBus3: NextBus?

    enum CodingKeys: String, CodingKey {
        case serviceNo = "ServiceNo"
        case nextBus = "NextBus"
        case nextBus2 = "NextBus2"
        case nextBus3 = "NextBus3"
    }

    var arrivals: [Arrival] {
        [nextBus, nextBus2, nextBus3].compactMap { $0?.arrival }
    }
}

/// A missing bus comes back with every field as an empty string,
/// so each field is decoded leniently and an unparseable time means no bus.
private struct NextBus: Decodable {
    let estimatedArrival: String?
    let monitored: Int?
    let load: String?
    let feature: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case estimatedArrival = "EstimatedArrival"
        case monitored = "Monitored"
        case load = "Load"
        case feature = "Feature"
        case type = "Type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        estimatedArrival = try? c.decode(String.self, forKey: .estimatedArrival)
        monitored = try? c.decode(Int.self, forKey: .monitored)
        load = try? c.decode(String.self, forKey: .load)
        feature = try? c.decode(String.self, forKey: .feature)
        type = try? c.decode(String.self, forKey: .type)
    }

    var arrival: Arrival? {
        guard let estimatedArrival, let eta = try? Date(estimatedArrival, strategy: .iso8601) else { return nil }
        return Arrival(
            eta: eta,
            load: load.flatMap(Load.init(rawValue:)),
            type: type.flatMap(BusType.init(rawValue:)),
            monitored: monitored == 1,
            wheelchair: feature == "WAB"
        )
    }
}

// MARK: - Lists

/// One page of an LTA list.
private struct Page<Row: Decodable>: Decodable {
    let value: [Row]
}

private struct StopRow: Decodable {
    let code: String
    let description: String
    let road: String

    enum CodingKeys: String, CodingKey {
        case code = "BusStopCode"
        case description = "Description"
        case road = "RoadName"
    }
}

/// One service at one stop: its direction, where the stop falls on the route, and first and last bus times ("0548", or "-" if it doesn't run that day).
private struct RouteRow: Decodable {
    let serviceNo: String
    let direction: Int?
    let stopSequence: Int?
    let stopCode: String
    let weekdayFirst: String?
    let weekdayLast: String?
    let saturdayFirst: String?
    let saturdayLast: String?
    let sundayFirst: String?
    let sundayLast: String?

    enum CodingKeys: String, CodingKey {
        case serviceNo = "ServiceNo"
        case direction = "Direction"
        case stopSequence = "StopSequence"
        case stopCode = "BusStopCode"
        case weekdayFirst = "WD_FirstBus"
        case weekdayLast = "WD_LastBus"
        case saturdayFirst = "SAT_FirstBus"
        case saturdayLast = "SAT_LastBus"
        case sundayFirst = "SUN_FirstBus"
        case sundayLast = "SUN_LastBus"
    }

    static func hours(_ first: String?, _ last: String?) -> ServiceHours? {
        guard let first, let last, first.count == 4, last.count == 4, first.allSatisfy(\.isNumber) else { return nil }
        return ServiceHours(first: first, last: last)
    }
}
