import Foundation
import Testing
@testable import SGBusBar

@Suite("Timetables from LTA's route list")
struct TimetableTests {
    /// 26 Sep 2026 is a Saturday.
    private func date(day: Int, hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private let lateWeekdayService = ServiceAtStop(
        serviceNo: "992",
        weekday: ServiceHours(first: "0548", last: "0014"),  // last bus after midnight
        saturday: nil,
        sunday: nil
    )

    @Test("Hours that run past midnight")
    func pastMidnight() {
        let hours = ServiceHours(first: "0548", last: "0014")
        #expect(hours.covers(minute: 23 * 60 + 30, margin: 0))
        #expect(hours.covers(minute: 24 * 60 + 10, margin: 0))
        #expect(!hours.covers(minute: 3 * 60, margin: 0))
    }

    @Test("The margin allows for buses a little early or late")
    func margin() {
        let hours = ServiceHours(first: "0548", last: "2300")
        #expect(!hours.covers(minute: 5 * 60 + 20, margin: 0))
        #expect(hours.covers(minute: 5 * 60 + 20, margin: 30))
        #expect(hours.covers(minute: 23 * 60 + 25, margin: 30))
    }

    @Test("A weekday service's last bus just after midnight on Saturday still counts")
    func previousDaysLastBus() {
        #expect(lateWeekdayService.isInOperation(at: date(day: 26, hour: 0, minute: 10)))
        #expect(!lateWeekdayService.isInOperation(at: date(day: 26, hour: 3, minute: 0)))
        #expect(!lateWeekdayService.isInOperation(at: date(day: 26, hour: 12, minute: 0)))
        #expect(lateWeekdayService.isInOperation(at: date(day: 25, hour: 12, minute: 0)))  // Friday
    }

    @Test("Today's hours come from the right day's timetable")
    func dayOfWeek() {
        let service = ServiceAtStop(
            serviceNo: "10",
            weekday: ServiceHours(first: "0500", last: "2300"),
            saturday: ServiceHours(first: "0600", last: "2300"),
            sunday: ServiceHours(first: "0700", last: "2300")
        )
        #expect(service.hours(on: date(day: 25, hour: 9, minute: 0))?.first == "0500")  // Friday
        #expect(service.hours(on: date(day: 26, hour: 9, minute: 0))?.first == "0600")  // Saturday
        #expect(service.hours(on: date(day: 27, hour: 9, minute: 0))?.first == "0700")  // Sunday
    }

    @Test("Services that don't run today say when they do")
    func otherDays() {
        #expect(lateWeekdayService.otherDaysText?.hasPrefix("Weekdays only · ") == true)
        let weekendToo = ServiceAtStop(
            serviceNo: "10",
            weekday: ServiceHours(first: "0500", last: "2300"),
            saturday: ServiceHours(first: "0600", last: "2300"),
            sunday: nil
        )
        #expect(weekendToo.otherDaysText?.hasPrefix("Weekdays and Saturdays · ") == true)
        #expect(ServiceAtStop(serviceNo: "X", weekday: nil, saturday: nil, sunday: nil).otherDaysText == nil)
    }
}
