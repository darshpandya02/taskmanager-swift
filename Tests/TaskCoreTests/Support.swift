import Foundation
@testable import TaskCore

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

enum Fixture {
    static let zone = TimeZone(identifier: "America/New_York")!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// 2026-09-26 10:00 in New York.
    static let now = date(2026, 9, 26, 10, 0)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @MainActor
    static func store(clock: TestClock = TestClock(now)) throws -> TaskStore {
        TaskStore(container: try Persistence.load(.ephemeral), calendar: calendar, clock: { clock.now })
    }
}
