import Foundation
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
            currentWorkLine
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
            if !row.activeTimeText.isEmpty {
                Text(row.activeTimeText)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.warning)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(row.taskName ?? row.title)
                .fontWeight(.semibold)
                .foregroundStyle(palette.command)
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
            metaLine(label: "branch", value: repo.branch, tone: .normal)
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

    private var currentWorkLine: some View {
        Group {
            if let statusReadAction = row.statusReadAction {
                Button(action: { store.perform(statusReadAction) }) {
                    currentWorkLineContent
                }
                .buttonStyle(.plain)
                .help(row.isStatusUnread ? "Mark status update as read" : "Status update is read")
            } else {
                currentWorkLineContent
            }
        }
    }

    private var currentWorkLineContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│")
                .foregroundStyle(palette.accent)
                .fontWeight(.semibold)
            Text(statusSegmentText)
                .foregroundStyle(row.isStatusUnread ? palette.warning : palette.color(for: statusTone))
                .fontWeight(.bold)
                .lineLimit(1)
            Text("│")
                .foregroundStyle(palette.muted)
            Text(timeSegmentText)
                .foregroundStyle(palette.warning)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text("│")
                .foregroundStyle(palette.muted)
            Text(statusMessageText)
                .foregroundStyle(row.isStatusUnread ? palette.accent : palette.warning)
                .fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
    }

    private var statusDetailsBlock: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                if let memo = row.memoTitle, !memo.isEmpty {
                    detailLine(label: "memo", value: memo, tone: .muted)
                }
                if row.plans.count > 1 {
                    ForEach(Array(renderablePlans.enumerated()), id: \.offset) { _, plan in
                        planBlock(plan)
                    }
                } else {
                    ForEach(Array(row.checklistItems.enumerated()), id: \.offset) { _, item in
                        statusItemLine(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 176, alignment: .top)
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


    private func planBlock(_ plan: WorkbranchPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            planHeaderLine(plan)
            ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                statusItemLine(item)
            }
        }
    }

    private func planHeaderLine(_ plan: WorkbranchPlan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("│ plan")
                .foregroundStyle(palette.muted)
            Text(plan.title)
                .foregroundStyle(palette.command)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            if plan.progressTotal > 0 {
                Text("\(plan.progressDone)/\(plan.progressTotal)")
                    .foregroundStyle(palette.warning)
                    .monospacedDigit()
            }
            Text(plan.status.uppercased())
                .foregroundStyle(palette.color(for: tone(for: plan.status)))
                .fontWeight(.semibold)
                .lineLimit(1)
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
        if row.plans.count > 1 { return !renderablePlans.isEmpty }
        return !row.checklistItems.isEmpty
    }

    private var renderablePlans: [WorkbranchPlan] {
        row.plans.filter { plan in
            !plan.title.isEmpty ||
                !plan.status.isEmpty ||
                plan.progressTotal > 0 ||
                !plan.currentItem.isEmpty ||
                !plan.items.isEmpty
        }
    }

    private var statusMessageText: String {
        if !row.currentItem.isEmpty { return row.currentItem }
        if row.progressTotal > 0 { return "\(row.progressDone)/\(row.progressTotal)" }
        return "no active checklist item"
    }

    private var statusSegmentText: String {
        let text = statusLabel.uppercased()
        return row.isStatusUnread ? "● \(text)" : text
    }

    private var timeSegmentText: String {
        updatedTimeText ?? "--:--"
    }

    private var updatedTimeText: String? {
        guard row.updatedAt > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)))
    }

    private var statusLabel: String {
        row.status.isEmpty ? "unknown" : row.status
    }

    private var statusTone: TerminalTone {
        tone(for: row.status)
    }

    private func tone(for status: String) -> TerminalTone {
        switch status {
        case "done": return .accent
        case "in-progress": return .normal
        case "review": return .warning
        case "blocked": return .error
        case "planning": return .muted
        case "todo": return .muted
        default: return .muted
        }
    }
}
