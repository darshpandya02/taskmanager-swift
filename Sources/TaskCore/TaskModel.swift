import CoreData

/// The Core Data model, built in code.
///
/// Every attribute is optional or has a default and there are no unique
/// constraints, which is what NSPersistentCloudKitContainer requires, so the same
/// model can be mirrored to CloudKit without a migration.
public enum TaskModel {
    public static let entityName = "TaskItem"

    /// One shared instance: Core Data warns if several models claim the same class.
    /// The model is never mutated after it is built, so sharing it is safe.
    nonisolated(unsafe) public static let shared: NSManagedObjectModel = make()

    static func make() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(TaskItem.self)

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            return a
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("notes", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("dueDate", .dateAttributeType),
            attribute("priorityValue", .integer16AttributeType, optional: false, defaultValue: Priority.medium.rawValue),
            attribute("isCompleted", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("completedAt", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]

        let byDue = NSFetchIndexDescription(name: "byCompletionAndDue", elements: [
            NSFetchIndexElementDescription(property: entity.propertiesByName["isCompleted"]!, collationType: .binary),
            NSFetchIndexElementDescription(property: entity.propertiesByName["dueDate"]!, collationType: .binary),
        ])
        entity.indexes = [byDue]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
