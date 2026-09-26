import Foundation
import Testing
@testable import SGBusBar

@Suite("Colour bands and time labels")
struct ColourAndTimeTests {
    @Test("Bands follow the minutes to spare")
    func bands() {
        let cases: [(minutes: Int, walk: Int, expected: Urgency)] = [
            (0, 0, .miss), (1, 0, .leaveNow), (4, 0, .leaveNow),
            (5, 0, .comfortable), (14, 0, .comfortable), (15, 0, .relaxed),
        ]
        for c in cases {
            #expect(Urgency(minutesAway: c.minutes, walkMinutes: c.walk) == c.expected, "\(c.minutes) min away")
        }
    }

    @Test("The walk to the stop comes off the time to spare")
    func walkTime() {
        #expect(Urgency(minutesAway: 4, walkMinutes: 4) == .miss)
        #expect(Urgency(minutesAway: 8, walkMinutes: 4) == .leaveNow)
        #expect(Urgency(minutesAway: 9, walkMinutes: 4) == .comfortable)
        #expect(Urgency(minutesAway: 19, walkMinutes: 4) == .relaxed)
    }

    @Test("Labels: Arr under a minute, ~ for scheduled estimates")
    func labels() {
        #expect(TimeDisplay(minutes: 0, monitored: true, urgency: .miss).short == "Arr")
        #expect(TimeDisplay(minutes: 3, monitored: true, urgency: .leaveNow).short == "3m")
        #expect(TimeDisplay(minutes: 3, monitored: true, urgency: .leaveNow).long == "3 min")
        #expect(TimeDisplay(minutes: 5, monitored: false, urgency: .comfortable).long == "~5 min")
        // "~Arr" would add nothing.
        #expect(TimeDisplay(minutes: 0, monitored: false, urgency: .miss).short == "Arr")
    }

    @Test("Capsule colours exist only for the bands that need one")
    func chipColours() {
        #expect(Urgency.miss.chipColor != nil)
        #expect(Urgency.leaveNow.chipColor != nil)
        #expect(Urgency.comfortable.chipColor != nil)
        #expect(Urgency.relaxed.chipColor == nil)
        #expect(Urgency.stale.chipColor == nil)
    }

    @Test("Menu bar formats show 0 to 3 times")
    func menuBarFormats() {
        #expect(MenuBarFormat.allCases.map(\.count) == [0, 1, 2, 3])
    }
}
