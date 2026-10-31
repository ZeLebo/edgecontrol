import Foundation

@MainActor
final class SettingsStore {
    static let storageKey = "edgecontrol.settings.v2"

    private(set) var settings: EdgeSettings
    private(set) var loadError: String?
    var onChange: ((EdgeSettings) -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = .defaults
        guard let stored = defaults.object(forKey: Self.storageKey) else { return }
        do {
            guard let data = stored as? Data else { throw SettingsStoreError.invalidStoredSettings }
            let decoded = try JSONDecoder().decode(EdgeSettings.self, from: data)
            guard decoded.isValid else { throw SettingsStoreError.invalidStoredSettings }
            settings = decoded
        } catch {
            loadError = "Could not load settings. Using defaults."
        }
    }

    func update(_ value: EdgeSettings) throws {
        guard value.isValid else { throw SettingsStoreError.invalidWidth }
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: Self.storageKey)
        settings = value
        loadError = nil
        onChange?(value)
    }

    func reset() throws {
        try update(.defaults)
    }
}

private enum SettingsStoreError: LocalizedError {
    case invalidStoredSettings
    case invalidWidth

    var errorDescription: String? {
        switch self {
        case .invalidStoredSettings: "Stored settings are invalid"
        case .invalidWidth: "Edge width must be between 3% and 15%"
        }
    }
}
