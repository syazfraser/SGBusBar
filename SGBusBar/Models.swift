import AppKit
import SwiftUI

/// A service at a stop. The stop's name (official or nickname) lives in ArrivalStore, shared by every bus there.
struct SavedBus: Codable, Identifiable, Hashable {
    var id = UUID()
    var stopCode: String   // "83139"; a string because some codes start with 0
    var serviceNo: String  // "992"; a string because some services have letters (243W)
    var walkMinutes = 0    // shifts the colour bands
}

enum Load: String {
    case seats = "SEA"
    case standing = "SDA"
    case limited = "LSD"

    var title: String {
        switch self {
        case .seats: "Seats"
        case .standing: "Standing"
        case .limited: "Limited"
        }
    }

    /// For tooltips.
    var detail: String {
        switch self {
        case .seats: "Seats available"
        case .standing: "Standing room"
        case .limited: "Limited standing"
        }
    }

    var color: Color {
        switch self {
        case .seats: .green
        case .standing: .orange
        case .limited: .red
        }
    }
}

enum BusType: String {
    case single = "SD"
    case double = "DD"
    case bendy = "BD"

    var title: String {
        switch self {
        case .single: "Single deck"
        case .double: "Double deck"
        case .bendy: "Bendy bus"
        }
    }
}

struct Arrival: Hashable {
    let eta: Date
    let load: Load?
    let type: BusType?
    let monitored: Bool   // false = scheduled estimate, not GPS-tracked
    let wheelchair: Bool
}

struct BusStop: Codable, Identifiable, Hashable {
    let code: String
    let description: String  // "Joo Koon Int"
    let road: String         // "Joo Koon Circle"

    var id: String { code }
}

/// One direction of a service and its stops in order, from LTA's route list.
struct ServiceRoute: Codable, Hashable, Identifiable {
    let serviceNo: String
    let direction: Int
    /// In the order the bus calls at them, each stop once.
    let stopCodes: [String]
    /// Starts and ends at the same interchange.
    let isLoop: Bool

    var id: String { "\(serviceNo)-\(direction)" }
}

/// A service that calls at a stop, from LTA's route list, with when it runs there.
struct ServiceAtStop: Codable, Hashable {
    let serviceNo: String
    let weekday: ServiceHours?
    let saturday: ServiceHours?
    let sunday: ServiceHours?

    /// Today's first and last bus at this stop; nil if it doesn't run today.
    func hours(on date: Date = Date()) -> ServiceHours? {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: sunday
        case 7: saturday
        default: weekday
        }
    }

    /// Whether the timetable has this service calling here at `date`, give or take `marginMinutes`.
    /// Last buses after midnight belong to the previous day's timetable, so that's checked too.
    func isInOperation(at date: Date = Date(), marginMinutes: Int = 0) -> Bool {
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let today = hours(on: date), today.covers(minute: minute, margin: marginMinutes) { return true }
        if let yesterday = hours(on: date.addingTimeInterval(-24 * 60 * 60)),
           yesterday.covers(minute: minute + 24 * 60, margin: marginMinutes) { return true }
        return false
    }

    /// For a service that doesn't run today: "Weekdays only · 6:30 AM – 8:30 AM".
    var otherDaysText: String? {
        let days = [("weekdays", weekday), ("Saturdays", saturday), ("Sundays", sunday)].filter { $0.1 != nil }
        guard let hours = days.first?.1 else { return nil }
        let names = days.map(\.0)
        let list = names.count == 1 ? "\(names[0]) only" : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(list.prefix(1).uppercased() + list.dropFirst()) · \(hours.text)"
    }
}

/// First and last bus as LTA writes them, "0548" and "0014" (after midnight).
struct ServiceHours: Codable, Hashable {
    let first: String
    let last: String

    /// "5:48 am – 12:14 am"
    var text: String {
        "\(Self.format(first)) – \(Self.format(last))"
    }

    /// Minutes since midnight at the start of the day; a last bus after midnight counts past 24:00.
    func covers(minute: Int, margin: Int) -> Bool {
        guard let start = Self.minutes(first), var end = Self.minutes(last) else { return true }
        if end < start { end += 24 * 60 }
        return minute >= start - margin && minute <= end + margin
    }

    private static func minutes(_ hhmm: String) -> Int? {
        guard hhmm.count == 4, let hour = Int(hhmm.prefix(2)), let minute = Int(hhmm.suffix(2)) else { return nil }
        return hour * 60 + minute
    }

    private static func format(_ hhmm: String) -> String {
        guard hhmm.count == 4, let hour = Int(hhmm.prefix(2)), let minute = Int(hhmm.suffix(2)),
              let date = Calendar.current.date(from: DateComponents(hour: hour % 24, minute: minute))
        else { return hhmm }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// How many arrival times the menu bar shows: none (just the icon), 1, 2 or 3.
/// The popup always shows 3. Raw values are what's saved, so keep them as they are.
enum MenuBarFormat: String, CaseIterable, Identifiable {
    case iconOnly
    case nextOnly
    case nextAndSecond
    case nextThree

    var id: Self { self }

    var title: String {
        switch self {
        case .iconOnly: "None"
        case .nextOnly: "1 bus"
        case .nextAndSecond: "2 buses"
        case .nextThree: "3 buses"
        }
    }

    /// How many arrival times the menu bar shows.
    var count: Int {
        switch self {
        case .nextOnly: 1
        case .nextAndSecond: 2
        case .nextThree: 3
        case .iconOnly: 0
        }
    }
}

/// In the order macOS shows them: Light, Dark, then Auto (here, System).
enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Match your Mac"
        case .light: "Always light"
        case .dark: "Always dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// For the popup and Settings window. nil follows macOS. The menu bar always follows macOS.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// What's behind the popup's cards.
enum PopupBackground: String, CaseIterable, Identifiable {
    /// A near-solid light or dark surface, so the theme looks the same over any wallpaper.
    case frosted
    /// Plain Liquid Glass; your wallpaper shows through.
    case clear

    var id: Self { self }

    var title: String {
        switch self {
        case .frosted: "Frosted"
        case .clear: "Clear glass"
        }
    }
}

/// How soon you need to leave, from the minutes to spare after walking to the stop.
enum Urgency {
    case miss         // under 1 min spare
    case leaveNow     // 1–4 min
    case comfortable  // 5–14 min
    case relaxed      // 15+ min
    case stale        // data too old to trust

    init(minutesAway: Int, walkMinutes: Int) {
        switch minutesAway - walkMinutes {
        case ..<1: self = .miss
        case 1...4: self = .leaveNow
        case 5...14: self = .comfortable
        default: self = .relaxed
        }
    }

    /// For the menu bar. nil means the default text colour.
    var nsColor: NSColor? {
        switch self {
        case .miss: .systemRed
        case .leaveNow: .systemOrange
        case .comfortable: .systemGreen
        case .relaxed: nil
        case .stale: .secondaryLabelColor
        }
    }

    /// A word for it, used on the menu bar bus's card and in the colour legend.
    var title: String {
        switch self {
        case .miss: "Hurry"
        case .leaveNow: "Leave now"
        case .comfortable: "Leave soon"
        case .relaxed: "No rush"
        case .stale: "Not live"
        }
    }

    /// Capsule fill for times in the popup, used with white text. Deep enough for at least
    /// 4.5:1 contrast (red 5.4, orange 4.8, green 5.1) in light and dark mode. nil = no capsule.
    var chipColor: Color? {
        switch self {
        case .miss: Color(hex: 0xD70015)
        case .leaveNow: Color(hex: 0xB35900)
        case .comfortable: Color(hex: 0x1F7F36)
        case .relaxed, .stale: nil
        }
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// One arrival as it should be shown right now.
struct TimeDisplay {
    let minutes: Int
    let monitored: Bool
    let urgency: Urgency

    /// "3m", "Arr", "~5m"
    var short: String { prefix + (minutes < 1 ? "Arr" : "\(minutes)m") }

    /// "3 min", "Arr", "~5 min"
    var long: String { prefix + (minutes < 1 ? "Arr" : "\(minutes) min") }

    /// "~" marks a scheduled estimate; "Arr" doesn't need it.
    private var prefix: String { monitored || minutes < 1 ? "" : "~" }
}
