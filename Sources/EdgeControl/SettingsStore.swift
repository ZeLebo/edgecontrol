import Foundation

@MainActor
final class SettingsStore {
    static let storageKey = "edgecontrol.settings.v5"
    static let previousStorageKey = "edgecontrol.settings.v4"
    static let edgeStorageKey = "edgecontrol.settings.v3"
    static let flatStorageKey = "edgecontrol.settings.v2"
    // One-time import from the previous application's domain; never used after a v5 record exists.
    static let legacyDomain = "local.edgebar.app"
    static let legacyStorageKey = "edgebar.settings.v2"

    private var document: ProfileDocument
    private(set) var loadError: String?
    var onChange: ((EdgeSettings) -> Void)?
    private let defaults: UserDefaults

    var excludedAppIDs: [String] { document.excludedAppIDs }
    var profiles: [ControlProfile] { document.profiles }
    var activeProfileID: UUID { document.activeProfileID }
    var activeProfileName: String { document.profiles[activeProfileIndex].name }
    var profileSwitchZone: TapZone? { document.profileSwitchZone }
    var settings: EdgeSettings { document.profiles[activeProfileIndex].settings }
    var gestureSettings: EdgeSettings {
        var value = settings
        if let profileSwitchZone { value[profileSwitchZone] = .nextProfile }
        return value
    }
    private var activeProfileIndex: Int {
        // Every loaded or saved document is validated before replacing the active state.
        document.profiles.firstIndex { $0.id == document.activeProfileID }!
    }

    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, previousDefaults: UserDefaults(suiteName: Self.legacyDomain))
    }

    init(defaults: UserDefaults, previousDefaults: UserDefaults?) {
        self.defaults = defaults
        document = Self.initialDocument(settings: .defaults)
        if let record = defaults.object(forKey: Self.storageKey) {
            do {
                guard let data = record as? Data else { throw SettingsStoreError.invalidRecord }
                let value = try JSONDecoder().decode(ProfileDocument.self, from: data)
                guard value.isValid else { throw SettingsStoreError.invalidRecord }
                document = value
            } catch {
                loadError = "Saved profiles could not be read. Defaults are active until you save or reset."
            }
            return
        }
        do {
            let initial: EdgeSettings
            if let record = defaults.object(forKey: Self.previousStorageKey) {
                guard let data = record as? Data else { throw SettingsStoreError.invalidRecord }
                initial = try JSONDecoder().decode(EdgeSettings.self, from: data)
            } else if let record = defaults.object(forKey: Self.edgeStorageKey) {
                guard let data = record as? Data else { throw SettingsStoreError.invalidRecord }
                initial = try JSONDecoder().decode(PreviousSettings.self, from: data).currentSettings
            } else if let record = defaults.object(forKey: Self.flatStorageKey)
                ?? previousDefaults?.object(forKey: Self.legacyStorageKey) {
                guard let data = record as? Data else { throw SettingsStoreError.invalidRecord }
                initial = try JSONDecoder().decode(FlatSettings.self, from: data).currentSettings
            } else {
                initial = .defaults
            }
            let value = Self.initialDocument(settings: initial)
            guard value.isValid else { throw SettingsStoreError.invalidRecord }
            // Persist the seed once so profile identities survive a restart before the first edit.
            defaults.set(try JSONEncoder().encode(value), forKey: Self.storageKey)
            document = value
        } catch {
            loadError = "Previous settings could not be imported. Defaults are active until you save or reset."
        }
    }

    func update(_ value: EdgeSettings) throws {
        guard value.isValid else { throw SettingsStoreError.invalidValues }
        guard TapZone.allCases.allSatisfy({ value[$0] != .nextProfile }) else {
            throw SettingsStoreError.globalSwitchOnly
        }
        var changed = document
        changed.profiles[activeProfileIndex].settings = value
        try save(changed)
    }

    func reset() throws { try update(.defaults) }

    func selectProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw SettingsStoreError.profileNotFound }
        var changed = document
        changed.activeProfileID = id
        try save(changed)
    }

    func nextProfile() throws {
        try selectProfile(id: profiles[(activeProfileIndex + 1) % profiles.count].id)
    }

    @discardableResult
    func createProfile(named name: String) throws -> UUID {
        let profile = ControlProfile(name: try validName(name))
        var changed = document
        changed.profiles.append(profile)
        changed.activeProfileID = profile.id
        try save(changed)
        return profile.id
    }

    @discardableResult
    func duplicateProfile(id: UUID, named name: String) throws -> UUID {
        guard let original = profiles.first(where: { $0.id == id }) else { throw SettingsStoreError.profileNotFound }
        let profile = ControlProfile(name: try validName(name), settings: original.settings)
        var changed = document
        changed.profiles.append(profile)
        changed.activeProfileID = profile.id
        try save(changed)
        return profile.id
    }

    func renameProfile(id: UUID, to name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SettingsStoreError.profileNotFound }
        let name = try validName(name, excluding: id)
        var changed = document
        changed.profiles[index].name = name
        try save(changed)
    }

    func deleteProfile(id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SettingsStoreError.profileNotFound }
        guard profiles.count > 1 else { throw SettingsStoreError.lastProfile }
        var changed = document
        changed.profiles.remove(at: index)
        if changed.activeProfileID == id {
            changed.activeProfileID = changed.profiles[min(index, changed.profiles.count - 1)].id
        }
        try save(changed)
    }

    func setProfileSwitchZone(_ zone: TapZone?) throws {
        var changed = document
        changed.profileSwitchZone = zone
        try save(changed)
    }

    func setExcludedAppIDs(_ bundleIDs: [String]) throws {
        var changed = document
        changed.excludedAppIDs = bundleIDs
        try save(changed)
    }

    private func validName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw SettingsStoreError.invalidName }
        guard !profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw SettingsStoreError.duplicateName
        }
        return trimmed
    }

    private func save(_ value: ProfileDocument) throws {
        guard value.isValid else { throw SettingsStoreError.invalidRecord }
        defaults.set(try JSONEncoder().encode(value), forKey: Self.storageKey)
        document = value
        loadError = nil
        onChange?(settings)
    }

    private static func initialDocument(settings: EdgeSettings) -> ProfileDocument {
        let everyday = ControlProfile(name: "Everyday", settings: settings)
        var mediaSettings = settings
        mediaSettings.bottom.action = .volume
        mediaSettings.right.action = .tracks
        mediaSettings.right.mode = .relative
        mediaSettings.top.action = .seek
        mediaSettings.top.mode = .relative
        mediaSettings.left.action = .brightness
        let media = ControlProfile(name: "Media", settings: mediaSettings)
        return ProfileDocument(profiles: [everyday, media], activeProfileID: everyday.id, profileSwitchZone: nil)
    }
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
    case invalidRecord, invalidValues, globalSwitchOnly, profileNotFound, lastProfile, invalidName, duplicateName
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The saved profiles are invalid."
        case .invalidValues: "Edge width must be 1% to 15% and sensitivity must be 0.25x to 3x."
        case .globalSwitchOnly: "Assign Next Profile with the global profile switch point."
        case .profileNotFound: "The selected profile no longer exists."
        case .lastProfile: "Keep at least one profile."
        case .invalidName: "Profile names must contain 1 to 40 characters."
        case .duplicateName: "A profile with this name already exists."
        }
    }
}
