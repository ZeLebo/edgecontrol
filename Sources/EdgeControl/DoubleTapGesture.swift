struct DoubleTapGesture {
    private struct Zone: Equatable {
        let position: TapZone
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
                    return TapUpdate(command: TapCommand(zone: touch.zone.position, action: touch.zone.action), suppressClicks: true,
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
        for position in TapZone.allCases {
            let zone = Zone(position: position, action: settings[position])
            if zone.action != .none, contains(contact, in: zone, width: settings.stripWidth) { return zone }
        }
        return nil
    }

    private func contains(_ contact: TrackpadContact, in zone: Zone, width: Double) -> Bool {
        let x = contact.x
        let y = contact.y
        let left = x <= width
        let right = x >= 1 - width
        let bottom = y <= width
        let top = y >= 1 - width
        // Each corner is one L-shaped region shared by both adjacent edge strips.
        switch zone.position {
        case .topLeft: return (top && x <= 0.12) || (left && y >= 0.88)
        case .topRight: return (top && x >= 0.88) || (right && y >= 0.88)
        case .bottomLeft: return (bottom && x <= 0.12) || (left && y <= 0.12)
        case .bottomRight: return (bottom && x >= 0.88) || (right && y <= 0.12)
        case .topCenter: return top && abs(x - 0.5) <= 0.06 + 1e-12
        case .rightCenter: return right && abs(y - 0.5) <= 0.06 + 1e-12
        case .bottomCenter: return bottom && abs(x - 0.5) <= 0.06 + 1e-12
        case .leftCenter: return left && abs(y - 0.5) <= 0.06 + 1e-12
        }
    }
}
