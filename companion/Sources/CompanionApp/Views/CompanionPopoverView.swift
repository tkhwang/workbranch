import SwiftUI
import CompanionCore

struct CompanionPopoverView: View {
    @ObservedObject var store: StateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.menuState.sections) { section in
                        sectionView(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actions
            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 520, height: 600)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Workbranch")
                .font(.headline)
            Text(store.menuState.title)
                .foregroundStyle(.secondary)
            Spacer()
            Button("↻") { store.refreshAll() }
                .help("Refresh")
            Button("⏻") { store.quit() }
                .help("Quit")
        }
    }

    private func sectionView(_ section: MenuSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(section.rows) { row in
                RowView(row: row, store: store)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Open config") { store.openConfig() }
            Spacer()
            Button("Refresh now") { store.refreshAll() }
            Button("Quit") { store.quit() }
        }
    }
}

private struct RowView: View {
    let row: MenuRow
    @ObservedObject var store: StateStore
    @State private var editing = false
    @State private var memoText = ""
    @State private var expanded: Bool

    init(row: MenuRow, store: StateStore) {
        self.row = row
        self.store = store
        _expanded = State(initialValue: row.isExpandedByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if editing, case .editMemo(let root, let task) = row.primaryAction {
                Text(row.taskName ?? task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Memo", text: $memoText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        store.saveMemo(root: root, task: task, text: memoText)
                        editing = false
                    }
                    Button("Cancel") { editing = false }
                }
            } else if row.kind == .task {
                taskDisclosure
            } else if row.kind == .repo {
                repoLine(title: row.title)
            } else {
                messageLine
            }
        }
        .padding(.vertical, 3)
    }

    private var taskDisclosure: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                if !row.currentItem.isEmpty {
                    Text("now ▸ \(row.currentItem)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ForEach(Array(row.repos.enumerated()), id: \.offset) { _, repo in
                    repoLine(title: repoTitle(repo))
                }
                ForEach(Array(row.checklistItems.enumerated()), id: \.offset) { index, item in
                    checklistLine(item: item, rollup: rollupText(at: index))
                }
                if row.repos.isEmpty && row.checklistItems.isEmpty && row.currentItem.isEmpty {
                    Text("No details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }
            }
            .padding(.leading, 14)
        } label: {
            HStack(alignment: .top) {
                Button(action: startPrimaryAction) {
                    Text(row.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(statusColor(row.status))
                Menu("Actions") {
                    ForEach(Array(row.secondaryActions.enumerated()), id: \.offset) { _, action in
                        Button(label(for: action)) { store.perform(action) }
                    }
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var messageLine: some View {
        Button(action: startPrimaryAction) {
            Text(row.title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(row.kind == .error ? .red : .primary)
    }

    private func repoLine(title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
    }

    private func checklistLine(item: WorkbranchChecklistItem, rollup: String) -> some View {
        HStack(spacing: 4) {
            Text(item.checked ? "✓" : "☐")
            Text(item.text)
                .strikethrough(item.checked)
            if !rollup.isEmpty {
                Text(rollup)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(item.checked ? .secondary : .primary)
        .padding(.leading, CGFloat(max(item.depth, 0) * 14 + 18))
    }

    private func repoTitle(_ repo: WorkbranchRepo) -> String {
        var title = "\(repo.name)  \(repo.branch)"
        if repo.dirty { title += "  ●" }
        return title
    }

    private func rollupText(at index: Int) -> String {
        guard index < row.checklistItems.count else { return "" }
        let parent = row.checklistItems[index]
        var done = parent.checked ? 1 : 0
        var total = 1
        var cursor = index + 1
        while cursor < row.checklistItems.count {
            let candidate = row.checklistItems[cursor]
            guard candidate.depth > parent.depth else { break }
            total += 1
            if candidate.checked { done += 1 }
            cursor += 1
        }
        return total > 1 ? "\(done)/\(total)" : ""
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "in-progress": return .blue
        case "review": return .purple
        case "blocked": return .red
        case "planning": return .gray
        default: return .primary
        }
    }

    private func startPrimaryAction() {
        if case .editMemo = row.primaryAction {
            memoText = row.memoTitle ?? ""
            editing = true
        } else if let primaryAction = row.primaryAction {
            store.perform(primaryAction)
        }
    }

    private func label(for action: MenuAction) -> String {
        switch action {
        case .editMemo: return "Edit memo"
        case .clearNotifications: return "Clear notifications"
        case .openTerminal: return "Open terminal"
        case .openIDE: return "Open in IDE"
        case .revealFinder: return "Reveal in Finder"
        case .copyPath: return "Copy task path"
        case .openConfig: return "Open config"
        case .refresh: return "Refresh now"
        case .quit: return "Quit"
        }
    }
}
