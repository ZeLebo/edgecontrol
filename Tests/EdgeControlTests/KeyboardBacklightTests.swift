import Testing
@testable import EdgeControl

@MainActor
struct KeyboardBacklightTests {
    @Test func discoversTheBuiltInBacklightAndPreservesTheFullIdentifier() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        #expect(try backlight.readBrightnessPercent() == 70)
        #expect(transport.readIDs.allSatisfy { $0 == transport.builtInID })
        #expect(transport.writes.isEmpty)
        backlight.stop()
        #expect(transport.stopCount == 1)
        #expect(throws: KeyboardBacklightError.self) { try backlight.readBrightnessPercent() }
    }

    @Test func absoluteLevelsReachTheHardwareBoundaryAsUnitScalars() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        for percent in [0, 50, 100] { try backlight.setBrightness(percent: percent) }
        #expect(transport.writes.map(\.scalar) == [0, 0.5, 1])
        #expect(transport.writes.allSatisfy { $0.id == transport.builtInID })
        for percent in [-1, 101] {
            #expect(throws: KeyboardBacklightError.self) { try backlight.setBrightness(percent: percent) }
        }
        #expect(transport.writes.count == 3)
    }

    @Test func relativeLevelsStartAtTheSystemReadingAndClampBeforeHardwareWrites() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        var levels = LevelAccumulator()
        try levels.start(at: backlight.readBrightnessPercent())
        for delta in [40.0, -1, -200, 1] {
            try backlight.setBrightness(percent: levels.apply(.relative(delta)))
        }
        #expect(transport.writes.map(\.scalar) == [1, 0.99, 0, 0.01])
    }

    @Test func missingExternalOnlyAndAmbiguousDevicesFailWithoutWriting() {
        for devices in [[], [KeyboardBacklightDevice(id: 7, isBuiltIn: false)], [
            KeyboardBacklightDevice(id: 7, isBuiltIn: true),
            KeyboardBacklightDevice(id: 8, isBuiltIn: true),
        ]] {
            let transport = RecordingKeyboard()
            transport.foundDevices = devices
            let backlight = KeyboardBacklight(transport: transport)
            #expect(throws: KeyboardBacklightError.self) { try backlight.start() }
            #expect(transport.writes.isEmpty)
        }
    }

    @Test func malformedReadingsDoNotEstablishAUsableBinding() {
        let invalidValues: [Float32] = [-0.1, 1.1, .nan, .infinity, -.infinity]
        for value in invalidValues {
            let transport = RecordingKeyboard()
            transport.scalar = value
            let backlight = KeyboardBacklight(transport: transport)
            #expect(throws: KeyboardBacklightError.self) { try backlight.start() }
            #expect(throws: KeyboardBacklightError.self) { try backlight.setBrightness(percent: 50) }
            #expect(transport.writes.isEmpty)
        }
    }

    @Test func togglesOffAndRestoresTheLastNonzeroSystemLevelAcrossPause() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        #expect(try backlight.toggle() == false)
        #expect(try backlight.toggle() == true)
        transport.scalar = 0.45
        #expect(try backlight.toggle() == false)
        backlight.stop()
        try backlight.start()
        #expect(try backlight.toggle() == true)
        #expect(transport.writes.map(\.scalar) == [0, 0.7, 0, 0.45])
    }

    @Test func initiallyOffBacklightUsesDocumentedRestoreLevelAndFailedWriteDoesNotReplaceIt() throws {
        let transport = RecordingKeyboard()
        transport.scalar = 0
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        transport.failWrite = true
        #expect(throws: TransportFailure.self) { try backlight.setBrightness(percent: 90) }
        transport.failWrite = false
        #expect(try backlight.toggle() == true)
        #expect(transport.writes.last?.scalar == 0.5)
    }

    @Test func changedDevicesInvalidateTheBindingAndDoNotInheritAnotherDevicesRestoreLevel() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        try backlight.start()
        transport.foundDevices = [KeyboardBacklightDevice(id: 12, isBuiltIn: true)]
        transport.scalar = 0
        #expect(throws: KeyboardBacklightError.self) { try backlight.readBrightnessPercent() }
        #expect(throws: KeyboardBacklightError.self) { try backlight.setBrightness(percent: 80) }
        #expect(transport.writes.isEmpty)
        try backlight.refresh()
        #expect(try backlight.toggle() == true)
        #expect(transport.writes.last?.id == 12)
        #expect(transport.writes.last?.scalar == 0.5)
    }

    @Test func transportFailuresPropagateAndRefreshCanRecover() throws {
        let transport = RecordingKeyboard()
        let backlight = KeyboardBacklight(transport: transport)
        transport.failDiscovery = true
        #expect(throws: TransportFailure.self) { try backlight.start() }
        transport.failDiscovery = false
        transport.failRead = true
        #expect(throws: TransportFailure.self) { try backlight.refresh() }
        transport.failRead = false
        try backlight.refresh()
        transport.failWrite = true
        #expect(throws: TransportFailure.self) { try backlight.toggle() }
        #expect(transport.scalar == 0.7)
        transport.failWrite = false
        #expect(try backlight.toggle() == false)
    }

    private enum TransportFailure: Error { case requested }

    private final class RecordingKeyboard: KeyboardBacklightTransport {
        struct Write { let scalar: Float32; let id: UInt64 }
        let builtInID: UInt64 = 0x1234_5678_abcd_ef01
        var foundDevices: [KeyboardBacklightDevice] = [
            KeyboardBacklightDevice(id: 99, isBuiltIn: false),
            KeyboardBacklightDevice(id: 0x1234_5678_abcd_ef01, isBuiltIn: true),
        ]
        var scalar: Float32 = 0.7
        var readIDs: [UInt64] = []
        var writes: [Write] = []
        var stopCount = 0
        var failDiscovery = false
        var failRead = false
        var failWrite = false

        func devices() throws -> [KeyboardBacklightDevice] {
            if failDiscovery { throw TransportFailure.requested }
            return foundDevices
        }

        func readBrightness(deviceID: UInt64) throws -> Float32 {
            readIDs.append(deviceID)
            if failRead { throw TransportFailure.requested }
            return scalar
        }

        func setBrightness(_ scalar: Float32, deviceID: UInt64) throws {
            if failWrite { throw TransportFailure.requested }
            writes.append(Write(scalar: scalar, id: deviceID))
            self.scalar = scalar
        }

        func stop() { stopCount += 1 }
    }
}
