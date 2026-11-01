import ServiceManagement
import Testing
@testable import EdgeControl

@MainActor
struct LaunchAtLoginTests {
    @Test func initializationAndStatusReadsNeverRegisterAnything() {
        let service = RecordingService()
        let setting = LaunchAtLogin(service: service)
        #expect(setting.isEnabled == false)
        #expect(setting.isRegistered == false)
        #expect(!setting.statusText.isEmpty)
        #expect(service.operations.isEmpty)
    }

    @Test func pendingApprovalIsRegisteredButNotEnabledAndDoesNotRegisterAgain() throws {
        let service = RecordingService()
        service.registrationStatus = .requiresApproval
        let setting = LaunchAtLogin(service: service)
        try setting.setEnabled(true)
        #expect(setting.isEnabled == false)
        #expect(setting.isRegistered)
        #expect(setting.status == .requiresApproval)
        #expect(!setting.statusText.isEmpty)
        try setting.setEnabled(true)
        #expect(service.operations == ["register"])
        service.status = .enabled
        #expect(setting.isEnabled)
        try setting.setEnabled(true)
        #expect(service.operations == ["register"])
    }

    @Test func unregistersPendingApprovalAndAlreadyDisabledIsANoOp() throws {
        let service = RecordingService()
        service.status = .requiresApproval
        let setting = LaunchAtLogin(service: service)
        try setting.setEnabled(false)
        #expect(service.operations == ["unregister"])
        #expect(setting.isRegistered == false)
        #expect(setting.isEnabled == false)
        try setting.setEnabled(false)
        #expect(service.operations == ["unregister"])
    }

    @Test func serviceErrorsAreVisibleAndDoNotCreateASeparateEnabledFlag() throws {
        let service = RecordingService()
        let setting = LaunchAtLogin(service: service)
        service.fail = true
        #expect(throws: ServiceFailure.self) { try setting.setEnabled(true) }
        #expect(setting.isEnabled == false)
        #expect(setting.isRegistered == false)
        service.status = .enabled
        #expect(setting.isEnabled)
        #expect(throws: ServiceFailure.self) { try setting.setEnabled(false) }
        #expect(setting.isEnabled)
        service.fail = false
        try setting.setEnabled(false)
        #expect(setting.isEnabled == false)
    }

    private enum ServiceFailure: Error { case requested }

    private final class RecordingService: LoginItemService {
        var status: SMAppService.Status = .notRegistered
        var registrationStatus: SMAppService.Status = .enabled
        var operations: [String] = []
        var fail = false

        func register() throws {
            operations.append("register")
            if fail { throw ServiceFailure.requested }
            status = registrationStatus
        }

        func unregister() throws {
            operations.append("unregister")
            if fail { throw ServiceFailure.requested }
            status = .notRegistered
        }
    }
}
