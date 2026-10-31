import Foundation
import Testing
@testable import EdgeControl

@MainActor
struct SettingsStoreTests {
    @Test func firstLaunchUsesDefaultsWithoutWriting() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.settings == .defaults)
            #expect(store.loadError == nil)
            #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
        }
    }

    @Test func savesAllAssignmentsModesAndSensitivityBeforeNotifying() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            var settings = EdgeSettings.defaults
            settings.top = EdgeConfiguration(action: .brightness, mode: .relative, sensitivity: 0.25)
            settings.right = EdgeConfiguration(action: .disabled)
            settings.bottom = EdgeConfiguration(action: .volume, mode: .relative, sensitivity: 3)
            settings.left = EdgeConfiguration(action: .volume, mode: .relative, sensitivity: 1.5)
            settings.stripWidth = 0.15
            settings.hapticsEnabled = false
            var notifications = 0
            store.onChange = { value in
                notifications += 1
                #expect(value == settings)
                #expect(store.settings == settings)
                let stored = defaults.data(forKey: SettingsStore.storageKey)
                #expect(stored.flatMap { try? JSONDecoder().decode(EdgeSettings.self, from: $0) } == settings)
            }
            try store.update(settings)
            #expect(notifications == 1)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == settings)
        }
    }

    @Test func invalidUpdateDoesNotChangeStoredOrCurrentSettings() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            try store.update(.defaults)
            let original = defaults.data(forKey: SettingsStore.storageKey)
            var notifications = 0
            store.onChange = { _ in notifications += 1 }
            var invalidValues: [EdgeSettings] = []
            for width in [0.02, 0.16, Double.nan, Double.infinity] {
                var invalid = EdgeSettings.defaults
                invalid.stripWidth = width
                invalidValues.append(invalid)
            }
            for edge in TrackpadEdge.allCases {
                for sensitivity in [0.24, 3.01, Double.nan, Double.infinity] {
                    var invalid = EdgeSettings.defaults
                    invalid[edge].sensitivity = sensitivity
                    invalidValues.append(invalid)
                }
            }
            for invalid in invalidValues {
                #expect(throws: (any Error).self) { try store.update(invalid) }
                #expect(store.settings == .defaults)
                #expect(defaults.data(forKey: SettingsStore.storageKey) == original)
            }
            #expect(notifications == 0)
        }
    }

    @Test func corruptCurrentRecordDoesNotFallBackToLegacyOrOverwriteIt() throws {
        try withDefaults { defaults in
            let legacy = try legacyRecord(bottom: "brightness")
            defaults.set(legacy, forKey: SettingsStore.previousStorageKey)
            var invalid = EdgeSettings.defaults
            invalid.stripWidth = 0.01
            let records: [Any] = ["wrong-type", Data("{bad json".utf8), try JSONEncoder().encode(invalid)]
            for record in records {
                defaults.set(record, forKey: SettingsStore.storageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                #expect(store.settings == .defaults)
                #expect(store.loadError != nil)
                if let data = record as? Data { #expect(defaults.data(forKey: SettingsStore.storageKey) == data) }
                else { #expect(defaults.string(forKey: SettingsStore.storageKey) == record as? String) }
                #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == legacy)
                try store.reset()
                #expect(store.loadError == nil)
                #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == .defaults)
            }
        }
    }

    @Test func lowerWidthBoundaryAndResetArePersisted() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            var settings = EdgeSettings.defaults
            settings.stripWidth = 0.03
            settings.bottom = EdgeConfiguration(action: .disabled)
            try store.update(settings)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == settings)
            try store.reset()
            #expect(store.settings == .defaults)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == .defaults)
        }
    }

    @Test func importsPreviousDomainOnceAndPreservesOriginalRecord() throws {
        try withDefaults { defaults in
            try withDefaults { previous in
                let record = try legacyRecord(bottom: "brightness", left: "volume", width: 0.09)
                previous.set(record, forKey: SettingsStore.legacyStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: previous)
                #expect(store.loadError == nil)
                #expect(store.settings.bottom.action == .brightness)
                #expect(store.settings.left.action == .volume)
                #expect(store.settings.stripWidth == 0.09)
                #expect(store.settings.left.mode == .absolute)
                #expect(store.settings.left.sensitivity == 1)
                #expect(defaults.data(forKey: SettingsStore.storageKey) != nil)
                #expect(previous.data(forKey: SettingsStore.legacyStorageKey) == record)
                var edited = store.settings
                edited.left.mode = .relative
                edited.left.sensitivity = 2
                try store.update(edited)
                #expect(SettingsStore(defaults: defaults, previousDefaults: previous).settings == edited)
                #expect(previous.data(forKey: SettingsStore.legacyStorageKey) == record)
            }
        }
    }

    @Test func currentDomainLegacyRecordTakesPrecedenceAndValidCurrentRecordWins() throws {
        try withDefaults { defaults in
            try withDefaults { previous in
                let localRecord = try legacyRecord(bottom: "volume", width: 0.08)
                defaults.set(localRecord, forKey: SettingsStore.previousStorageKey)
                previous.set(try legacyRecord(bottom: "brightness"), forKey: SettingsStore.legacyStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: previous)
                #expect(store.settings.bottom.action == .volume)
                #expect(store.settings.stripWidth == 0.08)
                #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == localRecord)
                var current = store.settings
                current.bottom.mode = .relative
                current.top.action = .brightness
                try store.update(current)
                defaults.set("invalid old data", forKey: SettingsStore.previousStorageKey)
                #expect(SettingsStore(defaults: defaults, previousDefaults: previous).settings == current)
            }
        }
    }

    @Test func invalidLegacyRecordIsVisibleAndNotReplaced() throws {
        try withDefaults { defaults in
            let invalid = try legacyRecord(bottom: "unsupported", width: 0.05)
            defaults.set(invalid, forKey: SettingsStore.previousStorageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.loadError != nil)
            #expect(store.settings == .defaults)
            #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
            #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == invalid)
        }
    }

    @Test func earlierV3RecordsKeepRelativeSettingsAndEnableHaptics() throws {
        try withDefaults { defaults in
            var settings = EdgeSettings.defaults
            settings.bottom.mode = .relative
            settings.bottom.sensitivity = 2
            settings.stripWidth = 0.09
            var record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            record.removeValue(forKey: "hapticsEnabled")
            let data = try JSONSerialization.data(withJSONObject: record)
            defaults.set(data, forKey: SettingsStore.storageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.loadError == nil)
            #expect(store.settings == settings)
            #expect(store.settings.hapticsEnabled)
            #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
        }
    }

    @Test func invalidPresentHapticsPreferenceIsNotTreatedAsAnUpgradeDefault() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = [NSNull(), "true", 7]
            for invalid in invalidValues {
                var record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(EdgeSettings.defaults)) as? [String: Any])
                record["hapticsEnabled"] = invalid
                let data = try JSONSerialization.data(withJSONObject: record)
                defaults.set(data, forKey: SettingsStore.storageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                #expect(store.loadError != nil)
                #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
            }
        }
    }

    private func legacyRecord(bottom: String, left: String = "disabled", width: Double = 0.05) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["top": "disabled", "right": "brightness", "bottom": bottom, "left": left, "stripWidth": width])
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "EdgeControlTests.SettingsStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
