import Testing
@testable import EdgeControl

@MainActor
struct HapticFeedbackTests {
    @Test func levelRequestsUseBoundedStrengthAtEveryBoundary() throws {
        let clock = Clock()
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { clock.time })
        try feedback.start(deviceID: 0x1234_5678_9abc_def0)
        for percent in [0, 33, 34, 66, 67, 100] {
            try feedback.levelChanged(to: percent, enabled: true)
            clock.time += 0.1
        }
        #expect(transport.deviceIDs == [0x1234_5678_9abc_def0])
        #expect(transport.requests == [.weak, .weak, .medium, .medium, .strong, .strong])
    }

    @Test func discreteActionsUseTheSameTransportWithFixedMediumStrength() throws {
        let clock = Clock()
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { clock.time })
        try feedback.start(deviceID: 42)
        try feedback.levelChanged(to: 100, enabled: true)
        clock.time = 0.1
        try feedback.actionPerformed(enabled: true)
        clock.time = 0.2
        try feedback.actionPerformed(enabled: true)
        #expect(transport.requests == [.strong, .medium, .medium])
    }

    @Test func disabledRequestsDoNotReachTheActuator() throws {
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { 1 })
        try feedback.start(deviceID: 42)
        try feedback.levelChanged(to: 50, enabled: false)
        try feedback.actionPerformed(enabled: false)
        try feedback.levelChanged(to: -1, enabled: true)
        try feedback.levelChanged(to: 101, enabled: true)
        #expect(transport.requests.isEmpty)
    }

    @Test func failedActuationIsVisibleAndDoesNotConsumeTheLevelOrFeedbackWindow() throws {
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { 1 })
        try feedback.start(deviceID: 42)
        transport.failActuation = true
        #expect(throws: TransportFailure.self) { try feedback.levelChanged(to: 70, enabled: true) }
        transport.failActuation = false
        try feedback.levelChanged(to: 70, enabled: true)
        #expect(transport.requests == [.strong, .strong])
        #expect(transport.successes == [.strong])
    }

    @Test func failedActionsCanBeRetriedWithoutWaitingForAConsumedWindow() throws {
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { 1 })
        try feedback.start(deviceID: 42)
        transport.failActuation = true
        #expect(throws: TransportFailure.self) { try feedback.actionPerformed(enabled: true) }
        transport.failActuation = false
        try feedback.actionPerformed(enabled: true)
        #expect(transport.successes == [.medium])
    }

    @Test func readinessTracksStartStopAndFailuresWhileResetOnlyClearsTheGate() throws {
        let transport = RecordingTransport()
        let feedback = HapticFeedback(transport: transport, now: { 1 })
        #expect(feedback.isReady == false)
        #expect(throws: HapticFeedbackError.self) { try feedback.actionPerformed(enabled: true) }
        transport.failStart = true
        #expect(throws: TransportFailure.self) { try feedback.start(deviceID: 42) }
        #expect(feedback.isReady == false)
        transport.failStart = false
        try feedback.start(deviceID: 43)
        #expect(feedback.isReady)
        try feedback.levelChanged(to: 50, enabled: true)
        feedback.reset()
        #expect(feedback.isReady)
        #expect(transport.stopCount == 0)
        try feedback.levelChanged(to: 50, enabled: true)
        #expect(transport.successes == [.medium, .medium])
        transport.failStop = true
        #expect(throws: TransportFailure.self) { try feedback.stop() }
        #expect(feedback.isReady == false)
    }

    @Test func changedLevelsAreImmediateButDuplicatesAndFastUpdatesAreNotQueued() {
        var gate = HapticFeedbackGate()
        #expect(gate.acceptLevel(50, enabled: true, at: 0) == true)
        #expect(gate.acceptLevel(50, enabled: true, at: 1) == false)
        #expect(gate.acceptLevel(51, enabled: true, at: 0.01) == false)
        #expect(gate.acceptLevel(51, enabled: true, at: 0.1) == false)
        #expect(gate.acceptLevel(52, enabled: true, at: 0.1) == true)
        #expect(gate.acceptAction(enabled: true, at: 0.15) == false)
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
        #expect(gate.acceptAction(enabled: true, at: 0.05) == false)
        #expect(gate.acceptAction(enabled: true, at: 0.051) == true)
    }

    private final class Clock { var time = 0.0 }

    private enum TransportFailure: Error { case requested }

    private final class RecordingTransport: HapticTransport {
        var deviceIDs: [UInt64] = []
        var requests: [HapticWaveform] = []
        var successes: [HapticWaveform] = []
        var stopCount = 0
        var failStart = false
        var failActuation = false
        var failStop = false

        func start(deviceID: UInt64) throws {
            deviceIDs.append(deviceID)
            if failStart { throw TransportFailure.requested }
        }

        func actuate(_ waveform: HapticWaveform) throws {
            requests.append(waveform)
            if failActuation { throw TransportFailure.requested }
            successes.append(waveform)
        }

        func stop() throws {
            stopCount += 1
            if failStop { throw TransportFailure.requested }
        }
    }
}
