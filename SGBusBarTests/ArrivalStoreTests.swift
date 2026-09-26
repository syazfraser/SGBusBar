import Foundation
import Testing
@testable import SGBusBar

/// Uses its own settings domain and no API key, so your real buses and Keychain are never touched.
@MainActor
@Suite("Saved buses and stops", .serialized)
struct ArrivalStoreTests {
    private static let suiteName = "SGBusBarTests"
    private let defaults: UserDefaults
    private let store: ArrivalStore

    private static let home = "43009"
    private static let work = "24009"

    init() {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults(suiteName: Self.suiteName)!
        store = Self.makeStore(defaults: defaults)
    }

    private static func makeStore(defaults: UserDefaults, servicesByStop: [String: [ServiceAtStop]] = [:]) -> ArrivalStore {
        let directory = BusStopDirectory(
            stops: [
                BusStop(code: home, description: "Bt Batok Int", road: "Bt Batok Ctrl"),
                BusStop(code: work, description: "Joo Koon Int", road: "Joo Koon Circle"),
            ],
            servicesByStop: servicesByStop
        )
        return ArrivalStore(defaults: defaults, directory: directory, apiKey: nil)
    }

    @Test("A new install starts with no buses")
    func startsEmpty() {
        #expect(store.buses.isEmpty)
        #expect(store.pinned == nil)
    }

    @Test("Saving a stop adds services, shares its walk time and name")
    func updateStopAdds() {
        store.add([SavedBus(stopCode: Self.home, serviceNo: "992")], pin: true)
        store.updateStop(Self.home, nickname: "Home", walkMinutes: 4, services: ["992", "991"])
        #expect(store.buses(atStop: Self.home).map(\.serviceNo) == ["992", "991"])
        #expect(store.buses(atStop: Self.home).allSatisfy { $0.walkMinutes == 4 })
        #expect(store.stopName(Self.home) == "Home")
    }

    @Test("Leaving a service out of the stop removes it")
    func updateStopRemoves() {
        store.add([SavedBus(stopCode: Self.home, serviceNo: "992"), SavedBus(stopCode: Self.home, serviceNo: "991")], pin: false)
        store.updateStop(Self.home, nickname: nil, walkMinutes: 0, services: ["991"])
        #expect(store.buses.map(\.serviceNo) == ["991"])
    }

    @Test("A blank nickname goes back to LTA's name")
    func blankNickname() {
        store.setNickname("   ", forStop: Self.home)
        #expect(store.nickname(forStop: Self.home) == nil)
        #expect(store.stopName(Self.home) == "Bt Batok Int")
    }

    @Test("Stops move up and down; buses reorder within their stop")
    func reordering() {
        store.add([
            SavedBus(stopCode: Self.home, serviceNo: "992"),
            SavedBus(stopCode: Self.home, serviceNo: "991"),
            SavedBus(stopCode: Self.work, serviceNo: "253"),
        ], pin: false)
        store.moveStop(Self.work, by: -1)
        #expect(store.stopCodes == [Self.work, Self.home])
        store.moveBuses(atStop: Self.home, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store.buses(atStop: Self.home).map(\.serviceNo) == ["991", "992"])
    }

    @Test("Removing the menu bar bus's stop moves the menu bar to the next bus")
    func removeStop() {
        store.add([SavedBus(stopCode: Self.home, serviceNo: "992"), SavedBus(stopCode: Self.work, serviceNo: "253")], pin: true)
        store.removeStop(Self.home)
        #expect(store.pinned?.serviceNo == "253")
    }

    @Test("Buses and names are saved between launches")
    func persistence() {
        store.add([SavedBus(stopCode: Self.home, serviceNo: "992", walkMinutes: 3)], pin: true)
        store.setNickname("Home", forStop: Self.home)
        let reopened = Self.makeStore(defaults: defaults)
        #expect(reopened.buses.map(\.serviceNo) == ["992"])
        #expect(reopened.stopName(Self.home) == "Home")
        #expect(reopened.pinned?.serviceNo == "992")
    }

    @Test("A saved refresh interval faster than LTA's 20 seconds is raised to 20")
    func pollingFloor() {
        defaults.set(10, forKey: "pollSeconds")
        #expect(Self.makeStore(defaults: defaults).pollSeconds == ArrivalStore.minimumPollSeconds)
    }

    @Test("No times: 'Not in operation' off-schedule, 'No estimate available' when it should be running")
    func noArrivalsMessages() {
        let allDay = ServiceHours(first: "0000", last: "2359")
        let services = [
            Self.home: [
                ServiceAtStop(serviceNo: "992", weekday: allDay, saturday: allDay, sunday: allDay),
                ServiceAtStop(serviceNo: "991", weekday: nil, saturday: nil, sunday: nil),
            ],
        ]
        let store = Self.makeStore(defaults: defaults, servicesByStop: services)
        #expect(store.noArrivalsMessage(for: SavedBus(stopCode: Self.home, serviceNo: "992")) == "No estimate available")
        #expect(store.noArrivalsMessage(for: SavedBus(stopCode: Self.home, serviceNo: "991")) == "Not in operation")
        #expect(store.noArrivalsMessage(for: SavedBus(stopCode: Self.home, serviceNo: "5")) == "Not running now")
    }

    @Test("Minutes round down, as LTA's guide asks")
    func roundingDown() {
        let bus = SavedBus(stopCode: Self.home, serviceNo: "992")
        let soon = Arrival(eta: store.now.addingTimeInterval(3 * 60 + 59), load: nil, type: nil, monitored: true, wheelchair: true)
        let now = Arrival(eta: store.now.addingTimeInterval(59), load: nil, type: nil, monitored: true, wheelchair: true)
        #expect(store.display(soon, for: bus).long == "3 min")
        #expect(store.display(now, for: bus).short == "Arr")
    }
}
