import Foundation

/// Converts between the API's "YYYY-MM-DD" and a Date, using the user's own
/// calendar. A UTC conversion would shift the day for anyone west of London.
nonisolated enum DueDate {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static var today: String { string(from: .now) }

    /// "Nov 1, 2026" for display.
    static func display(_ value: String) -> String {
        date(from: value)?.formatted(date: .abbreviated, time: .omitted) ?? value
    }
}
