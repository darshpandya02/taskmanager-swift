import AppKit
import SwiftUI
import TaskCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs outside an .app bundle (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct TaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let options = LaunchOptions(CommandLine.arguments)
        let kind: StoreKind = options.ephemeral ? .ephemeral : .local(options.storeURL ?? Persistence.defaultStoreURL)
        let description: String
        switch kind {
        case .ephemeral: description = "In-memory store"
        case .local(let url): description = "Local store: \(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) \u{00B7} iCloud sync off"
        case .cloudKit: description = "iCloud"
        }
        let container: NSPersistentContainer
        do {
            container = try Persistence.load(kind)
        } catch {
            fatalError("Could not open the task store: \(error)")
        }
        let model = AppModel(store: TaskStore(container: container), storeDescription: description)
        _model = StateObject(wrappedValue: model)
        if let dir = options.demoCaptureDir {
            DemoRunner.start(model: model, outputDir: dir)
        }
    }

    var body: some Scene {
        Window("TaskManager", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 440)
        }
        .defaultSize(width: 1100, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { model.newTask() }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }.keyboardShortcut("z")
                Button("Redo") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Export Backup\u{2026}") { model.showExportPanel() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Backup\u{2026}") { model.showImportPanel() }.keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("TaskManager", systemImage: "checklist")
        }
    }
}

import CoreData

struct LaunchOptions {
    var ephemeral = false
    var storeURL: URL?
    var demoCaptureDir: URL?

    /// --in-memory, --store PATH, --demo-capture DIR (implies --in-memory)
    init(_ args: [String]) {
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--in-memory": ephemeral = true
            case "--store" where i + 1 < args.count: i += 1; storeURL = URL(fileURLWithPath: args[i])
            case "--demo-capture" where i + 1 < args.count:
                i += 1
                demoCaptureDir = URL(fileURLWithPath: args[i], isDirectory: true)
                ephemeral = true
            default: break
            }
            i += 1
        }
    }
}
