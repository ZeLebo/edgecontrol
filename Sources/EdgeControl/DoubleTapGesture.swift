struct DoubleTapGesture {
    private struct Zone: Equatable {
        let edge: TrackpadEdge
        let end: TapZoneEnd
        let action: TapAction
    }
    private struct FirstTap {
        let zone: Zone
        let releasedAt: Double
    }
    private struct Touch {
        let start: TrackpadContact
        let beganAt: Double
        let zone: Zone
        let isSecond: Bool
    }
    private enum State {
        case waitingForLift
        case ready
        case touching(Touch)
    }

    private var state = State.waitingForLift
    private var firstTap: FirstTap?
    private var lastTimestamp: Double?
    private var lastSettings: EdgeSettings?
    private var suppressionUntil: Double?

    mutating func process(_ frame: TrackpadFrame, settings: EdgeSettings, sliding: Bool) -> TapUpdate {
        guard settings.isValid, frame.timestamp.isFinite, frame.timestamp >= 0,
              lastTimestamp.map({ frame.timestamp > $0 }) ?? true,
              frame.contacts.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
              }) else { return cancel(lifted: false) }
        lastTimestamp = frame.timestamp
        if sliding ||
            (lastSettings.map { $0 != settings } ?? false) {
            lastSettings = settings
            return cancel(lifted: frame.contacts.isEmpty)
        }
        lastSettings = settings

        switch state {
        case .waitingForLift:
            if frame.contacts.isEmpty { state = .ready }
            return .inactive
        case .ready:
            if let firstTap, frame.timestamp - firstTap.releasedAt > 0.35 + 1e-12 {
                self.firstTap = nil
            }
            if frame.contacts.isEmpty {
                guard let suppressionUntil, frame.timestamp <= suppressionUntil else { return .inactive }
                return TapUpdate(command: nil, suppressClicks: true, suppressionUntil: suppressionUntil)
            }
            guard frame.contacts.count == 1, let contact = frame.contacts.first,
                  let zone = zone(at: contact, settings: settings) else { return cancel(lifted: false) }
            suppressionUntil = nil
            let isSecond = firstTap?.zone == zone
            if !isSecond { firstTap = nil }
            state = .touching(Touch(start: contact, beganAt: frame.timestamp, zone: zone, isSecond: isSecond))
            return TapUpdate(command: nil, suppressClicks: true, suppressionUntil: frame.timestamp + 0.18)
        case .touching(let touch):
            guard frame.timestamp - touch.beganAt <= 0.18 + 1e-12 else {
                return cancel(lifted: frame.contacts.isEmpty)
            }
            if frame.contacts.isEmpty {
                state = .ready
                if touch.isSecond {
                    firstTap = nil
                    suppressionUntil = frame.timestamp + 0.08
                    return TapUpdate(command: TapCommand(edge: touch.zone.edge, end: touch.zone.end,
                                                         action: touch.zone.action), suppressClicks: true,
                                     suppressionUntil: suppressionUntil)
                }
                firstTap = FirstTap(zone: touch.zone, releasedAt: frame.timestamp)
                // Native tap-to-click events may arrive after the raw contact has lifted.
                suppressionUntil = frame.timestamp + 0.35
                return TapUpdate(command: nil, suppressClicks: true, suppressionUntil: suppressionUntil)
            }
            guard frame.contacts.count == 1, let contact = frame.contacts.first,
                  contact.id == touch.start.id,
                  contains(contact, in: touch.zone, width: settings.stripWidth) else {
                return cancel(lifted: false)
            }
            let dx = contact.x - touch.start.x
            let dy = contact.y - touch.start.y
            guard dx * dx + dy * dy <= 0.015 * 0.015 + 1e-15 else { return cancel(lifted: false) }
            return TapUpdate(command: nil, suppressClicks: true, suppressionUntil: touch.beganAt + 0.18)
        }
    }

    mutating func reset() {
        lastTimestamp = nil
        lastSettings = nil
        _ = cancel(lifted: false)
    }

    private mutating func cancel(lifted: Bool) -> TapUpdate {
        state = lifted ? .ready : .waitingForLift
        firstTap = nil
        suppressionUntil = nil
        return .inactive
    }

    private func zone(at contact: TrackpadContact, settings: EdgeSettings) -> Zone? {
        var closest: (zone: Zone, distance: Double)?
        for edge in TrackpadEdge.allCases {
            for end in TapZoneEnd.allCases {
                let action = settings[edge][end]
                let zone = Zone(edge: edge, end: end, action: action)
                guard action != .none, contains(contact, in: zone, width: settings.stripWidth) else { continue }
                let distance: Double
                switch edge {
                case .top: distance = 1 - contact.y
                case .right: distance = 1 - contact.x
                case .bottom: distance = contact.y
                case .left: distance = contact.x
                }
                // Ties keep the documented clockwise edge order, including opposite-corner rounding.
                if closest == nil || distance < closest!.distance - 1e-12 {
                    closest = (zone, distance)
                }
            }
        }
        return closest?.zone
    }

    private func contains(_ contact: TrackpadContact, in zone: Zone, width: Double) -> Bool {
        let inBand: Bool
        switch zone.edge {
        case .top: inBand = contact.y >= 1 - width
        case .right: inBand = contact.x >= 1 - width
        case .bottom: inBand = contact.y <= width
        case .left: inBand = contact.x <= width
        }
        let coordinate = zone.edge.isHorizontal ? contact.x : contact.y
        return inBand && (zone.end == .start ? coordinate <= 0.12 : coordinate >= 0.88)
    }
}
