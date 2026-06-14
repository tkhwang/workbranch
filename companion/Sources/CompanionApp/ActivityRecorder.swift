import Foundation
import CompanionCore

struct ActivityRecorder {
    let url: URL
    private let fileManager: FileManager

    init(url: URL = ActivityRecorder.defaultLogURL(), fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    static func defaultLogURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base: URL
        if let xdg = environment["XDG_STATE_HOME"], !xdg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local").appendingPathComponent("state")
        }
        return base.appendingPathComponent("workbranch").appendingPathComponent("activity.jsonl")
    }

    func append(_ events: [ActivityEvent]) throws {
        guard !events.isEmpty else { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = try events.map { try $0.jsonLine() }.joined()
        guard let data = text.data(using: .utf8) else { return }
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func readEvents() -> [ActivityEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? ActivityEvent.decodeLine(String(line))
        }
    }
}
