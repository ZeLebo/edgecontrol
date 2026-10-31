import CoreAudio
import Foundation

@MainActor
final class AudioOutput {
    var onChange: (() -> Void)?

    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var listeners: [Listener] = []
    private var device: AudioDeviceID = kAudioObjectUnknown
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var muteElements: [AudioObjectPropertyElement] = []
    private var isReady = false
    private var generation = 0
    private var deviceGeneration = 0

    /// The default-device listener survives an unsupported output so a later switch can recover.
    func start() throws {
        if !listeners.contains(where: { $0.object == kAudioObjectSystemObject }) {
            try listen(
                object: AudioObjectID(kAudioObjectSystemObject),
                address: address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            )
        }
        try refresh()
    }

    func refresh() throws {
        deviceGeneration += 1
        isReady = false
        volumeElements = []
        muteElements = []
        removeListeners(forDeviceOnly: true)
        device = try defaultDevice()
        guard device != kAudioObjectUnknown else {
            throw AudioOutputError("No audio output selected")
        }

        let observedProperties = [
            address(kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal),
            address(kAudioDevicePropertyStreamConfiguration),
            address(kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal),
        ]
        for var property in observedProperties where AudioObjectHasProperty(device, &property) {
            try listen(object: device, address: property)
        }

        let alive = try readUInt32(device, address(kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal))
        guard alive != 0 else { throw AudioOutputError("Audio output is unavailable") }
        let count = try outputChannelCount()
        guard count > 0 else { throw AudioOutputError("Audio output has no channels") }
        let channels = Array(1...count)
        if try isWritable(device, address(kAudioDevicePropertyVolumeScalar)) {
            volumeElements = [kAudioObjectPropertyElementMain]
        } else {
            // Every output channel must be controllable for the left edge to mean silence.
            for channel in channels {
                guard try isWritable(device, address(kAudioDevicePropertyVolumeScalar, element: channel)) else {
                    throw AudioOutputError("Output does not support volume control")
                }
            }
            volumeElements = channels
        }
        for element in [kAudioObjectPropertyElementMain] + channels {
            if try isWritable(device, address(kAudioDevicePropertyMute, element: element)) {
                muteElements.append(element)
            }
        }
        guard try defaultDevice() == device else {
            throw AudioOutputError("Audio output changed")
        }
        isReady = true
    }

    func setVolume(percent: Int) throws {
        guard (0...100).contains(percent) else { throw AudioOutputError("Invalid volume") }
        try requireCurrentDevice()
        var scalar = Float32(percent) / 100
        for element in volumeElements {
            try requireCurrentDevice()
            var property = address(kAudioDevicePropertyVolumeScalar, element: element)
            try check(
                AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar),
                "Could not set volume, channel \(element)"
            )
        }
        if percent > 0 {
            var unmuted: UInt32 = 0
            for element in muteElements {
                try requireCurrentDevice()
                var property = address(kAudioDevicePropertyMute, element: element)
                try check(
                    AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted),
                    "Could not unmute, channel \(element)"
                )
            }
        }
    }

    func toggleMute() throws -> Bool {
        try requireCurrentDevice()
        guard !muteElements.isEmpty else { throw AudioOutputError("Output does not support mute control") }
        let observed = muteElements.contains(kAudioObjectPropertyElementMain)
            ? [kAudioObjectPropertyElementMain] : muteElements
        let muted = try observed.allSatisfy {
            try readUInt32(device, address(kAudioDevicePropertyMute, element: $0)) != 0
        }
        var value: UInt32 = muted ? 0 : 1
        for element in muteElements {
            try requireCurrentDevice()
            var property = address(kAudioDevicePropertyMute, element: element)
            try check(AudioObjectSetPropertyData(device, &property, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &value), "Could not toggle mute, channel \(element)")
        }
        return !muted
    }

    /// Reports the scalar level; per-channel outputs use their mean. Mute is separate.
    func readVolumePercent() throws -> Int {
        try requireCurrentDevice()
        var sum: Float = 0
        for element in volumeElements {
            var property = address(kAudioDevicePropertyVolumeScalar, element: element)
            var scalar: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, &scalar), "Could not read volume")
            guard size == MemoryLayout<Float32>.size, scalar.isFinite, (0...1).contains(scalar) else {
                throw AudioOutputError("Audio output returned an invalid volume")
            }
            sum += scalar
        }
        return Int((100 * sum / Float(volumeElements.count)).rounded())
    }

    func stop() {
        generation += 1
        isReady = false
        removeListeners(forDeviceOnly: false)
        device = kAudioObjectUnknown
        volumeElements = []
        muteElements = []
    }

    private func requireCurrentDevice() throws {
        guard isReady, !volumeElements.isEmpty else { throw AudioOutputError("Audio output is not ready") }
        guard try defaultDevice() == device else {
            isReady = false
            throw AudioOutputError("Audio output changed")
        }
    }

    private func defaultDevice() throws -> AudioDeviceID {
        try readUInt32(
            AudioObjectID(kAudioObjectSystemObject),
            address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        )
    }

    private func outputChannelCount() throws -> UInt32 {
        var property = address(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size), "Could not read output channels")
        let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
        guard size >= offset else { throw AudioOutputError("Invalid audio output configuration") }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, storage), "Could not read output channels")
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        guard Int(list.pointee.mNumberBuffers) <= (Int(size) - offset) / MemoryLayout<AudioBuffer>.stride else {
            throw AudioOutputError("Invalid audio output configuration")
        }
        return UnsafeMutableAudioBufferListPointer(list).reduce(UInt32(0)) { $0 + $1.mNumberChannels }
    }

    private func listen(object: AudioObjectID, address property: AudioObjectPropertyAddress) throws {
        var property = property
        let currentGeneration = generation
        let currentDeviceGeneration = deviceGeneration
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == currentGeneration else { return }
                guard object == kAudioObjectSystemObject || self.deviceGeneration == currentDeviceGeneration else { return }
                self.isReady = false
                self.onChange?()
            }
        }
        try check(AudioObjectAddPropertyListenerBlock(object, &property, .main, block), "Could not observe the audio output")
        listeners.append(Listener(object: object, address: property, block: block))
    }

    private func removeListeners(forDeviceOnly: Bool) {
        var kept: [Listener] = []
        for var listener in listeners {
            if forDeviceOnly && listener.object == kAudioObjectSystemObject {
                kept.append(listener)
                continue
            }
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
            if status != noErr {
                NSLog("EdgeControl: AudioObjectRemovePropertyListenerBlock: %d", status)
            }
        }
        listeners = kept
    }

    private func isWritable(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> Bool {
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return false }
        var writable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(object, &property, &writable), "Could not check volume control")
        return writable.boolValue
    }

    private func readUInt32(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> UInt32 {
        var property = property
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "Could not read audio output")
        guard size == MemoryLayout<UInt32>.size else { throw AudioOutputError("Invalid audio output response") }
        return value
    }

    private func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func check(_ status: OSStatus, _ message: String) throws {
        guard status == noErr else { throw AudioOutputError("\(message) (CoreAudio \(status))") }
    }
}

private struct AudioOutputError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
