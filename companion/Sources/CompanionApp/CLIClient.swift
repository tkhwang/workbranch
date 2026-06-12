import Foundation
import CompanionCore

struct CommandResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool

    var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
}

struct CLIClient: Sendable {
    let workbranchBin: String
    let timeout: TimeInterval

    init(config: CompanionConfig, timeout: TimeInterval = 10) throws {
        self.workbranchBin = try Self.locateWorkbranch(configured: config.workbranchBin)
        self.timeout = timeout
    }

    static func locateWorkbranch(configured: String?) throws -> String {
        let candidates = ([configured].compactMap { $0 } + [
            "/opt/homebrew/bin/workbranch",
            "/usr/local/bin/workbranch",
            NSString(string: "~/.local/bin/workbranch").expandingTildeInPath,
        ])
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        throw CLIClientError.workbranchNotFound(candidates)
    }

    func listJSON(root: String) throws -> WorkbranchListDocument {
        let result = try run(arguments: ["list", "--json"], cwd: root)
        guard !result.timedOut else { throw CLIClientError.timeout("workbranch list --json timed out") }
        guard result.exitCode == 0 else {
            let message = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIClientError.commandFailed(message.isEmpty ? "workbranch list --json failed" : message)
        }
        do {
            return try WorkbranchListDocument.decode(result.stdout)
        } catch {
            throw CLIClientError.invalidJSON(String(describing: error))
        }
    }

    func run(arguments: [String], cwd: String, standardInput: String? = nil, detached: Bool = false) throws -> CommandResult {
        try run(executable: workbranchBin, arguments: arguments, cwd: cwd, standardInput: standardInput, detached: detached)
    }

    func run(command: ExternalCommand) throws -> CommandResult {
        try run(
            executable: command.executable,
            arguments: command.arguments,
            cwd: command.cwd ?? FileManager.default.currentDirectoryPath,
            standardInput: command.standardInput,
            detached: command.detached
        )
    }

    private func run(executable: String, arguments: [String], cwd: String, standardInput: String?, detached: Bool) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = augmentedEnvironment()

        if detached {
            process.standardOutput = nil
            process.standardError = nil
            try process.run()
            return CommandResult(exitCode: 0, stdout: Data(), stderr: Data(), timedOut: false)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if let standardInput {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            if let data = standardInput.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            try? input.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
            timedOut: timedOut
        )
    }

    private func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let additions = ["/opt/homebrew/bin", "/usr/local/bin", NSString(string: "~/.local/bin").expandingTildeInPath]
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (additions + [current]).joined(separator: ":")
        return env
    }
}

enum CLIClientError: Error, CustomStringConvertible {
    case workbranchNotFound([String])
    case timeout(String)
    case commandFailed(String)
    case invalidJSON(String)

    var description: String {
        switch self {
        case .workbranchNotFound(let candidates): return "workbranch binary not found. Checked: \(candidates.joined(separator: ", "))"
        case .timeout(let message): return message
        case .commandFailed(let message): return message
        case .invalidJSON(let message): return "invalid workbranch list --json: \(message)"
        }
    }
}
