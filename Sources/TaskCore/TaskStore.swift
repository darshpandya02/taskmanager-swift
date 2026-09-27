import Combine
import CoreData
import Foundation

public enum TaskValidationError: Error, Equatable, LocalizedError {
    case emptyTitle
    case titleTooLong(max: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "A task needs a title."
        case .titleTooLong(let max): "Titles can be at most \(max) characters."
        }
    }
}

/// The app's single entry point to the task data. All work happens on the view
/// context (main queue); every change is saved immediately and can be undone.
@MainActor
public final class TaskStore: ObservableObject {
    public static let maxTitleLength = 200

    public let container: NSPersistentContainer
    public var context: NSManagedObjectContext { container.viewContext }
    public let calendar: Calendar
    private let clock: () -> Date

    /// Bumped after every save, including saves from undo and from other contexts.
    @Published public private(set) var revision = 0

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    public init(container: NSPersistentContainer, calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.container = container
        self.calendar = calendar
        self.clock = clock
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: container.viewContext, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var now: Date { clock() }

    // MARK: Reading

    public func tasks(_ query: TaskQuery) -> [TaskItem] {
        let request = TaskItem.fetchRequest()
        request.predicate = query.predicate(now: clock(), calendar: calendar)
        let rows = (try? context.fetch(request)) ?? []
        return rows.sorted(by: query.sort.areInIncreasingOrder)
    }

    public func count(_ filter: SmartFilter) -> Int {
        let request = TaskItem.fetchRequest()
        request.predicate = filter == .all
            ? NSPredicate(format: "isCompleted == NO")
            : filter.predicate(now: clock(), calendar: calendar)
        return (try? context.count(for: request)) ?? 0
    }

    /// Open tasks with a due date, soonest first. Used by the menu bar extra.
    public func nextDue(limit: Int) -> [TaskItem] {
        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "isCompleted == NO AND dueDate != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    public func task(id: UUID) -> TaskItem? {
        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: Writing

    @discardableResult
    public func add(title: String, notes: String = "", due: Date? = nil, priority: Priority = .medium) throws -> TaskItem {
        let clean = try Self.validated(title)
        return try change("Add Task") {
            let item = TaskItem(context: context)
            let now = clock()
            item.title = clean
            item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            item.dueDate = due
            item.priority = priority
            item.createdAt = now
            item.updatedAt = now
            return item
        }
    }

    public func update(_ item: TaskItem, title: String, notes: String, due: Date?, priority: Priority) throws {
        let clean = try Self.validated(title)
        try change("Edit Task") {
            item.title = clean
            item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            item.dueDate = due
            item.priority = priority
            item.updatedAt = clock()
        }
    }

    public func setCompleted(_ item: TaskItem, _ completed: Bool) throws {
        guard item.isCompleted != completed else { return }
        try change(completed ? "Complete Task" : "Reopen Task") {
            item.isCompleted = completed
            item.completedAt = completed ? clock() : nil
            item.updatedAt = clock()
        }
    }

    public func delete(_ items: [TaskItem]) throws {
        guard !items.isEmpty else { return }
        try change(items.count == 1 ? "Delete Task" : "Delete Tasks") {
            items.forEach(context.delete)
        }
    }

    public var undoManager: UndoManager? { context.undoManager }

    public func undo() throws {
        guard let undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        try context.save()
    }

    public func redo() throws {
        guard let undoManager, undoManager.canRedo else { return }
        undoManager.redo()
        try context.save()
    }

    // MARK: Backup

    public func exportBackup() throws -> Data {
        let request = TaskItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try TaskBackup.encode(context.fetch(request).map(TaskBackup.Record.init), exportedAt: clock())
    }

    /// Replaces every task with the backup's records. Not undoable. Returns the number imported.
    @discardableResult
    public func importBackup(_ data: Data) throws -> Int {
        let records = try TaskBackup.decode(data)
        context.processPendingChanges()
        undoManager?.disableUndoRegistration()
        defer {
            context.processPendingChanges()
            undoManager?.enableUndoRegistration()
            undoManager?.removeAllActions()
        }
        let existing = try context.fetch(TaskItem.fetchRequest())
        existing.forEach(context.delete)
        for r in records {
            let item = TaskItem(context: context)
            item.id = r.id
            item.title = r.title
            item.notes = r.notes
            item.dueDate = r.dueDate
            item.priority = Priority(rawValue: r.priority) ?? .medium
            item.isCompleted = r.isCompleted
            item.completedAt = r.completedAt
            item.createdAt = r.createdAt
            item.updatedAt = r.updatedAt
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return records.count
    }

    // MARK: Helpers

    static func validated(_ title: String) throws -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw TaskValidationError.emptyTitle }
        if clean.count > maxTitleLength { throw TaskValidationError.titleTooLong(max: maxTitleLength) }
        return clean
    }

    /// Runs one user-visible change as its own undo step and saves it. Grouping is
    /// explicit rather than per run-loop event (see Persistence.load), so two changes
    /// made in the same event, or in a test, still undo one at a time.
    private func change<T>(_ actionName: String, _ body: () throws -> T) throws -> T {
        let undo = undoManager
        undo?.beginUndoGrouping()
        let result: T
        do {
            result = try body()
            context.processPendingChanges()
            undo?.setActionName(actionName)
        } catch {
            undo?.endUndoGrouping()
            context.rollback()
            throw error
        }
        undo?.endUndoGrouping()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return result
    }
}
