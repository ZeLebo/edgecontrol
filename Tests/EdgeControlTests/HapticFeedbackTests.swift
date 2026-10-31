import Testing
@testable import EdgeControl

struct HapticFeedbackTests {
    @Test func changedLevelsAreImmediateButDuplicatesAndFastUpdatesAreNotQueued() {
        var gate = HapticFeedbackGate()
        #expect(gate.acceptLevel(50, enabled: true, at: 0) == true)
        #expect(gate.acceptLevel(50, enabled: true, at: 1) == false)
        #expect(gate.acceptLevel(51, enabled: true, at: 0.01) == false)
        #expect(gate.acceptLevel(51, enabled: true, at: 0.1) == false)
        #expect(gate.acceptLevel(52, enabled: true, at: 0.1) == true)
        #expect(gate.acceptAction(enabled: true, at: 0.11) == false)
        #expect(gate.acceptAction(enabled: true, at: 0.16) == true)
    }

    @Test func disabledOrInvalidRequestsDoNotConsumeTheFeedbackWindow() {
        var gate = HapticFeedbackGate()
        #expect(gate.acceptLevel(10, enabled: false, at: 0) == false)
        #expect(gate.acceptLevel(-1, enabled: true, at: 0) == false)
        #expect(gate.acceptAction(enabled: true, at: .nan) == false)
        #expect(gate.acceptAction(enabled: true, at: .infinity) == false)
        #expect(gate.acceptAction(enabled: true, at: -1) == false)
        #expect(gate.acceptLevel(11, enabled: true, at: 0) == true)
        #expect(gate.acceptAction(enabled: true, at: -0.1) == false)
        #expect(gate.acceptAction(enabled: true, at: 0.1) == true)
    }
}
