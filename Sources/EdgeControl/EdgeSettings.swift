import Foundation

enum TrackpadEdge: String, Codable, CaseIterable, Sendable {
    case top, right, bottom, left
    var title: String { rawValue.capitalized }
    var isHorizontal: Bool { self == .top || self == .bottom }
}

enum EdgeAction: String, Codable, CaseIterable, Sendable {
    case disabled, volume, brightness, tracks, seek
    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .tracks: "Track Navigation"
        case .seek: "Seek"
        }
    }
    var symbol: String {
        switch self {
        case .disabled: "minus"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .tracks: "forward.end.fill"
        case .seek: "goforward.10"
        }
    }
    var isLevel: Bool { self == .volume || self == .brightness }
}

enum AdjustmentMode: String, Codable, CaseIterable, Sendable {
    case absolute, relative
    var title: String { rawValue.capitalized }
}

enum TapZoneEnd: String, Codable, CaseIterable, Sendable {
    case start, end
    func title(on edge: TrackpadEdge) -> String {
        edge.isHorizontal ? (self == .start ? "Left" : "Right") : (self == .start ? "Bottom" : "Top")
    }
}

enum TapAction: String, Codable, CaseIterable, Sendable {
    case none, mute, playPause, previousTrack, nextTrack, seekBackward, seekForward
    var title: String {
        switch self {
        case .none: "None"
        case .mute: "Mute / Unmute"
        case .playPause: "Play / Pause"
        case .previousTrack: "Previous Track"
        case .nextTrack: "Next Track"
        case .seekBackward: "Back 10 Seconds"
        case .seekForward: "Forward 10 Seconds"
        }
    }
    var symbol: String {
        switch self {
        case .none: "minus"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        case .previousTrack: "backward.end.fill"
        case .nextTrack: "forward.end.fill"
        case .seekBackward: "gobackward.10"
        case .seekForward: "goforward.10"
        }
    }
}

struct EdgeConfiguration: Codable, Equatable, Sendable {
    var action: EdgeAction = .disabled
    var mode: AdjustmentMode = .absolute
    var sensitivity: Double = 1
    var startTap: TapAction = .none
    var endTap: TapAction = .none
    var effectiveMode: AdjustmentMode { action.isLevel ? mode : .relative }
    var isValid: Bool { sensitivity.isFinite && (0.25...3).contains(sensitivity) }
    subscript(end: TapZoneEnd) -> TapAction {
        get { end == .start ? startTap : endTap }
        set { if end == .start { startTap = newValue } else { endTap = newValue } }
    }
}

struct EdgeSettings: Codable, Equatable, Sendable {
    var top = EdgeConfiguration()
    var right = EdgeConfiguration(action: .brightness)
    var bottom = EdgeConfiguration(action: .volume, startTap: .mute, endTap: .mute)
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

extension EdgeConfiguration {
    private enum CodingKeys: String, CodingKey { case action, mode, sensitivity, startTap, endTap }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        action = try values.decode(EdgeAction.self, forKey: .action)
        mode = try values.decode(AdjustmentMode.self, forKey: .mode)
        sensitivity = try values.decode(Double.self, forKey: .sensitivity)
        // Earlier v3 releases stored slide settings before double taps were added.
        let initialTap: TapAction = action == .volume ? .mute : .none
        startTap = try values.contains(.startTap) ? values.decode(TapAction.self, forKey: .startTap) : initialTap
        endTap = try values.contains(.endTap) ? values.decode(TapAction.self, forKey: .endTap) : initialTap
    }
}

extension EdgeSettings {
    private enum CodingKeys: String, CodingKey { case top, right, bottom, left, stripWidth, hapticsEnabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        top = try values.decode(EdgeConfiguration.self, forKey: .top)
        right = try values.decode(EdgeConfiguration.self, forKey: .right)
        bottom = try values.decode(EdgeConfiguration.self, forKey: .bottom)
        left = try values.decode(EdgeConfiguration.self, forKey: .left)
        stripWidth = try values.decode(Double.self, forKey: .stripWidth)
        hapticsEnabled = try values.contains(.hapticsEnabled) ? values.decode(Bool.self, forKey: .hapticsEnabled) : true
    }
}
