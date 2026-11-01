import Darwin
import Foundation
import ObjectiveC

struct KeyboardBacklightDevice: Equatable, Sendable {
    let id: UInt64
    let isBuiltIn: Bool
}

@MainActor
protocol KeyboardBacklightTransport: AnyObject {
    func devices() throws -> [KeyboardBacklightDevice]
    func readBrightness(deviceID: UInt64) throws -> Float32
    func setBrightness(_ scalar: Float32, deviceID: UInt64) throws
    func stop()
}

@MainActor
final class KeyboardBacklight {
    private let transport: any KeyboardBacklightTransport
    private var keyboardID: UInt64?
    private var restoreDeviceID: UInt64?
    private var lastNonzeroPercent: Int?

    init(transport: (any KeyboardBacklightTransport)? = nil) {
        self.transport = transport ?? CoreBrightnessKeyboardTransport()
    }

    func start() throws { try refresh() }

    func refresh() throws {
        keyboardID = nil
        let selected = try builtInKeyboardID(in: transport.devices())
        if restoreDeviceID != selected {
            restoreDeviceID = selected
            lastNonzeroPercent = nil
        }
        keyboardID = selected
        do { _ = try readBrightnessPercent() }
        catch { keyboardID = nil; throw error }
    }

    func readBrightnessPercent() throws -> Int {
        let id = try currentKeyboardID()
        let scalar = try transport.readBrightness(deviceID: id)
        guard scalar.isFinite, (0...1).contains(scalar) else { throw KeyboardBacklightError.invalidReading }
        _ = try currentKeyboardID()
        let percent = Int((scalar * 100).rounded())
        if percent > 0 { lastNonzeroPercent = percent }
        return percent
    }

    func setBrightness(percent: Int) throws {
        guard (0...100).contains(percent) else { throw KeyboardBacklightError.invalidLevel }
        let id = try currentKeyboardID()
        try transport.setBrightness(Float32(percent) / 100, deviceID: id)
        _ = try currentKeyboardID()
        if percent > 0 { lastNonzeroPercent = percent }
    }

    @discardableResult
    func toggle() throws -> Bool {
        let current = try readBrightnessPercent()
        // A fresh session that first observes an off backlight has no previous
        // nonzero level to restore. In that one case, Toggle On chooses 50%.
        let target = current > 0 ? 0 : (lastNonzeroPercent ?? 50)
        try setBrightness(percent: target)
        return target > 0
    }

    func stop() {
        keyboardID = nil
        transport.stop()
        // Keep only the last known level/ID across pause and wake, not a client.
    }

    isolated deinit { stop() }

    private func currentKeyboardID() throws -> UInt64 {
        guard let keyboardID else { throw KeyboardBacklightError.notStarted }
        do {
            guard try builtInKeyboardID(in: transport.devices()) == keyboardID else {
                throw KeyboardBacklightError.deviceChanged
            }
        } catch {
            self.keyboardID = nil
            throw error
        }
        return keyboardID
    }
}

private func builtInKeyboardID(in devices: [KeyboardBacklightDevice]) throws -> UInt64 {
    let builtIn = devices.filter(\.isBuiltIn)
    guard builtIn.count == 1, let selected = builtIn.first else {
        throw KeyboardBacklightError.unavailable(builtIn.isEmpty
            ? "No built-in keyboard backlight found" : "Multiple built-in keyboard backlights found")
    }
    return selected.id
}

enum KeyboardBacklightError: LocalizedError {
    case unavailable(String)
    case notStarted
    case invalidLevel
    case invalidReading
    case deviceChanged
    case writeRejected

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .notStarted: "The keyboard backlight is not ready"
        case .invalidLevel: "Keyboard backlight level must be between 0 and 100"
        case .invalidReading: "The keyboard returned an invalid backlight level"
        case .deviceChanged: "The built-in keyboard backlight changed"
        case .writeRejected: "macOS refused to change the keyboard backlight"
        }
    }
}

@MainActor
private final class CoreBrightnessKeyboardTransport: KeyboardBacklightTransport {
    private var library: UnsafeMutableRawPointer?
    private var bridge: KeyboardBrightnessBridge?

    func devices() throws -> [KeyboardBacklightDevice] { try client().devices() }
    func readBrightness(deviceID: UInt64) throws -> Float32 { try client().readBrightness(deviceID: deviceID) }
    func setBrightness(_ scalar: Float32, deviceID: UInt64) throws {
        try client().setBrightness(scalar, deviceID: deviceID)
    }
    func stop() { bridge = nil }
    isolated deinit { stop() }

    private func client() throws -> KeyboardBrightnessBridge {
        if let bridge { return bridge }
        if library == nil {
            let path = try systemPrivateFrameworkPath("CoreBrightness")
            guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                throw KeyboardBacklightError.unavailable("CoreBrightness is unavailable")
            }
            self.library = library
            // Its Objective-C classes stay registered. Keep the image mapped
            // for the process lifetime; stop releases our client instance.
        }
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            throw KeyboardBacklightError.unavailable("CoreBrightness: KeyboardBrightnessClient is unavailable")
        }
        let value = try KeyboardBrightnessBridge(client: type.init())
        bridge = value
        return value
    }
}

// Primary declarations and implementation:
// https://github.com/rakalex/mac-brightnessctl/blob/master/KeyboardBrightnessClient.h
// https://macos.readthedocs.io/en/v1.25.0/_modules/macos/keyboard.html
// Float32 arguments/returns use floating-point registers, not integer bit casts.
@MainActor
private final class KeyboardBrightnessBridge {
    typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    typealias BuiltIn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float32
    typealias Write = @convention(c) (AnyObject, Selector, Float32, Int32, Bool, UInt64) -> Bool

    private let client: NSObject
    private let copyIDs: CopyIDs
    private let builtIn: BuiltIn
    private let read: Read
    private let write: Write
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
    private static let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
    private static let readSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let writeSelector = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")

    init(client: NSObject) throws {
        self.client = client
        func bind<T>(_ selector: Selector, signature: String, _: T.Type) throws -> T {
            guard let method = class_getInstanceMethod(type(of: client), selector),
                  let encoding = method_getTypeEncoding(method) else {
                throw KeyboardBacklightError.unavailable("CoreBrightness: missing \(NSStringFromSelector(selector))")
            }
            let actual = String(cString: encoding).filter { !$0.isNumber }
            guard actual == signature else {
                throw KeyboardBacklightError.unavailable("CoreBrightness: incompatible \(NSStringFromSelector(selector)) signature")
            }
            return unsafeBitCast(method_getImplementation(method), to: T.self)
        }
        copyIDs = try bind(Self.idsSelector, signature: "@@:", CopyIDs.self)
        builtIn = try bind(Self.builtInSelector, signature: "B@:Q", BuiltIn.self)
        read = try bind(Self.readSelector, signature: "f@:Q", Read.self)
        write = try bind(Self.writeSelector, signature: "B@:fiBQ", Write.self)
    }

    func devices() throws -> [KeyboardBacklightDevice] {
        guard let found = copyIDs(client, Self.idsSelector)?.takeRetainedValue(),
              let values = found as? [NSNumber] else {
            throw KeyboardBacklightError.unavailable("CoreBrightness could not enumerate keyboard backlights")
        }
        return try values.map { value in
            guard let id = UInt64(value.stringValue) else {
                throw KeyboardBacklightError.unavailable("CoreBrightness returned an invalid keyboard identifier")
            }
            return KeyboardBacklightDevice(id: id, isBuiltIn: builtIn(client, Self.builtInSelector, id))
        }
    }

    func readBrightness(deviceID: UInt64) -> Float32 { read(client, Self.readSelector, deviceID) }

    func setBrightness(_ scalar: Float32, deviceID: UInt64) throws {
        // Commit the requested level immediately. Automatic brightness and idle
        // dimming keep their existing settings and can adjust it afterwards.
        guard write(client, Self.writeSelector, scalar, 0, true, deviceID) else {
            throw KeyboardBacklightError.writeRejected
        }
    }
}
