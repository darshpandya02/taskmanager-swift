import Foundation

public enum TaskBackupError: Error, Equatable, LocalizedError {
    case notABackup
    case unsupportedVersion(Int)
    case invalidRecord(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup: "This file is not a TaskManager backup."
        case .unsupportedVersion(let v): "Backup version \(v) is newer than this app supports."
        case .invalidRecord(let why): "The backup has an invalid task: \(why)."
        }
    }
}

/// Versioned JSON backup format. The same shape as the Android TaskMaster backup
/// apart from field names, so it is easy to read by eye.
public enum TaskBackup {
    public static let format = "taskmanager-backup"
    public static let version = 1

    public struct Record: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var dueDate: Date?
        public var priority: Int16
        public var isCompleted: Bool
        public var completedAt: Date?
        public var createdAt: Date?
        public var updatedAt: Date?

        public init(id: UUID, title: String, notes: String = "", dueDate: Date? = nil, priority: Int16 = 1,
                    isCompleted: Bool = false, completedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
            self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate; self.priority = priority
            self.isCompleted = isCompleted; self.completedAt = completedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
        }

        @MainActor init(_ item: TaskItem) {
            self.init(id: item.id ?? UUID(), title: item.title ?? "", notes: item.notes ?? "", dueDate: item.dueDate,
                      priority: item.priorityValue, isCompleted: item.isCompleted, completedAt: item.completedAt,
                      createdAt: item.createdAt, updatedAt: item.updatedAt)
        }
    }

    struct File: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var tasks: [Record]
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func encode(_ records: [Record], exportedAt: Date) throws -> Data {
        try encoder().encode(File(format: format, version: version, exportedAt: exportedAt, tasks: records))
    }

    public static func decode(_ data: Data) throws -> [Record] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let file: File
        do { file = try d.decode(File.self, from: data) } catch { throw TaskBackupError.notABackup }
        guard file.format == format else { throw TaskBackupError.notABackup }
        guard file.version <= version else { throw TaskBackupError.unsupportedVersion(file.version) }
        var seen = Set<UUID>()
        for r in file.tasks {
            if r.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw TaskBackupError.invalidRecord("empty title") }
            if !seen.insert(r.id).inserted { throw TaskBackupError.invalidRecord("duplicate id \(r.id)") }
        }
        return file.tasks
    }
}
