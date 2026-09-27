# TaskManager (macOS, Swift)

Rebuilt from scratch in 2026. The original 2022-23 project code was not preserved.

A task manager for macOS in Swift: create, edit, complete, search, sort and delete tasks
(with undo), smart filters with counts, a menu bar extra, and JSON backup and restore,
stored with Core Data.

- Demo (window screenshot sequence), screenshots and test results: https://project-demos-gamma.vercel.app/taskmanager-swift/
- App download: see [Releases](https://github.com/darshpandya02/taskmanager-swift/releases)

## Stack: this rebuild vs. the resume

| | Original project (per resume) | This rebuild |
|---|---|---|
| Platforms | iOS and macOS | **macOS only** (macOS 14+). The iOS target was not rebuilt: that needs full Xcode, and this machine has only the Command Line Tools |
| iOS UI | UIKit | Not rebuilt (no UIKit code in this repository) |
| macOS UI | AppKit, SwiftUI, Auto Layout | SwiftUI app shell, editor pane and sidebar; AppKit `NSTableView` task list hosted with `NSViewRepresentable`, cells laid out with Auto Layout constraints and self-sizing rows; `MenuBarExtra`; `NSSavePanel`/`NSOpenPanel` |
| Storage | Core Data | Core Data with a model built in code (`NSManagedObjectModel`, no `.xcdatamodeld`), SQLite store, undo via `UndoManager` |
| Sync | iCloud | **iCloud sync is not active.** The persistence layer can build an `NSPersistentCloudKitContainer` (see below), but the shipped app uses a local store |
| Build | Xcode | Swift Package Manager (`swift build`), packaged into an `.app` by `scripts/package.sh` |
| Tests | | Swift Testing, 27 tests |

### iCloud sync is not active

CloudKit needs a signed app with the iCloud (CloudKit) entitlement and a container
registered to an Apple developer account. This build has neither, so it stores tasks in
`~/Library/Application Support/TaskManager/TaskManager.sqlite` and the status bar says
"iCloud sync off".

What is in place for switching it on:

- `StoreKind.cloudKit(containerIdentifier:url:)` makes `Persistence.makeContainer` return an
  `NSPersistentCloudKitContainer` with `NSPersistentCloudKitContainerOptions` set.
- The model follows CloudKit's rules (every attribute optional or defaulted, no unique
  constraints), and a test checks this.
- Persistent history tracking and remote change notifications are on for the local store
  already, so the store options do not change when CloudKit is added.

To turn it on you would sign the app with a team, add the iCloud entitlement with a
container, and pass `.cloudKit(...)` in `TaskManagerApp.init`. None of that has been run.

## Features

- Smart filters with counts: All (open), Today, Upcoming, Overdue, Completed
- Search over title and notes (case and diacritic insensitive), combined with the filter
- Sortable columns (task, due, priority). Open tasks come before completed ones, and tasks
  without a due date stay last in either sort direction
- Editor pane: title (required, 200 characters max), notes, optional due date, priority
- Complete with the checkbox; delete with the Delete key or toolbar; Undo/Redo (⌘Z / ⇧⌘Z),
  one step per change
- File > Export Backup… / Import Backup… (versioned JSON; import replaces all tasks)
- Menu bar extra: open and overdue counts, the next five due tasks, New Task

## Layout

```
Sources/TaskCore/      Core Data model in code, Persistence (local / CloudKit-ready),
                       TaskStore, filters and sorting, JSON backup, due date text
Sources/TaskManager/   SwiftUI app, AppKit NSTableView list, menu bar extra, demo capture mode
Tests/TaskCoreTests/   Swift Testing suites
scripts/test.sh        swift test, with the Swift Testing paths the Command Line Tools need
scripts/package.sh     builds dist/TaskManager.app (arm64 + x86_64) and the zip
```

## Build, test, run

```sh
scripts/test.sh                        # swift test
swift run TaskManager                  # local store in Application Support
swift run TaskManager --in-memory      # throwaway store
scripts/package.sh                     # dist/TaskManager.app and dist/TaskManager-1.0.0-macOS.zip
```

Results on 2026-09-26 (MacBook Air, Apple M5, macOS 26.5.2, Swift 6.3.3 from the Command
Line Tools): 27 tests in 5 suites, all passed.

| Suite | Tests |
|---|---|
| Core Data model (entity, CloudKit rules, container kinds, reload from disk) | 5 |
| TaskStore (add, validation, edit, complete, delete with undo/redo, change tracking, next due) | 7 |
| Filters, search and sorting | 9 |
| JSON backup | 4 |
| Due date text | 2 |

Writing the undo test found a bug: `UndoManager` groups changes per run-loop event, so
several changes made in one event undid together. `TaskStore` now opens an undo group per
change.

## Installing the release build

The zip on the Releases page holds a universal (arm64 + x86_64) app that is ad-hoc signed
only: no Developer ID and no notarization. Gatekeeper blocks it the first time. On macOS 14,
right-click the app and choose Open, then Open again. On macOS 15 and later, try to open it
once, then go to System Settings > Privacy & Security and click Open Anyway.

## About the demo

This Mac does not give the terminal the screen recording permission (`screencapture` and
ffmpeg's avfoundation capture both fail), so the demo is not a screen recording. Running
`TaskManager --demo-capture DIR` performs a fixed sequence of actions through the same
`AppModel` methods the buttons call, against an in-memory store, and saves a PNG of the app
window after each step (`NSView.cacheDisplay`). ffmpeg joins the PNGs into a video. The
menu bar extra is not in the frames, because it is a separate system-owned menu.
