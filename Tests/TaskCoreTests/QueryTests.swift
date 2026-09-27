import Foundation
import Testing
@testable import TaskCore

@MainActor
@Suite("Filters, search and sorting")
struct QueryTests {
    /// now = Sat 2026-09-26 10:00 New York
    func seeded() throws -> TaskStore {
        let store = try Fixture.store()
        try store.add(title: "Overdue from yesterday", due: Fixture.date(2026, 9, 25, 17, 0), priority: .high)
        try store.add(title: "Earlier today", due: Fixture.date(2026, 9, 26, 8, 0))
        try store.add(title: "Later today", notes: "call the bank", due: Fixture.date(2026, 9, 26, 18, 0), priority: .low)
        try store.add(title: "Tomorrow morning", due: Fixture.date(2026, 9, 27, 9, 0))
        try store.add(title: "Next month", due: Fixture.date(2026, 10, 15, 12, 0), priority: .high)
        try store.add(title: "Someday")
        let done = try store.add(title: "Finished", due: Fixture.date(2026, 9, 26, 9, 0))
        try store.setCompleted(done, true)
        return store
    }

    func titles(_ store: TaskStore, _ q: TaskQuery) -> [String] { store.tasks(q).compactMap(\.title) }

    @Test func allSortsOpenByDueWithUndatedLastThenCompleted() throws {
        let store = try seeded()
        #expect(titles(store, TaskQuery()) == [
            "Overdue from yesterday", "Earlier today", "Later today", "Tomorrow morning", "Next month", "Someday", "Finished",
        ])
    }

    @Test func todayIncludesEarlierTodayButNotYesterdayOrCompleted() throws {
        #expect(titles(try seeded(), TaskQuery(filter: .today)) == ["Earlier today", "Later today"])
    }

    @Test func upcomingStartsTomorrow() throws {
        #expect(titles(try seeded(), TaskQuery(filter: .upcoming)) == ["Tomorrow morning", "Next month"])
    }

    @Test func overdueIsOpenAndPastDue() throws {
        #expect(titles(try seeded(), TaskQuery(filter: .overdue)) == ["Overdue from yesterday", "Earlier today"])
    }

    @Test func completedFilter() throws {
        #expect(titles(try seeded(), TaskQuery(filter: .completed)) == ["Finished"])
    }

    @Test func countsPerFilter() throws {
        let store = try seeded()
        #expect(store.count(.all) == 6) // open tasks
        #expect(store.count(.today) == 2)
        #expect(store.count(.upcoming) == 2)
        #expect(store.count(.overdue) == 2)
        #expect(store.count(.completed) == 1)
    }

    @Test func searchMatchesTitleAndNotesIgnoringCaseAndDiacritics() throws {
        let store = try seeded()
        #expect(titles(store, TaskQuery(searchText: "BANK")) == ["Later today"])
        #expect(titles(store, TaskQuery(searchText: "  month ")) == ["Next month"])
        try store.add(title: "Café visit")
        #expect(titles(store, TaskQuery(searchText: "cafe")) == ["Café visit"])
        #expect(titles(store, TaskQuery(filter: .completed, searchText: "month")).isEmpty)
    }

    @Test func sortByPriorityAndTitle() throws {
        let store = try seeded()
        let byPriority = titles(store, TaskQuery(filter: .upcoming, sort: TaskSort(key: .priority, ascending: false)))
        #expect(byPriority == ["Next month", "Tomorrow morning"])
        let byTitle = titles(store, TaskQuery(filter: .today, sort: TaskSort(key: .title, ascending: false)))
        #expect(byTitle == ["Later today", "Earlier today"])
    }

    @Test func descendingDueDateStillPutsUndatedLast() throws {
        let store = try seeded()
        let t = titles(store, TaskQuery(sort: TaskSort(key: .dueDate, ascending: false)))
        #expect(t.first == "Next month")
        #expect(t.suffix(2) == ["Someday", "Finished"])
    }
}
