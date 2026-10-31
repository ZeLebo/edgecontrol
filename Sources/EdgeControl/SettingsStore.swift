import Foundation

@MainActor
final class SettingsStore {
    static let storageKey = "edgecontrol.settings.v3"
    static let previousStorageKey = "edgecontrol.settings.v2"
    // One-time import from the previous application's domain; never used after a v3 record exists.
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
            ?? previousDefaults?.object(forKey: Self.legacyStorageKey)
        guard let previous else { return }
        do {
            guard let data = previous as? Data else { throw SettingsStoreError.invalidRecord }
            let legacy = try JSONDecoder().decode(PreviousSettings.self, from: data)
            guard legacy.isValid else { throw SettingsStoreError.invalidRecord }
            let value = legacy.currentSettings
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
    enum Action: String, Decodable {
        case disabled, volume, brightness
        var current: EdgeAction {
            switch self {
            case .disabled: .disabled
            case .volume: .volume
            case .brightness: .brightness
            }
        }
    }
    let top: Action
    let right: Action
    let bottom: Action
    let left: Action
    let stripWidth: Double
    var isValid: Bool { stripWidth.isFinite && EdgeSettings.allowedStripWidths.contains(stripWidth) }
    var currentSettings: EdgeSettings {
        var result = EdgeSettings.defaults
        for (edge, action) in [(TrackpadEdge.top, top), (.right, right), (.bottom, bottom), (.left, left)] {
            result[edge] = EdgeConfiguration(
                action: action.current,
                startTap: action == .volume ? .mute : .none,
                endTap: action == .volume ? .mute : .none
            )
        }
        result.stripWidth = stripWidth
        return result
    }
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
