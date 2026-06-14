import SwiftUI
import CompanionCore

struct RowView: View {
    let row: MenuRow
    @ObservedObject var store: StateStore
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
            ForEach(Array(row.repos.enumerated()), id: \.offset) { _, repo in
                repoMetaLines(repo)
            }
            if hasStatusDetails {
                statusDetailsBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskCommandLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("[+]")
                .foregroundStyle(palette.accent)
            Text(row.taskName ?? row.title)
                .fontWeight(.semibold)
                .foregroundStyle(palette.command)
                .lineLimit(1)
            Text("|")
                .foregroundStyle(palette.muted)
            Text(statusLabel)
                .foregroundStyle(palette.color(for: statusTone))
                .lineLimit(1)
        }
    }

    private var messageLine: some View {
        Group {
            if let primaryAction = row.primaryAction {
                Button(action: { store.perform(primaryAction) }) {
                    messageText
                }
                .buttonStyle(.plain)
            } else {
                messageText
            }
        }
    }

    private var messageText: some View {
        TerminalLine(
            prefix: row.kind == .error ? "!" : "#",
            command: row.title,
            tone: row.kind == .error ? .error : .muted
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func repoMetaLines(_ repo: WorkbranchRepo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metaLine(label: "repo", value: repo.name, tone: .normal)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                metaLine(label: "branch", value: repo.branch, tone: .normal)
                TerminalToken(
                    label: "dirty",
                    value: repo.dirty ? "yes" : "no",
                    tone: repo.dirty ? .warning : .muted
                )
            }
        }
    }

    private func metaLine(label: String, value: String, tone: TerminalTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│ \(label)")
                .foregroundStyle(palette.accent)
            Text(value)
                .foregroundStyle(palette.color(for: tone))
                .fontWeight(label == "repo" ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusDetailsBlock: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                statusSummaryLine
                if let memo = row.memoTitle, !memo.isEmpty {
                    detailLine(label: "memo", value: memo, tone: .muted)
                }
                ForEach(Array(row.checklistItems.enumerated()), id: \.offset) { _, item in
                    statusItemLine(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 176, alignment: .top)
    }

    private var statusSummaryLine: some View {
        let summary = row.currentItem.isEmpty ? statusLabel : "\(statusLabel) · now ▸ \(row.currentItem)"
        return detailLine(label: "status", value: summary, tone: statusTone, showsGuide: false)
    }

    private func detailLine(label: String, value: String, tone: TerminalTone, showsGuide: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(showsGuide ? "│ \(label)" : label)
                .foregroundStyle(palette.muted)
            Text(value)
                .foregroundStyle(palette.color(for: tone))
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    private func statusItemLine(_ item: WorkbranchChecklistItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("│")
                .foregroundStyle(palette.muted)
            Text(String(repeating: "  ", count: max(item.depth, 0)) + (item.checked ? "[x]" : "[ ]"))
                .foregroundStyle(item.checked ? palette.muted : palette.text)
            Text(item.text)
                .foregroundStyle(item.checked ? palette.muted : palette.text)
                .strikethrough(item.checked)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var hasStatusDetails: Bool {
        if let memo = row.memoTitle, !memo.isEmpty { return true }
        return !row.checklistItems.isEmpty || !row.currentItem.isEmpty || row.progressTotal > 0
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
