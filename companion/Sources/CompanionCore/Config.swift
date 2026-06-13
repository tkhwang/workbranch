import Foundation

public enum CompanionConfigError: Error, CustomStringConvertible, Equatable {
    case rootMustBeAbsolute(String)
    case workbranchBinMustBeAbsolute(String)
    case fontSizeMustBePositive(String)
    case unsupportedColorTheme(String)

    public var description: String {
        switch self {
        case .rootMustBeAbsolute(let root): return "config root must be absolute: \(root)"
        case .workbranchBinMustBeAbsolute(let path): return "workbranchBin must be absolute: \(path)"
        case .fontSizeMustBePositive(let value): return "fontSize must be a positive number: \(value)"
        case .unsupportedColorTheme(let value): return "unsupported colorTheme: \(value)"
        }
    }
}

public enum CompanionColorTheme: String, CaseIterable, Equatable, Sendable {
    case dracula
    case matrix
    case amber
    case nord
    case solarized

    public static let `default`: CompanionColorTheme = .dracula

    public static func parse(_ value: String) -> CompanionColorTheme? {
        switch value.lowercased() {
        case "green": return .matrix
        case "blue": return .nord
        default: return CompanionColorTheme(rawValue: value.lowercased())
        }
    }

    public var label: String {
        switch self {
        case .dracula: return "Dracula"
        case .matrix: return "Matrix"
        case .amber: return "Amber"
        case .nord: return "Nord"
        case .solarized: return "Solarized"
        }
    }
}

public struct CompanionFontSettings: Equatable, Sendable {
    public static let `default` = CompanionFontSettings(name: "Menlo", size: 13)

    public let name: String
    public let size: Double

    public init(name: String, size: Double) {
        self.name = name
        self.size = size
    }
}

public struct CompanionConfig: Equatable, Sendable {
    public let roots: [String]
    public let workbranchBin: String?
    public let font: CompanionFontSettings
    public let colorTheme: CompanionColorTheme

    public init(
        roots: [String],
        workbranchBin: String? = nil,
        font: CompanionFontSettings = .default,
        colorTheme: CompanionColorTheme = .default
    ) throws {
        for root in roots where !root.hasPrefix("/") {
            throw CompanionConfigError.rootMustBeAbsolute(root)
        }
        if let workbranchBin, !workbranchBin.hasPrefix("/") {
            throw CompanionConfigError.workbranchBinMustBeAbsolute(workbranchBin)
        }
        self.roots = roots
        self.workbranchBin = workbranchBin
        self.font = font
        self.colorTheme = colorTheme
    }

    public static func load(from url: URL) throws -> CompanionConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        var roots: [String] = []
        var workbranchBin: String?
        var fontName = CompanionFontSettings.default.name
        var fontSize = CompanionFontSettings.default.size
        var colorTheme = CompanionColorTheme.default
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("workbranchBin:") {
                let value = String(line.dropFirst("workbranchBin:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { workbranchBin = value }
                continue
            }
            if line.hasPrefix("fontName:") {
                let value = String(line.dropFirst("fontName:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { fontName = value }
                continue
            }
            if line.hasPrefix("fontSize:") {
                let value = String(line.dropFirst("fontSize:".count)).trimmingCharacters(in: .whitespaces)
                guard let parsed = Double(value), parsed > 0 else { throw CompanionConfigError.fontSizeMustBePositive(value) }
                fontSize = parsed
                continue
            }
            if line.hasPrefix("colorTheme:") {
                let value = String(line.dropFirst("colorTheme:".count)).trimmingCharacters(in: .whitespaces)
                guard let parsed = CompanionColorTheme.parse(value) else {
                    throw CompanionConfigError.unsupportedColorTheme(value)
                }
                colorTheme = parsed
                continue
            }
            guard line.hasPrefix("- ") else { continue }
            let root = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard root.hasPrefix("/") else { throw CompanionConfigError.rootMustBeAbsolute(root) }
            roots.append(root)
        }
        return try CompanionConfig(
            roots: roots,
            workbranchBin: workbranchBin,
            font: CompanionFontSettings(name: fontName, size: fontSize),
            colorTheme: colorTheme
        )
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
        try CompanionConfig(roots: roots.filter { $0 != root }, workbranchBin: workbranchBin, font: font, colorTheme: colorTheme)
    }

    public func write(to url: URL) throws {
        var lines: [String] = ["# workbranch companion projects", ""]
        if let workbranchBin { lines.append("workbranchBin: \(workbranchBin)"); lines.append("") }
        lines.append("fontName: \(font.name)")
        lines.append("fontSize: \(formatFontSize(font.size))")
        lines.append("colorTheme: \(colorTheme.rawValue)")
        lines.append("")
        lines.append("## projects")
        for root in roots { lines.append("- \(root)") }
        lines.append("")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func formatFontSize(_ size: Double) -> String {
        if size.rounded() == size { return String(Int(size)) }
        return String(size)
    }
}
