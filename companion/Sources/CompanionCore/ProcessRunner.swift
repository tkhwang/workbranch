import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let result = data
        lock.unlock()
        return result
    }
}

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool

    public var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    public var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }

    public init(exitCode: Int32, stdout: Data, stderr: Data, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public struct ProcessRunner: Sendable {
    public let timeout: TimeInterval
    public let environment: [String: String]
    private let terminationGrace: TimeInterval = 0.5

    public init(timeout: TimeInterval, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.timeout = timeout
        self.environment = environment
    }

    public func run(
        executable: String,
        arguments: [String],
        cwd: String,
        standardInput: String? = nil,
        detached: Bool = false
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = environment

        if detached {
            process.standardOutput = nil
            process.standardError = nil
            try process.run()
            return CommandResult(exitCode: 0, stdout: Data(), stderr: Data(), timedOut: false)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }
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
            let terminationDeadline = Date().addingTimeInterval(terminationGrace)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                forceKill(process)
            }
        }
        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdoutBuffer.snapshot(),
            stderr: stderrBuffer.snapshot(),
            timedOut: timedOut
        )
    }

    private func forceKill(_ process: Process) {
        #if canImport(Darwin) || canImport(Glibc)
        kill(process.processIdentifier, SIGKILL)
        #else
        process.terminate()
        #endif
    }
}
