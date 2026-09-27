// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TaskManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TaskManager", targets: ["TaskManager"]),
        .library(name: "TaskCore", targets: ["TaskCore"]),
    ],
    targets: [
        // Core Data model, persistence and task logic. No UI.
        .target(name: "TaskCore"),
        // SwiftUI app with AppKit pieces (NSTableView list, menu bar extra, open/save panels).
        .executableTarget(name: "TaskManager", dependencies: ["TaskCore"]),
        .testTarget(name: "TaskCoreTests", dependencies: ["TaskCore"]),
    ]
)
