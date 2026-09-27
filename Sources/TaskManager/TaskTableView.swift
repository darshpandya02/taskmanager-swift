import AppKit
import CoreData
import SwiftUI
import TaskCore

/// The task list: an AppKit NSTableView hosted in SwiftUI. Cells are built in code
/// with Auto Layout constraints, and rows size themselves (usesAutomaticRowHeights).
struct TaskTableView: NSViewRepresentable {
    var rows: [TaskRow]
    @Binding var selection: Set<NSManagedObjectID>
    @Binding var sort: TaskSort
    var onOpen: (NSManagedObjectID) -> Void
    var onToggle: (NSManagedObjectID, Bool) -> Void
    var onDelete: (Set<NSManagedObjectID>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyTableView()
        table.style = .inset
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 8, height: 6)

        func column(_ id: String, _ title: String, width: CGFloat, min: CGFloat, sortKey: TaskSortKey?) -> NSTableColumn {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.minWidth = min
            if let sortKey { c.sortDescriptorPrototype = NSSortDescriptor(key: sortKey.rawValue, ascending: true) }
            return c
        }
        let done = column("done", "", width: 22, min: 22, sortKey: nil)
        done.maxWidth = 22
        table.addTableColumn(done)
        table.addTableColumn(column("title", "Task", width: 300, min: 160, sortKey: .title))
        table.addTableColumn(column("due", "Due", width: 200, min: 110, sortKey: .dueDate))
        table.addTableColumn(column("priority", "Priority", width: 80, min: 70, sortKey: .priority))
        table.sortDescriptors = [NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)]

        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.onDelete = { [weak coordinator = context.coordinator] in coordinator?.deleteSelected() }
        table.setAccessibilityIdentifier("taskTable")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let table = c.table else { return }
        if c.rows != rows {
            c.rows = rows
            c.applyingSelection = true
            table.reloadData()
            c.applyingSelection = false
        }
        let descriptor = NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)
        if table.sortDescriptors.first != descriptor {
            c.applyingSelection = true
            table.sortDescriptors = [descriptor]
            c.applyingSelection = false
        }
        let wanted = IndexSet(rows.indices.filter { selection.contains(rows[$0].id) })
        if table.selectedRowIndexes != wanted {
            c.applyingSelection = true
            table.selectRowIndexes(wanted, byExtendingSelection: false)
            c.applyingSelection = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: TaskTableView
        var rows: [TaskRow] = []
        weak var table: NSTableView?
        var applyingSelection = false

        init(_ parent: TaskTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, row < rows.count else { return nil }
            let r = rows[row]
            switch id {
            case "done":
                let cell = tableView.makeView(withIdentifier: .init("doneCell"), owner: nil) as? CheckCell ?? CheckCell()
                cell.configure(checked: r.isCompleted, title: r.title) { [weak self] checked in
                    self?.parent.onToggle(r.id, checked)
                }
                return cell
            case "title":
                let cell = tableView.makeView(withIdentifier: .init("titleCell"), owner: nil) as? TitleCell ?? TitleCell()
                cell.configure(r)
                return cell
            case "due":
                let cell = tableView.makeView(withIdentifier: .init("dueCell"), owner: nil) as? TextCell ?? TextCell(id: "dueCell")
                cell.set(r.isOverdue ? "\(r.dueText) (overdue)" : r.dueText,
                         color: r.isOverdue ? .systemRed : .secondaryLabelColor, completed: r.isCompleted)
                return cell
            default:
                let cell = tableView.makeView(withIdentifier: .init("priorityCell"), owner: nil) as? TextCell ?? TextCell(id: "priorityCell")
                cell.set(r.priority.label, color: r.priority.color, completed: r.isCompleted)
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !applyingSelection, let table else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !applyingSelection, let d = tableView.sortDescriptors.first, let key = d.key.flatMap(TaskSortKey.init(rawValue:)) else { return }
            parent.sort = TaskSort(key: key, ascending: d.ascending)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            if row >= 0, row < rows.count { parent.onOpen(rows[row].id) }
        }

        func deleteSelected() {
            guard let table else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
            if !ids.isEmpty { parent.onDelete(ids) }
        }
    }
}

/// Sends Delete / Forward Delete to the coordinator.
final class KeyTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
    }
}

extension Priority {
    var color: NSColor {
        switch self {
        case .high: .systemRed
        case .medium: .systemOrange
        case .low: .systemGreen
        }
    }
}

// MARK: Cells, laid out with Auto Layout anchors

final class CheckCell: NSTableCellView {
    private let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var onChange: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = .init("doneCell")
        box.translatesAutoresizingMaskIntoConstraints = false
        box.target = self
        box.action = #selector(toggled)
        addSubview(box)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: centerXAnchor),
            box.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(checked: Bool, title: String, onChange: @escaping (Bool) -> Void) {
        box.state = checked ? .on : .off
        box.setAccessibilityLabel("Mark \(title) done")
        self.onChange = onChange
    }

    @objc private func toggled() { onChange?(box.state == .on) }
}

final class TitleCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let notes = NSTextField(labelWithString: "")
    private let stack: NSStackView

    init() {
        stack = NSStackView(views: [title, notes])
        super.init(frame: .zero)
        identifier = .init("titleCell")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        notes.font = .systemFont(ofSize: 11)
        notes.textColor = .secondaryLabelColor
        notes.lineBreakMode = .byTruncatingTail
        [title, notes].forEach { $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ r: TaskRow) {
        let attrs: [NSAttributedString.Key: Any] = r.isCompleted
            ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor]
            : [.foregroundColor: NSColor.labelColor]
        title.attributedStringValue = NSAttributedString(string: r.title, attributes: attrs)
        notes.stringValue = r.notes
        notes.isHidden = r.notes.isEmpty
    }
}

final class TextCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(id: String) {
        super.init(frame: .zero)
        identifier = .init(id)
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(_ text: String, color: NSColor, completed: Bool) {
        label.stringValue = text
        label.textColor = completed ? .tertiaryLabelColor : color
    }
}
