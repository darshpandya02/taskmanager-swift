import CoreData
import Foundation

/// The sidebar filters.
public enum SmartFilter: String, CaseIterable, Identifiable, Sendable {
    case all, today, upcoming, overdue, completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .overdue: "Overdue"
        case .completed: "Completed"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .overdue: "exclamationmark.circle"
        case .completed: "checkmark.circle"
        }
    }

    /// Predicate for this filter, relative to `now` in `calendar`'s time zone.
    /// "Today" is open tasks due any time today, including earlier today.
    public func predicate(now: Date, calendar: Calendar) -> NSPredicate? {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        switch self {
        case .all:
            return nil
        case .today:
            return NSPredicate(format: "isCompleted == NO AND dueDate >= %@ AND dueDate < %@",
                               startOfToday as NSDate, startOfTomorrow as NSDate)
        case .upcoming:
            return NSPredicate(format: "isCompleted == NO AND dueDate >= %@", startOfTomorrow as NSDate)
        case .overdue:
            return NSPredicate(format: "isCompleted == NO AND dueDate < %@", now as NSDate)
        case .completed:
            return NSPredicate(format: "isCompleted == YES")
        }
    }
}

public enum TaskSortKey: String, CaseIterable, Sendable {
    case dueDate, priority, title, created
}

public struct TaskSort: Equatable, Sendable {
    public var key: TaskSortKey
    public var ascending: Bool

    public init(key: TaskSortKey = .dueDate, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// Open tasks always come before completed ones. Within each group, tasks
    /// without a due date sort after dated ones whichever way the column is sorted.
    public func areInIncreasingOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        switch key {
        case .dueDate:
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return ascending ? x < y : x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
        case .priority:
            if a.priority != b.priority { return ascending ? a.priority < b.priority : a.priority > b.priority }
        case .title:
            let r = (a.title ?? "").localizedStandardCompare(b.title ?? "")
            if r != .orderedSame { return ascending ? r == .orderedAscending : r == .orderedDescending }
        case .created:
            break
        }
        let ca = a.createdAt ?? .distantPast, cb = b.createdAt ?? .distantPast
        return key == .created && !ascending ? ca > cb : ca < cb
    }
}

public struct TaskQuery: Equatable, Sendable {
    public var filter: SmartFilter
    public var searchText: String
    public var sort: TaskSort

    public init(filter: SmartFilter = .all, searchText: String = "", sort: TaskSort = TaskSort()) {
        self.filter = filter
        self.searchText = searchText
        self.sort = sort
    }

    public func predicate(now: Date, calendar: Calendar) -> NSPredicate? {
        var parts: [NSPredicate] = []
        if let p = filter.predicate(now: now, calendar: calendar) { parts.append(p) }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            parts.append(NSPredicate(format: "title CONTAINS[cd] %@ OR notes CONTAINS[cd] %@", text, text))
        }
        switch parts.count {
        case 0: return nil
        case 1: return parts[0]
        default: return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        }
    }
}
