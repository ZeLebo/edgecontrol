import Foundation

@MainActor
final class SettingsStore {
    static let storageKey = "edgecontrol.settings.v4"
    static let previousStorageKey = "edgecontrol.settings.v3"
    static let flatStorageKey = "edgecontrol.settings.v2"
    // One-time import from the previous application's domain; never used after a v4 record exists.
    static let legacyDomain = "local.edgebar.app"
    static let legacyStorageKey = "edgebar.settings.v2"

    private(set) var settings: EdgeSettings
    private(set) var loadError: String?
    var onChange: ((EdgeSettings) -> Void)?
    private let defaults: UserDefaults

    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, previousDefaults: UserDefaults(suiteName: Self.legacyDomain))
    }

    init(defaults: UserDefaults, previousDefaults: UserDefaults?) {
        self.defaults = defaults
        settings = .defaults
        if let record = defaults.object(forKey: Self.storageKey) {
            do {
                guard let data = record as? Data else { throw SettingsStoreError.invalidRecord }
                let value = try JSONDecoder().decode(EdgeSettings.self, from: data)
                guard value.isValid else { throw SettingsStoreError.invalidRecord }
                settings = value
            } catch {
                loadError = "Saved settings could not be read. Defaults are active until you save or reset."
            }
            return
        }
        let previous = defaults.object(forKey: Self.previousStorageKey)
        let flat = defaults.object(forKey: Self.flatStorageKey)
            ?? previousDefaults?.object(forKey: Self.legacyStorageKey)
        guard previous != nil || flat != nil else { return }
        do {
            let value: EdgeSettings
            if let previous {
                guard let data = previous as? Data else { throw SettingsStoreError.invalidRecord }
                value = try JSONDecoder().decode(PreviousSettings.self, from: data).currentSettings
            } else {
                guard let data = flat as? Data else { throw SettingsStoreError.invalidRecord }
                value = try JSONDecoder().decode(FlatSettings.self, from: data).currentSettings
            }
            guard value.isValid else { throw SettingsStoreError.invalidRecord }
            defaults.set(try JSONEncoder().encode(value), forKey: Self.storageKey)
            settings = value
        } catch {
            loadError = "Previous settings could not be imported. Defaults are active until you save or reset."
        }
    }

    func update(_ value: EdgeSettings) throws {
        guard value.isValid else { throw SettingsStoreError.invalidValues }
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: Self.storageKey)
        settings = value
        loadError = nil
        onChange?(value)
    }

    func reset() throws { try update(.defaults) }
}

private struct PreviousSettings: Decodable {
    struct Edge: Decodable {
        let action: EdgeAction
        let mode: AdjustmentMode
        let sensitivity: Double
        let startTap: TapAction
        let endTap: TapAction
        var current: EdgeConfiguration { EdgeConfiguration(action: action, mode: mode, sensitivity: sensitivity) }
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
    let top: Edge
    let right: Edge
    let bottom: Edge
    let left: Edge
    let stripWidth: Double
    let hapticsEnabled: Bool
    private enum CodingKeys: String, CodingKey { case top, right, bottom, left, stripWidth, hapticsEnabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        top = try values.decode(Edge.self, forKey: .top)
        right = try values.decode(Edge.self, forKey: .right)
        bottom = try values.decode(Edge.self, forKey: .bottom)
        left = try values.decode(Edge.self, forKey: .left)
        stripWidth = try values.decode(Double.self, forKey: .stripWidth)
        hapticsEnabled = try values.contains(.hapticsEnabled) ? values.decode(Bool.self, forKey: .hapticsEnabled) : true
    }

    var currentSettings: EdgeSettings {
        var result = EdgeSettings.defaults
        result.top = top.current
        result.right = right.current
        result.bottom = bottom.current
        result.left = left.current
        result.stripWidth = stripWidth
        result.hapticsEnabled = hapticsEnabled
        result.tapActions = mergeCorners(top: (top.startTap, top.endTap), right: (right.startTap, right.endTap),
                                         bottom: (bottom.startTap, bottom.endTap), left: (left.startTap, left.endTap))
        return result
    }
}

private struct FlatSettings: Decodable {
    enum Action: String, Decodable {
        case disabled, volume, brightness
        var current: EdgeAction {
            switch self {
            case .disabled: .disabled
            case .volume: .volume
            case .brightness: .brightness
            }
        }
        var taps: (TapAction, TapAction) { self == .volume ? (.mute, .mute) : (.none, .none) }
    }
    let top: Action
    let right: Action
    let bottom: Action
    let left: Action
    let stripWidth: Double
    var currentSettings: EdgeSettings {
        var result = EdgeSettings.defaults
        for (edge, action) in [(TrackpadEdge.top, top), (.right, right), (.bottom, bottom), (.left, left)] {
            result[edge] = EdgeConfiguration(action: action.current)
        }
        result.stripWidth = stripWidth
        result.tapActions = mergeCorners(top: top.taps, right: right.taps, bottom: bottom.taps, left: left.taps)
        return result
    }
}

// Shared corners keep the horizontal assignment when enabled, otherwise the vertical one; new centers stay disabled.
private func mergeCorners(top: (TapAction, TapAction), right: (TapAction, TapAction),
                          bottom: (TapAction, TapAction), left: (TapAction, TapAction)) -> TapAssignments {
    TapAssignments(topLeft: top.0 != .none ? top.0 : left.1,
                   topRight: top.1 != .none ? top.1 : right.1,
                   bottomRight: bottom.1 != .none ? bottom.1 : right.0,
                   bottomLeft: bottom.0 != .none ? bottom.0 : left.0)
}

private enum SettingsStoreError: LocalizedError {
    case invalidRecord, invalidValues
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The saved settings are invalid."
        case .invalidValues: "Edge width must be 3% to 15% and sensitivity must be 0.25x to 3x."
        }
    }
}
