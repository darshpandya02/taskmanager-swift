import Foundation

/// "Today 14:05", "Tomorrow 09:00", "Wed, Sep 30 08:30", "Jan 4, 2027 12:00".
public struct DueDateText: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    public func string(for date: Date, now: Date) -> String {
        let time = format(date, "HH:mm")
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case -1: return "Yesterday \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return format(date, sameYear ? "EEE, MMM d" : "MMM d, yyyy") + " " + time
        }
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
