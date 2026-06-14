import Foundation

public enum WorkbranchListError: Error, CustomStringConvertible, Equatable {
    case unsupportedSchemaVersion(Int)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "unsupported schemaVersion \(version); expected schemaVersion 1"
        }
    }
}

public struct WorkbranchGlobalDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let projects: [WorkbranchListDocument]
    public let errors: [WorkbranchGlobalError]

    public init(schemaVersion: Int, projects: [WorkbranchListDocument], errors: [WorkbranchGlobalError] = []) throws {
        guard schemaVersion == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(schemaVersion) }
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.errors = errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(version) }
        schemaVersion = version
        projects = try container.decode([WorkbranchListDocument].self, forKey: .projects)
        errors = try container.decodeIfPresent([WorkbranchGlobalError].self, forKey: .errors) ?? []
    }

    public static func decode(_ data: Data) throws -> WorkbranchGlobalDocument {
        try JSONDecoder().decode(WorkbranchGlobalDocument.self, from: data)
    }
}

public struct WorkbranchGlobalError: Codable, Equatable, Sendable {
    public let root: String
    public let message: String

    public init(root: String, message: String) {
        self.root = root
        self.message = message
    }
}

public struct WorkbranchListDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let project: String
    public let root: String
    public let tasks: [WorkbranchTask]

    public init(schemaVersion: Int, project: String, root: String, tasks: [WorkbranchTask]) throws {
        guard schemaVersion == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(schemaVersion) }
        self.schemaVersion = schemaVersion
        self.project = project
        self.root = root
        self.tasks = tasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else { throw WorkbranchListError.unsupportedSchemaVersion(version) }
        schemaVersion = version
        project = try container.decode(String.self, forKey: .project)
        root = try container.decode(String.self, forKey: .root)
        tasks = try container.decode([WorkbranchTask].self, forKey: .tasks)
    }

    public static func decode(_ data: Data) throws -> WorkbranchListDocument {
        try JSONDecoder().decode(WorkbranchListDocument.self, from: data)
    }
}

public struct WorkbranchTask: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let memoTitle: String
    public let status: String
    public let progressDone: Int
    public let progressTotal: Int
    public let currentItem: String
    public let updatedAt: Int
    public let items: [WorkbranchChecklistItem]
    public let notiCount: Int
    public let repos: [WorkbranchRepo]

    public init(
        name: String,
        path: String,
        memoTitle: String,
        status: String = "",
        progressDone: Int = 0,
        progressTotal: Int = 0,
        currentItem: String = "",
        updatedAt: Int = 0,
        items: [WorkbranchChecklistItem] = [],
        notiCount: Int,
        repos: [WorkbranchRepo]
    ) {
        self.name = name
        self.path = path
        self.memoTitle = memoTitle
        self.status = status
        self.progressDone = progressDone
        self.progressTotal = progressTotal
        self.currentItem = currentItem
        self.updatedAt = updatedAt
        self.items = items
        self.notiCount = notiCount
        self.repos = repos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        memoTitle = try container.decode(String.self, forKey: .memoTitle)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        progressDone = try container.decodeIfPresent(Int.self, forKey: .progressDone) ?? 0
        progressTotal = try container.decodeIfPresent(Int.self, forKey: .progressTotal) ?? 0
        currentItem = try container.decodeIfPresent(String.self, forKey: .currentItem) ?? ""
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        items = try container.decodeIfPresent([WorkbranchChecklistItem].self, forKey: .items) ?? []
        notiCount = try container.decode(Int.self, forKey: .notiCount)
        repos = try container.decode([WorkbranchRepo].self, forKey: .repos)
    }
}

public struct WorkbranchRepo: Codable, Equatable, Sendable {
    public let name: String
    public let branch: String
    public let dirty: Bool

    public init(name: String, branch: String, dirty: Bool) {
        self.name = name
        self.branch = branch
        self.dirty = dirty
    }
}


public struct WorkbranchChecklistItem: Codable, Equatable, Sendable {
    public let text: String
    public let checked: Bool
    public let depth: Int

    public init(text: String, checked: Bool, depth: Int) {
        self.text = text
        self.checked = checked
        self.depth = depth
    }
}
