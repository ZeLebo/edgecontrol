import Foundation
import Testing
@testable import EdgeControl

@MainActor
struct SettingsStoreTests {
    @Test func firstLaunchUsesDefaultsWithoutWriting() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            #expect(store.settings == .defaults)
            #expect(store.loadError == nil)
            #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
        }
    }

    @Test func savesAllAssignmentsBeforeNotifyingAndRestoresThem() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var settings = EdgeSettings.defaults
            settings.top = .brightness
            settings.right = .disabled
            settings.bottom = .brightness
            settings.left = .volume
            settings.stripWidth = 0.15
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
            #expect(SettingsStore(defaults: defaults).settings == settings)
        }
    }

    @Test func invalidUpdateDoesNotChangeStoredOrCurrentSettings() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            try store.update(.defaults)
            let original = defaults.data(forKey: SettingsStore.storageKey)
            var notifications = 0
            store.onChange = { _ in notifications += 1 }
            for width in [0.02, 0.16, Double.nan, Double.infinity] {
                var invalid = EdgeSettings.defaults
                invalid.stripWidth = width
                #expect(throws: (any Error).self) { try store.update(invalid) }
                #expect(store.settings == .defaults)
                #expect(defaults.data(forKey: SettingsStore.storageKey) == original)
            }
            #expect(notifications == 0)
        }
    }

    @Test func corruptRecordIsVisibleAndOnlyResetReplacesIt() throws {
        try withDefaults { defaults in
            var invalid = EdgeSettings.defaults
            invalid.stripWidth = 0.01
            let records: [Any] = ["wrong-type", Data("{bad json".utf8), try JSONEncoder().encode(invalid)]
            for record in records {
                defaults.set(record, forKey: SettingsStore.storageKey)
                let store = SettingsStore(defaults: defaults)
                #expect(store.settings == .defaults)
                #expect(store.loadError != nil)
                if let data = record as? Data {
                    #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
                } else {
                    #expect(defaults.string(forKey: SettingsStore.storageKey) == record as? String)
                }
                try store.reset()
                #expect(store.loadError == nil)
                #expect(SettingsStore(defaults: defaults).settings == .defaults)
            }
        }
    }

    @Test func lowerWidthBoundaryAndResetArePersisted() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var settings = EdgeSettings.defaults
            settings.stripWidth = 0.03
            settings.bottom = .disabled
            try store.update(settings)
            #expect(SettingsStore(defaults: defaults).settings == settings)
            try store.reset()
            #expect(store.settings == .defaults)
            #expect(SettingsStore(defaults: defaults).settings == .defaults)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "EdgeControlTests.SettingsStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
