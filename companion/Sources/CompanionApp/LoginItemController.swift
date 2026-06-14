import CompanionCore
import ServiceManagement

struct SMAppServiceLoginItemController: LoginItemControlling {
    private let service: SMAppService

    init(service: SMAppService = SMAppService.mainApp) {
        self.service = service
    }

    var status: LoginItemStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
