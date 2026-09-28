import Foundation
import Testing
@testable import SGBusBar

/// Answers the app's LTA requests with canned responses, so the tests never touch the network.
/// Only for requests made with this suite's key, so other suites can fake LTA their own way.
final class FakeLTA: URLProtocol {
    static let apiKey = "test"
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = "{}"
    nonisolated(unsafe) static var lastURL: URL?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.contains("mytransport.sg") == true
            && request.value(forHTTPHeaderField: "AccountKey") == apiKey
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Shaped like LTA's BusArrival v3 response: a GPS-tracked bus, a scheduled one, and a missing third.
private let arrivalsJSON = """
{
  "BusStopCode": "83139",
  "Services": [{
    "ServiceNo": "15",
    "Operator": "GAS",
    "NextBus": {"EstimatedArrival": "2026-09-26T16:41:48+08:00", "Monitored": 1, "Load": "SEA", "Feature": "WAB", "Type": "SD"},
    "NextBus2": {"EstimatedArrival": "2026-09-26T16:49:22+08:00", "Monitored": 0, "Load": "SDA", "Feature": "", "Type": "DD"},
    "NextBus3": {"EstimatedArrival": "", "Monitored": 0, "Load": "", "Feature": "", "Type": ""}
  }]
}
"""

@Suite("Reading LTA DataMall responses", .serialized)
struct LTAClientTests {
    private let client = LTAClient(apiKey: FakeLTA.apiKey)

    init() {
        URLProtocol.registerClass(FakeLTA.self)
        FakeLTA.status = 200
        FakeLTA.body = "{}"
        FakeLTA.lastURL = nil
    }

    @Test("Arrivals, including a scheduled bus and a missing one")
    func arrivals() async throws {
        FakeLTA.body = arrivalsJSON
        let services = try await client.arrivals(atStop: "83139")
        let times = try #require(services["15"])
        #expect(times.count == 2)
        #expect(times[0].monitored)
        #expect(times[0].load == .seats)
        #expect(times[0].type == .single)
        #expect(times[0].wheelchair)
        #expect(!times[1].monitored)
        #expect(times[1].load == .standing)
        #expect(times[1].type == .double)
        #expect(!times[1].wheelchair)
        #expect(times[0].eta < times[1].eta)
    }

    @Test("Asking for one service adds ServiceNo to the request")
    func serviceFilter() async throws {
        FakeLTA.body = arrivalsJSON
        _ = try await client.arrivals(atStop: "83139", serviceNo: "15")
        let query = URLComponents(url: try #require(FakeLTA.lastURL), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "BusStopCode", value: "83139")))
        #expect(query.contains(URLQueryItem(name: "ServiceNo", value: "15")))
    }

    @Test("A stop with nothing running comes back empty")
    func nothingRunning() async throws {
        FakeLTA.body = #"{"BusStopCode": "46961", "Services": []}"#
        #expect(try await client.arrivals(atStop: "46961").isEmpty)
    }

    @Test("A rejected key is reported as such")
    func rejectedKey() async {
        FakeLTA.status = 401
        await #expect(throws: LTAClient.Failure.self) {
            try await client.arrivals(atStop: "83139")
        }
    }
}
