import Foundation

public struct EventFilter: Sendable {
    public init() {}

    public func shouldRefresh(forPath path: String, root: String) -> Bool {
        guard path == root || path.hasPrefix(root + "/") else { return false }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return true }
        let parts = relative.split(separator: "/").map(String.init)
        return !parts.contains(".git")
    }
}

public struct DebounceScheduler: Sendable {
    public let delay: TimeInterval
    private var pending: [String: TimeInterval] = [:]

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    public mutating func record(root: String, at time: TimeInterval) {
        pending[root] = time + delay
    }

    public mutating func dueRoots(at time: TimeInterval) -> [String] {
        let due = pending
            .filter { $0.value <= time }
            .map { $0.key }
            .sorted()
        for root in due { pending.removeValue(forKey: root) }
        return due
    }
}

public enum RefreshCompletion: Equatable, Sendable {
    case idle
    case runAgain
}

public struct RefreshCoordinator: Sendable {
    private struct RootState: Sendable {
        var inFlight = false
        var pending = false
    }

    private var states: [String: RootState] = [:]

    public init() {}

    public mutating func begin(root: String) -> Bool {
        var state = states[root, default: RootState()]
        guard !state.inFlight else {
            state.pending = true
            states[root] = state
            return false
        }
        state.inFlight = true
        states[root] = state
        return true
    }

    public mutating func markPending(root: String) {
        var state = states[root, default: RootState()]
        state.pending = true
        states[root] = state
    }

    public mutating func finish(root: String) -> RefreshCompletion {
        var state = states[root, default: RootState()]
        if state.pending {
            state.inFlight = false
            state.pending = false
            states[root] = state
            return .runAgain
        }
        states[root] = RootState()
        return .idle
    }
}
