import Foundation
import Testing
@testable import TaskCore

@MainActor
@Suite("TaskStore")
struct TaskStoreTests {
    let clock = TestClock(Fixture.now)

    @Test func addTrimsAndStamps() throws {
        let store = try Fixture.store(clock: clock)
        let item = try store.add(title: "  Buy milk ", notes: " 2 litres  ", priority: .high)
        #expect(item.title == "Buy milk")
        #expect(item.notes == "2 litres")
        #expect(item.priority == .high)
        #expect(item.createdAt == Fixture.now)
        #expect(item.id != nil)
        #expect(!item.isCompleted)
        #expect(store.task(id: item.id!) === item)
    }

    @Test func titleValidation() throws {
        let store = try Fixture.store(clock: clock)
        #expect(throws: TaskValidationError.emptyTitle) { try store.add(title: "   ") }
        #expect(throws: TaskValidationError.titleTooLong(max: 200)) { try store.add(title: String(repeating: "x", count: 201)) }
        let item = try store.add(title: "ok")
        #expect(throws: TaskValidationError.emptyTitle) { try store.update(item, title: "", notes: "", due: nil, priority: .low) }
        #expect(store.tasks(TaskQuery()).map(\.title) == ["ok"])
    }

    @Test func updateChangesFieldsAndTimestamp() throws {
        let store = try Fixture.store(clock: clock)
        let item = try store.add(title: "Draft")
        clock.now = Fixture.now.addingTimeInterval(60)
        let due = Fixture.date(2026, 9, 28, 9, 0)
        try store.update(item, title: "Final", notes: "send to Sam", due: due, priority: .low)
        #expect(item.title == "Final")
        #expect(item.notes == "send to Sam")
        #expect(item.dueDate == due)
        #expect(item.priority == .low)
        #expect(item.updatedAt == clock.now)
        #expect(item.createdAt == Fixture.now)
    }

    @Test func completeAndReopen() throws {
        let store = try Fixture.store(clock: clock)
        let item = try store.add(title: "Pay rent")
        try store.setCompleted(item, true)
        #expect(item.isCompleted)
        #expect(item.completedAt == Fixture.now)
        try store.setCompleted(item, false)
        #expect(!item.isCompleted)
        #expect(item.completedAt == nil)
    }

    @Test func deleteThenUndoThenRedo() throws {
        let store = try Fixture.store(clock: clock)
        let a = try store.add(title: "Keep")
        let b = try store.add(title: "Remove")
        try store.delete([b])
        #expect(store.tasks(TaskQuery()).map(\.title) == ["Keep"])
        #expect(store.undoManager?.undoActionName == "Delete Task")
        try store.undo()
        #expect(Set(store.tasks(TaskQuery()).compactMap(\.title)) == ["Keep", "Remove"])
        try store.redo()
        #expect(store.tasks(TaskQuery()).map(\.title) == ["Keep"])
        #expect(a.title == "Keep")
    }

    @Test func revisionChangesOnEverySave() throws {
        let store = try Fixture.store(clock: clock)
        let start = store.revision
        let item = try store.add(title: "One")
        try store.setCompleted(item, true)
        #expect(store.revision >= start + 2)
    }

    @Test func nextDueListsOpenDatedTasksSoonestFirst() throws {
        let store = try Fixture.store(clock: clock)
        try store.add(title: "later", due: Fixture.date(2026, 10, 2, 9, 0))
        try store.add(title: "soon", due: Fixture.date(2026, 9, 26, 15, 0))
        try store.add(title: "undated")
        let done = try store.add(title: "done", due: Fixture.date(2026, 9, 26, 11, 0))
        try store.setCompleted(done, true)
        #expect(store.nextDue(limit: 5).map(\.title) == ["soon", "later"])
        #expect(store.nextDue(limit: 1).map(\.title) == ["soon"])
    }
}
