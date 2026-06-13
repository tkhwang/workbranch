import SwiftUI
import CompanionCore

struct RowView: View {
    let row: MenuRow
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if row.kind == .task {
                taskBlock
            } else {
                messageLine
            }
        }
        .padding(.vertical, 2)
    }

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            taskCommandLine
            if let memo = row.memoTitle, !memo.isEmpty {
                TerminalLine(prefix: " ", command: "memo \(memo)", tone: .muted)
            }
            ForEach(Array(row.repos.enumerated()), id: \.offset) { _, repo in
                repoLine(repo)
            }
            ForEach(Array(row.checklistItems.enumerated()), id: \.offset) { _, item in
                statusItemLine(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskCommandLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("$")
                .foregroundStyle(palette.accent)
            Text(row.taskName ?? row.title)
                .fontWeight(.semibold)
                .foregroundStyle(palette.command)
                .lineLimit(1)
            TerminalToken(label: "status", value: statusLabel, tone: statusTone)
        }
    }

    private var messageLine: some View {
        TerminalLine(
            prefix: row.kind == .error ? "!" : "#",
            command: row.title,
            tone: row.kind == .error ? .error : .muted
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func repoLine(_ repo: WorkbranchRepo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│ repo")
                .foregroundStyle(palette.accent)
            Text(repo.name)
                .foregroundStyle(palette.command)
                .fontWeight(.semibold)
        }
    }

    private func statusItemLine(_ item: WorkbranchChecklistItem) -> some View {
        HStack(spacing: 7) {
            Text("│")
                .foregroundStyle(palette.muted)
            Text(String(repeating: "  ", count: max(item.depth, 0)) + (item.checked ? "[x]" : "[ ]"))
                .foregroundStyle(item.checked ? palette.muted : palette.text)
            Text(item.text)
                .foregroundStyle(item.checked ? palette.muted : palette.text)
                .strikethrough(item.checked)
                .lineLimit(1)
        }
    }

    private var statusLabel: String {
        row.status.isEmpty ? "unknown" : row.status
    }

    private var statusTone: TerminalTone {
        switch row.status {
        case "done": return .accent
        case "in-progress": return .normal
        case "review": return .warning
        case "blocked": return .error
        case "planning": return .muted
        default: return .muted
        }
    }
}
