import Foundation

public enum CompanionConfigError: Error, CustomStringConvertible, Equatable {
    case rootMustBeAbsolute(String)
    case workbranchBinMustBeAbsolute(String)

    public var description: String {
        switch self {
        case .rootMustBeAbsolute(let root): return "config root must be absolute: \(root)"
        case .workbranchBinMustBeAbsolute(let path): return "workbranchBin must be absolute: \(path)"
        }
    }
}

public struct CompanionConfig: Codable, Equatable, Sendable {
    public let roots: [String]
    public let workbranchBin: String?

    public init(roots: [String], workbranchBin: String? = nil) throws {
        for root in roots where !root.hasPrefix("/") {
            throw CompanionConfigError.rootMustBeAbsolute(root)
        }
        if let workbranchBin, !workbranchBin.hasPrefix("/") {
            throw CompanionConfigError.workbranchBinMustBeAbsolute(workbranchBin)
        }
        self.roots = roots
        self.workbranchBin = workbranchBin
    }

    public static func load(from url: URL) throws -> CompanionConfig {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(RawConfig.self, from: data)
        return try CompanionConfig(roots: decoded.roots, workbranchBin: decoded.workbranchBin)
    }

    public static func initSkeleton(currentDirectory: URL) -> CompanionConfig {
        let configFile = currentDirectory.appendingPathComponent(".workbranch.config")
        if FileManager.default.fileExists(atPath: configFile.path), let config = try? CompanionConfig(roots: [currentDirectory.path]) {
            return config
        }
        return try! CompanionConfig(roots: [])
    }

    public static func ensureGUIConfig(at url: URL) throws -> CompanionConfig {
        if FileManager.default.fileExists(atPath: url.path) {
            return try load(from: url)
        }
        let config = try CompanionConfig(roots: [])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.write(to: url)
        return config
    }

    public func write(to url: URL) throws {
        let raw = RawConfig(roots: roots, workbranchBin: workbranchBin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(raw)
        try data.write(to: url)
    }
}

private struct RawConfig: Codable {
    let roots: [String]
    let workbranchBin: String?

    init(roots: [String], workbranchBin: String?) {
        self.roots = roots
        self.workbranchBin = workbranchBin
    }
}
