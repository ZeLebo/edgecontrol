import Foundation
import Testing
@testable import EdgeControl

@MainActor
struct ShortcutBindingsTests {
    @Test func directionalAndTapBindingsRemainSeparatePerProfileUnderTheGlobalSwitch() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            let firstID = store.activeProfileID
            let negative = try #require(KeyboardShortcut.functionKey(13, modifiers: .control))
            let positive = try #require(KeyboardShortcut.functionKey(24, modifiers: .command))
            let tap = try #require(KeyboardShortcut.functionKey(23, modifiers: [.option, .shift]))
            var value = store.settings
            value.bottom = EdgeConfiguration(action: .shortcut, sensitivity: 1.5, negativeShortcut: negative, positiveShortcut: positive)
            value[TapZone.topRight] = .shortcut
            value.tapShortcuts[TapZone.topRight.rawValue] = tap
            try store.update(value)
            try store.setProfileSwitchZone(.topRight)
            #expect(store.gestureSettings[TapZone.topRight] == .nextProfile)
            #expect(store.settings.tapShortcuts[TapZone.topRight.rawValue] == tap)
            try store.nextProfile()
            #expect(store.settings.bottom.action != .shortcut)
            try store.selectProfile(id: firstID)
            #expect(store.settings == value)
            let reloaded = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(reloaded.loadError == nil)
            #expect(reloaded.settings.bottom.negativeShortcut == negative)
            #expect(reloaded.settings.bottom.positiveShortcut == positive)
            try reloaded.setProfileSwitchZone(nil)
            #expect(reloaded.gestureSettings[TapZone.topRight] == .shortcut)
            #expect(reloaded.gestureSettings.tapShortcuts[TapZone.topRight.rawValue] == tap)
        }
    }

    @Test func missingOrInvalidShortcutBindingsCannotReplaceSavedSettings() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            let original = defaults.data(forKey: SettingsStore.storageKey)
            var bad = store.settings
            bad.bottom.action = .shortcut
            #expect(throws: (any Error).self) { try store.update(bad) }
            bad = store.settings
            bad[TapZone.topLeft] = .shortcut
            #expect(throws: (any Error).self) { try store.update(bad) }
            bad = store.settings
            bad.tapShortcuts["unknownPoint"] = KeyboardShortcut(keyCode: 0)
            #expect(throws: (any Error).self) { try store.update(bad) }
            bad = store.settings
            bad.tapShortcuts[TapZone.topLeft.rawValue] = KeyboardShortcut(keyCode: 255)
            #expect(throws: (any Error).self) { try store.update(bad) }
            #expect(defaults.data(forKey: SettingsStore.storageKey) == original)
        }
    }

    @Test func earlierProfileRecordsWithoutShortcutFieldsPreserveIdentityAndSettings() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            let id = store.activeProfileID
            let original = store.settings
            let record = try #require(defaults.data(forKey: SettingsStore.storageKey))
            var json = try #require(JSONSerialization.jsonObject(with: record) as? [String: Any])
            var profiles = try #require(json["profiles"] as? [[String: Any]])
            for index in profiles.indices {
                var settings = try #require(profiles[index]["settings"] as? [String: Any])
                settings.removeValue(forKey: "tapShortcuts")
                profiles[index]["settings"] = settings
            }
            json["profiles"] = profiles
            defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: SettingsStore.storageKey)
            let restored = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(restored.loadError == nil)
            #expect(restored.activeProfileID == id)
            #expect(restored.settings == original)
        }
    }

    @Test func nullShortcutDictionaryIsRejectedWithoutOverwritingTheRecord() throws {
        try withDefaults { defaults in
            _ = SettingsStore(defaults: defaults, previousDefaults: nil)
            let record = try #require(defaults.data(forKey: SettingsStore.storageKey))
            var json = try #require(JSONSerialization.jsonObject(with: record) as? [String: Any])
            var profiles = try #require(json["profiles"] as? [[String: Any]])
            var settings = try #require(profiles[0]["settings"] as? [String: Any])
            settings["tapShortcuts"] = NSNull()
            profiles[0]["settings"] = settings
            json["profiles"] = profiles
            let data = try JSONSerialization.data(withJSONObject: json)
            defaults.set(data, forKey: SettingsStore.storageKey)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).loadError != nil)
            #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "EdgeControlTests.ShortcutBindings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
