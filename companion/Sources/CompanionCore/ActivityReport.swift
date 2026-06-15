import Foundation

public enum ActivityReportScope: String, Codable, Equatable, Sendable {
    case today
    case week
    case month
    case all
}

public struct ActivityReportTotals: Codable, Equatable, Sendable {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }
}

public struct ActivityReportPlan: Codable, Equatable, Sendable {
    public let title: String
    public let index: Int
    public let seconds: Int
    public let sessions: Int
    public let firstEditedAt: Int
    public let lastEditedAt: Int
    public let status: String
    public let progressDone: Int
    public let progressTotal: Int
    public let items: [WorkbranchChecklistItem]

    private enum CodingKeys: String, CodingKey {
        case title
        case index
        case seconds
        case sessions
        case firstEditedAt
        case lastEditedAt
        case status
        case progressDone
        case progressTotal
        case items
    }

    public var identity: String { "\(firstEditedAt)\u{0}\(index)\u{0}\(title)" }

    public init(
        title: String,
        index: Int,
        seconds: Int,
        sessions: Int,
        firstEditedAt: Int? = nil,
        lastEditedAt: Int,
        status: String = "",
        progressDone: Int = 0,
        progressTotal: Int = 0,
        items: [WorkbranchChecklistItem] = []
    ) {
        self.title = title
        self.index = index
        self.seconds = seconds
        self.sessions = sessions
        self.firstEditedAt = firstEditedAt ?? lastEditedAt
        self.lastEditedAt = lastEditedAt
        self.status = status
        self.progressDone = progressDone
        self.progressTotal = progressTotal
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        index = try container.decode(Int.self, forKey: .index)
        seconds = try container.decode(Int.self, forKey: .seconds)
        sessions = try container.decode(Int.self, forKey: .sessions)
        lastEditedAt = try container.decode(Int.self, forKey: .lastEditedAt)
        firstEditedAt = try container.decodeIfPresent(Int.self, forKey: .firstEditedAt) ?? lastEditedAt
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        progressDone = try container.decodeIfPresent(Int.self, forKey: .progressDone) ?? 0
        progressTotal = try container.decodeIfPresent(Int.self, forKey: .progressTotal) ?? 0
        items = try container.decodeIfPresent([WorkbranchChecklistItem].self, forKey: .items) ?? []
    }
}

public struct ActivityReportTask: Codable, Equatable, Sendable {
    public let task: String
    public let planTitle: String
    public let seconds: Int
    public let sessions: Int
    public let lastEditedAt: Int
    public let status: String
    public let progressDone: Int
    public let progressTotal: Int
    public let plans: [ActivityReportPlan]

    public init(
        task: String,
        planTitle: String = "",
        seconds: Int,
        sessions: Int,
        lastEditedAt: Int,
        status: String = "",
        progressDone: Int = 0,
        progressTotal: Int = 0,
        plans: [ActivityReportPlan] = []
    ) {
        self.task = task
        self.planTitle = planTitle
        self.seconds = seconds
        self.sessions = sessions
        self.lastEditedAt = lastEditedAt
        self.status = status
        self.progressDone = progressDone
        self.progressTotal = progressTotal
        self.plans = plans
    }
}

public struct ActivityReportProject: Codable, Equatable, Sendable {
    public let project: String
    public let root: String
    public let totalSeconds: Int
    public let tasks: [ActivityReportTask]

    public var identity: String { "\(root)\u{0}\(project)" }

    public init(project: String, root: String, totalSeconds: Int, tasks: [ActivityReportTask]) {
        self.project = project
        self.root = root
        self.totalSeconds = totalSeconds
        self.tasks = tasks
    }
}

public struct ActivityReport: Codable, Equatable, Sendable {
    public let scope: ActivityReportScope
    public let generatedAt: Int
    public let projects: [ActivityReportProject]
    public let totals: ActivityReportTotals

    private static let idleGapSeconds = 25 * 60
    private static let leadPadSeconds = 5 * 60

    public init(scope: ActivityReportScope, generatedAt: Int, projects: [ActivityReportProject], totals: ActivityReportTotals) {
        self.scope = scope
        self.generatedAt = generatedAt
        self.projects = projects
        self.totals = totals
    }

    public static func empty(scope: ActivityReportScope, generatedAt: Int) -> ActivityReport {
        ActivityReport(scope: scope, generatedAt: generatedAt, projects: [], totals: ActivityReportTotals(seconds: 0))
    }

    public static func parseEvents(fromJSONL text: String) -> [ActivityEvent] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? ActivityEvent.decodeLine(String(line))
        }
    }

    public static func make(
        events: [ActivityEvent],
        scope: ActivityReportScope,
        project projectFilter: String? = nil,
        generatedAt: Int,
        calendar: Calendar = .current
    ) -> ActivityReport {
        let scopeInterval = dateInterval(for: scope, generatedAt: generatedAt, calendar: calendar)
        let filtered = events.filter { event in
            guard event.editedAt > 0 else { return false }
            if let projectFilter, event.project != projectFilter { return false }
            return true
        }
        guard !filtered.isEmpty else { return empty(scope: scope, generatedAt: generatedAt) }

        let grouped = Dictionary(grouping: filtered) { event in
            "\(event.root)\u{0}\(event.project)\u{0}\(event.task)"
        }
        var projectsByKey: [String: (project: String, root: String, tasks: [ActivityReportTask])] = [:]
        for events in grouped.values {
            guard let first = events.first else { continue }
            let sorted = events.sorted { lhs, rhs in
                if lhs.editedAt != rhs.editedAt { return lhs.editedAt < rhs.editedAt }
                if lhs.observedAt != rhs.observedAt { return lhs.observedAt < rhs.observedAt }
                return lhs.planIndex < rhs.planIndex
            }
            let rollup = rollupSessions(sorted.map(\.editedAt), in: scopeInterval)
            guard rollup.seconds > 0 else { continue }
            let detailEvents = sorted.filter { includes($0.editedAt, in: scopeInterval) }
            let latest = detailEvents.last ?? sorted.last
            let planReports = makePlanReports(from: sorted, in: scopeInterval)
            let task = ActivityReportTask(
                task: first.task,
                planTitle: latest?.planTitle ?? first.planTitle,
                seconds: rollup.seconds,
                sessions: rollup.sessions,
                lastEditedAt: latest?.editedAt ?? first.editedAt,
                status: latest?.status ?? first.status,
                progressDone: latest?.taskProgressDone ?? first.taskProgressDone,
                progressTotal: latest?.taskProgressTotal ?? first.taskProgressTotal,
                plans: planReports
            )
            let projectKey = "\(first.root)\u{0}\(first.project)"
            var existing = projectsByKey[projectKey] ?? (project: first.project, root: first.root, tasks: [])
            existing.tasks.append(task)
            projectsByKey[projectKey] = existing
        }

        let projects = projectsByKey.values.map { value in
            let tasks = value.tasks.sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
                if lhs.lastEditedAt != rhs.lastEditedAt { return lhs.lastEditedAt > rhs.lastEditedAt }
                return lhs.task < rhs.task
            }
            return ActivityReportProject(
                project: value.project,
                root: value.root,
                totalSeconds: tasks.reduce(0) { $0 + $1.seconds },
                tasks: tasks
            )
        }.sorted { lhs, rhs in
            if lhs.totalSeconds != rhs.totalSeconds { return lhs.totalSeconds > rhs.totalSeconds }
            if lhs.project != rhs.project { return lhs.project < rhs.project }
            return lhs.root < rhs.root
        }
        let total = projects.reduce(0) { $0 + $1.totalSeconds }
        return ActivityReport(scope: scope, generatedAt: generatedAt, projects: projects, totals: ActivityReportTotals(seconds: total))
    }

    public func activeSecondsByTask() -> [String: Int] {
        var values: [String: Int] = [:]
        for project in projects {
            for task in project.tasks {
                values[Self.taskKey(root: project.root, task: task.task)] = task.seconds
            }
        }
        return values
    }

    public static func taskKey(root: String, task: String) -> String {
        "\(root)\u{0}\(task)"
    }

    public static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let minutes = seconds / 60
        if minutes == 0 { return "<1m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h\(remainingMinutes)m"
    }

    private static func makePlanReports(from events: [ActivityEvent], in interval: DateInterval?) -> [ActivityReportPlan] {
        let grouped = Dictionary(grouping: events) { event in
            "\(event.plan)\u{0}\(event.planIndex)"
        }
        return grouped.values.compactMap { planEvents in
            guard let first = planEvents.first else { return nil }
            let title = first.plan.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let sorted = planEvents.sorted { lhs, rhs in
                if lhs.editedAt != rhs.editedAt { return lhs.editedAt < rhs.editedAt }
                return lhs.observedAt < rhs.observedAt
            }
            let rollup = rollupSessions(sorted.map(\.editedAt), in: interval)
            guard rollup.seconds > 0 else { return nil }
            let detailEvents = sorted.filter { includes($0.editedAt, in: interval) }
            let latest = detailEvents.last ?? sorted.last
            let latestWithItems = detailEvents.last(where: { !$0.items.isEmpty }) ?? sorted.last(where: { !$0.items.isEmpty })
            return ActivityReportPlan(
                title: title,
                index: first.planIndex,
                seconds: rollup.seconds,
                sessions: rollup.sessions,
                firstEditedAt: firstEditedAt(from: sorted, in: interval),
                lastEditedAt: latest?.editedAt ?? first.editedAt,
                status: latest?.planStatus ?? first.planStatus,
                progressDone: latest?.progressDone ?? first.progressDone,
                progressTotal: latest?.progressTotal ?? first.progressTotal,
                items: latestWithItems?.items ?? []
            )
        }.sorted { lhs, rhs in
            if lhs.firstEditedAt != rhs.firstEditedAt { return lhs.firstEditedAt < rhs.firstEditedAt }
            if lhs.lastEditedAt != rhs.lastEditedAt { return lhs.lastEditedAt < rhs.lastEditedAt }
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.title < rhs.title
        }
    }

    private static func firstEditedAt(from events: [ActivityEvent], in interval: DateInterval?) -> Int {
        guard let interval else { return events.first?.editedAt ?? 0 }
        if let first = events.first(where: { includes($0.editedAt, in: interval) }) {
            return first.editedAt
        }
        return Int(interval.start.timeIntervalSince1970)
    }

    private static func dateInterval(for scope: ActivityReportScope, generatedAt: Int, calendar: Calendar) -> DateInterval? {
        switch scope {
        case .all:
            return nil
        case .today:
            return calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: TimeInterval(generatedAt)))
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: TimeInterval(generatedAt)))
        case .month:
            return calendar.dateInterval(of: .month, for: Date(timeIntervalSince1970: TimeInterval(generatedAt)))
        }
    }

    private static func includes(_ timestamp: Int, in interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date >= interval.start && date < interval.end
    }

    private static func rollupSessions(_ editedAts: [Int], in interval: DateInterval?) -> (seconds: Int, sessions: Int) {
        let unique = Array(Set(editedAts)).sorted()
        guard let first = unique.first else { return (0, 0) }
        var sessionStart = first
        var sessionLast = first
        var seconds = 0
        var sessions = 0
        for editedAt in unique.dropFirst() {
            if editedAt - sessionLast <= idleGapSeconds {
                sessionLast = editedAt
            } else {
                let sessionSeconds = clippedSessionSeconds(start: sessionStart, last: sessionLast, in: interval)
                if sessionSeconds > 0 {
                    seconds += sessionSeconds
                    sessions += 1
                }
                sessionStart = editedAt
                sessionLast = editedAt
            }
        }
        let sessionSeconds = clippedSessionSeconds(start: sessionStart, last: sessionLast, in: interval)
        if sessionSeconds > 0 {
            seconds += sessionSeconds
            sessions += 1
        }
        return (seconds, sessions)
    }

    private static func clippedSessionSeconds(start: Int, last: Int, in interval: DateInterval?) -> Int {
        let sessionStart = start
        let sessionEnd = last + leadPadSeconds
        guard let interval else { return max(0, sessionEnd - sessionStart) }
        let intervalStart = Int(interval.start.timeIntervalSince1970)
        let intervalEnd = Int(interval.end.timeIntervalSince1970)
        let clippedStart = max(sessionStart, intervalStart)
        let clippedEnd = min(sessionEnd, intervalEnd)
        return max(0, clippedEnd - clippedStart)
    }
}
