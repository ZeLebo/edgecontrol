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

enum LevelChange: Sendable, Equatable {
    case absolute(Int)
    /// Incremental percentage-point movement since the previous sample (first: since touch-down).
    case relative(Double)
}

enum GestureUpdate: Sendable, Equatable {
    case inactive
    case active(edge: TrackpadEdge, action: EdgeAction, change: LevelChange?)
    var isActive: Bool { if case .active = self { true } else { false } }
}

struct TapCommand: Sendable, Equatable {
    let zone: TapZone
    let action: TapAction
}

struct TapUpdate: Sendable, Equatable {
    let command: TapCommand?
    let suppressClicks: Bool
    let suppressionUntil: Double?
    static let inactive = TapUpdate(command: nil, suppressClicks: false, suppressionUntil: nil)
}
