import CoreData
import Foundation

/// Where the store lives, and whether it is mirrored to iCloud.
public enum StoreKind: Sendable, Equatable {
    /// SQLite at /dev/null: real SQL behaviour, nothing kept. Used by tests and previews.
    case ephemeral
    /// A local SQLite file.
    case local(URL)
    /// A local SQLite file mirrored to a CloudKit private database.
    ///
    /// Not used by the shipped app. It needs a signed build with the iCloud
    /// (CloudKit) entitlement and a container registered to an Apple developer account.
    case cloudKit(containerIdentifier: String, url: URL)
}

public enum Persistence {
    /// ~/Library/Application Support/TaskManager/TaskManager.sqlite
    public static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TaskManager", isDirectory: true).appendingPathComponent("TaskManager.sqlite")
    }

    /// Builds the container without loading stores. `.cloudKit` returns an
    /// NSPersistentCloudKitContainer with the container options set; the other kinds
    /// return a plain NSPersistentContainer.
    public static func makeContainer(_ kind: StoreKind) -> NSPersistentContainer {
        let container: NSPersistentContainer
        let description: NSPersistentStoreDescription
        switch kind {
        case .ephemeral:
            container = NSPersistentContainer(name: "TaskManager", managedObjectModel: TaskModel.shared)
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        case .local(let url):
            container = NSPersistentContainer(name: "TaskManager", managedObjectModel: TaskModel.shared)
            description = NSPersistentStoreDescription(url: url)
        case .cloudKit(let identifier, let url):
            container = NSPersistentCloudKitContainer(name: "TaskManager", managedObjectModel: TaskModel.shared)
            description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
        }
        description.type = NSSQLiteStoreType
        // History tracking is on for local stores too, so switching a store to
        // CloudKit later does not need a different store setup.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        return container
    }

    /// Builds and loads the container. The view context gets an undo manager.
    @MainActor
    public static func load(_ kind: StoreKind) throws -> NSPersistentContainer {
        if case .local(let url) = kind {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let container = makeContainer(kind)
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // TaskStore opens one undo group per change, so turn off per-event grouping.
        let undo = UndoManager()
        undo.groupsByEvent = false
        container.viewContext.undoManager = undo
        return container
    }
}
