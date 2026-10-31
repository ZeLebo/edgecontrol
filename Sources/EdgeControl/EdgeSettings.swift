enum TrackpadEdge: String, Codable, CaseIterable, Sendable {
    case top, right, bottom, left

    var title: String {
        switch self {
        case .top: "Top"
        case .right: "Right"
        case .bottom: "Bottom"
        case .left: "Left"
        }
    }

    var isHorizontal: Bool { self == .top || self == .bottom }
}

enum EdgeAction: String, Codable, CaseIterable, Sendable {
    case disabled, volume, brightness

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .volume: "Volume"
        case .brightness: "Brightness"
        }
    }

    var symbol: String {
        switch self {
        case .disabled: "minus"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        }
    }
}

struct EdgeSettings: Codable, Equatable, Sendable {
    var top: EdgeAction = .disabled
    var right: EdgeAction = .brightness
    var bottom: EdgeAction = .volume
    var left: EdgeAction = .disabled
    var stripWidth: Double = 0.05

    static let defaults = EdgeSettings()
    static let allowedStripWidths = 0.03...0.15

    var isValid: Bool { stripWidth.isFinite && Self.allowedStripWidths.contains(stripWidth) }

    subscript(edge: TrackpadEdge) -> EdgeAction {
        get {
            switch edge {
            case .top: top
            case .right: right
            case .bottom: bottom
            case .left: left
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            }
        }
    }
}
