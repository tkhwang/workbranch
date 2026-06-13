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

public struct CompanionConfig: Equatable, Sendable {
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
        let text = try String(contentsOf: url, encoding: .utf8)
        var roots: [String] = []
        var workbranchBin: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("workbranchBin:") {
                let value = String(line.dropFirst("workbranchBin:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { workbranchBin = value }
                continue
            }
            guard line.hasPrefix("- ") else { continue }
            let root = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard root.hasPrefix("/") else { throw CompanionConfigError.rootMustBeAbsolute(root) }
            roots.append(root)
        }
        return try CompanionConfig(roots: roots, workbranchBin: workbranchBin)
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

    public func removingRoot(_ root: String) throws -> CompanionConfig {
        try CompanionConfig(roots: roots.filter { $0 != root }, workbranchBin: workbranchBin)
    }

    public func write(to url: URL) throws {
        var lines: [String] = ["# workbranch companion projects", ""]
        if let workbranchBin { lines.append("workbranchBin: \(workbranchBin)"); lines.append("") }
        lines.append("## projects")
        for root in roots { lines.append("- \(root)") }
        lines.append("")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
