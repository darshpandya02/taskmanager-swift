import AppKit
import SwiftUI
import TaskCore

/// `--demo-capture DIR`: runs a fixed sequence of actions against an in-memory
/// store and saves a PNG of the app window after each one, plus `frames.txt`
/// (an ffmpeg concat list with how long to show each frame).
///
/// The actions go through the same AppModel methods the buttons and the table
/// call; the frames are the window's own drawing (NSView.cacheDisplay), which
/// does not need the screen recording permission.
@MainActor
enum DemoRunner {
    static func start(model: AppModel, outputDir: URL) {
        Task { @MainActor in
            do {
                try await run(model, outputDir)
            } catch {
                FileHandle.standardError.write(Data("demo failed: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }

    private final class Recorder {
        let dir: URL
        var list = ""
        var n = 0
        init(dir: URL) { self.dir = dir }

        @MainActor func frame(_ hold: Double) async throws {
            try await Task.sleep(for: .milliseconds(400)) // let SwiftUI and AppKit lay out
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "" && $0.contentView != nil && $0.frame.width > 500 }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "demo", code: 1, userInfo: [NSLocalizedDescriptionKey: "no window to capture"])
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            // The window frame has transparent rounded corners; flatten onto the
            // window background colour so the video has no black corners.
            let flat = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flat)
            let rect = NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            n += 1
            let name = String(format: "frame-%03d.png", n)
            try flat.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
            list += "file '\(name)'\nduration \(hold)\n"
        }

        func finish() throws {
            // ffmpeg's concat demuxer ignores the last duration unless the last file is repeated.
            list += "file '\(String(format: "frame-%03d.png", n))'\n"
            try list.write(to: dir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static func run(_ model: AppModel, _ dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rec = Recorder(dir: dir)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: today)!
        }

        // Wait for the window.
        for _ in 0..<50 where !NSApp.windows.contains(where: { $0.isVisible && $0.frame.width > 500 }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        if let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
            w.setFrame(NSRect(x: 80, y: 80, width: 1100, height: 640), display: true)
        }
        try await rec.frame(2.0)

        // Create a task in the inspector, typing the title a few characters at a time.
        model.newTask()
        try await rec.frame(0.8)
        let title = "Submit expense report"
        var typed = ""
        for chunk in stride(from: 0, to: title.count, by: 4) {
            typed = String(title.prefix(chunk + 4))
            model.draft?.title = typed
            try await rec.frame(0.12)
        }
        model.draft?.notes = "September receipts"
        model.draft?.hasDueDate = true
        model.draft?.dueDate = cal.date(bySetting: .second, value: 0, of: Date().addingTimeInterval(45 * 60))!
        model.draft?.priority = .high
        try await rec.frame(1.5)
        model.saveDraft()
        try await rec.frame(1.2)

        // A blank title is refused.
        model.newTask()
        model.saveDraft()
        try await rec.frame(1.8)

        let more: [(String, String, Date?, Priority)] = [
            ("Buy groceries", "milk, eggs, bread", at(1, 18), .medium),
            ("Call the dentist", "", nil, .low),
            ("Renew library books", "two are overdue", at(-1, 12), .medium),
            ("Plan weekend trip", "check train times", at(6, 10), .low),
        ]
        for (t, notes, due, p) in more {
            model.draft = TaskDraft(title: t, notes: notes, hasDueDate: due != nil, dueDate: due ?? Date(), priority: p)
            try await rec.frame(0.9)
            model.saveDraft()
            try await rec.frame(0.7)
        }
        model.selection = []
        try await rec.frame(2.0)

        // Edit.
        let groceries = model.rows.first { $0.title == "Buy groceries" }!.id
        model.edit(groceries)
        try await rec.frame(1.0)
        model.draft?.title = "Buy groceries for the week"
        try await rec.frame(1.0)
        model.saveDraft()
        try await rec.frame(1.5)

        // Complete.
        let dentist = model.rows.first { $0.title == "Call the dentist" }!.id
        model.selection = [dentist]
        model.setCompleted(dentist, true)
        try await rec.frame(1.8)

        // Sidebar filters.
        for f in [SmartFilter.today, .upcoming, .overdue, .completed, .all] {
            model.filter = f
            try await rec.frame(1.3)
        }

        // Sort by priority, then back to due date.
        model.sort = TaskSort(key: .priority, ascending: false)
        try await rec.frame(1.6)
        model.sort = TaskSort()

        // Search.
        for s in ["t", "tr", "tri", "trip"] {
            model.searchText = s
            try await rec.frame(0.3)
        }
        try await rec.frame(1.2)
        model.searchText = ""
        try await rec.frame(0.8)

        // Delete, then undo.
        let library = model.rows.first { $0.title == "Renew library books" }!.id
        model.selection = [library]
        try await rec.frame(0.9)
        model.delete([library])
        try await rec.frame(1.6)
        model.undo()
        try await rec.frame(1.6)

        // Export, delete everything, import.
        let backup = dir.appendingPathComponent("taskmanager-backup.json")
        model.export(to: backup)
        try await rec.frame(1.8)
        model.delete(Set(model.rows.map(\.id)))
        try await rec.frame(1.6)
        model.importBackup(from: backup)
        try await rec.frame(2.5)

        try rec.finish()
    }
}
