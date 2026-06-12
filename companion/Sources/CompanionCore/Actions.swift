import Foundation

public enum ActionError: Error, CustomStringConvertible, Equatable {
    case invalidTaskName(String)

    public var description: String {
        switch self {
        case .invalidTaskName(let value): return "invalid task name: \(value)"
        }
    }
}

public struct TaskNameValidator: Sendable {
    private static let conventionalPrefixes: Set<String> = ["feat", "fix", "chore", "docs", "refactor", "test", "perf", "ci", "build", "revert"]
    private static let safeScalars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    public static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        guard !value.contains("/") else { return false }
        guard value.rangeOfCharacter(from: safeScalars.inverted) == nil else { return false }
        if let dash = value.firstIndex(of: "-") {
            let prefix = String(value[..<dash])
            if conventionalPrefixes.contains(prefix) {
                let detail = String(value[value.index(after: dash)...])
                return !detail.isEmpty && detail.rangeOfCharacter(from: safeScalars.inverted) == nil
            }
        }
        return true
    }

    public static func validate(_ value: String) throws {
        guard isValid(value) else { throw ActionError.invalidTaskName(value) }
    }
}

public struct ExternalCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let cwd: String?
    public let standardInput: String?
    public let detached: Bool

    public init(executable: String, arguments: [String], cwd: String? = nil, standardInput: String? = nil, detached: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.cwd = cwd
        self.standardInput = standardInput
        self.detached = detached
    }
}

public struct ActionBuilder: Sendable {
    public let workbranchBin: String

    public init(workbranchBin: String) {
        self.workbranchBin = workbranchBin
    }

    public func editMemo(root: String, task: String, text: String) -> ExternalCommand {
        let args = text.isEmpty ? ["memo", task, "--clear"] : ["memo", task, text]
        return ExternalCommand(executable: workbranchBin, arguments: args, cwd: root)
    }

    public func clearNotifications(root: String, task: String) -> ExternalCommand {
        ExternalCommand(executable: workbranchBin, arguments: ["noti", "clear", task], cwd: root)
    }

    public func openTerminal(root: String, task: String) -> ExternalCommand {
        ExternalCommand(executable: workbranchBin, arguments: ["terminal", task], cwd: root)
    }

    public func openIDE(root: String, task: String) -> ExternalCommand {
        ExternalCommand(executable: workbranchBin, arguments: ["ide", task], cwd: root)
    }

    public func revealFinder(root: String, task: String) -> ExternalCommand {
        ExternalCommand(executable: workbranchBin, arguments: ["finder", task], cwd: root)
    }

    public func copyPath(_ path: String) -> ExternalCommand {
        ExternalCommand(executable: "/usr/bin/pbcopy", arguments: [], standardInput: path)
    }

    public func add(root: String, task: String) -> ExternalCommand {
        ExternalCommand(executable: workbranchBin, arguments: ["add", task], cwd: root, detached: true)
    }

    public func validatedAdd(root: String, task: String) throws -> ExternalCommand {
        try TaskNameValidator.validate(task)
        return add(root: root, task: task)
    }
}
