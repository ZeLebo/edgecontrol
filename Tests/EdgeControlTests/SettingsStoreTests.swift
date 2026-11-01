import Foundation
import Testing
@testable import EdgeControl

@MainActor
struct SettingsStoreTests {
    @Test func firstLaunchUsesEightSharedZonesWithoutWriting() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.settings == .defaults)
            #expect(store.loadError == nil)
            #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
            #expect(TapZone.allCases.map(\.rawValue) == ["topLeft", "topCenter", "topRight", "rightCenter", "bottomRight", "bottomCenter", "bottomLeft", "leftCenter"])
            #expect(TrackpadEdge.top.tapZones == [.topLeft, .topCenter, .topRight])
            #expect(TrackpadEdge.right.tapZones == [.bottomRight, .rightCenter, .topRight])
            #expect(TrackpadEdge.bottom.tapZones == [.bottomLeft, .bottomCenter, .bottomRight])
            #expect(TrackpadEdge.left.tapZones == [.bottomLeft, .leftCenter, .topLeft])
            let positions: [TapZone: (Double, Double)] = [.topLeft: (0, 1), .topCenter: (0.5, 1), .topRight: (1, 1), .rightCenter: (1, 0.5), .bottomRight: (1, 0), .bottomCenter: (0.5, 0), .bottomLeft: (0, 0), .leftCenter: (0, 0.5)]
            for zone in TapZone.allCases {
                #expect(zone.position.x == positions[zone]?.0)
                #expect(zone.position.y == positions[zone]?.1)
                #expect(store.settings[zone] == ([TapZone.bottomLeft, .bottomRight].contains(zone) ? .mute : .none))
            }
        }
    }

    @Test func savesAllEdgeSettingsAndEightTapPointsBeforeNotifying() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            var settings = EdgeSettings.defaults
            settings.top = EdgeConfiguration(action: .brightness, mode: .relative, sensitivity: 0.25)
            settings.right = EdgeConfiguration(action: .disabled)
            settings.bottom = EdgeConfiguration(action: .seek, sensitivity: 3)
            settings.left = EdgeConfiguration(action: .volume, mode: .relative, sensitivity: 1.5)
            let actions: [TapAction] = [.seekBackward, .playPause, .seekForward, .nextTrack, .previousTrack, .none, .mute, .playPause]
            for (zone, action) in zip(TapZone.allCases, actions) { settings[zone] = action }
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
            let reloaded = SettingsStore(defaults: defaults, previousDefaults: nil).settings
            #expect(reloaded == settings)
            for (zone, action) in zip(TapZone.allCases, actions) { #expect(reloaded.tapActions[zone] == action) }
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

    @Test func corruptCurrentRecordDoesNotFallBackOrOverwriteOlderRecords() throws {
        try withDefaults { defaults in
            let previous = try v3Record()
            let flat = try flatRecord(bottom: "brightness")
            defaults.set(previous, forKey: SettingsStore.previousStorageKey)
            defaults.set(flat, forKey: SettingsStore.flatStorageKey)
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
                #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == previous)
                #expect(defaults.data(forKey: SettingsStore.flatStorageKey) == flat)
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
            settings[.bottomLeft] = .none
            settings[.topCenter] = .playPause
            try store.update(settings)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == settings)
            try store.reset()
            #expect(store.settings == .defaults)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == .defaults)
        }
    }

    @Test func importsOldDomainV2OnceAndPreservesOriginalRecord() throws {
        try withDefaults { defaults in
            try withDefaults { previous in
                let record = try flatRecord(bottom: "brightness", left: "volume", width: 0.09)
                previous.set(record, forKey: SettingsStore.legacyStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: previous)
                #expect(store.loadError == nil)
                #expect(store.settings.bottom.action == .brightness)
                #expect(store.settings.left.action == .volume)
                #expect(store.settings.stripWidth == 0.09)
                #expect(store.settings.left.mode == .absolute)
                #expect(store.settings.left.sensitivity == 1)
                #expect(store.settings[.topLeft] == .mute)
                #expect(store.settings[.bottomLeft] == .mute)
                #expect(store.settings[.bottomRight] == .none)
                #expect(store.settings.hapticsEnabled)
                #expect(defaults.data(forKey: SettingsStore.storageKey) != nil)
                #expect(previous.data(forKey: SettingsStore.legacyStorageKey) == record)
                var edited = store.settings
                edited.left.mode = .relative
                edited.left.sensitivity = 2
                edited[.leftCenter] = .seekForward
                try store.update(edited)
                #expect(SettingsStore(defaults: defaults, previousDefaults: previous).settings == edited)
                #expect(previous.data(forKey: SettingsStore.legacyStorageKey) == record)
            }
        }
    }

    @Test func currentDomainV2TakesPrecedenceOverOldDomainV2() throws {
        try withDefaults { defaults in
            try withDefaults { previous in
                let localRecord = try flatRecord(bottom: "volume", width: 0.08)
                defaults.set(localRecord, forKey: SettingsStore.flatStorageKey)
                previous.set(try flatRecord(bottom: "brightness"), forKey: SettingsStore.legacyStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: previous)
                #expect(store.settings.bottom.action == .volume)
                #expect(store.settings.stripWidth == 0.08)
                #expect(store.settings[.bottomLeft] == .mute)
                #expect(store.settings[.bottomRight] == .mute)
                #expect(defaults.data(forKey: SettingsStore.flatStorageKey) == localRecord)
            }
        }
    }

    @Test func invalidV2RecordIsVisibleAndNotReplaced() throws {
        try withDefaults { defaults in
            try withDefaults { previous in
                let oldValid = try flatRecord(bottom: "volume")
                previous.set(oldValid, forKey: SettingsStore.legacyStorageKey)
                for record in [try flatRecord(bottom: "unsupported"), try flatRecord(bottom: "volume", width: 0.01)] {
                    defaults.set(record, forKey: SettingsStore.flatStorageKey)
                    let store = SettingsStore(defaults: defaults, previousDefaults: previous)
                    #expect(store.loadError != nil)
                    #expect(store.settings == .defaults)
                    #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
                    #expect(defaults.data(forKey: SettingsStore.flatStorageKey) == record)
                    #expect(previous.data(forKey: SettingsStore.legacyStorageKey) == oldValid)
                }
            }
        }
    }

    @Test func earlierV3RecordsKeepRelativeSettingsAndMissingFieldDefaults() throws {
        try withDefaults { defaults in
            for savedHaptics in [nil, false, true] as [Bool?] {
                defaults.removeObject(forKey: SettingsStore.storageKey)
                let data = try v3Record(overrides: [.bottom: ["mode": "relative", "sensitivity": 1.75]], includesTaps: false, haptics: savedHaptics, width: 0.09)
                defaults.set(data, forKey: SettingsStore.previousStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                #expect(store.loadError == nil)
                #expect(store.settings.bottom.mode == .relative)
                #expect(store.settings.bottom.sensitivity == 1.75)
                #expect(store.settings.stripWidth == 0.09)
                #expect(store.settings[.bottomLeft] == .mute)
                #expect(store.settings[.bottomRight] == .mute)
                #expect(store.settings[.topRight] == .none)
                #expect(store.settings.hapticsEnabled == (savedHaptics ?? true))
                #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == data)
                #expect(defaults.data(forKey: SettingsStore.storageKey) != nil)
            }
        }
    }

    @Test func v3SharedCornersPreferEnabledHorizontalActionsOtherwiseVertical() throws {
        try withDefaults { defaults in
            let data = try v3Record(overrides: [
                .top: ["action": "seek", "mode": "relative", "sensitivity": 0.5, "startTap": "previousTrack", "endTap": "none"],
                .right: ["mode": "relative", "sensitivity": 2, "startTap": "seekForward", "endTap": "playPause"],
                .bottom: ["startTap": "none", "endTap": "mute"],
                .left: ["startTap": "seekBackward", "endTap": "nextTrack"]
            ], haptics: false, width: 0.12)
            defaults.set(data, forKey: SettingsStore.previousStorageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.loadError == nil)
            #expect(store.settings.top == EdgeConfiguration(action: .seek, mode: .relative, sensitivity: 0.5))
            #expect(store.settings.right == EdgeConfiguration(action: .brightness, mode: .relative, sensitivity: 2))
            #expect(store.settings.stripWidth == 0.12)
            #expect(!store.settings.hapticsEnabled)
            #expect(store.settings[.topLeft] == .previousTrack)
            #expect(store.settings[.topRight] == .playPause)
            #expect(store.settings[.bottomRight] == .mute)
            #expect(store.settings[.bottomLeft] == .seekBackward)
            for zone in [TapZone.topCenter, .rightCenter, .bottomCenter, .leftCenter] { #expect(store.settings[zone] == .none) }
            #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == data)
        }
    }

    @Test func v3ImportRunsOnceAndPreservesOriginalAfterNewSave() throws {
        try withDefaults { defaults in
            let data = try v3Record(overrides: [.top: ["startTap": "playPause"]])
            defaults.set(data, forKey: SettingsStore.previousStorageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            var current = store.settings
            current[.topLeft] = .none
            current[.topCenter] = .nextTrack
            try store.update(current)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == current)
            #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == data)
        }
    }

    @Test func v3TakesPrecedenceOverV2AndCurrentV4WinsOverBoth() throws {
        try withDefaults { defaults in
            let v3 = try v3Record(overrides: [.bottom: ["action": "seek"]])
            let v2 = try flatRecord(bottom: "brightness")
            defaults.set(v3, forKey: SettingsStore.previousStorageKey)
            defaults.set(v2, forKey: SettingsStore.flatStorageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            #expect(store.settings.bottom.action == .seek)
            var current = store.settings
            current.bottom.action = .tracks
            current[.bottomCenter] = .playPause
            try store.update(current)
            defaults.set("invalid v3", forKey: SettingsStore.previousStorageKey)
            defaults.set("invalid v2", forKey: SettingsStore.flatStorageKey)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).settings == current)
        }
    }

    @Test func corruptV3FieldsDoNotFallBackToV2OrTreatNullAsMissing() throws {
        try withDefaults { defaults in
            let flat = try flatRecord(bottom: "brightness")
            defaults.set(flat, forKey: SettingsStore.flatStorageKey)
            for field in ["hapticsEnabled", "startTap", "endTap", "sensitivity"] {
                var record = try #require(JSONSerialization.jsonObject(with: v3Record()) as? [String: Any])
                if field == "hapticsEnabled" { record[field] = NSNull() }
                else {
                    var bottom = try #require(record["bottom"] as? [String: Any])
                    bottom[field] = NSNull()
                    record["bottom"] = bottom
                }
                let data = try JSONSerialization.data(withJSONObject: record)
                defaults.set(data, forKey: SettingsStore.previousStorageKey)
                let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                #expect(store.loadError != nil)
                #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
                #expect(defaults.data(forKey: SettingsStore.previousStorageKey) == data)
                #expect(defaults.data(forKey: SettingsStore.flatStorageKey) == flat)
            }
            let invalid = try v3Record(overrides: [.left: ["sensitivity": 9]])
            defaults.set(invalid, forKey: SettingsStore.previousStorageKey)
            #expect(SettingsStore(defaults: defaults, previousDefaults: nil).loadError != nil)
            #expect(defaults.object(forKey: SettingsStore.storageKey) == nil)
        }
    }

    @Test func currentV4RequiresValidCompleteTapAssignments() throws {
        try withDefaults { defaults in
            let encoded = try JSONEncoder().encode(EdgeSettings.defaults)
            for field in ["tapActions", "hapticsEnabled"] {
                for null in [false, true] {
                    var record = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    if null { record[field] = NSNull() } else { record.removeValue(forKey: field) }
                    let data = try JSONSerialization.data(withJSONObject: record)
                    defaults.set(data, forKey: SettingsStore.storageKey)
                    let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                    #expect(store.loadError != nil)
                    #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
                }
            }
            for zone in TapZone.allCases {
                for invalid in [nil, NSNull(), "unsupported"] as [Any?] {
                    var record = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    var actions = try #require(record["tapActions"] as? [String: Any])
                    actions[zone.rawValue] = invalid
                    record["tapActions"] = actions
                    let data = try JSONSerialization.data(withJSONObject: record)
                    defaults.set(data, forKey: SettingsStore.storageKey)
                    let store = SettingsStore(defaults: defaults, previousDefaults: nil)
                    #expect(store.loadError != nil)
                    #expect(defaults.data(forKey: SettingsStore.storageKey) == data)
                }
            }
        }
    }

    @Test func v2VolumeAssignmentsPopulateAllRelevantCornersAndNoCenters() throws {
        try withDefaults { defaults in
            let data = try flatRecord(top: "volume", right: "volume", bottom: "volume", left: "volume")
            defaults.set(data, forKey: SettingsStore.flatStorageKey)
            let store = SettingsStore(defaults: defaults, previousDefaults: nil)
            for zone in TapZone.allCases {
                let corner = zone.position.x != 0.5 && zone.position.y != 0.5
                #expect(store.settings[zone] == (corner ? .mute : .none))
            }
            #expect(defaults.data(forKey: SettingsStore.flatStorageKey) == data)
        }
    }

    private func v3Record(overrides: [TrackpadEdge: [String: Any]] = [:], includesTaps: Bool = true,
                          haptics: Bool? = true, width: Double = 0.05) throws -> Data {
        var record: [String: Any] = ["stripWidth": width]
        if let haptics { record["hapticsEnabled"] = haptics }
        for edge in TrackpadEdge.allCases {
            let initial = EdgeSettings.defaults[edge]
            var configuration: [String: Any] = ["action": initial.action.rawValue, "mode": initial.mode.rawValue, "sensitivity": initial.sensitivity]
            if includesTaps {
                let tap = initial.action == .volume ? "mute" : "none"
                configuration["startTap"] = tap
                configuration["endTap"] = tap
            }
            configuration.merge(overrides[edge] ?? [:]) { _, new in new }
            record[edge.rawValue] = configuration
        }
        return try JSONSerialization.data(withJSONObject: record)
    }

    private func flatRecord(top: String = "disabled", right: String = "brightness", bottom: String,
                            left: String = "disabled", width: Double = 0.05) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["top": top, "right": right, "bottom": bottom, "left": left, "stripWidth": width])
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "EdgeControlTests.SettingsStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
