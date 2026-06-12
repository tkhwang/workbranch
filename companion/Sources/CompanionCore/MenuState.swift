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
    case message
    case error
}

public enum MenuAction: Equatable, Sendable {
    case editMemo(root: String, task: String)
    case clearNotifications(root: String, task: String)
    case openTerminal(root: String, task: String)
    case openIDE(root: String, task: String)
    case revealFinder(root: String, task: String)
    case copyPath(path: String)
    case openConfig
    case refresh
    case newWorkspace(root: String?)
    case quit
}

public struct MenuRow: Equatable, Sendable {
    public let kind: MenuRowKind
    public let title: String
    public let subtitle: String?
    public let primaryAction: MenuAction?
    public let secondaryActions: [MenuAction]
    public let taskName: String?
    public let memoTitle: String?
    public let notificationCount: Int

    public init(
        kind: MenuRowKind,
        title: String,
        subtitle: String? = nil,
        primaryAction: MenuAction? = nil,
        secondaryActions: [MenuAction] = [],
        taskName: String? = nil,
        memoTitle: String? = nil,
        notificationCount: Int = 0
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.taskName = taskName
        self.memoTitle = memoTitle
        self.notificationCount = notificationCount
    }
}

public struct MenuSection: Equatable, Sendable {
    public let root: String?
    public let title: String
    public let rows: [MenuRow]
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

public struct MenuState: Equatable, Sendable {
    public let title: String
    public let sections: [MenuSection]
    public let notificationsToSend: [TaskNotification]

    public static func make(
        configuredRoots: [String],
        results: [RootResult],
        previous: [String: WorkbranchListDocument]?,
        tracker: inout NotificationTracker,
        isBaseline: Bool
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

        let resultByRoot = Dictionary(uniqueKeysWithValues: results.map { ($0.root, $0) })
        var sections: [MenuSection] = []
        var taskCount = 0
        var rootsWithNotifications = Set<String>()
        var notifications: [TaskNotification] = []

        for root in configuredRoots {
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
                errorMessage = "No refresh result for root"
            }

            var rows: [MenuRow] = []
            if let errorMessage {
                rows.append(MenuRow(kind: .error, title: "Error: \(errorMessage)"))
            }

            if let document {
                taskCount += document.tasks.count
                for task in document.tasks {
                    if task.notiCount > 0 { rootsWithNotifications.insert(document.root) }
                    if let notification = tracker.observe(root: document.root, task: task.name, count: task.notiCount, isBaseline: isBaseline) {
                        notifications.append(notification)
                    }
                    rows.append(row(for: task, root: document.root))
                }
                if document.tasks.isEmpty && rows.isEmpty {
                    rows.append(MenuRow(kind: .message, title: "No task workspaces"))
                }
                sections.append(MenuSection(root: document.root, title: document.project, rows: rows))
            } else {
                if rows.isEmpty {
                    rows.append(MenuRow(kind: .error, title: "Error: root has no data"))
                }
                sections.append(MenuSection(root: root, title: root, rows: rows))
            }
        }

        var title = "⎇ \(taskCount)"
        if !rootsWithNotifications.isEmpty {
            title += " 🔔\(rootsWithNotifications.count)"
        }
        return MenuState(title: title, sections: sections, notificationsToSend: notifications)
    }

    private static func row(for task: WorkbranchTask, root: String) -> MenuRow {
        var title = task.name
        if !task.memoTitle.isEmpty {
            title += " — \(task.memoTitle)"
        }
        if task.notiCount > 0 {
            title += " 🔔\(task.notiCount)"
        }
        if task.repos.contains(where: { $0.dirty }) {
            title += " ●"
        }
        return MenuRow(
            kind: .task,
            title: title,
            subtitle: task.path,
            primaryAction: .editMemo(root: root, task: task.name),
            secondaryActions: [
                .clearNotifications(root: root, task: task.name),
                .openTerminal(root: root, task: task.name),
                .openIDE(root: root, task: task.name),
                .revealFinder(root: root, task: task.name),
                .copyPath(path: task.path),
            ],
            taskName: task.name,
            memoTitle: task.memoTitle,
            notificationCount: task.notiCount
        )
    }
}
