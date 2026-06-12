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
    public let notiCount: Int
    public let repos: [WorkbranchRepo]
}

public struct WorkbranchRepo: Codable, Equatable, Sendable {
    public let name: String
    public let branch: String
    public let dirty: Bool
}
