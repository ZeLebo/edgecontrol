struct EdgeGesture {
    private enum State {
        case waitingForLift
        case ready
        case candidate(start: TrackpadContact, edges: [TrackpadEdge])
        case active(id: Int32, edge: TrackpadEdge, configuration: EdgeConfiguration, coordinate: Double)
    }

    private var state = State.waitingForLift
    private var lastTimestamp: Double?
    private var lastSettings: EdgeSettings?
    private var lastPercent: Int?

    mutating func process(_ frame: TrackpadFrame, settings: EdgeSettings) -> GestureUpdate {
        guard settings.isValid, frame.timestamp.isFinite, frame.timestamp >= 0,
              lastTimestamp.map({ frame.timestamp > $0 }) ?? true else { return cancel() }
        lastTimestamp = frame.timestamp
        guard frame.contacts.allSatisfy({
            $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }) else { return cancel() }

        if let lastSettings, lastSettings != settings {
            self.lastSettings = settings
            return finish(frame)
        }
        lastSettings = settings

        switch state {
        case .waitingForLift:
            if frame.contacts.isEmpty { state = .ready }
            return .inactive

        case .ready:
            if frame.contacts.isEmpty { return .inactive }
            guard frame.contacts.count == 1, let contact = frame.contacts.first else { return cancel() }
            let edges = TrackpadEdge.allCases.filter {
                settings[$0].action != .disabled && contains(contact, in: $0, width: settings.stripWidth)
            }
            guard !edges.isEmpty else { return cancel() }
            state = .candidate(start: contact, edges: edges)
            return .inactive

        case let .candidate(start, edges):
            guard frame.contacts.count == 1, let contact = frame.contacts.first,
                  contact.id == start.id else { return finish(frame) }
            let eligible = edges.filter { contains(contact, in: $0, width: settings.stripWidth) }
            guard !eligible.isEmpty else { return finish(frame) }
            state = .candidate(start: start, edges: eligible)
            guard let edge = activatedEdge(from: eligible, start: start, current: contact) else {
                return .inactive
            }
            let configuration = settings[edge]
            return update(contact, edge: edge, configuration: configuration,
                          previous: coordinate(of: start, along: edge))

        case let .active(id, edge, configuration, previous):
            guard frame.contacts.count == 1, let contact = frame.contacts.first,
                  contact.id == id, contains(contact, in: edge, width: settings.stripWidth) else {
                return finish(frame)
            }
            return update(contact, edge: edge, configuration: configuration, previous: previous)
        }
    }

    @discardableResult
    mutating func reset() -> GestureUpdate {
        lastTimestamp = nil
        lastSettings = nil
        return cancel()
    }

    private func activatedEdge(
        from edges: [TrackpadEdge], start: TrackpadContact, current: TrackpadContact
    ) -> TrackpadEdge? {
        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)
        let xTolerance = max(current.x.ulp, start.x.ulp)
        let yTolerance = max(current.y.ulp, start.y.ulp)
        if edges.count > 1 {
            // Equal physical deltas can differ by a few ulps near opposite corners.
            guard abs(dx - dy) > 2 * max(xTolerance, yTolerance) else { return nil }
        }
        return edges.first { edge in
            let distance = edge.isHorizontal ? dx : dy
            let tolerance = edge.isHorizontal ? xTolerance : yTolerance
            return distance + tolerance >= 0.02 &&
                (edges.count == 1 || edge.isHorizontal == (dx > dy))
        }
    }

    private func contains(_ contact: TrackpadContact, in edge: TrackpadEdge, width: Double) -> Bool {
        switch edge {
        case .top: contact.y >= 1 - width
        case .right: contact.x >= 1 - width
        case .bottom: contact.y <= width
        case .left: contact.x <= width
        }
    }

    private func coordinate(of contact: TrackpadContact, along edge: TrackpadEdge) -> Double {
        edge.isHorizontal ? contact.x : contact.y
    }

    private mutating func update(
        _ contact: TrackpadContact, edge: TrackpadEdge, configuration: EdgeConfiguration, previous: Double
    ) -> GestureUpdate {
        let coordinate = coordinate(of: contact, along: edge)
        state = .active(id: contact.id, edge: edge, configuration: configuration, coordinate: coordinate)
        let change: LevelChange?
        switch configuration.effectiveMode {
        case .absolute:
            let percent = Int((100 * min(1, max(0, (coordinate - 0.03) / 0.94))).rounded())
            change = percent == lastPercent ? nil : .absolute(percent)
            lastPercent = percent
        case .relative:
            let delta = (coordinate - previous) * 100 * configuration.sensitivity
            change = delta == 0 ? nil : .relative(delta)
        }
        return .active(edge: edge, action: configuration.action, change: change)
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
