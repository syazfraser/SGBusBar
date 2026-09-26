import SwiftUI

// How an arrival is drawn: its time, and that particular bus's type and crowding.
// Each of a service's next 3 buses can differ (a DD, then an SD), so the details
// go under each time rather than once per row.

/// An arrival time. Coloured times sit in a solid capsule with white text,
/// which stays readable over glass whatever is behind it.
struct TimeChip: View {
    let time: TimeDisplay?

    var body: some View {
        let fill = time?.urgency.chipColor
        Text(time?.long ?? "—")
            .font(.callout.monospacedDigit().weight(time?.minutes ?? 99 < 1 ? .bold : .semibold))
            .foregroundStyle(textStyle(onFill: fill != nil))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                if let fill {
                    Capsule().fill(fill)
                }
            }
    }

    private func textStyle(onFill: Bool) -> AnyShapeStyle {
        if onFill { return AnyShapeStyle(.white) }
        return time?.urgency == .stale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }
}

/// "● DD · Seats" for one bus: a dot in the crowding colour, the bus type, how full it is.
struct BusInfo: View {
    let arrival: Arrival

    var body: some View {
        HStack(spacing: 3) {
            if let load = arrival.load {
                Circle()
                    .fill(load.color)
                    .frame(width: 5, height: 5)
            }
            Text([arrival.type?.rawValue, arrival.load?.title].compactMap { $0 }.joined(separator: " · "))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// One arrival as a column: the time, with that bus's details underneath.
struct ArrivalColumn: View {
    let time: TimeDisplay?
    let arrival: Arrival?

    static let width: CGFloat = 104

    var body: some View {
        VStack(spacing: 3) {
            TimeChip(time: time)
            if let arrival {
                BusInfo(arrival: arrival)
            } else {
                // Keeps rows the same height when there's no 3rd bus.
                Text(" ").font(.caption2)
            }
        }
        .frame(width: Self.width)
        .help(arrival.map(Self.tooltip) ?? "")
    }

    /// "Double deck · Seats available · Wheelchair accessible · Scheduled estimate"
    static func tooltip(for arrival: Arrival) -> String {
        [
            arrival.type?.title,
            arrival.load?.detail,
            arrival.wheelchair ? "Wheelchair accessible" : "Not wheelchair accessible",
            arrival.monitored ? "Live GPS position" : "Scheduled estimate, not GPS-tracked",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// A service's next 3 arrivals, side by side.
struct ArrivalColumns: View {
    let store: ArrivalStore
    let bus: SavedBus
    let arrivals: [Arrival]

    var body: some View {
        ForEach(0..<3, id: \.self) { index in
            let arrival = arrivals.indices.contains(index) ? arrivals[index] : nil
            ArrivalColumn(time: arrival.map { store.display($0, for: bus) }, arrival: arrival)
        }
    }
}
