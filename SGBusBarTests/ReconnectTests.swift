import Foundation
import Testing
@testable import SGBusBar

/// Answers the store's LTA requests in these tests (only those made with this key): as if the
/// Mac had no internet, or with an empty response and the given status.
final class ScriptedLTA: URLProtocol {
    static let apiKey = "reconnect-test"
    nonisolated(unsafe) static var offline = true
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "AccountKey") == apiKey
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"BusStopCode": "43009", "Services": []}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Starting up or waking before Wi-Fi has joined, then getting a connection.
@MainActor
@Suite("Losing and regaining the internet connection", .serialized)
struct ReconnectTests {
    private static let suiteName = "SGBusBarReconnectTests"
    private let store: ArrivalStore

    init() throws {
        URLProtocol.registerClass(ScriptedLTA.self)
        ScriptedLTA.offline = true
        ScriptedLTA.status = 200

        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        let defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.set(try JSONEncoder().encode([SavedBus(stopCode: "43009", serviceNo: "992")]), forKey: "buses")
        store = ArrivalStore(defaults: defaults, directory: BusStopDirectory(stops: []), apiKey: ScriptedLTA.apiKey)
    }

    @Test("With no internet it keeps trying at the normal interval, not ever slower")
    func offlineDoesNotBackOff() async {
        await store.refresh()
        await store.refresh()
        #expect(store.lastError != nil)
        #expect(store.nextPollDelay == store.pollSeconds)
    }

    @Test("LTA failing still backs off")
    func ltaErrorsBackOff() async {
        ScriptedLTA.offline = false
        ScriptedLTA.status = 500
        await store.refresh()
        #expect(store.lastError != nil)
        #expect(store.nextPollDelay == store.pollSeconds * 2)
    }

    @Test("Coming back online fetches times straight away, not at the next poll")
    func reconnectFetchesNow() async throws {
        store.start()
        defer { store.stop() }
        try await waitUntil { store.lastError != nil }

        store.setOnline(false)
        #expect(store.feedStatus == .offline)

        ScriptedLTA.offline = false
        store.setOnline(true)
        try await waitUntil { store.lastUpdated != nil }
        #expect(store.lastError == nil)
        #expect(store.feedStatus == .live)
    }

    /// Polls for up to 3 seconds, far less than the 30 seconds until the next scheduled poll.
    private func waitUntil(_ condition: () -> Bool) async throws {
        var tries = 0
        while !condition() && tries < 60 {
            try await Task.sleep(for: .milliseconds(50))
            tries += 1
        }
        try #require(condition())
    }
}
