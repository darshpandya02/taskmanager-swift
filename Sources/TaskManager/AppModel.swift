import AppKit
import CoreData
import SwiftUI
import TaskCore

/// A value snapshot of a task for the table, so AppKit never holds managed objects.
struct TaskRow: Equatable, Identifiable {
    let id: NSManagedObjectID
    let title: String
    let notes: String
    let dueText: String
    let isOverdue: Bool
    let priority: Priority
    let isCompleted: Bool
}

/// The editor's working copy. Nothing is written until Save.
struct TaskDraft: Equatable {
    /// New for every draft, so the editor view is rebuilt instead of reused.
    var token = UUID()
    var objectID: NSManagedObjectID?
    var title = ""
    var notes = ""
    var hasDueDate = false
    var dueDate = Date()
    var priority: Priority = .medium
    var error: String?

    var isNew: Bool { objectID == nil }
}

@MainActor
final class AppModel: ObservableObject {
    let store: TaskStore
    let storeDescription: String

    @Published var filter: SmartFilter = .all
    @Published var searchText = ""
    @Published var sort = TaskSort()
    @Published var selection: Set<NSManagedObjectID> = []
    @Published var draft: TaskDraft?
    @Published var status: String?

    private let dueText = DueDateText()

    init(store: TaskStore, storeDescription: String) {
        self.store = store
        self.storeDescription = storeDescription
    }

    var query: TaskQuery { TaskQuery(filter: filter, searchText: searchText, sort: sort) }

    var rows: [TaskRow] {
        _ = store.revision
        let now = store.now
        return store.tasks(query).map { t in
            TaskRow(id: t.objectID, title: t.title ?? "", notes: t.notes ?? "",
                    dueText: t.dueDate.map { dueText.string(for: $0, now: now) } ?? "",
                    isOverdue: t.isOverdue(at: now), priority: t.priority, isCompleted: t.isCompleted)
        }
    }

    func count(_ f: SmartFilter) -> Int {
        _ = store.revision
        return store.count(f)
    }

    private func item(_ id: NSManagedObjectID) -> TaskItem? {
        try? store.context.existingObject(with: id) as? TaskItem
    }

    // MARK: Editing

    func newTask() {
        var d = TaskDraft()
        d.dueDate = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
        draft = d
    }

    func edit(_ id: NSManagedObjectID) {
        guard let t = item(id) else { return }
        draft = TaskDraft(objectID: id, title: t.title ?? "", notes: t.notes ?? "", hasDueDate: t.dueDate != nil,
                          dueDate: t.dueDate ?? Date(), priority: t.priority)
        selection = [id]
    }

    func saveDraft() {
        guard var d = draft else { return }
        do {
            let due = d.hasDueDate ? d.dueDate : nil
            if let id = d.objectID, let t = item(id) {
                try store.update(t, title: d.title, notes: d.notes, due: due, priority: d.priority)
                status = "Saved \u{201C}\(t.title ?? "")\u{201D}"
            } else {
                let t = try store.add(title: d.title, notes: d.notes, due: due, priority: d.priority)
                selection = [t.objectID]
                status = "Added \u{201C}\(t.title ?? "")\u{201D}"
            }
            draft = nil
        } catch {
            d.error = error.localizedDescription
            draft = d
        }
    }

    // MARK: Row actions

    func setCompleted(_ id: NSManagedObjectID, _ done: Bool) {
        guard let t = item(id) else { return }
        try? store.setCompleted(t, done)
        status = done ? "Completed \u{201C}\(t.title ?? "")\u{201D}" : "Reopened \u{201C}\(t.title ?? "")\u{201D}"
    }

    func delete(_ ids: Set<NSManagedObjectID>) {
        let items = ids.compactMap(item)
        guard !items.isEmpty else { return }
        let name = items.count == 1 ? "\u{201C}\(items[0].title ?? "")\u{201D}" : "\(items.count) tasks"
        try? store.delete(items)
        if let d = draft, let id = d.objectID, ids.contains(id) { draft = nil }
        selection.subtract(ids)
        status = "Deleted \(name). Undo with \u{2318}Z."
    }

    func undo() {
        let name = store.undoManager?.undoActionName ?? ""
        try? store.undo()
        if !name.isEmpty { status = "Undid \(name.lowercased())" }
    }

    func redo() { try? store.redo() }

    // MARK: Backup

    func export(to url: URL) {
        do {
            let data = try store.exportBackup()
            try data.write(to: url, options: .atomic)
            status = "Exported \(store.tasks(TaskQuery()).count) tasks to \(url.lastPathComponent)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func importBackup(from url: URL) {
        do {
            let n = try store.importBackup(Data(contentsOf: url))
            selection = []
            draft = nil
            status = "Imported \(n) tasks from \(url.lastPathComponent)"
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    func showExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "taskmanager-backup-\(Date().formatted(.iso8601.year().month().day())).json"
        if panel.runModal() == .OK, let url = panel.url { export(to: url) }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        let confirm = NSAlert()
        confirm.messageText = "Import a backup?"
        confirm.informativeText = "Importing replaces all current tasks with the tasks in the file."
        confirm.addButton(withTitle: "Choose File…")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        if panel.runModal() == .OK, let url = panel.url { importBackup(from: url) }
    }
}
