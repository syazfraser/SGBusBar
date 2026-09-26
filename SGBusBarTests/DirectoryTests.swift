import Foundation
import Testing
@testable import SGBusBar

@MainActor
@Suite("Finding stops and buses")
struct DirectoryTests {
    private let directory = BusStopDirectory(
        stops: [
            BusStop(code: "24009", description: "Joo Koon Int", road: "Joo Koon Circle"),
            BusStop(code: "23499", description: "Joo Koon Stn Exit A", road: "Joo Koon Circle"),
            BusStop(code: "43009", description: "Bt Batok Int", road: "Bt Batok Ctrl"),
            BusStop(code: "44009", description: "Tengah Int", road: "Tengah Blvd"),
        ],
        routes: [
            ServiceRoute(serviceNo: "99", direction: 1, stopCodes: ["43009", "24009"], isLoop: false),
            ServiceRoute(serviceNo: "253", direction: 1, stopCodes: ["24009", "23499"], isLoop: true),
            ServiceRoute(serviceNo: "992", direction: 1, stopCodes: ["43009", "44009"], isLoop: false),
        ]
    )

    @Test("Stop search by name puts names that start with the query first")
    func stopByName() {
        #expect(directory.search("joo koon").map(\.code) == ["24009", "23499"])
        #expect(directory.search("tengah blvd").map(\.code) == ["44009"])
    }

    @Test("Stop search by code matches the start of the code")
    func stopByCode() {
        #expect(directory.search("240").map(\.code) == ["24009"])
        #expect(directory.search("   ").isEmpty)
    }

    @Test("Bus search by number puts an exact match first")
    func busByNumber() {
        #expect(directory.searchRoutes("99").map(\.serviceNo) == ["99", "992"])
    }

    @Test("Bus search by where it goes")
    func busByPlace() {
        #expect(directory.searchRoutes("tengah").map(\.serviceNo) == ["992"])
    }

    @Test("Directions are named by where they end, or where a loop starts")
    func routeTitles() {
        let loop = directory.routes.first { $0.serviceNo == "253" }!
        let oneWay = directory.routes.first { $0.serviceNo == "992" }!
        #expect(directory.title(of: loop) == "Loop from Joo Koon Int")
        #expect(directory.title(of: oneWay) == "To Tengah Int")
        #expect(directory.subtitle(of: oneWay) == "From Bt Batok Int · 2 stops")
    }
}
