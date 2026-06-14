import Foundation

public enum RootResult: Equatable, Sendable {
    case success(WorkbranchListDocument)
    case failure(root: String, message: String)

    public var root: String {
        switch self {
        case .success(let document): return document.root
        case .failure(let root, _): return root
        }
    }
}

public enum MenuRowKind: Equatable, Sendable {
    case task
    case repo
    case message
    case error
}

public enum MenuAction: Equatable, Sendable {
    case editMemo(root: String, task: String)
    case markStatusRead(root: String, task: String, updatedAt: Int)
    case clearNotifications(root: String, task: String)
    case openTerminal(root: String, task: String)
    case openIDE(root: String, task: String)
    case revealFinder(root: String, task: String)
    case copyPath(path: String)
    case openConfig
    case refresh
    case quit
}

public struct MenuRow: Equatable, Identifiable, Sendable {
    public let kind: MenuRowKind
    public let title: String
    public let subtitle: String?
    public let primaryAction: MenuAction?
    public let statusReadAction: MenuAction?
    public let secondaryActions: [MenuAction]
    public let taskName: String?
    public let memoTitle: String?
    public let notificationCount: Int
    public let checklistItems: [WorkbranchChecklistItem]
    public let repos: [WorkbranchRepo]
    public let status: String
    public let progressDone: Int
    public let progressTotal: Int
    public let currentItem: String
    public let updatedAt: Int
    public let activeTimeText: String
    public let isStatusUnread: Bool
    public let isExpandedByDefault: Bool

    public var id: String {
        if let primaryAction {
            return "primary:\(MenuRow.actionID(primaryAction))"
        }
        if let taskName {
            return "task:\(taskName)"
        }
        return "\(kind):\(title)\u{0}\(subtitle ?? "")"
    }

    public init(
        kind: MenuRowKind,
        title: String,
        subtitle: String? = nil,
        primaryAction: MenuAction? = nil,
        statusReadAction: MenuAction? = nil,
        secondaryActions: [MenuAction] = [],
        taskName: String? = nil,
        memoTitle: String? = nil,
        notificationCount: Int = 0,
        checklistItems: [WorkbranchChecklistItem] = [],
        repos: [WorkbranchRepo] = [],
        status: String = "",
        progressDone: Int = 0,
        progressTotal: Int = 0,
        currentItem: String = "",
        updatedAt: Int = 0,
        activeTimeText: String = "",
        isStatusUnread: Bool = false,
        isExpandedByDefault: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.statusReadAction = statusReadAction
        self.secondaryActions = secondaryActions
        self.taskName = taskName
        self.memoTitle = memoTitle
        self.notificationCount = notificationCount
        self.checklistItems = checklistItems
        self.repos = repos
        self.status = status
        self.progressDone = progressDone
        self.progressTotal = progressTotal
        self.currentItem = currentItem
        self.updatedAt = updatedAt
        self.activeTimeText = activeTimeText
        self.isStatusUnread = isStatusUnread
        self.isExpandedByDefault = isExpandedByDefault
    }

    private static func actionID(_ action: MenuAction) -> String {
        switch action {
        case .editMemo(let root, let task): return "editMemo:\(root)\u{0}\(task)"
        case .markStatusRead(let root, let task, let updatedAt): return "markStatusRead:\(root)\u{0}\(task)\u{0}\(updatedAt)"
        case .clearNotifications(let root, let task): return "clearNotifications:\(root)\u{0}\(task)"
        case .openTerminal(let root, let task): return "openTerminal:\(root)\u{0}\(task)"
        case .openIDE(let root, let task): return "openIDE:\(root)\u{0}\(task)"
        case .revealFinder(let root, let task): return "revealFinder:\(root)\u{0}\(task)"
        case .copyPath(let path): return "copyPath:\(path)"
        case .openConfig: return "openConfig"
        case .refresh: return "refresh"
        case .quit: return "quit"
        }
    }
}

public struct MenuSection: Equatable, Identifiable, Sendable {
    public let root: String?
    public let title: String
    public let rows: [MenuRow]

    public var id: String {
        root.map { "root:\($0)" } ?? "companion:\(title)"
    }
}

public struct TaskNotification: Equatable, Sendable {
    public let root: String
    public let task: String
    public let count: Int
    public let previousCount: Int

    public init(root: String, task: String, count: Int, previousCount: Int) {
        self.root = root
        self.task = task
        self.count = count
        self.previousCount = previousCount
    }
}

public struct NotificationTracker: Equatable, Sendable {
    private var counts: [String: Int] = [:]

    public init() {}

    public mutating func observe(root: String, task: String, count: Int, isBaseline: Bool) -> TaskNotification? {
        let key = "\(root)\u{0}\(task)"
        defer { counts[key] = count }
        guard !isBaseline, let previous = counts[key] else { return nil }
        guard count > previous else { return nil }
        return TaskNotification(root: root, task: task, count: count, previousCount: previous)
    }
}

public struct StatusReadMarkers: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public private(set) var roots: [String: [String: Int]]

    public init(schemaVersion: Int = 1, roots: [String: [String: Int]] = [:]) {
        self.schemaVersion = schemaVersion
        self.roots = roots
    }

    public var isEmpty: Bool {
        roots.isEmpty
    }

    public static func load(from url: URL) throws -> StatusReadMarkers {
        let data = try Data(contentsOf: url)
        let markers = try JSONDecoder().decode(StatusReadMarkers.self, from: data)
        guard markers.schemaVersion == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(markers.schemaVersion) }
        return markers
    }

    public static func loadOrEmpty(from url: URL) -> StatusReadMarkers {
        (try? load(from: url)) ?? StatusReadMarkers()
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public func lastReadUpdatedAt(root: String, task: String) -> Int {
        roots[root]?[task] ?? 0
    }

    public func isUnread(root: String, task: String, updatedAt: Int) -> Bool {
        updatedAt > 0 && updatedAt > lastReadUpdatedAt(root: root, task: task)
    }

    public mutating func markRead(root: String, task: String, updatedAt: Int) {
        guard updatedAt > 0 else { return }
        var tasks = roots[root] ?? [:]
        tasks[task] = max(tasks[task] ?? 0, updatedAt)
        roots[root] = tasks
    }

    public mutating func markBaselineRead(documents: [WorkbranchListDocument]) {
        for document in documents {
            for task in document.tasks {
                markRead(root: document.root, task: task.name, updatedAt: task.updatedAt)
            }
        }
    }
}

public struct MenuState: Equatable, Sendable {
    public let title: String
    public let sections: [MenuSection]
    public let notificationsToSend: [TaskNotification]

    public static func make(
        configuredRoots: [String],
        results: [RootResult],
        previous: [String: WorkbranchListDocument]?,
        tracker: inout NotificationTracker,
        isBaseline: Bool,
        statusReadMarkers: StatusReadMarkers = StatusReadMarkers(),
        activeSecondsByTask: [String: Int] = [:]
    ) -> MenuState {
        guard !configuredRoots.isEmpty else {
            return MenuState(
                title: "⎇ 0",
                sections: [MenuSection(root: nil, title: "Workbranch Companion", rows: [
                    MenuRow(kind: .message, title: "No config roots. Open config to add workbranch project roots.", primaryAction: .openConfig)
                ])],
                notificationsToSend: []
            )
        }

        let roots = orderedUnique(configuredRoots)
        var resultByRoot: [String: RootResult] = [:]
        for result in results {
            resultByRoot[result.root] = result
        }
        var sectionBuilds: [(section: MenuSection, maxUpdatedAt: Int, originalIndex: Int)] = []
        var taskCount = 0
        var inProgressCount = 0
        var blockedCount = 0
        var totalNotificationCount = 0
        var notifications: [TaskNotification] = []

        for (rootIndex, root) in roots.enumerated() {
            let result = resultByRoot[root]
            let document: WorkbranchListDocument?
            let errorMessage: String?
            switch result {
            case .success(let success):
                document = success
                errorMessage = nil
            case .failure(_, let message):
                document = previous?[root]
                errorMessage = message
            case nil:
                document = previous?[root]
                errorMessage = document == nil ? "No refresh result for root" : nil
            }

            var rows: [MenuRow] = []
            if let errorMessage {
                rows.append(MenuRow(kind: .error, title: "Error: \(errorMessage)"))
            }

            if let document {
                taskCount += document.tasks.count
                let sortedTasks = document.tasks.enumerated().sorted { lhs, rhs in
                    if lhs.element.updatedAt != rhs.element.updatedAt {
                        return lhs.element.updatedAt > rhs.element.updatedAt
                    }
                    return lhs.offset < rhs.offset
                }.map(\.element)
                let maxUpdatedAt = sortedTasks.map(\.updatedAt).max() ?? 0
                for task in sortedTasks {
                    if task.status == "in-progress" { inProgressCount += 1 }
                    if task.status == "blocked" { blockedCount += 1 }
                    totalNotificationCount += task.notiCount
                    if let notification = tracker.observe(root: document.root, task: task.name, count: task.notiCount, isBaseline: isBaseline) {
                        notifications.append(notification)
                    }
                    rows.append(taskRow(
                        for: task,
                        root: document.root,
                        isStatusUnread: statusReadMarkers.isUnread(root: document.root, task: task.name, updatedAt: task.updatedAt),
                        activeTimeText: ActivityReport.formatDuration(activeSecondsByTask[ActivityReport.taskKey(root: document.root, task: task.name)] ?? 0)
                    ))
                }
                if document.tasks.isEmpty && rows.isEmpty {
                    rows.append(MenuRow(kind: .message, title: "No task workspaces"))
                }
                sectionBuilds.append((
                    section: MenuSection(root: document.root, title: document.project, rows: rows),
                    maxUpdatedAt: maxUpdatedAt,
                    originalIndex: rootIndex
                ))
            } else {
                if rows.isEmpty {
                    rows.append(MenuRow(kind: .error, title: "Error: root has no data"))
                }
                sectionBuilds.append((
                    section: MenuSection(root: root, title: root, rows: rows),
                    maxUpdatedAt: 0,
                    originalIndex: rootIndex
                ))
            }
        }

        var titleParts: [String] = []
        if inProgressCount > 0 { titleParts.append("▶\(inProgressCount)") }
        if blockedCount > 0 { titleParts.append("⚠\(blockedCount)") }
        if totalNotificationCount > 0 { titleParts.append("🔔\(totalNotificationCount)") }
        let title = titleParts.isEmpty ? "⎇ \(taskCount)" : titleParts.joined(separator: " ")
        let sections = sectionBuilds.sorted { lhs, rhs in
            if lhs.maxUpdatedAt != rhs.maxUpdatedAt {
                return lhs.maxUpdatedAt > rhs.maxUpdatedAt
            }
            return lhs.originalIndex < rhs.originalIndex
        }.map(\.section)
        return MenuState(title: title, sections: sections, notificationsToSend: notifications)
    }

    private static func orderedUnique(_ roots: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueRoots: [String] = []
        for root in roots where seen.insert(root).inserted {
            uniqueRoots.append(root)
        }
        return uniqueRoots
    }

    private static func taskRow(for task: WorkbranchTask, root: String, isStatusUnread: Bool, activeTimeText: String) -> MenuRow {
        var parts: [String] = []
        if let icon = statusIcon(task.status) { parts.append(icon) }
        let label = task.memoTitle.isEmpty ? task.name : "\(task.name) — \(task.memoTitle)"
        parts.append(label)
        if task.notiCount > 0 { parts.append("🔔\(task.notiCount)") }
        if task.progressTotal > 0 { parts.append("\(task.progressDone)/\(task.progressTotal)") }
        let subtitle = task.currentItem.isEmpty ? nil : "지금: \(task.currentItem)"
        return MenuRow(
            kind: .task,
            title: parts.joined(separator: " "),
            subtitle: subtitle,
            primaryAction: .editMemo(root: root, task: task.name),
            statusReadAction: .markStatusRead(root: root, task: task.name, updatedAt: task.updatedAt),
            secondaryActions: [
                .clearNotifications(root: root, task: task.name),
                .openTerminal(root: root, task: task.name),
                .openIDE(root: root, task: task.name),
                .revealFinder(root: root, task: task.name),
                .copyPath(path: task.path),
            ],
            taskName: task.name,
            memoTitle: task.memoTitle,
            notificationCount: task.notiCount,
            checklistItems: task.items,
            repos: task.repos,
            status: task.status,
            progressDone: task.progressDone,
            progressTotal: task.progressTotal,
            currentItem: task.currentItem,
            updatedAt: task.updatedAt,
            activeTimeText: activeTimeText,
            isStatusUnread: isStatusUnread,
            isExpandedByDefault: task.status == "blocked" || task.notiCount > 0 || isStatusUnread
        )
    }

    private static func statusIcon(_ status: String) -> String? {
        switch status {
        case "done": return "✓"
        case "in-progress": return "●"
        case "review": return "◐"
        case "blocked": return "⚠"
        case "planning": return "○"
        case "todo": return "·"
        default: return nil
        }
    }
}
