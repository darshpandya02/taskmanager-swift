import CoreData
import Foundation

public enum Priority: Int16, CaseIterable, Codable, Sendable, Comparable {
    case low = 0, medium = 1, high = 2

    public var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

/// A task row. The entity is described in code by `TaskModel`, so no .xcdatamodeld is needed.
@objc(TaskItem)
public final class TaskItem: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var notes: String?
    @NSManaged public var dueDate: Date?
    @NSManaged public var priorityValue: Int16
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(UUID(), forKey: "id")
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
    }

    public var priority: Priority {
        get { Priority(rawValue: priorityValue) ?? .medium }
        set { priorityValue = newValue.rawValue }
    }

    public func isOverdue(at now: Date) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < now
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TaskItem> {
        NSFetchRequest<TaskItem>(entityName: "TaskItem")
    }
}
