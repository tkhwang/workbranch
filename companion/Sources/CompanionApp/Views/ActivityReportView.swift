import SwiftUI
import CompanionCore

struct ActivityReportView: View {
    let today: ActivityReport
    let week: ActivityReport
    let month: ActivityReport
    @Environment(\.terminalPalette) private var palette
    private let sectionSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            TerminalLine(prefix: "[*]", command: "Activity report", tone: .accent)
            sectionBlock(title: "Today", report: today, showsPlanDetails: true)
            sectionBlock(title: "Weekly", report: week, showsPlanDetails: false)
            sectionBlock(title: "Monthly", report: month, showsPlanDetails: false)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.rule, lineWidth: 1)
        )
    }

    private func sectionBlock(title: String, report: ActivityReport, showsPlanDetails: Bool) -> some View {
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
                    projectBlock(project, showsPlanDetails: showsPlanDetails)
                }
            }
        }
    }

    private func projectBlock(_ project: ActivityReportProject, showsPlanDetails: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("│ project")
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
            ForEach(project.tasks, id: \.task) { task in
                taskBlock(task)
                if showsPlanDetails {
                    if !task.planTitle.isEmpty {
                        taskLine(task)
                    }
                    statusLine(task)
                }
            }
        }
    }

    private func taskBlock(_ task: ActivityReportTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(task.planTitle.isEmpty ? "│  • task" : "│  • plan")
                .foregroundStyle(palette.muted)
            Text(planTitleText(task))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(durationText(task.seconds))
                .foregroundStyle(palette.warning)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func planTitleText(_ task: ActivityReportTask) -> String {
        task.planTitle.isEmpty ? task.task : task.planTitle
    }

    private func taskLine(_ task: ActivityReportTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│    task")
                .foregroundStyle(palette.muted)
            Text(task.task)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func statusLine(_ task: ActivityReportTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("│    status")
                .foregroundStyle(palette.muted)
            Text(statusText(task))
                .foregroundStyle(palette.warning)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text("│ sessions")
                .foregroundStyle(palette.muted)
            Text("\(task.sessions)")
                .foregroundStyle(palette.text)
                .monospacedDigit()
            Text("│ last")
                .foregroundStyle(palette.muted)
            Text(lastEditedText(task.lastEditedAt))
                .foregroundStyle(palette.text)
                .monospacedDigit()
        }
    }

    private func statusText(_ task: ActivityReportTask) -> String {
        let status = task.status.isEmpty ? "unknown" : task.status.uppercased()
        guard task.progressTotal > 0 else { return status }
        return "\(status) \(task.progressDone)/\(task.progressTotal)"
    }

    private func lastEditedText(_ timestamp: Int) -> String {
        guard timestamp > 0 else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func durationText(_ seconds: Int) -> String {
        let formatted = ActivityReport.formatDuration(seconds)
        return formatted.isEmpty ? "0m" : formatted
    }
}
