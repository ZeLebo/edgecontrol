import Foundation

enum TrackpadEdge: String, Codable, CaseIterable, Sendable {
    case top, right, bottom, left
    var title: String { rawValue.capitalized }
    var isHorizontal: Bool { self == .top || self == .bottom }
    var tapZones: [TapZone] {
        switch self {
        case .top: [.topLeft, .topCenter, .topRight]
        case .right: [.bottomRight, .rightCenter, .topRight]
        case .bottom: [.bottomLeft, .bottomCenter, .bottomRight]
        case .left: [.bottomLeft, .leftCenter, .topLeft]
        }
    }
}

enum EdgeAction: String, Codable, CaseIterable, Sendable {
    case disabled, volume, brightness, keyboardBrightness, tracks, seek, shortcut
    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .keyboardBrightness: "Keyboard Backlight"
        case .tracks: "Track Navigation"
        case .seek: "Seek"
        case .shortcut: "Keyboard Shortcut"
        }
    }
    var symbol: String {
        switch self {
        case .disabled: "minus"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .keyboardBrightness: "keyboard.fill"
        case .tracks: "forward.end.fill"
        case .seek: "goforward.10"
        case .shortcut: "command.square"
        }
    }
    var isLevel: Bool { self == .volume || self == .brightness || self == .keyboardBrightness }
}

enum AdjustmentMode: String, Codable, CaseIterable, Sendable {
    case absolute, relative
    var title: String { rawValue.capitalized }
}

enum TapZone: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight, rightCenter, bottomRight, bottomCenter, bottomLeft, leftCenter
    var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .topCenter: "Top Center"
        case .topRight: "Top Right"
        case .rightCenter: "Right Center"
        case .bottomRight: "Bottom Right"
        case .bottomCenter: "Bottom Center"
        case .bottomLeft: "Bottom Left"
        case .leftCenter: "Left Center"
        }
    }
    var position: (x: Double, y: Double) {
        switch self {
        case .topLeft: (0, 1)
        case .topCenter: (0.5, 1)
        case .topRight: (1, 1)
        case .rightCenter: (1, 0.5)
        case .bottomRight: (1, 0)
        case .bottomCenter: (0.5, 0)
        case .bottomLeft: (0, 0)
        case .leftCenter: (0, 0.5)
        }
    }
}

enum TapAction: String, Codable, CaseIterable, Sendable {
    static var configurableCases: [Self] { allCases.filter { $0 != .nextProfile } }
    case none, mute, playPause, previousTrack, nextTrack, seekBackward, seekForward, nextProfile, toggleKeyboardBacklight, shortcut
    var title: String {
        switch self {
        case .none: "None"
        case .mute: "Mute / Unmute"
        case .playPause: "Play / Pause"
        case .previousTrack: "Previous Track"
        case .nextTrack: "Next Track"
        case .seekBackward: "Back 10 Seconds"
        case .seekForward: "Forward 10 Seconds"
        case .nextProfile: "Next Profile"
        case .toggleKeyboardBacklight: "Keyboard Backlight On / Off"
        case .shortcut: "Keyboard Shortcut"
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
        case .nextProfile: "rectangle.stack"
        case .toggleKeyboardBacklight: "keyboard.fill"
        case .shortcut: "command.square"
        }
    }
}

struct EdgeConfiguration: Codable, Equatable, Sendable {
    var action: EdgeAction = .disabled
    var mode: AdjustmentMode = .absolute
    var sensitivity: Double = 1
    var negativeShortcut: KeyboardShortcut?
    var positiveShortcut: KeyboardShortcut?
    var effectiveMode: AdjustmentMode { action.isLevel ? mode : .relative }
    var isValid: Bool {
        sensitivity.isFinite && (0.25...3).contains(sensitivity) &&
            (negativeShortcut?.isValid ?? true) && (positiveShortcut?.isValid ?? true) &&
            (action != .shortcut || (negativeShortcut != nil && positiveShortcut != nil))
    }
}

struct TapAssignments: Codable, Equatable, Sendable {
    var topLeft: TapAction = .none
    var topCenter: TapAction = .none
    var topRight: TapAction = .none
    var rightCenter: TapAction = .none
    var bottomRight: TapAction = .mute
    var bottomCenter: TapAction = .none
    var bottomLeft: TapAction = .mute
    var leftCenter: TapAction = .none

    subscript(zone: TapZone) -> TapAction {
        get {
            switch zone {
            case .topLeft: topLeft
            case .topCenter: topCenter
            case .topRight: topRight
            case .rightCenter: rightCenter
            case .bottomRight: bottomRight
            case .bottomCenter: bottomCenter
            case .bottomLeft: bottomLeft
            case .leftCenter: leftCenter
            }
        }
        set {
            switch zone {
            case .topLeft: topLeft = newValue
            case .topCenter: topCenter = newValue
            case .topRight: topRight = newValue
            case .rightCenter: rightCenter = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomCenter: bottomCenter = newValue
            case .bottomLeft: bottomLeft = newValue
            case .leftCenter: leftCenter = newValue
            }
        }
    }
}

struct EdgeSettings: Codable, Equatable, Sendable {
    var top = EdgeConfiguration()
    var right = EdgeConfiguration(action: .brightness)
    var bottom = EdgeConfiguration(action: .volume)
    var left = EdgeConfiguration()
    var stripWidth: Double = 0.05
    var hapticsEnabled = true
    var tapActions = TapAssignments()
    var tapShortcuts: [String: KeyboardShortcut] = [:]
    static let defaults = EdgeSettings()
    static let allowedStripWidths = 0.03...0.15
    var isValid: Bool {
        stripWidth.isFinite && Self.allowedStripWidths.contains(stripWidth) &&
            TrackpadEdge.allCases.allSatisfy { self[$0].isValid } &&
            tapShortcuts.allSatisfy { key, value in TapZone(rawValue: key) != nil && value.isValid } &&
            TapZone.allCases.allSatisfy { self[$0] != .shortcut || tapShortcuts[$0.rawValue] != nil }
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
    subscript(zone: TapZone) -> TapAction {
        get { tapActions[zone] }
        set { tapActions[zone] = newValue }
    }

}

struct ControlProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var settings: EdgeSettings

    init(id: UUID = UUID(), name: String, settings: EdgeSettings = .defaults) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}

struct ProfileDocument: Codable, Equatable, Sendable {
    var profiles: [ControlProfile]
    var activeProfileID: UUID
    var profileSwitchZone: TapZone?
    var excludedAppIDs: [String] = []

    var isValid: Bool {
        Set(excludedAppIDs).count == excludedAppIDs.count &&
            excludedAppIDs.allSatisfy { !$0.isEmpty && !$0.contains(where: { $0.isWhitespace || $0.isNewline }) } &&
            !profiles.isEmpty && Set(profiles.map(\.id)).count == profiles.count &&
            profiles.contains { $0.id == activeProfileID } &&
            profiles.enumerated().allSatisfy { index, profile in
                !profile.name.isEmpty && profile.name.count <= 40 &&
                    profile.name == profile.name.trimmingCharacters(in: .whitespacesAndNewlines) &&
                    profiles.prefix(index).allSatisfy { $0.name.caseInsensitiveCompare(profile.name) != .orderedSame } &&
                    profile.settings.isValid &&
                    TapZone.allCases.allSatisfy { profile.settings[$0] != .nextProfile }
            }
    }
}

extension ProfileDocument {
    private enum CodingKeys: String, CodingKey { case profiles, activeProfileID, profileSwitchZone, excludedAppIDs }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try values.decode([ControlProfile].self, forKey: .profiles)
        activeProfileID = try values.decode(UUID.self, forKey: .activeProfileID)
        profileSwitchZone = try values.decodeIfPresent(TapZone.self, forKey: .profileSwitchZone)
        // Earlier v5 releases had profiles before application exclusions were added.
        excludedAppIDs = try values.contains(.excludedAppIDs) ? values.decode([String].self, forKey: .excludedAppIDs) : []
    }
}

extension EdgeSettings {
    private enum CodingKeys: String, CodingKey { case top, right, bottom, left, stripWidth, hapticsEnabled, tapActions, tapShortcuts }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        top = try values.decode(EdgeConfiguration.self, forKey: .top)
        right = try values.decode(EdgeConfiguration.self, forKey: .right)
        bottom = try values.decode(EdgeConfiguration.self, forKey: .bottom)
        left = try values.decode(EdgeConfiguration.self, forKey: .left)
        stripWidth = try values.decode(Double.self, forKey: .stripWidth)
        hapticsEnabled = try values.decode(Bool.self, forKey: .hapticsEnabled)
        tapActions = try values.decode(TapAssignments.self, forKey: .tapActions)
        // Profile records predating shortcut actions had no per-point shortcut dictionary.
        tapShortcuts = try values.contains(.tapShortcuts) ? values.decode([String: KeyboardShortcut].self, forKey: .tapShortcuts) : [:]
    }
}
