struct VolumeGesture {
    private enum State {
        case waitingForLift, ready
        case candidate(id: Int32, startX: Double)
        case active(id: Int32)
    }
    private var state = State.waitingForLift
    private var lastTimestamp: Double?
    private var lastPercent: Int?

    mutating func process(_ frame: TrackpadFrame) -> GestureUpdate {
        guard frame.timestamp.isFinite, frame.timestamp >= 0,
              lastTimestamp.map({ frame.timestamp > $0 }) ?? true else { return cancel() }
        lastTimestamp = frame.timestamp
        guard frame.contacts.allSatisfy({
            $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }) else { return cancel() }
        switch state {
        case .waitingForLift:
            if frame.contacts.isEmpty { state = .ready }
            return .inactive
        case .ready:
            if frame.contacts.isEmpty { return .inactive }
            guard frame.contacts.count == 1, let contact = frame.contacts.first,
                  contact.y <= 0.05 else { return cancel() }
            state = .candidate(id: contact.id, startX: contact.x)
            return .inactive
        case let .candidate(id, startX):
            guard let contact = continuing(frame, id: id) else { return finish(frame) }
            guard abs(contact.x - startX) + max(contact.x.ulp, startX.ulp) >= 0.02 else { return .inactive }
            state = .active(id: id)
            return update(contact.x)
        case let .active(id):
            guard let contact = continuing(frame, id: id) else { return finish(frame) }
            return update(contact.x)
        }
    }
    @discardableResult mutating func reset() -> GestureUpdate {
        lastTimestamp = nil
        return cancel()
    }
    private func continuing(_ frame: TrackpadFrame, id: Int32) -> TrackpadContact? {
        guard frame.contacts.count == 1, let contact = frame.contacts.first,
              contact.id == id, contact.y <= 0.05 else { return nil }
        return contact
    }
    private mutating func update(_ x: Double) -> GestureUpdate {
        let percent = Int((100 * min(1, max(0, (x - 0.03) / 0.94))).rounded())
        let changed = percent != lastPercent
        lastPercent = percent
        return GestureUpdate(isActive: true, percent: changed ? percent : nil)
    }
    private mutating func cancel() -> GestureUpdate {
        state = .waitingForLift
        lastPercent = nil
        return .inactive
    }
    private mutating func finish(_ frame: TrackpadFrame) -> GestureUpdate {
        let result = cancel()
        if frame.contacts.isEmpty { state = .ready }
        return result
    }
}
