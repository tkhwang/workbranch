import Foundation

public struct ActivityEvent: Codable, Equatable, Sendable {
    public let v: Int
    public let editedAt: Int
    public let observedAt: Int
    public let root: String
    public let project: String
    public let task: String
    public let plan: String
    public let planIndex: Int
    public let planTitle: String
    public let planStatus: String
    public let status: String
    public let taskProgressDone: Int
    public let taskProgressTotal: Int
    public let progressDone: Int
    public let progressTotal: Int
    public let items: [WorkbranchChecklistItem]

    private enum CodingKeys: String, CodingKey {
        case v
        case editedAt
        case observedAt
        case root
        case project
        case task
        case plan
        case planIndex
        case planTitle
        case planStatus
        case status
        case taskProgressDone
        case taskProgressTotal
        case progressDone
        case progressTotal
        case items
    }

    public init(
        v: Int = 1,
        editedAt: Int,
        observedAt: Int,
        root: String,
        project: String,
        task: String,
        plan: String? = nil,
        planIndex: Int = 0,
        planTitle: String = "",
        planStatus: String? = nil,
        status: String,
        taskProgressDone: Int? = nil,
        taskProgressTotal: Int? = nil,
        progressDone: Int,
        progressTotal: Int,
        items: [WorkbranchChecklistItem] = []
    ) {
        self.v = v
        self.editedAt = editedAt
        self.observedAt = observedAt
        self.root = root
        self.project = project
        self.task = task
        self.plan = plan ?? planTitle
        self.planIndex = planIndex
        self.planTitle = planTitle.isEmpty ? (plan ?? "") : planTitle
        self.planStatus = planStatus ?? status
        self.status = status
        self.taskProgressDone = taskProgressDone ?? progressDone
        self.taskProgressTotal = taskProgressTotal ?? progressTotal
        self.progressDone = progressDone
        self.progressTotal = progressTotal
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        editedAt = try container.decode(Int.self, forKey: .editedAt)
        observedAt = try container.decode(Int.self, forKey: .observedAt)
        root = try container.decode(String.self, forKey: .root)
        project = try container.decode(String.self, forKey: .project)
        task = try container.decode(String.self, forKey: .task)
        let decodedPlanTitle = try container.decodeIfPresent(String.self, forKey: .planTitle) ?? ""
        let decodedPlan = try container.decodeIfPresent(String.self, forKey: .plan) ?? decodedPlanTitle
        plan = decodedPlan
        planIndex = try container.decodeIfPresent(Int.self, forKey: .planIndex) ?? 0
        planTitle = decodedPlanTitle.isEmpty ? decodedPlan : decodedPlanTitle
        status = try container.decode(String.self, forKey: .status)
        planStatus = try container.decodeIfPresent(String.self, forKey: .planStatus) ?? status
        let decodedProgressDone = try container.decode(Int.self, forKey: .progressDone)
        let decodedProgressTotal = try container.decode(Int.self, forKey: .progressTotal)
        taskProgressDone = try container.decodeIfPresent(Int.self, forKey: .taskProgressDone) ?? decodedProgressDone
        taskProgressTotal = try container.decodeIfPresent(Int.self, forKey: .taskProgressTotal) ?? decodedProgressTotal
        progressDone = decodedProgressDone
        progressTotal = decodedProgressTotal
        items = try container.decodeIfPresent([WorkbranchChecklistItem].self, forKey: .items) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(editedAt, forKey: .editedAt)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(root, forKey: .root)
        try container.encode(project, forKey: .project)
        try container.encode(task, forKey: .task)
        try container.encode(plan, forKey: .plan)
        try container.encode(planIndex, forKey: .planIndex)
        try container.encode(planTitle, forKey: .planTitle)
        try container.encode(planStatus, forKey: .planStatus)
        try container.encode(status, forKey: .status)
        try container.encode(taskProgressDone, forKey: .taskProgressDone)
        try container.encode(taskProgressTotal, forKey: .taskProgressTotal)
        try container.encode(progressDone, forKey: .progressDone)
        try container.encode(progressTotal, forKey: .progressTotal)
        if !items.isEmpty {
            try container.encode(items, forKey: .items)
        }
    }

    public static func diff(
        previous: [String: WorkbranchListDocument],
        next documents: [WorkbranchListDocument],
        observedAt: Int,
        isBaseline: Bool
    ) -> [ActivityEvent] {
        guard !isBaseline else { return [] }
        var events: [ActivityEvent] = []
        var seen = Set<String>()
        for document in documents {
            guard let previousDocument = previous[document.root] else { continue }
            let previousTasks = Dictionary(uniqueKeysWithValues: previousDocument.tasks.map { ($0.name, $0) })
            for task in document.tasks {
                guard task.updatedAt > 0 else { continue }
                let previousTask = previousTasks[task.name]
                if let previousTask, task.updatedAt < previousTask.updatedAt { continue }
                let previousPlans = Dictionary(uniqueKeysWithValues: (previousTask?.activityPlans ?? []).map { ($0.identityKey, $0) })
                var emittedPlanChange = false
                for plan in task.activityPlans {
                    if let previousPlan = previousPlans[plan.identityKey], plan.activityEventKey == previousPlan.activityEventKey {
                        continue
                    }
                    emittedPlanChange = true
                    let key = "\(document.root)\u{0}\(task.name)\u{0}\(plan.title)\u{0}\(plan.index)\u{0}\(task.updatedAt)\u{0}\(plan.activityEventKey)"
                    guard seen.insert(key).inserted else { continue }
                    events.append(ActivityEvent(
                        editedAt: task.updatedAt,
                        observedAt: observedAt,
                        root: document.root,
                        project: document.project,
                        task: task.name,
                        plan: plan.title,
                        planIndex: plan.index,
                        planTitle: plan.title,
                        planStatus: plan.status,
                        status: task.status,
                        taskProgressDone: task.progressDone,
                        taskProgressTotal: task.progressTotal,
                        progressDone: plan.progressDone,
                        progressTotal: plan.progressTotal,
                        items: plan.items
                    ))
                }
                if !emittedPlanChange, let previousTask, task.status != previousTask.status, let plan = task.activityPlans.first {
                    let key = "\(document.root)\u{0}\(task.name)\u{0}\(plan.title)\u{0}\(plan.index)\u{0}\(task.updatedAt)\u{0}\(task.status)"
                    guard seen.insert(key).inserted else { continue }
                    events.append(ActivityEvent(
                        editedAt: task.updatedAt,
                        observedAt: observedAt,
                        root: document.root,
                        project: document.project,
                        task: task.name,
                        plan: plan.title,
                        planIndex: plan.index,
                        planTitle: plan.title,
                        planStatus: plan.status,
                        status: task.status,
                        taskProgressDone: task.progressDone,
                        taskProgressTotal: task.progressTotal,
                        progressDone: plan.progressDone,
                        progressTotal: plan.progressTotal,
                        items: plan.items
                    ))
                }
            }
        }
        return events
    }

    public func jsonLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return text + "\n"
    }

    public static func decodeLine(_ line: String) throws -> ActivityEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        let event = try JSONDecoder().decode(ActivityEvent.self, from: data)
        guard event.v == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(event.v) }
        return event
    }
}

private extension WorkbranchTask {
    var activityPlans: [WorkbranchPlan] {
        plans
    }
}

private extension WorkbranchPlan {
    var identityKey: String { "\(title)\u{0}\(index)" }

    var activityEventKey: String {
        let stepKey = items.map { "\($0.depth)\u{1}\($0.checked)\u{1}\($0.text)" }.joined(separator: "\u{2}")
        return [
            title,
            "\(index)",
            status,
            "\(progressDone)",
            "\(progressTotal)",
            currentItem,
            stepKey
        ].joined(separator: "\u{0}")
    }
}
