import CoreData
import Foundation
import Testing
@testable import TaskCore

@Suite("Core Data model")
struct ModelTests {
    @Test func modelHasTheTaskEntity() throws {
        let entity = try #require(TaskModel.shared.entitiesByName["TaskItem"])
        #expect(entity.managedObjectClassName == NSStringFromClass(TaskItem.self))
        #expect(Set(entity.attributesByName.keys) == [
            "id", "title", "notes", "dueDate", "priorityValue", "isCompleted", "completedAt", "createdAt", "updatedAt",
        ])
    }

    /// NSPersistentCloudKitContainer rejects models with unique constraints or
    /// required attributes that have no default value.
    @Test func modelMeetsCloudKitRules() {
        for entity in TaskModel.shared.entities {
            #expect(entity.uniquenessConstraints.isEmpty)
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name)")
            }
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship != nil)
            }
        }
    }

    @Test func cloudKitKindBuildsCloudKitContainerWithoutLoading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ck-\(UUID()).sqlite")
        let container = Persistence.makeContainer(.cloudKit(containerIdentifier: "iCloud.com.darshpandya.TaskManager", url: url))
        #expect(container is NSPersistentCloudKitContainer)
        let description = try #require(container.persistentStoreDescriptions.first)
        #expect(description.cloudKitContainerOptions?.containerIdentifier == "iCloud.com.darshpandya.TaskManager")
        #expect(description.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
        #expect(container.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    @Test func localKindIsPlainContainerWithHistoryTracking() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-\(UUID()).sqlite")
        let container = Persistence.makeContainer(.local(url))
        #expect(!(container is NSPersistentCloudKitContainer))
        let description = try #require(container.persistentStoreDescriptions.first)
        #expect(description.cloudKitContainerOptions == nil)
        #expect(description.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
    }

    @MainActor
    @Test func localStorePersistsAcrossReloads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tm-\(UUID())", isDirectory: true)
        let url = dir.appendingPathComponent("TaskManager.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let store = TaskStore(container: try Persistence.load(.local(url)))
            try store.add(title: "Survives a restart", priority: .high)
        }
        let reopened = TaskStore(container: try Persistence.load(.local(url)))
        let tasks = reopened.tasks(TaskQuery())
        #expect(tasks.map(\.title) == ["Survives a restart"])
        #expect(tasks.first?.priority == .high)
    }
}
