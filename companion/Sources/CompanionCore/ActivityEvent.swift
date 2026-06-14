import Foundation

public struct ActivityEvent: Codable, Equatable, Sendable {
    public let v: Int
    public let editedAt: Int
    public let observedAt: Int
    public let root: String
    public let project: String
    public let task: String
    public let planTitle: String
    public let status: String
    public let progressDone: Int
    public let progressTotal: Int

    private enum CodingKeys: String, CodingKey {
        case v
        case editedAt
        case observedAt
        case root
        case project
        case task
        case planTitle
        case status
        case progressDone
        case progressTotal
    }

    public init(
        v: Int = 1,
        editedAt: Int,
        observedAt: Int,
        root: String,
        project: String,
        task: String,
        planTitle: String = "",
        status: String,
        progressDone: Int,
        progressTotal: Int
    ) {
        self.v = v
        self.editedAt = editedAt
        self.observedAt = observedAt
        self.root = root
        self.project = project
        self.task = task
        self.planTitle = planTitle
        self.status = status
        self.progressDone = progressDone
        self.progressTotal = progressTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        editedAt = try container.decode(Int.self, forKey: .editedAt)
        observedAt = try container.decode(Int.self, forKey: .observedAt)
        root = try container.decode(String.self, forKey: .root)
        project = try container.decode(String.self, forKey: .project)
        task = try container.decode(String.self, forKey: .task)
        planTitle = try container.decodeIfPresent(String.self, forKey: .planTitle) ?? ""
        status = try container.decode(String.self, forKey: .status)
        progressDone = try container.decode(Int.self, forKey: .progressDone)
        progressTotal = try container.decode(Int.self, forKey: .progressTotal)
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
            let previousTasks = Dictionary(uniqueKeysWithValues: (previous[document.root]?.tasks ?? []).map { ($0.name, $0) })
            for task in document.tasks {
                guard task.updatedAt > 0 else { continue }
                if let previousTask = previousTasks[task.name] {
                    if task.updatedAt < previousTask.updatedAt { continue }
                    if task.updatedAt == previousTask.updatedAt, task.activityEventKey == previousTask.activityEventKey { continue }
                }
                let key = "\(document.root)\u{0}\(task.name)\u{0}\(task.activityEventKey)"
                guard seen.insert(key).inserted else { continue }
                events.append(ActivityEvent(
                    editedAt: task.updatedAt,
                    observedAt: observedAt,
                    root: document.root,
                    project: document.project,
                    task: task.name,
                    planTitle: task.planTitle,
                    status: task.status,
                    progressDone: task.progressDone,
                    progressTotal: task.progressTotal
                ))
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
    var activityEventKey: String {
        let stepKey = items.map { "\($0.depth)\u{1}\($0.checked)\u{1}\($0.text)" }.joined(separator: "\u{2}")
        return [
            "\(updatedAt)",
            memoTitle,
            planTitle,
            status,
            "\(progressDone)",
            "\(progressTotal)",
            currentItem,
            stepKey
        ].joined(separator: "\u{0}")
    }
}
