import Foundation
import Testing
@testable import TaskCore

@MainActor
@Suite("JSON backup")
struct BackupTests {
    @Test func exportThenImportRestoresEveryField() throws {
        let source = try Fixture.store()
        let a = try source.add(title: "Renew passport", notes: "photos first", due: Fixture.date(2026, 10, 1, 9, 0), priority: .high)
        let b = try source.add(title: "Water plants", priority: .low)
        try source.setCompleted(b, true)
        let data = try source.exportBackup()

        let target = try Fixture.store()
        try target.add(title: "Will be replaced")
        #expect(try target.importBackup(data) == 2)

        let restored = target.tasks(TaskQuery())
        #expect(restored.compactMap(\.title) == ["Renew passport", "Water plants"])
        let r = try #require(target.task(id: a.id!))
        #expect(r.notes == "photos first")
        #expect(r.dueDate == a.dueDate)
        #expect(r.priority == .high)
        #expect(target.task(id: b.id!)?.isCompleted == true)
        #expect(target.undoManager?.canUndo == false)
    }

    @Test func fileIsVersionedJSON() throws {
        let store = try Fixture.store()
        try store.add(title: "x")
        let text = String(decoding: try store.exportBackup(), as: UTF8.self)
        #expect(text.contains("\"format\" : \"taskmanager-backup\""))
        #expect(text.contains("\"version\" : 1"))
        #expect(text.contains("\"exportedAt\" : \"2026-09-26T14:00:00Z\""))
    }

    @Test func rejectsBadFiles() throws {
        #expect(throws: TaskBackupError.notABackup) { try TaskBackup.decode(Data("nope".utf8)) }
        #expect(throws: TaskBackupError.notABackup) {
            try TaskBackup.decode(Data(#"{"format":"other","version":1,"exportedAt":"2026-01-01T00:00:00Z","tasks":[]}"#.utf8))
        }
        #expect(throws: TaskBackupError.unsupportedVersion(2)) {
            try TaskBackup.decode(Data(#"{"format":"taskmanager-backup","version":2,"exportedAt":"2026-01-01T00:00:00Z","tasks":[]}"#.utf8))
        }
        let id = UUID().uuidString
        let dup = #"{"format":"taskmanager-backup","version":1,"exportedAt":"2026-01-01T00:00:00Z","tasks":["#
            + #"{"id":"\#(id)","title":"a","notes":"","priority":1,"isCompleted":false},"#
            + #"{"id":"\#(id)","title":"b","notes":"","priority":1,"isCompleted":false}]}"#
        #expect(throws: TaskBackupError.invalidRecord("duplicate id \(id)")) { try TaskBackup.decode(Data(dup.utf8)) }
    }

    @Test func failedImportLeavesTasksAlone() throws {
        let store = try Fixture.store()
        try store.add(title: "Safe")
        #expect(throws: TaskBackupError.notABackup) { try store.importBackup(Data("{}".utf8)) }
        #expect(store.tasks(TaskQuery()).compactMap(\.title) == ["Safe"])
    }
}

@Suite("Due date text")
struct DueDateTextTests {
    let text = DueDateText(calendar: Fixture.calendar, locale: Locale(identifier: "en_US_POSIX"))

    @Test func relativeDays() {
        #expect(text.string(for: Fixture.date(2026, 9, 26, 14, 5), now: Fixture.now) == "Today 14:05")
        #expect(text.string(for: Fixture.date(2026, 9, 27, 9, 0), now: Fixture.now) == "Tomorrow 09:00")
        #expect(text.string(for: Fixture.date(2026, 9, 25, 23, 59), now: Fixture.now) == "Yesterday 23:59")
    }

    @Test func otherDates() {
        #expect(text.string(for: Fixture.date(2026, 9, 30, 8, 30), now: Fixture.now) == "Wed, Sep 30 08:30")
        #expect(text.string(for: Fixture.date(2027, 1, 4, 12, 0), now: Fixture.now) == "Jan 4, 2027 12:00")
    }
}
