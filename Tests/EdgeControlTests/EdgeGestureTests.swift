import Testing
@testable import EdgeControl

private struct Input {
    var gesture = EdgeGesture()
    var settings = EdgeSettings.defaults
    var time = 0.0

    mutating func send(_ contacts: [TrackpadContact]) -> GestureUpdate {
        time += 0.01
        return gesture.process(TrackpadFrame(timestamp: time, contacts: contacts), settings: settings)
    }

    mutating func finger(_ x: Double, y: Double = 0.02, id: Int32 = 1) -> GestureUpdate {
        send([TrackpadContact(id: id, x: x, y: y)])
    }

    mutating func along(_ edge: TrackpadEdge, at value: Double) -> GestureUpdate {
        switch edge {
        case .top: finger(value, y: 0.98)
        case .right: finger(0.98, y: value)
        case .bottom: finger(value)
        case .left: finger(0.02, y: value)
        }
    }

    mutating func begin(at x: Double = 0.1) {
        #expect(send([]) == .inactive)
        #expect(finger(x) == .inactive)
    }
}

private func level(_ percent: Int?, edge: TrackpadEdge = .bottom, action: EdgeAction = .volume) -> GestureUpdate {
    .active(edge: edge, action: action, change: percent.map(LevelChange.absolute))
}

private func disabledSettings() -> EdgeSettings {
    var settings = EdgeSettings.defaults
    for edge in TrackpadEdge.allCases { settings[edge] = EdgeConfiguration() }
    return settings
}

private func allVolumeSettings(width: Double) -> EdgeSettings {
    var settings = disabledSettings()
    settings.stripWidth = width
    for edge in TrackpadEdge.allCases { settings[edge].action = .volume }
    return settings
}

@Suite("Edge gestures")
struct EdgeGestureTests {
    @Test func absoluteScaleWorksFromBothDirections() {
        for start in [0.1, 0.9] {
            var input = Input()
            input.begin(at: start)
            #expect(input.finger(0.5) == level(50))
            #expect(input.finger(0.03) == level(0))
            #expect(input.finger(0) == level(nil))
            #expect(input.finger(0.97) == level(100))
            #expect(input.finger(1) == level(nil))
            #expect(input.finger(0.5) == level(50))
        }
    }

    @Test func activationThresholdAndStripBoundaryAreInclusive() {
        var input = Input()
        input.begin(at: 0.1)
        #expect(input.finger(0.119999, y: 0.05) == .inactive)
        #expect(input.finger(0.12, y: 0.05) == level(10))

        var left = Input()
        left.begin(at: 0.9)
        #expect(left.finger(0.880001) == .inactive)
        #expect(left.finger(0.88).isActive)
    }

    @Test func stationaryTouchAndEntryFromAboveDoNotActivate() {
        var input = Input()
        input.begin()
        #expect(input.finger(0.1) == .inactive)
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.2, y: 0.051) == .inactive)
        #expect(input.finger(0.5) == .inactive)
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.2) == .inactive)
        #expect(input.finger(0.5) == level(50))
    }

    @Test func startupAndResetWaitForFullLift() {
        var input = Input()
        #expect(input.finger(0.1) == .inactive)
        #expect(input.finger(0.8) == .inactive)
        input.begin()
        #expect(input.finger(0.5).isActive)
        #expect(input.gesture.reset() == .inactive)
        #expect(input.finger(0.8) == .inactive)
        #expect(input.finger(0.1) == .inactive)
        input.begin()
        #expect(input.finger(0.5) == level(50))
    }

    @Test func leavingStripOrChangingContactCancelsUntilLift() {
        for replacement in [
            [TrackpadContact(id: 1, x: 0.6, y: 0.050001)],
            [TrackpadContact(id: 2, x: 0.6, y: 0.02)],
            [TrackpadContact(id: 1, x: 0.6, y: 0.02), TrackpadContact(id: 2, x: 0.7, y: 0.8)],
        ] {
            var input = Input()
            input.begin()
            #expect(input.finger(0.5).isActive)
            #expect(input.send(replacement) == .inactive)
            #expect(input.finger(0.1) == .inactive)
            #expect(input.finger(0.8) == .inactive)
            input.begin()
            #expect(input.finger(0.5).isActive)
        }
    }

    @Test func twoFingerStartAndInterruptedCandidateDoNotActivate() {
        var input = Input()
        #expect(input.send([]) == .inactive)
        #expect(input.send([
            TrackpadContact(id: 1, x: 0.1, y: 0.02),
            TrackpadContact(id: 2, x: 0.8, y: 0.02),
        ]) == .inactive)
        #expect(input.finger(0.5) == .inactive)
        input.begin()
        #expect(input.finger(0.5, id: 2) == .inactive)
        #expect(input.finger(0.8, id: 2) == .inactive)
    }

    @Test func liftingEndsGestureAndNextGestureCanRepeatSamePercent() {
        var input = Input()
        input.begin()
        #expect(input.finger(0.5) == level(50))
        #expect(input.finger(0.50001) == level(nil))
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.9) == .inactive)
        #expect(input.finger(0.5) == level(50))
    }

    @Test func invalidCoordinatesCancelInsteadOfClamping() {
        for (x, y) in [
            (-0.01, 0.02), (1.01, 0.02), (Double.nan, 0.02),
            (Double.infinity, 0.02), (0.5, -0.01), (0.5, 1.01),
            (0.5, Double.nan), (0.5, -Double.infinity),
        ] {
            var input = Input()
            input.begin()
            #expect(input.finger(0.5).isActive)
            #expect(input.finger(x, y: y) == .inactive)
            #expect(input.finger(0.8) == .inactive)
            input.begin()
            #expect(input.finger(0.5).isActive)
        }
    }

    @Test func invalidOrOutOfOrderTimestampsCancel() {
        for time in [-1, Double.nan, Double.infinity, 0, 0.03] {
            var input = Input()
            input.begin()
            #expect(input.finger(0.5).isActive)
            #expect(input.gesture.process(TrackpadFrame(
                timestamp: time, contacts: [TrackpadContact(id: 1, x: 0.8, y: 0.02)]
            ), settings: input.settings) == .inactive)
            #expect(input.finger(0.8) == .inactive)
            input.begin()
            #expect(input.finger(0.5).isActive)
        }
    }

    @Test func allFourEdgesHaveTheSameAbsoluteOrientation() {
        for edge in TrackpadEdge.allCases {
            for action in [EdgeAction.volume, .brightness] {
                for start in [0.1, 0.9] {
                    var input = Input()
                    input.settings = disabledSettings()
                    input.settings[edge].action = action
                    #expect(input.send([]) == .inactive)
                    #expect(input.along(edge, at: start) == .inactive)
                    #expect(input.along(edge, at: 0.5) == level(50, edge: edge, action: action))
                    #expect(input.along(edge, at: 0.03) == level(0, edge: edge, action: action))
                    #expect(input.along(edge, at: 0.97) == level(100, edge: edge, action: action))
                }
            }
        }
    }

    @Test func disabledEdgesAndCenterStartsRemainInactive() {
        var input = Input()
        input.settings = disabledSettings()
        for edge in TrackpadEdge.allCases {
            #expect(input.send([]) == .inactive)
            #expect(input.along(edge, at: 0.1) == .inactive)
            #expect(input.along(edge, at: 0.5) == .inactive)
        }
        input.settings = .defaults
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.5, y: 0.5) == .inactive)
        #expect(input.finger(0.98, y: 0.6) == .inactive)
        #expect(input.finger(0.98, y: 0.9) == .inactive)
    }

    @Test func cornersChooseDominantMovementAndWaitOnTies() {
        var horizontal = Input()
        horizontal.begin(at: 0.98)
        #expect(horizontal.finger(0.95, y: 0.05) == .inactive)
        #expect(horizontal.finger(0.92, y: 0.05) == level(95))

        var vertical = Input()
        vertical.begin(at: 0.98)
        #expect(vertical.finger(0.96, y: 0.05) == level(2, edge: .right, action: .brightness))
    }

    @Test func activeCornerDoesNotSwitchToTheAdjacentAction() {
        var input = Input()
        input.begin(at: 0.9)
        #expect(input.finger(0.98) == level(100))
        #expect(input.finger(0.98, y: 0.04) == level(nil))
        #expect(input.finger(0.98, y: 0.08) == .inactive)
        #expect(input.finger(0.98, y: 0.8) == .inactive)
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.98, y: 0.1) == .inactive)
        #expect(input.finger(0.98, y: 0.5) == level(50, edge: .right, action: .brightness))
    }

    @Test func disabledCornerAxisDoesNotCompeteWithTheEnabledAxis() {
        var input = Input()
        input.settings.right.action = .disabled
        input.begin(at: 0.98)
        #expect(input.finger(0.96, y: 0.04) == level(99))
    }

    @Test func configuredWidthControlsAllFourStripBoundaries() {
        for edge in TrackpadEdge.allCases {
            var input = Input()
            input.settings = allVolumeSettings(width: 0.15)
            #expect(input.send([]) == .inactive)
            switch edge {
            case .bottom:
                #expect(input.finger(0.2, y: 0.15) == .inactive)
                #expect(input.finger(0.5, y: 0.15) == level(50, edge: edge))
                #expect(input.finger(0.6, y: 0.150001) == .inactive)
            case .top:
                #expect(input.finger(0.2, y: 0.85) == .inactive)
                #expect(input.finger(0.5, y: 0.85) == level(50, edge: edge))
                #expect(input.finger(0.6, y: 0.849999) == .inactive)
            case .left:
                #expect(input.finger(0.15, y: 0.2) == .inactive)
                #expect(input.finger(0.15, y: 0.5) == level(50, edge: edge))
                #expect(input.finger(0.150001, y: 0.6) == .inactive)
            case .right:
                #expect(input.finger(0.85, y: 0.2) == .inactive)
                #expect(input.finger(0.85, y: 0.5) == level(50, edge: edge))
                #expect(input.finger(0.849999, y: 0.6) == .inactive)
            }
        }
    }

    @Test func changingSettingsCancelsUntilLift() {
        for changeAction in [false, true] {
            var input = Input()
            input.begin()
            #expect(input.finger(0.5) == level(50))
            if changeAction { input.settings.bottom.action = .brightness } else { input.settings.stripWidth = 0.1 }
            #expect(input.finger(0.8) == .inactive)
            #expect(input.finger(0.1) == .inactive)
            input.begin()
            #expect(input.finger(0.5) == level(50, action: changeAction ? .brightness : .volume))
        }
    }

    @Test func invalidSettingsNeverActivate() {
        for width in [0.0, 0.029999, 0.150001, Double.nan, Double.infinity] {
            var input = Input()
            input.settings.stripWidth = width
            #expect(input.send([]) == .inactive)
            #expect(input.finger(0.1) == .inactive)
            #expect(input.finger(0.5) == .inactive)
        }
    }

    @Test func candidateCannotReenterAnEdgeItAlreadyLeft() {
        var input = Input()
        #expect(input.send([]) == .inactive)
        #expect(input.finger(0.96, y: 0.049) == .inactive)
        #expect(input.finger(0.96, y: 0.051) == .inactive)
        #expect(input.finger(0.93, y: 0.049) == .inactive)
        #expect(input.finger(0.5) == .inactive)
    }
}

@Suite("Relative edge adjustments")
struct RelativeEdgeGestureTests {
    @Test func currentSeventyIsAdjustedWithoutJumpingToTouchPosition() throws {
        for edge in TrackpadEdge.allCases {
            for start in [0.3, 0.6] {
                var input = Input()
                input.settings = disabledSettings()
                input.settings[edge] = EdgeConfiguration(action: .brightness, mode: .relative)
                var levels = LevelAccumulator()
                try levels.start(at: 70)
                #expect(input.send([]) == .inactive)
                #expect(input.along(edge, at: start) == .inactive)
                let first = input.along(edge, at: start + 0.03)
                #expect(try apply(first, to: &levels) == 73)
                #expect(try apply(input.along(edge, at: start + 0.1), to: &levels) == 80)
                #expect(try apply(input.along(edge, at: start), to: &levels) == 70)
            }
        }
    }

    @Test func smallFrameMovementsAccumulateWithoutPerFrameRounding() throws {
        var input = Input()
        input.settings.bottom.mode = .relative
        input.begin(at: 0.3)
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        #expect(try apply(input.finger(0.33), to: &levels) == 73)
        var result = 73
        for step in 1...100 {
            result = try #require(apply(input.finger(0.33 + Double(step) * 0.0001), to: &levels))
        }
        #expect(result == 74)
        #expect(input.finger(0.34) == .active(edge: .bottom, action: .volume, change: nil))
    }

    @Test func sensitivityIsIndependentForEachSideAndIgnoredByAbsoluteMode() throws {
        var settings = disabledSettings()
        settings.bottom = EdgeConfiguration(action: .volume, mode: .relative, sensitivity: 0.5)
        settings.right = EdgeConfiguration(action: .brightness, mode: .relative, sensitivity: 2)
        for (edge, expected) in [(TrackpadEdge.bottom, 72), (.right, 78)] {
            var input = Input(settings: settings)
            #expect(input.send([]) == .inactive)
            #expect(input.along(edge, at: 0.3) == .inactive)
            var levels = LevelAccumulator()
            try levels.start(at: 70)
            #expect(try apply(input.along(edge, at: 0.34), to: &levels) == expected)
        }
        var absolute = Input()
        absolute.settings.bottom.sensitivity = 3
        absolute.begin(at: 0.3)
        #expect(absolute.finger(0.5) == level(50))
    }

    @Test func changedModeOrSensitivityCancelsUntilLift() {
        for changeMode in [false, true] {
            var input = Input()
            input.begin()
            #expect(input.finger(0.5).isActive)
            if changeMode { input.settings.bottom.mode = .relative }
            else { input.settings.bottom.sensitivity = 2 }
            #expect(input.finger(0.6) == .inactive)
            #expect(input.finger(0.8) == .inactive)
            #expect(input.send([]) == .inactive)
            #expect(input.finger(0.3) == .inactive)
            #expect(input.finger(0.4).isActive)
        }
    }

    @Test func invalidSensitivityCannotActivateAnyAction() {
        for value in [0.24, 3.01, Double.nan, Double.infinity] {
            var input = Input()
            input.settings.bottom.sensitivity = value
            input.begin()
            #expect(input.finger(0.5) == .inactive)
        }
    }

    private func apply(_ update: GestureUpdate, to levels: inout LevelAccumulator) throws -> Int? {
        guard case let .active(_, _, change?) = update else { return nil }
        return try levels.apply(change)
    }
}
