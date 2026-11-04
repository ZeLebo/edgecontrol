import AppKit
import Testing
@testable import EdgeControl

@MainActor
struct ApplicationRecoveryTests {
    @Test(arguments: [
        "Output does not support volume control",
        "Output does not support mute control",
        "Audio output changed",
        "Could not set volume, channel 0 (CoreAudio -1)",
    ])
    func audioFailureDoesNotPauseGestures(_ message: String) throws {
        try withController { controller in
            controller.handleGestureError(AudioOutputError(message))
            #expect(controller.isPaused == false)
            #expect(controller.controlErrors[.volume] == message)
        }
    }

    @Test func trackpadFailureStillPausesGestures() throws {
        try withController { controller in
            controller.handleGestureError(TrackpadInputError.invalidFrame)
            #expect(controller.isPaused)
            #expect(controller.controlErrors.isEmpty)
        }
    }

    private func withController(_ body: (ApplicationController) -> Void) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let suite = "EdgeControlTests.ApplicationRecovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, previousDefaults: nil)
        // Do not launch the delegate: no input hooks, output transports or menu are started.
        body(ApplicationController(diagnostic: false, settings: settings))
    }
}
