struct TrackpadContact: Sendable, Equatable {
    let id: Int32
    let x: Double
    let y: Double
}

struct TrackpadFrame: Sendable, Equatable {
    /// Monotonic seconds, using the same clock as ProcessInfo.systemUptime.
    let timestamp: Double
    let contacts: [TrackpadContact]
}

enum GestureUpdate: Sendable, Equatable {
    case inactive
    case active(edge: TrackpadEdge, action: EdgeAction, percent: Int?)

    var isActive: Bool {
        if case .active = self { true } else { false }
    }
}
