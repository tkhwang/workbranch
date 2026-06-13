import SwiftUI
import CompanionCore

struct CompanionPopoverView: View {
    @ObservedObject var store: StateStore
    @State private var showingNewWorkspace = false
    @State private var selectedRoot = ""
    @State private var newTaskName = ""

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
        .frame(width: 480, height: 560)
        .onAppear {
            if selectedRoot.isEmpty { selectedRoot = store.configuredRoots.first ?? "" }
        }
        .sheet(isPresented: $showingNewWorkspace) { newWorkspaceSheet }
    }

    private var header: some View {
        HStack {
            Text("Workbranch")
                .font(.headline)
            Spacer()
            Text(store.menuState.title)
                .foregroundStyle(.secondary)
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
            Button("New workspace…") {
                selectedRoot = store.configuredRoots.first ?? ""
                newTaskName = ""
                showingNewWorkspace = true
            }
            .disabled(store.configuredRoots.isEmpty)
            Button("Refresh now") { store.refreshAll() }
            Button("Open config") { store.openConfig() }
            Spacer()
            Button("Quit") { store.quit() }
        }
    }

    private var newWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New workspace")
                .font(.headline)
            Picker("Root", selection: $selectedRoot) {
                ForEach(store.configuredRoots, id: \.self) { root in Text(root).tag(root) }
            }
            TextField("Task name", text: $newTaskName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showingNewWorkspace = false }
                Button("Create") {
                    store.addWorkspace(root: selectedRoot, task: newTaskName)
                    showingNewWorkspace = false
                }
                .disabled(selectedRoot.isEmpty || newTaskName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}

private struct RowView: View {
    let row: MenuRow
    @ObservedObject var store: StateStore
    @State private var editing = false
    @State private var memoText = ""

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
            } else if row.kind == .repo {
                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button(action: startPrimaryAction) {
                            Text(row.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(row.kind == .error ? .red : .primary)
                        if let subtitle = row.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if row.kind == .task {
                        Menu("Actions") {
                            ForEach(Array(row.secondaryActions.enumerated()), id: \.offset) { _, action in
                                Button(label(for: action)) { store.perform(action) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
        }
        .padding(.vertical, 3)
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
        case .newWorkspace: return "New workspace"
        case .quit: return "Quit"
        }
    }
}
