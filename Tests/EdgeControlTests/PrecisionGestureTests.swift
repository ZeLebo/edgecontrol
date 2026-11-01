import Testing
@testable import EdgeControl

private struct PrecisionInput {
    var gesture = EdgeGesture()
    var settings = EdgeSettings.defaults
    var time = 0.0

    mutating func send(_ contacts: [TrackpadContact], precision: Bool = false) -> GestureUpdate {
        time += 0.01
        return gesture.process(TrackpadFrame(timestamp: time, contacts: contacts), settings: settings, precision: precision)
    }

    mutating func along(_ edge: TrackpadEdge = .bottom, at value: Double, precision: Bool = false) -> GestureUpdate {
        let contact: TrackpadContact
        switch edge {
        case .top: contact = TrackpadContact(id: 1, x: value, y: 0.98)
        case .right: contact = TrackpadContact(id: 1, x: 0.98, y: value)
        case .bottom: contact = TrackpadContact(id: 1, x: value, y: 0.02)
        case .left: contact = TrackpadContact(id: 1, x: 0.02, y: value)
        }
        return send([contact], precision: precision)
    }

    mutating func begin(_ edge: TrackpadEdge = .bottom, at value: Double = 0.3, precision: Bool = false) {
        #expect(send([], precision: precision) == .inactive)
        #expect(along(edge, at: value, precision: precision) == .inactive)
    }
}

private func precisionApply(_ update: GestureUpdate, to levels: inout LevelAccumulator) throws -> Int? {
    guard case let .active(_, _, change?) = update else { return nil }
    return try levels.apply(change)
}

private func expectPrecisionDelta(_ update: GestureUpdate, _ expected: Double) {
    guard case let .active(_, _, .relative(delta)) = update else {
        Issue.record("Expected relative precision movement")
        return
    }
    #expect(abs(delta - expected) < 1e-10)
}

@Suite("Shift precision")
struct PrecisionGestureTests {
    @Test func absolutePrecisionStartsFromTheActualLevelAtAnyTouchPosition() throws {
        for action in [EdgeAction.volume, .brightness, .keyboardBrightness] {
            for start in [0.2, 0.6] {
                var input = PrecisionInput()
                input.settings.bottom.action = action
                var levels = LevelAccumulator()
                // The application supplies the current output reading when the first change is relative.
                try levels.start(at: 70)
                input.begin(at: start, precision: true)
                let first = input.along(at: start + 0.05, precision: true)
                expectPrecisionDelta(first, 1)
                #expect(try precisionApply(first, to: &levels) == 71)
                #expect(try precisionApply(input.along(at: start - 0.05, precision: true), to: &levels) == 69)
            }
        }
    }

    @Test func precisionKeepsThePhysicalActivationThresholdAndStationaryTouchDoesNothing() {
        var input = PrecisionInput()
        input.begin(precision: true)
        #expect(input.along(at: 0.3, precision: true) == .inactive)
        #expect(input.along(at: 0.319999, precision: true) == .inactive)
        expectPrecisionDelta(input.along(at: 0.32, precision: true), 0.4)
        #expect(input.along(at: 0.32, precision: false) == .active(edge: .bottom, action: .volume, change: nil))
    }

    @Test func configuredRelativeModeChangesSpeedFromEachPreviousCoordinate() throws {
        var input = PrecisionInput()
        input.settings.bottom.mode = .relative
        input.begin(precision: true)
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        #expect(try precisionApply(input.along(at: 0.4, precision: true), to: &levels) == 72)
        #expect(try precisionApply(input.along(at: 0.45), to: &levels) == 77)
        #expect(try precisionApply(input.along(at: 0.5, precision: true), to: &levels) == 78)
        #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: nil))
        #expect(try precisionApply(input.along(at: 0.55), to: &levels) == 83)
    }

    @Test func pressingShiftDuringAbsoluteControlUsesTheLastAcceptedLevelWithoutJumping() throws {
        var input = PrecisionInput()
        input.begin()
        var levels = LevelAccumulator()
        #expect(try precisionApply(input.along(at: 0.5), to: &levels) == 50)
        #expect(input.along(at: 0.5, precision: true) == .active(edge: .bottom, action: .volume, change: nil))
        #expect(try precisionApply(input.along(at: 0.55, precision: true), to: &levels) == 51)
        #expect(input.along(at: 0.55) == .active(edge: .bottom, action: .volume, change: nil))
        let released = input.along(at: 0.6)
        expectPrecisionDelta(released, 5)
        #expect(try precisionApply(released, to: &levels) == 56)
        #expect(try precisionApply(input.along(at: 0.65, precision: true), to: &levels) == 57)
    }

    @Test func releasingShiftRestoresNormalSpeedAndKeepsTheRelativeOverrideUntilLift() throws {
        var input = PrecisionInput()
        input.begin(precision: true)
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        #expect(try precisionApply(input.along(at: 0.35, precision: true), to: &levels) == 71)
        #expect(try precisionApply(input.along(at: 0.4), to: &levels) == 76)
        #expect(try precisionApply(input.along(at: 0.42), to: &levels) == 78)
        #expect(input.send([]) == .inactive)
        #expect(input.along(at: 0.1) == .inactive)
        #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: .absolute(50)))
    }

    @Test func precisionFactorCombinesWithSensitivityOnEveryEdge() {
        for edge in TrackpadEdge.allCases {
            for sensitivity in [0.25, 1, 3] {
                var input = PrecisionInput()
                for side in TrackpadEdge.allCases { input.settings[side].action = .disabled }
                input.settings[edge] = EdgeConfiguration(action: .brightness, mode: .relative, sensitivity: sensitivity)
                input.begin(edge, precision: true)
                expectPrecisionDelta(input.along(edge, at: 0.4, precision: true), 2 * sensitivity)
                expectPrecisionDelta(input.along(edge, at: 0.5), 10 * sensitivity)
            }
        }
    }

    @Test func mediaGesturesUseTheSamePrecisionFactorWithoutAbsoluteControl() {
        for action in [EdgeAction.tracks, .seek] {
            var input = PrecisionInput()
            input.settings.bottom = EdgeConfiguration(action: action, mode: .absolute, sensitivity: 2)
            input.begin(precision: true)
            expectPrecisionDelta(input.along(at: 0.4, precision: true), 4)
            expectPrecisionDelta(input.along(at: 0.5), 20)
            expectPrecisionDelta(input.along(at: 0.4, precision: true), -4)
        }
    }

    @Test func fractionalPrecisionMovementsAccumulateWithoutPerFrameRounding() throws {
        var input = PrecisionInput()
        input.settings.bottom.mode = .relative
        input.begin(precision: true)
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        #expect(try precisionApply(input.along(at: 0.32, precision: true), to: &levels) == 70)
        var result: Int?
        for step in 1...100 {
            result = try precisionApply(input.along(at: 0.32 + Double(step) * 0.0001, precision: true), to: &levels)
        }
        #expect(result == 71)
    }

    @Test func invalidContactsCancelPrecisionAndClearTheOverrideBeforeTheNextGesture() {
        let interruptions = [
            [TrackpadContact(id: 1, x: .nan, y: 0.02)],
            [TrackpadContact(id: 1, x: 0.5, y: 0.06)],
            [TrackpadContact(id: 2, x: 0.5, y: 0.02)],
            [TrackpadContact(id: 1, x: 0.5, y: 0.02), TrackpadContact(id: 2, x: 0.6, y: 0.02)],
        ]
        for contacts in interruptions {
            var input = PrecisionInput()
            input.begin(precision: true)
            expectPrecisionDelta(input.along(at: 0.4, precision: true), 2)
            #expect(input.send(contacts) == .inactive)
            #expect(input.along(at: 0.6) == .inactive)
            input.begin(at: 0.1)
            #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: .absolute(50)))
        }
    }

    @Test func invalidTimestampsCancelAndClearThePrecisionOverride() {
        for timestamp in [Double.nan, Double.infinity, -1, 0.03] {
            var input = PrecisionInput()
            input.begin(precision: true)
            expectPrecisionDelta(input.along(at: 0.4, precision: true), 2)
            let bad = TrackpadFrame(timestamp: timestamp, contacts: [TrackpadContact(id: 1, x: 0.5, y: 0.02)])
            #expect(input.gesture.process(bad, settings: input.settings) == .inactive)
            #expect(input.along(at: 0.6) == .inactive)
            input.begin(at: 0.1)
            #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: .absolute(50)))
        }
    }

    @Test func resetAndSettingsChangesClearThePrecisionOverrideUntilFullLift() {
        for reset in [false, true] {
            var input = PrecisionInput()
            input.begin(precision: true)
            expectPrecisionDelta(input.along(at: 0.4, precision: true), 2)
            if reset { #expect(input.gesture.reset() == .inactive) }
            else {
                input.settings.bottom.sensitivity = 2
                #expect(input.along(at: 0.5) == .inactive)
            }
            #expect(input.along(at: 0.6) == .inactive)
            input.begin(at: 0.1)
            #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: .absolute(50)))
        }
    }

    @Test func shiftBeforeActivationDoesNotLatchIfItIsReleasedBeforeSliding() {
        var input = PrecisionInput()
        input.begin(precision: true)
        #expect(input.along(at: 0.31, precision: true) == .inactive)
        #expect(input.along(at: 0.31) == .inactive)
        #expect(input.along(at: 0.5) == .active(edge: .bottom, action: .volume, change: .absolute(50)))
    }
}
