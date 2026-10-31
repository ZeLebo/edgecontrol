import CoreGraphics
import Darwin
import Foundation

@MainActor
final class BrightnessOutput {
    var onChange: (() -> Void)?

    private var api: DisplayServicesAPI?
    private var observation: DisplayChangeObservation?
    private var display: CGDirectDisplayID?
    private var displayGeneration: UInt64 = 0

    /// The observer survives an unavailable display so a later configuration can recover.
    func start() throws {
        if observation == nil {
            let observation = DisplayChangeObservation { [weak self] observation in
                guard let self, self.observation === observation else { return }
                self.display = nil
                self.onChange?()
            }
            DisplayChangeRegistry.shared.install(observation)
            let status = CGDisplayRegisterReconfigurationCallback(displayChanged, observation.context)
            guard status == .success else {
                DisplayChangeRegistry.shared.remove(observation)
                throw BrightnessOutputError("Could not observe display changes (CoreGraphics \(status.rawValue))")
            }
            self.observation = observation
        }
        try refresh()
    }

    func refresh() throws {
        display = nil
        guard let observation else { throw BrightnessOutputError("Display observation has not started") }
        let api = try self.api ?? DisplayServicesAPI()
        self.api = api
        let generation = observation.generation
        let selected = try currentBuiltInDisplay()
        _ = try readScalar(from: selected, using: api)
        guard observation.generation == generation, try currentBuiltInDisplay() == selected else {
            throw BrightnessOutputError("The built-in display changed")
        }
        displayGeneration = generation
        display = selected
    }

    func setBrightness(percent: Int) throws {
        guard (0...100).contains(percent) else { throw BrightnessOutputError("Invalid brightness") }
        let (display, api) = try requireCurrentDisplay()
        let status = api.set(display, Float(percent) / 100)
        guard status == 0 else {
            throw BrightnessOutputError("Could not set brightness (DisplayServices \(status))")
        }
    }

    func readBrightnessPercent() throws -> Int {
        let (display, api) = try requireCurrentDisplay()
        let scalar = try readScalar(from: display, using: api)
        _ = try requireCurrentDisplay()
        return Int((scalar * 100).rounded())
    }

    func stop() {
        display = nil
        if let observation {
            DisplayChangeRegistry.shared.remove(observation)
            let status = CGDisplayRemoveReconfigurationCallback(displayChanged, observation.context)
            if status != .success {
                NSLog("EdgeControl: CGDisplayRemoveReconfigurationCallback: %d", status.rawValue)
            }
        }
        observation = nil
    }

    isolated deinit { stop() }

    private func requireCurrentDisplay() throws -> (CGDirectDisplayID, DisplayServicesAPI) {
        guard let display, let api, let observation else {
            throw BrightnessOutputError("The built-in display is not ready")
        }
        do {
            guard observation.generation == displayGeneration,
                  try currentBuiltInDisplay() == display,
                  observation.generation == displayGeneration else {
                throw BrightnessOutputError("The built-in display changed")
            }
        } catch {
            self.display = nil
            onChange?()
            throw error
        }
        return (display, api)
    }

    private func currentBuiltInDisplay() throws -> CGDirectDisplayID {
        var count: UInt32 = 0
        var status = CGGetOnlineDisplayList(0, nil, &count)
        guard status == .success else {
            throw BrightnessOutputError("Could not list displays (CoreGraphics \(status.rawValue))")
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        status = CGGetOnlineDisplayList(count, &displays, &count)
        guard status == .success, count <= displays.count else {
            throw BrightnessOutputError("Could not read displays (CoreGraphics \(status.rawValue))")
        }
        return try builtInDisplayID(in: displays.prefix(Int(count)).map {
            (id: $0, isBuiltIn: CGDisplayIsBuiltin($0) != 0, isActive: CGDisplayIsActive($0) != 0)
        })
    }

    private func readScalar(from display: CGDirectDisplayID, using api: DisplayServicesAPI) throws -> Float {
        var scalar: Float = .nan
        let status = api.get(display, &scalar)
        guard status == 0 else {
            throw BrightnessOutputError("Could not read brightness (DisplayServices \(status))")
        }
        guard scalar.isFinite, (0...1).contains(scalar) else {
            throw BrightnessOutputError("The display returned an invalid brightness")
        }
        return scalar
    }
}

func builtInDisplayID(
    in displays: [(id: CGDirectDisplayID, isBuiltIn: Bool, isActive: Bool)]
) throws -> CGDirectDisplayID {
    let candidates = displays.filter(\.isBuiltIn)
    guard candidates.count == 1, let selected = candidates.first else {
        throw BrightnessOutputError(candidates.isEmpty ? "No built-in display found" : "Multiple built-in displays found")
    }
    guard selected.isActive else { throw BrightnessOutputError("The built-in display is inactive") }
    return selected.id
}

struct BrightnessOutputError: LocalizedError, Sendable {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private let displayChanged: CGDisplayReconfigurationCallBack = { _, _, context in
    guard let context, let observation = DisplayChangeRegistry.shared.observation(for: context) else { return }
    observation.invalidate()
    DispatchQueue.main.async { observation.deliver(observation) }
}

private final class DisplayChangeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    let deliver: @MainActor @Sendable (DisplayChangeObservation) -> Void

    init(deliver: @escaping @MainActor @Sendable (DisplayChangeObservation) -> Void) { self.deliver = deliver }
    var context: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    var generation: UInt64 { lock.withLock { value } }
    func invalidate() { lock.withLock { value &+= 1 } }
}

// Look up callback contexts without dereferencing them after an observer is removed.
private final class DisplayChangeRegistry: @unchecked Sendable {
    static let shared = DisplayChangeRegistry()
    private let lock = NSLock()
    private var observations: [UInt: DisplayChangeObservation] = [:]

    func install(_ observation: DisplayChangeObservation) {
        lock.withLock { observations[UInt(bitPattern: observation.context)] = observation }
    }

    func remove(_ observation: DisplayChangeObservation) {
        _ = lock.withLock { observations.removeValue(forKey: UInt(bitPattern: observation.context)) }
    }

    func observation(for context: UnsafeMutableRawPointer) -> DisplayChangeObservation? {
        lock.withLock { observations[UInt(bitPattern: context)] }
    }
}

// shortcut: this private ABI must be rechecked after incompatible macOS updates.
// Signatures: https://github.com/nriley/brightness/blob/master/brightness.c
private final class DisplayServicesAPI {
    typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let library: UnsafeMutableRawPointer
    let get: Get
    let set: Set

    init() throws {
        let path = try systemPrivateFrameworkPath("DisplayServices")
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
            throw BrightnessOutputError("DisplayServices is unavailable: \(detail)")
        }
        self.library = library
        do {
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let pointer = dlsym(library, name) else {
                    throw BrightnessOutputError("DisplayServices: missing \(name)")
                }
                return unsafeBitCast(pointer, to: T.self)
            }
            get = try symbol("DisplayServicesGetBrightness", Get.self)
            set = try symbol("DisplayServicesSetBrightness", Set.self)
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit { dlclose(library) }
}
