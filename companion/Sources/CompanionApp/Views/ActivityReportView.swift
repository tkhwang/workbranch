import SwiftUI
import CompanionCore

private enum ReportDetailLevel {
    case projectOnly
    case taskPlans

    var includesTasks: Bool {
        switch self {
        case .projectOnly: return false
        case .taskPlans: return true
        }
    }

    var includesPlans: Bool {
        switch self {
        case .projectOnly: return false
        case .taskPlans: return true
        }
    }
}

struct ActivityReportView: View {
    let today: ActivityReport
    let week: ActivityReport
    let month: ActivityReport
    @Environment(\.terminalPalette) private var palette
    private let sectionSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            TerminalLine(prefix: "[*]", command: "Activity report", tone: .accent)
            sectionBlock(title: "Today", report: today, detailLevel: .taskPlans)
            sectionBlock(title: "Weekly", report: week, detailLevel: .taskPlans)
            sectionBlock(title: "Monthly", report: month, detailLevel: .projectOnly)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.rule, lineWidth: 1)
        )
    }

    private func sectionBlock(title: String, report: ActivityReport, detailLevel: ReportDetailLevel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("[+]")
                    .foregroundStyle(palette.accent)
                Text(title)
                    .foregroundStyle(palette.command)
                    .fontWeight(.semibold)
                Text(durationText(report.totals.seconds))
                    .foregroundStyle(palette.warning)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            if report.projects.isEmpty {
                TerminalLine(prefix: "#", command: "No activity recorded \(title.lowercased())", tone: .muted)
            } else {
                ForEach(report.projects, id: \.identity) { project in
                    projectBlock(project, detailLevel: detailLevel)
                }
            }
        }
    }

    private func projectBlock(_ project: ActivityReportProject, detailLevel: ReportDetailLevel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("│")
                    .foregroundStyle(palette.accent)
                Text(project.project)
                    .foregroundStyle(palette.command)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(durationText(project.totalSeconds))
                    .foregroundStyle(palette.warning)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            if detailLevel.includesTasks {
                ForEach(project.tasks, id: \.task) { task in
                    if shouldShowTaskIdentity(in: project) {
                        taskIdentityLine(task)
                    }
                    if detailLevel.includesPlans {
                        ForEach(task.plans, id: \.identity) { plan in
                            planBlock(plan)
                        }
                    }
                }
            }
        }
    }

    private func shouldShowTaskIdentity(in project: ActivityReportProject) -> Bool {
        project.tasks.count > 1
    }

    private func taskIdentityLine(_ task: ActivityReportTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│")
                .foregroundStyle(palette.muted)
            Text("•")
                .foregroundStyle(palette.muted)
            Text(task.task)
                .foregroundStyle(palette.text)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(durationText(task.seconds))
                .foregroundStyle(palette.warning)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func planBlock(_ plan: ActivityReportPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            planLine(plan)
            if !plan.items.isEmpty {
                ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                    planStepLine(item)
                }
            }
        }
    }

    private func planLine(_ plan: ActivityReportPlan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│")
                .foregroundStyle(palette.muted)
            Text("[*]")
                .foregroundStyle(palette.accent)
            Text(plan.title)
                .foregroundStyle(palette.text)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(durationText(plan.seconds))
                .foregroundStyle(palette.warning)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(planStatusText(plan))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
        }
    }

    private func planStepLine(_ item: WorkbranchChecklistItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│")
                .foregroundStyle(palette.muted)
            Text(indentedStepText(item))
                .foregroundStyle(item.checked ? palette.muted : palette.text)
                .strikethrough(item.checked, color: palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func planStatusText(_ plan: ActivityReportPlan) -> String {
        let status = plan.status.isEmpty ? "unknown" : plan.status.uppercased()
        guard plan.progressTotal > 0 else { return status }
        return "\(status) \(plan.progressDone)/\(plan.progressTotal)"
    }

    private func indentedStepText(_ item: WorkbranchChecklistItem) -> String {
        String(repeating: "  ", count: max(0, item.depth)) + item.text
    }

    private func durationText(_ seconds: Int) -> String {
        let formatted = ActivityReport.formatDuration(seconds)
        return formatted.isEmpty ? "0m" : formatted
    }
}
