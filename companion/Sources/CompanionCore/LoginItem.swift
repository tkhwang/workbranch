import Foundation

public enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

public enum LoginItemToggleOutcome {
    public static func resolve(
        requested: Bool,
        statusAfter: LoginItemStatus,
        errorDescription: String? = nil
    ) -> (launchAtLogin: Bool, message: String) {
        switch statusAfter {
        case .enabled:
            return (true, "Launch at login enabled")
        case .requiresApproval:
            return (false, "Approve workbranch in System Settings > General > Login Items")
        case .notRegistered:
            if !requested {
                return (false, "Launch at login disabled")
            }
            if let errorDescription {
                return (false, "Launch at login failed: \(errorDescription)")
            }
            return (false, "Launch at login unavailable; check System Settings > General > Login Items")
        case .notFound:
            if let errorDescription {
                return (false, "Launch at login failed: \(errorDescription)")
            }
            return (false, "Launch at login unavailable; check System Settings > General > Login Items")
        }
    }
}
