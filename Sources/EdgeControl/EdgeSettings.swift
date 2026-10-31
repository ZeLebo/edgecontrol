import Foundation

enum TrackpadEdge: String, Codable, CaseIterable, Sendable {
    case top, right, bottom, left
    var title: String { rawValue.capitalized }
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
    var isLevel: Bool { self == .volume || self == .brightness }
}

enum AdjustmentMode: String, Codable, CaseIterable, Sendable {
    case absolute, relative
    var title: String { rawValue.capitalized }
}

struct EdgeConfiguration: Codable, Equatable, Sendable {
    var action: EdgeAction = .disabled
    var mode: AdjustmentMode = .absolute
    var sensitivity: Double = 1
    var isValid: Bool { sensitivity.isFinite && (0.25...3).contains(sensitivity) }
}

struct EdgeSettings: Codable, Equatable, Sendable {
    var top = EdgeConfiguration()
    var right = EdgeConfiguration(action: .brightness)
    var bottom = EdgeConfiguration(action: .volume)
    var left = EdgeConfiguration()
    var stripWidth: Double = 0.05
    var hapticsEnabled = true
    static let defaults = EdgeSettings()
    static let allowedStripWidths = 0.03...0.15
    var isValid: Bool {
        stripWidth.isFinite && Self.allowedStripWidths.contains(stripWidth) &&
            TrackpadEdge.allCases.allSatisfy { self[$0].isValid }
    }
    subscript(edge: TrackpadEdge) -> EdgeConfiguration {
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

// Existing v3 records predate the haptics preference. Other fields remain required.
extension EdgeSettings {
    private enum CodingKeys: String, CodingKey {
        case top, right, bottom, left, stripWidth, hapticsEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        top = try values.decode(EdgeConfiguration.self, forKey: .top)
        right = try values.decode(EdgeConfiguration.self, forKey: .right)
        bottom = try values.decode(EdgeConfiguration.self, forKey: .bottom)
        left = try values.decode(EdgeConfiguration.self, forKey: .left)
        stripWidth = try values.decode(Double.self, forKey: .stripWidth)
        hapticsEnabled = values.contains(.hapticsEnabled)
            ? try values.decode(Bool.self, forKey: .hapticsEnabled) : true
    }
}
