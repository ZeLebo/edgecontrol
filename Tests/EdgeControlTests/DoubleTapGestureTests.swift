import Testing
@testable import EdgeControl

private struct TapInput {
    var gesture = DoubleTapGesture()
    var settings = EdgeSettings.defaults
    var time = 0.0

    mutating func send(_ contacts: [TrackpadContact], after seconds: Double = 0.01, sliding: Bool = false) -> TapUpdate {
        time += seconds
        return gesture.process(TrackpadFrame(timestamp: time, contacts: contacts), settings: settings, sliding: sliding)
    }
    mutating func finger(_ x: Double = 0.06, y: Double = 0.02, id: Int32 = 1,
                         after seconds: Double = 0.01, sliding: Bool = false) -> TapUpdate {
        send([TrackpadContact(id: id, x: x, y: y)], after: seconds, sliding: sliding)
    }
    mutating func tap(_ x: Double = 0.06, y: Double = 0.02, id: Int32 = 1,
                      gap: Double = 0.1, hold: Double = 0.04) -> TapUpdate {
        #expect(finger(x, y: y, id: id, after: gap).command == nil)
        return send([], after: hold)
    }
    mutating func ready() { #expect(send([]) == .inactive) }
}

@Suite("Double-tap zones")
struct DoubleTapGestureTests {
    @Test func firstTapDoesNothingAndSecondReleaseEmitsOneCommand() {
        var input = TapInput()
        input.ready()
        let began = input.finger()
        #expect(began.suppressClicks)
        #expect(began.suppressionUntil == input.time + 0.18)
        let held = input.finger(after: 0.02)
        #expect(held.suppressClicks)
        #expect(held.suppressionUntil == began.suppressionUntil)
        #expect(input.send([], after: 0.02).suppressClicks)
        #expect(input.send([], after: 0.03).suppressClicks)
        #expect(input.finger(id: 2, after: 0.05).suppressClicks)
        let completed = input.send([], after: 0.04)
        #expect(completed.command == TapCommand(zone: .bottomLeft, action: .mute))
        #expect(completed.suppressClicks)
        #expect(completed.suppressionUntil == input.time + 0.08)
        #expect(input.send([]).suppressClicks)
        #expect(input.tap(id: 3).command == nil)
        #expect(input.tap(id: 4).command?.action == .mute)
    }

    @Test(arguments: [0.01, 0.05])
    func allEightZonesWorkWithSlidingDisabled(_ width: Double) {
        #expect(TapZone.allCases.count == 8)
        for zone in TapZone.allCases {
            var input = TapInput()
            input.settings = emptySettings()
            input.settings.stripWidth = width
            input.settings[zone] = .playPause
            input.ready()
            let point = zone.position
            let inset = width / 2
            let x = max(inset, min(1 - inset, point.x))
            let y = max(inset, min(1 - inset, point.y))
            #expect(input.tap(x, y: y).command == nil)
            #expect(input.tap(x, y: y, id: 2).command == TapCommand(zone: zone, action: .playPause))
        }
    }

    @Test func onlyConfiguredZonesSuppressClicks() {
        for (x, y) in [(0.5, 0.02), (0.06, 0.5), (0.5, 0.5), (0.98, 0.5)] {
            var input = TapInput()
            input.ready()
            #expect(input.finger(x, y: y) == .inactive)
            #expect(input.finger(0.06) == .inactive)
            #expect(input.send([]) == .inactive)
            #expect(input.tap().command == nil)
        }
    }

    @Test func movingOrLeavingTheTapZoneCancelsUntilLift() {
        for replacement in [
            TrackpadContact(id: 1, x: 0.076, y: 0.02),
            TrackpadContact(id: 1, x: 0.06, y: 0.051),
            TrackpadContact(id: 2, x: 0.06, y: 0.02),
        ] {
            var input = TapInput()
            input.ready()
            #expect(input.finger().suppressClicks)
            #expect(input.send([replacement]) == .inactive)
            #expect(input.finger() == .inactive)
            #expect(input.send([]) == .inactive)
            #expect(input.tap().command == nil)
            #expect(input.tap(id: 2).command?.action == .mute)
        }
        var boundary = TapInput()
        boundary.ready()
        #expect(boundary.finger(0.119).suppressClicks)
        #expect(boundary.finger(0.121) == .inactive)
        #expect(boundary.send([]) == .inactive)
        #expect(boundary.tap(0.119).command == nil)
    }

    @Test func durationAndIntertapGapAreBounded() {
        var long = TapInput()
        long.ready()
        #expect(long.tap(hold: 0.181).command == nil)
        #expect(long.tap(id: 2).command == nil)
        #expect(long.tap(id: 3).command?.action == .mute)

        var late = TapInput()
        late.ready()
        #expect(late.tap().command == nil)
        #expect(late.tap(id: 2, gap: 0.351).command == nil)
        #expect(late.tap(id: 3).command?.action == .mute)

        var inclusive = TapInput()
        inclusive.ready()
        #expect(inclusive.tap(hold: 0.18).command == nil)
        #expect(inclusive.tap(id: 2, gap: 0.35, hold: 0.18).command?.action == .mute)
    }

    @Test func differentZonesDoNotCompleteTheSameDoubleTap() {
        var input = TapInput()
        input.settings[TapZone.bottomRight] = .nextTrack
        input.ready()
        #expect(input.tap().command == nil)
        #expect(input.tap(0.94, id: 2).command == nil)
        #expect(input.tap(0.94, id: 3).command == TapCommand(zone: .bottomRight, action: .nextTrack))
    }

    @Test func slidingAndMultipleFingersClearThePendingTap() {
        for sliding in [false, true] {
            var input = TapInput()
            input.ready()
            #expect(input.tap().command == nil)
            #expect(input.finger(id: 2).suppressClicks)
            let contacts = sliding ? [TrackpadContact(id: 2, x: 0.1, y: 0.02)] : [
                TrackpadContact(id: 2, x: 0.06, y: 0.02),
                TrackpadContact(id: 3, x: 0.5, y: 0.5),
            ]
            #expect(input.send(contacts, sliding: sliding) == .inactive)
            #expect(input.send([]) == .inactive)
            #expect(input.tap().command == nil)
        }
    }

    @Test func settingsChangeAndResetRequireAFreshPair() {
        for reset in [false, true] {
            var input = TapInput()
            input.ready()
            #expect(input.tap().command == nil)
            if reset { input.gesture.reset() }
            else { input.settings[TapZone.bottomLeft] = .playPause }
            #expect(input.finger(id: 2) == .inactive)
            #expect(input.send([]) == .inactive)
            #expect(input.tap().command == nil)
            #expect(input.tap(id: 2).command?.action == (reset ? .mute : .playPause))
        }
    }

    @Test func trailingClickSuppressionHasBoundedDeadlines() {
        var input = TapInput()
        input.ready()
        let first = input.tap()
        #expect(first.suppressClicks)
        #expect(first.suppressionUntil == input.time + 0.35)
        let pending = input.send([], after: 0.34)
        #expect(pending.suppressClicks)
        #expect(pending.suppressionUntil == first.suppressionUntil)
        #expect(input.send([], after: 0.011) == .inactive)
        #expect(input.tap(id: 2).command == nil)
        #expect(input.tap(id: 3).suppressClicks)
        #expect(input.send([], after: 0.079).suppressClicks)
        #expect(input.send([], after: 0.002) == .inactive)
    }

    @Test func idleTimeDoesNotDiscardTheFirstTapOfANewPair() {
        var input = TapInput()
        input.ready()
        #expect(input.tap(gap: 2).command == nil)
        #expect(input.tap(id: 2).command?.action == .mute)
    }

    @Test func startupContactCannotCountAsATap() {
        var input = TapInput()
        #expect(input.finger() == .inactive)
        #expect(input.send([]) == .inactive)
        #expect(input.tap().command == nil)
        #expect(input.tap(id: 2).command?.action == .mute)
    }

    @Test func malformedOrStaleFramesCancelPendingRecognition() {
        for timestamp in [-1, 0, Double.nan, Double.infinity] {
            var input = TapInput()
            input.ready()
            #expect(input.tap().command == nil)
            #expect(input.gesture.process(TrackpadFrame(timestamp: timestamp, contacts: []),
                                         settings: input.settings, sliding: false) == .inactive)
            input.ready()
            #expect(input.tap().command == nil)
        }
        for contact in [TrackpadContact(id: 2, x: .nan, y: 0.02),
                        TrackpadContact(id: 2, x: 0.06, y: 1.01)] {
            var input = TapInput()
            input.ready()
            #expect(input.tap().command == nil)
            #expect(input.send([contact]) == .inactive)
            input.ready()
            #expect(input.tap().command == nil)
        }
        var stale = TapInput()
        stale.ready()
        #expect(stale.tap().command == nil)
        #expect(stale.finger(id: 2, after: 0.6).suppressClicks)
        #expect(stale.send([]).command == nil)
        #expect(stale.tap().command?.action == .mute)
    }

    @Test func adjacentEdgesShareOneCornerActionAndOneTapPair() {
        for (zone, firstX, firstY, secondX, secondY) in [
            (TapZone.bottomLeft, 0.06, 0.02, 0.02, 0.06),
            (.bottomRight, 0.94, 0.02, 0.98, 0.06),
            (.topLeft, 0.06, 0.98, 0.02, 0.94),
            (.topRight, 0.94, 0.98, 0.98, 0.94),
        ] {
            var input = TapInput()
            input.settings = emptySettings()
            input.settings[zone] = .playPause
            input.ready()
            #expect(input.tap(firstX, y: firstY).command == nil)
            #expect(input.tap(secondX, y: secondY, id: 2).command == TapCommand(zone: zone, action: .playPause))
            #expect(input.send([]).command == nil)
        }
    }

    @Test func centersUseTheirOwnTwelvePercentRegion() {
        for edge in TrackpadEdge.allCases {
            let zone = edge.tapZones[1]
            for (coordinate, inside) in [(0.4399, false), (0.44, true), (0.5, true), (0.56, true), (0.5601, false)] {
                var input = TapInput()
                input.settings = emptySettings()
                input.settings[zone] = .nextTrack
                input.ready()
                let (x, y) = position(edge, coordinate)
                #expect(input.finger(x, y: y).suppressClicks == inside)
            }
        }
    }

    @Test func aCenterAndACornerCannotCompleteOnePair() {
        var input = TapInput()
        input.settings[TapZone.bottomCenter] = .playPause
        input.ready()
        #expect(input.tap().command == nil)
        #expect(input.tap(0.5, id: 2).command == nil)
        #expect(input.tap(0.5, id: 3).command == TapCommand(zone: .bottomCenter, action: .playPause))
    }

    private func emptySettings() -> EdgeSettings {
        var settings = EdgeSettings.defaults
        for edge in TrackpadEdge.allCases { settings[edge] = EdgeConfiguration() }
        for zone in TapZone.allCases { settings[zone] = .none }
        return settings
    }

    private func position(_ edge: TrackpadEdge, _ coordinate: Double) -> (Double, Double) {
        switch edge {
        case .top: (coordinate, 0.98)
        case .right: (0.98, coordinate)
        case .bottom: (coordinate, 0.02)
        case .left: (0.02, coordinate)
        }
    }
}
