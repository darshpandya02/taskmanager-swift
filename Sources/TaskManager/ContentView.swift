import SwiftUI
import TaskCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore

    init(model: AppModel) {
        self.model = model
        self.store = model.store
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: 200)
            Divider()
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                let rows = model.rows
                if rows.isEmpty {
                    ContentUnavailableView(
                        model.searchText.isEmpty ? "No tasks" : "No matches",
                        systemImage: model.searchText.isEmpty ? "checklist" : "magnifyingglass",
                        description: Text(model.searchText.isEmpty ? "Press \u{2318}N to add a task." : "Nothing matches \u{201C}\(model.searchText)\u{201D}.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TaskTableView(
                        rows: rows,
                        selection: $model.selection,
                        sort: $model.sort,
                        onOpen: model.edit,
                        onToggle: model.setCompleted,
                        onDelete: model.delete
                    )
                }
                StatusBar(text: model.status, storeDescription: model.storeDescription)
            }
            if let draft = model.draft {
                Divider()
                TaskEditorView(model: model)
                    .id(draft.token)
                    .frame(width: 320)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            }
            .navigationTitle(model.filter.title)
            .navigationSubtitle("\(model.count(.all)) open")
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search tasks")
        .toolbar {
            ToolbarItemGroup {
                Button { model.newTask() } label: { Label("New Task", systemImage: "plus") }
                    .help("New Task (\u{2318}N)")
                Button { if let id = model.selection.first { model.edit(id) } } label: { Label("Edit", systemImage: "square.and.pencil") }
                    .disabled(model.selection.count != 1)
                Button { model.delete(model.selection) } label: { Label("Delete", systemImage: "trash") }
                    .disabled(model.selection.isEmpty)
            }
        }
    }
}

/// Smart filters with counts. A plain view rather than a NavigationSplitView
/// sidebar, so the window can draw itself into an image (the sidebar's vibrancy
/// layer does not show up in NSView.cacheDisplay).
struct Sidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tasks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(SmartFilter.allCases) { f in
                let selected = model.filter == f
                Button {
                    model.filter = f
                } label: {
                    HStack {
                        Image(systemName: f.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(selected ? Color.white : Color.accentColor)
                        Text(f.title)
                        Spacer()
                        Text("\(model.count(f))")
                            .monospacedDigit()
                            .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
    }
}

struct StatusBar: View {
    var text: String?
    var storeDescription: String

    var body: some View {
        HStack {
            Text(text ?? " ")
                .lineLimit(1)
            Spacer()
            Text(storeDescription)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @FocusState private var titleFocused: Bool

    private var draft: Binding<TaskDraft> {
        Binding(get: { model.draft ?? TaskDraft() }, set: { model.draft = $0 })
    }

    var body: some View {
        Form {
            Section(draft.wrappedValue.isNew ? "New Task" : "Edit Task") {
                TextField("Title", text: draft.title)
                    .focused($titleFocused)
                    .onSubmit(model.saveDraft)
                if let error = draft.wrappedValue.error {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                TextField("Notes", text: draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Schedule") {
                Toggle("Due date", isOn: draft.hasDueDate)
                if draft.wrappedValue.hasDueDate {
                    DatePicker("Due", selection: draft.dueDate)
                }
                Picker("Priority", selection: draft.priority) {
                    ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                HStack {
                    Button("Cancel", role: .cancel) { model.draft = nil }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save", action: model.saveDraft)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { titleFocused = true }
    }
}

/// Contents of the menu bar extra: open-task count and the next due tasks.
struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @Environment(\.openWindow) private var openWindow

    init(model: AppModel) {
        self.model = model
        self.store = model.store
    }

    var body: some View {
        let _ = store.revision
        let next = store.nextDue(limit: 5)
        let text = DueDateText()
        Text("\(store.count(.all)) open, \(store.count(.overdue)) overdue")
        Divider()
        if next.isEmpty {
            Text("Nothing scheduled")
        }
        ForEach(next, id: \.objectID) { t in
            Button("\(t.title ?? "")  \u{00B7}  \(text.string(for: t.dueDate!, now: store.now))") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                model.edit(t.objectID)
            }
        }
        Divider()
        Button("New Task") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            model.newTask()
        }
        Button("Open TaskManager") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
