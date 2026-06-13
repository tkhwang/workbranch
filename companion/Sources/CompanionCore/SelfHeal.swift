import Foundation

public enum ProjectRootAvailability: Equatable, Sendable {
    case available
    case trueDeletionCandidate
    case unavailable
}

public enum ProjectRootSelfHeal {
    public static func classify(root: String, fileManager: FileManager = .default) -> ProjectRootAvailability {
        if fileManager.fileExists(atPath: root) { return .available }
        let parent = URL(fileURLWithPath: root).deletingLastPathComponent().path
        if fileManager.fileExists(atPath: parent) { return .trueDeletionCandidate }
        return .unavailable
    }
}

public enum ProjectRootIdentity {
    public static func matches(configuredRoot: String, documentRoot: String) -> Bool {
        canonicalPath(configuredRoot) == canonicalPath(documentRoot)
    }

    public static func canonicalPath(_ root: String) -> String {
        URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
