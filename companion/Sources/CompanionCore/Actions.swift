import Foundation

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
}
