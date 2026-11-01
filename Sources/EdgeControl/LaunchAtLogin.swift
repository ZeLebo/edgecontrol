import ServiceManagement

@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
final class LaunchAtLogin {
    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        self.service = service ?? SMAppService.mainApp
    }

    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { status == .enabled }
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    var statusText: String {
        switch status {
        case .notRegistered: "Does not launch at login."
        case .enabled: "Launches automatically when you log in."
        case .requiresApproval: "Allow EdgeControl in System Settings > General > Login Items."
        case .notFound: "Launch at Login is unavailable. Open the built application and try again."
        @unknown default: "Launch at Login status is unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isRegistered else { return }
            try service.register()
        } else {
            guard status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
